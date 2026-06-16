# Auto-generated client for Asana v1.0
# Source: <spec>
# Auth: --token flag or $env.ASANA_TOKEN

const BASE_URL = "https://app.asana.com/api/1.0"
const DEFAULT_AUTH = "bearer"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o ASANA_TOKEN | default "" }
  let scheme = ($auth_scheme | default "bearer")
  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }
  match $scheme {
    "bearer" => { {headers: {Authorization: $"Bearer ($token_val)"}, query: ""} }
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

def base-url-completer [] { ["https://app.asana.com/api/1.0"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def resource-subtype-completer [] { ["asana" "external"] }
def actor-type-completer [] { ["anonymous" "asana" "asana_support" "external_administrator" "user"] }


# Get access requests
#
# GET /access_requests
# operationId: getAccessRequests
export def "access-requests get" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --target: string
  --user: string
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
]: nothing -> record<data: table<gid: string, resource_type: string, message: string, approval_status: string, requester: record, target: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "target" $target "scalar") (serialize-qp "user" $user "scalar") (serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/access_requests" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Create an access request
#
# POST /access_requests
# operationId: createAccessRequest
export def "access-requests create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --data: record
]: any -> record<data: record<gid: string, resource_type: string, message: string, approval_status: string, requester: record<gid: string, resource_type: string, name: string>, target: record<gid: string, resource_type: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/access_requests")
  let body = {"data": $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Approve an access request
#
# POST /access_requests/{access_request_gid}/approve
# operationId: approveAccessRequest
export def "access-requests-approve approveAccessRequest" [
  access_request_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/access_requests/($access_request_gid)/approve")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Reject an access request
#
# POST /access_requests/{access_request_gid}/reject
# operationId: rejectAccessRequest
export def "access-requests-reject rejectAccessRequest" [
  access_request_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/access_requests/($access_request_gid)/reject")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get a list of agents in a workspace
#
# GET /workspaces/{workspace_gid}/agents
# operationId: getAgentsForWorkspace
export def "workspaces-agents get-agents-for-workspace" [
  workspace_gid: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --limit: int
  --offset: string
  --opt-fields: list
]: nothing -> record<data: table<gid: string, resource_type: string, resource_subtype: string, name: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/workspaces/($workspace_gid)/agents" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get an agent
#
# GET /agents/{agent_gid}
# operationId: getAgent
export def "agents get" [
  agent_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
]: nothing -> record<data: record<gid: string, resource_type: string, resource_subtype: string, name: string, description: string, behavior_guidance: string, workspace: record<gid: string, resource_type: string, name: string>, photo: record<image_21x21: string, image_27x27: string, image_36x36: string, image_60x60: string, image_128x128: string, image_1024x1024: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/agents/($agent_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get an allocation
#
# GET /allocations/{allocation_gid}
# operationId: getAllocation
export def "allocations get" [
  allocation_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
]: nothing -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/allocations/($allocation_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Update an allocation
#
# PUT /allocations/{allocation_gid}
# operationId: updateAllocation
export def "allocations update" [
  allocation_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/allocations/($allocation_gid)" $qp)
  let body = {"data": $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Delete an allocation
#
# DELETE /allocations/{allocation_gid}
# operationId: deleteAllocation
export def "allocations delete" [
  allocation_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/allocations/($allocation_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get multiple allocations
#
# GET /allocations
# operationId: getAllocations
export def "allocations list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --parent: string
  --assignee: string
  --workspace: string
  --limit: int
  --offset: string
  --opt-fields: list
]: nothing -> record<data: table<gid: string, resource_type: string, start_date: string, end_date: string, effort: record, assignee: record, created_by: record, parent: record, resource_subtype: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "parent" $parent "scalar") (serialize-qp "assignee" $assignee "scalar") (serialize-qp "workspace" $workspace "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/allocations" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Create an allocation
#
# POST /allocations
# operationId: createAllocation
export def "allocations create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/allocations" $qp)
  let body = {"data": $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Get an attachment
#
# GET /attachments/{attachment_gid}
# operationId: getAttachment
export def "attachments get" [
  attachment_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
]: nothing -> record<data: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_at: string, download_url: string, permanent_url: string, host: string, parent: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_by: record>, size: int, view_url: string, connected_to_app: bool>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/attachments/($attachment_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Delete an attachment
#
# DELETE /attachments/{attachment_gid}
# operationId: deleteAttachment
export def "attachments delete" [
  attachment_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/attachments/($attachment_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get attachments from an object
#
# GET /attachments
# operationId: getAttachmentsForObject
export def "attachments get-attachments-for-object" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --limit: int
  --offset: string
  --parent: string
  --opt-fields: list
]: nothing -> record<data: table<gid: string, resource_type: string, name: string, resource_subtype: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "parent" $parent "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/attachments" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Upload an attachment
#
# POST /attachments
# operationId: createAttachmentForObject
export def "attachments create-attachment-for-object" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
  --resource-subtype: string@resource-subtype-completer
  --file: string
  parent: string
  --body-url: string
  --name: string
  --connect-to-app: oneof<nothing, bool>
]: any -> record<data: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_at: string, download_url: string, permanent_url: string, host: string, parent: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_by: record>, size: int, view_url: string, connected_to_app: bool>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/attachments" $qp)
  let body = {"resource_subtype": $resource_subtype, "file": $file, "parent": $parent, "url": $body_url, "name": $name, "connect_to_app": $connect_to_app} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "multipart/form-data" $body
}

# Get audit log events
#
# GET /workspaces/{workspace_gid}/audit_log_events
# operationId: getAuditLogEvents
export def "workspaces-audit-log-events get" [
  workspace_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --start-at: string
  --end-at: string
  --event-type: string
  --actor-type: string@actor-type-completer
  --actor-gid: string
  --resource-gid: string
  --limit: int
  --offset: string
]: nothing -> record<data: table<gid: string, created_at: string, event_type: string, event_category: string, actor: record, resource: record, details: record, context: record>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "start_at" $start_at "scalar") (serialize-qp "end_at" $end_at "scalar") (serialize-qp "event_type" $event_type "scalar") (serialize-qp "actor_type" $actor_type "scalar") (serialize-qp "actor_gid" $actor_gid "scalar") (serialize-qp "resource_gid" $resource_gid "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/workspaces/($workspace_gid)/audit_log_events" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Submit parallel requests
#
# POST /batch
# operationId: createBatchRequest
export def "batch create-batch-request" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
  --data: record
]: any -> record<data: table<status_code: int, headers: record, body: record>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/batch" $qp)
  let body = {"data": $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Get all budgets
#
# GET /budgets
# operationId: getBudgets
export def "budgets list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --parent: string
]: nothing -> record<data: table<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "parent" $parent "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/budgets" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Create a budget
#
# POST /budgets
# operationId: createBudget
export def "budgets create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/budgets" $qp)
  let body = {"data": $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Get a budget
#
# GET /budgets/{budget_gid}
# operationId: getBudget
export def "budgets get" [
  budget_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
]: nothing -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/budgets/($budget_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Update a budget
#
# PUT /budgets/{budget_gid}
# operationId: updateBudget
export def "budgets update" [
  budget_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --opt-fields: list
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/budgets/($budget_gid)" $qp)
  let body = {"data": $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# Delete a budget
#
# DELETE /budgets/{budget_gid}
# operationId: deleteBudget
export def "budgets delete" [
  budget_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/budgets/($budget_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get a project's custom fields
#
# GET /projects/{project_gid}/custom_field_settings
# operationId: getCustomFieldSettingsForProject
export def "projects-custom-field-settings get-custom-field-settings-for-project" [
  project_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --limit: int
  --offset: string
  --opt-fields: list
]: nothing -> record<data: table<gid: string, resource_type: string, project: record, is_important: bool, parent: record, custom_field: record>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/projects/($project_gid)/custom_field_settings" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# Get a portfolio's custom fields
#
# GET /portfolios/{portfolio_gid}/custom_field_settings
# operationId: getCustomFieldSettingsForPortfolio
export def "portfolios-custom-field-settings get-custom-field-settings-for-portfolio" [
  portfolio_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool>
  --limit: int
  --offset: string
  --opt-fields: list
]: nothing -> record<data: table<gid: string, resource_type: string, project: record, is_important: bool, parent: record, custom_field: record>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/portfolios/($portfolio_gid)/custom_field_settings" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}
