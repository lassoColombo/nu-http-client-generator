# Auto-generated client for anacleto v0.0.0
# Source: <spec>
# Auth: --token flag or $env.ANACLETO_TOKEN

const BASE_URL = "http://127.0.0.1:8000"
const DEFAULT_AUTH = "jwt"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o ANACLETO_TOKEN | default "" }
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
def base-url-completer [] { ["http://127.0.0.1:8000"] }
def auth-scheme-completer [] { ["jwt" "bearer" "static"] }

# Completers for enum parameters
def type-completer [] { ["CUSTOM" "HOSTNAME"] }
def type-completer-1 [] { ["CI" "CUSTOM" "HOSTNAME" "NETWORK"] }
def creation-comment-completer [] { ["Risk accepted" "Risk transferred" "Under decommissioning"] }


# Get active IDRS list
#
# POST /api/carpet/v1/active_idrs/
# operationId: api_carpet_v1_active_idrs_create
export def "carpet-active-idrs create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/carpet/v1/active_idrs/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get asset list for customer
#
# GET /api/carpet/v1/asset_list/idrs/{IDRS}/
# operationId: api_carpet_v1_asset_list_idrs_list
export def "carpet-asset-list-idrs list" [
  IDRS: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --per-page: int # Number of results to return per page.
  --search: string # A search term.
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "search" $search "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/carpet/v1/asset_list/idrs/($IDRS)/" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get host vulnerabilities for customer
#
# GET /api/carpet/v1/host/idrs/{IDRS}/
# operationId: api_carpet_v1_host_idrs_retrieve
export def "carpet-host-idrs get" [
  IDRS: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/carpet/v1/host/idrs/($IDRS)/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Return customer api key
#
# GET /api/delivery/v1/apikeys/idrs/{IDRS}/
# operationId: api_delivery_v1_apikeys_idrs_retrieve
export def "delivery-apikeys-idrs get" [
  IDRS: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/delivery/v1/apikeys/idrs/($IDRS)/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Asset list
#
# GET /api/delivery/v1/asset/
# operationId: api_delivery_v1_asset_list
export def "delivery-asset list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --address: string
  --idrs: string # IDRS
  --is-active: string@bool-completer
  --is-public: string@bool-completer
  --is-scannable: string@bool-completer
  --name: string
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --per-page: int # Number of results to return per page.
  --scanner-name: string
  --search: string # A search term.
  --tag: string # Tag
  --type: list # * `CI` - CI * `NETWORK` - NETWORK * `CUSTOM` - CUSTOM * `DEFAULT` - DEFAULT * `HOSTNAME` - HOSTNAME
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "address" $address "scalar") (serialize-qp "idrs" $idrs "scalar") (serialize-qp "is_active" $is_active "scalar") (serialize-qp "is_public" $is_public "scalar") (serialize-qp "is_scannable" $is_scannable "scalar") (serialize-qp "name" $name "scalar") (serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "scanner_name" $scanner_name "scalar") (serialize-qp "search" $search "scalar") (serialize-qp "tag" $tag "scalar") (serialize-qp "type" $type "multi")] | flatten | str join "&"
  let full_url = (build-url $base "/api/delivery/v1/asset/" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Add new asset tag
#
# POST /api/delivery/v1/asset-tag/create/
# operationId: api_delivery_v1_asset_tag_create_create
export def "delivery-asset-tag-create create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  idrs: string
  name: string
]: any -> record<idrs: string, name: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/delivery/v1/asset-tag/create/")
  let body = {idrs: $idrs, name: $name} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Delete asset tag
#
# DELETE /api/delivery/v1/asset-tag/delete/{id}/
# operationId: api_delivery_v1_asset_tag_delete_destroy
export def "delivery-asset-tag-delete delete" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/delivery/v1/asset-tag/delete/($id)/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Edit asset tag
#
# PUT /api/delivery/v1/asset-tag/edit/{id}/
# operationId: api_delivery_v1_asset_tag_edit_update
export def "delivery-asset-tag-edit update" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  name: string
]: any -> record<name: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/delivery/v1/asset-tag/edit/($id)/")
  let body = {name: $name} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Get asset Tag for Customer
