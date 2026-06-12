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

def base-url-completer [] { ["https://app.asana.com/api/1.0"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def resource-subtype-completer [] { ["asana" "external"] }
def actor-type-completer [] { ["anonymous" "asana" "asana_support" "external_administrator" "user"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "access-requests get" } } | get name | first)
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
  --target: string # Globally unique identifier for the target object. (e.g. 1331)
  --user: string # A string identifying a user. This can either be the string "me", an email, or the gid of a user. (e.g. me)
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [approval_status, message, requester, requester.name, target])
]: nothing -> record<data: table<gid: string, resource_type: string, message: string, approval_status: string, requester: record, target: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "target" $target "scalar") (serialize-qp "user" $user "scalar") (serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/access_requests" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Create an access request
#
# POST /access_requests
# operationId: createAccessRequest
# --data shape: {target: string, message?: string}
export def "access-requests createAccessRequest" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --data: record # A request to create shareable access for a user. — shape: {target: string, message?: string}
]: any -> record<data: record<gid: string, resource_type: string, message: string, approval_status: string, requester: record<gid: string, resource_type: string, name: string>, target: record<gid: string, resource_type: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/access_requests")
  let body = {data: $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
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
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/access_requests/($access_request_gid)/approve")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
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
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/access_requests/($access_request_gid)/reject")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get a list of agents in a workspace
#
# GET /workspaces/{workspace_gid}/agents
# operationId: getAgentsForWorkspace
export def "workspaces-agents get" [
  workspace_gid: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [behavior_guidance, description, name, offset, path, photo, photo.image_1024x1024, photo.image_128x128, photo.image_21x21, photo.image_27x27, photo.image_36x36, photo.image_60x60, resource_subtype, uri, workspace])
]: nothing -> record<data: table<gid: string, resource_type: string, resource_subtype: string, name: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/workspaces/($workspace_gid)/agents" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
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
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [behavior_guidance, description, name, photo, photo.image_1024x1024, photo.image_128x128, photo.image_21x21, photo.image_27x27, photo.image_36x36, photo.image_60x60, resource_subtype, workspace])
]: nothing -> record<data: record<gid: string, resource_type: string, resource_subtype: string, name: string, description: string, behavior_guidance: string, workspace: record<gid: string, resource_type: string, name: string>, photo: record<image_21x21: string, image_27x27: string, image_36x36: string, image_60x60: string, image_128x128: string, image_1024x1024: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/agents/($agent_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
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
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [assignee, assignee.name, created_by, created_by.name, effort, effort.type, effort.value, end_date, parent, parent.name, resource_subtype, start_date])
]: nothing -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/allocations/($allocation_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Update an allocation
#
# PUT /allocations/{allocation_gid}
# operationId: updateAllocation
export def "allocations updateAllocation" [
  allocation_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [assignee, assignee.name, created_by, created_by.name, effort, effort.type, effort.value, end_date, parent, parent.name, resource_subtype, start_date])
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/allocations/($allocation_gid)" $qp)
  let body = {data: $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
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
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/allocations/($allocation_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
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
  --parent: string # Globally unique identifier for the project to filter allocations by. (e.g. 77688)
  --assignee: string # Globally unique identifier for the user or placeholder the allocation is assigned to. (e.g. 12345)
  --workspace: string # Globally unique identifier for the workspace. (e.g. 98765)
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [assignee, assignee.name, created_by, created_by.name, effort, effort.type, effort.value, end_date, offset, parent, parent.name, path, resource_subtype, start_date, uri])
]: nothing -> record<data: table<gid: string, resource_type: string, start_date: string, end_date: string, effort: record, assignee: record, created_by: record, parent: record, resource_subtype: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "parent" $parent "scalar") (serialize-qp "assignee" $assignee "scalar") (serialize-qp "workspace" $workspace "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/allocations" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Create an allocation
#
# POST /allocations
# operationId: createAllocation
export def "allocations createAllocation" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [assignee, assignee.name, created_by, created_by.name, effort, effort.type, effort.value, end_date, parent, parent.name, resource_subtype, start_date])
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/allocations" $qp)
  let body = {data: $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
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
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [connected_to_app, created_at, download_url, host, name, parent, parent.created_by, parent.name, parent.resource_subtype, permanent_url, resource_subtype, size, view_url])
]: nothing -> record<data: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_at: string, download_url: string, permanent_url: string, host: string, parent: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_by: record>, size: int, view_url: string, connected_to_app: bool>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/attachments/($attachment_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
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
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/attachments/($attachment_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get attachments from an object
#
# GET /attachments
# operationId: getAttachmentsForObject
export def "attachments list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --parent: string # Globally unique identifier for object to fetch statuses from. Must be a GID for a `project`, `project_brief`, or `task`. (e.g. 159874)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [connected_to_app, created_at, download_url, host, name, offset, parent, parent.created_by, parent.name, parent.resource_subtype, path, permanent_url, resource_subtype, size, uri, view_url])
]: nothing -> record<data: table<gid: string, resource_type: string, name: string, resource_subtype: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "parent" $parent "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/attachments" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Upload an attachment
#
# POST /attachments
# operationId: createAttachmentForObject
export def "attachments createAttachmentForObject" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [connected_to_app, created_at, download_url, host, name, parent, parent.created_by, parent.name, parent.resource_subtype, permanent_url, resource_subtype, size, view_url])
  --resource-subtype: string@resource-subtype-completer # The type of the attachment. Must be one of the given values. If not specified, a file attachment of type `asana` will be assumed. Note that if the value of `resource_subtype` is `external`, a `parent`, `name`, and `url` must also be provided.  (e.g. external)
  --file: string # Required for `asana` attachments.  (format: binary)
  parent: string # Required identifier of the parent task, project, or project_brief, as a string.
  --body-url: string # The URL of the external resource being attached. Required for attachments of type `external`.
  --name: string # The name of the external resource being attached. Required for attachments of type `external`.
  --connect-to-app: oneof<nothing, bool> # *Optional*. Only relevant for external attachments with a parent task. A boolean indicating whether the current app should be connected with the attachment for the purposes of showing an app components widget. Requires the app to have been added to a project the parent task is in. This property can only be set if an OAuth token is used to authenticate the request.  Criteria for displaying app widget: 1. An OAuth token must be used to authenticate the request 2. The app needs to have its `widget_metadata_url` configured in the developer console 3. The task the attachment is being attached to must be in a project with the app installed
]: any -> record<data: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_at: string, download_url: string, permanent_url: string, host: string, parent: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_by: record>, size: int, view_url: string, connected_to_app: bool>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/attachments" $qp)
  let body = {resource_subtype: $resource_subtype, file: $file, parent: $parent, url: $body_url, name: $name, connect_to_app: $connect_to_app} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "multipart/form-data" $body
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
  --start-at: string # Filter to events created after this time (inclusive). (format: date-time)
  --end-at: string # Filter to events created before this time (exclusive). (format: date-time)
  --event-type: string # Filter to events of this type. Refer to the [supported audit log events](/docs/audit-log-events#supported-audit-log-events) for a full list of values.
  --actor-type: string@actor-type-completer # Filter to events with an actor of this type. This only needs to be included if querying for actor types without an ID. If `actor_gid` is included, this should be excluded.
  --actor-gid: string # Filter to events triggered by the actor with this ID.
  --resource-gid: string # Filter to events with this resource ID.
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
]: nothing -> record<data: table<gid: string, created_at: string, event_type: string, event_category: string, actor: record, resource: record, details: record, context: record>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "start_at" $start_at "scalar") (serialize-qp "end_at" $end_at "scalar") (serialize-qp "event_type" $event_type "scalar") (serialize-qp "actor_type" $actor_type "scalar") (serialize-qp "actor_gid" $actor_gid "scalar") (serialize-qp "resource_gid" $resource_gid "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/workspaces/($workspace_gid)/audit_log_events" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Submit parallel requests
#
# POST /batch
# operationId: createBatchRequest
# --data shape: {actions?: list}
export def "batch createBatchRequest" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [body, headers, status_code])
  --data: record # A request object for use in a batch request. — shape: {actions?: list}
]: any -> record<data: table<status_code: int, headers: record, body: record>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/batch" $qp)
  let body = {data: $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
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
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --parent: string # Globally unique identifier for the budget's parent object. This currently can only be a `project`. (e.g. 1331)
]: nothing -> record<data: table<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "parent" $parent "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/budgets" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Create a budget
#
# POST /budgets
# operationId: createBudget
export def "budgets createBudget" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/budgets" $qp)
  let body = {data: $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
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
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [actual, actual.billable_status_filter, actual.units, actual.value, budget_type, estimate, estimate.billable_status_filter, estimate.enabled, estimate.source, estimate.units, estimate.value, parent, parent.name, total, total.enabled, total.units, total.value])
]: nothing -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/budgets/($budget_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Update a budget
#
# PUT /budgets/{budget_gid}
# operationId: updateBudget
export def "budgets updateBudget" [
  budget_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [actual, actual.billable_status_filter, actual.units, actual.value, budget_type, estimate, estimate.billable_status_filter, estimate.enabled, estimate.source, estimate.units, estimate.value, parent, parent.name, total, total.enabled, total.units, total.value])
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/budgets/($budget_gid)" $qp)
  let body = {data: $data} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
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
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/budgets/($budget_gid)" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get a project's custom fields
#
# GET /projects/{project_gid}/custom_field_settings
# operationId: getCustomFieldSettingsForProject
export def "projects-custom-field-settings get" [
  project_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [custom_field, custom_field.asana_created_field, custom_field.created_by, custom_field.created_by.name, custom_field.currency_code, custom_field.custom_label, custom_field.custom_label_position, custom_field.date_value, custom_field.date_value.date, custom_field.date_value.date_time, custom_field.default_access_level, custom_field.description, custom_field.display_value, custom_field.enabled, custom_field.enum_options, custom_field.enum_options.color, custom_field.enum_options.enabled, custom_field.enum_options.name, custom_field.enum_value, custom_field.enum_value.color, custom_field.enum_value.enabled, custom_field.enum_value.name, custom_field.format, custom_field.has_notifications_enabled, custom_field.html_text_value, custom_field.id_prefix, custom_field.input_restrictions, custom_field.is_formula_field, custom_field.is_global_to_workspace, custom_field.is_value_read_only, custom_field.multi_enum_values, custom_field.multi_enum_values.color, custom_field.multi_enum_values.enabled, custom_field.multi_enum_values.name, custom_field.name, custom_field.number_value, custom_field.people_value, custom_field.people_value.name, custom_field.precision, custom_field.privacy_setting, custom_field.reference_value, custom_field.reference_value.name, custom_field.representation_type, custom_field.resource_subtype, custom_field.text_value, custom_field.type, is_important, offset, parent, parent.name, path, project, project.name, uri])
]: nothing -> record<data: table<gid: string, resource_type: string, project: record, is_important: bool, parent: record, custom_field: record>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/projects/($project_gid)/custom_field_settings" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get a portfolio's custom fields
#
# GET /portfolios/{portfolio_gid}/custom_field_settings
# operationId: getCustomFieldSettingsForPortfolio
export def "portfolios-custom-field-settings get" [
  portfolio_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --opt-fields: list # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [custom_field, custom_field.asana_created_field, custom_field.created_by, custom_field.created_by.name, custom_field.currency_code, custom_field.custom_label, custom_field.custom_label_position, custom_field.date_value, custom_field.date_value.date, custom_field.date_value.date_time, custom_field.default_access_level, custom_field.description, custom_field.display_value, custom_field.enabled, custom_field.enum_options, custom_field.enum_options.color, custom_field.enum_options.enabled, custom_field.enum_options.name, custom_field.enum_value, custom_field.enum_value.color, custom_field.enum_value.enabled, custom_field.enum_value.name, custom_field.format, custom_field.has_notifications_enabled, custom_field.html_text_value, custom_field.id_prefix, custom_field.input_restrictions, custom_field.is_formula_field, custom_field.is_global_to_workspace, custom_field.is_value_read_only, custom_field.multi_enum_values, custom_field.multi_enum_values.color, custom_field.multi_enum_values.enabled, custom_field.multi_enum_values.name, custom_field.name, custom_field.number_value, custom_field.people_value, custom_field.people_value.name, custom_field.precision, custom_field.privacy_setting, custom_field.reference_value, custom_field.reference_value.name, custom_field.representation_type, custom_field.resource_subtype, custom_field.text_value, custom_field.type, is_important, offset, parent, parent.name, path, project, project.name, uri])
]: nothing -> record<data: table<gid: string, resource_type: string, project: record, is_important: bool, parent: record, custom_field: record>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base $"/portfolios/($portfolio_gid)/custom_field_settings" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}
