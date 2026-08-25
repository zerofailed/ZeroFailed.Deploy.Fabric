# `ZeroFailed.Deploy.Fabric` — Microsoft Fabric Workspace Provisioner

A ZeroFailed extension module for provisioning Microsoft Fabric workspaces across DTAP environments. Workspaces are named from a convention, connected to Git, optionally provisioned with Workspace Identities, optionally configured with workspace monitoring, optionally provisioned with a Fabric Spark Environment (set as the workspace default), optionally have Entra-based RBAC role assignments applied, and optionally have Fabric deployment pipelines set up across environments — with their own Entra-based role assignments. All provisioning steps are idempotent and safe to re-run.

The module also handles **Python library deployment**: once workspaces and their Spark Environments have been provisioned, `Invoke-FabricPythonLibraryDeploy` downloads a Python package (`.whl`) and its full dependency closure from an Azure Artifacts feed and uploads them into the Spark Environments' custom libraries for a given stage. Provisioning and Python library deployment are designed to run as **two separate pipelines** — see [Python library deployment](#python-library-deployment).

### Requirements

| Requirement | Details |
|---|---|
| PowerShell | 7.0+ |
| Az module | `Install-Module Az -Scope CurrentUser` |
| MicrosoftFabricMgmt module | `Install-Module MicrosoftFabricMgmt -Scope CurrentUser` |
| Azure login | `Connect-AzAccount -UseDeviceAuthentication` before running |
| Python + pip | Only for **Python library deployment** (`Invoke-FabricPythonLibraryDeploy`) — used to download the package and its dependencies from the Azure Artifacts feed |

### Installation

```powershell
Import-Module ./module/ZeroFailed.Deploy.Fabric.psd1
```

### ZeroFailed task usage

In a ZeroFailed build pipeline, add the module as a dependency and the tasks are automatically available:

```powershell
# In your build's .zf/config.ps1:
$FabricTopologyConfigPath = './fabric/topology.json'
$FabricEnvironmentFilter  = @('Dev')   # omit to process all environments
$FabricSkipGit            = $false
$FabricSkipIdentity       = $false
$FabricSkipMonitoring     = $false
$FabricSkipEnvironment    = $false
$FabricSkipRbac           = $false
$FabricSkipPipeline       = $false
$FabricSkipPipelineRbac   = $false
$FabricWhatIf             = $false
```

Every `$Fabric*` property above (and the Python library deployment ones below) can also be overridden via an identically-named environment variable — e.g. `$env:FabricSkipGit = 'true'` — without editing `.zf/config.ps1`, which is useful for varying behaviour between CI/CD and local runs. An explicit assignment in `.zf/config.ps1` still takes priority over the environment variable. (`$FabricEnvironmentFilter` is the one exception — it's an array, which doesn't have a clean single-environment-variable representation.)

The module registers these Invoke-Build tasks:
- `ensureFabricModules` — registers Az.Accounts, Az.Resources and MicrosoftFabricMgmt with ZeroFailed.DevOps.Common's `RequiredPowerShellModules`, so `setupModules` installs/imports them (runs before `setupModules`)
- `provisionFabricWorkspaces` — runs `Invoke-FabricSetup` from the topology config (runs after `DeployCore`)
- `ensureFabricPythonLibraryTooling` — verifies Python/pip is available (runs before `deployFabricPythonLibraries`)
- `deployFabricPythonLibraries` — runs `Invoke-FabricPythonLibraryDeploy` for a single stage (standalone; invoke from a separate deployment pipeline)

For **Python library deployment** (typically a separate pipeline from provisioning), configure:

```powershell
# In your deployment build's .zf/config.ps1:
$FabricPythonLibraryConfigPath = './fabric/topology.json'   # defaults to $FabricTopologyConfigPath
$FabricPythonLibraryStage = 'DEV'                       # the single stage this run targets
$FabricPackageName        = 'mycompany.dataprep'
$FabricPackageVersion     = '1.4.2'
$FabricFeedOrganisation   = 'contoso'
$FabricFeedProject        = 'Analytics'
$FabricFeedName           = 'fabric-python'
$FabricFeedToken          = $env:SYSTEM_ACCESSTOKEN    # Feed Reader PAT / pipeline access token
$FabricConstraintsPath    = './fabric/constraints.txt' # optional pip constraints file (omit for none)
$FabricPythonLibraryForce = $false                     # re-publish even if already up to date
$FabricSkipPythonLibraryDeploy = $false
$FabricPythonExecutable   = 'python3'                  # 'python' is not on Microsoft-hosted Ubuntu images

# Wheels are resolved for the target Fabric Spark runtime, not the build agent's interpreter.
# Runtime 1.2 -> Python 3.10; runtime 1.3 -> Python 3.11.
$FabricTargetPythonVersion = '3.11'
$FabricTargetPlatform      = 'manylinux2014_x86_64'
```

### Quick start

```powershell
# 1. Log in to Azure
Connect-AzAccount -UseDeviceAuthentication

# 2. Generate a topology config
$topology = New-FabricTopologyConfig `
    -Project             "salesanalytics" `
    -WorkspaceTypes      @("Bronze", "Silver", "Gold", "Reporting") `
    -Environments        @("Dev", "Test", "Acceptance", "Production") `
    -CapacityMap         @{ Dev="cap-dev"; Test="cap-test"; Acceptance="cap-acc"; Production="cap-prod" } `
    -GitProvider         "AzureDevOps" `
    -GitOrganisation     "contoso" `
    -GitProject          "SalesAnalytics" `
    -GitEnvironment      "Dev" `
    -GitWorkspaceConfig  @{
        Bronze = @{ RepositoryName = "salesanalytics-bronze"; Branch = "feature/dev" }
        Gold   = @{ RepositoryName = "salesanalytics-gold";   Branch = "feature/dev" }
    } `
    -EnableIdentity      @("Bronze", "Silver", "Gold") `
    -EnableMonitoring    @("Bronze", "Silver", "Gold", "Reporting") `
    -EnablePipelines     @("Bronze", "Silver", "Gold") `
    -EnableEnvironments  @("Bronze", "Silver", "Gold") `
    -EnvironmentStages   @{
        # Restrict which environments get a Spark Environment (omit a type for all environments)
        Bronze = @("Dev", "Production")
        Silver = @("Dev", "Production")
        Gold   = @("Production")
    } `
    -SetEnvironmentAsDefault `
    -RoleAssignments     @(
        # All workspaces, all environments: read-only for the reporting group
        @{ PrincipalId = "aaaaaaaa-0000-0000-0000-000000000001"; PrincipalType = "Group"; Role = "Viewer" }
        # Bronze/Silver/Gold: contributors in Dev only
        @{ PrincipalId = "bbbbbbbb-0000-0000-0000-000000000002"; PrincipalType = "Group"; Role = "Contributor";
           WorkspaceTypes = @("Bronze", "Silver", "Gold"); Environments = @("Dev") }
    ) `
    -PipelineRoleAssignments @(
        # Platform team administers every deployment pipeline (Admin is the only pipeline role)
        @{ PrincipalId = "dddddddd-0000-0000-0000-000000000004"; PrincipalType = "Group" }
    )

# 3. Preview what will be created (no API calls made)
Invoke-FabricSetup -Config $topology -WhatIf

# 4. Provision everything
$result = Invoke-FabricSetup -Config $topology

# 5. Inspect the identity report for downstream RBAC use
$result.Identities | Format-Table WorkspaceName, ServicePrincipalObjectId, ApplicationId

