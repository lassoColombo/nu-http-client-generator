# Auto-generated client for GitLab API vv4
# Source: <spec>
# Auth: --token flag or $env.TEST_CLIENT_TOKEN

const BASE_URL = "https://gitlab.com"
const DEFAULT_AUTH = "private-token"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o TEST_CLIENT_TOKEN | default "" }
  let scheme = ($auth_scheme | default "bearer")
  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }
  match $scheme {
    "private-token" => { {headers: {PRIVATE-TOKEN: $token_val}, query: ""} }
    "query-private_token" => { {headers: {}, query: $"(encode-path-segment "private_token")=(encode-path-segment $token_val)"} }
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
    "head" => { http head --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure $req_url }
    "options" => { http options --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure $req_url }
    "post" => { if ($body | is-empty) { http post --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http post --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }
    "put" => { if ($body | is-empty) { http put --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http put --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }
    "patch" => { if ($body | is-empty) { http patch --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http patch --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }
    "delete" => { if ($body | is-empty) { http delete --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } else { http delete --headers $auth.headers --content-type $ct --data $body --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } }
  }
  if ($method == "head") and (not $full) and (not $allow_errors) and $resp.status < 400 { return $resp.headers }
  if $allow_errors { $resp } else if $resp.status >= 400 { error make --unspanned { msg: $"HTTP ($resp.status): ($resp.body)" } } else if $full { {status: $resp.status, headers: $resp.headers, body: $resp.body} } else if $resp.status == 204 { null } else { $resp.body }
}

def base-url-completer [] { ["https://gitlab.com"] }
def auth-scheme-completer [] { ["private-token" "query-private_token"] }

# Completers for enum parameters
def visibility-completer [] { ["internal" "private" "public"] }
def order-by-completer [] { ["id" "name" "path" "similarity"] }
def sort-completer [] { ["asc" "desc"] }
def min-access-level-completer [] { ["10" "15" "20" "30" "40" "50"] }
def project-creation-level-completer [] { ["administrator" "developer" "maintainer" "noone" "owner"] }
def subgroup-creation-level-completer [] { ["maintainer" "owner"] }
def default-branch-protection-completer [] { ["0" "1" "2" "3" "4"] }
def enabled-git-access-protocol-completer [] { ["all" "http" "ssh"] }
def wiki-access-level-completer [] { ["disabled" "enabled" "private"] }
def duo-availability-completer [] { ["default_off" "default_on" "never_on"] }
def tool-approval-for-session-availability-completer [] { ["default_off" "default_on" "never_on"] }
def shared-runners-setting-completer [] { ["disabled_and_overridable" "disabled_and_unoverridable" "enabled"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "full" "dry-run" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "groups-access-requests get" } } | get name | first)
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

# Gets a list of access requests for a group.
#
# GET /api/v4/groups/{id}/access_requests
# operationId: getApiV4GroupsIdAccessRequests
export def "groups-access-requests get" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: table<key: string, value: string>, web_url: string, requested_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}/access_requests") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Requests access for the authenticated user to a group.
#
# POST /api/v4/groups/{id}/access_requests
# operationId: postApiV4GroupsIdAccessRequests
export def "groups-access-requests create" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: table<key: string, value: string>, web_url: string, requested_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}/access_requests"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Approves an access request for the given user.
#
# PUT /api/v4/groups/{id}/access_requests/{user_id}/approve
# operationId: putApiV4GroupsIdAccessRequestsUserIdApprove
export def "groups-access-requests-approve update" [
  id: string
  user_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --access-level: int # A valid access level (defaults: `30`, the Developer role) (format: int32, default: 30)
]: any -> record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: table<key: string, value: string>, web_url: string, access_level: string, created_at: string, created_by: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, expires_at: string, group_saml_identity: record<provider: string, extern_uid: string, saml_provider_id: string>, group_scim_identity: record<extern_uid: string, group_id: string, active: string>, email: string, is_using_seat: string, override: string, membership_state: string, member_role: record<id: int, group_id: int, name: any, description: any, base_access_level: int, apply_security_scan_profiles: bool, admin_merge_request: bool, archive_project: bool, admin_ai_catalog_item_consumer: bool, remove_project: bool, remove_group: bool, manage_security_policy_link: bool, admin_ai_catalog_item: bool, admin_compliance_framework: bool, admin_cicd_variables: bool, manage_deploy_tokens: bool, manage_group_access_tokens: bool, admin_group_member: bool, admin_integrations: bool, manage_merge_request_settings: bool, manage_project_access_tokens: bool, admin_protected_branch: bool, admin_protected_environments: bool, admin_push_rules: bool, admin_runners: bool, admin_security_attributes: bool, admin_terraform_state: bool, admin_vulnerability: bool, admin_web_hook: bool, read_compliance_dashboard: bool, read_security_scan_profiles: bool, read_virtual_registry: bool, update_sast_vulnerability_resolution_setting: bool, read_admin_cicd: bool, read_crm_contact: bool, read_dependency: bool, read_admin_groups: bool, read_admin_projects: bool, read_code: bool, read_runners: bool, read_security_attribute: bool, read_admin_subscription: bool, read_admin_monitoring: bool, read_admin_users: bool, read_vulnerability: bool>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), user_id: (encode-path-segment $user_id)} | format pattern "/api/v4/groups/{id}/access_requests/{user_id}/approve"))
  let req_body = {"access_level": $access_level} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Denies an access request for the given user.
