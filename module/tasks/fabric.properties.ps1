
# Paths
$FabricTopologyConfigPath = property FabricTopologyConfigPath './fabric/topology.json'

# Behaviour flags
# $FabricEnvironmentFilter stays on ??=, not property: InvokeBuild's 'property' collapses an empty
# array default (@()) to $null, and a single env var has no clean way to represent an array anyway.
$FabricEnvironmentFilter ??= @()
$FabricSkipGit           = [Convert]::ToBoolean((property FabricSkipGit $false))
$FabricSkipIdentity      = [Convert]::ToBoolean((property FabricSkipIdentity $false))
$FabricSkipIdentityGroup = [Convert]::ToBoolean((property FabricSkipIdentityGroup $false))
$FabricSkipMonitoring    = [Convert]::ToBoolean((property FabricSkipMonitoring $false))
$FabricSkipEnvironment   = [Convert]::ToBoolean((property FabricSkipEnvironment $false))
$FabricSkipRbac          = [Convert]::ToBoolean((property FabricSkipRbac $false))
$FabricSkipPipeline      = [Convert]::ToBoolean((property FabricSkipPipeline $false))
$FabricSkipPipelineRbac  = [Convert]::ToBoolean((property FabricSkipPipelineRbac $false))
$FabricWhatIf            = [Convert]::ToBoolean((property FabricWhatIf $false))

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