# 6. Inspect the monitoring report
$result.Monitoring | Format-Table WorkspaceName, WorkspaceId, Enabled

# 6b. Inspect the environment report
$result.Environments | Format-Table WorkspaceName, EnvironmentName, EnvironmentId, Action

# 7. Inspect the role assignment report
$result.RoleAssignments | Format-Table WorkspaceName, PrincipalId, Role, Action

# 8. Inspect the deployment pipeline report
$result.Pipelines | Format-Table PipelineName, PipelineId, WorkspaceType, StagesAssigned, Action

# 9. Inspect the pipeline role assignment report
$result.PipelineRoleAssignments | Format-Table PipelineName, PrincipalId, Role, Action
```

---

### Naming convention

Workspace names follow the template `{project}-{type} [{env}]`, with casing controlled by the short-code maps, non-alphanumeric characters replaced by hyphens, truncated to 64 characters.

| Type | Short code | Environment | Short code |
|---|---|---|---|
| Bronze | `Bronze` | Dev | `DEV` |
| Silver | `Silver` | Test | `TEST` |
| Gold | `Gold` | Acceptance | `ACC` |
| ETL | `ETL` | Production | `PROD` |
| Storage | `Storage` | | |
| Reporting | `Report` | | |

**Examples:** `salesanalytics-Bronze [DEV]`, `salesanalytics-Report [PROD]`, `salesanalytics-ETL [ACC]`

---

### Public functions

#### `New-FabricTopologyConfig`

Generates a structured topology config object from parameters. This is the primary entry point before provisioning. The config can be inspected, saved to JSON for version control, and passed directly to `Invoke-FabricSetup`.

```powershell
New-FabricTopologyConfig `
    -Project             "salesanalytics" `
    -WorkspaceTypes      @("Bronze", "Silver", "Gold", "Reporting") `
    -Environments        @("Dev", "Test", "Acceptance", "Production") `
    -CapacityMap         @{ Dev="cap-dev"; Test="cap-test"; Acceptance="cap-acc"; Production="cap-prod" } `
    -GitProvider         "AzureDevOps" `
    -GitOrganisation     "contoso" `
    -GitProject          "SalesAnalytics" `
    -GitEnvironment      "Dev" `
    -GitWorkspaceConfig  @{
        Bronze = @{ RepositoryName = "salesanalytics-bronze"; Branch = "feature/dev" }
        Gold   = @{ RepositoryName = "salesanalytics-gold";   Branch = "feature/dev"; RootFolder = "gold" }
    } `
    -EnableIdentity      @("Bronze", "Silver", "Gold") `
    -EnableMonitoring    @("Bronze", "Silver", "Gold", "Reporting") `
    -EnablePipelines     @("Bronze", "Silver", "Gold") `
    -EnableEnvironments  @("Bronze", "Silver", "Gold") `
    -EnvironmentStages   @{
        Bronze = @("Dev", "Production")   # Spark Environment only in these stages
        Gold   = @("Production")
        # Silver omitted -> Spark Environment in every environment
    } `
    -SetEnvironmentAsDefault `
    -RoleAssignments     @(
        @{ PrincipalId = "aaaaaaaa-..."; PrincipalType = "Group"; Role = "Viewer" }
        @{ PrincipalId = "bbbbbbbb-..."; PrincipalType = "Group"; Role = "Contributor";
           WorkspaceTypes = @("Bronze", "Silver", "Gold"); Environments = @("Dev") }
    ) `
    -PipelineRoleAssignments @(
        @{ PrincipalId = "dddddddd-..."; PrincipalType = "Group" }
        @{ PrincipalId = "eeeeeeee-..."; PrincipalType = "ServicePrincipal"; WorkspaceTypes = @("Gold") }
    ) `
    -OutputPath          "./topology.json"
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-Project` | `string` | Yes | — | Project name; used as the first segment of all workspace names |
| `-WorkspaceTypes` | `string[]` | Yes | — | Workspace types to create. Valid: `Bronze`, `Silver`, `Gold`, `ETL`, `Storage`, `Reporting` |
| `-Environments` | `string[]` | Yes | — | DTAP environments. Valid: `Dev`, `Test`, `Acceptance`, `Production` |
| `-CapacityMap` | `hashtable` | Yes | — | Maps each environment name to a Fabric capacity name |
| `-GitProvider` | `string` | When using Git | — | `AzureDevOps` or `GitHub` |
| `-GitOrganisation` | `string` | When using Git | — | Azure DevOps organisation or GitHub owner name |
| `-GitProject` | `string` | AzureDevOps only | — | Azure DevOps project name |
| `-GitEnvironment` | `string` | No | `Dev` | Single environment where Git integration is enabled. Set to `''` to disable for all |
| `-GitWorkspaceConfig` | `hashtable` | No | — | Per-workspace-type Git configuration (see below) |
| `-EnableIdentity` | `string[]` | No | All types | Workspace types that should have a Workspace Identity provisioned |
| `-EnableMonitoring` | `string[]` | No | None | Workspace types that should have monitoring enabled |
| `-EnablePipelines` | `string[]` | No | None | Workspace types that should have a Fabric deployment pipeline created (one pipeline per type, spanning all environments) |
| `-EnableEnvironments` | `string[]` | No | None | Workspace types that should have a Fabric Spark Environment provisioned (one environment per workspace) |
| `-EnvironmentStages` | `hashtable` | No | All environments | Per-workspace-type map restricting *which* environments get a Spark Environment (see below) |
| `-SetEnvironmentAsDefault` | `switch` | No | Off | When set, environment-enabled workspaces have their environment registered as the workspace default |
| `-EnvironmentRuntimeVersion` | `string` | No | `1.3` | Spark runtime version used for provisioned environments |
| `-RoleAssignments` | `hashtable[]` | No | None | Role assignment rules applied by workspace type and environment (see below) |
| `-PipelineRoleAssignments` | `hashtable[]` | No | None | Deployment pipeline role assignment rules applied by workspace type (see below) |
| `-OutputPath` | `string` | No | — | Write the generated config as JSON to this path |

**Returns:** A `pscustomobject` topology config. Also writes JSON to `-OutputPath` if specified.

**`-GitWorkspaceConfig` — per-type Git configuration:**

Git integration is opt-in per workspace type. Only types listed in `-GitWorkspaceConfig` will be connected to Git, and only in the environment specified by `-GitEnvironment`. All other environments receive no Git integration (deployments are artefact-based).

Each entry supports:

| Key | Required | Default | Description |
|---|---|---|---|
| `RepositoryName` | Yes | — | Git repository name |
| `RootFolder` | No | `fabric` | Root folder within the repository |
| `Branch` | No | `main` | Branch to connect in the Git environment |

```powershell
-GitWorkspaceConfig @{
    # ETL workspace: dedicated repo, develop branch
    ETL = @{
        RepositoryName = "salesanalytics-etl"
        Branch         = "develop"
    }
    # Reporting: separate repo, custom folder, default branch (main)
    Reporting = @{
        RepositoryName = "salesanalytics-reporting"
        RootFolder     = "reporting"
    }
    # All other workspace types (Bronze, Silver, Gold) get no Git integration
}
```

**Inspect the config:**

```powershell
$topology = New-FabricTopologyConfig ...
$topology | ConvertTo-Json -Depth 10

