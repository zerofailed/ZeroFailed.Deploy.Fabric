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
