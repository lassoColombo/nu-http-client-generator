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
  let is_list = ($value | describe | str starts-with "list")
  if ($value | describe | str starts-with "record") { return ($value | transpose k v | each { $"($name)[($in.k)]=($in.v)" }) }
  if not $is_list { return [$"($name)=($value)"] }
  match $style {
    "multi" => { $value | each {|v| $"($name)=($v)" } }
    "csv" => { let joined = ($value | each { $in | into string } | str join ","); [$"($name)=($joined)"] }
    "ssv" => { let joined = ($value | each { $in | into string } | str join "%20"); [$"($name)=($joined)"] }
    "tsv" => { let joined = ($value | each { $in | into string } | str join "\t"); [$"($name)=($joined)"] }
    "pipes" => { let joined = ($value | each { $in | into string } | str join "|"); [$"($name)=($joined)"] }
    "deepObject" => { $value | each {|v| $"($name)[]=($v)" } }
    _ => { $value | each {|v| $"($name)=($v)" } }
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
  let auth = {headers: ({"X-Test": "value"} | merge $auth.headers), query: $auth.query}
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

def bool-completer [] { ["'true'" "'false'"] }
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
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "accept" "help"]
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
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: table<key: string, value: string>, web_url: string, requested_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/access_requests" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Requests access for the authenticated user to a group.
#
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
]: nothing -> record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: table<key: string, value: string>, web_url: string, requested_at: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/access_requests")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Approves an access request for the given user.
#
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
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Denies an access request for the given user.
#
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
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/access_requests/($user_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# List an awardable's emoji reactions for groups
#
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
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> table<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/award_emoji" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Add a new emoji reaction
#
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
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Get a single emoji reaction
#
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
]: nothing -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/award_emoji/($award_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Delete an emoji reaction
#
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
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/award_emoji/($award_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# List an awardable's emoji reactions for groups
#
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
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
]: nothing -> table<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/notes/($note_id)/award_emoji" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Add a new emoji reaction
#
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
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Get a single emoji reaction
#
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
]: nothing -> record<id: int, name: string, user: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list<record>, web_url: string>, created_at: string, updated_at: string, awardable_id: int, awardable_type: string, url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/notes/($note_id)/award_emoji/($award_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Delete an emoji reaction
#
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
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/epics/($epic_iid)/notes/($note_id)/award_emoji/($award_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Gets a list of group badges viewable by the authenticated user.
#
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
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Adds a badge to a group.
#
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
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Preview a badge from a group.
#
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
  --link-url: string # URL of the badge link
  --image-url: string # URL of the badge image
]: nothing -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "link_url" $link_url "scalar") (serialize-qp "image_url" $image_url "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges/render" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Gets a badge of a group.
#
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
]: nothing -> record<name: string, link_url: string, image_url: string, rendered_link_url: string, rendered_image_url: string, id: int, kind: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges/($badge_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Updates a badge of a group.
#
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
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Removes a badge from the group.
#
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
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/badges/($badge_id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get all custom attributes on a group
#
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
]: nothing -> record<key: string, value: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/custom_attributes")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get a custom attribute on a group
#
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
]: nothing -> record<key: string, value: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/custom_attributes/($key)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Set a custom attribute on a group
#
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
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Delete a custom attribute on a group
#
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
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/custom_attributes/($key)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get a groups list
#
# operationId: getApiV4Groups
export def "groups list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --statistics: string@bool-completer # Include project statistics (default: false)
  --archived: string@bool-completer # Limit by archived status
  --skip-groups: list # Array of group ids to exclude from list
  --all-available: string@bool-completer # When `true`, returns all accessible groups. When `false`, returns only groups where the user is a member.
  --visibility: string@visibility-completer # Limit by visibility
  --search: string # Search for a specific group
  --owned: string@bool-completer # Limit by owned by authenticated user (default: false)
  --order-by: string@order-by-completer # Order by name, path, id or similarity if searching (default: name)
  --qp-sort: string@sort-completer # Sort by asc (ascending) or desc (descending) (default: asc)
  --min-access-level: int@min-access-level-completer # Minimum access level of authenticated user (format: int32)
  --top-level-only: string@bool-completer # Only include top-level groups
  --marked-for-deletion-on: string # Return groups that are marked for deletion on this date (format: date)
  --active: string@bool-completer # Limit by groups that are not archived and not marked for deletion
  --repository-storage: string # Filter by repository storage used by the group
  --page: int # Current page number (format: int32, default: 1, e.g. 1)
  --per-page: int # Number of items per page (format: int32, default: 20, e.g. 20)
  --with-custom-attributes: string@bool-completer # Include custom attributes in the response (default: false)
]: nothing -> table<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "statistics" $statistics "scalar") (serialize-qp "archived" $archived "scalar") (serialize-qp "skip_groups" $skip_groups "csv") (serialize-qp "all_available" $all_available "scalar") (serialize-qp "visibility" $visibility "scalar") (serialize-qp "search" $search "scalar") (serialize-qp "owned" $owned "scalar") (serialize-qp "order_by" $order_by "scalar") (serialize-qp "sort" $qp_sort "scalar") (serialize-qp "min_access_level" $min_access_level "scalar") (serialize-qp "top_level_only" $top_level_only "scalar") (serialize-qp "marked_for_deletion_on" $marked_for_deletion_on "scalar") (serialize-qp "active" $active "scalar") (serialize-qp "repository_storage" $repository_storage "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "with_custom_attributes" $with_custom_attributes "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v4/groups" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Create a group. Available only for users who can create groups.
#
# operationId: postApiV4Groups
# --default_branch_protection_defaults shape: {allowed_to_push?: list, allow_force_push?: bool, allowed_to_merge?: list, code_owner_approval_required?: bool, developer_can_initial_push?: bool}
# --foundational_agents_statuses item shape: {reference: string, enabled: bool}
# --ai_settings_attributes shape: {duo_agent_platform_enabled?: bool, duo_workflow_mcp_enabled?: bool, ai_usage_data_collection_enabled?: bool, ai_catalog_restricted_to_group_hierarchy?: bool, foundational_agents_default_enabled?: bool, prompt_injection_protection_level?: "no_checks"|"log_only"|"interrupt", include_recommended_allowed?: bool, allow_all_unix_sockets?: bool, allow_project_extension?: bool, minimum_access_level_execute?: "10"|"15"|"20"|"30"|"40"|"50", minimum_access_level_execute_async?: "30"|"40"|"50", minimum_access_level_manage?: "30"|"40"|"50", minimum_access_level_enable_on_projects?: "30"|"40"|"50"}
export def "groups post" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  name: string # The name of the group
  path: string # The path of the group
  --parent-id: int # The parent group id for creating nested group (format: int32)
  --organization-id: int # The organization id for the group (format: int32, default: {})
  --description: string # The description of the group
  --visibility: string@visibility-completer # The visibility of the group
  --avatar: path # Avatar image for the group
  --share-with-group-lock: string@bool-completer # Prevent sharing a project with another group within this group
  --require-two-factor-authentication: string@bool-completer # Require all users in this group to setup Two-factor authentication
  --two-factor-grace-period: int # Time before Two-factor authentication is enforced (format: int32)
  --project-creation-level: string@project-creation-level-completer # Determine if developers can create projects in the group
  --auto-devops-enabled: string@bool-completer # Default to Auto DevOps pipeline for all projects within this group
  --subgroup-creation-level: string@subgroup-creation-level-completer # Allowed to create subgroups
  --emails-disabled: string@bool-completer # _(Deprecated)_ Disable email notifications. Use: emails_enabled
  --emails-enabled: string@bool-completer # Enable email notifications
  --show-diff-preview-in-email: string@bool-completer # Include the code diff preview in merge request notification emails
  --mentions-disabled: string@bool-completer # Disable a group from getting mentioned
  --lfs-enabled: string@bool-completer # Enable/disable LFS for the projects in this group
  --request-access-enabled: string@bool-completer # Allow users to request member access
  --default-branch: string # The default branch of group's projects (e.g. main)
  --default-branch-protection: int@default-branch-protection-completer # Determine if developers can push to default branch (format: int32)
  --default-branch-protection-defaults: record # Determine if developers can push to default branch — shape: {allowed_to_push?: list, allow_force_push?: bool, allowed_to_merge?: list, code_owner_approval_required?: bool, developer_can_initial_push?: bool}
  --enabled-git-access-protocol: string@enabled-git-access-protocol-completer # Allow only the selected protocols to be used for Git access.
  --membership-lock: string@bool-completer # Prevent adding new members to projects within this group
  --ldap-cn: string # LDAP Common Name
  --ldap-access: int # A valid access level (format: int32)
  --shared-runners-minutes-limit: int # (admin-only) compute minutes quota for this group (format: int32)
  --extra-shared-runners-minutes-limit: int # (admin-only) Extra compute minutes quota for this group (format: int32)
  --wiki-access-level: string@wiki-access-level-completer # Wiki access level. One of `disabled`, `private` or `enabled`
  --duo-availability: string@duo-availability-completer # Duo availability. One of `default_on`, `default_off` or `never_on`
  --duo-remote-flows-availability: string@bool-completer # Enable GitLab Duo remote flows for this group
  --duo-foundational-flows-availability: string@bool-completer # Enable GitLab foundational Duo flows for this group
  --duo-custom-agents-availability: string@bool-completer # Enable GitLab Duo custom agents for this group
  --duo-custom-flows-availability: string@bool-completer # Enable GitLab Duo custom flows for this group
  --duo-external-agents-availability: string@bool-completer # Enable GitLab Duo external agents for this group
  --tool-approval-for-session-availability: string@tool-approval-for-session-availability-completer # Tool approval for session availability. One of `default_on`, `default_off` or `never_on`
  --amazon-q-auto-review-enabled: string@bool-completer # Enable Amazon Q auto review for merge request
  --experiment-features-enabled: string@bool-completer # Enable experiment features for this group
  --model-prompt-cache-enabled: string@bool-completer # Enable model prompt cache for this group
  --foundational-agents-statuses: list # Whether each foundational agent has been enabled or disabled. — item shape: {reference: string, enabled: bool}
  --ai-settings-attributes: record # AI-related settings — shape: {duo_agent_platform_enabled?: bool, duo_workflow_mcp_enabled?: bool, ai_usage_data_collection_enabled?: bool, ai_catalog_restricted_to_group_hierarchy?: bool, foundational_agents_default_enabled?: bool, prompt_injection_protection_level?: "no_checks"|"log_only"|"interrupt", include_recommended_allowed?: bool, allow_all_unix_sockets?: bool, allow_project_extension?: bool, minimum_access_level_execute?: "10"|"15"|"20"|"30"|"40"|"50", minimum_access_level_execute_async?: "30"|"40"|"50", minimum_access_level_manage?: "30"|"40"|"50", minimum_access_level_enable_on_projects?: "30"|"40"|"50"}
]: any -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/v4/groups")
  let body = {name: $name, path: $path, parent_id: $parent_id, organization_id: $organization_id, description: $description, visibility: $visibility, avatar: $avatar, share_with_group_lock: $share_with_group_lock, require_two_factor_authentication: $require_two_factor_authentication, two_factor_grace_period: $two_factor_grace_period, project_creation_level: $project_creation_level, auto_devops_enabled: $auto_devops_enabled, subgroup_creation_level: $subgroup_creation_level, emails_disabled: $emails_disabled, emails_enabled: $emails_enabled, show_diff_preview_in_email: $show_diff_preview_in_email, mentions_disabled: $mentions_disabled, lfs_enabled: $lfs_enabled, request_access_enabled: $request_access_enabled, default_branch: $default_branch, default_branch_protection: $default_branch_protection, default_branch_protection_defaults: $default_branch_protection_defaults, enabled_git_access_protocol: $enabled_git_access_protocol, membership_lock: $membership_lock, ldap_cn: $ldap_cn, ldap_access: $ldap_access, shared_runners_minutes_limit: $shared_runners_minutes_limit, extra_shared_runners_minutes_limit: $extra_shared_runners_minutes_limit, wiki_access_level: $wiki_access_level, duo_availability: $duo_availability, duo_remote_flows_availability: $duo_remote_flows_availability, duo_foundational_flows_availability: $duo_foundational_flows_availability, duo_custom_agents_availability: $duo_custom_agents_availability, duo_custom_flows_availability: $duo_custom_flows_availability, duo_external_agents_availability: $duo_external_agents_availability, tool_approval_for_session_availability: $tool_approval_for_session_availability, amazon_q_auto_review_enabled: $amazon_q_auto_review_enabled, experiment_features_enabled: $experiment_features_enabled, model_prompt_cache_enabled: $model_prompt_cache_enabled, foundational_agents_statuses: $foundational_agents_statuses, ai_settings_attributes: $ai_settings_attributes} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Update a group. Available only for users who can administrate groups.