# Check resolved names before provisioning
foreach ($ws in $topology.workspaces) {
    foreach ($env in $topology.environments) {
        "{0}-{1}-{2}" -f $topology.project, $topology.namingConvention.typeShortCodes.($ws.type), $env.shortCode
    }
}
```

**Save and reload config:**

```powershell
# Save
New-FabricTopologyConfig ... -OutputPath "./topology.json"

# Reload and provision
Invoke-FabricSetup -ConfigPath "./topology.json"
```

**GitHub provider:**

```powershell
New-FabricTopologyConfig `
    -Project         "myproject" `
    -WorkspaceTypes  @("Bronze", "Gold") `
    -Environments    @("Dev", "Production") `
    -CapacityMap     @{ Dev="cap-dev"; Production="cap-prod" } `
    -GitEnvironment  "Dev" `
    -GitProvider     "GitHub" `
    -GitOrganisation "my-github-org" `
    -GitWorkspaceConfig @{
        Bronze = @{ RepositoryName = "myproject-bronze" }
        Gold   = @{ RepositoryName = "myproject-gold" }
    }
```

**`-RoleAssignments` — RBAC configuration:**

Each rule in `-RoleAssignments` is a hashtable that declares which Entra principal should hold which role, with optional filters for workspace type and environment. Rules are resolved and stored in the topology config per workspace per environment; `Invoke-FabricSetup` applies them idempotently using the Fabric workspace role assignment API.

| Key | Required | Description |
|---|---|---|
| `PrincipalId` | Yes | Entra object ID of the group, user, or service principal |
| `PrincipalType` | Yes | `Group`, `User`, or `ServicePrincipal` |
| `Role` | Yes | `Admin`, `Contributor`, `Member`, or `Viewer` |
| `WorkspaceTypes` | No | Array of workspace type names to apply this rule to; omit for all types |
| `Environments` | No | Array of environment names to apply this rule to; omit for all environments |

```powershell
-RoleAssignments @(
    # All workspace types, all environments — broad read-only access
    @{ PrincipalId = "aaaaaaaa-0000-0000-0000-000000000001"
       PrincipalType = "Group"; Role = "Viewer" }

    # ETL and Bronze only, Dev and Test — contributor access for engineers
    @{ PrincipalId = "bbbbbbbb-0000-0000-0000-000000000002"
       PrincipalType = "Group"; Role = "Contributor"
       WorkspaceTypes = @("ETL", "Bronze"); Environments = @("Dev", "Test") }

    # Gold workspace in Production only — individual user admin override
    @{ PrincipalId = "cccccccc-0000-0000-0000-000000000003"
       PrincipalType = "User"; Role = "Admin"
       WorkspaceTypes = @("Gold"); Environments = @("Production") }
)
```

Rules are **additive** — all matching rules apply to a given workspace/environment combination. The idempotency check (`Set-FabricWorkspaceRoleAssignment`) ensures assignments are not duplicated on re-runs.

**`-PipelineRoleAssignments` — deployment pipeline RBAC configuration:**

Deployment pipelines have their own access control, separate from the workspaces they orchestrate. Each rule in `-PipelineRoleAssignments` declares which Entra principal should be granted access to a pipeline, with an optional filter for workspace type. A deployment pipeline spans all environments, so — unlike `-RoleAssignments` — these rules are **not** environment-scoped. Rules are resolved and stored on each workspace type's `pipeline` block; after a pipeline is created, `Invoke-FabricSetup` applies them idempotently using the Fabric deployment pipeline role assignment API.

| Key | Required | Description |
|---|---|---|
| `PrincipalId` | Yes | Entra object ID of the group, user, or service principal |
| `PrincipalType` | Yes | `Group`, `User`, or `ServicePrincipal` |
| `Role` | No | Only `Admin` is supported by Fabric deployment pipelines; defaults to `Admin` |
| `WorkspaceTypes` | No | Array of workspace type names to apply this rule to; omit for all types |

```powershell
-PipelineRoleAssignments @(
    # Platform team administers every deployment pipeline
    @{ PrincipalId = "dddddddd-0000-0000-0000-000000000004"
       PrincipalType = "Group" }

    # Release service principal scoped to the Gold pipeline only
    @{ PrincipalId = "eeeeeeee-0000-0000-0000-000000000005"
       PrincipalType = "ServicePrincipal"; WorkspaceTypes = @("Gold") }
)
```

> **Note:** Fabric deployment pipelines only support the `Admin` role. Supplying any other `Role` value is rejected by `New-FabricTopologyConfig`. As with workspace RBAC, the idempotency check (`Set-FabricDeploymentPipelineRoleAssignment`) skips principals that already have access on re-runs. Pipeline role assignments are applied only for workspace types whose pipelines are enabled via `-EnablePipelines`.

**`-EnableEnvironments` — Spark Environments:**

Fabric Spark Environments are the mechanism for deploying custom Python packages (`.whl`) and shared Spark compute/library configuration so notebooks and Spark job definitions can consume them. Environment provisioning is opt-in per workspace type via `-EnableEnvironments`; each enabled workspace gets its own environment (one per workspace), named from the `{project}-{type} Env` template (e.g. `salesanalytics-Bronze Env`). The stage (Dev/Prod/…) is deliberately **not** part of the environment name — each stage's environment lives in its own workspace, so the name stays stable across stages.

By default, an enabled workspace type gets a Spark Environment in **every** environment (Dev, Test, …). Use `-EnvironmentStages` to restrict *which* environments get one, per workspace type — for example, provision Bronze's environment only in Dev and Production, and Gold's only in Production:

```powershell
New-FabricTopologyConfig `
    -Project            "salesanalytics" `
    -WorkspaceTypes     @("Bronze", "Silver", "Gold") `
    -Environments       @("Dev", "Test", "Acceptance", "Production") `
    -CapacityMap        @{ Dev="cap-dev"; Test="cap-test"; Acceptance="cap-acc"; Production="cap-prod" } `
    -EnableEnvironments @("Bronze", "Gold") `
    -EnvironmentStages  @{
        Bronze = @("Dev", "Production")   # Spark Environment only in Dev + Production
        Gold   = @("Production")          # Spark Environment only in Production
        # Silver is not environment-enabled, so it gets none
        # A type omitted here but present in -EnableEnvironments defaults to all environments
    }
