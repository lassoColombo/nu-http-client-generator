# Auto-generated client for gitlab v0.0.0
# Source: <spec>
# Auth: --token flag or $env.GITLAB_TOKEN

const BASE_URL = "https://example.com/graphql"
const DEFAULT_AUTH = "bearer"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o GITLAB_TOKEN | default "" }
  let scheme = ($auth_scheme | default "bearer")
  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }
  match $scheme {
    "none" => { {headers: {}, query: ""} }
    _ => { {headers: {Authorization: $"Bearer ($token_val)"}, query: ""} }
  }
}

# Serialize a single query parameter based on collection style
def serialize-qp [name: string, value: any, style: string]: nothing -> list<string> {
  if ($value == null) { return [] }
  let n = ($name | url encode)
  let is_list = ($value | describe | str starts-with "list")
  if ($value | describe | str starts-with "record") { return ($value | transpose k v | each { $"($n)[($in.k | into string | url encode)]=($in.v | into string | url encode)" }) }
  if not $is_list { return [$"($n)=($value | into string | url encode)"] }
  match $style {
    "multi" => { $value | each {|v| $"($n)=($v | into string | url encode)" } }
    "csv" => { let joined = ($value | each { $in | into string | url encode } | str join ","); [$"($n)=($joined)"] }
    "ssv" => { let joined = ($value | each { $in | into string | url encode } | str join "%20"); [$"($n)=($joined)"] }
    "tsv" => { let joined = ($value | each { $in | into string | url encode } | str join "%09"); [$"($n)=($joined)"] }
    "pipes" => { let joined = ($value | each { $in | into string | url encode } | str join "|"); [$"($n)=($joined)"] }
    "deepObject" => { $value | each {|v| $"($n)[]=($v | into string | url encode)" } }
    _ => { $value | each {|v| $"($n)=($v | into string | url encode)" } }
  }
}

# Build URL from base, path, and optional query string
def build-url [base: string, path: string, query?: string]: nothing -> string {
  let parsed = ($base | url parse | reject params)
  let full_path = if ($path | is-empty) { $parsed.path } else { [$parsed.path $path] | str join "/" | str replace --all --regex '/+' '/' }
  let result = ($parsed | upsert path $full_path)
  if ($query != null) and ($query | is-not-empty) { $result | upsert query $query | url join } else { $result | url join }
}

