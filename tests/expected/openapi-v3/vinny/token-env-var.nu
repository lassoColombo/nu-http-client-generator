# Auto-generated client for vinny v1.38.0-q1779702605
# Source: <spec>
# Auth: --token flag or $env.TEST_TOKEN

const BASE_URL = "https://avcfg.k8s.elmec.ad"
const DEFAULT_AUTH = "jwt"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o TEST_TOKEN | default "" }
  let scheme = ($auth_scheme | default "bearer")
  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }
  match $scheme {
    "jwt" => { {headers: {Authorization: $"JWT ($token_val)"}, query: ""} }
    "bearer" => { {headers: {Authorization: $"Bearer ($token_val)"}, query: ""} }
    "static" => { {headers: {Authorization: $"STATIC ($token_val)"}, query: ""} }
    "none" => { {headers: {}, query: ""} }
    _ => { {headers: {Authorization: $"Bearer ($token_val)"}, query: ""} }
  }
}

# Serialize a single query parameter based on collection style
# Uses encode-path-segment for keys and values: RFC 3986 unreserved chars
# ([A-Za-z0-9-._~]) stay literal; everything else gets %XX.
def serialize-qp [name: string, value: any, style: string]: nothing -> list<string> {
  if ($value == null) { return [] }
  let is_list = ($value | describe | str starts-with "list")
  if $is_list and ($value | is-empty) { return [] }
  let n = (encode-path-segment $name)
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

def base-url-completer [] { ["https://avcfg.k8s.elmec.ad"] }
def auth-scheme-completer [] { ["jwt" "bearer" "static"] }

# Completers for enum parameters
def type-completer [] { ["MOB" "PC" "SRV"] }
def health-status-completer [] { ["" "BAD" "GOOD" "WARN"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "full" "dry-run" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "avcfg-asset get" } } | get name | first)
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

# GET /avcfg/asset/{id}/
#
# operationId: avcfg_asset_retrieve
export def "avcfg-asset get" [
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
]: nothing -> record<id: int, type: string, hostname: string, last_seen: string, health_status: string, active_av: string, person_name: string, via_login: string, additional_info: string, atlantis_id: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($id | is-empty) { error make --unspanned { msg: "path parameter 'id' must be non-empty" } }
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/avcfg/asset/{id}/"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# PATCH /avcfg/asset/enable/{id}/
#
# operationId: avcfg_asset_enable_partial_update
export def "avcfg-asset-enable update" [
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
  --type: string@type-completer # * `SRV` - server * `PC` - computer * `MOB` - mobile
  --hostname: string
  --last-seen: string # nullable, format: date-time
  --health-status: string@health-status-completer # * `GOOD` - good * `WARN` - warning * `BAD` - bad (nullable)
  --active-av: string # nullable
  --person-name: string # nullable
  --via-login: string # nullable
  --atlantis-id: string # nullable
]: any -> record<id: int, type: string, hostname: string, last_seen: string, health_status: string, active_av: string, person_name: string, via_login: string, additional_info: string, atlantis_id: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($id | is-empty) { error make --unspanned { msg: "path parameter 'id' must be non-empty" } }
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/avcfg/asset/enable/{id}/"))
  let req_body = {"type": $type, "hostname": $hostname, "last_seen": $last_seen, "health_status": $health_status, "active_av": $active_av, "person_name": $person_name, "via_login": $via_login, "atlantis_id": $atlantis_id} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# GET /avcfg/chart/endpoints/{idrs}/
