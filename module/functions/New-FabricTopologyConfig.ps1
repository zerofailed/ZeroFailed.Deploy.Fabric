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
        Array of workspace type names to provision. Any name is accepted.
        Bronze, Silver, Gold, ETL, Storage, and Reporting have built-in display short codes;
        any other name uses the name itself (with whitespace removed) as its short code,
        unless overridden via -TypeShortCodes.
    .PARAMETER Environments
        Array of environment names. Any name is accepted.
        Dev, Test, Acceptance, and Production have built-in display short codes (DEV, TEST, ACC, PROD);
        any other name is uppercased with whitespace removed to form its short code,
        unless overridden via -EnvShortCodes.
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
    .PARAMETER EnablePipelines
        Array of workspace type names that should have a Fabric deployment pipeline created.
        Each pipeline spans all environments in order, with one stage per environment.
        Defaults to no workspace types (opt-in).
    .PARAMETER EnableEnvironments
        Array of workspace type names that should have a Fabric Spark Environment provisioned
        (one environment per workspace). Defaults to no workspace types (opt-in).
    .PARAMETER EnvironmentStages
        Optional hashtable keyed by workspace type name, restricting which environments (stages)
        get a Spark Environment for that type. Each value is an array of environment names.
        Only meaningful for types listed in -EnableEnvironments. A type that is environment-enabled
        but absent from this hashtable gets a Spark Environment in every environment (the default).
        E.g. @{ ETL = @('Dev','Production'); Reporting = @('Production') }
    .PARAMETER SetEnvironmentAsDefault
        When set, environment-enabled workspaces have their environment registered as the
        workspace default (so notebooks/jobs using "Workspace default" inherit it).
    .PARAMETER EnvironmentRuntimeVersion
        Spark runtime version used for provisioned environments. Default: 1.3.
    .PARAMETER EnableVariableLibraries
        Array of workspace type names that should have a Fabric Variable Library provisioned
        (one empty library per workspace, in every environment). Defaults to no workspace types (opt-in).
    .PARAMETER VariableLibraryName
        Display name for the provisioned variable libraries. The name is used as-is, and is the same in
        every workspace and environment. Default: 'DefaultVariableLibrary'.
    .PARAMETER VariableLibraryStages
        Optional hashtable keyed by workspace type name, restricting which environments (stages)
        get a Variable Library for that type. Each value is an array of environment names.
        Only meaningful for types listed in -EnableVariableLibraries. A type that is enabled but absent
        from this hashtable gets a Variable Library in every environment (the default).
        E.g. @{ ETL = @('Dev','Production') }
    .PARAMETER VariableLibraryDefaultValues
        When set, variable libraries are populated with default variables (workspace_name, workspace_id,
        workspace_identity_name, workspace_identity_id). Their default value set holds only a
        placeholder; the real values go in a value set per stage (named by the environment short code,
        e.g. DEV), which is activated.
    .PARAMETER RoleAssignments
        Array of role assignment rules to apply to workspaces. Each rule is a hashtable with:
          PrincipalId    (required) — Entra object ID of the group, user, or service principal
          PrincipalType  (required) — Group, User, or ServicePrincipal
          Role           (required) — Admin, Contributor, Member, or Viewer
          WorkspaceTypes (optional) — array of workspace type names this rule applies to; omit for all types
          Environments   (optional) — array of environment names this rule applies to; omit for all environments
        Each rule is resolved per workspace type and environment and stored in the topology config.
    .PARAMETER PipelineRoleAssignments
        Array of role assignment rules to apply to deployment pipelines. Each rule is a hashtable with:
          PrincipalId    (required) — Entra object ID of the group, user, or service principal
          PrincipalType  (required) — Group, User, or ServicePrincipal
          Role           (optional) — only 'Admin' is supported by Fabric deployment pipelines; defaults to 'Admin'
          WorkspaceTypes (optional) — array of workspace type names this rule applies to; omit for all types
        Pipelines span all environments, so these rules are not environment-scoped. Each rule is
        resolved per workspace type and stored on the workspace's pipeline block in the topology config.
    .PARAMETER ManagedPrivateEndpoints
        Array of managed private endpoint rules to create in workspaces. Each rule is a hashtable with:
          ResourceType          (required) — the target resource type: one of KeyVault, Storage, SqlServer,
                                             CosmosDb or EventHubs, or any provider path such as
                                             'Microsoft.KeyVault/vaults'
          Targets               (required) — hashtable mapping environment name to
                                             @{ ResourceGroup = '...'; ResourceName = '...' } for that stage;
                                             a stage left out of the map gets no endpoint
          SubResourceType       (optional) — private link sub-resource; defaults from ResourceType (e.g. 'vault'
                                             for KeyVault). Required for Storage ('blob', 'dfs', ...); pass it
                                             explicitly with a provider path when the type needs one
          WorkspaceTypes        (optional) — array of workspace type names this rule applies to; omit for all types
        Rules are resolved per workspace type and environment and stored in the topology config as
        managedPrivateEndpoints.<env> = { subscriptionId, resources = [{ resourceName, resourceGroup,
        resourceType, subResourceType }] }. At provisioning time the target resource ID is built as
        /subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/{provider path}/{resourceName},
        the endpoint is named '{resourceName}.{subResourceType}' in lower case (e.g. 'kv-sales-dev.vault'),
        and the approval request message is 'Fabric access from {workspace name}'. Endpoint names must fit
        Fabric's 64-character limit.
    .PARAMETER AzureSubscriptionIds
        Hashtable mapping environment name to the Azure subscription ID that holds that stage's resources,
        e.g. @{ Dev = '...'; Production = '...' }. Required for every environment a
        -ManagedPrivateEndpoints rule targets.
    .PARAMETER TypeShortCodes
        Optional hashtable mapping workspace type names to the display short code used in workspace names.
        Overrides built-in defaults and the generated fallback. E.g. @{ Lakehouse = 'LH' }.
    .PARAMETER EnvShortCodes
        Optional hashtable mapping environment names to the display short code used in workspace names.
        Overrides built-in defaults and the generated fallback. E.g. @{ Staging = 'STG' }.
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
        [ValidateNotNullOrEmpty()]
        [string[]]$WorkspaceTypes,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
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

        [string[]]$EnablePipelines,

        [hashtable[]]$PipelineRoleAssignments,

        [string[]]$EnableEnvironments,

        [hashtable]$EnvironmentStages,

        [switch]$SetEnvironmentAsDefault,

        [string]$EnvironmentRuntimeVersion = '1.3',

        [string[]]$EnableVariableLibraries,

        [ValidateNotNullOrEmpty()]
        [string]$VariableLibraryName = 'DefaultVariableLibrary',

        [hashtable]$VariableLibraryStages,

        [switch]$VariableLibraryDefaultValues,

        [hashtable]$TypeShortCodes,

        [hashtable]$EnvShortCodes,

        [hashtable[]]$ManagedPrivateEndpoints,

        [hashtable]$AzureSubscriptionIds,

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

    # Validate PipelineRoleAssignments rules — deployment pipelines only support the 'Admin' role
    if ($PipelineRoleAssignments) {
        foreach ($rule in $PipelineRoleAssignments) {
            if (-not $rule.PrincipalId) {
                throw "Each -PipelineRoleAssignments entry must include 'PrincipalId'."
            }
            if ($rule.PrincipalType -notin $validPrincipalTypes) {
                throw "-PipelineRoleAssignments entry for '$($rule.PrincipalId)' has invalid PrincipalType '$($rule.PrincipalType)'. Valid values: $($validPrincipalTypes -join ', ')."
            }
            if ($rule.ContainsKey('Role') -and $rule.Role -ne 'Admin') {
                throw "-PipelineRoleAssignments entry for '$($rule.PrincipalId)' has invalid Role '$($rule.Role)'. Fabric deployment pipelines only support the 'Admin' role."
            }
            foreach ($wsType in @($rule.WorkspaceTypes)) {
                if ($wsType -and $wsType -notin $WorkspaceTypes) {
                    throw "-PipelineRoleAssignments entry for '$($rule.PrincipalId)' references workspace type '$wsType' which is not in -WorkspaceTypes."
                }
            }
        }
    }

    # Validate ManagedPrivateEndpoints rules. Each target is checked by resolving it exactly as
    # Invoke-FabricSetup will (resource type, sub-resource, subscription ID, endpoint name length), so
    # a bad rule fails here rather than part-way through provisioning.
    if ($ManagedPrivateEndpoints) {
        foreach ($envName in @(if ($AzureSubscriptionIds) { $AzureSubscriptionIds.Keys })) {
            if ($envName -notin $Environments) {
                throw "-AzureSubscriptionIds references environment '$envName' which is not in -Environments."
            }
        }

        $ruleIndex = 0
        foreach ($rule in $ManagedPrivateEndpoints) {
            $ruleIndex++
            $ruleLabel = "-ManagedPrivateEndpoints entry $ruleIndex ($($rule.ResourceType))"

            if (-not $rule.Targets -or $rule.Targets -isnot [System.Collections.IDictionary] -or $rule.Targets.Count -eq 0) {
                throw "$ruleLabel must include 'Targets': a hashtable mapping environment names to @{ ResourceGroup = '...'; ResourceName = '...' }."
            }
            foreach ($envName in $rule.Targets.Keys) {
                if ($envName -notin $Environments) {
                    throw "$ruleLabel references environment '$envName' which is not in -Environments."
                }
                if (-not $AzureSubscriptionIds -or -not $AzureSubscriptionIds.ContainsKey($envName)) {
                    throw "$ruleLabel targets environment '$envName', which has no subscription in -AzureSubscriptionIds."
                }
                $target = $rule.Targets[$envName]
                if ($target -isnot [System.Collections.IDictionary]) {
                    throw "$ruleLabel has an invalid target for environment '$envName'. Supply @{ ResourceGroup = '...'; ResourceName = '...' }."
                }
                try {
                    _Resolve-ManagedPrivateEndpoint `
                        -SubscriptionId  $AzureSubscriptionIds[$envName] `
                        -ResourceGroup   $target.ResourceGroup `
                        -ResourceName    $target.ResourceName `
                        -ResourceType    $rule.ResourceType `
                        -SubResourceType $rule.SubResourceType | Out-Null
                }
                catch {
                    throw "$ruleLabel is invalid for environment '$envName': $($_.Exception.Message)"
                }
            }
            foreach ($wsType in @($rule.WorkspaceTypes)) {
                if ($wsType -and $wsType -notin $WorkspaceTypes) {
                    throw "$ruleLabel references workspace type '$wsType' which is not in -WorkspaceTypes."
                }
            }
        }

        # Fabric requires endpoint names to be unique in a workspace. Two rules resolving to the same
        # name (the same resource and sub-resource) would be the same endpoint, and the second would
        # be reported as drift of the first on every run.
        foreach ($wsType in $WorkspaceTypes) {
            foreach ($envName in $Environments) {
                $duplicate = $ManagedPrivateEndpoints |
                    Where-Object { (-not $_.WorkspaceTypes -or $wsType -in $_.WorkspaceTypes) -and $_.Targets.Contains($envName) } |
                    Group-Object -Property {
                        (_Resolve-ManagedPrivateEndpoint -SubscriptionId $AzureSubscriptionIds[$envName] `
                            -ResourceGroup $_.Targets[$envName].ResourceGroup -ResourceName $_.Targets[$envName].ResourceName `
                            -ResourceType $_.ResourceType -SubResourceType $_.SubResourceType).Name
                    } |
                    Where-Object { $_.Count -gt 1 } |
                    Select-Object -First 1
                if ($duplicate) {
                    throw "-ManagedPrivateEndpoints defines endpoint '$($duplicate.Name)' more than once for workspace type '$wsType' in environment '$envName'."
                }
            }
        }
    }

    # Normalise project name — preserve casing, replace non-alphanumeric/hyphen chars
    $projectNorm = $Project -replace '[^a-zA-Z0-9\-]', '-' -replace '-{2,}', '-'

    # Built-in short codes — values define exact display casing in workspace names
    $defaultTypeShortCodes = @{
        Bronze    = 'Bronze'
        Silver    = 'Silver'
        Gold      = 'Gold'
        ETL       = 'ETL'
        Storage   = 'Storage'
        Reporting = 'Report'
    }
    $defaultEnvShortCodes = @{
        Dev        = 'DEV'
        Test       = 'TEST'
        Acceptance = 'ACC'
        Production = 'PROD'
    }

    # Resolve a short code for each requested type/environment.
    # Precedence: caller override > built-in default > generated fallback.
    # Type fallback: name with whitespace removed (casing preserved).
    # Env fallback:  name uppercased with whitespace removed.
    $resolvedTypeShortCodes = @{}
    foreach ($wsType in $WorkspaceTypes) {
        $resolvedTypeShortCodes[$wsType] =
            if ($TypeShortCodes -and $TypeShortCodes.ContainsKey($wsType)) { $TypeShortCodes[$wsType] }
            elseif ($defaultTypeShortCodes.ContainsKey($wsType))           { $defaultTypeShortCodes[$wsType] }
            else                                                           { $wsType -replace '\s', '' }
    }
    $resolvedEnvShortCodes = @{}
    foreach ($envName in $Environments) {
        $resolvedEnvShortCodes[$envName] =
            if ($EnvShortCodes -and $EnvShortCodes.ContainsKey($envName)) { $EnvShortCodes[$envName] }
            elseif ($defaultEnvShortCodes.ContainsKey($envName))          { $defaultEnvShortCodes[$envName] }
            else                                                          { ($envName -replace '\s', '').ToUpper() }
    }

    # Resolve EnableIdentity — default to all workspace types
    $identityTypes = if ($EnableIdentity) { $EnableIdentity } else { $WorkspaceTypes }

    # Resolve EnableMonitoring — default to no workspace types (opt-in)
    $monitoringTypes = if ($EnableMonitoring) { $EnableMonitoring } else { @() }

    # Resolve EnablePipelines — default to no workspace types (opt-in)
    $pipelineTypes = if ($EnablePipelines) { $EnablePipelines } else { @() }

    # Resolve EnableEnvironments — default to no workspace types (opt-in)
    $environmentTypes = if ($EnableEnvironments) { $EnableEnvironments } else { @() }

    # Resolve EnableVariableLibraries — default to no workspace types (opt-in)
    $variableLibraryTypes = if ($EnableVariableLibraries) { $EnableVariableLibraries } else { @() }

    # Validate VariableLibraryName up front, so a name that breaks Fabric's naming rules fails here
    # rather than part-way through provisioning.
    $resolvedVariableLibraryName = _Resolve-VariableLibraryName -Name $VariableLibraryName

    # Validate EnvironmentStages — keys must be environment-enabled types, values must be known environments
    if ($EnvironmentStages) {
        foreach ($wsType in $EnvironmentStages.Keys) {
            if ($wsType -notin $WorkspaceTypes) {
                throw "-EnvironmentStages contains workspace type '$wsType' which is not in -WorkspaceTypes."
            }
            if ($wsType -notin $environmentTypes) {
                throw "-EnvironmentStages contains workspace type '$wsType' which does not have a Spark Environment enabled (see -EnableEnvironments)."
            }
            foreach ($envName in @($EnvironmentStages[$wsType])) {
                if ($envName -notin $Environments) {
                    throw "-EnvironmentStages entry for '$wsType' references environment '$envName' which is not in -Environments."
                }
            }
        }
    }

    # Validate VariableLibraryStages — keys must be variable-library-enabled types, values must be known environments
    if ($VariableLibraryStages) {
        foreach ($wsType in $VariableLibraryStages.Keys) {
            if ($wsType -notin $WorkspaceTypes) {
                throw "-VariableLibraryStages contains workspace type '$wsType' which is not in -WorkspaceTypes."
            }
            if ($wsType -notin $variableLibraryTypes) {
                throw "-VariableLibraryStages contains workspace type '$wsType' which does not have a Variable Library enabled (see -EnableVariableLibraries)."
            }
            foreach ($envName in @($VariableLibraryStages[$wsType])) {
                if ($envName -notin $Environments) {
                    throw "-VariableLibraryStages entry for '$wsType' references environment '$envName' which is not in -Environments."
                }
            }
        }
    }

    # Build environments list
    $envList = foreach ($envName in $Environments) {
        $shortCode    = $resolvedEnvShortCodes[$envName]
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
        $typeCode      = $resolvedTypeShortCodes[$wsType]
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

        $identityEnabled  = $wsType -in $identityTypes
        $monitoringEnabled = $wsType -in $monitoringTypes
        $pipelineEnabled  = $wsType -in $pipelineTypes
        $environmentEnabled = $wsType -in $environmentTypes

        # Resolve the environments (stages) that get a Spark Environment for this type.
        # Absent from -EnvironmentStages => all environments (previous behaviour).
        # Note: name deliberately differs from the $EnvironmentStages parameter — PowerShell
        # variable names are case-insensitive, so reusing it would clash with the typed param.
        $wsEnvironmentStages = @(
            if ($environmentEnabled) {
                if ($EnvironmentStages -and $EnvironmentStages.ContainsKey($wsType)) {
                    $EnvironmentStages[$wsType]
                }
                else { $Environments }
            }
        )

        # Resolve the environments (stages) that get a Variable Library for this type.
        # Absent from -VariableLibraryStages => all environments.
        $variableLibraryEnabled = $wsType -in $variableLibraryTypes
        $wsVariableLibraryStages = @(
            if ($variableLibraryEnabled) {
                if ($VariableLibraryStages -and $VariableLibraryStages.ContainsKey($wsType)) {
                    $VariableLibraryStages[$wsType]
                }
                else { $Environments }
            }
        )

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

        # Resolve pipeline role assignments for this workspace type (pipelines span all environments).
        # Only meaningful when the pipeline is enabled — otherwise there is no pipeline to assign to.
        $pipelineRbac = @(
            if ($pipelineEnabled -and $PipelineRoleAssignments) {
                $PipelineRoleAssignments |
                    Where-Object { -not $_.WorkspaceTypes -or $wsType -in $_.WorkspaceTypes } |
                    ForEach-Object {
                        [pscustomobject]@{
                            principalId   = $_.PrincipalId
                            principalType = $_.PrincipalType
                            role          = if ($_.ContainsKey('Role') -and $_.Role) { $_.Role } else { 'Admin' }
                        }
                    }
            }
        )

        # Managed private endpoints per environment for this workspace type: the environment's
        # subscription and the resources its workspace connects to. The endpoint name and full resource
        # ID are resolved from these at provisioning time. The sub-resource is stored with its default
        # applied, so the config shows exactly what will be requested.
        $mpeByEnv = [ordered]@{}
        foreach ($envName in $Environments) {
            $resources = @(
                if ($ManagedPrivateEndpoints) {
                    $ManagedPrivateEndpoints |
                        Where-Object { (-not $_.WorkspaceTypes -or $wsType -in $_.WorkspaceTypes) -and $_.Targets.Contains($envName) } |
                        ForEach-Object {
                            $target   = $_.Targets[$envName]
                            $resolved = _Resolve-ManagedPrivateEndpoint `
                                -SubscriptionId  $AzureSubscriptionIds[$envName] `
                                -ResourceGroup   $target.ResourceGroup `
                                -ResourceName    $target.ResourceName `
                                -ResourceType    $_.ResourceType `
                                -SubResourceType $_.SubResourceType

                            [pscustomobject]@{
                                resourceName    = $target.ResourceName
                                resourceGroup   = $target.ResourceGroup
                                resourceType    = $_.ResourceType
                                subResourceType = $resolved.TargetSubresourceType
                            }
                        }
                }
            )
            $mpeByEnv[$envName] = [pscustomobject]@{
                subscriptionId = if ($AzureSubscriptionIds -and $AzureSubscriptionIds.ContainsKey($envName)) { $AzureSubscriptionIds[$envName] } else { $null }
                resources      = $resources
            }
        }

        [pscustomobject]@{
            id         = $typeCode
            type       = $wsType
            git        = $gitBlock
            identity   = [pscustomobject]@{ enabled = $identityEnabled }
            monitoring = [pscustomobject]@{ enabled = $monitoringEnabled }
            pipeline   = [pscustomobject]@{ enabled = $pipelineEnabled; roleAssignments = $pipelineRbac }
            environment = [pscustomobject]@{
                enabled               = $environmentEnabled
                stages                = $wsEnvironmentStages
                setAsWorkspaceDefault = $environmentEnabled -and $SetEnvironmentAsDefault.IsPresent
                runtimeVersion        = $EnvironmentRuntimeVersion
            }
            variableLibrary = [pscustomobject]@{
                enabled       = $variableLibraryEnabled
                name          = $resolvedVariableLibraryName
                stages        = $wsVariableLibraryStages
                defaultValues = $variableLibraryEnabled -and $VariableLibraryDefaultValues.IsPresent
            }
            rbac       = $rbacByEnv
            managedPrivateEndpoints = $mpeByEnv
        }
    }

    # Assemble top-level config
    $resolvedGitEnvironment = if ($GitWorkspaceConfig -and $GitWorkspaceConfig.Count -gt 0) { $GitEnvironment } else { $null }

    $config = [pscustomobject]@{
        project           = $projectNorm
        gitEnvironment    = $resolvedGitEnvironment
        namingConvention  = [pscustomobject]@{
            template                = '{project}-{type} [{env}]'
            environmentNameTemplate = '{project}-{type} Env'
            maxLength               = 64
            typeShortCodes          = [pscustomobject]$resolvedTypeShortCodes
            envShortCodes           = [pscustomobject]$resolvedEnvShortCodes
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