# Execute HTTP request with method dispatch
def do-request [method: string, url: string, auth: record, insecure: bool, raw: bool, max_time?: duration, allow_errors?: bool, content_type?: string, body?: any]: nothing -> any {
  let req_url = if ($auth.query | is-not-empty) { if ($url | str contains "?") { $"($url)&($auth.query)" } else { $"($url)?($auth.query)" } } else { $url }
  let timeout = ($max_time | default 30min)
  let ct = ($content_type | default "application/json")
  let resp = match $method {
    "get" => { http get --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url }
    "head" => { http head --headers $auth.headers --max-time $timeout --insecure=$insecure $req_url }
    "options" => { http options --headers $auth.headers --max-time $timeout --insecure=$insecure $req_url }
    "post" => { http post --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }
    "put" => { http put --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }
    "patch" => { http patch --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }
    "delete" => { if ($body | is-empty) { http delete --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } else { http delete --headers $auth.headers --content-type $ct --data $body --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } }
  }
  if ($method in ["head" "options"]) { return $resp }
  if $allow_errors { $resp } else if $resp.status == 204 { null } else if $resp.status >= 400 { error make --unspanned { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# Unwrap a GraphQL response: extract data.{field} and surface errors
def unwrap-graphql [resp: any, field: string] {
  if ($resp | describe) == "string" { return $resp }
  let errors = ($resp.errors? | default [])
  if ($errors | length) > 0 {
    let msgs = ($errors | each {|e| $e.message? | default "unknown error" } | str join "; ")
    error make --unspanned { msg: $"GraphQL error: ($msgs)" }
  }
  $resp.data? | get -o $field | default $resp.data?
}

def base-url-completer [] { ["https://example.com/graphql"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def order-by-completer [] { ["CREATED_AT" "ID" "NAME"] }
def sort-completer [] { ["ASC" "DESC"] }
def archived-completer [] { ["EXCLUDE" "INCLUDE" "ONLY"] }
def min-access-level-completer [] { ["ADMIN" "DEVELOPER" "GUEST" "MAINTAINER" "MINIMAL_ACCESS" "NO_ACCESS" "OWNER" "PLANNER" "REPORTER"] }
def visibility-level-completer [] { ["internal" "private" "public"] }
def duo-licensed-feature-completer [] { ["AGENTIC_CHAT" "AI_CATALOG" "AI_FEATURES"] }
def flow-config-type-completer [] { ["CHAT"] }
def item-type-completer [] { ["AGENT" "FLOW" "FOUNDATIONAL_AGENT" "THIRD_PARTY_FLOW"] }
def item-types-completer [] { ["AGENT" "FLOW" "FOUNDATIONAL_AGENT" "THIRD_PARTY_FLOW"] }
def sort-completer-1 [] { ["CATALOG_PRIORITY" "STAR_COUNT_ASC" "STAR_COUNT_DESC" "USAGE_COUNT_ASC" "USAGE_COUNT_DESC"] }
def input-conversationType-completer [] { ["DUO_CHAT" "DUO_CHAT_LEGACY" "DUO_CODE_REVIEW" "DUO_QUICK_CHAT"] }
def input-versionBump-completer [] { ["MAJOR" "MINOR" "PATCH"] }


# Find an abuse report. Introduced in GitLab 16.3: **Status**: Experiment.
#
# DEPRECATED
# operationId: abuseReport
@deprecated "**Status**: Experiment. Introduced in GitLab 16.3."
export def "query abuse-report" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  id: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id" }
    let body = {query: ("query($id: AbuseReportID!) { abuseReport(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "abuseReport" }
}

# List of permissions for fine-grained access tokens Introduced in GitLab 18.6: **Status**: Experiment.
#
# DEPRECATED
# operationId: accessTokenPermissions
@deprecated "**Status**: Experiment. Introduced in GitLab 18.6."
export def "query access-token-permissions" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {}
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "action boundaries category categoryName description name resource resourceDescription resourceName" }
    let body = {query: ("query { accessTokenPermissions { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "accessTokenPermissions" }
}

# Retrieve all active add-on purchases. This query can be used in GitLab.com and self-managed environments.
#
# operationId: addOnPurchases
export def "query add-on-purchases" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --namespace-id: string
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"namespaceId": $namespace_id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "assignedQuantity id name purchasedQuantity" }
    let body = {query: ("query($namespaceId: NamespaceID) { addOnPurchases(namespaceId: $namespaceId) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "addOnPurchases" }
}

# Find groups visible to the current admin. Introduced in GitLab 18.4: **Status**: Experiment.
#
# DEPRECATED
# operationId: adminGroups
@deprecated "**Status**: Experiment. Introduced in GitLab 18.4."
export def "query admin-groups" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --ids: string
  --top-level-only: oneof<nothing, bool>
  --owned-only: oneof<nothing, bool>
  --search: string
  --qp-sort: string
  --parent-path: string
  --all-available: oneof<nothing, bool>
  --marked-for-deletion-on: string
  --active: oneof<nothing, bool>
  --after: string
  --before: string
  --first: int
  --last: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"ids": $ids, "topLevelOnly": $top_level_only, "ownedOnly": $owned_only, "search": $search, "sort": $qp_sort, "parentPath": $parent_path, "allAvailable": $all_available, "markedForDeletionOn": $marked_for_deletion_on, "active": $active, "after": $after, "before": $before, "first": $first, "last": $last} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "count" }
    let body = {query: ("query($ids: [ID!], $topLevelOnly: Boolean, $ownedOnly: Boolean, $search: String, $sort: String, $parentPath: ID, $allAvailable: Boolean, $markedForDeletionOn: Date, $active: Boolean, $after: String, $before: String, $first: Int, $last: Int) { adminGroups(ids: $ids, topLevelOnly: $topLevelOnly, ownedOnly: $ownedOnly, search: $search, sort: $sort, parentPath: $parentPath, allAvailable: $allAvailable, markedForDeletionOn: $markedForDeletionOn, active: $active, after: $after, before: $before, first: $first, last: $last) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "adminGroups" }
}

# Finds a single admin custom role for the instance. Available only for GitLab Self-Managed. Introduced in GitLab 17.10: **Status**: Experiment.
#
# DEPRECATED
# operationId: adminMemberRole
@deprecated "**Status**: Experiment. Introduced in GitLab 17.10."
export def "query admin-member-role" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --assignable: oneof<nothing, bool>
  --id: string
  --ids: string
  --order-by: string@order-by-completer
  --qp-sort: string@sort-completer
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"assignable": $assignable, "id": $id, "ids": $ids, "orderBy": $order_by, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "createdAt description detailsPath editPath id name usersCount" }
    let body = {query: ("query($assignable: Boolean, $id: MemberRoleID, $ids: [MemberRoleID!], $orderBy: MemberRolesOrderBy, $sort: SortDirectionEnum) { adminMemberRole(assignable: $assignable, id: $id, ids: $ids, orderBy: $orderBy, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "adminMemberRole" }
}

# List of all admin customizable permissions. Introduced in GitLab 17.9: **Status**: Experiment.
#
# DEPRECATED
# operationId: adminMemberRolePermissions
@deprecated "**Status**: Experiment. Introduced in GitLab 17.9."
export def "query admin-member-role-permissions" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --after: string
  --before: string
  --first: int
  --last: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"after": $after, "before": $before, "first": $first, "last": $last} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($after: String, $before: String, $first: Int, $last: Int) { adminMemberRolePermissions(after: $after, before: $before, first: $first, last: $last) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "adminMemberRolePermissions" }
}

# Admin custom roles available for the instance. Available only for GitLab Self-Managed. Introduced in GitLab 17.10: **Status**: Experiment.
#
# DEPRECATED
# operationId: adminMemberRoles
@deprecated "**Status**: Experiment. Introduced in GitLab 17.10."
export def "query admin-member-roles" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --assignable: oneof<nothing, bool>
  --id: string
  --ids: string
  --order-by: string@order-by-completer
  --qp-sort: string@sort-completer
  --after: string
  --before: string
  --first: int
  --last: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"assignable": $assignable, "id": $id, "ids": $ids, "orderBy": $order_by, "sort": $qp_sort, "after": $after, "before": $before, "first": $first, "last": $last} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($assignable: Boolean, $id: MemberRoleID, $ids: [MemberRoleID!], $orderBy: MemberRolesOrderBy, $sort: SortDirectionEnum, $after: String, $before: String, $first: Int, $last: Int) { adminMemberRoles(assignable: $assignable, id: $id, ids: $ids, orderBy: $orderBy, sort: $sort, after: $after, before: $before, first: $first, last: $last) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "adminMemberRoles" }
}

# Find projects visible to the current admin. Introduced in GitLab 18.4: **Status**: Experiment.
#
# DEPRECATED
# operationId: adminProjects
@deprecated "**Status**: Experiment. Introduced in GitLab 18.4."
@deprecated --flag trending
@deprecated --flag with-duo-eligible
@deprecated --flag duo-licensed-feature
export def "query admin-projects" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --membership: oneof<nothing, bool>
  --search: string
  --search-namespaces: oneof<nothing, bool>
  --topics: string
  --personal: oneof<nothing, bool>
  --qp-sort: string
  --namespace-path: string
  --ids: string
  --full-paths: string
  --with-issues-enabled: oneof<nothing, bool>
  --with-merge-requests-enabled: oneof<nothing, bool>
  --archived: string@archived-completer
  --min-access-level: string@min-access-level-completer
  --programming-language-name: string
  --trending: oneof<nothing, bool>
  --aimed-for-deletion: oneof<nothing, bool>
  --not-aimed-for-deletion: oneof<nothing, bool>
  --marked-for-deletion-on: string
  --active: oneof<nothing, bool>
  --visibility-level: string@visibility-level-completer
  --last-repository-check-failed: oneof<nothing, bool>
  --include-hidden: oneof<nothing, bool>
  --with-duo-eligible: oneof<nothing, bool>
  --duo-licensed-feature: string@duo-licensed-feature-completer
  --after: string
  --before: string
  --first: int
  --last: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"membership": $membership, "search": $search, "searchNamespaces": $search_namespaces, "topics": $topics, "personal": $personal, "sort": $qp_sort, "namespacePath": $namespace_path, "ids": $ids, "fullPaths": $full_paths, "withIssuesEnabled": $with_issues_enabled, "withMergeRequestsEnabled": $with_merge_requests_enabled, "archived": $archived, "minAccessLevel": $min_access_level, "programmingLanguageName": $programming_language_name, "trending": $trending, "aimedForDeletion": $aimed_for_deletion, "notAimedForDeletion": $not_aimed_for_deletion, "markedForDeletionOn": $marked_for_deletion_on, "active": $active, "visibilityLevel": $visibility_level, "lastRepositoryCheckFailed": $last_repository_check_failed, "includeHidden": $include_hidden, "withDuoEligible": $with_duo_eligible, "duoLicensedFeature": $duo_licensed_feature, "after": $after, "before": $before, "first": $first, "last": $last} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "count" }
    let body = {query: ("query($membership: Boolean, $search: String, $searchNamespaces: Boolean, $topics: [String!], $personal: Boolean, $sort: String, $namespacePath: ID, $ids: [ID!], $fullPaths: [String!], $withIssuesEnabled: Boolean, $withMergeRequestsEnabled: Boolean, $archived: ProjectArchived, $minAccessLevel: AccessLevelEnum, $programmingLanguageName: String, $trending: Boolean, $aimedForDeletion: Boolean, $notAimedForDeletion: Boolean, $markedForDeletionOn: Date, $active: Boolean, $visibilityLevel: VisibilityLevelsEnum, $lastRepositoryCheckFailed: Boolean, $includeHidden: Boolean, $withDuoEligible: Boolean, $duoLicensedFeature: DuoLicensedFeature, $after: String, $before: String, $first: Int, $last: Int) { adminProjects(membership: $membership, search: $search, searchNamespaces: $searchNamespaces, topics: $topics, personal: $personal, sort: $sort, namespacePath: $namespacePath, ids: $ids, fullPaths: $fullPaths, withIssuesEnabled: $withIssuesEnabled, withMergeRequestsEnabled: $withMergeRequestsEnabled, archived: $archived, minAccessLevel: $minAccessLevel, programmingLanguageName: $programmingLanguageName, trending: $trending, aimedForDeletion: $aimedForDeletion, notAimedForDeletion: $notAimedForDeletion, markedForDeletionOn: $markedForDeletionOn, active: $active, visibilityLevel: $visibilityLevel, lastRepositoryCheckFailed: $lastRepositoryCheckFailed, includeHidden: $includeHidden, withDuoEligible: $withDuoEligible, duoLicensedFeature: $duoLicensedFeature, after: $after, before: $before, first: $first, last: $last) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "adminProjects" }
}

# Get flow configuration for an AI Catalog agent. Introduced in GitLab 18.4: **Status**: Experiment.
#
# DEPRECATED
# operationId: aiCatalogAgentFlowConfig
@deprecated "**Status**: Experiment. Introduced in GitLab 18.4."
export def "query ai-catalog-agent-flow-config" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  agent_version_id: string
  flow_config_type: string@flow-config-type-completer
]: any -> string {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"agentVersionId": $agent_version_id, "flowConfigType": $flow_config_type} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let body = {query: "query($agentVersionId: AiCatalogItemVersionID!, $flowConfigType: AiCatalogFlowConfigType!) { aiCatalogAgentFlowConfig(agentVersionId: $agentVersionId, flowConfigType: $flowConfigType) }", variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogAgentFlowConfig" }
}