#
# DELETE /api/v4/groups/{id}/access_requests/{user_id}
# operationId: deleteApiV4GroupsIdAccessRequestsUserId
export def "groups-access-requests delete" [
  id: string
  user_id: int
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
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), user_id: (encode-path-segment $user_id)} | format pattern "/api/v4/groups/{id}/access_requests/{user_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# List an awardable's emoji reactions for groups
#
# GET /api/v4/groups/{id}/epics/{epic_iid}/award_emoji
# operationId: getApiV4GroupsIdEpicsEpicIidAwardEmoji
export def "groups-epics-award-emoji list" [
  id: string
  epic_iid: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> table<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({id: (encode-path-segment $id), epic_iid: (encode-path-segment $epic_iid)} | format pattern "/api/v4/groups/{id}/epics/{epic_iid}/award_emoji") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Add a new emoji reaction
#
# POST /api/v4/groups/{id}/epics/{epic_iid}/award_emoji
# operationId: postApiV4GroupsIdEpicsEpicIidAwardEmoji
export def "groups-epics-award-emoji create" [
  id: int
  epic_iid: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  name: string # Name of the emoji without colons.
]: any -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), epic_iid: (encode-path-segment $epic_iid)} | format pattern "/api/v4/groups/{id}/epics/{epic_iid}/award_emoji"))
  let req_body = {"name": $name} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Get a single emoji reaction
#
# GET /api/v4/groups/{id}/epics/{epic_iid}/award_emoji/{award_id}
# operationId: getApiV4GroupsIdEpicsEpicIidAwardEmojiAwardId
export def "groups-epics-award-emoji get" [
  id: int
  epic_iid: int
  award_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), epic_iid: (encode-path-segment $epic_iid), award_id: (encode-path-segment $award_id)} | format pattern "/api/v4/groups/{id}/epics/{epic_iid}/award_emoji/{award_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Delete an emoji reaction
#
# DELETE /api/v4/groups/{id}/epics/{epic_iid}/award_emoji/{award_id}
# operationId: deleteApiV4GroupsIdEpicsEpicIidAwardEmojiAwardId
export def "groups-epics-award-emoji delete" [
  id: int
  epic_iid: int
  award_id: int
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
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), epic_iid: (encode-path-segment $epic_iid), award_id: (encode-path-segment $award_id)} | format pattern "/api/v4/groups/{id}/epics/{epic_iid}/award_emoji/{award_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# List an awardable's emoji reactions for groups
#
# GET /api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji
# operationId: getApiV4GroupsIdEpicsEpicIidNotesNoteIdAwardEmoji
export def "groups-epics-notes-award-emoji list" [
  id: int
  epic_iid: int
  note_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> table<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({id: (encode-path-segment $id), epic_iid: (encode-path-segment $epic_iid), note_id: (encode-path-segment $note_id)} | format pattern "/api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Add a new emoji reaction
#
# POST /api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji
# operationId: postApiV4GroupsIdEpicsEpicIidNotesNoteIdAwardEmoji
export def "groups-epics-notes-award-emoji create" [
  id: int
  epic_iid: int
  note_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  name: string # Name of the emoji without colons.
]: any -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), epic_iid: (encode-path-segment $epic_iid), note_id: (encode-path-segment $note_id)} | format pattern "/api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji"))
  let req_body = {"name": $name} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Get a single emoji reaction
#
# GET /api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji/{award_id}
# operationId: getApiV4GroupsIdEpicsEpicIidNotesNoteIdAwardEmojiAwardId
export def "groups-epics-notes-award-emoji get" [
  id: int
  epic_iid: int
  note_id: int
  award_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), epic_iid: (encode-path-segment $epic_iid), note_id: (encode-path-segment $note_id), award_id: (encode-path-segment $award_id)} | format pattern "/api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji/{award_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Delete an emoji reaction
#
# DELETE /api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji/{award_id}
# operationId: deleteApiV4GroupsIdEpicsEpicIidNotesNoteIdAwardEmojiAwardId
export def "groups-epics-notes-award-emoji delete" [
  id: int
  epic_iid: int
  note_id: int
  award_id: int
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
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), epic_iid: (encode-path-segment $epic_iid), note_id: (encode-path-segment $note_id), award_id: (encode-path-segment $award_id)} | format pattern "/api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji/{award_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Gets a list of group badges viewable by the authenticated user.
#
# GET /api/v4/groups/{id}/badges
# operationId: getApiV4GroupsIdBadges
export def "groups-badges list" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
  --name: string # Name for the badge
]: nothing -> table<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "name" $name "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}/badges") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Adds a badge to a group.
#
# POST /api/v4/groups/{id}/badges
# operationId: postApiV4GroupsIdBadges
export def "groups-badges create" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  link_url: string # URL of the badge link
  image_url: string # URL of the badge image
  --name: string # Name for the badge
]: any -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}/badges"))
  let req_body = {"link_url": $link_url, "image_url": $image_url, "name": $name} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Preview a badge from a group.
#
# GET /api/v4/groups/{id}/badges/render
# operationId: getApiV4GroupsIdBadgesRender
export def "groups-badges-render get" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --link-url: string # URL of the badge link
  --image-url: string # URL of the badge image
]: nothing -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "link_url" $link_url "scalar") (serialize-qp "image_url" $image_url "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}/badges/render") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Gets a badge of a group.
#
# GET /api/v4/groups/{id}/badges/{badge_id}
# operationId: getApiV4GroupsIdBadgesBadgeId
export def "groups-badges get" [
  id: string
  badge_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), badge_id: (encode-path-segment $badge_id)} | format pattern "/api/v4/groups/{id}/badges/{badge_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Updates a badge of a group.
#
# PUT /api/v4/groups/{id}/badges/{badge_id}
# operationId: putApiV4GroupsIdBadgesBadgeId
export def "groups-badges update" [
  id: string
  badge_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --link-url: string # URL of the badge link
  --image-url: string # URL of the badge image
  --name: string # Name for the badge
]: any -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), badge_id: (encode-path-segment $badge_id)} | format pattern "/api/v4/groups/{id}/badges/{badge_id}"))
  let req_body = {"link_url": $link_url, "image_url": $image_url, "name": $name} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Removes a badge from the group.
#
# DELETE /api/v4/groups/{id}/badges/{badge_id}
# operationId: deleteApiV4GroupsIdBadgesBadgeId
export def "groups-badges delete" [
  id: string
  badge_id: int
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
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), badge_id: (encode-path-segment $badge_id)} | format pattern "/api/v4/groups/{id}/badges/{badge_id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Get all custom attributes on a group
#
# GET /api/v4/groups/{id}/custom_attributes
# operationId: getApiV4GroupsIdCustomAttributes
export def "groups-custom-attributes list" [
  id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<key: string, value: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}/custom_attributes"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Get a custom attribute on a group
