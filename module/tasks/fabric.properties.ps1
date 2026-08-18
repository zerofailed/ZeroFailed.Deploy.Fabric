# InvokeBuild's 'property' checks, in order: 1) a variable already set with this exact name (e.g.
# by a consumer's .zf/config.ps1 — the pre-existing override mechanism this module has always
# supported), 2) an environment variable of this exact name (new: enables CI/CD overrides without
# editing .zf/config.ps1), 3) the given default. The property name is therefore kept identical to
# the destination variable name throughout, rather than following ZeroFailed.DevOps.Common's
# SCREAMING_SNAKE_CASE convention — using a different name would silently stop honouring a
# consumer's existing '$FabricXxx = ...' override, since 'property' has no knowledge of the
# variable it's being assigned into.

# Paths
$FabricTopologyConfigPath = property FabricTopologyConfigPath './fabric/topology.json'

# Behaviour flags
# $FabricEnvironmentFilter stays on ??=, not property: InvokeBuild's 'property' collapses an empty
# array default (@()) to $null, and a single env var has no clean way to represent an array anyway.
$FabricEnvironmentFilter ??= @()
$FabricSkipGit           = [Convert]::ToBoolean((property FabricSkipGit $false))
$FabricSkipIdentity      = [Convert]::ToBoolean((property FabricSkipIdentity $false))
$FabricSkipMonitoring    = [Convert]::ToBoolean((property FabricSkipMonitoring $false))
$FabricSkipEnvironment   = [Convert]::ToBoolean((property FabricSkipEnvironment $false))
$FabricSkipRbac          = [Convert]::ToBoolean((property FabricSkipRbac $false))
$FabricSkipPipeline      = [Convert]::ToBoolean((property FabricSkipPipeline $false))
$FabricSkipPipelineRbac  = [Convert]::ToBoolean((property FabricSkipPipelineRbac $false))
$FabricWhatIf            = [Convert]::ToBoolean((property FabricWhatIf $false))

# Python library deployment (Invoke-FabricPythonLibraryDeploy) — runs after provisioning, typically
# as a separate pipeline. Stage/package coordinates flow from the calling pipeline's build/stage context.
# Empty-string defaults (not $null) below: InvokeBuild's 'property' throws 'Missing property' at
# build-load time for a $null default, which would break every consumer — even ones that never
# touch Python library deployment — since this file is dot-sourced unconditionally. These stay
# optional until deployFabricPythonLibraries' own required-value check runs (fabric.tasks.ps1),
# which already treats '' the same as $null via [string]::IsNullOrWhiteSpace.
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