# AI Catalog flows available to enable for a project. Introduced in GitLab 18.9: **Status**: Experiment.
#
# DEPRECATED
# operationId: aiCatalogAvailableFlowsForProject
@deprecated "**Status**: Experiment. Introduced in GitLab 18.9."
export def "query ai-catalog-available-flows-for-project" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  project_id: string
  --after: string
  --before: string
  --first: int
  --last: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"projectId": $project_id, "after": $after, "before": $before, "first": $first, "last": $last} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "count" }
    let body = {query: ("query($projectId: ProjectID!, $after: String, $before: String, $first: Int, $last: Int) { aiCatalogAvailableFlowsForProject(projectId: $projectId, after: $after, before: $before, first: $first, last: $last) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogAvailableFlowsForProject" }
}

# List of AI Catalog built-in tools. Introduced in GitLab 18.3: **Status**: Experiment.
#
# DEPRECATED
# operationId: aiCatalogBuiltInTools
@deprecated "**Status**: Experiment. Introduced in GitLab 18.3."
export def "query ai-catalog-built-in-tools" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --after: string
  --before: string
  --first: int
  --last: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"after": $after, "before": $before, "first": $first, "last": $last} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($after: String, $before: String, $first: Int, $last: Int) { aiCatalogBuiltInTools(after: $after, before: $before, first: $first, last: $last) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogBuiltInTools" }
}

