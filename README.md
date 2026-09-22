# `ZeroFailed.Deploy.Fabric` — Microsoft Fabric Workspace Provisioner

A ZeroFailed extension module for provisioning Microsoft Fabric workspaces across DTAP environments. Workspaces are named from a convention, connected to Git, optionally provisioned with Workspace Identities, optionally configured with workspace monitoring, optionally provisioned with a Fabric Spark Environment (set as the workspace default), optionally provisioned with an (empty) Fabric Variable Library, optionally have Entra-based RBAC role assignments applied, and optionally have Fabric deployment pipelines set up across environments — with their own Entra-based role assignments. All provisioning steps are idempotent and safe to re-run.

The module also handles **Python library deployment**: once workspaces and their Spark Environments have been provisioned, `Invoke-FabricPythonLibraryDeploy` downloads a Python package (`.whl`) and its full dependency closure from an Azure Artifacts feed and uploads them into the Spark Environments' custom libraries for a given stage. Provisioning and Python library deployment are designed to run as **two separate pipelines** — see [Python library deployment](#python-library-deployment).

**Deployment pipelines** span every environment, so they are configured by a separate entry point, `Invoke-FabricDeploymentPipelineSetup`, from the same topology config — typically in a dedicated stage that runs once each environment's workspaces have been provisioned. See [`Invoke-FabricDeploymentPipelineSetup`](#invoke-fabricdeploymentpipelinesetup).

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
$FabricEnvironment        = 'Dev'      # omit (or leave blank) to process all environments
$FabricSkipGit            = $false
$FabricSkipIdentity       = $false
$FabricSkipMonitoring     = $false
$FabricSkipEnvironment    = $false
$FabricSkipVariableLibrary = $false
$FabricSkipRbac           = $false
$FabricSkipManagedPrivateEndpoints = $false
$FabricSkipPipeline       = $false    # provisionFabricDeploymentPipelines task only
$FabricSkipPipelineRbac   = $false    # provisionFabricDeploymentPipelines task only
$FabricWhatIf             = $false
```

Every `$Fabric*` property above (and the Python library deployment ones below) can also be overridden via an identically-named environment variable — e.g. `$env:FabricEnvironment = 'Dev'` — without editing `.zf/config.ps1`, which is useful for varying behaviour between CI/CD and local runs (for example, setting `FabricEnvironment` per stage in a multi-stage ADO pipeline). An explicit assignment in `.zf/config.ps1` still takes priority over the environment variable.

The module registers these Invoke-Build tasks:
- `ensureFabricModules` — registers Az.Accounts, Az.Resources and MicrosoftFabricMgmt with ZeroFailed.DevOps.Common's `RequiredPowerShellModules`, so `setupModules` installs/imports them (runs before `setupModules`)
- `provisionFabricWorkspaces` — runs `Invoke-FabricSetup` from the topology config (runs after `DeployCore`)
- `provisionFabricDeploymentPipelines` — runs `Invoke-FabricDeploymentPipelineSetup` from the topology config (standalone; invoke from a dedicated stage once every environment's workspaces exist)
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
    -EnableVariableLibraries @("Bronze", "Silver", "Gold") `
    -VariableLibraryDefaultValues `
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
    ) `
    -AzureSubscriptionIds @{
        Dev        = "11111111-1111-1111-1111-111111111111"
        Test       = "11111111-1111-1111-1111-111111111111"
        Production = "22222222-2222-2222-2222-222222222222"
    } `
    -ManagedPrivateEndpoints @(
        # Every workspace type connects to its own stage's Key Vault (stages left out get no endpoint)
        @{ ResourceType = "KeyVault"
           Targets = @{
               Dev        = @{ ResourceGroup = "rg-sales-dev";  ResourceName = "kv-sales-dev" }
               Production = @{ ResourceGroup = "rg-sales-prod"; ResourceName = "kv-sales-prod" }
           } }
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

# 6c. Inspect the variable library report
$result.VariableLibraries | Format-Table WorkspaceName, VariableLibraryName, VariableLibraryId

# 7. Inspect the role assignment report
$result.RoleAssignments | Format-Table WorkspaceName, PrincipalId, Role, Action

# 7b. Inspect the managed private endpoint report (ConnectionStatus shows which still need approving)
$result.ManagedPrivateEndpoints | Format-Table WorkspaceName, Name, ConnectionStatus, Action

# 8. Once every environment's workspaces exist, set up the deployment pipelines
$pipelineResult = Invoke-FabricDeploymentPipelineSetup -Config $topology

# 9. Inspect the deployment pipeline and pipeline role assignment reports
$pipelineResult.Pipelines | Format-Table PipelineName, PipelineId, WorkspaceType, StagesAssigned, Action
$pipelineResult.PipelineRoleAssignments | Format-Table PipelineName, PrincipalId, Role, Action
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

Managed private endpoints are named after the Azure resource and sub-resource they target (e.g. `kv-sales-dev.vault`) rather than following this template — see [`-ManagedPrivateEndpoints`](#-managedprivateendpoints--managed-private-endpoints).

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
    -EnableVariableLibraries @("Bronze", "Silver", "Gold") `
    -VariableLibraryDefaultValues `
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
| `-EnableVariableLibraries` | `string[]` | No | None | Workspace types that should have an empty Fabric Variable Library provisioned (one library per workspace, in every environment) |
| `-VariableLibraryName` | `string` | No | `DefaultVariableLibrary` | Variable library display name, used as-is — the same in every workspace and environment |
| `-VariableLibraryStages` | `hashtable` | No | All environments | Per-workspace-type map restricting *which* environments get a Variable Library (see below) |
| `-VariableLibraryDefaultValues` | `switch` | No | Off | When set, variable libraries are populated with default variables and a value set per stage (see below) |
| `-RoleAssignments` | `hashtable[]` | No | None | Role assignment rules applied by workspace type and environment (see below) |
| `-PipelineRoleAssignments` | `hashtable[]` | No | None | Deployment pipeline role assignment rules applied by workspace type (see below) |
| `-ManagedPrivateEndpoints` | `hashtable[]` | No | None | Managed private endpoints to create per workspace type, with a target resource per environment (see below) |
| `-AzureSubscriptionIds` | `hashtable` | With `-ManagedPrivateEndpoints` | None | Environment name → Azure subscription ID holding that stage's resources |
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

Deployment pipelines have their own access control, separate from the workspaces they orchestrate. Each rule in `-PipelineRoleAssignments` declares which Entra principal should be granted access to a pipeline, with an optional filter for workspace type. A deployment pipeline spans all environments, so — unlike `-RoleAssignments` — these rules are **not** environment-scoped. Rules are resolved and stored on each workspace type's `pipeline` block; after a pipeline is created, `Invoke-FabricDeploymentPipelineSetup` applies them idempotently using the Fabric deployment pipeline role assignment API.

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

**`-ManagedPrivateEndpoints` — managed private endpoints:**

Managed private endpoints let a Fabric workspace's Spark workloads reach Azure resources that are closed to public network access, such as a Key Vault or storage account. Each rule in `-ManagedPrivateEndpoints` declares an endpoint for one or more workspace types, and — because each stage normally has its own copy of the resource — which resource it targets in each environment. The subscription is set once per environment with `-AzureSubscriptionIds`, since every resource in a stage shares it; the resource group and resource name are given on each rule, per environment. Rules are resolved and stored per workspace type and environment; `Invoke-FabricSetup` then creates them idempotently in each workspace.

| Key | Required | Description |
|---|---|---|
| `ResourceType` | Yes | The target resource type — see the table below — or any provider path such as `Microsoft.Search/searchServices` |
| `Targets` | Yes | Hashtable mapping environment name → `@{ ResourceGroup = "..."; ResourceName = "..." }`. An environment left out gets no endpoint |
| `SubResourceType` | Depends | Private link sub-resource. Defaults from `ResourceType`; required for `Storage` (`blob`, `dfs`, …). Pass it with a provider path when the type needs one |
| `WorkspaceTypes` | No | Array of workspace type names to apply this rule to; omit for all types |

| `ResourceType` | Provider path | Default sub-resource |
|---|---|---|
| `KeyVault` | `Microsoft.KeyVault/vaults` | `vault` |
| `Storage` | `Microsoft.Storage/storageAccounts` | — (required) |
| `SqlServer` | `Microsoft.Sql/servers` | `sqlServer` |
| `CosmosDb` | `Microsoft.DocumentDB/databaseAccounts` | `Sql` |
| `EventHubs` | `Microsoft.EventHub/namespaces` | `namespace` |

```powershell
-AzureSubscriptionIds @{
    Dev        = "11111111-1111-1111-1111-111111111111"
    Test       = "11111111-1111-1111-1111-111111111111"
    Production = "22222222-2222-2222-2222-222222222222"
} `
-ManagedPrivateEndpoints @(
    # Every workspace type reaches its own stage's Key Vault
    @{ ResourceType = "KeyVault"
       Targets = @{
           Dev        = @{ ResourceGroup = "rg-sales-dev";  ResourceName = "kv-sales-dev" }
           Test       = @{ ResourceGroup = "rg-sales-test"; ResourceName = "kv-sales-test" }
           Production = @{ ResourceGroup = "rg-sales-prod"; ResourceName = "kv-sales-prod" }
       } }

    # ETL reads the data lake over its dfs endpoint
    @{ ResourceType = "Storage"; SubResourceType = "dfs"; WorkspaceTypes = @("ETL")
       Targets = @{
           Dev        = @{ ResourceGroup = "rg-data-dev";  ResourceName = "stsalesdev" }
           Production = @{ ResourceGroup = "rg-data-prod"; ResourceName = "stsalesprod" }
       } }
)
# ETL in Dev gets two endpoints: kv-sales-dev.vault and stsalesdev.dfs
```