#
# operationId: putApiV4GroupsId
# --default_branch_protection_defaults shape: {allowed_to_push?: list, allow_force_push?: bool, allowed_to_merge?: list, code_owner_approval_required?: bool, developer_can_initial_push?: bool}
# --foundational_agents_statuses item shape: {reference: string, enabled: bool}
# --ai_settings_attributes shape: {duo_agent_platform_enabled?: bool, duo_workflow_mcp_enabled?: bool, ai_usage_data_collection_enabled?: bool, ai_catalog_restricted_to_group_hierarchy?: bool, foundational_agents_default_enabled?: bool, prompt_injection_protection_level?: "no_checks"|"log_only"|"interrupt", include_recommended_allowed?: bool, allow_all_unix_sockets?: bool, allow_project_extension?: bool, minimum_access_level_execute?: "10"|"15"|"20"|"30"|"40"|"50", minimum_access_level_execute_async?: "30"|"40"|"50", minimum_access_level_manage?: "30"|"40"|"50", minimum_access_level_enable_on_projects?: "30"|"40"|"50"}
# --duo_namespace_access_rules item shape: {through_namespace?: record, features: list}
export def "groups put" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --name: string # The name of the group
  --path: string # The path of the group
  --shared-runners-setting: string@shared-runners-setting-completer # Enable/disable shared runners for the group and its subgroups and projects
  --description: string # The description of the group
  --visibility: string@visibility-completer # The visibility of the group
  --avatar: path # Avatar image for the group
  --share-with-group-lock: string@bool-completer # Prevent sharing a project with another group within this group
  --require-two-factor-authentication: string@bool-completer # Require all users in this group to setup Two-factor authentication
  --two-factor-grace-period: int # Time before Two-factor authentication is enforced (format: int32)
  --project-creation-level: string@project-creation-level-completer # Determine if developers can create projects in the group
  --auto-devops-enabled: string@bool-completer # Default to Auto DevOps pipeline for all projects within this group
  --subgroup-creation-level: string@subgroup-creation-level-completer # Allowed to create subgroups
  --emails-disabled: string@bool-completer # _(Deprecated)_ Disable email notifications. Use: emails_enabled
  --emails-enabled: string@bool-completer # Enable email notifications
  --show-diff-preview-in-email: string@bool-completer # Include the code diff preview in merge request notification emails
  --mentions-disabled: string@bool-completer # Disable a group from getting mentioned
  --lfs-enabled: string@bool-completer # Enable/disable LFS for the projects in this group
  --request-access-enabled: string@bool-completer # Allow users to request member access
  --default-branch: string # The default branch of group's projects (e.g. main)
  --default-branch-protection: int@default-branch-protection-completer # Determine if developers can push to default branch (format: int32)
  --default-branch-protection-defaults: record # Determine if developers can push to default branch — shape: {allowed_to_push?: list, allow_force_push?: bool, allowed_to_merge?: list, code_owner_approval_required?: bool, developer_can_initial_push?: bool}
  --enabled-git-access-protocol: string@enabled-git-access-protocol-completer # Allow only the selected protocols to be used for Git access.
  --membership-lock: string@bool-completer # Prevent adding new members to projects within this group
  --ldap-cn: string # LDAP Common Name
  --ldap-access: int # A valid access level (format: int32)
  --shared-runners-minutes-limit: int # (admin-only) compute minutes quota for this group (format: int32)
  --extra-shared-runners-minutes-limit: int # (admin-only) Extra compute minutes quota for this group (format: int32)
  --wiki-access-level: string@wiki-access-level-completer # Wiki access level. One of `disabled`, `private` or `enabled`
  --duo-availability: string@duo-availability-completer # Duo availability. One of `default_on`, `default_off` or `never_on`
  --duo-remote-flows-availability: string@bool-completer # Enable GitLab Duo remote flows for this group
  --duo-foundational-flows-availability: string@bool-completer # Enable GitLab foundational Duo flows for this group
  --duo-custom-agents-availability: string@bool-completer # Enable GitLab Duo custom agents for this group
  --duo-custom-flows-availability: string@bool-completer # Enable GitLab Duo custom flows for this group
  --duo-external-agents-availability: string@bool-completer # Enable GitLab Duo external agents for this group
  --tool-approval-for-session-availability: string@tool-approval-for-session-availability-completer # Tool approval for session availability. One of `default_on`, `default_off` or `never_on`
  --amazon-q-auto-review-enabled: string@bool-completer # Enable Amazon Q auto review for merge request
  --experiment-features-enabled: string@bool-completer # Enable experiment features for this group
  --model-prompt-cache-enabled: string@bool-completer # Enable model prompt cache for this group
  --foundational-agents-statuses: list # Whether each foundational agent has been enabled or disabled. — item shape: {reference: string, enabled: bool}
  --ai-settings-attributes: record # AI-related settings — shape: {duo_agent_platform_enabled?: bool, duo_workflow_mcp_enabled?: bool, ai_usage_data_collection_enabled?: bool, ai_catalog_restricted_to_group_hierarchy?: bool, foundational_agents_default_enabled?: bool, prompt_injection_protection_level?: "no_checks"|"log_only"|"interrupt", include_recommended_allowed?: bool, allow_all_unix_sockets?: bool, allow_project_extension?: bool, minimum_access_level_execute?: "10"|"15"|"20"|"30"|"40"|"50", minimum_access_level_execute_async?: "30"|"40"|"50", minimum_access_level_manage?: "30"|"40"|"50", minimum_access_level_enable_on_projects?: "30"|"40"|"50"}
  --prevent-sharing-groups-outside-hierarchy: string@bool-completer # Prevent sharing groups within this namespace with any groups outside the namespace. Only available on top-level groups.
  --step-up-auth-required-oauth-provider: string # OAuth provider required for step-up authentication. Pass empty string to disable.
  --lock-math-rendering-limits-enabled: string@bool-completer # Indicates if math rendering limits are locked for all descendent groups.
  --math-rendering-limits-enabled: string@bool-completer # Indicates if math rendering limits are used for this group.
  --max-artifacts-size: int # Set the maximum file size for each job's artifacts (format: int32)
  --file-template-project-id: int # The ID of a project to use for custom templates in this group (format: int32)
  --prevent-forking-outside-group: string@bool-completer # Prevent forking projects inside this group to external namespaces
  --unique-project-download-limit: int # Maximum number of unique projects a user can download in the specified time period before they are banned. (format: int32)
  --unique-project-download-limit-interval-in-seconds: int # Time period during which a user can download a maximum amount of projects before they are banned. (format: int32)
  --unique-project-download-limit-allowlist: list # List of usernames excluded from the unique project download limit
  --unique-project-download-limit-alertlist: list # List of user ids who will be emailed when Git abuse rate limit is exceeded
  --auto-ban-user-on-excessive-projects-download: string@bool-completer # Ban users from the group when they exceed maximum number of unique projects download in the specified time period
  --ip-restriction-ranges: string # List of IP addresses which need to be restricted for group
  --allowed-email-domains-list: string # List of allowed email domains for group
  --service-access-tokens-expiration-enforced: string@bool-completer # To enforce token expiration for Service accounts users for group
  --duo-core-features-enabled: string@bool-completer # [Experimental] Indicates whether GitLab Duo Core features are enabled for the group
  --duo-features-enabled: string@bool-completer # Indicates whether GitLab Duo features are enabled for the group
  --lock-duo-features-enabled: string@bool-completer # Indicates if the GitLab Duo features enabled setting is enforced for all subgroups
  --auto-duo-code-review-enabled: string@bool-completer # Enable automatic reviews by GitLab Duo on merge requests
  --web-based-commit-signing-enabled: string@bool-completer # Enable web based commit signing for this group
  --only-allow-merge-if-pipeline-succeeds: string@bool-completer # Only allow to merge if builds succeed
  --allow-merge-on-skipped-pipeline: string@bool-completer # Allow to merge if pipeline is skipped
  --only-allow-merge-if-all-discussions-are-resolved: string@bool-completer # Only allow to merge if all threads are resolved
  --enabled-foundational-flows: list # References of enabled foundational flows
  --duo-template-project-id: int # The ID of a project to use as the Duo Code Review custom instructions template for this group (format: int32)
  --allow-personal-snippets: string@bool-completer # Allow creation of personal snippets for enterprise users of this group
  --duo-namespace-access-rules: list # AI entity access rules for controlling Duo feature access — item shape: {through_namespace?: record, features: list}
  --built-in-project-templates-enabled: string@bool-completer # Enable built-in project templates for project creation
  --lock-built-in-project-templates-enabled: string@bool-completer # Enforce the built-in project templates setting for all subgroups
]: any -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)")
  let body = {name: $name, path: $path, shared_runners_setting: $shared_runners_setting, description: $description, visibility: $visibility, avatar: $avatar, share_with_group_lock: $share_with_group_lock, require_two_factor_authentication: $require_two_factor_authentication, two_factor_grace_period: $two_factor_grace_period, project_creation_level: $project_creation_level, auto_devops_enabled: $auto_devops_enabled, subgroup_creation_level: $subgroup_creation_level, emails_disabled: $emails_disabled, emails_enabled: $emails_enabled, show_diff_preview_in_email: $show_diff_preview_in_email, mentions_disabled: $mentions_disabled, lfs_enabled: $lfs_enabled, request_access_enabled: $request_access_enabled, default_branch: $default_branch, default_branch_protection: $default_branch_protection, default_branch_protection_defaults: $default_branch_protection_defaults, enabled_git_access_protocol: $enabled_git_access_protocol, membership_lock: $membership_lock, ldap_cn: $ldap_cn, ldap_access: $ldap_access, shared_runners_minutes_limit: $shared_runners_minutes_limit, extra_shared_runners_minutes_limit: $extra_shared_runners_minutes_limit, wiki_access_level: $wiki_access_level, duo_availability: $duo_availability, duo_remote_flows_availability: $duo_remote_flows_availability, duo_foundational_flows_availability: $duo_foundational_flows_availability, duo_custom_agents_availability: $duo_custom_agents_availability, duo_custom_flows_availability: $duo_custom_flows_availability, duo_external_agents_availability: $duo_external_agents_availability, tool_approval_for_session_availability: $tool_approval_for_session_availability, amazon_q_auto_review_enabled: $amazon_q_auto_review_enabled, experiment_features_enabled: $experiment_features_enabled, model_prompt_cache_enabled: $model_prompt_cache_enabled, foundational_agents_statuses: $foundational_agents_statuses, ai_settings_attributes: $ai_settings_attributes, prevent_sharing_groups_outside_hierarchy: $prevent_sharing_groups_outside_hierarchy, step_up_auth_required_oauth_provider: $step_up_auth_required_oauth_provider, lock_math_rendering_limits_enabled: $lock_math_rendering_limits_enabled, math_rendering_limits_enabled: $math_rendering_limits_enabled, max_artifacts_size: $max_artifacts_size, file_template_project_id: $file_template_project_id, prevent_forking_outside_group: $prevent_forking_outside_group, unique_project_download_limit: $unique_project_download_limit, unique_project_download_limit_interval_in_seconds: $unique_project_download_limit_interval_in_seconds, unique_project_download_limit_allowlist: $unique_project_download_limit_allowlist, unique_project_download_limit_alertlist: $unique_project_download_limit_alertlist, auto_ban_user_on_excessive_projects_download: $auto_ban_user_on_excessive_projects_download, ip_restriction_ranges: $ip_restriction_ranges, allowed_email_domains_list: $allowed_email_domains_list, service_access_tokens_expiration_enforced: $service_access_tokens_expiration_enforced, duo_core_features_enabled: $duo_core_features_enabled, duo_features_enabled: $duo_features_enabled, lock_duo_features_enabled: $lock_duo_features_enabled, auto_duo_code_review_enabled: $auto_duo_code_review_enabled, web_based_commit_signing_enabled: $web_based_commit_signing_enabled, only_allow_merge_if_pipeline_succeeds: $only_allow_merge_if_pipeline_succeeds, allow_merge_on_skipped_pipeline: $allow_merge_on_skipped_pipeline, only_allow_merge_if_all_discussions_are_resolved: $only_allow_merge_if_all_discussions_are_resolved, enabled_foundational_flows: $enabled_foundational_flows, duo_template_project_id: $duo_template_project_id, allow_personal_snippets: $allow_personal_snippets, duo_namespace_access_rules: $duo_namespace_access_rules, built_in_project_templates_enabled: $built_in_project_templates_enabled, lock_built_in_project_templates_enabled: $lock_built_in_project_templates_enabled} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Get a single group, with containing projects.