#
# operationId: avcfg_chart_endpoints_list
export def "avcfg-chart-endpoints list" [
  idrs: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # A page number within the paginated result set.
  --per-page: int # Number of results to return per page.
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($idrs | is-empty) { error make --unspanned { msg: "path parameter 'idrs' must be non-empty" } }
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({idrs: (encode-path-segment $idrs)} | format pattern "/avcfg/chart/endpoints/{idrs}/") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# GET /avcfg/customers/
#
# operationId: avcfg_customers_list
export def "avcfg-customers list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --idrs: string
  --page: int # A page number within the paginated result set.
  --per-page: int # Number of results to return per page.
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "idrs" $idrs "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/avcfg/customers/" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# PUT /avcfg/cynet/alerts/acknowledge/{id}/
#
# operationId: avcfg_cynet_alerts_acknowledge_update
export def "avcfg-cynet-alerts-acknowledge update-by-id" [
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
  --uniqueness: string # nullable
  --incident-name: string # nullable
  --eps-prevention: oneof<nothing, bool> # nullable
  --eps-prevention-success: string # nullable
  --path: string # nullable
  --command-line: string # nullable
  --alert-ip: string # nullable
  --alert-domain: string # nullable
  --alert-url: string # nullable
  --username: string # nullable
  --severity: string # nullable
  --status: string # nullable
  --alert-type: string # nullable
  --date-in: string # nullable
  --last-seen: string # nullable, format: date-time
  --date-changed: string # nullable
  --remediation-status: string # nullable
  --scan-group-name: string # nullable
  --file: string # nullable
  --acknowledged: oneof<nothing, bool>
  --notified-llama: oneof<nothing, bool>
  --notified-cardinalis: oneof<nothing, bool>
  --customer: int # nullable
]: any -> record<id: int, endpoint_name: string, endpoint_id: string, user_name: string, user_id: string, mapped_status: string, endpoint_atlantis_id: string, solved: string, type: string, created_at: string, updated_at: string, uniqueness: string, incident_name: string, eps_prevention: bool, eps_prevention_success: string, path: string, command_line: string, alert_ip: string, alert_domain: string, alert_url: string, username: string, severity: string, status: string, alert_type: string, date_in: string, last_seen: string, date_changed: string, remediation_status: string, scan_group_name: string, file: string, acknowledged: bool, notified_llama: bool, notified_cardinalis: bool, customer: int> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($id | is-empty) { error make --unspanned { msg: "path parameter 'id' must be non-empty" } }
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/avcfg/cynet/alerts/acknowledge/{id}/"))
  let req_body = {"uniqueness": $uniqueness, "incident_name": $incident_name, "eps_prevention": $eps_prevention, "eps_prevention_success": $eps_prevention_success, "path": $path, "command_line": $command_line, "alert_ip": $alert_ip, "alert_domain": $alert_domain, "alert_url": $alert_url, "username": $username, "severity": $severity, "status": $status, "alert_type": $alert_type, "date_in": $date_in, "last_seen": $last_seen, "date_changed": $date_changed, "remediation_status": $remediation_status, "scan_group_name": $scan_group_name, "file": $file, "acknowledged": $acknowledged, "notified_llama": $notified_llama, "notified_cardinalis": $notified_cardinalis, "customer": $customer} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# PATCH /avcfg/cynet/alerts/acknowledge/{id}/
#
# operationId: avcfg_cynet_alerts_acknowledge_partial_update
export def "avcfg-cynet-alerts-acknowledge update-by-id-1" [
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
  --uniqueness: string # nullable
  --incident-name: string # nullable
  --eps-prevention: oneof<nothing, bool> # nullable
  --eps-prevention-success: string # nullable
  --path: string # nullable
  --command-line: string # nullable
  --alert-ip: string # nullable
  --alert-domain: string # nullable
  --alert-url: string # nullable
  --username: string # nullable
  --severity: string # nullable
  --status: string # nullable
  --alert-type: string # nullable
  --date-in: string # nullable
  --last-seen: string # nullable, format: date-time
  --date-changed: string # nullable
  --remediation-status: string # nullable
  --scan-group-name: string # nullable
  --file: string # nullable
  --acknowledged: oneof<nothing, bool>
  --notified-llama: oneof<nothing, bool>
  --notified-cardinalis: oneof<nothing, bool>
  --customer: int # nullable
]: any -> record<id: int, endpoint_name: string, endpoint_id: string, user_name: string, user_id: string, mapped_status: string, endpoint_atlantis_id: string, solved: string, type: string, created_at: string, updated_at: string, uniqueness: string, incident_name: string, eps_prevention: bool, eps_prevention_success: string, path: string, command_line: string, alert_ip: string, alert_domain: string, alert_url: string, username: string, severity: string, status: string, alert_type: string, date_in: string, last_seen: string, date_changed: string, remediation_status: string, scan_group_name: string, file: string, acknowledged: bool, notified_llama: bool, notified_cardinalis: bool, customer: int> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($id | is-empty) { error make --unspanned { msg: "path parameter 'id' must be non-empty" } }
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/avcfg/cynet/alerts/acknowledge/{id}/"))
  let req_body = {"uniqueness": $uniqueness, "incident_name": $incident_name, "eps_prevention": $eps_prevention, "eps_prevention_success": $eps_prevention_success, "path": $path, "command_line": $command_line, "alert_ip": $alert_ip, "alert_domain": $alert_domain, "alert_url": $alert_url, "username": $username, "severity": $severity, "status": $status, "alert_type": $alert_type, "date_in": $date_in, "last_seen": $last_seen, "date_changed": $date_changed, "remediation_status": $remediation_status, "scan_group_name": $scan_group_name, "file": $file, "acknowledged": $acknowledged, "notified_llama": $notified_llama, "notified_cardinalis": $notified_cardinalis, "customer": $customer} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# GET /avcfg/cynet/alerts/list/{idrs}/
#
# operationId: avcfg_cynet_alerts_list_list
export def "avcfg-cynet-alerts-list list" [
  idrs: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --acknowledged: oneof<nothing, bool>
  --alert-domain: string
  --alert-ip: string
  --alert-type: string
  --alert-url: string
  --command-line: string
  --created-at: string # format: date-time
  --customer: int
  --date-changed: string
  --date-in: string
  --date-in-gte: string # format: date
  --date-in-lte: string # format: date
  --endpoint: int
  --endpoint-name: string
  --endpoint-type: string
  --eps-prevention: oneof<nothing, bool>
  --eps-prevention-success: string
  --file: string
  --incident-name: string
  --last-seen: string # format: date-time
  --last-seen-gte: string # format: date
  --last-seen-lte: string # format: date
  --notified-cardinalis: oneof<nothing, bool>
  --notified-llama: oneof<nothing, bool>
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --path: string
  --per-page: int # Number of results to return per page.
  --remediation-status: string
  --scan-group-name: string
  --search: string # A search term.
  --severity: string
  --solved: oneof<nothing, bool>
  --status: string
  --tenant: int
  --type: string
  --uniqueness: string
  --updated-at: string # format: date-time
  --user: int
  --user-name: string
  --username: string
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($idrs | is-empty) { error make --unspanned { msg: "path parameter 'idrs' must be non-empty" } }
  let qp = [(serialize-qp "acknowledged" $acknowledged "scalar") (serialize-qp "alert_domain" $alert_domain "scalar") (serialize-qp "alert_ip" $alert_ip "scalar") (serialize-qp "alert_type" $alert_type "scalar") (serialize-qp "alert_url" $alert_url "scalar") (serialize-qp "command_line" $command_line "scalar") (serialize-qp "created_at" $created_at "scalar") (serialize-qp "customer" $customer "scalar") (serialize-qp "date_changed" $date_changed "scalar") (serialize-qp "date_in" $date_in "scalar") (serialize-qp "date_in__gte" $date_in_gte "scalar") (serialize-qp "date_in__lte" $date_in_lte "scalar") (serialize-qp "endpoint" $endpoint "scalar") (serialize-qp "endpoint_name" $endpoint_name "scalar") (serialize-qp "endpoint_type" $endpoint_type "scalar") (serialize-qp "eps_prevention" $eps_prevention "scalar") (serialize-qp "eps_prevention_success" $eps_prevention_success "scalar") (serialize-qp "file" $file "scalar") (serialize-qp "incident_name" $incident_name "scalar") (serialize-qp "last_seen" $last_seen "scalar") (serialize-qp "last_seen__gte" $last_seen_gte "scalar") (serialize-qp "last_seen__lte" $last_seen_lte "scalar") (serialize-qp "notified_cardinalis" $notified_cardinalis "scalar") (serialize-qp "notified_llama" $notified_llama "scalar") (serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "path" $path "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "remediation_status" $remediation_status "scalar") (serialize-qp "scan_group_name" $scan_group_name "scalar") (serialize-qp "search" $search "scalar") (serialize-qp "severity" $severity "scalar") (serialize-qp "solved" $solved "scalar") (serialize-qp "status" $status "scalar") (serialize-qp "tenant" $tenant "scalar") (serialize-qp "type" $type "scalar") (serialize-qp "uniqueness" $uniqueness "scalar") (serialize-qp "updated_at" $updated_at "scalar") (serialize-qp "user" $user "scalar") (serialize-qp "user_name" $user_name "scalar") (serialize-qp "username" $username "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({idrs: (encode-path-segment $idrs)} | format pattern "/avcfg/cynet/alerts/list/{idrs}/") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# List all XDR log for a IDRS
#
# GET /avcfg/cynet/alerts/list/scangroup/{idrs}/
# operationId: avcfg_cynet_alerts_list_scangroup_list
export def "avcfg-cynet-alerts-list-scangroup list" [
  idrs: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --acknowledged: oneof<nothing, bool>
  --alert-domain: string
  --alert-ip: string
  --alert-type: string
  --alert-url: string
  --command-line: string
  --created-at: string # format: date-time
  --customer: int
  --date-changed: string
  --date-in: string
  --date-in-gte: string # format: date
  --date-in-lte: string # format: date
  --endpoint: int
  --endpoint-name: string
  --endpoint-type: string
  --eps-prevention: oneof<nothing, bool>
  --eps-prevention-success: string
  --file: string
  --incident-name: string
  --last-seen: string # format: date-time
  --last-seen-gte: string # format: date
  --last-seen-lte: string # format: date
  --notified-cardinalis: oneof<nothing, bool>
  --notified-llama: oneof<nothing, bool>
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --path: string
  --per-page: int # Number of results to return per page.
  --remediation-status: string
  --scan-group-name: string
  --search: string # A search term.
  --severity: string
  --solved: oneof<nothing, bool>
  --status: string
  --tenant: int
  --type: string
  --uniqueness: string
  --updated-at: string # format: date-time
  --user: int
  --user-name: string
  --username: string
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($idrs | is-empty) { error make --unspanned { msg: "path parameter 'idrs' must be non-empty" } }
  let qp = [(serialize-qp "acknowledged" $acknowledged "scalar") (serialize-qp "alert_domain" $alert_domain "scalar") (serialize-qp "alert_ip" $alert_ip "scalar") (serialize-qp "alert_type" $alert_type "scalar") (serialize-qp "alert_url" $alert_url "scalar") (serialize-qp "command_line" $command_line "scalar") (serialize-qp "created_at" $created_at "scalar") (serialize-qp "customer" $customer "scalar") (serialize-qp "date_changed" $date_changed "scalar") (serialize-qp "date_in" $date_in "scalar") (serialize-qp "date_in__gte" $date_in_gte "scalar") (serialize-qp "date_in__lte" $date_in_lte "scalar") (serialize-qp "endpoint" $endpoint "scalar") (serialize-qp "endpoint_name" $endpoint_name "scalar") (serialize-qp "endpoint_type" $endpoint_type "scalar") (serialize-qp "eps_prevention" $eps_prevention "scalar") (serialize-qp "eps_prevention_success" $eps_prevention_success "scalar") (serialize-qp "file" $file "scalar") (serialize-qp "incident_name" $incident_name "scalar") (serialize-qp "last_seen" $last_seen "scalar") (serialize-qp "last_seen__gte" $last_seen_gte "scalar") (serialize-qp "last_seen__lte" $last_seen_lte "scalar") (serialize-qp "notified_cardinalis" $notified_cardinalis "scalar") (serialize-qp "notified_llama" $notified_llama "scalar") (serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "path" $path "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "remediation_status" $remediation_status "scalar") (serialize-qp "scan_group_name" $scan_group_name "scalar") (serialize-qp "search" $search "scalar") (serialize-qp "severity" $severity "scalar") (serialize-qp "solved" $solved "scalar") (serialize-qp "status" $status "scalar") (serialize-qp "tenant" $tenant "scalar") (serialize-qp "type" $type "scalar") (serialize-qp "uniqueness" $uniqueness "scalar") (serialize-qp "updated_at" $updated_at "scalar") (serialize-qp "user" $user "scalar") (serialize-qp "user_name" $user_name "scalar") (serialize-qp "username" $username "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({idrs: (encode-path-segment $idrs)} | format pattern "/avcfg/cynet/alerts/list/scangroup/{idrs}/") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# GET /avcfg/cynet/alerts/summary/{idrs}/
#
# operationId: avcfg_cynet_alerts_summary_list
export def "avcfg-cynet-alerts-summary list" [
  idrs: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --acknowledged: oneof<nothing, bool>
  --alert-domain: string
  --alert-ip: string
  --alert-type: string
  --alert-url: string
  --command-line: string
  --created-at: string # format: date-time
  --customer: int
  --date-changed: string
  --date-in: string
  --date-in-gte: string # format: date
  --date-in-lte: string # format: date
  --endpoint: int
  --endpoint-name: string
  --endpoint-type: string
  --eps-prevention: oneof<nothing, bool>
  --eps-prevention-success: string
  --file: string
  --incident-name: string
  --last-seen: string # format: date-time
  --last-seen-gte: string # format: date
  --last-seen-lte: string # format: date
  --notified-cardinalis: oneof<nothing, bool>
  --notified-llama: oneof<nothing, bool>
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --path: string
  --per-page: int # Number of results to return per page.
  --remediation-status: string
  --scan-group-name: string
  --search: string # A search term.
  --severity: string
  --solved: oneof<nothing, bool>
  --status: string
  --tenant: int
  --type: string
  --uniqueness: string
  --updated-at: string # format: date-time
  --user: int
  --user-name: string
  --username: string
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($idrs | is-empty) { error make --unspanned { msg: "path parameter 'idrs' must be non-empty" } }
  let qp = [(serialize-qp "acknowledged" $acknowledged "scalar") (serialize-qp "alert_domain" $alert_domain "scalar") (serialize-qp "alert_ip" $alert_ip "scalar") (serialize-qp "alert_type" $alert_type "scalar") (serialize-qp "alert_url" $alert_url "scalar") (serialize-qp "command_line" $command_line "scalar") (serialize-qp "created_at" $created_at "scalar") (serialize-qp "customer" $customer "scalar") (serialize-qp "date_changed" $date_changed "scalar") (serialize-qp "date_in" $date_in "scalar") (serialize-qp "date_in__gte" $date_in_gte "scalar") (serialize-qp "date_in__lte" $date_in_lte "scalar") (serialize-qp "endpoint" $endpoint "scalar") (serialize-qp "endpoint_name" $endpoint_name "scalar") (serialize-qp "endpoint_type" $endpoint_type "scalar") (serialize-qp "eps_prevention" $eps_prevention "scalar") (serialize-qp "eps_prevention_success" $eps_prevention_success "scalar") (serialize-qp "file" $file "scalar") (serialize-qp "incident_name" $incident_name "scalar") (serialize-qp "last_seen" $last_seen "scalar") (serialize-qp "last_seen__gte" $last_seen_gte "scalar") (serialize-qp "last_seen__lte" $last_seen_lte "scalar") (serialize-qp "notified_cardinalis" $notified_cardinalis "scalar") (serialize-qp "notified_llama" $notified_llama "scalar") (serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "path" $path "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "remediation_status" $remediation_status "scalar") (serialize-qp "scan_group_name" $scan_group_name "scalar") (serialize-qp "search" $search "scalar") (serialize-qp "severity" $severity "scalar") (serialize-qp "solved" $solved "scalar") (serialize-qp "status" $status "scalar") (serialize-qp "tenant" $tenant "scalar") (serialize-qp "type" $type "scalar") (serialize-qp "uniqueness" $uniqueness "scalar") (serialize-qp "updated_at" $updated_at "scalar") (serialize-qp "user" $user "scalar") (serialize-qp "user_name" $user_name "scalar") (serialize-qp "username" $username "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({idrs: (encode-path-segment $idrs)} | format pattern "/avcfg/cynet/alerts/summary/{idrs}/") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# POST /avcfg/cynet/carpet/active_idrs/
#
# operationId: avcfg_cynet_carpet_active_idrs_create
export def "avcfg-cynet-carpet-active-idrs create" [
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
  let full_url = (build-url $base "/avcfg/cynet/carpet/active_idrs/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# GET /avcfg/cynet/carpet/endpoints/{idrs}/
#
# operationId: avcfg_cynet_carpet_endpoints_list
export def "avcfg-cynet-carpet-endpoints list" [
  idrs: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --page: int # A page number within the paginated result set.
  --per-page: int # Number of results to return per page.
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($idrs | is-empty) { error make --unspanned { msg: "path parameter 'idrs' must be non-empty" } }
  let qp = [(serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({idrs: (encode-path-segment $idrs)} | format pattern "/avcfg/cynet/carpet/endpoints/{idrs}/") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# GET /avcfg/cynet/endpoint/ci/{atlantis_id}/
#
# operationId: avcfg_cynet_endpoint_ci_retrieve
export def "avcfg-cynet-endpoint-ci get" [
  atlantis_id: int
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> record<id: int, type: string, hostname: string, last_seen: string, health_status: string, active_av: string, person_name: string, via_login: string, additional_info: string, atlantis_id: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($atlantis_id | is-empty) { error make --unspanned { msg: "path parameter 'atlantis_id' must be non-empty" } }
  let full_url = (build-url $base ({atlantis_id: (encode-path-segment $atlantis_id)} | format pattern "/avcfg/cynet/endpoint/ci/{atlantis_id}/"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# GET /avcfg/cynet/endpoints/{idrs}/
#
# operationId: avcfg_cynet_endpoints_list
export def "avcfg-cynet-endpoints list" [
  idrs: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --cynet-info-last-seen-at-gte: string # format: date
  --cynet-info-last-seen-at-lte: string # format: date
  --hostname: string
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --per-page: int # Number of results to return per page.
  --scan-group: string
  --search: string # A search term.
  --type: string
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($idrs | is-empty) { error make --unspanned { msg: "path parameter 'idrs' must be non-empty" } }
  let qp = [(serialize-qp "cynet_info__last_seen_at__gte" $cynet_info_last_seen_at_gte "scalar") (serialize-qp "cynet_info__last_seen_at__lte" $cynet_info_last_seen_at_lte "scalar") (serialize-qp "hostname" $hostname "scalar") (serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "scan_group" $scan_group "scalar") (serialize-qp "search" $search "scalar") (serialize-qp "type" $type "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({idrs: (encode-path-segment $idrs)} | format pattern "/avcfg/cynet/endpoints/{idrs}/") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# GET /avcfg/cynet/endpoints/alerts/summary/{idrs}/
#
# operationId: avcfg_cynet_endpoints_alerts_summary_list
export def "avcfg-cynet-endpoints-alerts-summary list" [
  idrs: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --acknowledged: oneof<nothing, bool>
  --alert-domain: string
  --alert-ip: string
  --alert-type: string
  --alert-url: string
  --command-line: string
  --created-at: string # format: date-time
  --customer: int
  --date-changed: string
  --date-in: string
  --date-in-gte: string # format: date
  --date-in-lte: string # format: date
  --endpoint: int
  --endpoint-name: string
  --endpoint-type: string
  --eps-prevention: oneof<nothing, bool>
  --eps-prevention-success: string
  --file: string
  --incident-name: string
  --last-seen: string # format: date-time
  --last-seen-gte: string # format: date
  --last-seen-lte: string # format: date
  --notified-cardinalis: oneof<nothing, bool>
  --notified-llama: oneof<nothing, bool>
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --path: string
  --per-page: int # Number of results to return per page.
  --remediation-status: string
  --scan-group-name: string
  --search: string # A search term.
  --severity: string
  --solved: oneof<nothing, bool>
  --status: string
  --tenant: int
  --type: string
  --uniqueness: string
  --updated-at: string # format: date-time
  --user: int
  --user-name: string
  --username: string
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($idrs | is-empty) { error make --unspanned { msg: "path parameter 'idrs' must be non-empty" } }
  let qp = [(serialize-qp "acknowledged" $acknowledged "scalar") (serialize-qp "alert_domain" $alert_domain "scalar") (serialize-qp "alert_ip" $alert_ip "scalar") (serialize-qp "alert_type" $alert_type "scalar") (serialize-qp "alert_url" $alert_url "scalar") (serialize-qp "command_line" $command_line "scalar") (serialize-qp "created_at" $created_at "scalar") (serialize-qp "customer" $customer "scalar") (serialize-qp "date_changed" $date_changed "scalar") (serialize-qp "date_in" $date_in "scalar") (serialize-qp "date_in__gte" $date_in_gte "scalar") (serialize-qp "date_in__lte" $date_in_lte "scalar") (serialize-qp "endpoint" $endpoint "scalar") (serialize-qp "endpoint_name" $endpoint_name "scalar") (serialize-qp "endpoint_type" $endpoint_type "scalar") (serialize-qp "eps_prevention" $eps_prevention "scalar") (serialize-qp "eps_prevention_success" $eps_prevention_success "scalar") (serialize-qp "file" $file "scalar") (serialize-qp "incident_name" $incident_name "scalar") (serialize-qp "last_seen" $last_seen "scalar") (serialize-qp "last_seen__gte" $last_seen_gte "scalar") (serialize-qp "last_seen__lte" $last_seen_lte "scalar") (serialize-qp "notified_cardinalis" $notified_cardinalis "scalar") (serialize-qp "notified_llama" $notified_llama "scalar") (serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "path" $path "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "remediation_status" $remediation_status "scalar") (serialize-qp "scan_group_name" $scan_group_name "scalar") (serialize-qp "search" $search "scalar") (serialize-qp "severity" $severity "scalar") (serialize-qp "solved" $solved "scalar") (serialize-qp "status" $status "scalar") (serialize-qp "tenant" $tenant "scalar") (serialize-qp "type" $type "scalar") (serialize-qp "uniqueness" $uniqueness "scalar") (serialize-qp "updated_at" $updated_at "scalar") (serialize-qp "user" $user "scalar") (serialize-qp "user_name" $user_name "scalar") (serialize-qp "username" $username "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({idrs: (encode-path-segment $idrs)} | format pattern "/avcfg/cynet/endpoints/alerts/summary/{idrs}/") $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# GET /avcfg/cynet/tenant/{id}/
#
# operationId: avcfg_cynet_tenant_retrieve
export def "avcfg-cynet-tenant get" [
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
]: nothing -> record<id: int, name: string, enable: bool, note: string, alert: bool, discovery: bool, cynet_info: record<id: int, tenant_id: string, client_id: string, shared: bool, source: string, is_older_item_monitored: bool>, customer: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($id | is-empty) { error make --unspanned { msg: "path parameter 'id' must be non-empty" } }
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/avcfg/cynet/tenant/{id}/"))
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json"
}

# PUT /avcfg/cynet/tenant/{id}/
#
# operationId: avcfg_cynet_tenant_update
# --cynet_info shape: {tenant_id?: string, client_id: string, shared?: bool, source?: string, is_older_item_monitored?: bool}
export def "avcfg-cynet-tenant update-by-id" [
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
  --name: string # nullable
  --enable: oneof<nothing, bool> # nullable
  --note: string # nullable
  --alert: oneof<nothing, bool> # nullable
  --discovery: oneof<nothing, bool> # nullable
  cynet_info: record # shape: {tenant_id?: string, client_id: string, shared?: bool, source?: string, is_older_item_monitored?: bool}
]: any -> record<id: int, name: string, enable: bool, note: string, alert: bool, discovery: bool, cynet_info: record<id: int, tenant_id: string, client_id: string, shared: bool, source: string, is_older_item_monitored: bool>, customer: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($id | is-empty) { error make --unspanned { msg: "path parameter 'id' must be non-empty" } }
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/avcfg/cynet/tenant/{id}/"))
  let req_body = {"name": $name, "enable": $enable, "note": $note, "alert": $alert, "discovery": $discovery, "cynet_info": $cynet_info} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# PATCH /avcfg/cynet/tenant/{id}/
#
# operationId: avcfg_cynet_tenant_partial_update
# --cynet_info shape: {tenant_id?: string, client_id: string, shared?: bool, source?: string, is_older_item_monitored?: bool}
export def "avcfg-cynet-tenant update-by-id-1" [
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
  --name: string # nullable
  --enable: oneof<nothing, bool> # nullable
  --note: string # nullable
  --alert: oneof<nothing, bool> # nullable
  --discovery: oneof<nothing, bool> # nullable
  --cynet-info: record # shape: {tenant_id?: string, client_id: string, shared?: bool, source?: string, is_older_item_monitored?: bool}
]: any -> record<id: int, name: string, enable: bool, note: string, alert: bool, discovery: bool, cynet_info: record<id: int, tenant_id: string, client_id: string, shared: bool, source: string, is_older_item_monitored: bool>, customer: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  if ($id | is-empty) { error make --unspanned { msg: "path parameter 'id' must be non-empty" } }
  let full_url = (build-url $base ({id: (encode-path-segment $id)} | format pattern "/avcfg/cynet/tenant/{id}/"))
  let req_body = {"name": $name, "enable": $enable, "note": $note, "alert": $alert, "discovery": $discovery, "cynet_info": $cynet_info} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}

# POST /avcfg/cynet/tenant/create/
#
# operationId: avcfg_cynet_tenant_create_create
# --cynet_info shape: {tenant_id?: string, client_id: string, shared?: bool, source?: string, is_older_item_monitored?: bool}
export def "avcfg-cynet-tenant-create create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx
  --dry-run(-n) # Return the request that would be sent without executing it
  --name: string # nullable
  --enable: oneof<nothing, bool> # nullable
  --note: string # nullable
  --alert: oneof<nothing, bool> # nullable
  --discovery: oneof<nothing, bool> # nullable
  cynet_info: record # shape: {tenant_id?: string, client_id: string, shared?: bool, source?: string, is_older_item_monitored?: bool}
]: any -> record<id: int, name: string, enable: bool, note: string, alert: bool, discovery: bool, cynet_info: record<id: int, tenant_id: string, client_id: string, shared: bool, source: string, is_older_item_monitored: bool>, customer: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/avcfg/cynet/tenant/create/")
  let req_body = {"name": $name, "enable": $enable, "note": $note, "alert": $alert, "discovery": $discovery, "cynet_info": $cynet_info} | compact
  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full "application/json" $req_body
}
