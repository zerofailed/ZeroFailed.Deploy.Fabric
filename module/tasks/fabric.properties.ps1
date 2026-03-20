# Paths
$FabricTopologyConfigPath ??= './fabric/topology.json'

# Behaviour flags
$FabricEnvironmentFilter ??= @()
$FabricSkipGit           ??= $false
$FabricSkipIdentity      ??= $false
$FabricSkipMonitoring    ??= $false
$FabricSkipRbac          ??= $false
$FabricSkipPipeline      ??= $false
$FabricWhatIf            ??= $false
