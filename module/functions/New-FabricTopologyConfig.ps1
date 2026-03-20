function New-FabricTopologyConfig {
    <#
    .SYNOPSIS
        Generates a Fabric topology configuration object from input parameters.
    .DESCRIPTION
        Produces a structured config describing all workspaces, environments, naming convention,
        Git settings, and identity requirements. The output can be passed directly to
        Invoke-FabricSetup, or serialised to JSON for version control.

        Git integration is designed for a single environment (typically Dev) and is opt-in per
        workspace type. Each workspace type that needs Git specifies its own repository, folder,
        and branch via -GitWorkspaceConfig.
    .PARAMETER Project
        Project name used as the first segment of every workspace name (e.g. "SalesAnalytics").
        Casing is preserved as-is; only characters outside [A-Za-z0-9-] are replaced with hyphens.
    .PARAMETER WorkspaceTypes
        Array of workspace type names to provision. Valid values:
        Bronze, Silver, Gold, ETL, Storage, Reporting.
    .PARAMETER Environments
        Array of DTAP environment names. Valid values: Dev, Test, Acceptance, Production.
    .PARAMETER CapacityMap
        Hashtable mapping each environment name to its Fabric capacity name.
        E.g. @{ Dev="cap-dev"; Test="cap-test"; Acceptance="cap-acc"; Production="cap-prod" }
    .PARAMETER GitProvider
        Git provider: AzureDevOps or GitHub. Required when -GitWorkspaceConfig is specified.
    .PARAMETER GitOrganisation
        Azure DevOps organisation name (or GitHub owner name). Required when -GitWorkspaceConfig is specified.
    .PARAMETER GitProject
        Azure DevOps project name. Required when -GitProvider is AzureDevOps and -GitWorkspaceConfig is specified.
    .PARAMETER GitEnvironment
        The single environment name where Git integration is enabled (e.g. "Dev").
        Defaults to "Dev". Set to an empty string to disable Git for all workspaces.
    .PARAMETER GitWorkspaceConfig
        Hashtable keyed by workspace type name. Only types present here get Git integration.
        Each entry is a hashtable with:
          RepositoryName  (required) — the Git repository name
          RootFolder      (optional) — root folder within the repo; defaults to "fabric"
          Branch          (optional) — branch to connect; defaults to "main"
        E.g. @{
            ETL       = @{ RepositoryName = "salesanalytics-etl"; Branch = "develop" }
            Reporting = @{ RepositoryName = "salesanalytics-reporting"; RootFolder = "reporting" }
        }
    .PARAMETER EnableIdentity
        Array of workspace type names that should have Workspace Identity provisioned.
        Defaults to all workspace types.
    .PARAMETER EnableMonitoring
        Array of workspace type names that should have monitoring enabled.
        Defaults to no workspace types (opt-in).
    .PARAMETER RoleAssignments
        Array of role assignment rules to apply to workspaces. Each rule is a hashtable with:
          PrincipalId    (required) — Entra object ID of the group, user, or service principal
          PrincipalType  (required) — Group, User, or ServicePrincipal
          Role           (required) — Admin, Contributor, Member, or Viewer
          WorkspaceTypes (optional) — array of workspace type names this rule applies to; omit for all types
          Environments   (optional) — array of environment names this rule applies to; omit for all environments
        Each rule is resolved per workspace type and environment and stored in the topology config.
    .PARAMETER OutputPath
        Optional file path to write the generated config as JSON.
        If omitted, the config object is returned only.
    .EXAMPLE
        New-FabricTopologyConfig `
          -Project             "SalesAnalytics" `
          -WorkspaceTypes      @("ETL","Reporting") `
          -Environments        @("Dev","Test","Acceptance","Production") `
          -CapacityMap         @{ Dev="cap-dev"; Test="cap-test"; Acceptance="cap-acc"; Production="cap-prod" } `
          -GitProvider         "AzureDevOps" `
          -GitOrganisation     "contoso" `
          -GitProject          "SalesAnalytics" `
          -GitEnvironment      "Dev" `
          -GitWorkspaceConfig  @{
              ETL       = @{ RepositoryName = "salesanalytics-etl"; Branch = "develop" }
              Reporting = @{ RepositoryName = "salesanalytics-reporting" }
          } `
          -EnableIdentity      @("ETL") `
          -EnableMonitoring    @("ETL","Reporting") `
          -OutputPath          "./topology.json"
        # Produces workspace names like: SalesAnalytics-ETL [DEV], SalesAnalytics-Report [PROD]
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [ValidateSet('Bronze', 'Silver', 'Gold', 'ETL', 'Storage', 'Reporting')]
        [string[]]$WorkspaceTypes,

        [Parameter(Mandatory)]
        [ValidateSet('Dev', 'Test', 'Acceptance', 'Production')]
        [string[]]$Environments,

        [Parameter(Mandatory)]
        [hashtable]$CapacityMap,

        [ValidateSet('AzureDevOps', 'GitHub')]
        [string]$GitProvider,

        [string]$GitOrganisation,

        [string]$GitProject,

        [string]$GitEnvironment = 'Dev',

        [hashtable]$GitWorkspaceConfig,

        [string[]]$EnableIdentity,

        [string[]]$EnableMonitoring,

        [hashtable[]]$RoleAssignments,

        [string]$OutputPath
    )

    # Validate Git parameters when GitWorkspaceConfig is provided
    if ($GitWorkspaceConfig -and $GitWorkspaceConfig.Count -gt 0) {
        if (-not $GitProvider) {
            throw "-GitProvider is required when -GitWorkspaceConfig is specified."
        }
        if (-not $GitOrganisation) {
            throw "-GitOrganisation is required when -GitWorkspaceConfig is specified."
        }
        if ($GitProvider -eq 'AzureDevOps' -and -not $GitProject) {
            throw "-GitProject is required when -GitProvider is 'AzureDevOps'."
        }
        if ($GitEnvironment -and $GitEnvironment -notin $Environments) {
            throw "-GitEnvironment '$GitEnvironment' is not in the -Environments list."
        }

        # Validate each workspace type in GitWorkspaceConfig
        foreach ($wsType in $GitWorkspaceConfig.Keys) {
            if ($wsType -notin $WorkspaceTypes) {
                throw "-GitWorkspaceConfig contains workspace type '$wsType' which is not in -WorkspaceTypes."
            }
            if (-not $GitWorkspaceConfig[$wsType].RepositoryName) {
                throw "-GitWorkspaceConfig entry for '$wsType' must include 'RepositoryName'."
            }
        }
    }

    # Validate RoleAssignments rules
    $validPrincipalTypes = @('Group', 'User', 'ServicePrincipal')
    $validRoles          = @('Admin', 'Contributor', 'Member', 'Viewer')

    if ($RoleAssignments) {
        foreach ($rule in $RoleAssignments) {
            if (-not $rule.PrincipalId) {
                throw "Each -RoleAssignments entry must include 'PrincipalId'."
            }
            if ($rule.PrincipalType -notin $validPrincipalTypes) {
                throw "-RoleAssignments entry for '$($rule.PrincipalId)' has invalid PrincipalType '$($rule.PrincipalType)'. Valid values: $($validPrincipalTypes -join ', ')."
            }
            if ($rule.Role -notin $validRoles) {
                throw "-RoleAssignments entry for '$($rule.PrincipalId)' has invalid Role '$($rule.Role)'. Valid values: $($validRoles -join ', ')."
            }
            foreach ($wsType in @($rule.WorkspaceTypes)) {
                if ($wsType -and $wsType -notin $WorkspaceTypes) {
                    throw "-RoleAssignments entry for '$($rule.PrincipalId)' references workspace type '$wsType' which is not in -WorkspaceTypes."
                }
            }
            foreach ($envName in @($rule.Environments)) {
                if ($envName -and $envName -notin $Environments) {
                    throw "-RoleAssignments entry for '$($rule.PrincipalId)' references environment '$envName' which is not in -Environments."
                }
            }
        }
    }

    # Normalise project name — preserve casing, replace non-alphanumeric/hyphen chars
    $projectNorm = $Project -replace '[^a-zA-Z0-9\-]', '-' -replace '-{2,}', '-'

    # Fixed short-code maps — values define exact display casing in workspace names
    $typeShortCodes = @{
        Bronze    = 'Bronze'
        Silver    = 'Silver'
        Gold      = 'Gold'
        ETL       = 'ETL'
        Storage   = 'Storage'
        Reporting = 'Report'
    }
    $envShortCodes = @{
        Dev        = 'DEV'
        Test       = 'TEST'
        Acceptance = 'ACC'
        Production = 'PROD'
    }

    # Resolve EnableIdentity — default to all workspace types
    $identityTypes = if ($EnableIdentity) { $EnableIdentity } else { $WorkspaceTypes }

    # Resolve EnableMonitoring — default to no workspace types (opt-in)
    $monitoringTypes = if ($EnableMonitoring) { $EnableMonitoring } else { @() }

    # Build environments list
    $envList = foreach ($envName in $Environments) {
        $shortCode    = $envShortCodes[$envName]
        $capacityName = $CapacityMap[$envName]
        if (-not $capacityName) {
            throw "CapacityMap is missing an entry for environment '$envName'."
        }
        [pscustomobject]@{
            name         = $envName
            shortCode    = $shortCode
            capacityName = $capacityName
        }
    }

    # Build workspace list
    $workspaceList = foreach ($wsType in $WorkspaceTypes) {
        $typeCode      = $typeShortCodes[$wsType]
        $wsGitConfig   = if ($GitWorkspaceConfig) { $GitWorkspaceConfig[$wsType] } else { $null }
        $gitEnabled    = $null -ne $wsGitConfig -and -not [string]::IsNullOrEmpty($GitEnvironment)

        $gitBlock = if ($gitEnabled) {
            $repoName   = $wsGitConfig.RepositoryName
            $rootFolder = if ($wsGitConfig.RootFolder) { $wsGitConfig.RootFolder } else { 'fabric' }
            $branch     = if ($wsGitConfig.Branch)     { $wsGitConfig.Branch }     else { 'main' }

            if ($GitProvider -eq 'AzureDevOps') {
                [pscustomobject]@{
                    enabled          = $true
                    provider         = 'AzureDevOps'
                    organisationName = $GitOrganisation
                    projectName      = $GitProject
                    repositoryName   = $repoName
                    rootFolder       = $rootFolder
                    branch           = $branch
                }
            }
            else {
                [pscustomobject]@{
                    enabled        = $true
                    provider       = 'GitHub'
                    ownerName      = $GitOrganisation
                    repositoryName = $repoName
                    rootFolder     = $rootFolder
                    branch         = $branch
                }
            }
        }
        else {
            [pscustomobject]@{ enabled = $false }
        }

        $identityEnabled   = $wsType -in $identityTypes
        $monitoringEnabled = $wsType -in $monitoringTypes

        # Resolve role assignments per environment for this workspace type
        $rbacByEnv = [ordered]@{}
        foreach ($envName in $Environments) {
            $applicable = if ($RoleAssignments) {
                $RoleAssignments | Where-Object {
                    (-not $_.WorkspaceTypes -or $wsType -in $_.WorkspaceTypes) -and
                    (-not $_.Environments   -or $envName -in $_.Environments)
                }
            }
            else { @() }

            $rbacByEnv[$envName] = @(
                $applicable | ForEach-Object {
                    [pscustomobject]@{
                        principalId   = $_.PrincipalId
                        principalType = $_.PrincipalType
                        role          = $_.Role
                    }
                }
            )
        }

        [pscustomobject]@{
            id         = $typeCode
            type       = $wsType
            git        = $gitBlock
            identity   = [pscustomobject]@{ enabled = $identityEnabled }
            monitoring = [pscustomobject]@{ enabled = $monitoringEnabled }
            rbac       = $rbacByEnv
        }
    }

    # Assemble top-level config
    $resolvedGitEnvironment = if ($GitWorkspaceConfig -and $GitWorkspaceConfig.Count -gt 0) { $GitEnvironment } else { $null }

    $config = [pscustomobject]@{
        project           = $projectNorm
        gitEnvironment    = $resolvedGitEnvironment
        namingConvention  = [pscustomobject]@{
            template       = '{project}-{type} [{env}]'
            maxLength      = 64
            typeShortCodes = [pscustomobject]$typeShortCodes
            envShortCodes  = [pscustomobject]$envShortCodes
        }
        environments      = @($envList)
        workspaces        = @($workspaceList)
    }

    # Optionally write to file
    if ($OutputPath) {
        $json = $config | ConvertTo-Json -Depth 20
        Set-Content -Path $OutputPath -Value $json -Encoding UTF8
        Write-Verbose "Topology config written to: $OutputPath"
    }

    return $config
}
