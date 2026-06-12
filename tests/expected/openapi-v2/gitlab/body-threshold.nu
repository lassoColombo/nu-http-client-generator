# Auto-generated client for GitLab API vv4
# Source: <spec>
# Auth: --token flag or $env.GITLAB_API_TOKEN

const BASE_URL = "https://gitlab.com"
const DEFAULT_AUTH = "private-token"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o GITLAB_API_TOKEN | default "" }
  let scheme = ($auth_scheme | default "bearer")
  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }
  match $scheme {
    "private-token" => { {headers: {PRIVATE-TOKEN: $token_val}, query: ""} }
    "query-private_token" => { {headers: {}, query: $"private_token=($token_val)"} }
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
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "dry-run" "accept" "help"]
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
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: table<key: string, value: string>, web_url: string, requested_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/access_requests" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Requests access for the authenticated user to a group.
#
# POST /api/v4/groups/{id}/access_requests
# operationId: postApiV4GroupsIdAccessRequests
export def "groups-access-requests post" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: table<key: string, value: string>, web_url: string, requested_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/access_requests")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Approves an access request for the given user.
#
# PUT /api/v4/groups/{id}/access_requests/{user_id}/approve
# operationId: putApiV4GroupsIdAccessRequestsUserIdApprove
export def "groups-access-requests-approve put" [
  id: string
  user_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --access-level: int # A valid access level (defaults: `30`, the Developer role) (format: int32, default: 30)
]: any -> record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: table<key: string, value: string>, web_url: string, access_level: string, created_at: string, created_by: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, expires_at: string, group_saml_identity: record<provider: string, extern_uid: string, saml_provider_id: string>, group_scim_identity: record<extern_uid: string, group_id: string, active: string>, email: string, is_using_seat: string, override: string, membership_state: string, member_role: record<id: int, group_id: int, name: any, description: any, base_access_level: int, apply_security_scan_profiles: bool, admin_merge_request: bool, archive_project: bool, admin_ai_catalog_item_consumer: bool, remove_project: bool, remove_group: bool, manage_security_policy_link: bool, admin_ai_catalog_item: bool, admin_compliance_framework: bool, admin_cicd_variables: bool, manage_deploy_tokens: bool, manage_group_access_tokens: bool, admin_group_member: bool, admin_integrations: bool, manage_merge_request_settings: bool, manage_project_access_tokens: bool, admin_protected_branch: bool, admin_protected_environments: bool, admin_push_rules: bool, admin_runners: bool, admin_security_attributes: bool, admin_terraform_state: bool, admin_vulnerability: bool, admin_web_hook: bool, read_compliance_dashboard: bool, read_security_scan_profiles: bool, read_virtual_registry: bool, update_sast_vulnerability_resolution_setting: bool, read_admin_cicd: bool, read_crm_contact: bool, read_dependency: bool, read_admin_groups: bool, read_admin_projects: bool, read_code: bool, read_runners: bool, read_security_attribute: bool, read_admin_subscription: bool, read_admin_monitoring: bool, read_admin_users: bool, read_vulnerability: bool>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/access_requests/($user_id)/approve")
  let body = {access_level: $access_level} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
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
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/access_requests/($user_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
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
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> table<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/award_emoji" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Add a new emoji reaction
#
# POST /api/v4/groups/{id}/epics/{epic_iid}/award_emoji
# operationId: postApiV4GroupsIdEpicsEpicIidAwardEmoji
export def "groups-epics-award-emoji post" [
  id: int
  epic_iid: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  name: string # Name of the emoji without colons.
]: any -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/award_emoji")
  let body = {name: $name} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Get a single emoji reaction
#
# GET /api/v4/groups/{id}/epics/{epic_iid}/award_emoji/{award_id}
# operationId: getApiV4GroupsIdEpicsEpicIidAwardEmojiAwardId
export def "groups-epics-award-emoji get" [
  award_id: int
  id: int
  epic_iid: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/award_emoji/($award_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Delete an emoji reaction
#
# DELETE /api/v4/groups/{id}/epics/{epic_iid}/award_emoji/{award_id}
# operationId: deleteApiV4GroupsIdEpicsEpicIidAwardEmojiAwardId
export def "groups-epics-award-emoji delete" [
  award_id: int
  id: int
  epic_iid: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/award_emoji/($award_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
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
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> table<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/notes/($note_id)/award_emoji" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Add a new emoji reaction
#
# POST /api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji
# operationId: postApiV4GroupsIdEpicsEpicIidNotesNoteIdAwardEmoji
export def "groups-epics-notes-award-emoji post" [
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
  --dry-run(-n) # Return the request that would be sent without executing it
  name: string # Name of the emoji without colons.
]: any -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/notes/($note_id)/award_emoji")
  let body = {name: $name} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Get a single emoji reaction
#
# GET /api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji/{award_id}
# operationId: getApiV4GroupsIdEpicsEpicIidNotesNoteIdAwardEmojiAwardId
export def "groups-epics-notes-award-emoji get" [
  award_id: int
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
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/notes/($note_id)/award_emoji/($award_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Delete an emoji reaction
#
# DELETE /api/v4/groups/{id}/epics/{epic_iid}/notes/{note_id}/award_emoji/{award_id}
# operationId: deleteApiV4GroupsIdEpicsEpicIidNotesNoteIdAwardEmojiAwardId
export def "groups-epics-notes-award-emoji delete" [
  award_id: int
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
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/notes/($note_id)/award_emoji/($award_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
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
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
  --name: string # Name for the badge
]: nothing -> table<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "name" $name "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Adds a badge to a group.
#
# POST /api/v4/groups/{id}/badges
# operationId: postApiV4GroupsIdBadges
export def "groups-badges post" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  link_url: string # URL of the badge link
  image_url: string # URL of the badge image
  --name: string # Name for the badge
]: any -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges")
  let body = {link_url: $link_url, image_url: $image_url, name: $name} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
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
  --dry-run(-n) # Return the request that would be sent without executing it
  --link-url: string # URL of the badge link
  --image-url: string # URL of the badge image
]: nothing -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "link_url" $link_url "scalar") (serialize-qp "image_url" $image_url "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges/render" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
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
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges/($badge_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Updates a badge of a group.
#
# PUT /api/v4/groups/{id}/badges/{badge_id}
# operationId: putApiV4GroupsIdBadgesBadgeId
export def "groups-badges put" [
  id: string
  badge_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --link-url: string # URL of the badge link
  --image-url: string # URL of the badge image
  --name: string # Name for the badge
]: any -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges/($badge_id)")
  let body = {link_url: $link_url, image_url: $image_url, name: $name} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
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
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges/($badge_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
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
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<key: string, value: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/custom_attributes")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get a custom attribute on a group
#
# GET /api/v4/groups/{id}/custom_attributes/{key}
# operationId: getApiV4GroupsIdCustomAttributesKey
export def "groups-custom-attributes get" [
  key: string
  id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<key: string, value: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/custom_attributes/($key)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Set a custom attribute on a group
#
# PUT /api/v4/groups/{id}/custom_attributes/{key}
# operationId: putApiV4GroupsIdCustomAttributesKey
export def "groups-custom-attributes put" [
  key: string
  id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  value: string # The value of the custom attribute
]: any -> record<key: string, value: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/custom_attributes/($key)")
  let body = {value: $value} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Delete a custom attribute on a group
#
# DELETE /api/v4/groups/{id}/custom_attributes/{key}
# operationId: deleteApiV4GroupsIdCustomAttributesKey
export def "groups-custom-attributes delete" [
  key: string
  id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/custom_attributes/($key)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
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
  --dry-run(-n) # Return the request that would be sent without executing it
  --statistics: oneof<nothing, bool> # Include project statistics (default: false)
  --archived: oneof<nothing, bool> # Limit by archived status
  --skip-groups: list # Array of group ids to exclude from list
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
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Create a group. Available only for users who can create groups.
#
# POST /api/v4/groups
# operationId: postApiV4Groups
# --body shape: {name: string, path: string, parent_id?: int, organization_id?: int, description?: string, visibility?: "private"|"internal"|"public", avatar?: path, share_with_group_lock?: bool, require_two_factor_authentication?: bool, two_factor_grace_period?: int, project_creation_level?: "noone"|"owner"|"maintainer"|"developer"|"administrator", auto_devops_enabled?: bool, subgroup_creation_level?: "owner"|"maintainer", emails_disabled?: bool, emails_enabled?: bool, show_diff_preview_in_email?: bool, mentions_disabled?: bool, lfs_enabled?: bool, request_access_enabled?: bool, default_branch?: string, default_branch_protection?: "0"|"3"|"1"|"2"|"4", default_branch_protection_defaults?: record, enabled_git_access_protocol?: "ssh"|"http"|"all", membership_lock?: bool, ldap_cn?: string, ldap_access?: int, shared_runners_minutes_limit?: int, extra_shared_runners_minutes_limit?: int, wiki_access_level?: "disabled"|"private"|"enabled", duo_availability?: "default_on"|"default_off"|"never_on", duo_remote_flows_availability?: bool, duo_foundational_flows_availability?: bool, duo_custom_agents_availability?: bool, duo_custom_flows_availability?: bool, duo_external_agents_availability?: bool, tool_approval_for_session_availability?: "default_on"|"default_off"|"never_on", amazon_q_auto_review_enabled?: bool, experiment_features_enabled?: bool, model_prompt_cache_enabled?: bool, foundational_agents_statuses?: list, ai_settings_attributes?: record}
export def "groups post" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --body: record # shape: {name: string, path: string, parent_id?: int, organization_id?: int, description?: string, visibility?: "private"|"internal"|"public", avatar?: path, share_with_group_lock?: bool, require_two_factor_authentication?: bool, two_factor_grace_period?: int, project_creation_level?: "noone"|"owner"|"maintainer"|"developer"|"administrator", auto_devops_enabled?: bool, subgroup_creation_level?: "owner"|"maintainer", emails_disabled?: bool, emails_enabled?: bool, show_diff_preview_in_email?: bool, mentions_disabled?: bool, lfs_enabled?: bool, request_access_enabled?: bool, default_branch?: string, default_branch_protection?: "0"|"3"|"1"|"2"|"4", default_branch_protection_defaults?: record, enabled_git_access_protocol?: "ssh"|"http"|"all", membership_lock?: bool, ldap_cn?: string, ldap_access?: int, shared_runners_minutes_limit?: int, extra_shared_runners_minutes_limit?: int, wiki_access_level?: "disabled"|"private"|"enabled", duo_availability?: "default_on"|"default_off"|"never_on", duo_remote_flows_availability?: bool, duo_foundational_flows_availability?: bool, duo_custom_agents_availability?: bool, duo_custom_flows_availability?: bool, duo_external_agents_availability?: bool, tool_approval_for_session_availability?: "default_on"|"default_off"|"never_on", amazon_q_auto_review_enabled?: bool, experiment_features_enabled?: bool, model_prompt_cache_enabled?: bool, foundational_agents_statuses?: list, ai_settings_attributes?: record}
]: any -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/v4/groups")
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Update a group. Available only for users who can administrate groups.
#
# PUT /api/v4/groups/{id}
# operationId: putApiV4GroupsId
# --body shape: {name?: string, path?: string, shared_runners_setting?: "disabled_and_unoverridable"|"disabled_and_overridable"|"enabled", description?: string, visibility?: "private"|"internal"|"public", avatar?: path, share_with_group_lock?: bool, require_two_factor_authentication?: bool, two_factor_grace_period?: int, project_creation_level?: "noone"|"owner"|"maintainer"|"developer"|"administrator", auto_devops_enabled?: bool, subgroup_creation_level?: "owner"|"maintainer", emails_disabled?: bool, emails_enabled?: bool, show_diff_preview_in_email?: bool, mentions_disabled?: bool, lfs_enabled?: bool, request_access_enabled?: bool, default_branch?: string, default_branch_protection?: "0"|"3"|"1"|"2"|"4", default_branch_protection_defaults?: record, enabled_git_access_protocol?: "ssh"|"http"|"all", membership_lock?: bool, ldap_cn?: string, ldap_access?: int, shared_runners_minutes_limit?: int, extra_shared_runners_minutes_limit?: int, wiki_access_level?: "disabled"|"private"|"enabled", duo_availability?: "default_on"|"default_off"|"never_on", duo_remote_flows_availability?: bool, duo_foundational_flows_availability?: bool, duo_custom_agents_availability?: bool, duo_custom_flows_availability?: bool, duo_external_agents_availability?: bool, tool_approval_for_session_availability?: "default_on"|"default_off"|"never_on", amazon_q_auto_review_enabled?: bool, experiment_features_enabled?: bool, model_prompt_cache_enabled?: bool, foundational_agents_statuses?: list, ai_settings_attributes?: record, prevent_sharing_groups_outside_hierarchy?: bool, step_up_auth_required_oauth_provider?: string, lock_math_rendering_limits_enabled?: bool, math_rendering_limits_enabled?: bool, max_artifacts_size?: int, file_template_project_id?: int, prevent_forking_outside_group?: bool, unique_project_download_limit?: int, unique_project_download_limit_interval_in_seconds?: int, unique_project_download_limit_allowlist?: list, unique_project_download_limit_alertlist?: list, auto_ban_user_on_excessive_projects_download?: bool, ip_restriction_ranges?: string, allowed_email_domains_list?: string, service_access_tokens_expiration_enforced?: bool, duo_core_features_enabled?: bool, duo_features_enabled?: bool, lock_duo_features_enabled?: bool, auto_duo_code_review_enabled?: bool, web_based_commit_signing_enabled?: bool, only_allow_merge_if_pipeline_succeeds?: bool, allow_merge_on_skipped_pipeline?: bool, only_allow_merge_if_all_discussions_are_resolved?: bool, enabled_foundational_flows?: list, duo_template_project_id?: int, allow_personal_snippets?: bool, duo_namespace_access_rules?: list, built_in_project_templates_enabled?: bool, lock_built_in_project_templates_enabled?: bool}
export def "groups put" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --body: record # shape: {name?: string, path?: string, shared_runners_setting?: "disabled_and_unoverridable"|"disabled_and_overridable"|"enabled", description?: string, visibility?: "private"|"internal"|"public", avatar?: path, share_with_group_lock?: bool, require_two_factor_authentication?: bool, two_factor_grace_period?: int, project_creation_level?: "noone"|"owner"|"maintainer"|"developer"|"administrator", auto_devops_enabled?: bool, subgroup_creation_level?: "owner"|"maintainer", emails_disabled?: bool, emails_enabled?: bool, show_diff_preview_in_email?: bool, mentions_disabled?: bool, lfs_enabled?: bool, request_access_enabled?: bool, default_branch?: string, default_branch_protection?: "0"|"3"|"1"|"2"|"4", default_branch_protection_defaults?: record, enabled_git_access_protocol?: "ssh"|"http"|"all", membership_lock?: bool, ldap_cn?: string, ldap_access?: int, shared_runners_minutes_limit?: int, extra_shared_runners_minutes_limit?: int, wiki_access_level?: "disabled"|"private"|"enabled", duo_availability?: "default_on"|"default_off"|"never_on", duo_remote_flows_availability?: bool, duo_foundational_flows_availability?: bool, duo_custom_agents_availability?: bool, duo_custom_flows_availability?: bool, duo_external_agents_availability?: bool, tool_approval_for_session_availability?: "default_on"|"default_off"|"never_on", amazon_q_auto_review_enabled?: bool, experiment_features_enabled?: bool, model_prompt_cache_enabled?: bool, foundational_agents_statuses?: list, ai_settings_attributes?: record, prevent_sharing_groups_outside_hierarchy?: bool, step_up_auth_required_oauth_provider?: string, lock_math_rendering_limits_enabled?: bool, math_rendering_limits_enabled?: bool, max_artifacts_size?: int, file_template_project_id?: int, prevent_forking_outside_group?: bool, unique_project_download_limit?: int, unique_project_download_limit_interval_in_seconds?: int, unique_project_download_limit_allowlist?: list, unique_project_download_limit_alertlist?: list, auto_ban_user_on_excessive_projects_download?: bool, ip_restriction_ranges?: string, allowed_email_domains_list?: string, service_access_tokens_expiration_enforced?: bool, duo_core_features_enabled?: bool, duo_features_enabled?: bool, lock_duo_features_enabled?: bool, auto_duo_code_review_enabled?: bool, web_based_commit_signing_enabled?: bool, only_allow_merge_if_pipeline_succeeds?: bool, allow_merge_on_skipped_pipeline?: bool, only_allow_merge_if_all_discussions_are_resolved?: bool, enabled_foundational_flows?: list, duo_template_project_id?: int, allow_personal_snippets?: bool, duo_namespace_access_rules?: list, built_in_project_templates_enabled?: bool, lock_built_in_project_templates_enabled?: bool}
]: any -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)")
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
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
  --dry-run(-n) # Return the request that would be sent without executing it
  --with-custom-attributes: oneof<nothing, bool> # Include custom attributes in the response (default: false)
  --with-projects: oneof<nothing, bool> # Omit project details (default: true)
]: nothing -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool, shared_with_groups: list<record>, runners_token: string, enabled_git_access_protocol: string, prevent_sharing_groups_outside_hierarchy: bool, step_up_auth_required_oauth_provider: string, projects: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list<string>, topics: list<string>, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record<key: string, name: string, nickname: string, html_url: string, source_url: string>, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record<id: int, name: string, path: string, kind: string, full_path: string, parent_id: int, avatar_url: string, web_url: string>, custom_attributes: record<key: string, value: string>, repository_storage: string, forked_from_project: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list, topics: list, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record, custom_attributes: record, repository_storage: string>, container_registry_image_prefix: string, _links: record<self: string, issues: string, merge_requests: string, repo_branches: string, labels: string, events: string, members: string, cluster_agents: string>, marked_for_deletion_at: string, marked_for_deletion_on: string, packages_enabled: bool, empty_repo: bool, archived: bool, owner: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, resolve_outdated_diff_discussions: bool, container_expiration_policy: record<cadence: string, enabled: string, keep_n: string, older_than: string, name_regex: string, name_regex_keep: string, next_run_at: string>, repository_object_format: string, issues_enabled: bool, merge_requests_enabled: bool, wiki_enabled: bool, jobs_enabled: bool, snippets_enabled: bool, container_registry_enabled: bool, service_desk_enabled: bool, service_desk_address: string, can_create_merge_request_in: bool, issues_access_level: string, repository_access_level: string, merge_requests_access_level: string, forking_access_level: string, wiki_access_level: string, builds_access_level: string, snippets_access_level: string, pages_access_level: string, analytics_access_level: string, container_registry_access_level: string, security_and_compliance_access_level: string, releases_access_level: string, environments_access_level: string, feature_flags_access_level: string, infrastructure_access_level: string, monitor_access_level: string, model_experiments_access_level: string, model_registry_access_level: string, package_registry_access_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, shared_runners_enabled: bool, lfs_enabled: bool, creator_id: int, mr_default_target_self: bool, import_url: string, import_type: string, import_status: string, import_error: string, open_issues_count: int, description_html: string, updated_at: string, ci_default_git_depth: int, ci_delete_pipelines_in_seconds: int, ci_forward_deployment_enabled: bool, ci_forward_deployment_rollback_allowed: bool, ci_job_token_scope_enabled: bool, ci_separated_caches: bool, ci_allow_fork_pipelines_to_run_in_parent_project: bool, ci_id_token_sub_claim_components: list<string>, build_git_strategy: string, keep_latest_artifact: bool, restrict_user_defined_variables: bool, ci_pipeline_variables_minimum_override_role: string, runner_token_expiration_interval: int, group_runners_enabled: bool, resource_group_default_process_mode: string, auto_cancel_pending_pipelines: string, build_timeout: int, auto_devops_enabled: bool, auto_devops_deploy_strategy: string, ci_push_repository_for_job_token_allowed: bool, protect_merge_request_pipelines: bool, ci_display_pipeline_variables: bool, runners_token: string, ci_config_path: string, public_jobs: bool, shared_with_groups: list<record>, only_allow_merge_if_pipeline_succeeds: bool, allow_merge_on_skipped_pipeline: bool, request_access_enabled: bool, only_allow_merge_if_all_discussions_are_resolved: bool, remove_source_branch_after_merge: bool, printing_merge_request_link_enabled: bool, merge_method: string, squash_option: string, enforce_auth_checks_on_uploads: bool, suggestion_commit_message: string, merge_commit_template: string, squash_commit_template: string, mr_default_title_template: string, issue_branch_template: string, statistics: record<commit_count: int, storage_size: int, repository_size: int, wiki_size: int, lfs_objects_size: int, job_artifacts_size: int, pipeline_artifacts_size: int, packages_size: int, snippets_size: int, uploads_size: int, container_registry_size: int>, warn_about_potentially_unwanted_characters: bool, autoclose_referenced_issues: bool, max_artifacts_size: int, approvals_before_merge: string, mirror: string, mirror_user_id: string, mirror_trigger_builds: string, only_mirror_protected_branches: string, mirror_overwrites_diverged_branches: string, external_authorization_classification_label: string, requirements_enabled: string, requirements_access_level: string, security_and_compliance_enabled: string, secret_push_protection_enabled: bool, pre_receive_secret_detection_enabled: bool, compliance_frameworks: string, issues_template: string, merge_requests_template: string, ci_restrict_pipeline_cancellation_role: string, merge_pipelines_enabled: string, merge_trains_enabled: string, merge_trains_skip_train_allowed: string, max_pipelines_per_merge_train: string, only_allow_merge_if_all_status_checks_passed: string, allow_pipeline_trigger_approve_deployment: bool, prevent_merge_without_jira_issue: string, auto_duo_code_review_enabled: string, duo_remote_flows_enabled: string, duo_foundational_flows_enabled: string, duo_sast_fp_detection_enabled: string, duo_secret_detection_fp_enabled: string, duo_sast_vr_workflow_enabled: string, web_based_commit_signing_enabled: string, spp_repository_pipeline_access: bool, security_policy_pipeline_must_succeed: bool, merge_request_title_regex: string, merge_request_title_regex_description: string>, shared_projects: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list<string>, topics: list<string>, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record<key: string, name: string, nickname: string, html_url: string, source_url: string>, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record<id: int, name: string, path: string, kind: string, full_path: string, parent_id: int, avatar_url: string, web_url: string>, custom_attributes: record<key: string, value: string>, repository_storage: string, forked_from_project: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list, topics: list, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record, custom_attributes: record, repository_storage: string>, container_registry_image_prefix: string, _links: record<self: string, issues: string, merge_requests: string, repo_branches: string, labels: string, events: string, members: string, cluster_agents: string>, marked_for_deletion_at: string, marked_for_deletion_on: string, packages_enabled: bool, empty_repo: bool, archived: bool, owner: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, resolve_outdated_diff_discussions: bool, container_expiration_policy: record<cadence: string, enabled: string, keep_n: string, older_than: string, name_regex: string, name_regex_keep: string, next_run_at: string>, repository_object_format: string, issues_enabled: bool, merge_requests_enabled: bool, wiki_enabled: bool, jobs_enabled: bool, snippets_enabled: bool, container_registry_enabled: bool, service_desk_enabled: bool, service_desk_address: string, can_create_merge_request_in: bool, issues_access_level: string, repository_access_level: string, merge_requests_access_level: string, forking_access_level: string, wiki_access_level: string, builds_access_level: string, snippets_access_level: string, pages_access_level: string, analytics_access_level: string, container_registry_access_level: string, security_and_compliance_access_level: string, releases_access_level: string, environments_access_level: string, feature_flags_access_level: string, infrastructure_access_level: string, monitor_access_level: string, model_experiments_access_level: string, model_registry_access_level: string, package_registry_access_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, shared_runners_enabled: bool, lfs_enabled: bool, creator_id: int, mr_default_target_self: bool, import_url: string, import_type: string, import_status: string, import_error: string, open_issues_count: int, description_html: string, updated_at: string, ci_default_git_depth: int, ci_delete_pipelines_in_seconds: int, ci_forward_deployment_enabled: bool, ci_forward_deployment_rollback_allowed: bool, ci_job_token_scope_enabled: bool, ci_separated_caches: bool, ci_allow_fork_pipelines_to_run_in_parent_project: bool, ci_id_token_sub_claim_components: list<string>, build_git_strategy: string, keep_latest_artifact: bool, restrict_user_defined_variables: bool, ci_pipeline_variables_minimum_override_role: string, runner_token_expiration_interval: int, group_runners_enabled: bool, resource_group_default_process_mode: string, auto_cancel_pending_pipelines: string, build_timeout: int, auto_devops_enabled: bool, auto_devops_deploy_strategy: string, ci_push_repository_for_job_token_allowed: bool, protect_merge_request_pipelines: bool, ci_display_pipeline_variables: bool, runners_token: string, ci_config_path: string, public_jobs: bool, shared_with_groups: list<record>, only_allow_merge_if_pipeline_succeeds: bool, allow_merge_on_skipped_pipeline: bool, request_access_enabled: bool, only_allow_merge_if_all_discussions_are_resolved: bool, remove_source_branch_after_merge: bool, printing_merge_request_link_enabled: bool, merge_method: string, squash_option: string, enforce_auth_checks_on_uploads: bool, suggestion_commit_message: string, merge_commit_template: string, squash_commit_template: string, mr_default_title_template: string, issue_branch_template: string, statistics: record<commit_count: int, storage_size: int, repository_size: int, wiki_size: int, lfs_objects_size: int, job_artifacts_size: int, pipeline_artifacts_size: int, packages_size: int, snippets_size: int, uploads_size: int, container_registry_size: int>, warn_about_potentially_unwanted_characters: bool, autoclose_referenced_issues: bool, max_artifacts_size: int, approvals_before_merge: string, mirror: string, mirror_user_id: string, mirror_trigger_builds: string, only_mirror_protected_branches: string, mirror_overwrites_diverged_branches: string, external_authorization_classification_label: string, requirements_enabled: string, requirements_access_level: string, security_and_compliance_enabled: string, secret_push_protection_enabled: bool, pre_receive_secret_detection_enabled: bool, compliance_frameworks: string, issues_template: string, merge_requests_template: string, ci_restrict_pipeline_cancellation_role: string, merge_pipelines_enabled: string, merge_trains_enabled: string, merge_trains_skip_train_allowed: string, max_pipelines_per_merge_train: string, only_allow_merge_if_all_status_checks_passed: string, allow_pipeline_trigger_approve_deployment: bool, prevent_merge_without_jira_issue: string, auto_duo_code_review_enabled: string, duo_remote_flows_enabled: string, duo_foundational_flows_enabled: string, duo_sast_fp_detection_enabled: string, duo_secret_detection_fp_enabled: string, duo_sast_vr_workflow_enabled: string, web_based_commit_signing_enabled: string, spp_repository_pipeline_access: bool, security_policy_pipeline_must_succeed: bool, merge_request_title_regex: string, merge_request_title_regex_description: string>, shared_runners_minutes_limit: string, extra_shared_runners_minutes_limit: string, prevent_forking_outside_group: string, service_access_tokens_expiration_enforced: string, experiment_features_enabled: string, membership_lock: string, ip_restriction_ranges: string, allowed_email_domains_list: string, only_allow_merge_if_pipeline_succeeds: string, allow_merge_on_skipped_pipeline: string, only_allow_merge_if_all_discussions_are_resolved: string, unique_project_download_limit: string, unique_project_download_limit_interval_in_seconds: string, unique_project_download_limit_allowlist: string, unique_project_download_limit_alertlist: string, auto_ban_user_on_excessive_projects_download: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "with_custom_attributes" $with_custom_attributes "scalar") (serialize-qp "with_projects" $with_projects "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
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
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Archive a group
#
# POST /api/v4/groups/{id}/archive
# operationId: postApiV4GroupsIdArchive
export def "groups-archive post" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/archive")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}
