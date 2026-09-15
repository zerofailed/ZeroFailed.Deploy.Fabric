function Set-FabricDeploymentPipeline {
    <#
    .SYNOPSIS
        Creates or updates a Fabric deployment pipeline for a workspace type across all environments.
    .DESCRIPTION
        Provisions a deployment pipeline for a single workspace type. Each environment in the
        topology config becomes a named stage in the pipeline, and each environment's workspace is
        assigned to its stage.

        Every environment's workspace must already exist and be visible to the caller (assigning a
        workspace to a stage requires workspace Admin). If any cannot be found, an error is thrown
        before the pipeline is created or modified, so a partially-assigned pipeline is never left
        behind.

        Idempotent: safe to call on an existing pipeline. Already-assigned stages are skipped.
        If a stage is already assigned to a different workspace, a warning is emitted.
    .PARAMETER Config
        The topology config object produced by New-FabricTopologyConfig.
    .PARAMETER WorkspaceType
        The workspace type name to create the pipeline for (e.g. "Bronze").
    .PARAMETER Token
        Bearer token string for the Fabric REST API.
    .EXAMPLE
        Set-FabricDeploymentPipeline -Config $topology -WorkspaceType 'Bronze' -Token $token

        Creates or updates the deployment pipeline for the Bronze workspace type across all environments.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [Parameter(Mandatory)]
        [string]$WorkspaceType,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $wsConfig     = $Config.workspaces | Where-Object { $_.type -eq $WorkspaceType }
    $typeCode     = $wsConfig.id
    $pipelineName = "$($Config.project)-$typeCode Pipeline"

    if ($PSCmdlet.ShouldProcess($pipelineName, 'Configure Fabric Deployment Pipeline')) {
        Write-Debug "Setting up deployment pipeline '$pipelineName' for workspace type '$WorkspaceType'..."

        # 1. Resolve workspace IDs for every environment in the full config. All of them must resolve:
        # pipeline setup runs once every environment has been provisioned, so a missing workspace most
        # likely means the caller lacks access to it.
        $stageMap          = [ordered]@{}
        $missingWorkspaces = [System.Collections.Generic.List[string]]::new()
        foreach ($env in $Config.environments) {
            $wsDisplayName = _Resolve-WorkspaceName -Config $Config -WorkspaceId $typeCode -EnvironmentName $env.name
            $wsObj         = Test-FabricWorkspaceExists -DisplayName $wsDisplayName -Token $Token
            if ($wsObj) {
                $stageMap[$env.name] = $wsObj.id
            }
            else {
                $missingWorkspaces.Add($wsDisplayName)
            }
        }

        if ($missingWorkspaces.Count -gt 0) {
            throw "Cannot configure deployment pipeline '$pipelineName': workspace(s) not found — $($missingWorkspaces -join ', '). Ensure every environment has been provisioned and that the identity running pipeline setup has Admin access to each workspace."
        }

        # 2. Find an existing pipeline by name (paginated)
        $existingPipeline = $null
        $nextUri          = 'deploymentPipelines'
        do {
            $page             = _Invoke-FabricRestMethod -Method GET -RelativeUri $nextUri -Token $Token -ErrorAction Stop
            $existingPipeline = $page.value | Where-Object { $_.displayName -eq $pipelineName } | Select-Object -First 1
            # continuationToken is only present when more pages remain. Guard the access so it
            # does not throw under Set-StrictMode (as enforced by the ZeroFailed build harness).
            $continuationToken = if ($page.PSObject.Properties.Name -contains 'continuationToken') { $page.continuationToken } else { $null }
            $nextUri          = if ($continuationToken) {
                "deploymentPipelines?continuationToken=$continuationToken"
            }
            else { $null }
        } while (-not $existingPipeline -and $nextUri)

        $action     = $null
        $pipelineId = $null
        $apiStages  = $null

        if (-not $existingPipeline) {
            # 3a. Create pipeline with one stage per environment
            Write-Host "Creating deployment pipeline '$pipelineName'..."
            $stagesBody = @(
                foreach ($envName in $stageMap.Keys) {
                    @{ displayName = $envName; isPublic = $false }
                }
            )

            $created    = _Invoke-FabricRestMethod -Method POST `
                -RelativeUri 'deploymentPipelines' `
                -Body        @{ displayName = $pipelineName; stages = $stagesBody } `
                -Token       $Token `
                -ErrorAction Stop

            $pipelineId = $created.id
            $apiStages  = $created.stages
            $action     = 'Created'
            Write-Verbose "Pipeline '$pipelineName' created (id: $pipelineId)."
        }
        else {
            # 3b. Pipeline exists — retrieve its current stages
            $pipelineId = $existingPipeline.id
            Write-Verbose "Pipeline '$pipelineName' already exists (id: $pipelineId). Checking stage assignments..."
            $stagesResponse = _Invoke-FabricRestMethod -Method GET `
                -RelativeUri "deploymentPipelines/$pipelineId/stages" `
                -Token       $Token `
                -ErrorAction Stop
            $apiStages = $stagesResponse.value | Sort-Object order
            $action    = 'Skipped'
        }

        # 4. Assign workspaces to vacant stages
        $stagesAssigned = 0
        foreach ($stage in $apiStages) {
            $workspaceId = $stageMap[$stage.displayName]

            if (-not $workspaceId) {
                Write-Verbose "Stage '$($stage.displayName)' does not match an environment in the config. Skipping."
                continue
            }

            # workspaceId is absent on unassigned stages. Guard the access so it does not throw
            # under Set-StrictMode (as enforced by the ZeroFailed build harness).
            $stageWorkspaceId = if ($stage.PSObject.Properties.Name -contains 'workspaceId') { $stage.workspaceId } else { $null }

            if ($stageWorkspaceId -eq $workspaceId) {
                Write-Verbose "Stage '$($stage.displayName)' already assigned to the correct workspace. Skipping."
                continue
            }

            if ($stageWorkspaceId) {
                Write-Warning "Stage '$($stage.displayName)' is already assigned to workspace '$stageWorkspaceId' (expected '$workspaceId'). Unassign manually if a change is needed."
                continue
            }

            Write-Verbose "Assigning workspace to stage '$($stage.displayName)' in pipeline '$pipelineName'..."
            _Invoke-FabricRestMethod -Method POST `
                -RelativeUri "deploymentPipelines/$pipelineId/stages/$($stage.id)/assignWorkspace" `
                -Body        @{ workspaceId = $workspaceId } `
                -Token       $Token `
                -ErrorAction Stop | Out-Null

            $stagesAssigned++
            if ($action -eq 'Skipped') { $action = 'Updated' }
        }

        Write-Verbose "Pipeline '$pipelineName' ready. Action: $action, Stages assigned: $stagesAssigned."

        return @{
            PipelineName   = $pipelineName
            PipelineId     = $pipelineId
            WorkspaceType  = $WorkspaceType
            StagesAssigned = $stagesAssigned
            Action         = $action
        }
    }
    else {
        return @{
            PipelineName   = $pipelineName
            PipelineId     = 'whatif-pipeline-id'
            WorkspaceType  = $WorkspaceType
            StagesAssigned = 0
            Action         = 'WhatIf'
        }
    }
}