# AI Catalog items configured for use. Introduced in GitLab 18.2: **Status**: Experiment.
#
# DEPRECATED
# operationId: aiCatalogConfiguredItems
@deprecated "**Status**: Experiment. Introduced in GitLab 18.2."
@deprecated --flag include-foundational-consumers
export def "query ai-catalog-configured-items" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --group-id: string
  --include-inherited: oneof<nothing, bool>
  --include-foundational-consumers: oneof<nothing, bool>
  --item-id: string
  --project-id: string
  --configurable-for-project-id: string
  --foundational-flow-reference: string
  --item-type: string@item-type-completer
  --item-types: string@item-types-completer
  --after: string
  --before: string
  --first: int
  --last: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"groupId": $group_id, "includeInherited": $include_inherited, "includeFoundationalConsumers": $include_foundational_consumers, "itemId": $item_id, "projectId": $project_id, "configurableForProjectId": $configurable_for_project_id, "foundationalFlowReference": $foundational_flow_reference, "itemType": $item_type, "itemTypes": $item_types, "after": $after, "before": $before, "first": $first, "last": $last} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "count" }
    let body = {query: ("query($groupId: GroupID, $includeInherited: Boolean, $includeFoundationalConsumers: Boolean, $itemId: AiCatalogItemID, $projectId: ProjectID, $configurableForProjectId: ProjectID, $foundationalFlowReference: String, $itemType: AiCatalogItemType, $itemTypes: [AiCatalogItemType!], $after: String, $before: String, $first: Int, $last: Int) { aiCatalogConfiguredItems(groupId: $groupId, includeInherited: $includeInherited, includeFoundationalConsumers: $includeFoundationalConsumers, itemId: $itemId, projectId: $projectId, configurableForProjectId: $configurableForProjectId, foundationalFlowReference: $foundationalFlowReference, itemType: $itemType, itemTypes: $itemTypes, after: $after, before: $before, first: $first, last: $last) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogConfiguredItems" }
}

