function Get-FabricTopologyState {
    <#
    .SYNOPSIS
        Discovers the current state of a Fabric topology using read-only lookups, with no changes.
    .DESCRIPTION
        The read-only counterpart to Invoke-FabricSetup. It walks the same topology config but issues
        only Fabric REST GETs — it never creates or mutates a workspace, identity, Spark environment
        or deployment pipeline, never calls MicrosoftFabricMgmt, and does not resolve the deploying
        identity.

        It returns the same result-object model as Invoke-FabricSetup:
          - Workspaces        : one record per workspace type x environment (Type, Environment, Name,
                                WorkspaceId, CapacityName, Status, GitConnected, Identity,
                                SparkEnvironment). Status is 'Existing' or 'NotFound'.
          - WorkspacesByType  : the same records indexed as .<type>.<environment>.
          - Identities        : one entry per workspace whose Workspace Identity was found.
          - Environments      : one entry per resolved Spark Environment.
          - Pipelines         : one entry per pipeline-enabled workspace type, with a Stages map
                                (environment -> assigned workspace id) and Action 'Existing'/'NotFound'.
          - Failures          : non-fatal per-lookup errors.
          - Monitoring, RoleAssignments, PipelineRoleAssignments : always empty — there is no
                                non-invasive read-only equivalent.

        The Summary differs from Invoke-FabricSetup: it reports @{ Found; Missing; Failed } (workspace
        discovery counts) rather than @{ Created; Skipped; Failed }.

        Intended use: a deployment pipeline that runs separately from provisioning can call this (or
        the 'resolveFabricTopologyState' task) to populate $FabricProvisioningResult with real
        workspace / identity / environment / pipeline IDs without deploying anything.
    .PARAMETER Config
        Topology config object produced by New-FabricTopologyConfig.
    .PARAMETER ConfigPath
        Path to a JSON file containing the topology config (alternative to -Config).
    .PARAMETER Environments
        Subset of environment names to inspect. Defaults to all environments in config.
    .PARAMETER SkipGit
        Skip the per-workspace Git connection lookup (GitConfig stays $false).
    .PARAMETER SkipIdentity
        Skip the per-workspace Workspace Identity lookup (Identity stays $null).
    .PARAMETER SkipEnvironment
        Skip the per-workspace Spark Environment lookup (SparkEnvironment stays $null).
    .PARAMETER SkipPipeline
        Skip the deployment pipeline lookups (Pipelines stays empty).
    .EXAMPLE
        $state = Get-FabricTopologyState -Config $topology

        Discovers the full current state of every workspace and pipeline in the topology.
    .EXAMPLE
        $state = Get-FabricTopologyState -ConfigPath "./topology.json" -Environments @("Dev") -SkipPipeline

        Discovers only the Dev workspaces (workspace id, identity, environment, git), skipping pipelines.
    .LINK
        https://learn.microsoft.com/rest/api/fabric/
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object', Position = 0)]
        [pscustomobject]$Config,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$ConfigPath,

        [string[]]$Environments,

        [switch]$SkipGit,
        [switch]$SkipIdentity,
        [switch]$SkipEnvironment,
        [switch]$SkipPipeline
    )

    $ErrorActionPreference = 'Stop'

    # --- 1. Load config ---
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not (Test-Path $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }
        $Config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -Depth 20
    }

    # --- 2. Acquire auth token (read-only: no MicrosoftFabricMgmt, no Get-AzContext, no deploying identity) ---
    Write-Verbose 'Acquiring Fabric auth token...'
    $tokenInfo = _Get-FabricAuthToken
    $token     = $tokenInfo.Token

    # --- 3. Determine environments to inspect ---
    $targetEnvs = if ($Environments) {
        $Config.environments | Where-Object { $_.name -in $Environments }
    }
    else {
        $Config.environments
    }

    if (-not $targetEnvs) {
        throw "No matching environments found in config for filter: $($Environments -join ', ')"
    }

    # --- 4. Results ---
    $results = [pscustomobject]@{
        Summary                 = [pscustomobject]@{ Found = 0; Missing = 0; Failed = 0 }
        Workspaces              = [System.Collections.Generic.List[pscustomobject]]::new()
        WorkspacesByType        = [ordered]@{}
        Identities              = [System.Collections.Generic.List[hashtable]]::new()
        Monitoring              = [System.Collections.Generic.List[hashtable]]::new()   # always empty — no read-only equivalent
        Environments            = [System.Collections.Generic.List[hashtable]]::new()
        RoleAssignments         = [System.Collections.Generic.List[hashtable]]::new()   # always empty — not resolved read-only
        Pipelines               = [System.Collections.Generic.List[hashtable]]::new()
        PipelineRoleAssignments = [System.Collections.Generic.List[hashtable]]::new()   # always empty — not resolved read-only
        Failures                = [System.Collections.Generic.List[hashtable]]::new()
    }

    # --- 5. Pre-fetch the list endpoints once, then resolve every combination by name ---
    Write-Verbose 'Fetching workspace list...'
    $workspaceMap = _Get-FabricWorkspaceMap -Token $token
    $pipelineMap  = if (-not $SkipPipeline) {
        Write-Verbose 'Fetching deployment pipeline list...'
        _Get-FabricDeploymentPipelineMap -Token $token
    }
    else { @{} }

    # --- 6. Per environment x workspace ---
    foreach ($env in $targetEnvs) {
        Write-Verbose "=== Environment: $($env.name) ==="

        foreach ($ws in $Config.workspaces) {

            if (_Test-FabricTokenExpiry -TokenInfo $tokenInfo) {
                Write-Verbose 'Token nearing expiry — refreshing...'
                $tokenInfo = _Get-FabricAuthToken
                $token     = $tokenInfo.Token
            }

            $resolvedName = _Resolve-WorkspaceName -Config $Config -WorkspaceId $ws.id -EnvironmentName $env.name

            $wsRecord = _New-FabricWorkspaceRecord `
                -Type         $ws.type `
                -Environment  $env.name `
                -Name         $resolvedName `
                -CapacityName $env.capacityName
            $results.Workspaces.Add($wsRecord)

            # a. Resolve the workspace by name from the pre-fetched map.
            $workspaceObj = if ($workspaceMap.ContainsKey($resolvedName)) { $workspaceMap[$resolvedName] } else { $null }
            if (-not $workspaceObj) {
                Write-Verbose "Workspace '$resolvedName' not found."
                $wsRecord.Status = 'NotFound'
                $results.Summary.Missing++
                continue
            }

            $workspaceId          = $workspaceObj.id
            $wsRecord.WorkspaceId  = $workspaceId
            $wsRecord.Status       = 'Existing'
            $results.Summary.Found++

            # b. Workspace Identity — GET /workspaces/{id} exposes a workspaceIdentity block. Non-fatal.
            if (-not $SkipIdentity -and $ws.identity.enabled) {
                try {
                    $workspaceFull = _Invoke-FabricRestMethod -Method GET `
                        -RelativeUri "workspaces/$workspaceId" `
                        -Token       $token `
                        -ErrorAction Stop

                    $identity = if ($workspaceFull.PSObject.Properties.Name -contains 'workspaceIdentity') { $workspaceFull.workspaceIdentity } else { $null }
                    $servicePrincipalId = if ($identity -and $identity.PSObject.Properties.Name -contains 'servicePrincipalId') { $identity.servicePrincipalId } else { $null }

                    if ($servicePrincipalId) {
                        $applicationId = if ($identity.PSObject.Properties.Name -contains 'applicationId') { $identity.applicationId } else { $null }
                        $wsRecord.Identity = [pscustomobject]@{
                            PrincipalId   = $servicePrincipalId
                            ApplicationId = $applicationId
                        }
                        $results.Identities.Add(@{
                            WorkspaceName            = $resolvedName
                            WorkspaceId              = $workspaceId
                            ServicePrincipalObjectId = $servicePrincipalId
                            ApplicationId            = $applicationId
                        })
                    }
                }
                catch {
                    Write-Warning "Identity lookup failed for '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'Identity'
                        Error         = $_.ToString()
                    })
                }
            }

            # c. Git connection — only for the designated git environment (matches Invoke-FabricSetup's gate).
            if (-not $SkipGit -and $ws.git.enabled -and $Config.gitEnvironment -and $env.name -eq $Config.gitEnvironment) {
                try {
                    $gitConnection = _Invoke-FabricRestMethod -Method GET `
                        -RelativeUri "workspaces/$workspaceId/git/connection" `
                        -Token       $token `
                        -ErrorAction Stop

                    $gitState = if ($gitConnection.PSObject.Properties.Name -contains 'gitConnectionState') { $gitConnection.gitConnectionState } else { $null }
                    $wsRecord.GitConnected = [bool]($gitState -and $gitState -ne 'NotConnected')
                }
                catch {
                    # A workspace with no Git connection can surface as a 400/404 — that just means
                    # "not connected", not a failure. Anything else is recorded non-fatally.
                    if ("$_" -match 'Fabric API error (400|404)' -or "$_" -match 'NotFound') {
                        Write-Verbose "No Git connection for '$resolvedName'."
                    }
                    else {
                        Write-Warning "Git connection lookup failed for '$resolvedName' — $_"
                        $results.Failures.Add(@{
                            WorkspaceName = $resolvedName
                            Environment   = $env.name
                            Step          = 'Git'
                            Error         = $_.ToString()
                        })
                    }
                }
            }

            # d. Spark Environment — scoped to the type's configured stages (same gate as Invoke-FabricSetup).
            $wsEnvironment = if ($ws.PSObject.Properties.Name -contains 'environment') { $ws.environment } else { $null }
            $envInStage = $wsEnvironment -and (
                -not ($wsEnvironment.PSObject.Properties.Name -contains 'stages') -or
                -not $wsEnvironment.stages -or
                $env.name -in @($wsEnvironment.stages)
            )
            if (-not $SkipEnvironment -and $wsEnvironment -and $wsEnvironment.enabled -and $envInStage) {
                try {
                    $envName = _Resolve-EnvironmentName -Config $Config -WorkspaceId $ws.id -EnvironmentName $env.name
                    $environmentObj = _Resolve-FabricEnvironment -WorkspaceId $workspaceId -DisplayName $envName -Token $token

                    if ($environmentObj) {
                        $isWorkspaceDefault = $false
                        if ($wsEnvironment.setAsWorkspaceDefault) {
                            $sparkSettings = _Invoke-FabricRestMethod -Method GET `
                                -RelativeUri "workspaces/$workspaceId/spark/settings" `
                                -Token       $token `
                                -ErrorAction Stop
                            $currentEnv  = if ($sparkSettings.PSObject.Properties.Name -contains 'environment') { $sparkSettings.environment } else { $null }
                            $currentName = if ($currentEnv -and $currentEnv.PSObject.Properties.Name -contains 'name') { $currentEnv.name } else { $null }
                            $isWorkspaceDefault = ($currentName -eq $envName)
                        }

                        $wsRecord.SparkEnvironment = [pscustomobject]@{
                            Name               = $envName
                            Id                 = $environmentObj.id
                            IsWorkspaceDefault = $isWorkspaceDefault
                        }
                        $results.Environments.Add(@{
                            WorkspaceName   = $resolvedName
                            WorkspaceId     = $workspaceId
                            EnvironmentName = $envName
                            EnvironmentId   = $environmentObj.id
                        })
                    }
                }
                catch {
                    Write-Warning "Environment lookup failed for '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'Environment'
                        Error         = $_.ToString()
                    })
                }
            }
        }
    }

    # --- 7. Deployment pipelines (per workspace type) ---
    if (-not $SkipPipeline) {
        $pipelineWorkspaces = $Config.workspaces | Where-Object { $_.pipeline.enabled }

        foreach ($ws in $pipelineWorkspaces) {
            $typeCode     = $ws.id
            $pipelineName = "$($Config.project)-$typeCode Pipeline"

            $pipelineObj = if ($pipelineMap.ContainsKey($pipelineName)) { $pipelineMap[$pipelineName] } else { $null }
            if (-not $pipelineObj) {
                $results.Pipelines.Add(@{
                    PipelineName   = $pipelineName
                    PipelineId     = $null
                    WorkspaceType  = $ws.type
                    StagesAssigned = 0
                    Action         = 'NotFound'
                    Stages         = [ordered]@{}
                })
                continue
            }

            try {
                if (_Test-FabricTokenExpiry -TokenInfo $tokenInfo) {
                    $tokenInfo = _Get-FabricAuthToken
                    $token     = $tokenInfo.Token
                }

                $stagesResponse = _Invoke-FabricRestMethod -Method GET `
                    -RelativeUri "deploymentPipelines/$($pipelineObj.id)/stages" `
                    -Token       $token `
                    -ErrorAction Stop

                $stageMap       = [ordered]@{}
                $stagesAssigned = 0
                foreach ($stage in ($stagesResponse.value | Sort-Object order)) {
                    $stageWorkspaceId = if ($stage.PSObject.Properties.Name -contains 'workspaceId') { $stage.workspaceId } else { $null }
                    $stageMap[$stage.displayName] = $stageWorkspaceId
                    if ($stageWorkspaceId) { $stagesAssigned++ }
                }

                $results.Pipelines.Add(@{
                    PipelineName   = $pipelineName
                    PipelineId     = $pipelineObj.id
                    WorkspaceType  = $ws.type
                    StagesAssigned = $stagesAssigned
                    Action         = 'Existing'
                    Stages         = $stageMap
                })
            }
            catch {
                Write-Warning "Pipeline lookup failed for '$($ws.type)' — $_"
                $results.Failures.Add(@{
                    WorkspaceName = "$($ws.type) pipeline"
                    Environment   = 'all'
                    Step          = 'Pipeline'
                    Error         = $_.ToString()
                })
            }
        }
    }

    # --- 8. Index + summarise ---
    $results.WorkspacesByType = _ConvertTo-FabricWorkspaceIndex -Workspace $results.Workspaces
    $results.Summary.Failed   = $results.Failures.Count

    Write-Verbose "=== Topology state — Found: $($results.Summary.Found)  Missing: $($results.Summary.Missing)  Failed: $($results.Summary.Failed) ==="
    if ($results.Failures.Count -gt 0) {
        Write-Warning "$($results.Failures.Count) lookup(s) failed. See `$result.Failures for details."
    }

    return $results
}