Each workspace's endpoints are stored in the topology config per environment — the environment's subscription and the resources it connects to, with the resource type's default sub-resource filled in:

```json
"managedPrivateEndpoints": {
  "Dev": {
    "subscriptionId": "11111111-1111-1111-1111-111111111111",
    "resources": [
      { "resourceName": "kv-sales-dev", "resourceGroup": "rg-sales-dev", "resourceType": "KeyVault", "subResourceType": "vault" },
      { "resourceName": "stsalesdev",   "resourceGroup": "rg-data-dev",  "resourceType": "Storage",  "subResourceType": "dfs" }
    ]
  },
  "Production": {
    "subscriptionId": "22222222-2222-2222-2222-222222222222",
    "resources": [ ... ]
  }
}
```

At provisioning time, `Invoke-FabricSetup` turns each resource into the managed private endpoint API call:

- **Target resource ID:** `/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/{resourceType's provider path}/{resourceName}`
- **Endpoint name:** `{resourceName}.{subResourceType}` in lower case — e.g. `kv-sales-dev.vault`, `stsalesdev.dfs` — or just the resource name for a type with no sub-resource (such as a Private Link Service given as a provider path). Fabric appends the workspace ID to the name when it creates the endpoint. Including the sub-resource lets one resource have an endpoint per sub-resource in the same workspace, such as a storage account's `blob` and `dfs`.
- **Approval request message:** `Fabric access from {workspace name}`, so the resource owner can see which workspace is asking.