```

`-EnvironmentStages` is keyed by workspace type; each value is the list of environment names that should receive a Spark Environment for that type. Keys must be listed in `-EnableEnvironments` and reference environments present in `-Environments`, or `New-FabricTopologyConfig` throws. A type that is environment-enabled but omitted from `-EnvironmentStages` keeps the default behaviour (every environment). This scoping is stored as `environment.stages` on each workspace in the config, and is honoured by both `Invoke-FabricSetup` (only provisions the environment in the listed stages) and `Invoke-FabricPythonLibraryDeploy` (only deploys packages into workspaces whose environment is enabled for the target stage).

When `-SetEnvironmentAsDefault` is supplied, each enabled workspace's environment is registered as the **workspace default** (via the Spark settings API), so notebooks and jobs using *Workspace default* inherit its compute and libraries. Setting the default requires the workspace **Admin** role — already satisfied because `Invoke-FabricSetup` auto-grants the deploying identity Admin on every workspace.

> **Note:** This step provisions an **empty** environment and (optionally) sets it as the workspace default — it does not upload any libraries. Creating and referencing an empty environment does not require a publish. Uploading `.whl` packages (from Azure Artifacts) and publishing them is handled by `Invoke-FabricArtefactDeploy` as a separate step — see [Code-artefact deployment](#code-artefact-deployment).

---

#### `Invoke-FabricSetup`

Orchestrates the full provisioning pipeline. For each environment × workspace combination: resolves the name, creates the workspace (idempotent), grants the deploying identity Admin on the workspace, connects Git (in the designated Git environment only, for configured workspace types), provisions identity, enables monitoring, provisions a Spark Environment (and optionally sets it as the workspace default), and applies RBAC role assignments. After the per-workspace loop, creates or updates Fabric deployment pipelines for workspace types with pipelines enabled, then applies each pipeline's role assignments. Returns a structured results object.

> **Deploying identity auto-grant:** every workspace is granted the identity running the deployment the **Admin** role — idempotently, and independently of `-SkipRbac`. The identity (and its Entra **object id**, which Fabric role assignments require) is resolved with `Get-AzContext` plus `Get-AzADServicePrincipal`/`Get-AzADUser` (implemented directly in this module rather than depending on ZeroFailed.Deploy.Azure, to avoid pulling in a full deploy extension for a single identity lookup), so it works both as the Azure DevOps service principal and as a locally signed-in user. This guarantees the deployer can always see and re-manage the workspace on later runs — without it, a re-run hits `WorkspaceNameAlreadyExists` (names are unique tenant-wide) but cannot resolve the workspace via `GET /workspaces`. No topology config required.

```powershell
# Full run from config object
$result = Invoke-FabricSetup -Config $topology

# From saved JSON file
$result = Invoke-FabricSetup -ConfigPath "./topology.json"

# Target a single environment only
$result = Invoke-FabricSetup -Config $topology -Environments @("Dev")

# Dry run — no API calls made
$result = Invoke-FabricSetup -Config $topology -WhatIf

