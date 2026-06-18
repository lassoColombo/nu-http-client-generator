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

# Build a `multipart/form-data` envelope per RFC 7578. `file_fields` lists
# the field names whose value should be read from disk as bytes; every
# other field is sent as a text part (records/lists JSON-stringified).
# Returns {content_type, body} ready to pass to `do-request`.
# When `$dry_run` is true, file fields are NOT read from disk — they emit
# an empty-bytes placeholder so callers can inspect the request shape
# without the file existing on disk (issue 11.B).
def build-multipart-body [parts: record, file_fields: list<string>, dry_run: bool = false]: nothing -> record {
  let boundary = $"----nu-(random chars --length 24)"
  let crlf = "\r\n"
  let chunks = ($parts | transpose k v | where {|p| $p.v != null} | each {|p|
    let name = $p.k
    let val = $p.v
    if $name in $file_fields {
      let filename = ($val | into string | path basename)
      let bytes = if $dry_run { (0x[] | into binary) } else { (open --raw $val | into binary | collect) }
      let head = ($"--($boundary)($crlf)Content-Disposition: form-data; name=\"($name)\"; filename=\"($filename)\"($crlf)Content-Type: application/octet-stream($crlf)($crlf)" | into binary)
      $head ++ $bytes ++ ($crlf | into binary)
    } else {
      let dt = ($val | describe)
      let s = if (($dt | str starts-with "record") or ($dt | str starts-with "list") or ($dt | str starts-with "table")) { ($val | to json --raw) } else { ($val | into string) }
      let head = ($"--($boundary)($crlf)Content-Disposition: form-data; name=\"($name)\"($crlf)($crlf)" | into binary)
      $head ++ ($"($s)($crlf)" | into binary)
    }
  })
  let trailer = ($"--($boundary)--($crlf)" | into binary)
  let body = ($chunks | reduce --fold (0x[] | into binary) {|chunk, acc| $acc ++ $chunk }) ++ $trailer
  {content_type: $"multipart/form-data; boundary=($boundary)", body: $body}
}

def base-url-completer [] { ["https://app.asana.com/api/1.0"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def resource-subtype-completer [] { ["asana" "external"] }
def actor-type-completer [] { ["anonymous" "asana" "asana_support" "external_administrator" "user"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "full" "dry-run" "accept" "help"]
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --target: string # Globally unique identifier for the target object. (e.g. 1331)
  --user: string # A string identifying a user. This can either be the string "me", an email, or the gid of a user. (e.g. me)
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [approval_status, message, requester, requester.name, target])
]: nothing -> record<data: table<gid: string, resource_type: string, message: string, approval_status: string, requester: record, target: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "target" $target "scalar") (serialize-qp "user" $user "scalar") (serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/access_requests" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Create an access request
#
# POST /access_requests
# operationId: createAccessRequest
# --data shape: {target: string, message?: string}
export def "access-requests create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --data: record # A request to create shareable access for a user. — shape: {target: string, message?: string}
]: any -> record<data: record<gid: string, resource_type: string, message: string, approval_status: string, requester: record<gid: string, resource_type: string, name: string>, target: record<gid: string, resource_type: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/access_requests")
  let req_body = {"data": $data} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# Approve an access request
