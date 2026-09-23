
# Paths
$FabricTopologyConfigPath = property FabricTopologyConfigPath './fabric/topology.json'

# Behaviour flags
# Single environment name to provision. Defaults to all environments in the topology config.
$FabricEnvironment       = property FabricEnvironment ''
$FabricSkipGit           = [Convert]::ToBoolean((property FabricSkipGit $false))
$FabricSkipIdentity      = [Convert]::ToBoolean((property FabricSkipIdentity $false))
$FabricSkipMonitoring    = [Convert]::ToBoolean((property FabricSkipMonitoring $false))
$FabricSkipEnvironment   = [Convert]::ToBoolean((property FabricSkipEnvironment $false))
$FabricSkipVariableLibrary = [Convert]::ToBoolean((property FabricSkipVariableLibrary $false))
$FabricSkipRbac          = [Convert]::ToBoolean((property FabricSkipRbac $false))
$FabricSkipManagedPrivateEndpoints = [Convert]::ToBoolean((property FabricSkipManagedPrivateEndpoints $false))
# Approval of managed private endpoint connections — needs permission on the target Azure resources,
# so it can be skipped (or made fatal) independently of creating the endpoints.
$FabricSkipManagedPrivateEndpointApproval = [Convert]::ToBoolean((property FabricSkipManagedPrivateEndpointApproval $false))
$FabricFailOnManagedPrivateEndpointApprovalError = [Convert]::ToBoolean((property FabricFailOnManagedPrivateEndpointApprovalError $false))
$FabricManagedPrivateEndpointApprovalTimeoutSeconds = [int](property FabricManagedPrivateEndpointApprovalTimeoutSeconds 600)
$FabricManagedPrivateEndpointApprovalPollIntervalSeconds = [int](property FabricManagedPrivateEndpointApprovalPollIntervalSeconds 15)
# Wildcard pattern identifying the private endpoint Fabric creates on the target resource, with the
# {workspaceId} and {name} tokens. Override if Fabric's naming differs from the default.
$FabricManagedPrivateEndpointNamePattern = property FabricManagedPrivateEndpointNamePattern ''
$FabricWhatIf            = [Convert]::ToBoolean((property FabricWhatIf $false))

# Deployment pipeline setup (Invoke-FabricDeploymentPipelineSetup) — pipelines span every environment,
# so this runs as its own stage once each environment's workspaces have been provisioned.
$FabricSkipPipeline      = [Convert]::ToBoolean((property FabricSkipPipeline $false))
$FabricSkipPipelineRbac  = [Convert]::ToBoolean((property FabricSkipPipelineRbac $false))

# Python library deployment (Invoke-FabricPythonLibraryDeploy) — runs after provisioning, typically
# as a separate pipeline. Stage/package coordinates flow from the calling pipeline's build/stage context.
$FabricPythonLibraryConfigPath = property FabricPythonLibraryConfigPath $FabricTopologyConfigPath
$FabricPythonLibraryStage = property FabricPythonLibraryStage ''
$FabricPackageName        = property FabricPackageName ''
$FabricPackageVersion     = property FabricPackageVersion ''
$FabricFeedOrganisation   = property FabricFeedOrganisation ''
$FabricFeedProject        = property FabricFeedProject ''
$FabricFeedName           = property FabricFeedName ''
$FabricFeedToken          = property FabricFeedToken ($env:SYSTEM_ACCESSTOKEN ?? '')
$FabricPythonLibraryStagingPath = property FabricPythonLibraryStagingPath ''
# Optional pip constraints file, supplied by the calling repo alongside the topology config.
$FabricConstraintsPath    = property FabricConstraintsPath ''
$FabricPythonLibraryForce = [Convert]::ToBoolean((property FabricPythonLibraryForce $false))
$FabricSkipPythonLibraryDeploy = [Convert]::ToBoolean((property FabricSkipPythonLibraryDeploy $false))
$FabricPythonExecutable   = property FabricPythonExecutable 'python3'

# Wheels are resolved for the target Fabric Spark runtime, not the build agent's interpreter.
# Runtime 1.2 -> Python 3.10; runtime 1.3 -> Python 3.11 (matches the topology's default).
$FabricTargetPythonVersion = property FabricTargetPythonVersion '3.11'
$FabricTargetPlatform      = property FabricTargetPlatform 'manylinux2014_x86_64'
