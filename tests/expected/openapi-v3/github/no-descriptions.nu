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
# Uses encode-path-segment for keys and values: RFC 3986 unreserved chars
# ([A-Za-z0-9-._~]) stay literal; everything else gets %XX.
def serialize-qp [name: string, value: any, style: string]: nothing -> list<string> {
  if ($value == null) { return [] }
  let n = (encode-path-segment $name)
  let is_list = ($value | describe | str starts-with "list")
  if ($value | describe | str starts-with "record") { return ($value | transpose k v | each { $"($n)[(encode-path-segment $in.k)]=(encode-path-segment $in.v)" }) }
  if not $is_list { return [$"($n)=(encode-path-segment $value)"] }
  match $style {
    "multi" => { $value | each {|v| $"($n)=(encode-path-segment $v)" } }
    "csv" => { let joined = ($value | each { encode-path-segment $in } | str join ","); [$"($n)=($joined)"] }
    "ssv" => { let joined = ($value | each { encode-path-segment $in } | str join "%20"); [$"($n)=($joined)"] }
    "tsv" => { let joined = ($value | each { encode-path-segment $in } | str join "%09"); [$"($n)=($joined)"] }
    "pipes" => { let joined = ($value | each { encode-path-segment $in } | str join "|"); [$"($n)=($joined)"] }
    "deepObject" => { $value | each {|v| $"($n)[]=(encode-path-segment $v)" } }
    _ => { $value | each {|v| $"($n)=(encode-path-segment $v)" } }
  }
}

# Percent-encode a path-segment value per RFC 3986.
# Unreserved chars ([A-Za-z0-9-._~]) stay literal; everything else gets %XX.
# Trick: `url encode --all` over-encodes, then we decode the four unreserved
# punctuation chars back. Pre-existing %XX sequences in the input survive
# because `url encode --all` first turns their % into %25.
def encode-path-segment [v: any]: nothing -> string {
  $v | into string | url encode --all | str replace --all "%2D" "-" | str replace --all "%2E" "." | str replace --all "%5F" "_" | str replace --all "%7E" "~"
}

# Build URL from base, path, and optional query string
def build-url [base: string, path: string, query?: string]: nothing -> string {
  let parsed = ($base | url parse | reject params)
  let full_path = if ($path | is-empty) { $parsed.path } else { [$parsed.path $path] | str join "/" | str replace --all --regex '/+' '/' }
  let result = ($parsed | upsert path $full_path)
  if ($query != null) and ($query | is-not-empty) { $result | upsert query $query | url join } else { $result | url join }
}

