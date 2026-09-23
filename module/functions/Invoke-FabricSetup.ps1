function Invoke-FabricSetup {
    <#
    .SYNOPSIS
        Orchestrates the full Fabric workspace provisioning pipeline from a topology config.
    .DESCRIPTION
        For each environment x workspace combination in the config:
          1. Resolves the workspace name via naming convention
          2. Creates the workspace (idempotent)
          3. Grants the deploying identity Admin on the workspace (so re-runs can resolve it)
          4. Connects to Git (idempotent)
          5. Provisions Workspace Identity and grants it Contributor on the workspace (if enabled)
          6. Enables workspace monitoring (if enabled)
          7. Provisions a Spark Environment and (optionally) sets it as workspace default (if enabled
             for the type and the current environment is in the type's configured stages)
          8. Provisions a Variable Library (if enabled for the type and the current environment is in the
             type's configured stages) and, if default values are enabled, populates the default variables
             in a value set for the current stage and activates it
          9. Applies RBAC role assignments (if configured)
        Returns a structured results object with a summary; a per-workspace model (a flat
        'Workspaces' list and a nested 'WorkspacesByType.<type>.<environment>' index, each record
        carrying the workspace id, identity principal/application ids, Spark environment id and
        status); and the identity report, monitoring report, environment report, variable library report,
	role assignment report, and failure details.
        Deployment pipelines span every environment, so they are not configured here: run
        Invoke-FabricDeploymentPipelineSetup once each environment's workspaces have been provisioned.
    .PARAMETER Config
        Topology config object produced by New-FabricTopologyConfig.
    .PARAMETER ConfigPath
        Path to a JSON file containing the topology config (alternative to -Config).
    .PARAMETER Environment
        Single environment name to process. Defaults to all environments in config.
    .PARAMETER SkipGit
        Skip Git integration for all workspaces.
    .PARAMETER SkipIdentity
        Skip identity provisioning for all workspaces.
    .PARAMETER SkipMonitoring
        Skip monitoring enablement for all workspaces.
    .PARAMETER SkipEnvironment
        Skip Spark Environment provisioning for all workspaces.
    .PARAMETER SkipVariableLibrary
        Skip Variable Library provisioning for all workspaces.
    .PARAMETER SkipRbac
        Skip role assignment application for all workspaces.
    .EXAMPLE
        Invoke-FabricSetup -Config $topology -Environment "Dev" -WhatIf

        Runs the provisioning pipeline for the Dev environment in WhatIf mode.
    .EXAMPLE
        Invoke-FabricSetup -ConfigPath "./topology.json" -SkipGit

        Runs the full provisioning pipeline from a saved topology config, skipping Git integration.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object', SupportsShouldProcess,
        HelpUri = 'https://learn.microsoft.com/rest/api/fabric/')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object', Position = 0)]
        [pscustomobject]$Config,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$ConfigPath,

        [string]$Environment,

        [switch]$SkipGit,
        [switch]$SkipIdentity,
        [switch]$SkipMonitoring,
        [switch]$SkipEnvironment,
        [switch]$SkipVariableLibrary,
        [switch]$SkipRbac
    )

    $ErrorActionPreference = 'Stop'

    # --- 1. Load config ---
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -Depth 20
    }

    # --- 2. Acquire auth token ---
    Write-Verbose 'Acquiring Fabric auth token...'
    $tokenInfo = _Get-FabricAuthToken
    $token     = $tokenInfo.Token

    # Initialise MicrosoftFabricMgmt module session by injecting our already-acquired token.
    # Set-FabricApiHeaders always triggers a fresh interactive login, so we bypass it and
    # set the module's internal auth context directly using the token from _Get-FabricAuthToken.
    # Import and resolve a single module instance explicitly to avoid invalid '&' invocation.
    # Import with -Global: MicrosoftFabricMgmt also exports a 'New-FabricWorkspace', and importing
    # into this module's session state would shadow our own function. Keeping its commands in the
    # global session state lets our module-local New-FabricWorkspace win by module-scope precedence.
    Import-Module MicrosoftFabricMgmt -Global -ErrorAction Stop
    $tenantId         = (Get-AzContext -ErrorAction Stop).Tenant.Id
    $fabricMgmtModules = Get-Module MicrosoftFabricMgmt -All
    if (-not $fabricMgmtModules) {
        throw "MicrosoftFabricMgmt is not loaded. Ensure the module is installed and importable."
    }
    $fabricMgmtModule = $fabricMgmtModules | Sort-Object Version -Descending | Select-Object -First 1
    & $fabricMgmtModule {
        param($tok, $exp, $tid)
        $script:FabricAuthContext.FabricHeaders = @{
            'Content-Type'  = 'application/json; charset=utf-8'
            'Authorization' = "Bearer $tok"
        }
        $script:FabricAuthContext.TokenExpiresOn = $exp.ToString('o')
        $script:FabricAuthContext.TenantId       = $tid
        $script:FabricAuthContext.AuthMethod     = 'UserPrincipal'
    } $token $tokenInfo.ExpiresOn $tenantId

    # --- 2b. Resolve the deploying identity (object id + type). ---
    # Each workspace is granted this principal as Admin on creation so the deployer can always
    # see and re-manage it on subsequent runs (otherwise a re-run hits WorkspaceNameAlreadyExists
    # but cannot resolve the workspace via GET /workspaces). Best-effort: warn and continue.
    $deployerPrincipal = _Get-FabricDeploymentIdentity
    if ($deployerPrincipal) {
        Write-Verbose "Deploying identity resolved: $($deployerPrincipal.Id) ($($deployerPrincipal.Type)). Will be granted Admin on each workspace."
    }
    else {
        Write-Warning "Could not determine the deploying identity; workspaces will not be auto-granted Admin for the deployer."
    }

    # --- 3. Determine environments to process ---
    $targetEnvs = if ($Environment) {
        $Config.environments | Where-Object { $_.name -eq $Environment }
    }
    else {
        $Config.environments
    }

    if (-not $targetEnvs) {
        throw "Environment '$Environment' not found in config. Available: $(($Config.environments.name) -join ', ')."
    }

    # --- 4. Provision ---
    $results = [pscustomobject]@{
        Summary         = [pscustomobject]@{ Created = 0; Skipped = 0; Failed = 0 }
        Workspaces      = [System.Collections.Generic.List[pscustomobject]]::new()
        WorkspacesByType = [ordered]@{}
        Identities      = [System.Collections.Generic.List[hashtable]]::new()
        Monitoring      = [System.Collections.Generic.List[hashtable]]::new()
        Environments    = [System.Collections.Generic.List[hashtable]]::new()
        VariableLibraries = [System.Collections.Generic.List[hashtable]]::new()
        RoleAssignments = [System.Collections.Generic.List[hashtable]]::new()
        Failures        = [System.Collections.Generic.List[hashtable]]::new()
    }

    foreach ($env in $targetEnvs) {
        Write-Verbose "=== Environment: $($env.name) ==="

        foreach ($ws in $Config.workspaces) {

            # Refresh token if near expiry
            if (_Test-FabricTokenExpiry -TokenInfo $tokenInfo) {
                Write-Verbose 'Token nearing expiry — refreshing...'
                $tokenInfo = _Get-FabricAuthToken
                $token     = $tokenInfo.Token
                & $fabricMgmtModule {
                    param($tok, $exp, $tid)
                    $script:FabricAuthContext.FabricHeaders = @{
                        'Content-Type'  = 'application/json; charset=utf-8'
                        'Authorization' = "Bearer $tok"
                    }
                    $script:FabricAuthContext.TokenExpiresOn = $exp.ToString('o')
                    $script:FabricAuthContext.TenantId       = $tid
                    $script:FabricAuthContext.AuthMethod     = 'UserPrincipal'
                } $token $tokenInfo.ExpiresOn $tenantId
            }

            # a. Resolve workspace name
            $resolvedName = _Resolve-WorkspaceName -Config $Config -WorkspaceId $ws.id -EnvironmentName $env.name
            Write-Verbose "Processing: $resolvedName"

            # Addressable record for this workspace type x environment. Added before anything can fail,
            # so a creation failure still leaves a record (with a null WorkspaceId) in $results.Workspaces.
            # Enriched in place as the identity / Spark environment steps complete below. The schema
            # lives in _New-FabricWorkspaceRecord so it stays identical to Get-FabricTopologyState's.
            $wsRecord = _New-FabricWorkspaceRecord `
                -Type         $ws.type `
                -Environment  $env.name `
                -Name         $resolvedName `
                -CapacityName $env.capacityName
            $results.Workspaces.Add($wsRecord)

            # b. Create workspace (idempotent) — fatal for this workspace if it fails
            try {
                $existed = Test-FabricWorkspaceExists -DisplayName $resolvedName -Token $token
                if ($existed) {
                    $workspaceObj = $existed
                    $results.Summary.Skipped++
                }
                else {
                    # Bare call resolves to our module-local New-FabricWorkspace (module-scope
                    # precedence over the global MicrosoftFabricMgmt one imported above). A
                    # module-qualified call here fails under Azure DevOps with a spurious
                    # "module could not be loaded" auto-load error.
                    $workspaceObj = New-FabricWorkspace `
                        -DisplayName  $resolvedName `
                        -CapacityName $env.capacityName `
                        -Token        $token
                    if (-not $WhatIfPreference) {
                        $results.Summary.Created++
                    }
                }
            }
            catch {
                Write-Error "FAILED: $resolvedName — $_" -ErrorAction Continue
                $wsRecord.Status = 'Failed'
                $results.Failures.Add(@{
                    WorkspaceName = $resolvedName
                    Environment   = $env.name
                    Step          = 'Workspace'
                    Error         = $_.ToString()
                })
                $results.Summary.Failed++
                continue
            }

            $workspaceId = $workspaceObj.id

            $wsRecord.WorkspaceId = $workspaceId
            $wsRecord.Status      = if ($existed) { 'Existing' }
                                    elseif ($WhatIfPreference) { 'WhatIf' }
                                    else { 'Created' }

            # b2. Grant the deploying identity Admin on the workspace (idempotent, non-fatal).
            # Guarantees the deployer can resolve the workspace on future runs. Independent of
            # -SkipRbac, which governs only the topology's configured role assignments.
            if ($deployerPrincipal) {
                try {
                    $deployerRbac = Set-FabricWorkspaceRoleAssignment `
                        -WorkspaceId   $workspaceId `
                        -WorkspaceName $resolvedName `
                        -PrincipalId   $deployerPrincipal.Id `
                        -PrincipalType $deployerPrincipal.Type `
                        -Role          'Admin' `
                        -Token         $token
                    $results.RoleAssignments.Add($deployerRbac)
                }
                catch {
                    Write-Warning "Failed to grant the deploying identity Admin on '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'DeployerRoleAssignment'
                        Error         = $_.ToString()
                    })
                }
            }

            # c. Git integration — only for the designated git environment, non-fatal
            if (-not $SkipGit -and $ws.git.enabled -and $Config.gitEnvironment -and $env.name -eq $Config.gitEnvironment) {
                try {
                    Set-FabricGitIntegration `
                        -WorkspaceId   $workspaceId `
                        -WorkspaceName $resolvedName `
                        -GitConfig     $ws.git `
                        -Branch        $ws.git.branch `
                        -Token         $token
                    $wsRecord.GitConnected = $true
                }
                catch {
                    Write-Warning "Git integration failed for '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'Git'
                        Error         = $_.ToString()
                    })
                }
            }

            # d. Workspace Identity — non-fatal, log and continue
            if (-not $SkipIdentity -and $ws.identity.enabled) {
                try {
                    $identityEntry = Enable-FabricWorkspaceIdentity `
                        -WorkspaceId   $workspaceId `
                        -WorkspaceName $resolvedName `
                        -Token         $token
                    if ($identityEntry) {
                        $results.Identities.Add($identityEntry)
                        $wsRecord.Identity = [pscustomobject]@{
                            PrincipalId   = $identityEntry.ServicePrincipalObjectId
                            ApplicationId = $identityEntry.ApplicationId
                        }

                        # Grant the workspace identity Contributor on its own workspace, so that
                        # Fabric shortcuts using the identity can authenticate outbound requests.
                        try {
                            $identityRbac = Set-FabricWorkspaceRoleAssignment `
                                -WorkspaceId   $workspaceId `
                                -WorkspaceName $resolvedName `
                                -PrincipalId   $identityEntry.ServicePrincipalObjectId `
                                -PrincipalType 'ServicePrincipal' `
                                -Role          'Contributor' `
                                -Token         $token
                            $results.RoleAssignments.Add($identityRbac)
                        }
                        catch {
                            Write-Warning "Failed to grant the workspace identity Contributor on '$resolvedName' — $_"
                            $results.Failures.Add(@{
                                WorkspaceName = $resolvedName
                                Environment   = $env.name
                                Step          = 'IdentityRoleAssignment'
                                Error         = $_.ToString()
                            })
                        }
                    }
                }
                catch {
                    Write-Warning "Identity provisioning failed for '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'Identity'
                        Error         = $_.ToString()
                    })
                }
            }

            # e. Workspace Monitoring — non-fatal, log and continue
            if (-not $SkipMonitoring -and $ws.monitoring.enabled) {
                try {
                    $monitoringEntry = Enable-FabricWorkspaceMonitoring `
                        -WorkspaceId   $workspaceId `
                        -WorkspaceName $resolvedName `
                        -Token         $token
                    $results.Monitoring.Add($monitoringEntry)
                }
                catch {
                    Write-Warning "Monitoring enablement failed for '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'Monitoring'
                        Error         = $_.ToString()
                    })
                }
            }

            # f. Spark Environment — non-fatal, log and continue.
            # Scoped to the environments (stages) configured for this workspace type. A config
            # without a 'stages' list (older config) applies to every environment — previous behaviour.
            $wsEnvironment = if ($ws.PSObject.Properties.Name -contains 'environment') { $ws.environment } else { $null }
            $envInStage = $wsEnvironment -and (
                -not ($wsEnvironment.PSObject.Properties.Name -contains 'stages') -or
                -not $wsEnvironment.stages -or
                $env.name -in @($wsEnvironment.stages)
            )
            if (-not $SkipEnvironment -and $wsEnvironment -and $wsEnvironment.enabled -and $envInStage) {
                try {
                    # Resolve the environment display name from the naming convention template.
                    $envName = _Resolve-EnvironmentName -Config $Config -WorkspaceId $ws.id -EnvironmentName $env.name

                    $environmentObj = New-FabricEnvironment `
                        -WorkspaceId $workspaceId `
                        -DisplayName $envName `
                        -Token       $token
                    $results.Environments.Add(@{
                        WorkspaceName   = $resolvedName
                        WorkspaceId     = $workspaceId
                        EnvironmentName = $envName
                        EnvironmentId   = $environmentObj.id
                    })
                    $wsRecord.SparkEnvironment = [pscustomobject]@{
                        Name               = $envName
                        Id                 = $environmentObj.id
                        IsWorkspaceDefault = $false
                    }

                    if ($wsEnvironment.setAsWorkspaceDefault) {
                        $defaultResult = Set-FabricWorkspaceDefaultEnvironment `
                            -WorkspaceId     $workspaceId `
                            -WorkspaceName   $resolvedName `
                            -EnvironmentName $envName `
                            -RuntimeVersion  $wsEnvironment.runtimeVersion `
                            -Token           $token
                        $results.Environments.Add($defaultResult)
                        # 'Set' = applied this run; 'Skipped' = already the default; 'whatif' = simulated.
                        $wsRecord.SparkEnvironment.IsWorkspaceDefault = ($defaultResult.Action -in @('Set', 'Skipped'))
                    }
                }
                catch {
                    Write-Warning "Environment provisioning failed for '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'Environment'
                        Error         = $_.ToString()
                    })
                }
            }

            # g. Variable Library — non-fatal, log and continue.
            # The name is the same in every environment. Scoped to the environments (stages) configured
            # for this workspace type; a block without 'stages' applies to every environment. A config
            # without a 'variableLibrary' block (older config) provisions none; a block without a name
            # uses the default name. An existing library is never recreated. Without 'defaultValues' it
            # is left untouched; with it, only the default variables and this stage's value set change.
            $wsVariableLibrary = if ($ws.PSObject.Properties.Name -contains 'variableLibrary') { $ws.variableLibrary } else { $null }
            $libraryInStage = $wsVariableLibrary -and (
                -not ($wsVariableLibrary.PSObject.Properties.Name -contains 'stages') -or
                -not $wsVariableLibrary.stages -or
                $env.name -in @($wsVariableLibrary.stages)
            )
            if (-not $SkipVariableLibrary -and $wsVariableLibrary -and $wsVariableLibrary.enabled -and $libraryInStage) {
                try {
                    $configuredName = if ($wsVariableLibrary.PSObject.Properties.Name -contains 'name') { $wsVariableLibrary.name } else { $null }
                    $libraryName = _Resolve-VariableLibraryName -Name $configuredName

                    $libraryObj = New-FabricVariableLibrary `
                        -WorkspaceId $workspaceId `
                        -DisplayName $libraryName `
                        -Token       $token
                    $libraryEntry = @{
                        WorkspaceName       = $resolvedName
                        WorkspaceId         = $workspaceId
                        VariableLibraryName = $libraryName
                        VariableLibraryId   = $libraryObj.id
                        DefaultValues       = $null
                    }
                    $results.VariableLibraries.Add($libraryEntry)

                    # g2. Default variables — populate this stage's value set from the deployment and
                    # activate it. The default value set only ever holds a placeholder. Non-fatal: the
                    # library itself has been provisioned.
                    $defaultValuesEnabled = $wsVariableLibrary.PSObject.Properties.Name -contains 'defaultValues' -and $wsVariableLibrary.defaultValues
                    if ($defaultValuesEnabled) {
                        try {
                            # Prefer this run's identity report; otherwise read the identity off the
                            # workspace (e.g. with -SkipIdentity). Not looked up under -WhatIf.
                            $identity = $results.Identities | Where-Object { $_.WorkspaceId -eq $workspaceId } | Select-Object -Last 1
                            if (-not $identity -and -not $WhatIfPreference) {
                                $identity = _Get-FabricWorkspaceIdentity -WorkspaceId $workspaceId -Token $token
                            }

                            # The workspace identity's Entra name is the workspace name.
                            $values = [ordered]@{
                                workspace_name          = $resolvedName
                                workspace_id            = $workspaceId
                                workspace_identity_name = if ($identity) { $resolvedName } else { '' }
                                workspace_identity_id   = if ($identity) { $identity.ApplicationId } else { '' }
                            }

                            # Value sets are named by stage short code (e.g. DEV), falling back to the
                            # environment name for configs without short codes.
                            $valueSetName = if ($env.PSObject.Properties.Name -contains 'shortCode' -and $env.shortCode) { $env.shortCode } else { $env.name }

                            $libraryEntry.DefaultValues = Set-FabricVariableLibraryValues `
                                -WorkspaceId         $workspaceId `
                                -WorkspaceName       $resolvedName `
                                -VariableLibraryId   $libraryObj.id `
                                -VariableLibraryName $libraryName `
                                -ValueSetName        $valueSetName `
                                -Values              $values `
                                -Token               $token
                        }
                        catch {
                            Write-Warning "Variable library default values failed for '$resolvedName' — $_"
                            $results.Failures.Add(@{
                                WorkspaceName = $resolvedName
                                Environment   = $env.name
                                Step          = 'VariableLibraryValues'
                                Error         = $_.ToString()
                            })
                        }
                    }
                }
                catch {
                    Write-Warning "Variable library provisioning failed for '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'VariableLibrary'
                        Error         = $_.ToString()
                    })
                }
            }

            # h. Role Assignments — non-fatal, log and continue
            if (-not $SkipRbac) {
                $rbacEntries = $ws.rbac.$($env.name)
                if ($rbacEntries -and $rbacEntries.Count -gt 0) {
                    foreach ($entry in $rbacEntries) {
                        try {
                            $rbacResult = Set-FabricWorkspaceRoleAssignment `
                                -WorkspaceId   $workspaceId `
                                -WorkspaceName $resolvedName `
                                -PrincipalId   $entry.principalId `
                                -PrincipalType $entry.principalType `
                                -Role          $entry.role `
                                -Token         $token
                            $results.RoleAssignments.Add($rbacResult)
                        }
                        catch {
                            Write-Warning "Role assignment failed for '$resolvedName' (principal: $($entry.principalId)) — $_"
                            $results.Failures.Add(@{
                                WorkspaceName = $resolvedName
                                Environment   = $env.name
                                Step          = 'RoleAssignment'
                                Error         = $_.ToString()
                            })
                        }
                    }
                }
            }
        }
    }

    # --- 4b. Index the workspace records by type then environment. Synthesised once from the flat
    #         list so the two views hold the same record objects and cannot drift. ---
    $results.WorkspacesByType = _ConvertTo-FabricWorkspaceIndex -Workspace $results.Workspaces

    # --- 5. Report ---
    $s = $results.Summary
    Write-Verbose "=== Provisioning complete — Created: $($s.Created)  Skipped: $($s.Skipped)  Failed: $($s.Failed) ==="

    if ($results.Failures.Count -gt 0) {
        Write-Warning "$($results.Failures.Count) workspace(s) failed. See `$result.Failures for details."
    }

    return $results
}