`New-FabricTopologyConfig` resolves every target the same way when it builds the config, so it rejects unknown resource types, targets missing a resource group or name, environments with no subscription in `-AzureSubscriptionIds`, subscription IDs that aren't GUIDs, endpoint names over Fabric's 64-character limit, two rules resolving to the same endpoint in a workspace, and unknown environments or workspace types — before any API call is made.

> **Approval is a manual step.** Creating an endpoint only *requests* a private link connection. The owner of each target resource must approve it (Azure portal → the resource → **Networking** → **Private endpoint connections**) before it can be used. `Invoke-FabricSetup` reports each endpoint's `ConnectionStatus` and writes a warning on every run until it is `Approved`.

> **Endpoints can't be updated in place.** Fabric has no API to change an endpoint's target. If a rule's target or sub-resource changes, `Invoke-FabricSetup` reports a `ManagedPrivateEndpoint` failure rather than deleting the existing endpoint — deleting it would drop an approved connection. Delete the endpoint in the workspace's **Network security** settings and re-run to create it with the new target. Endpoints removed from the topology are likewise left in place.

> **Requirements:** the deploying identity needs the workspace **Admin** role (already granted by `Invoke-FabricSetup`), the workspace must be on a Fabric capacity that supports managed private endpoints, and the `Microsoft.Network` resource provider must be registered in the target resource's subscription.

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

**`-EnableVariableLibraries` — Variable Libraries:**

Fabric Variable Libraries hold configuration values (with a value set per stage) that other Fabric items reference. Variable Library provisioning is opt-in per workspace type via `-EnableVariableLibraries`; each enabled workspace gets one library named `-VariableLibraryName` (default `DefaultVariableLibrary`), in every environment unless restricted with `-VariableLibraryStages`.

The name is used as-is and is deliberately **the same in every workspace and environment** — each library lives in its own workspace, so there is no clash, and a stable name keeps references consistent as items are promoted between stages. It is stored as `variableLibrary.name` on each workspace in the config (a hand-written config that omits it gets the default). The name must follow Fabric's variable library naming rules (starts with a letter; only letters, numbers, underscores, hyphens and spaces; at most 256 characters), which `New-FabricTopologyConfig` checks up front.

```powershell
New-FabricTopologyConfig `
    -Project                     "salesanalytics" `
    -WorkspaceTypes              @("Bronze", "Silver", "Gold") `
    -Environments                @("Dev", "Test", "Production") `
    -CapacityMap                 @{ Dev="cap-dev"; Test="cap-test"; Production="cap-prod" } `
    -EnableVariableLibraries     @("Bronze", "Gold") `
    -VariableLibraryName         "Config" `
    -VariableLibraryStages       @{ Bronze = @("Dev") } `
    -VariableLibraryDefaultValues
```

All three are optional: the name defaults to `DefaultVariableLibrary`, Gold (omitted from `-VariableLibraryStages`) gets a library in every environment, and default variables are only populated with `-VariableLibraryDefaultValues`.

`-VariableLibraryStages` works like `-EnvironmentStages`: it is keyed by workspace type, each value is a list of environment names, keys must be listed in `-EnableVariableLibraries`, and a type that is omitted gets a library in every environment. It is stored as `variableLibrary.stages` on each workspace in the config.

Without `-VariableLibraryDefaultValues`, an **empty** Variable Library is provisioned — no variables or value sets are populated — and a library that already exists is left **completely untouched**.

**`-VariableLibraryDefaultValues` — default variables:** stored as `variableLibrary.defaultValues` on each workspace in the config. When enabled, each run also populates these String variables from the deployment:

| Variable | Value |
|---|---|
| `workspace_name` | The workspace display name, e.g. `salesanalytics-Bronze [DEV]` |
| `workspace_id` | The workspace ID |
| `workspace_identity_name` | The workspace identity's name (the workspace name); empty if the workspace has no identity |
| `workspace_identity_id` | The workspace identity's application (client) ID; empty if the workspace has no identity |

- The library's **default value set** only ever holds the placeholder `PLACEHOLDER - NO VALUE SET ACTIVE` — never a real value. If you see it, no stage value set is active.
- The real values go in a **value set for the stage being provisioned**, named by the environment short code (`DEV`, `TEST`, `PROD`, …). It is created if it does not exist, and made the library's **active** value set.
- Everything else in the library — other variables, other value sets, and other overrides in the stage's value set — is left untouched. The definition is only written back when one of the default variables or their stage values has changed, so re-runs are idempotent.
- The identity comes from this run's identity provisioning, or is read off the workspace (e.g. with `-SkipIdentity`).
- Failures are non-fatal and recorded with the step `VariableLibraryValues`; the library itself is still reported.

```json
"variableLibrary": {
  "enabled": true,
  "name": "DefaultVariableLibrary",
  "stages": ["Dev", "Test", "Production"],
  "defaultValues": true
}
```


