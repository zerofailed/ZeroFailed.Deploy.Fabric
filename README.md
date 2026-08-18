# `ZeroFailed.Deploy.Fabric` — Microsoft Fabric Workspace Provisioner

A ZeroFailed extension module for provisioning Microsoft Fabric workspaces across DTAP environments. Workspaces are named from a convention, connected to Git, optionally provisioned with Workspace Identities, optionally configured with workspace monitoring, optionally have Entra-based RBAC role assignments applied, and optionally have Fabric deployment pipelines set up across environments — with their own Entra-based role assignments. All provisioning steps are idempotent and safe to re-run.

### Requirements

| Requirement | Details |
|---|---|
| PowerShell | 7.0+ |
| Az module | `Install-Module Az -Scope CurrentUser` |
| MicrosoftFabricMgmt module | `Install-Module MicrosoftFabricMgmt -Scope CurrentUser` |
| Azure login | `Connect-AzAccount -UseDeviceAuthentication` before running |

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
$FabricSkipRbac           = $false
$FabricSkipPipeline       = $false
$FabricSkipPipelineRbac   = $false
$FabricWhatIf             = $false
```

The module registers two Invoke-Build tasks:
- `ensureFabricModules` — registers Az.Accounts, Az.Resources and MicrosoftFabricMgmt with ZeroFailed.DevOps.Common's `RequiredPowerShellModules`, so `setupModules` installs/imports them (runs before `setupModules`)
- `provisionFabricWorkspaces` — runs `Invoke-FabricSetup` from the topology config (runs after `DeployCore`)

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

---

#### `Invoke-FabricSetup`

Orchestrates the full provisioning pipeline. For each environment × workspace combination: resolves the name, creates the workspace (idempotent), grants the deploying identity Admin on the workspace, connects Git (in the designated Git environment only, for configured workspace types), provisions identity, enables monitoring, and applies RBAC role assignments. After the per-workspace loop, creates or updates Fabric deployment pipelines for workspace types with pipelines enabled, then applies each pipeline's role assignments. Returns a structured results object.

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
$result = Invoke-FabricSetup -Config $topology -SkipRbac
$result = Invoke-FabricSetup -Config $topology -SkipPipeline
$result = Invoke-FabricSetup -Config $topology -SkipPipelineRbac
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipRbac -SkipPipeline -SkipPipelineRbac
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
| `-SkipRbac` | `switch` | Skip role assignment application for all workspaces |
| `-SkipPipeline` | `switch` | Skip deployment pipeline setup for all workspace types |
| `-SkipPipelineRbac` | `switch` | Skip deployment pipeline role assignment application for all workspace types |
| `-WhatIf` | `switch` | Simulate all operations; no API calls are made |

**Return value:**

```powershell
$result.Summary         # @{ Created=int; Skipped=int; Failed=int }
$result.Identities      # Array of identity entries — handoff for downstream Azure RBAC
$result.Monitoring      # Array of monitoring report entries
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
# existing role assignments with correct role → Skipped
# existing pipelines with correct stage assignments → Skipped
$result = Invoke-FabricSetup -Config $topology
```

**Skip individual steps:**

```powershell
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipRbac -SkipPipeline
```

**Provision workspaces first, then wire up pipelines:**

```powershell
# Provision all workspaces across all environments
$result = Invoke-FabricSetup -Config $topology -SkipPipeline

# Once workspaces exist, set up deployment pipelines
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipRbac
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
- `New-FabricTopologyConfig` — environment count, workspace count, capacity assignment, Git opt-in per workspace type (`-GitWorkspaceConfig`), single Git environment (`-GitEnvironment`), identity filtering, monitoring filtering, pipeline opt-in (`-EnablePipelines`), RBAC role assignment rules (`-RoleAssignments`), pipeline role assignment rules (`-PipelineRoleAssignments`), `-OutputPath` JSON output, GitHub provider, validation errors
- `Set-FabricDeploymentPipeline` — WhatIf, create+assign all stages, skip when fully assigned, update vacant stages, skip missing workspaces gracefully, pagination across continuation tokens, API error propagation, report field correctness
- `Set-FabricDeploymentPipelineRoleAssignment` — WhatIf, Admin default, non-Admin role rejection, skip when principal already present, create via POST, principal type acceptance, API error propagation, report field correctness
- `Invoke-FabricSetup` — pipeline role assignment application, `-SkipPipelineRbac`, non-fatal pipeline RBAC failures, no RBAC attempt when pipeline setup fails
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
    │   ├── _Invoke-FabricRestMethod.ps1           # Private: REST wrapper with LRO
    │   ├── _Resolve-WorkspaceName.ps1             # Private: naming convention engine
    │   ├── Enable-FabricWorkspaceIdentity.ps1
    │   ├── Enable-FabricWorkspaceIdentity.Tests.ps1
    │   ├── Enable-FabricWorkspaceMonitoring.ps1
    │   ├── Enable-FabricWorkspaceMonitoring.Tests.ps1
    │   ├── Invoke-FabricSetup.ps1
    │   ├── Invoke-FabricSetup.Tests.ps1
    │   ├── New-FabricTopologyConfig.ps1
    │   ├── New-FabricTopologyConfig.Tests.ps1
    │   ├── New-FabricWorkspace.ps1
    │   ├── New-FabricWorkspace.Tests.ps1
    │   ├── Set-FabricGitIntegration.ps1
    │   ├── Set-FabricGitIntegration.Tests.ps1
    │   ├── Set-FabricDeploymentPipeline.ps1
    │   ├── Set-FabricDeploymentPipeline.Tests.ps1
    │   ├── Set-FabricDeploymentPipelineRoleAssignment.ps1
    │   ├── Set-FabricDeploymentPipelineRoleAssignment.Tests.ps1
    │   ├── Set-FabricWorkspaceRoleAssignment.ps1
    │   ├── Set-FabricWorkspaceRoleAssignment.Tests.ps1
    │   ├── Test-FabricWorkspaceExists.ps1
    │   └── Test-FabricWorkspaceExists.Tests.ps1
    └── tasks/
        ├── fabric.tasks.ps1                       # Invoke-Build tasks
        └── fabric.properties.ps1                  # Build-time properties
```