#
# POST /access_requests/{access_request_gid}/approve
# operationId: approveAccessRequest
export def "access-requests-approve approve" [
  access_request_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({access_request_gid: (encode-path-segment $access_request_gid)} | format pattern "/access_requests/{access_request_gid}/approve"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Reject an access request
#
# POST /access_requests/{access_request_gid}/reject
# operationId: rejectAccessRequest
export def "access-requests-reject reject" [
  access_request_gid: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base ({access_request_gid: (encode-path-segment $access_request_gid)} | format pattern "/access_requests/{access_request_gid}/reject"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [behavior_guidance, description, name, offset, path, photo, photo.image_1024x1024, photo.image_128x128, photo.image_21x21, photo.image_27x27, photo.image_36x36, photo.image_60x60, resource_subtype, uri, workspace])
]: nothing -> record<data: table<gid: string, resource_type: string, resource_subtype: string, name: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({workspace_gid: (encode-path-segment $workspace_gid)} | format pattern "/workspaces/{workspace_gid}/agents") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [behavior_guidance, description, name, photo, photo.image_1024x1024, photo.image_128x128, photo.image_21x21, photo.image_27x27, photo.image_36x36, photo.image_60x60, resource_subtype, workspace])
]: nothing -> record<data: record<gid: string, resource_type: string, resource_subtype: string, name: string, description: string, behavior_guidance: string, workspace: record<gid: string, resource_type: string, name: string>, photo: record<image_21x21: string, image_27x27: string, image_36x36: string, image_60x60: string, image_128x128: string, image_1024x1024: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({agent_gid: (encode-path-segment $agent_gid)} | format pattern "/agents/{agent_gid}") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [assignee, assignee.name, created_by, created_by.name, effort, effort.type, effort.value, end_date, parent, parent.name, resource_subtype, start_date])
]: nothing -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({allocation_gid: (encode-path-segment $allocation_gid)} | format pattern "/allocations/{allocation_gid}") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [assignee, assignee.name, created_by, created_by.name, effort, effort.type, effort.value, end_date, parent, parent.name, resource_subtype, start_date])
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({allocation_gid: (encode-path-segment $allocation_gid)} | format pattern "/allocations/{allocation_gid}") $qp)
  let req_body = {"data": $data} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({allocation_gid: (encode-path-segment $allocation_gid)} | format pattern "/allocations/{allocation_gid}") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --parent: string # Globally unique identifier for the project to filter allocations by. (e.g. 77688)
  --assignee: string # Globally unique identifier for the user or placeholder the allocation is assigned to. (e.g. 12345)
  --workspace: string # Globally unique identifier for the workspace. (e.g. 98765)
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [assignee, assignee.name, created_by, created_by.name, effort, effort.type, effort.value, end_date, offset, parent, parent.name, path, resource_subtype, start_date, uri])
]: nothing -> record<data: table<gid: string, resource_type: string, start_date: string, end_date: string, effort: record, assignee: record, created_by: record, parent: record, resource_subtype: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "parent" $parent "scalar") (serialize-qp "assignee" $assignee "scalar") (serialize-qp "workspace" $workspace "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/allocations" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [assignee, assignee.name, created_by, created_by.name, effort, effort.type, effort.value, end_date, parent, parent.name, resource_subtype, start_date])
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, start_date: string, end_date: string, effort: record<type: string, value: float>, assignee: record<gid: string, resource_type: string, name: string>, created_by: record<gid: string, resource_type: string, name: string>, parent: record<gid: string, resource_type: string, name: string>, resource_subtype: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/allocations" $qp)
  let req_body = {"data": $data} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [connected_to_app, created_at, download_url, host, name, parent, parent.created_by, parent.name, parent.resource_subtype, permanent_url, resource_subtype, size, view_url])
]: nothing -> record<data: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_at: string, download_url: string, permanent_url: string, host: string, parent: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_by: record>, size: int, view_url: string, connected_to_app: bool>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({attachment_gid: (encode-path-segment $attachment_gid)} | format pattern "/attachments/{attachment_gid}") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({attachment_gid: (encode-path-segment $attachment_gid)} | format pattern "/attachments/{attachment_gid}") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Get attachments from an object
#
# GET /attachments
# operationId: getAttachmentsForObject
export def "attachments get-for-object" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --parent: string # Globally unique identifier for object to fetch statuses from. Must be a GID for a `project`, `project_brief`, or `task`. (e.g. 159874)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [connected_to_app, created_at, download_url, host, name, offset, parent, parent.created_by, parent.name, parent.resource_subtype, path, permanent_url, resource_subtype, size, uri, view_url])
]: nothing -> record<data: table<gid: string, resource_type: string, name: string, resource_subtype: string>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "parent" $parent "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/attachments" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Upload an attachment
#
# POST /attachments
# operationId: createAttachmentForObject
# --body shape: {resource_subtype?: "asana"|"external", file?: string, parent: string, url?: string, name?: string, connect_to_app?: bool}
export def "attachments create-for-object" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [connected_to_app, created_at, download_url, host, name, parent, parent.created_by, parent.name, parent.resource_subtype, permanent_url, resource_subtype, size, view_url])
  --body: record # shape: {resource_subtype?: "asana"|"external", file?: string, parent: string, url?: string, name?: string, connect_to_app?: bool}
]: any -> record<data: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_at: string, download_url: string, permanent_url: string, host: string, parent: record<gid: string, resource_type: string, name: string, resource_subtype: string, created_by: record>, size: int, view_url: string, connected_to_app: bool>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/attachments" $qp)
  let req_body = $body
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  let req_body = if ($req_body | describe | str starts-with "record") { $req_body } else { {} }
  let mp = (build-multipart-body $req_body ["file"] $dry_run)
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full $mp.content_type $mp.body
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
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
  let full_url = (build-url $base ({workspace_gid: (encode-path-segment $workspace_gid)} | format pattern "/workspaces/{workspace_gid}/audit_log_events") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# Submit parallel requests
#
# POST /batch
# operationId: createBatchRequest
# --data shape: {actions?: list}
export def "batch create-request" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [body, headers, status_code])
  --data: record # A request object for use in a batch request. — shape: {actions?: list}
]: any -> record<data: table<status_code: int, headers: record, body: record>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base "/batch" $qp)
  let req_body = {"data": $data} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --parent: string # Globally unique identifier for the budget's parent object. This currently can only be a `project`. (e.g. 1331)
]: nothing -> record<data: table<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "parent" $parent "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/budgets" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/budgets" $qp)
  let req_body = {"data": $data} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [actual, actual.billable_status_filter, actual.units, actual.value, budget_type, estimate, estimate.billable_status_filter, estimate.enabled, estimate.source, estimate.units, estimate.value, parent, parent.name, total, total.enabled, total.units, total.value])
]: nothing -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({budget_gid: (encode-path-segment $budget_gid)} | format pattern "/budgets/{budget_gid}") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [actual, actual.billable_status_filter, actual.units, actual.value, budget_type, estimate, estimate.billable_status_filter, estimate.enabled, estimate.source, estimate.units, estimate.value, parent, parent.name, total, total.enabled, total.units, total.value])
  --data: any
]: any -> record<data: record<gid: string, resource_type: string, budget_type: string, estimate: record, actual: record, total: record, parent: record<gid: string, resource_type: string, name: string>>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({budget_gid: (encode-path-segment $budget_gid)} | format pattern "/budgets/{budget_gid}") $qp)
  let req_body = {"data": $data} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
]: nothing -> record<data: record> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({budget_gid: (encode-path-segment $budget_gid)} | format pattern "/budgets/{budget_gid}") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [custom_field, custom_field.asana_created_field, custom_field.created_by, custom_field.created_by.name, custom_field.currency_code, custom_field.custom_label, custom_field.custom_label_position, custom_field.date_value, custom_field.date_value.date, custom_field.date_value.date_time, custom_field.default_access_level, custom_field.description, custom_field.display_value, custom_field.enabled, custom_field.enum_options, custom_field.enum_options.color, custom_field.enum_options.enabled, custom_field.enum_options.name, custom_field.enum_value, custom_field.enum_value.color, custom_field.enum_value.enabled, custom_field.enum_value.name, custom_field.format, custom_field.has_notifications_enabled, custom_field.html_text_value, custom_field.id_prefix, custom_field.input_restrictions, custom_field.is_formula_field, custom_field.is_global_to_workspace, custom_field.is_value_read_only, custom_field.multi_enum_values, custom_field.multi_enum_values.color, custom_field.multi_enum_values.enabled, custom_field.multi_enum_values.name, custom_field.name, custom_field.number_value, custom_field.people_value, custom_field.people_value.name, custom_field.precision, custom_field.privacy_setting, custom_field.reference_value, custom_field.reference_value.name, custom_field.representation_type, custom_field.resource_subtype, custom_field.text_value, custom_field.type, is_important, offset, parent, parent.name, path, project, project.name, uri])
]: nothing -> record<data: table<gid: string, resource_type: string, project: record, is_important: bool, parent: record, custom_field: record>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({project_gid: (encode-path-segment $project_gid)} | format pattern "/projects/{project_gid}/custom_field_settings") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
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
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --opt-pretty: oneof<nothing, bool> # Provides “pretty” output. Provides the response in a “pretty” format. In the case of JSON this means doing proper line breaking and indentation to make it readable. This will take extra time and increase the response size so it is advisable only to use this during debugging. (e.g. true, allows empty value)
  --limit: int # Results per page. The number of objects to return per page. The value must be between 1 and 100. (e.g. 50)
  --offset: string # Offset token. An offset to the next page returned by the API. A pagination request will return an offset token, which can be used as an input parameter to the next request. If an offset is not passed in, the API will return the first page of results. *Note: You can only pass in an offset that was returned to you via a previously paginated request.* (e.g. eyJ0eXAiOJiKV1iQLCJhbGciOiJIUzI1NiJ9)
  --opt-fields: list<string> # This endpoint returns a resource which excludes some properties by default. To include those optional properties, set this query parameter to a comma-separated list of the properties you wish to include. (e.g. [custom_field, custom_field.asana_created_field, custom_field.created_by, custom_field.created_by.name, custom_field.currency_code, custom_field.custom_label, custom_field.custom_label_position, custom_field.date_value, custom_field.date_value.date, custom_field.date_value.date_time, custom_field.default_access_level, custom_field.description, custom_field.display_value, custom_field.enabled, custom_field.enum_options, custom_field.enum_options.color, custom_field.enum_options.enabled, custom_field.enum_options.name, custom_field.enum_value, custom_field.enum_value.color, custom_field.enum_value.enabled, custom_field.enum_value.name, custom_field.format, custom_field.has_notifications_enabled, custom_field.html_text_value, custom_field.id_prefix, custom_field.input_restrictions, custom_field.is_formula_field, custom_field.is_global_to_workspace, custom_field.is_value_read_only, custom_field.multi_enum_values, custom_field.multi_enum_values.color, custom_field.multi_enum_values.enabled, custom_field.multi_enum_values.name, custom_field.name, custom_field.number_value, custom_field.people_value, custom_field.people_value.name, custom_field.precision, custom_field.privacy_setting, custom_field.reference_value, custom_field.reference_value.name, custom_field.representation_type, custom_field.resource_subtype, custom_field.text_value, custom_field.type, is_important, offset, parent, parent.name, path, project, project.name, uri])
]: nothing -> record<data: table<gid: string, resource_type: string, project: record, is_important: bool, parent: record, custom_field: record>, next_page: record<offset: string, path: string, uri: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "opt_pretty" $opt_pretty "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "offset" $offset "scalar") (serialize-qp "opt_fields" $opt_fields "csv")] | flatten | str join "&"
  let full_url = (build-url $base ({portfolio_gid: (encode-path-segment $portfolio_gid)} | format pattern "/portfolios/{portfolio_gid}/custom_field_settings") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}