# List of AI Catalog items, including foundational items. Introduced in GitLab 19.0: **Status**: Experiment.
#
# DEPRECATED
# operationId: aiCatalogCustomAndFoundationalItems
@deprecated "**Status**: Experiment. Introduced in GitLab 19.0."
export def "query ai-catalog-custom-and-foundational-items" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --item-types: string@item-types-completer
  --search: string
  --qp-sort: string@sort-completer-1
  --after: string
  --before: string
  --first: int
  --last: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"itemTypes": $item_types, "search": $search, "sort": $qp_sort, "after": $after, "before": $before, "first": $first, "last": $last} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($itemTypes: [AiCatalogItemType!], $search: String, $sort: AiCatalogItemsSort, $after: String, $before: String, $first: Int, $last: Int) { aiCatalogCustomAndFoundationalItems(itemTypes: $itemTypes, search: $search, sort: $sort, after: $after, before: $before, first: $first, last: $last) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogCustomAndFoundationalItems" }
}

# Find an AI Catalog item. Introduced in GitLab 18.2: **Status**: Experiment.
#
# DEPRECATED
# operationId: aiCatalogItem
@deprecated "**Status**: Experiment. Introduced in GitLab 18.2."
export def "query ai-catalog-item" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  id: string
  --show-soft-deleted: oneof<nothing, bool>
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "showSoftDeleted": $show_soft_deleted} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "createdAt description foundational foundationalFlowReference id isEnabledInManagedByProject itemType last30DayUsageCount name public softDeleted softDeletedAt starCount starred updatedAt verificationLevel" }
    let body = {query: ("query($id: AiCatalogItemID!, $showSoftDeleted: Boolean) { aiCatalogItem(id: $id, showSoftDeleted: $showSoftDeleted) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogItem" }
}

