# Paths
$FabricTopologyConfigPath ??= './fabric/topology.json'

# Behaviour flags
$FabricEnvironmentFilter ??= @()
$FabricSkipGit           ??= $false
$FabricSkipIdentity      ??= $false
$FabricSkipMonitoring    ??= $false
$FabricSkipEnvironment   ??= $false
$FabricSkipRbac          ??= $false
$FabricSkipPipeline      ??= $false
$FabricSkipPipelineRbac  ??= $false
$FabricWhatIf            ??= $false

# Code artefact deployment (Invoke-FabricArtefactDeploy) — runs after provisioning, typically as a
# separate pipeline. Stage/package coordinates flow from the calling pipeline's build/stage context.
$FabricArtefactConfigPath ??= $FabricTopologyConfigPath
$FabricArtefactStage      ??= $null
$FabricPackageName        ??= $null
$FabricPackageVersion     ??= $null
$FabricFeedOrganisation   ??= $null
$FabricFeedProject        ??= $null
$FabricFeedName           ??= $null
$FabricFeedToken          ??= $env:SYSTEM_ACCESSTOKEN
$FabricArtefactStagingPath ??= $null
# Optional pip constraints file, supplied by the calling repo alongside the topology config.
$FabricConstraintsPath    ??= $null
$FabricArtefactForce      ??= $false
$FabricSkipArtefactDeploy ??= $false
$FabricPythonExecutable   ??= 'python3'

# Wheels are resolved for the target Fabric Spark runtime, not the build agent's interpreter.
# Runtime 1.2 -> Python 3.10; runtime 1.3 -> Python 3.11 (matches the topology's default).
$FabricTargetPythonVersion ??= '3.11'
$FabricTargetPlatform      ??= 'manylinux2014_x86_64'
