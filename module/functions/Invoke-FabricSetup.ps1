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
          5. Provisions Workspace Identity (if enabled)
          6. Enables workspace monitoring (if enabled)
          7. Provisions a Spark Environment and (optionally) sets it as workspace default (if enabled
             for the type and the current environment is in the type's configured stages)
          8. Applies RBAC role assignments (if configured)
        Then, for each workspace type with pipelines enabled:
          8. Creates or updates the deployment pipeline across all environments
          9. Applies deployment pipeline role assignments (if configured)
        Returns a structured results object with a summary, identity report, monitoring report,
        role assignment report, pipeline report, and pipeline role assignment report.
    .PARAMETER Config
        Topology config object produced by New-FabricTopologyConfig.
    .PARAMETER ConfigPath
        Path to a JSON file containing the topology config (alternative to -Config).
    .PARAMETER Environments
        Subset of environment names to process. Defaults to all environments in config.
    .PARAMETER SkipGit
        Skip Git integration for all workspaces.
    .PARAMETER SkipIdentity
        Skip identity provisioning for all workspaces.
    .PARAMETER SkipMonitoring
        Skip monitoring enablement for all workspaces.
    .PARAMETER SkipEnvironment
        Skip Spark Environment provisioning for all workspaces.
    .PARAMETER SkipRbac
        Skip role assignment application for all workspaces.
    .PARAMETER SkipPipeline
        Skip deployment pipeline setup for all workspace types.
    .PARAMETER SkipPipelineRbac
        Skip deployment pipeline role assignment application for all workspace types.
    .EXAMPLE
        Invoke-FabricSetup -Config $topology -Environments @("Dev") -WhatIf

        Runs the provisioning pipeline for the Dev environment in WhatIf mode.
    .EXAMPLE
        Invoke-FabricSetup -ConfigPath "./topology.json" -SkipGit

        Runs the full provisioning pipeline from a saved topology config, skipping Git integration.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object', SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object', Position = 0)]
        [pscustomobject]$Config,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$ConfigPath,

        [string[]]$Environments,

        [switch]$SkipGit,
        [switch]$SkipIdentity,
        [switch]$SkipMonitoring,
        [switch]$SkipEnvironment,
        [switch]$SkipRbac,
        [switch]$SkipPipeline,
        [switch]$SkipPipelineRbac
    )

    $ErrorActionPreference = 'Stop'

    # --- 1. Load config ---
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
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
    $targetEnvs = if ($Environments) {
        $Config.environments | Where-Object { $_.name -in $Environments }
    }
    else {
        $Config.environments
    }

    if (-not $targetEnvs) {
        throw "No matching environments found in config for filter: $($Environments -join ', ')"
    }

    # --- 4. Provision ---
    $results = [pscustomobject]@{
        Summary         = [pscustomobject]@{ Created = 0; Skipped = 0; Failed = 0 }
        Identities      = [System.Collections.Generic.List[hashtable]]::new()
        Monitoring      = [System.Collections.Generic.List[hashtable]]::new()
        Environments    = [System.Collections.Generic.List[hashtable]]::new()
        RoleAssignments = [System.Collections.Generic.List[hashtable]]::new()
        Pipelines       = [System.Collections.Generic.List[hashtable]]::new()
        PipelineRoleAssignments = [System.Collections.Generic.List[hashtable]]::new()
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

                    if ($wsEnvironment.setAsWorkspaceDefault) {
                        $defaultResult = Set-FabricWorkspaceDefaultEnvironment `
                            -WorkspaceId     $workspaceId `
                            -WorkspaceName   $resolvedName `
                            -EnvironmentName $envName `
                            -RuntimeVersion  $wsEnvironment.runtimeVersion `
                            -Token           $token
                        $results.Environments.Add($defaultResult)
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

            # g. Role Assignments — non-fatal, log and continue
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

    # --- 5. Deployment Pipelines (per workspace type, spans all environments) ---
    if (-not $SkipPipeline) {
        $pipelineWorkspaces = $Config.workspaces | Where-Object { $_.pipeline.enabled }

        foreach ($ws in $pipelineWorkspaces) {
            try {
                $pipelineResult = Set-FabricDeploymentPipeline `
                    -Config        $Config `
                    -WorkspaceType $ws.type `
                    -Token         $token
                $results.Pipelines.Add($pipelineResult)
            }
            catch {
                Write-Warning "Deployment pipeline setup failed for '$($ws.type)' — $_"
                $results.Failures.Add(@{
                    WorkspaceName = "$($ws.type) pipeline"
                    Environment   = 'all'
                    Step          = 'Pipeline'
                    Error         = $_.ToString()
                })
                continue
            }

            # Pipeline Role Assignments — non-fatal, log and continue
            if (-not $SkipPipelineRbac) {
                $pipelineRbac = $ws.pipeline.roleAssignments
                if ($pipelineRbac -and $pipelineRbac.Count -gt 0) {
                    foreach ($entry in $pipelineRbac) {
                        try {
                            $rbacResult = Set-FabricDeploymentPipelineRoleAssignment `
                                -PipelineId    $pipelineResult.PipelineId `
                                -PipelineName  $pipelineResult.PipelineName `
                                -PrincipalId   $entry.principalId `
                                -PrincipalType $entry.principalType `
                                -Role          $entry.role `
                                -Token         $token
                            $results.PipelineRoleAssignments.Add($rbacResult)
                        }
                        catch {
                            Write-Warning "Pipeline role assignment failed for '$($pipelineResult.PipelineName)' (principal: $($entry.principalId)) — $_"
                            $results.Failures.Add(@{
                                WorkspaceName = "$($ws.type) pipeline"
                                Environment   = 'all'
                                Step          = 'PipelineRoleAssignment'
                                Error         = $_.ToString()
                            })
                        }
                    }
                }
            }
        }
    }

    # --- 6. Report ---
    $s = $results.Summary
    Write-Verbose "=== Provisioning complete — Created: $($s.Created)  Skipped: $($s.Skipped)  Failed: $($s.Failed) ==="

    if ($results.Failures.Count -gt 0) {
        Write-Warning "$($results.Failures.Count) workspace(s) failed. See `$result.Failures for details."
    }

    return $results
}