# Find a single AI Catalog item consumer by ID. Introduced in GitLab 18.5: **Status**: Experiment.
#
# DEPRECATED
# operationId: aiCatalogItemConsumer
@deprecated "**Status**: Experiment. Introduced in GitLab 18.5."
export def "query ai-catalog-item-consumer" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  id: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "enabled id pinnedVersionPrefix webPath" }
    let body = {query: ("query($id: AiCatalogItemConsumerID!) { aiCatalogItemConsumer(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogItemConsumer" }
}

# GraphQL mutation: achievementsAward
#
# DEPRECATED
# operationId: achievementsAward
@deprecated "**Status**: Experiment. Introduced in GitLab 15.10."
export def "mutation achievements-award" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-achievementId: string
  --input-userId: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "achievementId": $input_achievementId, "userId": $input_userId} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AchievementsAwardInput!) { achievementsAward(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "achievementsAward" }
}

# GraphQL mutation: achievementsCreate
#
# DEPRECATED
# operationId: achievementsCreate
@deprecated "**Status**: Experiment. Introduced in GitLab 15.8."
export def "mutation achievements-create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-namespaceId: string
  --input-name: string
  --input-avatar: path
  --input-description: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "namespaceId": $input_namespaceId, "name": $input_name, "avatar": $input_avatar, "description": $input_description} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AchievementsCreateInput!) { achievementsCreate(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "achievementsCreate" }
}

# GraphQL mutation: achievementsDelete
#
# DEPRECATED
# operationId: achievementsDelete
@deprecated "**Status**: Experiment. Introduced in GitLab 15.11."
export def "mutation achievements-delete" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-achievementId: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "achievementId": $input_achievementId} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AchievementsDeleteInput!) { achievementsDelete(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "achievementsDelete" }
}

# GraphQL mutation: achievementsRevoke
#
# DEPRECATED
# operationId: achievementsRevoke
@deprecated "**Status**: Experiment. Introduced in GitLab 15.10."
export def "mutation achievements-revoke" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-userAchievementId: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "userAchievementId": $input_userAchievementId} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AchievementsRevokeInput!) { achievementsRevoke(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "achievementsRevoke" }
}

# GraphQL mutation: achievementsUpdate
#
# DEPRECATED
# operationId: achievementsUpdate
@deprecated "**Status**: Experiment. Introduced in GitLab 15.11."
export def "mutation achievements-update" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-achievementId: string
  --input-name: string
  --input-avatar: path
  --input-description: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "achievementId": $input_achievementId, "name": $input_name, "avatar": $input_avatar, "description": $input_description} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AchievementsUpdateInput!) { achievementsUpdate(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "achievementsUpdate" }
}

# GraphQL mutation: addProjectToSecurityDashboard
#
# operationId: addProjectToSecurityDashboard
export def "mutation add-project-to-security-dashboard" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-id: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "id": $input_id} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AddProjectToSecurityDashboardInput!) { addProjectToSecurityDashboard(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "addProjectToSecurityDashboard" }
}

