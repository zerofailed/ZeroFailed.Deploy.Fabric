function Invoke-FabricDeploymentPipelineSetup {
    <#
    .SYNOPSIS
        Creates or updates Fabric deployment pipelines from a topology config.
    .DESCRIPTION
        For each workspace type with pipelines enabled in the config:
          1. Creates or updates the deployment pipeline, with one stage per environment, and assigns
             each environment's workspace to its stage
          2. Applies deployment pipeline role assignments (if configured)
        Returns a structured results object with a summary, pipeline report, pipeline role assignment
        report, and failure details.

        Deployment pipelines span every environment, so this runs separately from Invoke-FabricSetup —
        typically as a dedicated pipeline stage once each environment's workspaces have been
        provisioned. The identity running it must be able to see every workspace, and assigning a
        workspace to a pipeline stage requires workspace Admin: grant this through the topology's
        role assignments for every environment. A workspace type whose workspaces cannot all be found
        is recorded as a failure and its pipeline is left untouched.
    .PARAMETER Config
        Topology config object produced by New-FabricTopologyConfig.
    .PARAMETER ConfigPath
        Path to a JSON file containing the topology config (alternative to -Config).
    .PARAMETER SkipPipelineRbac
        Skip deployment pipeline role assignment application for all workspace types.
    .EXAMPLE
        Invoke-FabricDeploymentPipelineSetup -Config $topology -WhatIf

        Simulates deployment pipeline setup for every pipeline-enabled workspace type.
    .EXAMPLE
        Invoke-FabricDeploymentPipelineSetup -ConfigPath "./topology.json" -SkipPipelineRbac

        Creates or updates the deployment pipelines from a saved topology config, without applying
        pipeline role assignments.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object', SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object', Position = 0)]
        [pscustomobject]$Config,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$ConfigPath,

        [switch]$SkipPipelineRbac
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
    # Pipeline setup only uses the Fabric REST API, so (unlike Invoke-FabricSetup) there is no
    # MicrosoftFabricMgmt auth context to initialise.
    Write-Verbose 'Acquiring Fabric auth token...'
    $tokenInfo = _Get-FabricAuthToken
    $token     = $tokenInfo.Token

    $results = [pscustomobject]@{
        Summary                 = [pscustomobject]@{ Created = 0; Updated = 0; Skipped = 0; Failed = 0 }
        Pipelines               = [System.Collections.Generic.List[hashtable]]::new()
        PipelineRoleAssignments = [System.Collections.Generic.List[hashtable]]::new()
        Failures                = [System.Collections.Generic.List[hashtable]]::new()
    }

    # --- 3. Deployment Pipelines (per workspace type, spans all environments) ---
    $pipelineWorkspaces = @($Config.workspaces | Where-Object { $_.pipeline.enabled })
    if ($pipelineWorkspaces.Count -eq 0) {
        Write-Warning 'No workspace types have deployment pipelines enabled in the config. Nothing to do.'
        return $results
    }

    foreach ($ws in $pipelineWorkspaces) {

        # Refresh token if near expiry
        if (_Test-FabricTokenExpiry -TokenInfo $tokenInfo) {
            Write-Verbose 'Token nearing expiry — refreshing...'
            $tokenInfo = _Get-FabricAuthToken
            $token     = $tokenInfo.Token
        }

        # a. Pipeline — fatal for this workspace type if it fails (including when any environment's
        # workspace cannot be found, in which case the pipeline is not created or modified)
        try {
            $pipelineResult = Set-FabricDeploymentPipeline `
                -Config        $Config `
                -WorkspaceType $ws.type `
                -Token         $token
            $results.Pipelines.Add($pipelineResult)

            switch ($pipelineResult.Action) {
                'Created' { $results.Summary.Created++ }
                'Updated' { $results.Summary.Updated++ }
                'Skipped' { $results.Summary.Skipped++ }
            }
        }
        catch {
            Write-Warning "Deployment pipeline setup failed for '$($ws.type)' — $_"
            $results.Failures.Add(@{
                WorkspaceType = $ws.type
                Step          = 'Pipeline'
                Error         = $_.ToString()
            })
            $results.Summary.Failed++
            continue
        }

        # b. Pipeline Role Assignments — non-fatal, log and continue
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
                            WorkspaceType = $ws.type
                            Step          = 'PipelineRoleAssignment'
                            Error         = $_.ToString()
                        })
                    }
                }
            }
        }
    }

    # --- 4. Report ---
    $s = $results.Summary
    Write-Verbose "=== Deployment pipeline setup complete — Created: $($s.Created)  Updated: $($s.Updated)  Skipped: $($s.Skipped)  Failed: $($s.Failed) ==="

    if ($results.Failures.Count -gt 0) {
        Write-Warning "$($results.Failures.Count) deployment pipeline step(s) failed. See `$result.Failures for details."
    }

    return $results
}