#
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
  --with-custom-attributes: string@bool-completer # Include custom attributes in the response (default: false)
  --with-projects: string@bool-completer # Omit project details (default: true)
]: nothing -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool, shared_with_groups: list<record>, runners_token: string, enabled_git_access_protocol: string, prevent_sharing_groups_outside_hierarchy: bool, step_up_auth_required_oauth_provider: string, projects: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list<string>, topics: list<string>, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record<key: string, name: string, nickname: string, html_url: string, source_url: string>, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record<id: int, name: string, path: string, kind: string, full_path: string, parent_id: int, avatar_url: string, web_url: string>, custom_attributes: record<key: string, value: string>, repository_storage: string, forked_from_project: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list, topics: list, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record, custom_attributes: record, repository_storage: string>, container_registry_image_prefix: string, _links: record<self: string, issues: string, merge_requests: string, repo_branches: string, labels: string, events: string, members: string, cluster_agents: string>, marked_for_deletion_at: string, marked_for_deletion_on: string, packages_enabled: bool, empty_repo: bool, archived: bool, owner: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, resolve_outdated_diff_discussions: bool, container_expiration_policy: record<cadence: string, enabled: string, keep_n: string, older_than: string, name_regex: string, name_regex_keep: string, next_run_at: string>, repository_object_format: string, issues_enabled: bool, merge_requests_enabled: bool, wiki_enabled: bool, jobs_enabled: bool, snippets_enabled: bool, container_registry_enabled: bool, service_desk_enabled: bool, service_desk_address: string, can_create_merge_request_in: bool, issues_access_level: string, repository_access_level: string, merge_requests_access_level: string, forking_access_level: string, wiki_access_level: string, builds_access_level: string, snippets_access_level: string, pages_access_level: string, analytics_access_level: string, container_registry_access_level: string, security_and_compliance_access_level: string, releases_access_level: string, environments_access_level: string, feature_flags_access_level: string, infrastructure_access_level: string, monitor_access_level: string, model_experiments_access_level: string, model_registry_access_level: string, package_registry_access_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, shared_runners_enabled: bool, lfs_enabled: bool, creator_id: int, mr_default_target_self: bool, import_url: string, import_type: string, import_status: string, import_error: string, open_issues_count: int, description_html: string, updated_at: string, ci_default_git_depth: int, ci_delete_pipelines_in_seconds: int, ci_forward_deployment_enabled: bool, ci_forward_deployment_rollback_allowed: bool, ci_job_token_scope_enabled: bool, ci_separated_caches: bool, ci_allow_fork_pipelines_to_run_in_parent_project: bool, ci_id_token_sub_claim_components: list<string>, build_git_strategy: string, keep_latest_artifact: bool, restrict_user_defined_variables: bool, ci_pipeline_variables_minimum_override_role: string, runner_token_expiration_interval: int, group_runners_enabled: bool, resource_group_default_process_mode: string, auto_cancel_pending_pipelines: string, build_timeout: int, auto_devops_enabled: bool, auto_devops_deploy_strategy: string, ci_push_repository_for_job_token_allowed: bool, protect_merge_request_pipelines: bool, ci_display_pipeline_variables: bool, runners_token: string, ci_config_path: string, public_jobs: bool, shared_with_groups: list<record>, only_allow_merge_if_pipeline_succeeds: bool, allow_merge_on_skipped_pipeline: bool, request_access_enabled: bool, only_allow_merge_if_all_discussions_are_resolved: bool, remove_source_branch_after_merge: bool, printing_merge_request_link_enabled: bool, merge_method: string, squash_option: string, enforce_auth_checks_on_uploads: bool, suggestion_commit_message: string, merge_commit_template: string, squash_commit_template: string, mr_default_title_template: string, issue_branch_template: string, statistics: record<commit_count: int, storage_size: int, repository_size: int, wiki_size: int, lfs_objects_size: int, job_artifacts_size: int, pipeline_artifacts_size: int, packages_size: int, snippets_size: int, uploads_size: int, container_registry_size: int>, warn_about_potentially_unwanted_characters: bool, autoclose_referenced_issues: bool, max_artifacts_size: int, approvals_before_merge: string, mirror: string, mirror_user_id: string, mirror_trigger_builds: string, only_mirror_protected_branches: string, mirror_overwrites_diverged_branches: string, external_authorization_classification_label: string, requirements_enabled: string, requirements_access_level: string, security_and_compliance_enabled: string, secret_push_protection_enabled: bool, pre_receive_secret_detection_enabled: bool, compliance_frameworks: string, issues_template: string, merge_requests_template: string, ci_restrict_pipeline_cancellation_role: string, merge_pipelines_enabled: string, merge_trains_enabled: string, merge_trains_skip_train_allowed: string, max_pipelines_per_merge_train: string, only_allow_merge_if_all_status_checks_passed: string, allow_pipeline_trigger_approve_deployment: bool, prevent_merge_without_jira_issue: string, auto_duo_code_review_enabled: string, duo_remote_flows_enabled: string, duo_foundational_flows_enabled: string, duo_sast_fp_detection_enabled: string, duo_secret_detection_fp_enabled: string, duo_sast_vr_workflow_enabled: string, web_based_commit_signing_enabled: string, spp_repository_pipeline_access: bool, security_policy_pipeline_must_succeed: bool, merge_request_title_regex: string, merge_request_title_regex_description: string>, shared_projects: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list<string>, topics: list<string>, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record<key: string, name: string, nickname: string, html_url: string, source_url: string>, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record<id: int, name: string, path: string, kind: string, full_path: string, parent_id: int, avatar_url: string, web_url: string>, custom_attributes: record<key: string, value: string>, repository_storage: string, forked_from_project: record<id: int, description: string, name: string, name_with_namespace: string, path: string, path_with_namespace: string, created_at: string, default_branch: string, tag_list: list, topics: list, ssh_url_to_repo: string, http_url_to_repo: string, web_url: string, readme_url: string, forks_count: int, license_url: string, license: record, avatar_url: string, star_count: int, last_activity_at: string, visibility: string, namespace: record, custom_attributes: record, repository_storage: string>, container_registry_image_prefix: string, _links: record<self: string, issues: string, merge_requests: string, repo_branches: string, labels: string, events: string, members: string, cluster_agents: string>, marked_for_deletion_at: string, marked_for_deletion_on: string, packages_enabled: bool, empty_repo: bool, archived: bool, owner: record<id: int, username: string, public_email: string, name: string, state: string, locked: bool, avatar_url: string, avatar_path: string, custom_attributes: list, web_url: string>, resolve_outdated_diff_discussions: bool, container_expiration_policy: record<cadence: string, enabled: string, keep_n: string, older_than: string, name_regex: string, name_regex_keep: string, next_run_at: string>, repository_object_format: string, issues_enabled: bool, merge_requests_enabled: bool, wiki_enabled: bool, jobs_enabled: bool, snippets_enabled: bool, container_registry_enabled: bool, service_desk_enabled: bool, service_desk_address: string, can_create_merge_request_in: bool, issues_access_level: string, repository_access_level: string, merge_requests_access_level: string, forking_access_level: string, wiki_access_level: string, builds_access_level: string, snippets_access_level: string, pages_access_level: string, analytics_access_level: string, container_registry_access_level: string, security_and_compliance_access_level: string, releases_access_level: string, environments_access_level: string, feature_flags_access_level: string, infrastructure_access_level: string, monitor_access_level: string, model_experiments_access_level: string, model_registry_access_level: string, package_registry_access_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, shared_runners_enabled: bool, lfs_enabled: bool, creator_id: int, mr_default_target_self: bool, import_url: string, import_type: string, import_status: string, import_error: string, open_issues_count: int, description_html: string, updated_at: string, ci_default_git_depth: int, ci_delete_pipelines_in_seconds: int, ci_forward_deployment_enabled: bool, ci_forward_deployment_rollback_allowed: bool, ci_job_token_scope_enabled: bool, ci_separated_caches: bool, ci_allow_fork_pipelines_to_run_in_parent_project: bool, ci_id_token_sub_claim_components: list<string>, build_git_strategy: string, keep_latest_artifact: bool, restrict_user_defined_variables: bool, ci_pipeline_variables_minimum_override_role: string, runner_token_expiration_interval: int, group_runners_enabled: bool, resource_group_default_process_mode: string, auto_cancel_pending_pipelines: string, build_timeout: int, auto_devops_enabled: bool, auto_devops_deploy_strategy: string, ci_push_repository_for_job_token_allowed: bool, protect_merge_request_pipelines: bool, ci_display_pipeline_variables: bool, runners_token: string, ci_config_path: string, public_jobs: bool, shared_with_groups: list<record>, only_allow_merge_if_pipeline_succeeds: bool, allow_merge_on_skipped_pipeline: bool, request_access_enabled: bool, only_allow_merge_if_all_discussions_are_resolved: bool, remove_source_branch_after_merge: bool, printing_merge_request_link_enabled: bool, merge_method: string, squash_option: string, enforce_auth_checks_on_uploads: bool, suggestion_commit_message: string, merge_commit_template: string, squash_commit_template: string, mr_default_title_template: string, issue_branch_template: string, statistics: record<commit_count: int, storage_size: int, repository_size: int, wiki_size: int, lfs_objects_size: int, job_artifacts_size: int, pipeline_artifacts_size: int, packages_size: int, snippets_size: int, uploads_size: int, container_registry_size: int>, warn_about_potentially_unwanted_characters: bool, autoclose_referenced_issues: bool, max_artifacts_size: int, approvals_before_merge: string, mirror: string, mirror_user_id: string, mirror_trigger_builds: string, only_mirror_protected_branches: string, mirror_overwrites_diverged_branches: string, external_authorization_classification_label: string, requirements_enabled: string, requirements_access_level: string, security_and_compliance_enabled: string, secret_push_protection_enabled: bool, pre_receive_secret_detection_enabled: bool, compliance_frameworks: string, issues_template: string, merge_requests_template: string, ci_restrict_pipeline_cancellation_role: string, merge_pipelines_enabled: string, merge_trains_enabled: string, merge_trains_skip_train_allowed: string, max_pipelines_per_merge_train: string, only_allow_merge_if_all_status_checks_passed: string, allow_pipeline_trigger_approve_deployment: bool, prevent_merge_without_jira_issue: string, auto_duo_code_review_enabled: string, duo_remote_flows_enabled: string, duo_foundational_flows_enabled: string, duo_sast_fp_detection_enabled: string, duo_secret_detection_fp_enabled: string, duo_sast_vr_workflow_enabled: string, web_based_commit_signing_enabled: string, spp_repository_pipeline_access: bool, security_policy_pipeline_must_succeed: bool, merge_request_title_regex: string, merge_request_title_regex_description: string>, shared_runners_minutes_limit: string, extra_shared_runners_minutes_limit: string, prevent_forking_outside_group: string, service_access_tokens_expiration_enforced: string, experiment_features_enabled: string, membership_lock: string, ip_restriction_ranges: string, allowed_email_domains_list: string, only_allow_merge_if_pipeline_succeeds: string, allow_merge_on_skipped_pipeline: string, only_allow_merge_if_all_discussions_are_resolved: string, unique_project_download_limit: string, unique_project_download_limit_interval_in_seconds: string, unique_project_download_limit_allowlist: string, unique_project_download_limit_alertlist: string, auto_ban_user_on_excessive_projects_download: string> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "with_custom_attributes" $with_custom_attributes "scalar") (serialize-qp "with_projects" $with_projects "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v4/groups/($id)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Remove a group.
#
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
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Archive a group
#
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
]: nothing -> record<id: int, web_url: string, name: string, path: string, description: string, visibility: string, share_with_group_lock: bool, require_two_factor_authentication: bool, two_factor_grace_period: int, project_creation_level: string, auto_devops_enabled: string, subgroup_creation_level: string, emails_disabled: bool, emails_enabled: bool, show_diff_preview_in_email: bool, mentions_disabled: string, lfs_enabled: bool, archived: bool, math_rendering_limits_enabled: bool, lock_math_rendering_limits_enabled: bool, default_branch: string, default_branch_protection: int, default_branch_protection_defaults: string, avatar_url: string, request_access_enabled: bool, full_name: string, full_path: string, created_at: string, parent_id: string, organization_id: int, shared_runners_setting: string, max_artifacts_size: int, custom_attributes: record<key: string, value: string>, statistics: record<storage_size: string, repository_size: string, wiki_size: string, lfs_objects_size: string, job_artifacts_size: string, pipeline_artifacts_size: string, packages_size: string, snippets_size: string, uploads_size: string>, marked_for_deletion_on: string, root_storage_statistics: record<build_artifacts_size: int, container_registry_size: int, container_registry_size_is_estimated: bool, dependency_proxy_size: int, lfs_objects_size: int, packages_size: int, pipeline_artifacts_size: int, repository_size: int, snippets_size: int, storage_size: int, uploads_size: int, wiki_size: int>, ldap_cn: string, ldap_access: string, ldap_group_links: record<cn: string, group_access: int, provider: string, filter: string, member_role_id: int>, saml_group_links: record<name: string, access_level: int, member_role_id: int, provider: string>, file_template_project_id: string, wiki_access_level: string, repository_storage: string, duo_core_features_enabled: bool, duo_features_enabled: string, lock_duo_features_enabled: string, auto_duo_code_review_enabled: string, web_based_commit_signing_enabled: string, allow_personal_snippets: string, duo_namespace_access_rules: string, built_in_project_templates_enabled: bool, lock_built_in_project_templates_enabled: bool> {
  let auth = (build-auth $token ($auth_scheme | default "private-token"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/v4/groups/($id)/archive")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}