#
# GET /api/delivery/v1/asset-tag/idrs/{IDRS}/
# operationId: api_delivery_v1_asset_tag_idrs_list
export def "delivery-asset-tag-idrs list" [
  IDRS: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --per-page: int # Number of results to return per page.
  --search: string # A search term.
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "search" $search "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/delivery/v1/asset-tag/idrs/($IDRS)/" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Add new asset
#
# POST /api/delivery/v1/asset/create/
# operationId: api_delivery_v1_asset_create_create
export def "delivery-asset-create create" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  idrs: string
  name: string
  --is-scannable: string@bool-completer
  scanner_id: int
  type: string@type-completer # * `HOSTNAME` - HOSTNAME * `CUSTOM` - CUSTOM
  address: list
  --tag-id: int # nullable
]: any -> record<id: int, idrs: string, name: string, is_scannable: bool, scanner_id: int, type: string, address: list<any>, tag_id: int> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/delivery/v1/asset/create/")
  let body = {idrs: $idrs, name: $name, is_scannable: $is_scannable, scanner_id: $scanner_id, type: $type, address: $address, tag_id: $tag_id} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Deactivate asset
#
# POST /api/delivery/v1/asset/deactivate/{id}/
# operationId: api_delivery_v1_asset_deactivate_create
export def "delivery-asset-deactivate create" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/delivery/v1/asset/deactivate/($id)/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Delete asset
#
# DELETE /api/delivery/v1/asset/delete/{id}/
# operationId: api_delivery_v1_asset_delete_destroy
export def "delivery-asset-delete delete" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/delivery/v1/asset/delete/($id)/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Get asset attribute
#
# GET /api/delivery/v1/asset/details/{id}/
# operationId: api_delivery_v1_asset_details_retrieve
export def "delivery-asset-details get" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
]: nothing -> record<id: int, idrs: string, name: string, is_scannable: bool, is_public: bool, location: string, atlantis_id: int, is_active: bool, type: string, address: list<any>, has_whitelist: string, whitelist: string, scanner_name: string, scanner_id: int, number_of_host: string, error: string, tag: string, tag_id: int> {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/delivery/v1/asset/details/($id)/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Edit asset attribute
#
# PUT /api/delivery/v1/asset/details/{id}/
# operationId: api_delivery_v1_asset_details_update
export def "delivery-asset-details update" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  name: string
  --is-scannable: string@bool-completer
  --atlantis-id: int # nullable
  --is-active: string@bool-completer
  type: string@type-completer-1 # * `HOSTNAME` - HOSTNAME * `CUSTOM` - CUSTOM * `CI` - CI * `NETWORK` - NETWORK
  address: list
  scanner_id: int
  --body-error: string # nullable
  --tag-id: int # nullable
]: any -> record<id: int, idrs: string, name: string, is_scannable: bool, is_public: bool, location: string, atlantis_id: int, is_active: bool, type: string, address: list<any>, has_whitelist: string, whitelist: string, scanner_name: string, scanner_id: int, number_of_host: string, error: string, tag: string, tag_id: int> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/delivery/v1/asset/details/($id)/")
  let body = {name: $name, is_scannable: $is_scannable, atlantis_id: $atlantis_id, is_active: $is_active, type: $type, address: $address, scanner_id: $scanner_id, error: $body_error, tag_id: $tag_id} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# Get asset for Customer
#
# GET /api/delivery/v1/asset/idrs/{IDRS}/
# operationId: api_delivery_v1_asset_idrs_list
export def "delivery-asset-idrs list" [
  IDRS: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --ordering: string # Which field to use when ordering the results.
  --page: int # A page number within the paginated result set.
  --per-page: int # Number of results to return per page.
  --search: string # A search term.
]: nothing -> any {
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "ordering" $ordering "scalar") (serialize-qp "page" $page "scalar") (serialize-qp "per_page" $per_page "scalar") (serialize-qp "search" $search "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/delivery/v1/asset/idrs/($IDRS)/" $qp)
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# Add whitelist for the asset
#
# POST /api/delivery/v1/asset/whitelist/{id}/
# operationId: api_delivery_v1_asset_whitelist_create
export def "delivery-asset-whitelist create" [
  id: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  ips: list
  creation_comment: string@creation-comment-completer # * `Under decommissioning` - Under decommissioning * `Risk transferred` - Risk transferred * `Risk accepted` - Risk accepted
  --expiration-date: string # format: date
  --description: string
]: any -> record<id: int, ips: list<any>, creation_comment: string, expiration_date: string, description: string> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "jwt"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base $"/api/delivery/v1/asset/whitelist/($id)/")
  let body = {ips: $ips, creation_comment: $creation_comment, expiration_date: $expiration_date, description: $description} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}