# Execute HTTP request with method dispatch
def do-request [method: string, url: string, auth: record, insecure: bool, raw: bool, dry_run: bool, max_time?: duration, allow_errors?: bool, full?: bool, content_type?: string, body?: any]: nothing -> any {
  let req_url = if ($auth.query | is-not-empty) { if ($url | str contains "?") { $"($url)&($auth.query)" } else { $"($url)?($auth.query)" } } else { $url }
  let timeout = ($max_time | default 30min)
  let ct = ($content_type | default "application/json")
  if $dry_run { return {method: $method, url: $req_url, headers: $auth.headers, query_string: $auth.query, content_type: $ct, timeout: $timeout, body: $body} }
  let resp = match $method {
    "get" => { http get --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url }
    "head" => { http head --headers $auth.headers --max-time $timeout --insecure=$insecure $req_url }
    "options" => { http options --headers $auth.headers --max-time $timeout --insecure=$insecure $req_url }
    "post" => { if ($body | is-empty) { http post --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http post --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }
    "put" => { if ($body | is-empty) { http put --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http put --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }
    "patch" => { if ($body | is-empty) { http patch --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http patch --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }
    "delete" => { if ($body | is-empty) { http delete --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } else { http delete --headers $auth.headers --content-type $ct --data $body --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } }
  }
  if ($method in ["head" "options"]) { return $resp }
  if $allow_errors { $resp } else if $resp.status >= 400 { error make --unspanned { msg: $"HTTP ($resp.status): ($resp.body)" } } else if $full { {status: $resp.status, headers: $resp.headers, body: $resp.body} } else if $resp.status == 204 { null } else { $resp.body }
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
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "full" "dry-run" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "meta get-root" } } | get name | first)
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
export def "meta get-root" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<current_user_url: string, current_user_authorizations_html_url: string, authorizations_url: string, code_search_url: string, commit_search_url: string, emails_url: string, emojis_url: string, events_url: string, feeds_url: string, followers_url: string, following_url: string, gists_url: string, hub_url: string, issue_search_url: string, issues_url: string, keys_url: string, label_search_url: string, notifications_url: string, organization_url: string, organization_repositories_url: string, organization_teams_url: string, public_gists_url: string, rate_limit_url: string, repository_url: string, repository_search_url: string, current_user_repositories_url: string, starred_url: string, starred_gists_url: string, topic_search_url: string, user_url: string, user_organizations_url: string, user_repositories_url: string, user_search_url: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# List global security advisories
#
# GET /advisories
# Docs: https://docs.github.com/rest/security-advisories/global-advisories#list-global-security-advisories — API method documentation
# operationId: security-advisories/list-global-advisories
export def "advisories list-security-global" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --ghsa-id: string
  --type: string@type-completer
  --cve-id: string
  --ecosystem: string@ecosystem-completer
  --severity: string@severity-completer
  --cwes: string
  --is-withdrawn: oneof<nothing, bool>
  --affects: string
  --published: string
  --updated: string
  --modified: string
  --epss-percentage: string
  --epss-percentile: string
  --before: string
  --after: string
  --direction: string@direction-completer
  --per-page: int
  --qp-sort: string@sort-completer
]: nothing -> table<ghsa_id: string, cve_id: string, url: string, html_url: string, repository_advisory_url: string, summary: string, description: string, type: string, severity: string, source_code_location: string, identifiers: list<record>, references: list<string>, published_at: string, updated_at: string, github_reviewed_at: string, nvd_published_at: string, withdrawn_at: string, vulnerabilities: list<record>, cvss: record<vector_string: string, score: float>, cvss_severities: record<cvss_v3: record, cvss_v4: record>, epss: record<percentage: float, percentile: float>, cwes: list<record>, credits: list<record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "ghsa_id" $ghsa_id "scalar") (serialize-qp "type" $type "scalar") (serialize-qp "cve_id" $cve_id "scalar") (serialize-qp "ecosystem" $ecosystem "scalar") (serialize-qp "severity" $severity "scalar") (serialize-qp "cwes" $cwes "scalar") (serialize-qp "is_withdrawn" $is_withdrawn "scalar") (serialize-qp "affects" $affects "scalar") (serialize-qp "published" $published "scalar") (serialize-qp "updated" $updated "scalar") (serialize-qp "modified" $modified "scalar") (serialize-qp "epss_percentage" $epss_percentage "scalar") (serialize-qp "epss_percentile" $epss_percentile "scalar") (serialize-qp "before" $before "scalar") (serialize-qp "after" $after "scalar") (serialize-qp "direction" $direction "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "sort" $qp_sort "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/advisories" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Get a global security advisory
#
# GET /advisories/{ghsa_id}
# Docs: https://docs.github.com/rest/security-advisories/global-advisories#get-a-global-security-advisory — API method documentation
# operationId: security-advisories/get-global-advisory
export def "advisories get-security-global-advisory" [
  ghsa_id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<ghsa_id: string, cve_id: string, url: string, html_url: string, repository_advisory_url: string, summary: string, description: string, type: string, severity: string, source_code_location: string, identifiers: table<type: string, value: string>, references: list<string>, published_at: string, updated_at: string, github_reviewed_at: string, nvd_published_at: string, withdrawn_at: string, vulnerabilities: table<package: record, vulnerable_version_range: string, first_patched_version: string, vulnerable_functions: list>, cvss: record<vector_string: string, score: float>, cvss_severities: record<cvss_v3: record<vector_string: string, score: float>, cvss_v4: record<vector_string: string, score: float>>, epss: record<percentage: float, percentile: float>, cwes: table<cwe_id: string, name: string>, credits: table<user: record, type: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({ghsa_id: (encode-path-segment $ghsa_id)} | format pattern "/advisories/{ghsa_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# List tasks for repository
#
# GET /agents/repos/{owner}/{repo}/tasks
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#list-tasks-for-repository — API method documentation
# operationId: agent-tasks/list-tasks-for-repo
export def "agents-repos-tasks list" [
  owner: string
  repo: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int
  --page: int
  --qp-sort: string@sort-completer-1
  --direction: string@direction-completer
  --state: string
  --is-archived: oneof<nothing, bool>
  --since: string
  --creator-id: list<int>
]: nothing -> record<tasks: table<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: list, owner: record, repository: record, state: string, session_count: int, artifacts: list, archived_at: string, updated_at: string, created_at: string>, total_active_count: int, total_archived_count: int> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "sort" $qp_sort "scalar") (serialize-qp "direction" $direction "scalar") (serialize-qp "state" $state "scalar") (serialize-qp "is_archived" $is_archived "scalar") (serialize-qp "since" $since "scalar") (serialize-qp "creator_id" $creator_id "multi")] | flatten | str join "&"
  let full_url = (build-url $base ({owner: (encode-path-segment $owner), repo: (encode-path-segment $repo)} | format pattern "/agents/repos/{owner}/{repo}/tasks") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Start a task
#
# POST /agents/repos/{owner}/{repo}/tasks
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#start-a-task — API method documentation
# operationId: agent-tasks/create-task-in-repo
export def "agents-repos-tasks create" [
  owner: string
  repo: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  prompt: string
  --model: string
  --create-pull-request: oneof<nothing, bool>
  --base-ref: string
  --head-ref: string
]: any -> record<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: table<id: int>, owner: record<id: int>, repository: record<id: int>, state: string, session_count: int, artifacts: table<provider: string, type: string, data: any>, archived_at: string, updated_at: string, created_at: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({owner: (encode-path-segment $owner), repo: (encode-path-segment $repo)} | format pattern "/agents/repos/{owner}/{repo}/tasks"))
  let req_body = {"prompt": $prompt, "model": $model, "create_pull_request": $create_pull_request, "base_ref": $base_ref, "head_ref": $head_ref} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Get a task by repo
#
# GET /agents/repos/{owner}/{repo}/tasks/{task_id}
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#get-a-task-by-repo — API method documentation
# operationId: agent-tasks/get-task-by-repo-and-id
export def "agents-repos-tasks get-by-and" [
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: table<id: int>, owner: record<id: int>, repository: record<id: int>, state: string, session_count: int, artifacts: table<provider: string, type: string, data: any>, archived_at: string, updated_at: string, created_at: string, sessions: table<id: string, name: string, user: record, owner: record, repository: record, task_id: string, state: string, created_at: string, updated_at: string, completed_at: string, prompt: string, head_ref: string, base_ref: string, model: string, error: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({owner: (encode-path-segment $owner), repo: (encode-path-segment $repo), task_id: (encode-path-segment $task_id)} | format pattern "/agents/repos/{owner}/{repo}/tasks/{task_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# List tasks
#
# GET /agents/tasks
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#list-tasks — API method documentation
# operationId: agent-tasks/list-tasks
export def "agents-tasks list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int
  --page: int
  --qp-sort: string@sort-completer-1
  --direction: string@direction-completer
  --state: string
  --is-archived: oneof<nothing, bool>
  --since: string
]: nothing -> record<tasks: table<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: list, owner: record, repository: record, state: string, session_count: int, artifacts: list, archived_at: string, updated_at: string, created_at: string>, total_active_count: int, total_archived_count: int> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "sort" $qp_sort "scalar") (serialize-qp "direction" $direction "scalar") (serialize-qp "state" $state "scalar") (serialize-qp "is_archived" $is_archived "scalar") (serialize-qp "since" $since "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/agents/tasks" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Get a task by ID
#
# GET /agents/tasks/{task_id}
# Docs: https://docs.github.com/rest/agent-tasks/agent-tasks#get-a-task-by-id — API method documentation
# operationId: agent-tasks/get-task-by-id
export def "agents-tasks get" [
  task_id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: string, url: string, html_url: string, name: string, creator: any, creator_type: string, user_collaborators: table<id: int>, owner: record<id: int>, repository: record<id: int>, state: string, session_count: int, artifacts: table<provider: string, type: string, data: any>, archived_at: string, updated_at: string, created_at: string, sessions: table<id: string, name: string, user: record, owner: record, repository: record, task_id: string, state: string, created_at: string, updated_at: string, completed_at: string, prompt: string, head_ref: string, base_ref: string, model: string, error: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({task_id: (encode-path-segment $task_id)} | format pattern "/agents/tasks/{task_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, slug: string, node_id: string, client_id: string, owner: any, name: string, description: string, external_url: string, html_url: string, created_at: string, updated_at: string, permissions: record<issues: string, checks: string, metadata: string, contents: string, deployments: string>, events: list<string>, installations_count: int> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/app")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Create a GitHub App from a manifest
#
# POST /app-manifests/{code}/conversions
# Docs: https://docs.github.com/rest/apps/apps#create-a-github-app-from-a-manifest — API method documentation
# operationId: apps/create-from-manifest
export def "app-manifests-conversions create" [
  code: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, slug: string, node_id: string, client_id: string, owner: any, name: string, description: string, external_url: string, html_url: string, created_at: string, updated_at: string, permissions: record<issues: string, checks: string, metadata: string, contents: string, deployments: string>, events: list<string>, installations_count: int, client_secret: string, webhook_secret: string, pem: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({code: (encode-path-segment $code)} | format pattern "/app-manifests/{code}/conversions"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Get a webhook configuration for an app
#
# GET /app/hook/config
# Docs: https://docs.github.com/rest/apps/webhooks#get-a-webhook-configuration-for-an-app — API method documentation
# operationId: apps/get-webhook-config-for-app
export def "app-hook-config get-webhook" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<url: string, content_type: string, secret: string, insecure_ssl: any> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/app/hook/config")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Update a webhook configuration for an app
#
# PATCH /app/hook/config
# Docs: https://docs.github.com/rest/apps/webhooks#update-a-webhook-configuration-for-an-app — API method documentation
# operationId: apps/update-webhook-config-for-app
export def "app-hook-config update-webhook" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --url: string
  --content-type: string
  --secret: string
  --insecure-ssl: any
]: any -> record<url: string, content_type: string, secret: string, insecure_ssl: any> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/app/hook/config")
  let req_body = {"url": $url, "content_type": $content_type, "secret": $secret, "insecure_ssl": $insecure_ssl} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# List deliveries for an app webhook
#
# GET /app/hook/deliveries
# Docs: https://docs.github.com/rest/apps/webhooks#list-deliveries-for-an-app-webhook — API method documentation
# operationId: apps/list-webhook-deliveries
export def "app-hook-deliveries list-webhook" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int
  --cursor: string
  --status: string@status-completer
]: nothing -> table<id: int, guid: string, delivered_at: string, redelivery: bool, duration: float, status: string, status_code: int, event: string, action: string, installation_id: int, repository_id: int, throttled_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "cursor" $cursor "scalar") (serialize-qp "status" $status "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/app/hook/deliveries" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Get a delivery for an app webhook
#
# GET /app/hook/deliveries/{delivery_id}
# Docs: https://docs.github.com/rest/apps/webhooks#get-a-delivery-for-an-app-webhook — API method documentation
# operationId: apps/get-webhook-delivery
export def "app-hook-deliveries get-webhook" [
  delivery_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, guid: string, delivered_at: string, redelivery: bool, duration: float, status: string, status_code: int, event: string, action: string, installation_id: int, repository_id: int, throttled_at: string, url: string, request: record<headers: record, payload: record>, response: record<headers: record, payload: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({delivery_id: (encode-path-segment $delivery_id)} | format pattern "/app/hook/deliveries/{delivery_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Redeliver a delivery for an app webhook
#
# POST /app/hook/deliveries/{delivery_id}/attempts
# Docs: https://docs.github.com/rest/apps/webhooks#redeliver-a-delivery-for-an-app-webhook — API method documentation
# operationId: apps/redeliver-webhook-delivery
export def "app-hook-deliveries-attempts create-redeliver-webhook" [
  delivery_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({delivery_id: (encode-path-segment $delivery_id)} | format pattern "/app/hook/deliveries/{delivery_id}/attempts"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# List installation requests for the authenticated app
#
# GET /app/installation-requests
# Docs: https://docs.github.com/rest/apps/apps#list-installation-requests-for-the-authenticated-app — API method documentation
# operationId: apps/list-installation-requests-for-authenticated-app
export def "app-installation-requests list-for-authenticated" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int
  --page: int
]: nothing -> table<id: int, node_id: string, account: any, requester: record<name: string, email: string, login: string, id: int, node_id: string, avatar_url: string, gravatar_id: string, url: string, html_url: string, followers_url: string, following_url: string, gists_url: string, starred_url: string, subscriptions_url: string, organizations_url: string, repos_url: string, events_url: string, received_events_url: string, type: string, site_admin: bool, starred_at: string, user_view_type: string>, created_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "page" $page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/app/installation-requests" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# List installations for the authenticated app
#
# GET /app/installations
# Docs: https://docs.github.com/rest/apps/apps#list-installations-for-the-authenticated-app — API method documentation
# operationId: apps/list-installations
export def "app-installations list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --per-page: int
  --page: int
  --since: string
  --outdated: string
]: nothing -> table<id: int, account: any, repository_selection: string, access_tokens_url: string, repositories_url: string, html_url: string, app_id: int, client_id: string, target_id: int, target_type: string, permissions: record<actions: string, administration: string, artifact_metadata: string, attestations: string, checks: string, code_quality: string, codespaces: string, contents: string, dependabot_secrets: string, deployments: string, discussions: string, environments: string, issues: string, merge_queues: string, metadata: string, packages: string, pages: string, pull_requests: string, repository_custom_properties: string, repository_hooks: string, repository_projects: string, secret_scanning_alerts: string, secrets: string, security_events: string, single_file: string, statuses: string, vulnerability_alerts: string, workflows: string, custom_properties_for_organizations: string, members: string, organization_administration: string, organization_custom_roles: string, organization_custom_org_roles: string, organization_custom_properties: string, organization_copilot_seat_management: string, organization_copilot_agent_settings: string, organization_announcement_banners: string, organization_events: string, organization_hooks: string, organization_personal_access_tokens: string, organization_personal_access_token_requests: string, organization_plan: string, organization_projects: string, organization_packages: string, organization_secrets: string, organization_self_hosted_runners: string, organization_user_blocking: string, email_addresses: string, followers: string, git_ssh_keys: string, gpg_keys: string, interaction_limits: string, profile: string, starring: string, enterprise_custom_properties_for_organizations: string>, events: list<string>, created_at: string, updated_at: string, single_file_name: string, has_multiple_single_files: bool, single_file_paths: list<string>, app_slug: string, suspended_by: record<name: string, email: string, login: string, id: int, node_id: string, avatar_url: string, gravatar_id: string, url: string, html_url: string, followers_url: string, following_url: string, gists_url: string, starred_url: string, subscriptions_url: string, organizations_url: string, repos_url: string, events_url: string, received_events_url: string, type: string, site_admin: bool, starred_at: string, user_view_type: string>, suspended_at: string, contact_email: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "per_page" $per_page "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "since" $since "scalar") (serialize-qp "outdated" $outdated "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/app/installations" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}