# GraphQL mutation: adminRolesLdapSync
#
# DEPRECATED
# operationId: adminRolesLdapSync
@deprecated "**Status**: Experiment. Introduced in GitLab 18.0."
export def "mutation admin-roles-ldap-sync" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors success" }
    let body = {query: ("mutation($input: AdminRolesLdapSyncInput!) { adminRolesLdapSync(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "adminRolesLdapSync" }
}

# GraphQL mutation: adminSidekiqQueuesDeleteJobs
#
# operationId: adminSidekiqQueuesDeleteJobs
export def "mutation admin-sidekiq-queues-delete-jobs" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-organizationId: string
  --input-user: string
  --input-userId: string
  --input-glUserId: string
  --input-scopedUser: string
  --input-scopedUserId: string
  --input-project: string
  --input-rootNamespace: string
  --input-clientId: string
  --input-callerId: string
  --input-remoteIp: string
  --input-jobId: string
  --input-pipelineId: string
  --input-relatedClass: string
  --input-featureCategory: string
  --input-artifactSize: string
  --input-artifactUsedCdn: string
  --input-artifactsDependenciesSize: string
  --input-artifactsDependenciesCount: string
  --input-rootCallerId: string
  --input-mergeActionStatus: string
  --input-bulkImportEntityId: string
  --input-sidekiqDestinationShardRedis: string
  --input-kubernetesAgentId: string
  --input-subscriptionPlan: string
  --input-aiResource: string
  --input-policySyncConfigId: string
  --input-workerClass: string
  --input-queueName: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "organizationId": $input_organizationId, "user": $input_user, "userId": $input_userId, "glUserId": $input_glUserId, "scopedUser": $input_scopedUser, "scopedUserId": $input_scopedUserId, "project": $input_project, "rootNamespace": $input_rootNamespace, "clientId": $input_clientId, "callerId": $input_callerId, "remoteIp": $input_remoteIp, "jobId": $input_jobId, "pipelineId": $input_pipelineId, "relatedClass": $input_relatedClass, "featureCategory": $input_featureCategory, "artifactSize": $input_artifactSize, "artifactUsedCdn": $input_artifactUsedCdn, "artifactsDependenciesSize": $input_artifactsDependenciesSize, "artifactsDependenciesCount": $input_artifactsDependenciesCount, "rootCallerId": $input_rootCallerId, "mergeActionStatus": $input_mergeActionStatus, "bulkImportEntityId": $input_bulkImportEntityId, "sidekiqDestinationShardRedis": $input_sidekiqDestinationShardRedis, "kubernetesAgentId": $input_kubernetesAgentId, "subscriptionPlan": $input_subscriptionPlan, "aiResource": $input_aiResource, "policySyncConfigId": $input_policySyncConfigId, "workerClass": $input_workerClass, "queueName": $input_queueName} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AdminSidekiqQueuesDeleteJobsInput!) { adminSidekiqQueuesDeleteJobs(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "adminSidekiqQueuesDeleteJobs" }
}

# GraphQL mutation: aiAction
#
# DEPRECATED
# operationId: aiAction
@deprecated "**Status**: Experiment. Introduced in GitLab 15.11."
export def "mutation ai-action" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-explainVulnerability: record
  --input-resolveVulnerability: record
  --input-summarizeReview: record
  --input-measureCommentTemperature: record
  --input-generateDescription: record
  --input-generateCommitMessage: record
  --input-descriptionComposer: record
  --input-chat: record
  --input-summarizeNewMergeRequest: record
  --input-agenticChat: record
  --input-clientSubscriptionId: string
  --input-platformOrigin: string
  --input-projectId: string
  --input-rootNamespaceId: string
  --input-conversationType: string@input-conversationType-completer
  --input-threadId: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "explainVulnerability": $input_explainVulnerability, "resolveVulnerability": $input_resolveVulnerability, "summarizeReview": $input_summarizeReview, "measureCommentTemperature": $input_measureCommentTemperature, "generateDescription": $input_generateDescription, "generateCommitMessage": $input_generateCommitMessage, "descriptionComposer": $input_descriptionComposer, "chat": $input_chat, "summarizeNewMergeRequest": $input_summarizeNewMergeRequest, "agenticChat": $input_agenticChat, "clientSubscriptionId": $input_clientSubscriptionId, "platformOrigin": $input_platformOrigin, "projectId": $input_projectId, "rootNamespaceId": $input_rootNamespaceId, "conversationType": $input_conversationType, "threadId": $input_threadId} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors requestId threadId" }
    let body = {query: ("mutation($input: AiActionInput!) { aiAction(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiAction" }
}