#
# GET /api/v4/groups/{id}/custom_attributes/{key}
# operationId: getApiV4GroupsIdCustomAttributesKey
export def "groups-custom-attributes get" [
  id: int
  key: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<key: string, value: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), key: (encode-path-segment $key)} | format pattern "/api/v4/groups/{id}/custom_attributes/{key}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Set a custom attribute on a group
#
# PUT /api/v4/groups/{id}/custom_attributes/{key}
# operationId: putApiV4GroupsIdCustomAttributesKey
export def "groups-custom-attributes update" [
  id: int
  key: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  value: string # The value of the custom attribute
]: any -> record<key: string, value: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), key: (encode-path-segment $key)} | format pattern "/api/v4/groups/{id}/custom_attributes/{key}"))
  let req_body = {"value": $value} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Delete a custom attribute on a group
#
# DELETE /api/v4/groups/{id}/custom_attributes/{key}
# operationId: deleteApiV4GroupsIdCustomAttributesKey
export def "groups-custom-attributes delete" [
  id: int
  key: string
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
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id), key: (encode-path-segment $key)} | format pattern "/api/v4/groups/{id}/custom_attributes/{key}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Get a groups list
#
# GET /api/v4/groups
# operationId: getApiV4Groups
export def "groups list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --statistics: oneof<nothing, bool> # Include project statistics (default: false)
  --archived: oneof<nothing, bool> # Limit by archived status
  --skip-groups: list<int> # Array of group ids to exclude from list
  --all-available: oneof<nothing, bool> # When `true`, returns all accessible groups. When `false`, returns only groups where the user is a member.
  --visibility: string@visibility-completer # Limit by visibility
  --search: string # Search for a specific group
  --owned: oneof<nothing, bool> # Limit by owned by authenticated user (default: false)
  --order-by: string@order-by-completer # Order by name, path, id or similarity if searching (default: name)
  --qp-sort: string@sort-completer # Sort by asc (ascending) or desc (descending) (default: asc)
  --min-access-level: int@min-access-level-completer # Minimum access level of authenticated user (format: int32)
  --top-level-only: oneof<nothing, bool> # Only include top-level groups
  --marked-for-deletion-on: string # Return groups that are marked for deletion on this date (format: date)
  --active: oneof<nothing, bool> # Limit by groups that are not archived and not marked for deletion
  --repository-storage: string # Filter by repository storage used by the group
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
  --with-custom-attributes: oneof<nothing, bool> # Include custom attributes in the response (default: false)
]: nothing -> table<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "statistics" $statistics "scalar") (serialize-qp "archived" $archived "scalar") (serialize-qp "skip_groups" $skip_groups "csv") (serialize-qp "all_available" $all_available "scalar") (serialize-qp "visibility" $visibility "scalar") (serialize-qp "search" $search "scalar") (serialize-qp "owned" $owned "scalar") (serialize-qp "order_by" $order_by "scalar") (serialize-qp "sort" $qp_sort "scalar") (serialize-qp "min_access_level" $min_access_level "scalar") (serialize-qp "top_level_only" $top_level_only "scalar") (serialize-qp "marked_for_deletion_on" $marked_for_deletion_on "scalar") (serialize-qp "active" $active "scalar") (serialize-qp "repository_storage" $repository_storage "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "with_custom_attributes" $with_custom_attributes "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v4/groups" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Create a group. Available only for users who can create groups.
#
# POST /api/v4/groups
# operationId: postApiV4Groups
# --default_branch_protection_defaults shape: {allowed_to_push?: list, allow_force_push?: bool, allowed_to_merge?: list, code_owner_approval_required?: bool, developer_can_initial_push?: bool}
# --foundational_agents_statuses item shape: {reference: string, enabled: bool}
# --ai_settings_attributes shape: {duo_agent_platform_enabled?: bool, duo_workflow_mcp_enabled?: bool, ai_usage_data_collection_enabled?: bool, ai_catalog_restricted_to_group_hierarchy?: bool, foundational_agents_default_enabled?: bool, prompt_injection_protection_level?: "no_checks"|"log_only"|"interrupt", include_recommended_allowed?: bool, allow_all_unix_sockets?: bool, allow_project_extension?: bool, minimum_access_level_execute?: "10"|"15"|"20"|"30"|"40"|"50", minimum_access_level_execute_async?: "30"|"40"|"50", ... (2 more fields)}
export def "groups create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  name: string # The name of the group
  path: string # The path of the group
  --parent-id: int # The parent group id for creating nested group (format: int32)
  --organization-id: int # The organization id for the group (format: int32, default: {})
  --description: string # The description of the group
  --visibility: string@visibility-completer # The visibility of the group
  --avatar: path # Avatar image for the group
  --share-with-group-lock: oneof<nothing, bool> # Prevent sharing a project with another group within this group
  --require-two-factor-authentication: oneof<nothing, bool> # Require all users in this group to setup Two-factor authentication
  --two-factor-grace-period: int # Time before Two-factor authentication is enforced (format: int32)
  --project-creation-level: string@project-creation-level-completer # Determine if developers can create projects in the group
  --auto-devops-enabled: oneof<nothing, bool> # Default to Auto DevOps pipeline for all projects within this group
  --subgroup-creation-level: string@subgroup-creation-level-completer # Allowed to create subgroups
  --emails-disabled: oneof<nothing, bool> # _(Deprecated)_ Disable email notifications. Use: emails_enabled
  --emails-enabled: oneof<nothing, bool> # Enable email notifications
  --show-diff-preview-in-email: oneof<nothing, bool> # Include the code diff preview in merge request notification emails
  --mentions-disabled: oneof<nothing, bool> # Disable a group from getting mentioned
  --lfs-enabled: oneof<nothing, bool> # Enable/disable LFS for the projects in this group
  --request-access-enabled: oneof<nothing, bool> # Allow users to request member access
  --default-branch: string # The default branch of group's projects (e.g. main)
  --default-branch-protection: int@default-branch-protection-completer # Determine if developers can push to default branch (format: int32)
  --default-branch-protection-defaults: record # Determine if developers can push to default branch — shape: {allowed_to_push?: list, allow_force_push?: bool, allowed_to_merge?: list, code_owner_approval_required?: bool, developer_can_initial_push?: bool}
  --enabled-git-access-protocol: string@enabled-git-access-protocol-completer # Allow only the selected protocols to be used for Git access.
  --membership-lock: oneof<nothing, bool> # Prevent adding new members to projects within this group
  --ldap-cn: string # LDAP Common Name
  --ldap-access: int # A valid access level (format: int32)
  --shared-runners-minutes-limit: int # (admin-only) compute minutes quota for this group (format: int32)
  --extra-shared-runners-minutes-limit: int # (admin-only) Extra compute minutes quota for this group (format: int32)
  --wiki-access-level: string@wiki-access-level-completer # Wiki access level. One of `disabled`, `private` or `enabled`
  --duo-availability: string@duo-availability-completer # Duo availability. One of `default_on`, `default_off` or `never_on`
  --duo-remote-flows-availability: oneof<nothing, bool> # Enable GitLab Duo remote flows for this group
  --duo-foundational-flows-availability: oneof<nothing, bool> # Enable GitLab foundational Duo flows for this group
  --duo-custom-agents-availability: oneof<nothing, bool> # Enable GitLab Duo custom agents for this group
  --duo-custom-flows-availability: oneof<nothing, bool> # Enable GitLab Duo custom flows for this group
  --duo-external-agents-availability: oneof<nothing, bool> # Enable GitLab Duo external agents for this group
  --tool-approval-for-session-availability: string@tool-approval-for-session-availability-completer # Tool approval for session availability. One of `default_on`, `default_off` or `never_on`
  --amazon-q-auto-review-enabled: oneof<nothing, bool> # Enable Amazon Q auto review for merge request
  --experiment-features-enabled: oneof<nothing, bool> # Enable experiment features for this group
  --model-prompt-cache-enabled: oneof<nothing, bool> # Enable model prompt cache for this group
  --foundational-agents-statuses: list # Whether each foundational agent has been enabled or disabled. — item shape: {reference: string, enabled: bool}
  --ai-settings-attributes: record # AI-related settings — shape: {duo_agent_platform_enabled?: bool, duo_workflow_mcp_enabled?: bool, ai_usage_data_collection_enabled?: bool, ai_catalog_restricted_to_group_hierarchy?: bool, foundational_agents_default_enabled?: bool, prompt_injection_protection_level?: "no_checks"|"log_only"|"interrupt", include_recommended_allowed?: bool, allow_all_unix_sockets?: bool, allow_project_extension?: bool, minimum_access_level_execute?: "10"|"15"|"20"|"30"|"40"|"50", minimum_access_level_execute_async?: "30"|"40"|"50", ... (2 more fields)}
]: any -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/v4/groups")
  let req_body = {"name": $name, "path": $path, "parent_id": $parent_id, "organization_id": $organization_id, "description": $description, "visibility": $visibility, "avatar": $avatar, "share_with_group_lock": $share_with_group_lock, "require_two_factor_authentication": $require_two_factor_authentication, "two_factor_grace_period": $two_factor_grace_period, "project_creation_level": $project_creation_level, "auto_devops_enabled": $auto_devops_enabled, "subgroup_creation_level": $subgroup_creation_level, "emails_disabled": $emails_disabled, "emails_enabled": $emails_enabled, "show_diff_preview_in_email": $show_diff_preview_in_email, "mentions_disabled": $mentions_disabled, "lfs_enabled": $lfs_enabled, "request_access_enabled": $request_access_enabled, "default_branch": $default_branch, "default_branch_protection": $default_branch_protection, "default_branch_protection_defaults": $default_branch_protection_defaults, "enabled_git_access_protocol": $enabled_git_access_protocol, "membership_lock": $membership_lock, "ldap_cn": $ldap_cn, "ldap_access": $ldap_access, "shared_runners_minutes_limit": $shared_runners_minutes_limit, "extra_shared_runners_minutes_limit": $extra_shared_runners_minutes_limit, "wiki_access_level": $wiki_access_level, "duo_availability": $duo_availability, "duo_remote_flows_availability": $duo_remote_flows_availability, "duo_foundational_flows_availability": $duo_foundational_flows_availability, "duo_custom_agents_availability": $duo_custom_agents_availability, "duo_custom_flows_availability": $duo_custom_flows_availability, "duo_external_agents_availability": $duo_external_agents_availability, "tool_approval_for_session_availability": $tool_approval_for_session_availability, "amazon_q_auto_review_enabled": $amazon_q_auto_review_enabled, "experiment_features_enabled": $experiment_features_enabled, "model_prompt_cache_enabled": $model_prompt_cache_enabled, "foundational_agents_statuses": $foundational_agents_statuses, "ai_settings_attributes": $ai_settings_attributes} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Update a group. Available only for users who can administrate groups.