---

#### `Invoke-FabricSetup`

Orchestrates the full provisioning pipeline. For each environment × workspace combination: resolves the name, creates the workspace (idempotent), grants the deploying identity Admin on the workspace, connects Git (in the designated Git environment only, for configured workspace types), provisions identity, enables monitoring, provisions a Spark Environment (and optionally sets it as the workspace default), provisions a Variable Library (with `defaultValues`, populating the default variables in the stage's value set and activating it), applies RBAC role assignments, and creates managed private endpoints. Returns a structured results object. Deployment pipelines are not configured here — they span every environment, so they are set up separately by [`Invoke-FabricDeploymentPipelineSetup`](#invoke-fabricdeploymentpipelinesetup).

> **Deploying identity auto-grant:** every workspace is granted the identity running the deployment the **Admin** role — idempotently, and independently of `-SkipRbac`. The identity (and its Entra **object id**, which Fabric role assignments require) is resolved with `Get-AzContext` plus `Get-AzADServicePrincipal`/`Get-AzADUser` (implemented directly in this module rather than depending on ZeroFailed.Deploy.Azure, to avoid pulling in a full deploy extension for a single identity lookup), so it works both as the Azure DevOps service principal and as a locally signed-in user. This guarantees the deployer can always see and re-manage the workspace on later runs — without it, a re-run hits `WorkspaceNameAlreadyExists` (names are unique tenant-wide) but cannot resolve the workspace via `GET /workspaces`. No topology config required.

```powershell
# Full run from config object
$result = Invoke-FabricSetup -Config $topology

# From saved JSON file
$result = Invoke-FabricSetup -ConfigPath "./topology.json"

# Target a single environment only (e.g. one ADO pipeline stage per environment)
$result = Invoke-FabricSetup -Config $topology -Environment "Dev"

# Dry run — no API calls made
$result = Invoke-FabricSetup -Config $topology -WhatIf

# Skip individual steps
$result = Invoke-FabricSetup -Config $topology -SkipGit
$result = Invoke-FabricSetup -Config $topology -SkipIdentity
$result = Invoke-FabricSetup -Config $topology -SkipMonitoring
$result = Invoke-FabricSetup -Config $topology -SkipEnvironment
$result = Invoke-FabricSetup -Config $topology -SkipVariableLibrary
$result = Invoke-FabricSetup -Config $topology -SkipRbac
$result = Invoke-FabricSetup -Config $topology -SkipManagedPrivateEndpoints
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipEnvironment -SkipVariableLibrary -SkipRbac -SkipManagedPrivateEndpoints
```

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `-Config` | `pscustomobject` | Topology config object from `New-FabricTopologyConfig` |
| `-ConfigPath` | `string` | Path to a JSON topology config file (alternative to `-Config`) |
| `-Environment` | `string` | Single environment name to process. Defaults to all environments in config |
| `-SkipGit` | `switch` | Skip Git integration for all workspaces |
| `-SkipIdentity` | `switch` | Skip identity provisioning for all workspaces |
| `-SkipMonitoring` | `switch` | Skip monitoring enablement for all workspaces |
| `-SkipEnvironment` | `switch` | Skip Spark Environment provisioning for all workspaces |
| `-SkipVariableLibrary` | `switch` | Skip Variable Library provisioning for all workspaces |
| `-SkipRbac` | `switch` | Skip role assignment application for all workspaces |
| `-SkipManagedPrivateEndpoints` | `switch` | Skip managed private endpoint creation for all workspaces |
| `-WhatIf` | `switch` | Simulate all operations; no API calls are made |

**Return value:**

```powershell
$result.Summary         # @{ Created=int; Skipped=int; Failed=int }
$result.Identities      # Array of identity entries — handoff for downstream Azure RBAC
$result.Monitoring      # Array of monitoring report entries
$result.Environments    # Array of environment provisioning report entries
$result.VariableLibraries # Array of variable library provisioning report entries
$result.RoleAssignments # Array of role assignment report entries
$result.ManagedPrivateEndpoints # Array of managed private endpoint report entries
$result.Failures        # Array of per-workspace failure details
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

**Variable library report structure** (one entry per workspace with a variable library enabled — whether newly created or already present):

```powershell
@{
    WorkspaceName       = "salesanalytics-Bronze [DEV]"
    WorkspaceId         = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    VariableLibraryName = "DefaultVariableLibrary"
    VariableLibraryId   = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    DefaultValues       = $null   # or, with variableLibrary.defaultValues, the Set-FabricVariableLibraryValues report:
    # @{ ValueSetName = "DEV"; Variables = @("workspace_name", ...);
    #    DefinitionAction = "Updated"; ActiveValueSetAction = "Set"; ... }   # Updated|Set / Skipped / WhatIf
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

**Managed private endpoint report structure** (one entry per configured endpoint):

```powershell
@{
    WorkspaceName               = "salesanalytics-Bronze [DEV]"
    WorkspaceId                 = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    Name                        = "kv-sales-dev.vault"
    EndpointId                  = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    TargetPrivateLinkResourceId = "/subscriptions/{sub-id}/resourceGroups/rg-sales-dev/providers/Microsoft.KeyVault/vaults/kv-sales-dev"
    TargetSubresourceType       = "vault"
    ProvisioningState           = "Succeeded"   # Provisioning | Succeeded | Updating | Deleting | Failed
    ConnectionStatus            = "Pending"     # Pending | Approved | Rejected | Disconnected ($null straight after creation)
    Action                      = "Created"     # Created | Skipped | WhatIf
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

# View variable library report
$result.VariableLibraries | ForEach-Object { [pscustomobject]$_ } | Format-Table

# View role assignment report
$result.RoleAssignments | ForEach-Object { [pscustomobject]$_ } |
    Format-Table WorkspaceName, PrincipalId, Role, Action

# List managed private endpoints still awaiting approval on their target resource
$result.ManagedPrivateEndpoints | ForEach-Object { [pscustomobject]$_ } |
    Where-Object ConnectionStatus -ne 'Approved' |
    Format-Table WorkspaceName, Name, TargetPrivateLinkResourceId, ConnectionStatus

# Check for failures
if ($result.Failures.Count -gt 0) {
    $result.Failures | ForEach-Object { [pscustomobject]$_ } | Format-List
}
```

---

#### `Invoke-FabricDeploymentPipelineSetup`

Creates or updates the Fabric deployment pipelines — one per workspace type listed in `-EnablePipelines`, with a stage per environment — assigns each environment's workspace to its stage, then applies each pipeline's role assignments (`-PipelineRoleAssignments`). It reads the same topology config as `Invoke-FabricSetup`; no additional config is needed.

Deployment pipelines span every environment, so this is deliberately separate from `Invoke-FabricSetup`. When each environment is provisioned in its own stage under its own service principal (keeping a security boundary between Dev, Test, Production, …), run pipeline setup in a **dedicated final stage** that depends on all of them — via the `provisionFabricDeploymentPipelines` task, which uses `$FabricTopologyConfigPath`, `$FabricSkipPipeline`, `$FabricSkipPipelineRbac` and `$FabricWhatIf`. All operations are idempotent, so the stage is safe to re-run.

```powershell
# From a config object
$pipelineResult = Invoke-FabricDeploymentPipelineSetup -Config $topology

# From saved JSON file
$pipelineResult = Invoke-FabricDeploymentPipelineSetup -ConfigPath "./topology.json"

# Dry run — no API calls made
$pipelineResult = Invoke-FabricDeploymentPipelineSetup -Config $topology -WhatIf

# Skip pipeline role assignments
$pipelineResult = Invoke-FabricDeploymentPipelineSetup -Config $topology -SkipPipelineRbac
```

**Access for the pipeline identity:**

The identity that runs pipeline setup must be able to see every environment's workspace for each pipeline-enabled type, and assigning a workspace to a pipeline stage requires the workspace **Admin** role. Grant this through the topology's existing `-RoleAssignments`, so that each environment's provisioning stage grants it as that environment's workspaces are created:

```powershell
-RoleAssignments @(
    # Deployment pipeline service principal: Admin on every pipeline-enabled workspace, in every environment
    @{ PrincipalId = "ffffffff-0000-0000-0000-000000000006"
       PrincipalType = "ServicePrincipal"; Role = "Admin"
       WorkspaceTypes = @("Bronze", "Silver", "Gold") }
)
```

The identity must also have access to any deployment pipeline that already exists — Fabric only lists pipelines the caller can access, so a pipeline created by a different identity (for example by an earlier version of `Invoke-FabricSetup`) is not found by name. Grant access to the existing pipeline before the first run; `-PipelineRoleAssignments` then keeps it in place.

**Missing workspaces fail the run:** if any environment's workspace for a pipeline-enabled type cannot be found — not yet provisioned, or not visible to the identity — that type's pipeline is not created or modified, and a `Pipeline` failure is recorded. Other workspace types are still processed. The `provisionFabricDeploymentPipelines` task throws if any failures were recorded, failing the stage.

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `-Config` | `pscustomobject` | Topology config object from `New-FabricTopologyConfig` |
| `-ConfigPath` | `string` | Path to a JSON topology config file (alternative to `-Config`) |
| `-SkipPipelineRbac` | `switch` | Skip deployment pipeline role assignment application for all workspace types |
| `-WhatIf` | `switch` | Simulate all operations; no API calls are made |

**Return value:**

```powershell
$pipelineResult.Summary                 # @{ Created=int; Updated=int; Skipped=int; Failed=int } — pipelines by action
$pipelineResult.Pipelines               # Array of deployment pipeline report entries
$pipelineResult.PipelineRoleAssignments # Array of pipeline role assignment report entries
$pipelineResult.Failures                # Array of per-workspace-type failure details (WorkspaceType, Step, Error)
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

```powershell
# View the pipeline and pipeline role assignment reports
$pipelineResult.Pipelines | ForEach-Object { [pscustomobject]$_ } |
    Format-Table PipelineName, PipelineId, StagesAssigned, Action
$pipelineResult.PipelineRoleAssignments | ForEach-Object { [pscustomobject]$_ } |
    Format-Table PipelineName, PrincipalId, Role, Action
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

#### `New-FabricVariableLibrary`

Creates an empty Fabric Variable Library in a workspace (`POST /workspaces/{id}/variableLibraries`, no definition — so no variables or value sets are populated). If a variable library with the same display name already exists it is returned **unchanged** — it is never overwritten or modified. An `ItemDisplayNameAlreadyInUse` (HTTP 409) conflict is treated idempotently by resolving and returning the existing library, and a long-running (HTTP 202) creation resolves the created library by name. Normally called by `Invoke-FabricSetup`; can also be used directly.

```powershell
$library = New-FabricVariableLibrary -WorkspaceId $ws.id -DisplayName "DefaultVariableLibrary" -Token $token
```

#### `Set-FabricVariableLibraryValues`

Sets variables and a value set on an existing Fabric Variable Library, preserving everything else. Each variable is added as a String variable if missing, with its default value (the default value set) set to a placeholder — `PLACEHOLDER - NO VALUE SET ACTIVE` unless `-DefaultValue` is given. The named value set is created if missing, its overrides for the variables are set to the supplied values, and it is made the library's active value set. The definition is read with `getDefinition` and written back in full with `updateDefinition` — only when something changed, and with unmodified parts passed through byte-for-byte. Normally called by `Invoke-FabricSetup` when `variableLibrary.defaultValues` is enabled; can also be used directly.

```powershell
Set-FabricVariableLibraryValues -WorkspaceId $ws.id -WorkspaceName "salesanalytics-Bronze [DEV]" `
    -VariableLibraryId $library.id -VariableLibraryName "DefaultVariableLibrary" `
    -ValueSetName "DEV" -Values ([ordered]@{ workspace_id = $ws.id }) -Token $token
```

#### `Set-FabricWorkspaceDefaultEnvironment`

Sets a Fabric environment as the workspace default via the Spark settings API (`PATCH /workspaces/{id}/spark/settings`), so notebooks and Spark job definitions using *Workspace default* inherit its compute and libraries. The environment is referenced by display name. Idempotent — reads the current settings first and skips the update if the default is already set to the requested environment. Requires the workspace **Admin** role. Normally called by `Invoke-FabricSetup` when `-SetEnvironmentAsDefault` is used; can also be used directly.

```powershell
$defaultResult = Set-FabricWorkspaceDefaultEnvironment -WorkspaceId $ws.id -WorkspaceName "salesanalytics-Bronze [DEV]" -EnvironmentName "salesanalytics-Bronze Env" -Token $token
```

#### `Set-FabricWorkspaceRoleAssignment`

Applies a single Entra Group, User, or Service Principal role assignment to a Fabric workspace using the role assignment API (`GET/POST/PATCH /workspaces/{id}/roleAssignments`). Idempotent — skips if the principal already holds the correct role, updates if the role has drifted, creates if not present. Normally called by `Invoke-FabricSetup`.

#### `Set-FabricManagedPrivateEndpoint`

Ensures a managed private endpoint exists in a workspace using the managed private endpoints API (`GET/POST /workspaces/{id}/managedPrivateEndpoints`). Idempotent — finds the endpoint by name (following continuation tokens), creates it if absent, and skips it if it already targets the same resource and sub-resource. Fabric can't update an endpoint in place, so one that exists with a *different* target is reported as an error rather than deleted and re-created. Returns the endpoint's provisioning state and connection (approval) status, and warns while the endpoint isn't yet usable. Requires the workspace **Admin** role. Normally called by `Invoke-FabricSetup`; can also be used directly.

```powershell
$mpe = Set-FabricManagedPrivateEndpoint -WorkspaceId $ws.id -WorkspaceName "salesanalytics-Bronze [DEV]" -Token $token `
    -Name "kv-sales-dev.vault" `
    -TargetPrivateLinkResourceId "/subscriptions/{sub-id}/resourceGroups/rg-sales-dev/providers/Microsoft.KeyVault/vaults/kv-sales-dev" `
    -TargetSubresourceType "vault"
```

#### `Set-FabricDeploymentPipeline`

Creates or updates a Fabric deployment pipeline for a single workspace type. Each environment in the topology becomes a named stage, and each environment's workspace is assigned to its stage. Every environment's workspace must already exist and be visible to the caller — if any cannot be found, it throws before creating or modifying the pipeline, so a partially-assigned pipeline is never left behind.

Idempotent: if the pipeline already exists, only vacant stages are assigned. Stages already assigned to the correct workspace are skipped. Stages assigned to a different workspace emit a warning and are not touched (manual intervention required).

Pipeline naming convention: `{project}-{typeCode} Pipeline` — e.g. `salesanalytics-Bronze Pipeline`.

Normally called by `Invoke-FabricDeploymentPipelineSetup`; can also be used directly.

```powershell
$pipelineResult = Set-FabricDeploymentPipeline -Config $topology -WorkspaceType 'Bronze' -Token $token
```

#### `Set-FabricDeploymentPipelineRoleAssignment`

Applies a single Entra Group, User, or Service Principal role assignment to a Fabric deployment pipeline using the deployment pipeline role assignment API (`GET/POST /deploymentPipelines/{id}/roleAssignments`). Idempotent — skips if the principal already has access, creates it if not present. Fabric deployment pipelines only support the `Admin` role, so `-Role` defaults to (and only accepts) `Admin`. Normally called by `Invoke-FabricDeploymentPipelineSetup` after the pipeline is created; can also be used directly.

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
    ├── New-FabricVariableLibrary  (unless -SkipVariableLibrary, variableLibrary.enabled=false, or the environment is not in variableLibrary.stages)
    │   ├── _Resolve-VariableLibraryName → variableLibrary.name, or "DefaultVariableLibrary" (same in every environment)
    │   ├── _Resolve-FabricVariableLibrary → GET /variableLibraries (paginated, by displayName)
    │   ├── exists  → leave as is
    │   ├── missing → POST /variableLibraries (empty; 409 → resolve existing)
    │   ├── append to $result.VariableLibraries
    │   └── if variableLibrary.defaultValues:
    │       └── Set-FabricVariableLibraryValues  (value set = environment short code, e.g. DEV)
    │           ├── identity: this run's identity report, else GET /workspaces/{id} (workspaceIdentity)
    │           ├── POST /variableLibraries/{id}/getDefinition
    │           ├── merge default variables (placeholder defaults) + stage value set overrides
    │           ├── changed → POST /variableLibraries/{id}/updateDefinition (full definition)
    │           └── active value set differs → PATCH /variableLibraries/{id} (activeValueSetName)
    ├── For each role assignment in ws.rbac[env]:  (unless -SkipRbac or no assignments)
    │   └── Set-FabricWorkspaceRoleAssignment
    │       ├── GET workspaces/{id}/roleAssignments  (idempotency check)
    │       ├── same role → skip
    │       ├── different role → PATCH /roleAssignments/{id}
    │       └── not found → POST /roleAssignments  → append to $result.RoleAssignments
    └── For each resource in ws.managedPrivateEndpoints[env].resources:  (unless -SkipManagedPrivateEndpoints or none configured)
        ├── _Resolve-ManagedPrivateEndpoint  → resource ID, name (e.g. "kv-sales-dev.vault") and sub-resource
        └── Set-FabricManagedPrivateEndpoint  (request message "Fabric access from {workspace name}")
            ├── GET workspaces/{id}/managedPrivateEndpoints  (paginated, find by name)
            ├── same target → skip
            ├── different target → throw (endpoints can't be updated in place)
            └── not found → POST /managedPrivateEndpoints  → append to $result.ManagedPrivateEndpoints
                (the connection then awaits approval on the target resource)

Invoke-FabricDeploymentPipelineSetup
├── _Get-FabricAuthToken        (Get-AzAccessToken for Fabric API)
│
└── For each workspace type with pipeline.enabled=true:
    ├── [token refresh if < 5 min remaining]
    ├── Set-FabricDeploymentPipeline
    │   ├── Test-FabricWorkspaceExists per environment → build stageMap
    │   │   └── any missing → throw before touching the pipeline  → append to $result.Failures
    │   ├── GET /deploymentPipelines  (paginated, find by name)
    │   │   ├── not found → POST /deploymentPipelines  (stages defined at creation)
    │   │   └── found     → GET /deploymentPipelines/{id}/stages
    │   └── For each vacant stage:
    │       └── POST /deploymentPipelines/{id}/stages/{stageId}/assignWorkspace
    │           → append to $result.Pipelines
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
$result = Invoke-FabricSetup -Config $topology -Environment "Dev"

# After validation, promote to test
$result = Invoke-FabricSetup -Config $topology -Environment "Test"

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
# existing variable libraries → left untouched (variables and value sets never overwritten)
# existing role assignments with correct role → Skipped
$result = Invoke-FabricSetup -Config $topology

# existing pipelines with correct stage assignments → Skipped
$pipelineResult = Invoke-FabricDeploymentPipelineSetup -Config $topology
```

**Skip individual steps:**

```powershell
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipEnvironment -SkipVariableLibrary -SkipRbac -SkipManagedPrivateEndpoints
```

**Provision each environment, then wire up pipelines:**

```powershell
# One run per environment (e.g. one ADO stage each, under that environment's service principal)
$result = Invoke-FabricSetup -Config $topology -Environment "Dev"
$result = Invoke-FabricSetup -Config $topology -Environment "Test"

# Once every environment's workspaces exist, set up the deployment pipelines (dedicated final stage)
$pipelineResult = Invoke-FabricDeploymentPipelineSetup -Config $topology
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
- `_Resolve-ManagedPrivateEndpoint` — resource ID from its parts, known types and their default sub-resources, provider paths, lower-case `{resource}.{sub-resource}` names, validation errors (unknown type, missing values, subscription GUID, Storage sub-resource, 64-character limit)
- `New-FabricTopologyConfig` — environment count, workspace count, capacity assignment, Git opt-in per workspace type (`-GitWorkspaceConfig`), single Git environment (`-GitEnvironment`), identity filtering, monitoring filtering, pipeline opt-in (`-EnablePipelines`), Spark Environment opt-in (`-EnableEnvironments`, `-SetEnvironmentAsDefault`, `-EnvironmentRuntimeVersion`), per-type Spark Environment stage scoping (`-EnvironmentStages`, defaulting, validation errors), Variable Library opt-in (`-EnableVariableLibraries`, `-VariableLibraryName` default/custom name and naming-rule validation, `-VariableLibraryStages` defaulting and validation errors, `-VariableLibraryDefaultValues`), RBAC role assignment rules (`-RoleAssignments`), pipeline role assignment rules (`-PipelineRoleAssignments`), managed private endpoint rules (`-ManagedPrivateEndpoints`, `-AzureSubscriptionIds`: per-environment subscription and resource entries, sub-resource defaults filled in, type scoping, JSON round trip, validation errors including duplicate endpoints in a workspace), `-OutputPath` JSON output, GitHub provider, validation errors
- `New-FabricEnvironment` — WhatIf, idempotent skip when present, create via POST, description in body, 409 conflict resolution, non-conflict error propagation
- `New-FabricVariableLibrary` — existing library returned with no create/update calls, WhatIf, empty create via POST (no definition), description in body, LRO resolution by name, 409 conflict resolution, non-conflict error propagation
- `_Resolve-VariableLibraryName` / `_Resolve-FabricVariableLibrary` — configured name or `DefaultVariableLibrary` default, naming-rule rejection; lookup by name with pagination
- `Set-FabricVariableLibraryValues` — WhatIf, empty library populated (placeholder defaults, new stage value set, activation), other variables/value sets/overrides preserved and untouched parts passed through unchanged, date strings not reformatted, real default values reset to the placeholder, stale overrides updated, no update/activation when up to date, activation only, missing parts added, getDefinition LRO result, API error propagation
- `_Get-FabricWorkspaceIdentity` — identity returned from the workspace, `$null` when there is none
- `Set-FabricWorkspaceDefaultEnvironment` — WhatIf, PATCH body shape, custom runtime version, skip when default already matches
- `Set-FabricDeploymentPipeline` — WhatIf, create+assign all stages, skip when fully assigned, update vacant stages, throw without touching the pipeline when a workspace is missing, pagination across continuation tokens, API error propagation, report field correctness
- `Set-FabricDeploymentPipelineRoleAssignment` — WhatIf, Admin default, non-Admin role rejection, skip when principal already present, create via POST, principal type acceptance, API error propagation, report field correctness
- `Invoke-FabricSetup` — deploying identity Admin and workspace identity Contributor grants, single-environment targeting, deployment pipelines not configured, environment provisioning + set-as-default, `-SkipEnvironment`, non-fatal environment failures, variable library provisioning per environment, stage scoping, `-SkipVariableLibrary`, older configs without a `variableLibrary` block, default name when none configured, default values off unless enabled, default values in a value set named by stage short code (environment name fallback), identity from this run or read off the workspace, empty identity values without an identity, non-fatal default values failures, non-fatal variable library failures, managed private endpoints (per-environment subscription and resources, request message naming the workspace, default sub-resource, `-SkipManagedPrivateEndpoints`, configs predating the block, in-memory dictionary shape, missing subscription, non-fatal failures)
- `Set-FabricManagedPrivateEndpoint` — WhatIf, create via POST (optional fields omitted or included), skip when the target matches (case-insensitive), drifted target or sub-resource rejected without a POST, approval and failed-provisioning warnings, pagination, StrictMode safety, API error propagation, name and request message length limits
- `Invoke-FabricDeploymentPipelineSetup` — pipeline-enabled types only, summary by action (WhatIf not counted), pipeline role assignment application, `-SkipPipelineRbac`, failed pipeline recorded without an RBAC attempt while other types continue, non-fatal pipeline RBAC failures, no-op warning when no pipelines are enabled, token refresh, `-ConfigPath`
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
    │   ├── _Get-FabricWorkspaceIdentity.ps1       # Private: read a workspace's identity
    │   ├── _Invoke-FabricFileUpload.ps1           # Private: multipart file upload
    │   ├── _Invoke-FabricRestMethod.ps1           # Private: REST wrapper with LRO
    │   ├── _Invoke-PipDownload.ps1                # Private: mockable pip download shim
    │   ├── _Resolve-FabricEnvironment.ps1         # Private: resolve Spark Environment by name
    │   ├── _Resolve-FabricVariableLibrary.ps1     # Private: resolve Variable Library by name
    │   ├── _Resolve-ManagedPrivateEndpoint.ps1    # Private: managed private endpoint resource ID, name and sub-resource
    │   ├── _Resolve-VariableLibraryName.ps1       # Private: Variable Library name default + validation
    │   ├── _Resolve-WorkspaceName.ps1             # Private: naming convention engine
    │   ├── Add-FabricEnvironmentLibrary.ps1       # Python library deploy: upload library to staging
    │   ├── Add-FabricEnvironmentLibrary.Tests.ps1
    │   ├── Enable-FabricWorkspaceIdentity.ps1
    │   ├── Enable-FabricWorkspaceIdentity.Tests.ps1
    │   ├── Enable-FabricWorkspaceMonitoring.ps1
    │   ├── Enable-FabricWorkspaceMonitoring.Tests.ps1
    │   ├── Get-FabricEnvironmentLibraries.ps1     # Python library deploy: read published/staging libs
    │   ├── Get-FabricEnvironmentLibraries.Tests.ps1
    │   ├── Invoke-FabricDeploymentPipelineSetup.ps1  # Deployment pipelines: orchestrator
    │   ├── Invoke-FabricDeploymentPipelineSetup.Tests.ps1
    │   ├── Invoke-FabricPythonLibraryDeploy.ps1   # Python library deploy: orchestrator
    │   ├── Invoke-FabricPythonLibraryDeploy.Tests.ps1
    │   ├── Invoke-FabricSetup.ps1
    │   ├── Invoke-FabricSetup.Tests.ps1
    │   ├── New-FabricEnvironment.ps1
    │   ├── New-FabricEnvironment.Tests.ps1
    │   ├── New-FabricTopologyConfig.ps1
    │   ├── New-FabricTopologyConfig.Tests.ps1
    │   ├── New-FabricVariableLibrary.ps1
    │   ├── New-FabricVariableLibrary.Tests.ps1
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
    │   ├── Set-FabricVariableLibraryValues.ps1
    │   ├── Set-FabricVariableLibraryValues.Tests.ps1
    │   ├── Set-FabricManagedPrivateEndpoint.ps1
    │   ├── Set-FabricManagedPrivateEndpoint.Tests.ps1
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