# GraphQL mutation: aiCatalogAgentCreate
#
# DEPRECATED
# operationId: aiCatalogAgentCreate
@deprecated "**Status**: Experiment. Introduced in GitLab 18.2."
@deprecated --flag input-mcpTools
@deprecated --flag input-mcpServers
export def "mutation ai-catalog-agent-create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-description: string
  --input-name: string
  --input-projectId: string
  --input-public: oneof<nothing, bool>
  --input-release: oneof<nothing, bool>
  --input-systemPrompt: string
  --input-tools: string
  --input-mcpTools: string
  --input-userPrompt: string
  --input-mcpServers: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "description": $input_description, "name": $input_name, "projectId": $input_projectId, "public": $input_public, "release": $input_release, "systemPrompt": $input_systemPrompt, "tools": $input_tools, "mcpTools": $input_mcpTools, "userPrompt": $input_userPrompt, "mcpServers": $input_mcpServers} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AiCatalogAgentCreateInput!) { aiCatalogAgentCreate(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogAgentCreate" }
}

# GraphQL mutation: aiCatalogAgentDelete
#
# DEPRECATED
# operationId: aiCatalogAgentDelete
@deprecated "**Status**: Experiment. Introduced in GitLab 18.2."
export def "mutation ai-catalog-agent-delete" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-id: string
  --input-forceHardDelete: oneof<nothing, bool>
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "id": $input_id, "forceHardDelete": $input_forceHardDelete} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors success" }
    let body = {query: ("mutation($input: AiCatalogAgentDeleteInput!) { aiCatalogAgentDelete(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogAgentDelete" }
}

# GraphQL mutation: aiCatalogAgentUpdate
#
# DEPRECATED
# operationId: aiCatalogAgentUpdate
@deprecated "**Status**: Experiment. Introduced in GitLab 18.3."
@deprecated --flag input-mcpTools
@deprecated --flag input-mcpServers
export def "mutation ai-catalog-agent-update" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-id: string
  --input-description: string
  --input-name: string
  --input-public: oneof<nothing, bool>
  --input-release: oneof<nothing, bool>
  --input-systemPrompt: string
  --input-tools: string
  --input-mcpTools: string
  --input-userPrompt: string
  --input-versionBump: string@input-versionBump-completer
  --input-mcpServers: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "id": $input_id, "description": $input_description, "name": $input_name, "public": $input_public, "release": $input_release, "systemPrompt": $input_systemPrompt, "tools": $input_tools, "mcpTools": $input_mcpTools, "userPrompt": $input_userPrompt, "versionBump": $input_versionBump, "mcpServers": $input_mcpServers} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AiCatalogAgentUpdateInput!) { aiCatalogAgentUpdate(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogAgentUpdate" }
}

# GraphQL mutation: aiCatalogFlowCreate
#
# DEPRECATED
# operationId: aiCatalogFlowCreate
@deprecated "**Status**: Experiment. Introduced in GitLab 18.3."
export def "mutation ai-catalog-flow-create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-description: string
  --input-name: string
  --input-projectId: string
  --input-public: oneof<nothing, bool>
  --input-release: oneof<nothing, bool>
  --input-definition: string
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "description": $input_description, "name": $input_name, "projectId": $input_projectId, "public": $input_public, "release": $input_release, "definition": $input_definition} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AiCatalogFlowCreateInput!) { aiCatalogFlowCreate(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogFlowCreate" }
}

# GraphQL mutation: aiCatalogFlowDelete
#
# DEPRECATED
# operationId: aiCatalogFlowDelete
@deprecated "**Status**: Experiment. Introduced in GitLab 18.3."
export def "mutation ai-catalog-flow-delete" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-id: string
  --input-forceHardDelete: oneof<nothing, bool>
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "id": $input_id, "forceHardDelete": $input_forceHardDelete} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors success" }
    let body = {query: ("mutation($input: AiCatalogFlowDeleteInput!) { aiCatalogFlowDelete(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogFlowDelete" }
}

# GraphQL mutation: aiCatalogFlowUpdate
#
# DEPRECATED
# operationId: aiCatalogFlowUpdate
@deprecated "**Status**: Experiment. Introduced in GitLab 18.3."
export def "mutation ai-catalog-flow-update" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --input-clientMutationId: string
  --input-id: string
  --input-description: string
  --input-name: string
  --input-public: oneof<nothing, bool>
  --input-release: oneof<nothing, bool>
  --input-definition: string
  --input-versionBump: string@input-versionBump-completer
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let input = ({"clientMutationId": $input_clientMutationId, "id": $input_id, "description": $input_description, "name": $input_name, "public": $input_public, "release": $input_release, "definition": $input_definition, "versionBump": $input_versionBump} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"input": $input} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "clientMutationId errors" }
    let body = {query: ("mutation($input: AiCatalogFlowUpdateInput!) { aiCatalogFlowUpdate(input: $input) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "aiCatalogFlowUpdate" }
}
