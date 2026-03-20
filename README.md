# `ZeroFailed.Deploy.Fabric` — Microsoft Fabric Workspace Provisioner

A ZeroFailed extension module for provisioning Microsoft Fabric workspaces across DTAP environments. Workspaces are named from a convention, connected to Git, optionally provisioned with Workspace Identities, optionally configured with workspace monitoring, and optionally have Entra-based RBAC role assignments applied. All provisioning steps are idempotent and safe to re-run.

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
$FabricWhatIf             = $false
```

The module registers two Invoke-Build tasks:
- `ensureFabricModules` — installs Az.Accounts and MicrosoftFabricMgmt if missing (runs before `setupModules`)
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
    -RoleAssignments     @(
        # All workspaces, all environments: read-only for the reporting group
        @{ PrincipalId = "aaaaaaaa-0000-0000-0000-000000000001"; PrincipalType = "Group"; Role = "Viewer" }
        # Bronze/Silver/Gold: contributors in Dev only
        @{ PrincipalId = "bbbbbbbb-0000-0000-0000-000000000002"; PrincipalType = "Group"; Role = "Contributor";
           WorkspaceTypes = @("Bronze", "Silver", "Gold"); Environments = @("Dev") }
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
    -RoleAssignments     @(
        @{ PrincipalId = "aaaaaaaa-..."; PrincipalType = "Group"; Role = "Viewer" }
        @{ PrincipalId = "bbbbbbbb-..."; PrincipalType = "Group"; Role = "Contributor";
           WorkspaceTypes = @("Bronze", "Silver", "Gold"); Environments = @("Dev") }
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
| `-RoleAssignments` | `hashtable[]` | No | None | Role assignment rules applied by workspace type and environment (see below) |
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

---

#### `Invoke-FabricSetup`

Orchestrates the full provisioning pipeline. For each environment × workspace combination: resolves the name, creates the workspace (idempotent), connects Git (in the designated Git environment only, for configured workspace types), provisions identity, enables monitoring, and applies RBAC role assignments. Returns a structured results object.

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
$result = Invoke-FabricSetup -Config $topology -SkipGit -SkipIdentity -SkipMonitoring -SkipRbac
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
| `-WhatIf` | `switch` | Simulate all operations; no API calls are made |

**Return value:**

```powershell
$result.Summary         # @{ Created=int; Skipped=int; Failed=int }
$result.Identities      # Array of identity entries — handoff for downstream Azure RBAC
$result.Monitoring      # Array of monitoring report entries
$result.RoleAssignments # Array of role assignment report entries
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
├── _Assert-Prerequisites       (checks Az.Accounts and MicrosoftFabricMgmt are installed)
├── _Get-FabricAuthToken        (Get-AzAccessToken for Fabric API)
├── Inject token into MicrosoftFabricMgmt internal auth context (bypasses interactive login)
│
└── For each environment × workspace:
    ├── [token refresh if < 5 min remaining]
    ├── _Resolve-WorkspaceName  → e.g. "salesanalytics-Bronze [DEV]"
    ├── Test-FabricWorkspaceExists
    │   ├── exists  → skip creation, increment Skipped
    │   └── missing → New-FabricWorkspace, increment Created
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
$result = Invoke-FabricSetup -Config $topology
```

**Skip individual steps:**

```powershell
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
- `New-FabricTopologyConfig` — environment count, workspace count, capacity assignment, Git opt-in per workspace type (`-GitWorkspaceConfig`), single Git environment (`-GitEnvironment`), identity filtering, monitoring filtering, RBAC role assignment rules (`-RoleAssignments`), `-OutputPath` JSON output, GitHub provider, validation errors
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
    ├── ZeroFailed.Deploy.Fabric.psd1              # Module manifest (PS 7+)
    ├── ZeroFailed.Deploy.Fabric.psm1              # Auto-discovery module loader
    ├── ZeroFailed.Deploy.Fabric.module.tests.ps1  # Module-level Pester tests
    ├── dependencies.psd1                          # ZeroFailed.Deploy.Common dependency
    ├── functions/
    │   ├── _Assert-Prerequisites.ps1              # Private: prereq validation
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
    │   ├── Set-FabricWorkspaceRoleAssignment.ps1
    │   ├── Set-FabricWorkspaceRoleAssignment.Tests.ps1
    │   ├── Test-FabricWorkspaceExists.ps1
    │   └── Test-FabricWorkspaceExists.Tests.ps1
    └── tasks/
        ├── fabric.tasks.ps1                       # Invoke-Build tasks
        └── fabric.properties.ps1                  # Build-time properties
```