#
# PUT /api/v4/groups/{id}
# operationId: putApiV4GroupsId
# --default_branch_protection_defaults shape: {allowed_to_push?: list, allow_force_push?: bool, allowed_to_merge?: list, code_owner_approval_required?: bool, developer_can_initial_push?: bool}
# --foundational_agents_statuses item shape: {reference: string, enabled: bool}
# --ai_settings_attributes shape: {duo_agent_platform_enabled?: bool, duo_workflow_mcp_enabled?: bool, ai_usage_data_collection_enabled?: bool, ai_catalog_restricted_to_group_hierarchy?: bool, foundational_agents_default_enabled?: bool, prompt_injection_protection_level?: "no_checks"|"log_only"|"interrupt", include_recommended_allowed?: bool, allow_all_unix_sockets?: bool, allow_project_extension?: bool, minimum_access_level_execute?: "10"|"15"|"20"|"30"|"40"|"50", minimum_access_level_execute_async?: "30"|"40"|"50", ... (2 more fields)}
# --duo_namespace_access_rules item shape: {through_namespace?: record, features: list<string>}
export def "groups update" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --name: string # The name of the group
  --path: string # The path of the group
  --shared-runners-setting: string@shared-runners-setting-completer # Enable/disable shared runners for the group and its subgroups and projects
  --description: string # The description of the group
  --visibility: string@visibility-completer # The visibility of the group
  --avatar: path # Avatar image for the group
  --share-with-group-lock: oneof<nothing, bool> # Prevent sharing a project with another group within this group
  --require-two-factor-authentication: oneof<nothing, bool> # Require all users in this group to setup Two-factor authentication
  --two-factor-grace-period: int # Time before Two-factor authentication is enforced (format: int32)
  --project-creation-level: string@project-creation-level-completer # Determine if developers can create projects in the group
  --auto-devops-enabled: oneof<nothing, bool> # Default to Auto DevOps pipeline for all projects within this group
  --subgroup-creation-level: string@subgroup-creation-level-completer # Allowed to create subgroups
  --emails-disabled: oneof<nothing, bool> # _(Deprecated)_ Disable email notifications. Use: emails_enabled
  --emails-enabled: oneof<nothing, bool> # Enable email notifications
  --show-diff-preview-in-email: oneof<nothing, bool> # Include the code diff preview in merge request notification emails
  --mentions-disabled: oneof<nothing, bool> # Disable a group from getting mentioned
  --lfs-enabled: oneof<nothing, bool> # Enable/disable LFS for the projects in this group
  --request-access-enabled: oneof<nothing, bool> # Allow users to request member access
  --default-branch: string # The default branch of group's projects (e.g. main)
  --default-branch-protection: int@default-branch-protection-completer # Determine if developers can push to default branch (format: int32)
  --default-branch-protection-defaults: record # Determine if developers can push to default branch — shape: {allowed_to_push?: list, allow_force_push?: bool, allowed_to_merge?: list, code_owner_approval_required?: bool, developer_can_initial_push?: bool}
  --enabled-git-access-protocol: string@enabled-git-access-protocol-completer # Allow only the selected protocols to be used for Git access.
  --membership-lock: oneof<nothing, bool> # Prevent adding new members to projects within this group
  --ldap-cn: string # LDAP Common Name
  --ldap-access: int # A valid access level (format: int32)
  --shared-runners-minutes-limit: int # (admin-only) compute minutes quota for this group (format: int32)
  --extra-shared-runners-minutes-limit: int # (admin-only) Extra compute minutes quota for this group (format: int32)
  --wiki-access-level: string@wiki-access-level-completer # Wiki access level. One of `disabled`, `private` or `enabled`
  --duo-availability: string@duo-availability-completer # Duo availability. One of `default_on`, `default_off` or `never_on`
  --duo-remote-flows-availability: oneof<nothing, bool> # Enable GitLab Duo remote flows for this group
  --duo-foundational-flows-availability: oneof<nothing, bool> # Enable GitLab foundational Duo flows for this group
  --duo-custom-agents-availability: oneof<nothing, bool> # Enable GitLab Duo custom agents for this group
  --duo-custom-flows-availability: oneof<nothing, bool> # Enable GitLab Duo custom flows for this group
  --duo-external-agents-availability: oneof<nothing, bool> # Enable GitLab Duo external agents for this group
  --tool-approval-for-session-availability: string@tool-approval-for-session-availability-completer # Tool approval for session availability. One of `default_on`, `default_off` or `never_on`
  --amazon-q-auto-review-enabled: oneof<nothing, bool> # Enable Amazon Q auto review for merge request
  --experiment-features-enabled: oneof<nothing, bool> # Enable experiment features for this group
  --model-prompt-cache-enabled: oneof<nothing, bool> # Enable model prompt cache for this group
  --foundational-agents-statuses: list # Whether each foundational agent has been enabled or disabled. — item shape: {reference: string, enabled: bool}
  --ai-settings-attributes: record # AI-related settings — shape: {duo_agent_platform_enabled?: bool, duo_workflow_mcp_enabled?: bool, ai_usage_data_collection_enabled?: bool, ai_catalog_restricted_to_group_hierarchy?: bool, foundational_agents_default_enabled?: bool, prompt_injection_protection_level?: "no_checks"|"log_only"|"interrupt", include_recommended_allowed?: bool, allow_all_unix_sockets?: bool, allow_project_extension?: bool, minimum_access_level_execute?: "10"|"15"|"20"|"30"|"40"|"50", minimum_access_level_execute_async?: "30"|"40"|"50", ... (2 more fields)}
  --prevent-sharing-groups-outside-hierarchy: oneof<nothing, bool> # Prevent sharing groups within this namespace with any groups outside the namespace. Only available on top-level groups.
  --step-up-auth-required-oauth-provider: string # OAuth provider required for step-up authentication. Pass empty string to disable.
  --lock-math-rendering-limits-enabled: oneof<nothing, bool> # Indicates if math rendering limits are locked for all descendent groups.
  --math-rendering-limits-enabled: oneof<nothing, bool> # Indicates if math rendering limits are used for this group.
  --max-artifacts-size: int # Set the maximum file size for each job's artifacts (format: int32)
  --file-template-project-id: int # The ID of a project to use for custom templates in this group (format: int32)
  --prevent-forking-outside-group: oneof<nothing, bool> # Prevent forking projects inside this group to external namespaces
  --unique-project-download-limit: int # Maximum number of unique projects a user can download in the specified time period before they are banned. (format: int32)
  --unique-project-download-limit-interval-in-seconds: int # Time period during which a user can download a maximum amount of projects before they are banned. (format: int32)
  --unique-project-download-limit-allowlist: list<string> # List of usernames excluded from the unique project download limit
  --unique-project-download-limit-alertlist: list<int> # List of user ids who will be emailed when Git abuse rate limit is exceeded
  --auto-ban-user-on-excessive-projects-download: oneof<nothing, bool> # Ban users from the group when they exceed maximum number of unique projects download in the specified time period
  --ip-restriction-ranges: string # List of IP addresses which need to be restricted for group
  --allowed-email-domains-list: string # List of allowed email domains for group
  --service-access-tokens-expiration-enforced: oneof<nothing, bool> # To enforce token expiration for Service accounts users for group
  --duo-core-features-enabled: oneof<nothing, bool> # [Experimental] Indicates whether GitLab Duo Core features are enabled for the group
  --duo-features-enabled: oneof<nothing, bool> # Indicates whether GitLab Duo features are enabled for the group
  --lock-duo-features-enabled: oneof<nothing, bool> # Indicates if the GitLab Duo features enabled setting is enforced for all subgroups
  --auto-duo-code-review-enabled: oneof<nothing, bool> # Enable automatic reviews by GitLab Duo on merge requests
  --web-based-commit-signing-enabled: oneof<nothing, bool> # Enable web based commit signing for this group
  --only-allow-merge-if-pipeline-succeeds: oneof<nothing, bool> # Only allow to merge if builds succeed
  --allow-merge-on-skipped-pipeline: oneof<nothing, bool> # Allow to merge if pipeline is skipped
  --only-allow-merge-if-all-discussions-are-resolved: oneof<nothing, bool> # Only allow to merge if all threads are resolved
  --enabled-foundational-flows: list<string> # References of enabled foundational flows
  --duo-template-project-id: int # The ID of a project to use as the Duo Code Review custom instructions template for this group (format: int32)
  --allow-personal-snippets: oneof<nothing, bool> # Allow creation of personal snippets for enterprise users of this group
  --duo-namespace-access-rules: list # AI entity access rules for controlling Duo feature access — item shape: {through_namespace?: record, features: list<string>}
  --built-in-project-templates-enabled: oneof<nothing, bool> # Enable built-in project templates for project creation
  --lock-built-in-project-templates-enabled: oneof<nothing, bool> # Enforce the built-in project templates setting for all subgroups
]: any -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}"))
  let req_body = {"name": $name, "path": $path, "shared_runners_setting": $shared_runners_setting, "description": $description, "visibility": $visibility, "avatar": $avatar, "share_with_group_lock": $share_with_group_lock, "require_two_factor_authentication": $require_two_factor_authentication, "two_factor_grace_period": $two_factor_grace_period, "project_creation_level": $project_creation_level, "auto_devops_enabled": $auto_devops_enabled, "subgroup_creation_level": $subgroup_creation_level, "emails_disabled": $emails_disabled, "emails_enabled": $emails_enabled, "show_diff_preview_in_email": $show_diff_preview_in_email, "mentions_disabled": $mentions_disabled, "lfs_enabled": $lfs_enabled, "request_access_enabled": $request_access_enabled, "default_branch": $default_branch, "default_branch_protection": $default_branch_protection, "default_branch_protection_defaults": $default_branch_protection_defaults, "enabled_git_access_protocol": $enabled_git_access_protocol, "membership_lock": $membership_lock, "ldap_cn": $ldap_cn, "ldap_access": $ldap_access, "shared_runners_minutes_limit": $shared_runners_minutes_limit, "extra_shared_runners_minutes_limit": $extra_shared_runners_minutes_limit, "wiki_access_level": $wiki_access_level, "duo_availability": $duo_availability, "duo_remote_flows_availability": $duo_remote_flows_availability, "duo_foundational_flows_availability": $duo_foundational_flows_availability, "duo_custom_agents_availability": $duo_custom_agents_availability, "duo_custom_flows_availability": $duo_custom_flows_availability, "duo_external_agents_availability": $duo_external_agents_availability, "tool_approval_for_session_availability": $tool_approval_for_session_availability, "amazon_q_auto_review_enabled": $amazon_q_auto_review_enabled, "experiment_features_enabled": $experiment_features_enabled, "model_prompt_cache_enabled": $model_prompt_cache_enabled, "foundational_agents_statuses": $foundational_agents_statuses, "ai_settings_attributes": $ai_settings_attributes, "prevent_sharing_groups_outside_hierarchy": $prevent_sharing_groups_outside_hierarchy, "step_up_auth_required_oauth_provider": $step_up_auth_required_oauth_provider, "lock_math_rendering_limits_enabled": $lock_math_rendering_limits_enabled, "math_rendering_limits_enabled": $math_rendering_limits_enabled, "max_artifacts_size": $max_artifacts_size, "file_template_project_id": $file_template_project_id, "prevent_forking_outside_group": $prevent_forking_outside_group, "unique_project_download_limit": $unique_project_download_limit, "unique_project_download_limit_interval_in_seconds": $unique_project_download_limit_interval_in_seconds, "unique_project_download_limit_allowlist": $unique_project_download_limit_allowlist, "unique_project_download_limit_alertlist": $unique_project_download_limit_alertlist, "auto_ban_user_on_excessive_projects_download": $auto_ban_user_on_excessive_projects_download, "ip_restriction_ranges": $ip_restriction_ranges, "allowed_email_domains_list": $allowed_email_domains_list, "service_access_tokens_expiration_enforced": $service_access_tokens_expiration_enforced, "duo_core_features_enabled": $duo_core_features_enabled, "duo_features_enabled": $duo_features_enabled, "lock_duo_features_enabled": $lock_duo_features_enabled, "auto_duo_code_review_enabled": $auto_duo_code_review_enabled, "web_based_commit_signing_enabled": $web_based_commit_signing_enabled, "only_allow_merge_if_pipeline_succeeds": $only_allow_merge_if_pipeline_succeeds, "allow_merge_on_skipped_pipeline": $allow_merge_on_skipped_pipeline, "only_allow_merge_if_all_discussions_are_resolved": $only_allow_merge_if_all_discussions_are_resolved, "enabled_foundational_flows": $enabled_foundational_flows, "duo_template_project_id": $duo_template_project_id, "allow_personal_snippets": $allow_personal_snippets, "duo_namespace_access_rules": $duo_namespace_access_rules, "built_in_project_templates_enabled": $built_in_project_templates_enabled, "lock_built_in_project_templates_enabled": $lock_built_in_project_templates_enabled} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Get a single group, with containing projects.
