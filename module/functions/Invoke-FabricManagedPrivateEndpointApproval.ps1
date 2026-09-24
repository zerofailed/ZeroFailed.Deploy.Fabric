function Invoke-FabricManagedPrivateEndpointApproval {
    <#
    .SYNOPSIS
        Approves the private endpoint connections requested by a topology's managed private endpoints.
    .DESCRIPTION
        Creating a managed private endpoint only sends a private link connection request to the target
        Azure resource; the endpoint cannot be used until the resource's owner approves it. For each
        managed private endpoint in the topology config, this:
          1. Finds the endpoint on its workspace, waiting for it to finish provisioning
          2. Skips it when its connection is already approved
          3. Otherwise approves the connection on the target resource, via
             ZeroFailed.Deploy.Azure's Assert-PrivateEndpointConnectionApproval
        Returns a structured results object with a summary, approval report and failure details.

        This runs separately from Invoke-FabricSetup because approving a connection needs permission on
        the target Azure resource (`privateEndpointConnectionsApproval/action`, included in Owner and
        Contributor), which the identity provisioning the workspaces often does not have. By default a
        failed approval is reported as a failure and leaves the connection pending, so provisioning is
        not blocked by it; use -FailOnError to fail instead.

        Fabric names the private endpoint it creates on the target resource after the managed private
        endpoint, prefixed with the workspace id. The connection to approve is identified by matching
        that name against -EndpointNamePattern.
    .PARAMETER Config
        Topology config object produced by New-FabricTopologyConfig.
    .PARAMETER ConfigPath
        Path to a JSON file containing the topology config (alternative to -Config).
    .PARAMETER Environment
        Single environment name to process. Defaults to every environment in the config.
    .PARAMETER EndpointNamePattern
        Wildcard pattern identifying the private endpoint on the target resource, with the tokens
        {workspaceId} and {name} (the managed private endpoint's name). Defaults to
        '*{workspaceId}*{name}'.
    .PARAMETER TimeoutSeconds
        How long to wait for each endpoint to finish provisioning, for its connection to appear on the
        target resource, and for an approval to take effect. Default: 120. The wait applies per
        endpoint, so a long timeout is expensive when connections cannot be found — raise it only when
        endpoints are known to be slow to provision.
    .PARAMETER PollIntervalSeconds
        How long to wait between checks. Default: 15.
    .PARAMETER FailOnError
        Throw at the end when any endpoint could not be approved, rather than reporting it as a failure.
    .EXAMPLE
        Invoke-FabricManagedPrivateEndpointApproval -Config $topology -Environment 'Dev'

        Approves the connections for the Dev workspaces' managed private endpoints.
    .EXAMPLE
        Invoke-FabricManagedPrivateEndpointApproval -ConfigPath './topology.json' -WhatIf

        Reports what would be approved, without approving anything.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object', SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Object', Position = 0)]
        [pscustomobject]$Config,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$ConfigPath,

        [string]$Environment,

        [string]$EndpointNamePattern = '*{workspaceId}*{name}',

        [ValidateRange(0, 3600)]
        [int]$TimeoutSeconds = 120,

        [ValidateRange(1, 300)]
        [int]$PollIntervalSeconds = 15,

        [switch]$FailOnError
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

    $results = [pscustomobject]@{
        Summary   = [pscustomobject]@{ Approved = 0; Skipped = 0; Failed = 0 }
        Approvals = [System.Collections.Generic.List[hashtable]]::new()
        Failures  = [System.Collections.Generic.List[hashtable]]::new()
    }

    $maxAttempts            = [Math]::Max(1, [Math]::Ceiling($TimeoutSeconds / $PollIntervalSeconds) + 1)
    $approvalCommandChecked = $false

    foreach ($env in $targetEnvs) {
        foreach ($ws in $Config.workspaces) {

            # Configs that predate managed private endpoints have no block, so guard the access (a bare
            # one would throw under Set-StrictMode). The block is an ordered dictionary when the config
            # comes straight from New-FabricTopologyConfig, and an object when loaded from JSON.
            if ($ws.PSObject.Properties.Name -notcontains 'managedPrivateEndpoints') { continue }

            $mpeByEnv = $ws.managedPrivateEndpoints
            $mpeBlock = if ($mpeByEnv -is [System.Collections.IDictionary]) {
                if ($mpeByEnv.Contains($env.name)) { $mpeByEnv[$env.name] }
            }
            elseif ($mpeByEnv -and $mpeByEnv.PSObject.Properties.Name -contains $env.name) {
                $mpeByEnv.$($env.name)
            }

            $mpeBlockProps  = if ($mpeBlock) { $mpeBlock.PSObject.Properties.Name } else { @() }
            $subscriptionId = if ($mpeBlockProps -contains 'subscriptionId') { $mpeBlock.subscriptionId } else { $null }
            $mpeResources   = @(if ($mpeBlockProps -contains 'resources') { $mpeBlock.resources | Where-Object { $_ } })
            if ($mpeResources.Count -eq 0) { continue }

            # Approval lives in ZeroFailed.Deploy.Azure, a required extension dependency of this one.
            # Checked on first use, so a topology with no managed private endpoints is a no-op rather
            # than a failure, and fails with something more useful than 'command not found'.
            if (-not $approvalCommandChecked) {
                if (-not (Get-Command Assert-PrivateEndpointConnectionApproval -ErrorAction Ignore)) {
                    throw "Assert-PrivateEndpointConnectionApproval was not found. Managed private endpoint approval requires the ZeroFailed.Deploy.Azure extension, which provides it."
                }
                $approvalCommandChecked = $true
            }

            # Refresh token if near expiry
            if (_Test-FabricTokenExpiry -TokenInfo $tokenInfo) {
                Write-Verbose 'Token nearing expiry — refreshing...'
                $tokenInfo = _Get-FabricAuthToken
                $token     = $tokenInfo.Token
            }

            $resolvedName = _Resolve-WorkspaceName -Config $Config -WorkspaceId $ws.id -EnvironmentName $env.name

            $workspace = Test-FabricWorkspaceExists -DisplayName $resolvedName -Token $token
            if (-not $workspace) {
                Write-Warning "Workspace '$resolvedName' was not found; its managed private endpoints cannot be approved. Run provisioning first."
                $results.Failures.Add(@{
                    WorkspaceName = $resolvedName
                    Environment   = $env.name
                    Step          = 'Workspace'
                    Error         = "Workspace '$resolvedName' not found."
                })
                $results.Summary.Failed++
                continue
            }
            $workspaceId = $workspace.id

            foreach ($resource in $mpeResources) {
                $resourceProps = $resource.PSObject.Properties.Name
                $resourceName  = if ($resourceProps -contains 'resourceName') { $resource.resourceName } else { $null }

                try {
                    $mpe = _Resolve-ManagedPrivateEndpoint `
                        -SubscriptionId  $subscriptionId `
                        -ResourceGroup   $(if ($resourceProps -contains 'resourceGroup') { $resource.resourceGroup }) `
                        -ResourceName    $resourceName `
                        -ResourceType    $(if ($resourceProps -contains 'resourceType') { $resource.resourceType }) `
                        -SubResourceType $(if ($resourceProps -contains 'subResourceType') { $resource.subResourceType })

                    # a. Find the endpoint on the workspace, waiting for provisioning to finish. The
                    # connection only reaches the target resource once provisioning has succeeded.
                    $endpoint = $null
                    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                        $endpoint = _Get-FabricManagedPrivateEndpoint -WorkspaceId $workspaceId -Name $mpe.Name -Token $token

                        $endpointProps     = if ($endpoint) { $endpoint.PSObject.Properties.Name } else { @() }
                        $provisioningState = if ($endpointProps -contains 'provisioningState') { $endpoint.provisioningState } else { $null }
                        if ($endpoint -and $provisioningState -ne 'Provisioning') { break }
                        if ($attempt -eq $maxAttempts) { break }

                        Write-Verbose "Waiting for managed private endpoint '$($mpe.Name)' on '$resolvedName' to finish provisioning..."
                        Start-Sleep -Seconds $PollIntervalSeconds
                    }

                    if (-not $endpoint) {
                        throw "Managed private endpoint '$($mpe.Name)' was not found on workspace '$resolvedName'. Run provisioning first."
                    }
                    if ($provisioningState -eq 'Provisioning') {
                        throw "Managed private endpoint '$($mpe.Name)' on '$resolvedName' was still provisioning after $TimeoutSeconds seconds."
                    }
                    if ($provisioningState -eq 'Failed') {
                        throw "Managed private endpoint '$($mpe.Name)' on '$resolvedName' failed to provision, so its connection cannot be approved."
                    }

                    # b. Skip an endpoint whose connection has already been approved, so re-runs don't
                    # query the target resource needlessly.
                    $connectionState  = if ($endpointProps -contains 'connectionState') { $endpoint.connectionState } else { $null }
                    $connectionStatus = if ($connectionState -and $connectionState.PSObject.Properties.Name -contains 'status') { $connectionState.status } else { $null }

                    if ($connectionStatus -eq 'Approved') {
                        Write-Verbose "Managed private endpoint '$($mpe.Name)' on '$resolvedName' is already approved."
                        $results.Approvals.Add(@{
                            WorkspaceName               = $resolvedName
                            WorkspaceId                 = $workspaceId
                            Environment                 = $env.name
                            Name                        = $mpe.Name
                            TargetPrivateLinkResourceId = $mpe.TargetPrivateLinkResourceId
                            ConnectionStatus            = 'Approved'
                            Action                      = 'Skipped'
                        })
                        $results.Summary.Skipped++
                        continue
                    }

                    # c. Approve the connection on the target resource.
                    $pattern = $EndpointNamePattern.Replace('{workspaceId}', $workspaceId).Replace('{name}', $mpe.Name)

                    $approval = Assert-PrivateEndpointConnectionApproval `
                        -PrivateLinkResourceId   $mpe.TargetPrivateLinkResourceId `
                        -PrivateEndpointNameLike $pattern `
                        -Description             "Approved for Fabric workspace '$resolvedName'" `
                        -TimeoutSeconds          $TimeoutSeconds `
                        -PollIntervalSeconds     $PollIntervalSeconds

                    $results.Approvals.Add(@{
                        WorkspaceName               = $resolvedName
                        WorkspaceId                 = $workspaceId
                        Environment                 = $env.name
                        Name                        = $mpe.Name
                        TargetPrivateLinkResourceId = $mpe.TargetPrivateLinkResourceId
                        ConnectionStatus            = $approval.Status
                        Action                      = $approval.Action
                    })

                    switch ($approval.Action) {
                        'Approved' { $results.Summary.Approved++ }
                        'Skipped'  { $results.Summary.Skipped++ }
                        default    {
                            # NotFound, or a rejected or disconnected connection: the endpoint is still
                            # unusable and needs someone to act on the target resource.
                            if ($approval.Action -ne 'WhatIf') {
                                $results.Failures.Add(@{
                                    WorkspaceName = $resolvedName
                                    Environment   = $env.name
                                    Step          = 'ManagedPrivateEndpointApproval'
                                    Error         = "Connection for '$($mpe.Name)' on '$($mpe.TargetPrivateLinkResourceId)' was not approved (status '$($approval.Status)')."
                                })
                                $results.Summary.Failed++
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Managed private endpoint approval failed for '$resourceName' on '$resolvedName' — $_"
                    $results.Failures.Add(@{
                        WorkspaceName = $resolvedName
                        Environment   = $env.name
                        Step          = 'ManagedPrivateEndpointApproval'
                        Error         = $_.ToString()
                    })
                    $results.Summary.Failed++
                }
            }
        }
    }

    if ($results.Summary.Failed -gt 0) {
        $message = "$($results.Summary.Failed) managed private endpoint(s) could not be approved. See the Failures report for details."
        if ($FailOnError) { throw $message }
        Write-Warning "$message Their connections remain pending and must be approved on the target resource."
    }

    return $results
}
