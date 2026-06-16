# Auto-generated client for GitHub v3 REST API v1.1.4
# Source: <spec>
# Auth: --token flag or $env.GITHUB_V3_REST_API_TOKEN

const BASE_URL = "https://api.github.com"
const DEFAULT_AUTH = "bearer"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o GITHUB_V3_REST_API_TOKEN | default "" }
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
def do-request [method: string, url: string, auth: record, insecure: bool, raw: bool, dry_run: bool, max_time?: duration, allow_errors?: bool, content_type?: string, body?: any]: nothing -> any {
  let req_url = if ($auth.query | is-not-empty) { if ($url | str contains "?") { $"($url)&($auth.query)" } else { $"($url)?($auth.query)" } } else { $url }
  let timeout = ($max_time | default 30min)
  let ct = ($content_type | default "application/json")
  if $dry_run { return {method: $method, url: $req_url, headers: $auth.headers, query_string: $auth.query, content_type: $ct, timeout: $timeout, body: $body} }
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

def base-url-completer [] { ["https://api.github.com"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def type-completer [] { ["malware" "reviewed" "unreviewed"] }
def ecosystem-completer [] { ["actions" "composer" "erlang" "go" "maven" "npm" "nuget" "other" "pip" "pub" "rubygems" "rust" "swift"] }
def severity-completer [] { ["critical" "high" "low" "medium" "unknown"] }
def direction-completer [] { ["asc" "desc"] }
def sort-completer [] { ["epss_percentage" "epss_percentile" "published" "updated"] }
def sort-completer-1 [] { ["created_at" "updated_at"] }
def status-completer [] { ["failure" "success"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "dry-run" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "meta meta-root" } } | get name | first)
  let mod_cmds = (scope modules | where name == $mod_name | get commands | first)
  let cmd_ids = ($mod_cmds | where name not-in [$mod_name "commands"] | get decl_id)
  scope commands | where decl_id in $cmd_ids | each {|cmd|
    let sig = $cmd.signatures | values | first
    let params = $sig
      | where parameter_type not-in ["input" "output"]
      | where parameter_name not-in $builtin_flags
      | select parameter_name parameter_type syntax_shape is_optional description
    let return_type = ($sig | where parameter_type == "output" | get -o syntax_shape | first | default "any")
    {
      name: ($cmd.name | str replace $"($mod_name) " "")
      description: $cmd.description
      extra_description: $cmd.extra_description
      return_type: $return_type
      params: $params
    }
  }
}

# GitHub API Root
#
# GET /
# Docs: https://docs.github.com/rest/meta/meta#github-api-root — API method documentation
# operationId: meta/root
export def "meta meta-root" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<current_user_url: string, current_user_authorizations_html_url: string, authorizations_url: string, code_search_url: string, commit_search_url: string, emails_url: string, emojis_url: string, events_url: string, feeds_url: string, followers_url: string, following_url: string, gists_url: string, hub_url: string, issue_search_url: string, issues_url: string, keys_url: string, label_search_url: string, notifications_url: string, organization_url: string, organization_repositories_url: string, organization_teams_url: string, public_gists_url: string, rate_limit_url: string, repository_url: string, repository_search_url: string, current_user_repositories_url: string, starred_url: string, starred_gists_url: string, topic_search_url: string, user_url: string, user_organizations_url: string, user_repositories_url: string, user_search_url: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# List global security advisories
#
# GET /advisories
# Docs: https://docs.github.com/rest/security-advisories/global-advisories#list-global-security-advisories — API method documentation
# operationId: security-advisories/list-global-advisories
export def "advisories list-global-advisories" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --ghsa-id: string # If specified, only advisories with this GHSA (GitHub Security Advisory) identifier will be returned.
  --type: string@type-completer # If specified, only advisories of this type will be returned. By default, a request with no other parameters defined will only return reviewed advisories that are not malware. (default: reviewed)
  --cve-id: string # If specified, only advisories with this CVE (Common Vulnerabilities and Exposures) identifier will be returned.
  --ecosystem: string@ecosystem-completer # If specified, only advisories for these ecosystems will be returned.
  --severity: string@severity-completer # If specified, only advisories with these severities will be returned.
  --cwes: string # If specified, only advisories with these Common Weakness Enumerations (CWEs) will be returned.  Example: `cwes=79,284,22` or `cwes[]=79&cwes[]=284&cwes[]=22`
  --is-withdrawn: oneof<nothing, bool> # Whether to only return advisories that have been withdrawn.
  --affects: string # If specified, only return advisories that affect any of `package` or `package@version`. A maximum of 1000 packages can be specified. If the query parameter causes the URL to exceed the maximum URL length supported by your client, you must specify fewer packages.  Example: `affects=package1,package2@1.0.0,package3@2.0.0` or `affects[]=package1&affects[]=package2@1.0.0`
  --published: string # If specified, only return advisories that were published on a date or date range.  For more information on the syntax of the date range, see "[Understanding the search syntax](https://docs.github.com/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax#query-for-dates)."
  --updated: string # If specified, only return advisories that were updated on a date or date range.  For more information on the syntax of the date range, see "[Understanding the search syntax](https://docs.github.com/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax#query-for-dates)."
  --modified: string # If specified, only show advisories that were updated or published on a date or date range.  For more information on the syntax of the date range, see "[Understanding the search syntax](https://docs.github.com/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax#query-for-dates)."
  --epss-percentage: string # If specified, only return advisories that have an EPSS percentage score that matches the provided value. The EPSS percentage represents the likelihood of a CVE being exploited.
  --epss-percentile: string # If specified, only return advisories that have an EPSS percentile score that matches the provided value. The EPSS percentile represents the relative rank of the CVE's likelihood of being exploited compared to other CVEs.
  --before: string # A cursor, as given in the [Link header](https://docs.github.com/rest/guides/using-pagination-in-the-rest-api#using-link-headers). If specified, the query only searches for results before this cursor. For more information, see "[Using pagination in the REST API](https://docs.github.com/rest/using-the-rest-api/using-pagination-in-the-rest-api)."
  --after: string # A cursor, as given in the [Link header](https://docs.github.com/rest/guides/using-pagination-in-the-rest-api#using-link-headers). If specified, the query only searches for results after this cursor. For more information, see "[Using pagination in the REST API](https://docs.github.com/rest/using-the-rest-api/using-pagination-in-the-rest-api)."
  --direction: string@direction-completer # The direction to sort the results by. (default: desc)
  --per-page: int # The number of results per page (max 100). For more information, see "[Using pagination in the REST API](https://docs.github.com/rest/using-the-rest-api/using-pagination-in-the-rest-api)." (default: 30)
  --qp-sort: string@sort-completer # The property to sort the results by. (default: published)
]: nothing -> table<ghsa_id: string, cve_id: string, url: string, html_url: string, repository_advisory_url: string, summary: string, description: string, type: string, severity: string, source_code_location: string, identifiers: list<record>, references: list<string>, published_at: string, updated_at: string, github_reviewed_at: string, nvd_published_at: string, withdrawn_at: string, vulnerabilities: list<record>, cvss: record<vector_string: string, score: float>, cvss_severities: record<cvss_v3: record, cvss_v4: record>, epss: record<percentage: float, percentile: float>, cwes: list<record>, credits: list<record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "ghsa_id" $ghsa_id "scalar") (serialize-qp "type" $type "scalar") (serialize-qp "cve_id" $cve_id "scalar") (serialize-qp "ecosystem" $ecosystem "scalar") (serialize-qp "severity" $severity "scalar") (serialize-qp "cwes" $cwes "scalar") (serialize-qp "is_withdrawn" $is_withdrawn "scalar") (serialize-qp "affects" $affects "scalar") (serialize-qp "published" $published "scalar") (serialize-qp "updated" $updated "scalar") (serialize-qp "modified" $modified "scalar") (serialize-qp "epss_percentage" $epss_percentage "scalar") (serialize-qp "epss_percentile" $epss_percentile "scalar") (serialize-qp "before" $before "scalar") (serialize-qp "after" $after "scalar") (serialize-qp "direction" $direction "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "sort" $qp_sort "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/advisories" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get a global security advisory
#
# GET /advisories/{ghsa_id}
# Docs: https://docs.github.com/rest/security-advisories/global-advisories#get-a-global-security-advisory — API method documentation
# operationId: security-advisories/get-global-advisory
export def "advisories get-global-advisory" [
  ghsa_id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<ghsa_id: string, cve_id: string, url: string, html_url: string, repository_advisory_url: string, summary: string, description: string, type: string, severity: string, source_code_location: string, identifiers: table<type: string, value: string>, references: list<string>, published_at: string, updated_at: string, github_reviewed_at: string, nvd_published_at: string, withdrawn_at: string, vulnerabilities: table<package: record, vulnerable_version_range: string, first_patched_version: string, vulnerable_functions: list>, cvss: record<vector_string: string, score: float>, cvss_severities: record<cvss_v3: record<vector_string: string, score: float>, cvss_v4: record<vector_string: string, score: float>>, epss: record<percentage: float, percentile: float>, cwes: table<cwe_id: string, name: string>, credits: table<user: record, type: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({ghsa_id: $ghsa_id} | format pattern "/advisories/{ghsa_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# List tasks for repository
#
# GET /agents/repos/{owner}/{repo}/tasks
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#list-tasks-for-repository — API method documentation
# operationId: agent-tasks/list-tasks-for-repo
export def "agents-repos-tasks list-tasks-for-repo" [
  owner: string
  repo: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int # The number of results per page (max 100). (default: 30)
  --page: int # The page number of the results to fetch. (default: 1)
  --qp-sort: string@sort-completer-1 # The field to sort results by. Can be `updated_at` or `created_at`. (default: updated_at)
  --direction: string@direction-completer # The direction to sort results. Can be `asc` or `desc`. (default: desc)
  --state: string # Comma-separated list of task states to filter by. Can be any combination of: `queued`, `in_progress`, `completed`, `failed`, `idle`, `waiting_for_user`, `timed_out`, `cancelled`.
  --is-archived: oneof<nothing, bool> # Filter by archived status. When `true`, returns only archived tasks. When `false` or omitted, returns only non-archived tasks. Defaults to `false`. (default: false)
  --since: string # Only show tasks updated at or after this time (ISO 8601 timestamp) (format: date-time)
  --creator-id: list # Filter tasks by creator user ID. Accepts one or more user IDs.
]: nothing -> record<tasks: table<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: list, owner: record, repository: record, state: string, session_count: int, artifacts: list, archived_at: string, updated_at: string, created_at: string>, total_active_count: int, total_archived_count: int> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "sort" $qp_sort "scalar") (serialize-qp "direction" $direction "scalar") (serialize-qp "state" $state "scalar") (serialize-qp "is_archived" $is_archived "scalar") (serialize-qp "since" $since "scalar") (serialize-qp "creator_id" $creator_id "multi")] | flatten | str join "&"
  let full_url = (build-url $base ({owner: $owner, repo: $repo} | format pattern "/agents/repos/{owner}/{repo}/tasks") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Start a task
#
# POST /agents/repos/{owner}/{repo}/tasks
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#start-a-task — API method documentation
# operationId: agent-tasks/create-task-in-repo
export def "agents-repos-tasks create-task-in-repo" [
  owner: string
  repo: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  prompt: string # The user's prompt for the agent
  --model: string # The model to use for this task. The allowed models may change over time and depend on the user's GitHub Copilot plan and organization policies. Currently supported values: `claude-sonnet-4.6`, `claude-opus-4.6`, `gpt-5.2-codex`, `gpt-5.3-codex`, `gpt-5.4`, `claude-sonnet-4.5`, `claude-opus-4.5`
  --create-pull-request: oneof<nothing, bool> # Whether to create a PR. (default: false)
  --base-ref: string # Base ref for new branch/PR
  --head-ref: string # Head ref for existing branch/PR. If provided with `base_ref`, the agent looks up open PR context for `head_ref` targeting `base_ref` and commits to `head_ref` instead of creating a new branch.
]: any -> record<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: table<id: int>, owner: record<id: int>, repository: record<id: int>, state: string, session_count: int, artifacts: table<provider: string, type: string, data: any>, archived_at: string, updated_at: string, created_at: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({owner: $owner, repo: $repo} | format pattern "/agents/repos/{owner}/{repo}/tasks"))
  let body = {"prompt": $prompt, "model": $model, "create_pull_request": $create_pull_request, "base_ref": $base_ref, "head_ref": $head_ref} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Get a task by repo
#
# GET /agents/repos/{owner}/{repo}/tasks/{task_id}
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#get-a-task-by-repo — API method documentation
# operationId: agent-tasks/get-task-by-repo-and-id
export def "agents-repos-tasks get-task-by-repo-and-id" [
  owner: string
  repo: string
  task_id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: table<id: int>, owner: record<id: int>, repository: record<id: int>, state: string, session_count: int, artifacts: table<provider: string, type: string, data: any>, archived_at: string, updated_at: string, created_at: string, sessions: table<id: string, name: string, user: record, owner: record, repository: record, task_id: string, state: string, created_at: string, updated_at: string, completed_at: string, prompt: string, head_ref: string, base_ref: string, model: string, error: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({owner: $owner, repo: $repo, task_id: $task_id} | format pattern "/agents/repos/{owner}/{repo}/tasks/{task_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# List tasks
#
# GET /agents/tasks
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#list-tasks — API method documentation
# operationId: agent-tasks/list-tasks
export def "agents-tasks list-tasks" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int # The number of results per page (max 100). (default: 30)
  --page: int # The page number of the results to fetch. (default: 1)
  --qp-sort: string@sort-completer-1 # The field to sort results by. Can be `updated_at` or `created_at`. (default: updated_at)
  --direction: string@direction-completer # The direction to sort results. Can be `asc` or `desc`. (default: desc)
  --state: string # Comma-separated list of task states to filter by. Can be any combination of: `queued`, `in_progress`, `completed`, `failed`, `idle`, `waiting_for_user`, `timed_out`, `cancelled`.
  --is-archived: oneof<nothing, bool> # Filter by archived status. When `true`, returns only archived tasks. When `false` or omitted, returns only non-archived tasks. Defaults to `false`. (default: false)
  --since: string # Only show tasks updated at or after this time (ISO 8601 timestamp) (format: date-time)
]: nothing -> record<tasks: table<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: list, owner: record, repository: record, state: string, session_count: int, artifacts: list, archived_at: string, updated_at: string, created_at: string>, total_active_count: int, total_archived_count: int> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "sort" $qp_sort "scalar") (serialize-qp "direction" $direction "scalar") (serialize-qp "state" $state "scalar") (serialize-qp "is_archived" $is_archived "scalar") (serialize-qp "since" $since "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/agents/tasks" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get a task by ID
#
# GET /agents/tasks/{task_id}
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#get-a-task-by-id — API method documentation
# operationId: agent-tasks/get-task-by-id
export def "agents-tasks get-task-by-id" [
  task_id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: table<id: int>, owner: record<id: int>, repository: record<id: int>, state: string, session_count: int, artifacts: table<provider: string, type: string, data: any>, archived_at: string, updated_at: string, created_at: string, sessions: table<id: string, name: string, user: record, owner: record, repository: record, task_id: string, state: string, created_at: string, updated_at: string, completed_at: string, prompt: string, head_ref: string, base_ref: string, model: string, error: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({task_id: $task_id} | format pattern "/agents/tasks/{task_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get the authenticated app
#
# GET /app
# Docs: https://docs.github.com/rest/apps/apps#get-the-authenticated-app — API method documentation
# operationId: apps/get-authenticated
export def "app get-authenticated" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, slug: string, node_id: string, client_id: string, owner: any, name: string, description: string, external_url: string, html_url: string, created_at: string, updated_at: string, permissions: record<issues: string, checks: string, metadata: string, contents: string, deployments: string>, events: list<string>, installations_count: int> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/app")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Create a GitHub App from a manifest
#
# POST /app-manifests/{code}/conversions
# Docs: https://docs.github.com/rest/apps/apps#create-a-github-app-from-a-manifest — API method documentation
# operationId: apps/create-from-manifest
export def "app-manifests-conversions create-from-manifest" [
  code: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, slug: string, node_id: string, client_id: string, owner: any, name: string, description: string, external_url: string, html_url: string, created_at: string, updated_at: string, permissions: record<issues: string, checks: string, metadata: string, contents: string, deployments: string>, events: list<string>, installations_count: int, client_secret: string, webhook_secret: string, pem: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({code: $code} | format pattern "/app-manifests/{code}/conversions"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get a webhook configuration for an app
#
# GET /app/hook/config
# Docs: https://docs.github.com/rest/apps/webhooks#get-a-webhook-configuration-for-an-app — API method documentation
# operationId: apps/get-webhook-config-for-app
export def "app-hook-config get-webhook-config-for-app" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<url: string, content_type: string, secret: string, insecure_ssl: any> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/app/hook/config")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Update a webhook configuration for an app
#
# PATCH /app/hook/config
# Docs: https://docs.github.com/rest/apps/webhooks#update-a-webhook-configuration-for-an-app — API method documentation
# operationId: apps/update-webhook-config-for-app
export def "app-hook-config update-webhook-config-for-app" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --body-url: string # The URL to which the payloads will be delivered. (format: uri, e.g. https://example.com/webhook)
  --content-type: string # The media type used to serialize the payloads. Supported values include `json` and `form`. The default is `form`. (e.g. "json")
  --secret: string # If provided, the `secret` will be used as the `key` to generate the HMAC hex digest value for [delivery signature headers](https://docs.github.com/webhooks/event-payloads/#delivery-headers). (e.g. "********")
  --insecure-ssl: any
]: any -> record<url: string, content_type: string, secret: string, insecure_ssl: any> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/app/hook/config")
  let body = {"url": $body_url, "content_type": $content_type, "secret": $secret, "insecure_ssl": $insecure_ssl} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# List deliveries for an app webhook
#
# GET /app/hook/deliveries
# Docs: https://docs.github.com/rest/apps/webhooks#list-deliveries-for-an-app-webhook — API method documentation
# operationId: apps/list-webhook-deliveries
export def "app-hook-deliveries list-webhook-deliveries" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int # The number of results per page (max 100). For more information, see "[Using pagination in the REST API](https://docs.github.com/rest/using-the-rest-api/using-pagination-in-the-rest-api)." (default: 30)
  --cursor: string # Used for pagination: the starting delivery from which the page of deliveries is fetched. Refer to the `link` header for the next and previous page cursors.
  --status: string@status-completer # Returns webhook deliveries filtered by delivery outcome classification based on `status_code` range. A `status` of `success` returns deliveries with a `status_code` in the 200-399 range (inclusive). A `status` of `failure` returns deliveries with a `status_code` in the 400-599 range (inclusive).
]: nothing -> table<id: int, guid: string, delivered_at: string, redelivery: bool, duration: float, status: string, status_code: int, event: string, action: string, installation_id: int, repository_id: int, throttled_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "cursor" $cursor "scalar") (serialize-qp "status" $status "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/app/hook/deliveries" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get a delivery for an app webhook
#
# GET /app/hook/deliveries/{delivery_id}
# Docs: https://docs.github.com/rest/apps/webhooks#get-a-delivery-for-an-app-webhook — API method documentation
# operationId: apps/get-webhook-delivery
export def "app-hook-deliveries get-webhook-delivery" [
  delivery_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, guid: string, delivered_at: string, redelivery: bool, duration: float, status: string, status_code: int, event: string, action: string, installation_id: int, repository_id: int, throttled_at: string, url: string, request: record<headers: record, payload: record>, response: record<headers: record, payload: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({delivery_id: $delivery_id} | format pattern "/app/hook/deliveries/{delivery_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Redeliver a delivery for an app webhook
#
# POST /app/hook/deliveries/{delivery_id}/attempts
# Docs: https://docs.github.com/rest/apps/webhooks#redeliver-a-delivery-for-an-app-webhook — API method documentation
# operationId: apps/redeliver-webhook-delivery
export def "app-hook-deliveries-attempts apps-redeliver-webhook-delivery" [
  delivery_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({delivery_id: $delivery_id} | format pattern "/app/hook/deliveries/{delivery_id}/attempts"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# List installation requests for the authenticated app
#
# GET /app/installation-requests
# Docs: https://docs.github.com/rest/apps/apps#list-installation-requests-for-the-authenticated-app — API method documentation
# operationId: apps/list-installation-requests-for-authenticated-app
export def "app-installation-requests list-installation-requests-for-authenticated-app" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int # The number of results per page (max 100). For more information, see "[Using pagination in the REST API](https://docs.github.com/rest/using-the-rest-api/using-pagination-in-the-rest-api)." (default: 30)
  --page: int # The page number of the results to fetch. For more information, see "[Using pagination in the REST API](https://docs.github.com/rest/using-the-rest-api/using-pagination-in-the-rest-api)." (default: 1)
]: nothing -> table<id: int, node_id: string, account: any, requester: record<name: string, email: string, login: string, id: int, node_id: string, avatar_url: string, gravatar_id: string, url: string, html_url: string, followers_url: string, following_url: string, gists_url: string, starred_url: string, subscriptions_url: string, organizations_url: string, repos_url: string, events_url: string, received_events_url: string, type: string, site_admin: bool, starred_at: string, user_view_type: string>, created_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "page" $page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/app/installation-requests" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# List installations for the authenticated app
#
# GET /app/installations
# Docs: https://docs.github.com/rest/apps/apps#list-installations-for-the-authenticated-app — API method documentation
# operationId: apps/list-installations
export def "app-installations list-installations" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int # The number of results per page (max 100). For more information, see "[Using pagination in the REST API](https://docs.github.com/rest/using-the-rest-api/using-pagination-in-the-rest-api)." (default: 30)
  --page: int # The page number of the results to fetch. For more information, see "[Using pagination in the REST API](https://docs.github.com/rest/using-the-rest-api/using-pagination-in-the-rest-api)." (default: 1)
  --since: string # Only show results that were last updated after the given time. This is a timestamp in [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601) format: `YYYY-MM-DDTHH:MM:SSZ`. (format: date-time)
  --outdated: string
]: nothing -> table<id: int, account: any, repository_selection: string, access_tokens_url: string, repositories_url: string, html_url: string, app_id: int, client_id: string, target_id: int, target_type: string, permissions: record<actions: string, administration: string, artifact_metadata: string, attestations: string, checks: string, code_quality: string, codespaces: string, contents: string, dependabot_secrets: string, deployments: string, discussions: string, environments: string, issues: string, merge_queues: string, metadata: string, packages: string, pages: string, pull_requests: string, repository_custom_properties: string, repository_hooks: string, repository_projects: string, secret_scanning_alerts: string, secrets: string, security_events: string, single_file: string, statuses: string, vulnerability_alerts: string, workflows: string, custom_properties_for_organizations: string, members: string, organization_administration: string, organization_custom_roles: string, organization_custom_org_roles: string, organization_custom_properties: string, organization_copilot_seat_management: string, organization_copilot_agent_settings: string, organization_announcement_banners: string, organization_events: string, organization_hooks: string, organization_personal_access_tokens: string, organization_personal_access_token_requests: string, organization_plan: string, organization_projects: string, organization_packages: string, organization_secrets: string, organization_self_hosted_runners: string, organization_user_blocking: string, email_addresses: string, followers: string, git_ssh_keys: string, gpg_keys: string, interaction_limits: string, profile: string, starring: string, enterprise_custom_properties_for_organizations: string>, events: list<string>, created_at: string, updated_at: string, single_file_name: string, has_multiple_single_files: bool, single_file_paths: list<string>, app_slug: string, suspended_by: record<name: string, email: string, login: string, id: int, node_id: string, avatar_url: string, gravatar_id: string, url: string, html_url: string, followers_url: string, following_url: string, gists_url: string, starred_url: string, subscriptions_url: string, organizations_url: string, repos_url: string, events_url: string, received_events_url: string, type: string, site_admin: bool, starred_at: string, user_view_type: string>, suspended_at: string, contact_email: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "since" $since "scalar") (serialize-qp "outdated" $outdated "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/app/installations" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}