#
# GET /api/v4/groups/{id}
# operationId: getApiV4GroupsId
export def "groups get" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --with-custom-attributes: oneof<nothing, bool> # Include custom attributes in the response (default: false)
  --with-projects: oneof<nothing, bool> # Omit project details (default: true)
]: nothing -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool, shared_with_groups: list<record>, runners_token: string, enabled_git_access_protocol: string, prevent_sharing_groups_outside_hierarchy: bool, step_up_auth_required_oauth_provider: string, projects: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list<string>, topics: list<string>, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record<key: string, name: string, nickname: string, html_url: string, source_url: string>, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record<id: int, name: string, path: string, kind: string, full_path: string, parent_id: int, avatar_url: string, web_url: string>, custom_attributes: record<key: string, value: string>, repository_storage: string, forked_from_project: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list, topics: list, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record, custom_attributes: record, repository_storage: string>, container_registry_image_prefix: string, _links: record<self: string, issues: string, merge_requests: string, repo_branches: string, labels: string, events: string, members: string, cluster_agents: string>, marked_for_deletion_at: string, marked_for_deletion_on: string, packages_enabled: bool, empty_repo: bool, archived: bool, owner: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, resolve_outdated_diff_discussions: bool, container_expiration_policy: record<cadence: string, enabled: string, keep_n: string, older_than: string, name_regex: string, name_regex_keep: string, next_run_at: string>, repository_object_format: string, issues_enabled: bool, merge_requests_enabled: bool, wiki_enabled: bool, jobs_enabled: bool, snippets_enabled: bool, container_registry_enabled: bool, service_desk_enabled: bool, service_desk_address: string, can_create_merge_request_in: bool, issues_access_level: string, repository_access_level: string, merge_requests_access_level: string, forking_access_level: string, wiki_access_level: string, builds_access_level: string, snippets_access_level: string, pages_access_level: string, analytics_access_level: string, container_registry_access_level: string, security_and_compliance_access_level: string, releases_access_level: string, environments_access_level: string, feature_flags_access_level: string, infrastructure_access_level: string, monitor_access_level: string, model_experiments_access_level: string, model_registry_access_level: string, package_registry_access_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, shared_runners_enabled: bool, lfs_enabled: bool, creator_id: int, mr_default_target_self: bool, import_url: string, import_type: string, import_status: string, import_error: string, open_issues_count: int, description_html: string, updated_at: string, ci_default_git_depth: int, ci_delete_pipelines_in_seconds: int, ci_forward_deployment_enabled: bool, ci_forward_deployment_rollback_allowed: bool, ci_job_token_scope_enabled: bool, ci_separated_caches: bool, ci_allow_fork_pipelines_to_run_in_parent_project: bool, ci_id_token_sub_claim_components: list<string>, build_git_strategy: string, keep_latest_artifact: bool, restrict_user_defined_variables: bool, ci_pipeline_variables_minimum_override_role: string, runner_token_expiration_interval: int, group_runners_enabled: bool, resource_group_default_process_mode: string, auto_cancel_pending_pipelines: string, build_timeout: int, auto_devops_enabled: bool, auto_devops_deploy_strategy: string, ci_push_repository_for_job_token_allowed: bool, protect_merge_request_pipelines: bool, ci_display_pipeline_variables: bool, runners_token: string, ci_config_path: string, public_jobs: bool, shared_with_groups: list<record>, only_allow_merge_if_pipeline_succeeds: bool, allow_merge_on_skipped_pipeline: bool, request_access_enabled: bool, only_allow_merge_if_all_discussions_are_resolved: bool, remove_source_branch_after_merge: bool, printing_merge_request_link_enabled: bool, merge_method: string, squash_option: string, enforce_auth_checks_on_uploads: bool, suggestion_commit_message: string, merge_commit_template: string, squash_commit_template: string, mr_default_title_template: string, issue_branch_template: string, statistics: record<commit_count: int, storage_size: int, repository_size: int, wiki_size: int, lfs_objects_size: int, job_artifacts_size: int, pipeline_artifacts_size: int, packages_size: int, snippets_size: int, uploads_size: int, container_registry_size: int>, warn_about_potentially_unwanted_characters: bool, autoclose_referenced_issues: bool, max_artifacts_size: int, approvals_before_merge: string, mirror: string, mirror_user_id: string, mirror_trigger_builds: string, only_mirror_protected_branches: string, mirror_overwrites_diverged_branches: string, external_authorization_classification_label: string, requirements_enabled: string, requirements_access_level: string, security_and_compliance_enabled: string, secret_push_protection_enabled: bool, pre_receive_secret_detection_enabled: bool, compliance_frameworks: string, issues_template: string, merge_requests_template: string, ci_restrict_pipeline_cancellation_role: string, merge_pipelines_enabled: string, merge_trains_enabled: string, merge_trains_skip_train_allowed: string, max_pipelines_per_merge_train: string, only_allow_merge_if_all_status_checks_passed: string, allow_pipeline_trigger_approve_deployment: bool, prevent_merge_without_jira_issue: string, auto_duo_code_review_enabled: string, duo_remote_flows_enabled: string, duo_foundational_flows_enabled: string, duo_sast_fp_detection_enabled: string, duo_secret_detection_fp_enabled: string, duo_sast_vr_workflow_enabled: string, web_based_commit_signing_enabled: string, spp_repository_pipeline_access: bool, security_policy_pipeline_must_succeed: bool, merge_request_title_regex: string, merge_request_title_regex_description: string>, shared_projects: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list<string>, topics: list<string>, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record<key: string, name: string, nickname: string, html_url: string, source_url: string>, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record<id: int, name: string, path: string, kind: string, full_path: string, parent_id: int, avatar_url: string, web_url: string>, custom_attributes: record<key: string, value: string>, repository_storage: string, forked_from_project: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list, topics: list, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record, custom_attributes: record, repository_storage: string>, container_registry_image_prefix: string, _links: record<self: string, issues: string, merge_requests: string, repo_branches: string, labels: string, events: string, members: string, cluster_agents: string>, marked_for_deletion_at: string, marked_for_deletion_on: string, packages_enabled: bool, empty_repo: bool, archived: bool, owner: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, resolve_outdated_diff_discussions: bool, container_expiration_policy: record<cadence: string, enabled: string, keep_n: string, older_than: string, name_regex: string, name_regex_keep: string, next_run_at: string>, repository_object_format: string, issues_enabled: bool, merge_requests_enabled: bool, wiki_enabled: bool, jobs_enabled: bool, snippets_enabled: bool, container_registry_enabled: bool, service_desk_enabled: bool, service_desk_address: string, can_create_merge_request_in: bool, issues_access_level: string, repository_access_level: string, merge_requests_access_level: string, forking_access_level: string, wiki_access_level: string, builds_access_level: string, snippets_access_level: string, pages_access_level: string, analytics_access_level: string, container_registry_access_level: string, security_and_compliance_access_level: string, releases_access_level: string, environments_access_level: string, feature_flags_access_level: string, infrastructure_access_level: string, monitor_access_level: string, model_experiments_access_level: string, model_registry_access_level: string, package_registry_access_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, shared_runners_enabled: bool, lfs_enabled: bool, creator_id: int, mr_default_target_self: bool, import_url: string, import_type: string, import_status: string, import_error: string, open_issues_count: int, description_html: string, updated_at: string, ci_default_git_depth: int, ci_delete_pipelines_in_seconds: int, ci_forward_deployment_enabled: bool, ci_forward_deployment_rollback_allowed: bool, ci_job_token_scope_enabled: bool, ci_separated_caches: bool, ci_allow_fork_pipelines_to_run_in_parent_project: bool, ci_id_token_sub_claim_components: list<string>, build_git_strategy: string, keep_latest_artifact: bool, restrict_user_defined_variables: bool, ci_pipeline_variables_minimum_override_role: string, runner_token_expiration_interval: int, group_runners_enabled: bool, resource_group_default_process_mode: string, auto_cancel_pending_pipelines: string, build_timeout: int, auto_devops_enabled: bool, auto_devops_deploy_strategy: string, ci_push_repository_for_job_token_allowed: bool, protect_merge_request_pipelines: bool, ci_display_pipeline_variables: bool, runners_token: string, ci_config_path: string, public_jobs: bool, shared_with_groups: list<record>, only_allow_merge_if_pipeline_succeeds: bool, allow_merge_on_skipped_pipeline: bool, request_access_enabled: bool, only_allow_merge_if_all_discussions_are_resolved: bool, remove_source_branch_after_merge: bool, printing_merge_request_link_enabled: bool, merge_method: string, squash_option: string, enforce_auth_checks_on_uploads: bool, suggestion_commit_message: string, merge_commit_template: string, squash_commit_template: string, mr_default_title_template: string, issue_branch_template: string, statistics: record<commit_count: int, storage_size: int, repository_size: int, wiki_size: int, lfs_objects_size: int, job_artifacts_size: int, pipeline_artifacts_size: int, packages_size: int, snippets_size: int, uploads_size: int, container_registry_size: int>, warn_about_potentially_unwanted_characters: bool, autoclose_referenced_issues: bool, max_artifacts_size: int, approvals_before_merge: string, mirror: string, mirror_user_id: string, mirror_trigger_builds: string, only_mirror_protected_branches: string, mirror_overwrites_diverged_branches: string, external_authorization_classification_label: string, requirements_enabled: string, requirements_access_level: string, security_and_compliance_enabled: string, secret_push_protection_enabled: bool, pre_receive_secret_detection_enabled: bool, compliance_frameworks: string, issues_template: string, merge_requests_template: string, ci_restrict_pipeline_cancellation_role: string, merge_pipelines_enabled: string, merge_trains_enabled: string, merge_trains_skip_train_allowed: string, max_pipelines_per_merge_train: string, only_allow_merge_if_all_status_checks_passed: string, allow_pipeline_trigger_approve_deployment: bool, prevent_merge_without_jira_issue: string, auto_duo_code_review_enabled: string, duo_remote_flows_enabled: string, duo_foundational_flows_enabled: string, duo_sast_fp_detection_enabled: string, duo_secret_detection_fp_enabled: string, duo_sast_vr_workflow_enabled: string, web_based_commit_signing_enabled: string, spp_repository_pipeline_access: bool, security_policy_pipeline_must_succeed: bool, merge_request_title_regex: string, merge_request_title_regex_description: string>, shared_runners_minutes_limit: string, extra_shared_runners_minutes_limit: string, prevent_forking_outside_group: string, service_access_tokens_expiration_enforced: string, experiment_features_enabled: string, membership_lock: string, ip_restriction_ranges: string, allowed_email_domains_list: string, only_allow_merge_if_pipeline_succeeds: string, allow_merge_on_skipped_pipeline: string, only_allow_merge_if_all_discussions_are_resolved: string, unique_project_download_limit: string, unique_project_download_limit_interval_in_seconds: string, unique_project_download_limit_allowlist: string, unique_project_download_limit_alertlist: string, auto_ban_user_on_excessive_projects_download: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "with_custom_attributes" $with_custom_attributes "scalar") (serialize-qp "with_projects" $with_projects "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Remove a group.
#
# DELETE /api/v4/groups/{id}
# operationId: deleteApiV4GroupsId
export def "groups delete" [
  id: string
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
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Archive a group
#
# POST /api/v4/groups/{id}/archive
# operationId: postApiV4GroupsIdArchive
export def "groups-archive create" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/api/v4/groups/{id}/archive"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}