# Skip individual steps
$result = Invoke-FabricSetup -Config $topology -SkipGit
$result = Invoke-FabricSetup -Config $topology -SkipIdentity
$result = Invoke-FabricSetup -Config $topology -SkipMonitoring
$result = Invoke-FabricSetup -Config $topology -SkipEnvironment
$result = Invoke-FabricSetup -Config $topology -SkipRbac
$result = Invoke-FabricSetup -Config $topology -SkipPipeline
$result = Invoke-FabricSetup -Config $topology -SkipPipelineRbac
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipEnvironment -SkipRbac -SkipPipeline -SkipPipelineRbac
```

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `-Config` | `pscustomobject` | Topology config object from `New-FabricTopologyConfig` |
| `-ConfigPath` | `string` | Path to a JSON topology config file (alternative to `-Config`) |
| `-Environments` | `string[]` | Filter to a subset of environments. Defaults to all |
| `-SkipGit` | `switch` | Skip Git integration for all workspaces |
| `-SkipIdentity` | `switch` | Skip identity provisioning for all workspaces |
| `-SkipMonitoring` | `switch` | Skip monitoring enablement for all workspaces |
| `-SkipEnvironment` | `switch` | Skip Spark Environment provisioning for all workspaces |
| `-SkipRbac` | `switch` | Skip role assignment application for all workspaces |
| `-SkipPipeline` | `switch` | Skip deployment pipeline setup for all workspace types |
| `-SkipPipelineRbac` | `switch` | Skip deployment pipeline role assignment application for all workspace types |
| `-WhatIf` | `switch` | Simulate all operations; no API calls are made |

**Return value:**

```powershell
$result.Summary         # @{ Created=int; Skipped=int; Failed=int }
$result.Identities      # Array of identity entries — handoff for downstream Azure RBAC
$result.Monitoring      # Array of monitoring report entries
$result.Environments    # Array of environment provisioning report entries
$result.RoleAssignments # Array of role assignment report entries
$result.Pipelines       # Array of deployment pipeline report entries
$result.PipelineRoleAssignments # Array of pipeline role assignment report entries
$result.Failures        # Array of per-workspace/pipeline failure details
```

**Identity report structure** (one entry per provisioned identity):

```powershell
@{
    WorkspaceName            = "salesanalytics-Bronze [DEV]"
    WorkspaceId              = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    ServicePrincipalObjectId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    ApplicationId            = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

**Monitoring report structure** (one entry per workspace with monitoring enabled):

```powershell
@{
    WorkspaceName = "salesanalytics-Bronze [DEV]"
    WorkspaceId   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    Enabled       = $true
}
```

**Environment report structure** (a create entry per provisioned environment, plus a set-default entry when `-SetEnvironmentAsDefault` is used):

```powershell
# Environment create entry
@{
    WorkspaceName   = "salesanalytics-Bronze [DEV]"
    WorkspaceId     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    EnvironmentName = "salesanalytics-Bronze Env"
    EnvironmentId   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

# Set-as-workspace-default entry (only when -SetEnvironmentAsDefault)
@{
    WorkspaceName   = "salesanalytics-Bronze [DEV]"
    WorkspaceId     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    EnvironmentName = "salesanalytics-Bronze Env"
    Action          = "Set"   # Set | Skipped | whatif
}
```

**Role assignment report structure** (one entry per applied assignment):

```powershell
@{
    WorkspaceName = "salesanalytics-Bronze [DEV]"
    WorkspaceId   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    PrincipalId   = "aaaaaaaa-0000-0000-0000-000000000001"
    PrincipalType = "Group"
    Role          = "Contributor"
    Action        = "Created"   # Created | Updated | Skipped | WhatIf
}
```

**Pipeline report structure** (one entry per workspace type with pipelines enabled):

```powershell
@{
    PipelineName   = "salesanalytics-Bronze Pipeline"
    PipelineId     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    WorkspaceType  = "Bronze"
    StagesAssigned = 3        # number of stage-workspace assignments made this run
    Action         = "Created"  # Created | Updated | Skipped | WhatIf
}
```

**Pipeline role assignment report structure** (one entry per applied pipeline assignment):

```powershell
@{
    PipelineName  = "salesanalytics-Bronze Pipeline"
    PipelineId    = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    PrincipalId   = "dddddddd-0000-0000-0000-000000000004"
    PrincipalType = "Group"
    Role          = "Admin"
    Action        = "Created"   # Created | Skipped | WhatIf
}
```

**Working with results:**

```powershell
$result = Invoke-FabricSetup -Config $topology

# Summary
$result.Summary

# Export identity report to CSV for RBAC handoff
$result.Identities | ForEach-Object { [pscustomobject]$_ } |
    Export-Csv -Path "./identity-report.csv" -NoTypeInformation

# View monitoring report
$result.Monitoring | ForEach-Object { [pscustomobject]$_ } | Format-Table

# View environment report
$result.Environments | ForEach-Object { [pscustomobject]$_ } | Format-Table

# View role assignment report
$result.RoleAssignments | ForEach-Object { [pscustomobject]$_ } |
    Format-Table WorkspaceName, PrincipalId, Role, Action

# View pipeline report
$result.Pipelines | ForEach-Object { [pscustomobject]$_ } |
    Format-Table PipelineName, PipelineId, StagesAssigned, Action

# View pipeline role assignment report
$result.PipelineRoleAssignments | ForEach-Object { [pscustomobject]$_ } |
    Format-Table PipelineName, PrincipalId, Role, Action

# Check for failures
if ($result.Failures.Count -gt 0) {
    $result.Failures | ForEach-Object { [pscustomobject]$_ } | Format-List
}
```

---

#### `New-FabricWorkspace`

Creates a single Fabric workspace, skipping creation if a workspace with the same display name already exists. Normally called by `Invoke-FabricSetup`; can also be used directly.

```powershell
$ws = New-FabricWorkspace -DisplayName "salesanalytics-bronze-dev" -CapacityName "cap-dev"
$ws = New-FabricWorkspace -DisplayName "salesanalytics-bronze-dev" -CapacityName "cap-dev" -WhatIf
```

#### `Set-FabricGitIntegration`

Connects a workspace to a Git repository using the Fabric REST API (`POST /git/connect` + `POST /git/initializeConnection`). Uses `PreferWorkspace` as the initialisation strategy. HTTP 400 `WorkspaceAlreadyConnectedToGit` is treated as a no-op. Normally called by `Invoke-FabricSetup`.

#### `Enable-FabricWorkspaceIdentity`

Provisions a Workspace Identity (managed identity / service principal) for a workspace via the `MicrosoftFabricMgmt` module (`Add-FabricWorkspaceIdentity`). Checks for an existing identity first and skips provisioning if one is already present. Waits for the asynchronous provisioning operation to complete using the module's LRO tracking functions before returning the service principal details. Normally called by `Invoke-FabricSetup`.

#### `Enable-FabricWorkspaceMonitoring`

Verifies that workspace monitoring has been provisioned by checking for the presence of the Monitoring Eventhouse in the workspace items list (`GET /workspaces/{id}/items`). Returns success if found (idempotent).

> **Important — manual prerequisite:** There is no public Fabric REST API for provisioning the Monitoring Eventhouse. Before including a workspace type in `-EnableMonitoring`, you must first enable monitoring manually in the Fabric portal for each affected workspace: **Workspace Settings → Monitoring → +Eventhouse**. If the Monitoring Eventhouse is not found, `Enable-FabricWorkspaceMonitoring` throws a descriptive error with instructions.

Normally called by `Invoke-FabricSetup`.

#### `New-FabricEnvironment`

Creates a Fabric Spark Environment in a workspace (`POST /workspaces/{id}/environments`), skipping creation if an environment with the same display name already exists. An `EnvironmentDisplayNameAlreadyInUse` (HTTP 409) conflict is treated idempotently by resolving and returning the existing environment. Provisions an empty environment only — uploading libraries and publishing are handled separately. Normally called by `Invoke-FabricSetup`; can also be used directly.

```powershell
$env = New-FabricEnvironment -WorkspaceId $ws.id -DisplayName "salesanalytics-Bronze Env" -Token $token
```

#### `Set-FabricWorkspaceDefaultEnvironment`

Sets a Fabric environment as the workspace default via the Spark settings API (`PATCH /workspaces/{id}/spark/settings`), so notebooks and Spark job definitions using *Workspace default* inherit its compute and libraries. The environment is referenced by display name. Idempotent — reads the current settings first and skips the update if the default is already set to the requested environment. Requires the workspace **Admin** role. Normally called by `Invoke-FabricSetup` when `-SetEnvironmentAsDefault` is used; can also be used directly.

```powershell
$defaultResult = Set-FabricWorkspaceDefaultEnvironment -WorkspaceId $ws.id -WorkspaceName "salesanalytics-Bronze [DEV]" -EnvironmentName "salesanalytics-Bronze Env" -Token $token
```

#### `Set-FabricWorkspaceRoleAssignment`

Applies a single Entra Group, User, or Service Principal role assignment to a Fabric workspace using the role assignment API (`GET/POST/PATCH /workspaces/{id}/roleAssignments`). Idempotent — skips if the principal already holds the correct role, updates if the role has drifted, creates if not present. Normally called by `Invoke-FabricSetup`.

#### `Set-FabricDeploymentPipeline`

Creates or updates a Fabric deployment pipeline for a single workspace type. Each environment in the topology becomes a named stage. Workspaces are assigned to stages where they already exist; stages for environments whose workspaces have not yet been provisioned are left unassigned and can be assigned on a subsequent run.

Idempotent: if the pipeline already exists, only vacant stages are assigned. Stages already assigned to the correct workspace are skipped. Stages assigned to a different workspace emit a warning and are not touched (manual intervention required).

Pipeline naming convention: `{project}-{typeCode} Pipeline` — e.g. `salesanalytics-Bronze Pipeline`.

Normally called by `Invoke-FabricSetup`; can also be used directly.

```powershell
$pipelineResult = Set-FabricDeploymentPipeline -Config $topology -WorkspaceType 'Bronze' -Token $token
```

#### `Set-FabricDeploymentPipelineRoleAssignment`

Applies a single Entra Group, User, or Service Principal role assignment to a Fabric deployment pipeline using the deployment pipeline role assignment API (`GET/POST /deploymentPipelines/{id}/roleAssignments`). Idempotent — skips if the principal already has access, creates it if not present. Fabric deployment pipelines only support the `Admin` role, so `-Role` defaults to (and only accepts) `Admin`. Normally called by `Invoke-FabricSetup` after the pipeline is created; can also be used directly.

```powershell
$rbacResult = Set-FabricDeploymentPipelineRoleAssignment -PipelineId $pipelineResult.PipelineId -PipelineName $pipelineResult.PipelineName -PrincipalId $groupId -PrincipalType 'Group' -Token $token
```

#### `Test-FabricWorkspaceExists`

Returns the workspace object if a workspace with the given display name exists, or `$null` if not found. Used for idempotency checks.

```powershell
$existing = Test-FabricWorkspaceExists -DisplayName "salesanalytics-bronze-dev"
if ($existing) { "Exists: $($existing.id)" }
```

---

### Python library deployment

Once workspaces and their Spark Environments have been provisioned, `Invoke-FabricPythonLibraryDeploy` deploys a Python package (and its dependencies) into those environments' **custom libraries**. It is the counterpart to `Invoke-FabricSetup` and is intended to run **after** provisioning, usually as a **separate pipeline**.

**Design:**

- **Stages are owned by the calling pipeline.** One invocation targets a single stage (`-Stage`). Your ADO/CI pipeline defines the stages and calls the script once per stage — there is no stage loop inside the module.
- **Targets are automatic.** Every workspace in the topology with a Spark Environment enabled (`environment.enabled`) for the target stage (`environment.stages`, set via `-EnvironmentStages`) receives the package. Workspaces whose environment is not provisioned for that stage are skipped. There is no per-package on/off config.
- **The package is a runtime parameter.** `-PackageName` / `-PackageVersion` flow from the build, so the version isn't baked into the topology config. The topology is used only to resolve workspace and environment names.
- **Dependencies are resolved automatically.** `pip download` reads the package metadata from the feed and pulls the full transitive dependency closure — no dependency list is maintained anywhere.
- **Public and private dependencies are handled differently.** The closure is split: **private** (feed-only) packages are uploaded as **custom libraries**; **public** packages (resolvable on PyPI) are declared in a generated **`environment.yml`** and imported as **external libraries** for Fabric to resolve from PyPI directly. This keeps large public binary wheels (e.g. `deltalake`, ~50 MB) out of the custom-library upload path, whose size limit a big wheel exceeds with a server-side 500. Classification is automatic via a PyPI lookup per package, or explicit via `-PrivatePackageName`. **This requires the Fabric Spark environment to have outbound access to PyPI.**

**What it does, per invocation:**

1. Downloads `PackageName==PackageVersion` **and all dependencies** once, from the Azure Artifacts feed, via `Save-FabricLibraryPackage` (`pip download`).
2. Splits the closure into private (custom-library) and public (environment.yml) packages.
3. For each target workspace in the stage: resolves the workspace and its Spark Environment (both must already exist from provisioning).
4. Clears down any staged custom library that isn't part of the private set (`Remove-FabricEnvironmentLibrary`); imports the public `environment.yml` (`Import-FabricEnvironmentExternalLibraries`, which overrides the whole external set); uploads the private wheels (`Add-FabricEnvironmentLibrary`); and publishes (`Publish-FabricEnvironment`, a long-running operation).
5. **Idempotent:** if both the published custom libraries and the published external (public) libraries are exactly the desired set, upload and publish are skipped (unless `-Force`). A stale version published alongside the desired files counts as a difference, so it triggers a deploy that clears it down.

```powershell
# Log in, then deploy one stage (this is what the deployment pipeline runs per stage)
Connect-AzAccount -UseDeviceAuthentication



$result.Summary   # @{ Deployed=int; Skipped=int; Failed=int }
$result.Deployed | ForEach-Object { [pscustomobject]$_ } |
    Format-Table WorkspaceName, EnvironmentName, Action
```

**`Invoke-FabricPythonLibraryDeploy` parameters:**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `-Config` | `pscustomobject` | Yes* | — | Topology config object from `New-FabricTopologyConfig` |
| `-ConfigPath` | `string` | Yes* | — | Path to a JSON topology config file (alternative to `-Config`) |
| `-Stage` | `string` | Yes | — | The single stage/environment name (as in `config.environments`) to deploy into |
| `-PackageName` | `string` | Yes | — | Package (distribution) name to deploy |
| `-PackageVersion` | `string` | Yes | — | Exact package version to deploy |
| `-FeedOrganisation` | `string` | Yes | — | Azure DevOps organisation hosting the Artifacts feed |
| `-FeedProject` | `string` | Yes | — | Azure DevOps project hosting the feed |
| `-FeedName` | `string` | Yes | — | Azure Artifacts feed name |
| `-FeedToken` | `string` | Yes | — | Bearer token / PAT with Feed Reader access (e.g. `System.AccessToken`) |
| `-StagingPath` | `string` | No | temp dir | Directory to download packages into |
| `-ConstraintsPath` | `string` | No | — | Path to a pip constraints file pinning versions in the dependency closure |
| `-SkipDownload` | `switch` | No | Off | Use files already present in `-StagingPath` instead of running pip |
| `-Force` | `switch` | No | Off | Upload and publish even when the files are already published |
| `-ExtraIndexUrl` | `string` | No | PyPI | Secondary index for dependencies not in the feed |
| `-PythonExecutable` | `string` | No | `python` | Python executable used for the download |
| `-TargetPythonVersion` | `string` | No | `3.11` | Python version of the target Fabric runtime that wheels are resolved for |
| `-TargetPlatform` | `string` | No | `manylinux2014_x86_64` | Platform tag wheels are resolved for |
| `-PublishTimeoutSeconds` | `int` | No | `600` | Max seconds to wait for each environment publish |
| `-WhatIf` | `switch` | No | — | Simulate upload/publish; no changes are made |

*Provide either `-Config` or `-ConfigPath`.

Per-workspace failures are non-fatal and collected in `$result.Failures`; the function throws at the end if any workspace failed, so the pipeline step fails while still attempting every target.

> **Wheels are resolved for the Fabric runtime, not the build agent.** pip would otherwise select wheels matching the agent's interpreter — e.g. a `cp312` wheel on a Python 3.12 agent — and any dependency with a compiled C extension would then fail to import inside Fabric, *after* a successful upload and publish. `Save-FabricLibraryPackage` therefore passes `--only-binary=:all: --python-version <target> --implementation cp --abi cp<target> --platform <platform>`. Fabric **runtime 1.2 → Python 3.10**; **runtime 1.3 → Python 3.11** (the default, matching `-EnvironmentRuntimeVersion`). Set `-TargetPythonVersion '3.10'` if your environments use runtime 1.2.
>
> Two consequences: (1) `--only-binary=:all:` is mandatory whenever `--platform`/`--abi` are used, so a dependency that publishes **only an sdist** now fails the download rather than silently shipping an unusable artefact; (2) the download happens **once per invocation**, so all target workspaces in a stage must share a runtime version.

> **Feed authentication:** the feed is accessed via an authenticated pip index URL of the form `https://build:<token>@pkgs.dev.azure.com/{org}/{project}/_packaging/{feed}/pypi/simple/`. The token (`-FeedToken`) is never logged and is kept off the topology config — supply it at runtime from a pipeline secret / `System.AccessToken`. Dependencies not present in the feed are resolved from `-ExtraIndexUrl` (PyPI by default), so the feed needs upstream sources configured or the agent needs outbound access to PyPI.

> **Pinning dependency versions:** `--only-binary=:all:` means a dependency whose resolved version publishes no wheel for the target runtime fails the download. Where that happens (or where a transitive version needs holding back for other reasons), supply a pip [constraints file](https://pip.pypa.io/en/stable/user_guide/#constraints-files) via `-ConstraintsPath` / `$FabricConstraintsPath`. It lives in your repo alongside the topology config — this module ships no constraints of its own — and holds one requirement specifier per line, e.g. `cryptography==42.0.2`. Constraints only pin the version of a package *if* it is already in the dependency closure; they never add one. A path that does not exist is an error rather than a silent no-op, since the resolution would otherwise differ from the one intended.

**Building-block functions** (normally called by `Invoke-FabricPythonLibraryDeploy`, usable directly):

#### `Save-FabricLibraryPackage`

Runs `pip download <name>==<version>` against the Azure Artifacts feed, fetching the package plus its full dependency closure into a directory, and returns the downloaded files.

```powershell
$files = Save-FabricLibraryPackage -PackageName "mycompany.dataprep" -PackageVersion "1.4.2" `
    -FeedOrganisation "contoso" -FeedProject "Analytics" -FeedName "fabric-python" `
    -FeedToken $env:SYSTEM_ACCESSTOKEN -DestinationPath "./.packages"

# Pin transitive dependency versions with a constraints file
$files = Save-FabricLibraryPackage -PackageName "mycompany.dataprep" -PackageVersion "1.4.2" `
    -FeedOrganisation "contoso" -FeedProject "Analytics" -FeedName "fabric-python" `
    -FeedToken $env:SYSTEM_ACCESSTOKEN -DestinationPath "./.packages" `
    -ConstraintsPath "./fabric/constraints.txt"
```

#### `Add-FabricEnvironmentLibrary`

Uploads a single library file (`.whl`, `.tar.gz`, `.jar`, `.py`) to an environment's staging libraries via the GA "Upload custom library" API `POST /workspaces/{id}/environments/{id}/staging/libraries/{libraryName}` (raw `application/octet-stream` body). Files remain in staging until the environment is published. Note: Fabric returns a server-side 500 for larger wheels well under the documented 100 MB cap, so this path is used only for **private** packages — public dependencies go via `Import-FabricEnvironmentExternalLibraries` instead.

```powershell
Add-FabricEnvironmentLibrary -WorkspaceId $ws.id -EnvironmentId $env.id `
    -FilePath "./.packages/mycompany.dataprep-1.4.2-py3-none-any.whl" -Token $token
```

#### `Import-FabricEnvironmentExternalLibraries`

Imports an environment's external (public) libraries from a generated `environment.yml` via `POST /workspaces/{id}/environments/{id}/staging/libraries/importExternalLibraries`. The call overrides the whole external list, and Fabric resolves the declared packages from PyPI on publish. Used for public dependencies so large binary wheels never go through the size-limited custom-library upload.

```powershell
Import-FabricEnvironmentExternalLibraries -WorkspaceId $ws.id -EnvironmentId $env.id `
    -EnvironmentYml $yml -Token $token
```

#### `Remove-FabricEnvironmentLibrary`

Removes a single custom library file from an environment's staging libraries via `DELETE /workspaces/{id}/environments/{id}/staging/libraries?libraryToDelete={name}`. Staging starts as a copy of the published libraries, so removing a file here and then publishing is how a published library is retired. A 404 (the library isn't staged) is treated as success, so this is safe to call repeatedly.

```powershell
Remove-FabricEnvironmentLibrary -WorkspaceId $ws.id -EnvironmentId $env.id `
    -LibraryName "mycompany.dataprep-1.4.1-py3-none-any.whl" -Token $token
```

#### `Publish-FabricEnvironment`

Publishes an environment's staging changes (`POST /staging/publish`), waiting for the long-running operation to complete. If there are no pending staging changes, this is treated as an idempotent no-op.

```powershell
Publish-FabricEnvironment -WorkspaceId $ws.id -EnvironmentId $env.id -Token $token
```

#### `Get-FabricEnvironmentLibraries`

Returns the flat set of custom library file names on an environment — the published libraries by default, or the staging libraries with `-Staging`. With `-External` it instead returns the external (public) libraries as normalised `name==version` tokens. Used to decide, idempotently, whether the desired custom and external sets are already deployed.

```powershell
$published = Get-FabricEnvironmentLibraries -WorkspaceId $ws.id -EnvironmentId $env.id -Token $token
```

---

### Execution flow

```
Invoke-FabricSetup
├── _Get-FabricAuthToken        (Get-AzAccessToken for Fabric API)
├── Inject token into MicrosoftFabricMgmt internal auth context (bypasses interactive login)
├── _Get-FabricDeploymentIdentity  → deploying identity object id + type (Get-AzContext + Get-AzAD*)
│
└── For each environment × workspace:
    ├── [token refresh if < 5 min remaining]
    ├── _Resolve-WorkspaceName  → e.g. "salesanalytics-Bronze [DEV]"
    ├── Test-FabricWorkspaceExists  → GET /workspaces (paginated, exact displayName match)
    │   ├── exists  → skip creation, increment Skipped
    │   └── missing → New-FabricWorkspace (POST /workspaces; 409 → resolve existing), increment Created
    ├── Set-FabricWorkspaceRoleAssignment  (deploying identity → Admin; idempotent, independent of -SkipRbac)
    ├── Set-FabricGitIntegration    (unless -SkipGit; only when env=gitEnvironment and ws.git.enabled)
    │   ├── POST /git/connect
    │   └── POST /git/initializeConnection  [LRO polled if HTTP 202]
    ├── Enable-FabricWorkspaceIdentity  (unless -SkipIdentity or identity.enabled=false)
    │   ├── GET workspaces/{id}/managedIdentity  (idempotency check)
    │   ├── Add-FabricWorkspaceIdentity  → Get-FabricLongRunningOperation  (if not present)
    │   └── Get-FabricLongRunningOperationResult  → append to $result.Identities
    ├── Enable-FabricWorkspaceMonitoring  (unless -SkipMonitoring or monitoring.enabled=false)
    │   └── GET workspaces/{id}/items  → check for Monitoring Eventhouse
    │       ├── found   → append to $result.Monitoring
    │       └── missing → throw (manual portal setup required)
    ├── New-FabricEnvironment  (unless -SkipEnvironment, environment.enabled=false, or the environment is not in environment.stages)
    │   ├── _Resolve-FabricEnvironment → GET /environments (paginated, by displayName)
    │   ├── missing → POST /environments (409 → resolve existing)  → append to $result.Environments
    │   └── if environment.setAsWorkspaceDefault:
    │       └── Set-FabricWorkspaceDefaultEnvironment
    │           ├── GET /spark/settings  (idempotency check)
    │           ├── already default → skip
    │           └── else → PATCH /spark/settings  → append to $result.Environments
    └── For each role assignment in ws.rbac[env]:  (unless -SkipRbac or no assignments)
        └── Set-FabricWorkspaceRoleAssignment
            ├── GET workspaces/{id}/roleAssignments  (idempotency check)
            ├── same role → skip
            ├── different role → PATCH /roleAssignments/{id}
            └── not found → POST /roleAssignments  → append to $result.RoleAssignments
│
└── For each workspace type with pipeline.enabled=true:  (unless -SkipPipeline)
    └── Set-FabricDeploymentPipeline
        ├── Test-FabricWorkspaceExists per environment → build stageMap
        ├── GET /deploymentPipelines  (paginated, find by name)
        │   ├── not found → POST /deploymentPipelines  (stages defined at creation)
        │   └── found     → GET /deploymentPipelines/{id}/stages
        ├── For each vacant stage with a known workspace:
        │   └── POST /deploymentPipelines/{id}/stages/{stageId}/assignWorkspace
        │       → append to $result.Pipelines
        └── For each role assignment in ws.pipeline.roleAssignments:  (unless -SkipPipelineRbac or no assignments)
            └── Set-FabricDeploymentPipelineRoleAssignment
                ├── GET /deploymentPipelines/{id}/roleAssignments  (idempotency check)
                ├── principal present → skip
                └── not found → POST /deploymentPipelines/{id}/roleAssignments
                    → append to $result.PipelineRoleAssignments
```

---

### Common scenarios

**Dev-only rollout, then promote:**

```powershell
# Initial dev rollout
$result = Invoke-FabricSetup -Config $topology -Environments @("Dev")

# After validation, promote to test
$result = Invoke-FabricSetup -Config $topology -Environments @("Test")

# Full DTAP in one pass
$result = Invoke-FabricSetup -Config $topology
```

**Re-run safely (idempotent):**

```powershell
# Re-running does nothing destructive:
# existing workspaces → Skipped
# existing Git connections → logged as already connected (Dev only)
# existing identities → skipped, SP details still returned
# existing environments → skipped, workspace default only re-set if it has drifted
# existing role assignments with correct role → Skipped
# existing pipelines with correct stage assignments → Skipped
$result = Invoke-FabricSetup -Config $topology
```

**Skip individual steps:**

```powershell
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipEnvironment -SkipRbac -SkipPipeline
```

**Provision workspaces first, then wire up pipelines:**

```powershell
# Provision all workspaces across all environments
$result = Invoke-FabricSetup -Config $topology -SkipPipeline

# Once workspaces exist, set up deployment pipelines
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipEnvironment -SkipRbac
```

**Inspect resolved workspace names before provisioning:**

```powershell
Invoke-FabricSetup -Config $topology -WhatIf
```

---

### Running tests

Tests use [Pester](https://pester.dev/) and require no live Azure connection — all external calls are mocked.

```powershell
Install-Module Pester -Scope CurrentUser -Force
Invoke-Pester ./module -Output Detailed
```

The test suite covers:
- `_Resolve-WorkspaceName` — correct name generation, lowercasing, truncation, error cases
- `New-FabricTopologyConfig` — environment count, workspace count, capacity assignment, Git opt-in per workspace type (`-GitWorkspaceConfig`), single Git environment (`-GitEnvironment`), identity filtering, monitoring filtering, pipeline opt-in (`-EnablePipelines`), Spark Environment opt-in (`-EnableEnvironments`, `-SetEnvironmentAsDefault`, `-EnvironmentRuntimeVersion`), per-type Spark Environment stage scoping (`-EnvironmentStages`, defaulting, validation errors), RBAC role assignment rules (`-RoleAssignments`), pipeline role assignment rules (`-PipelineRoleAssignments`), `-OutputPath` JSON output, GitHub provider, validation errors
- `New-FabricEnvironment` — WhatIf, idempotent skip when present, create via POST, description in body, 409 conflict resolution, non-conflict error propagation
- `Set-FabricWorkspaceDefaultEnvironment` — WhatIf, PATCH body shape, custom runtime version, skip when default already matches
- `Set-FabricDeploymentPipeline` — WhatIf, create+assign all stages, skip when fully assigned, update vacant stages, skip missing workspaces gracefully, pagination across continuation tokens, API error propagation, report field correctness
- `Set-FabricDeploymentPipelineRoleAssignment` — WhatIf, Admin default, non-Admin role rejection, skip when principal already present, create via POST, principal type acceptance, API error propagation, report field correctness
- `Invoke-FabricSetup` — pipeline role assignment application, `-SkipPipelineRbac`, non-fatal pipeline RBAC failures, no RBAC attempt when pipeline setup fails, environment provisioning + set-as-default, `-SkipEnvironment`, non-fatal environment failures
- `_Invoke-FabricFileUpload` — multipart upload URL/headers, no manual Content-Type, missing-file guard, API error unwrap
- `Add-FabricEnvironmentLibrary` — staging-libraries endpoint, WhatIf no-op
- `Remove-FabricEnvironmentLibrary` — staging delete endpoint, library-name URL encoding, 404 treated as already removed, other API errors rethrown, WhatIf no-op
- `Publish-FabricEnvironment` — publish endpoint + timeout passthrough, "no pending changes" idempotent skip, error propagation, WhatIf
- `Get-FabricEnvironmentLibraries` — custom-library name flattening, published vs staging endpoint, empty/404 handling
- `Save-FabricLibraryPackage` — pip download invocation (package/version/dest/authenticated feed index), target-runtime wheel resolution (`--only-binary`/`--python-version`/`--abi`/`--platform`), CPython ABI tag derivation, malformed target version rejection, constraints-file pass-through/omission/missing-file error, destination creation, no-files and pip-failure errors
- `Invoke-FabricPythonLibraryDeploy` — targets only environment-enabled workspaces (and only those whose environment is enabled for the target stage), single download for many targets, uploads every file, clear-down of stale staged libraries (and retention of desired ones), deploy rather than skip when a stale version is published, idempotent skip when already published, `-Force` re-publish, non-fatal missing-workspace failure, unknown-stage error, `-SkipDownload`, runtime-target pass-through, constraints-file pass-through and missing-file error
- Module-level tests — manifest validation, export checks, private function isolation

---

### Module structure

```
ZeroFailed.Deploy.Fabric/
├── build.ps1                                      # InvokeBuild bootstrapper
├── GitVersion.yml                                 # Semantic versioning config
├── .zf/
│   └── config.ps1                                 # ZeroFailed build config
├── .github/
│   └── workflows/
│       └── build.yml                              # CI/CD pipeline
└── module/
    ├── ZeroFailed.Deploy.Fabric.psd1              # Module manifest (PS 7+); declares ZF extension
    │                                               # dependencies (ZeroFailed.Deploy.Common,
    │                                               # ZeroFailed.DevOps.Common) under PrivateData.ZeroFailed
    ├── ZeroFailed.Deploy.Fabric.psm1              # Auto-discovery module loader
    ├── ZeroFailed.Deploy.Fabric.module.tests.ps1  # Module-level Pester tests
    ├── functions/
    │   ├── _Get-FabricAuthToken.ps1               # Private: auth token + expiry check
    │   ├── _Get-FabricDeploymentIdentity.ps1      # Private: resolve deploying identity object id
    │   ├── _Invoke-FabricFileUpload.ps1           # Private: multipart file upload
    │   ├── _Invoke-FabricRestMethod.ps1           # Private: REST wrapper with LRO
    │   ├── _Invoke-PipDownload.ps1                # Private: mockable pip download shim
    │   ├── _Resolve-FabricEnvironment.ps1         # Private: resolve Spark Environment by name
    │   ├── _Resolve-WorkspaceName.ps1             # Private: naming convention engine
    │   ├── Add-FabricEnvironmentLibrary.ps1       # Python library deploy: upload library to staging
    │   ├── Add-FabricEnvironmentLibrary.Tests.ps1
    │   ├── Enable-FabricWorkspaceIdentity.ps1
    │   ├── Enable-FabricWorkspaceIdentity.Tests.ps1
    │   ├── Enable-FabricWorkspaceMonitoring.ps1
    │   ├── Enable-FabricWorkspaceMonitoring.Tests.ps1
    │   ├── Get-FabricEnvironmentLibraries.ps1     # Python library deploy: read published/staging libs
    │   ├── Get-FabricEnvironmentLibraries.Tests.ps1
    │   ├── Invoke-FabricPythonLibraryDeploy.ps1   # Python library deploy: orchestrator
    │   ├── Invoke-FabricPythonLibraryDeploy.Tests.ps1
    │   ├── Invoke-FabricSetup.ps1
    │   ├── Invoke-FabricSetup.Tests.ps1
    │   ├── New-FabricEnvironment.ps1
    │   ├── New-FabricEnvironment.Tests.ps1
    │   ├── New-FabricTopologyConfig.ps1
    │   ├── New-FabricTopologyConfig.Tests.ps1
    │   ├── New-FabricWorkspace.ps1
    │   ├── New-FabricWorkspace.Tests.ps1
    │   ├── Remove-FabricEnvironmentLibrary.ps1    # Python library deploy: remove staged library
    │   ├── Remove-FabricEnvironmentLibrary.Tests.ps1
    │   ├── Publish-FabricEnvironment.ps1          # Python library deploy: publish staging changes
    │   ├── Publish-FabricEnvironment.Tests.ps1
    │   ├── Save-FabricLibraryPackage.ps1          # Python library deploy: pip download from feed
    │   ├── Save-FabricLibraryPackage.Tests.ps1
    │   ├── Set-FabricDeploymentPipeline.ps1
    │   ├── Set-FabricDeploymentPipeline.Tests.ps1
    │   ├── Set-FabricDeploymentPipelineRoleAssignment.ps1
    │   ├── Set-FabricDeploymentPipelineRoleAssignment.Tests.ps1
    │   ├── Set-FabricGitIntegration.ps1
    │   ├── Set-FabricGitIntegration.Tests.ps1
    │   ├── Set-FabricWorkspaceDefaultEnvironment.ps1
    │   ├── Set-FabricWorkspaceDefaultEnvironment.Tests.ps1
    │   ├── Set-FabricWorkspaceRoleAssignment.ps1
    │   ├── Set-FabricWorkspaceRoleAssignment.Tests.ps1
    │   ├── Test-FabricWorkspaceExists.ps1
    │   └── Test-FabricWorkspaceExists.Tests.ps1
    └── tasks/
        ├── fabric.tasks.ps1                       # Invoke-Build tasks
        └── fabric.properties.ps1                  # Build-time properties
```
