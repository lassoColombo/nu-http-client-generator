# Auto-generated client for Kubernetes vunversioned
# Source: <spec>
# Auth: --token flag or $env.KUBERNETES_TOKEN

const BASE_URL = "https://localhost"
const DEFAULT_AUTH = "bearer"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o KUBERNETES_TOKEN | default "" }
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

def base-url-completer [] { ["https://localhost"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def accept-completer [] { ["application/json" "application/vnd.kubernetes.protobuf" "application/yaml"] }
def accept-completer-1 [] { ["application/cbor" "application/json" "application/vnd.kubernetes.protobuf" "application/yaml"] }
def accept-completer-2 [] { ["application/cbor" "application/cbor-seq" "application/json" "application/json;stream=watch" "application/vnd.kubernetes.protobuf" "application/vnd.kubernetes.protobuf;stream=watch" "application/yaml"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "dry-run" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "well-known-openid-configuration get-service-account-issuer-open-id-configuration" } } | get name | first)
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

# get service account issuer OpenID configuration, also known as the 'OIDC discovery doc'
#
# GET /.well-known/openid-configuration/
# operationId: getServiceAccountIssuerOpenIDConfiguration
export def "well-known-openid-configuration get-service-account-issuer-open-id-configuration" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
]: nothing -> string {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/.well-known/openid-configuration/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# get available API versions
#
# GET /api/
# operationId: getCoreAPIVersions
export def "core get-core-api-versions" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer # Response content type
]: nothing -> record<apiVersion: string, kind: string, serverAddressByClientCIDRs: table<clientCIDR: string, serverAddress: string>, versions: list<string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/")
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# get available resources
#
# GET /api/v1/
# operationId: getCoreV1APIResources
export def "core-v1 get-core-v1api-resources" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
]: nothing -> record<apiVersion: string, groupVersion: string, kind: string, resources: table<categories: list, group: string, kind: string, name: string, namespaced: bool, shortNames: list, singularName: string, storageVersionHash: string, verbs: list, version: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/v1/")
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# list objects of kind ComponentStatus
#
# GET /api/v1/componentstatuses
# operationId: listCoreV1ComponentStatus
export def "componentstatuses list-core-v1-component-status" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-2 # Response content type
  --allow-watch-bookmarks: oneof<nothing, bool>
  --qp-continue: string
  --field-selector: string
  --label-selector: string
  --limit: int
  --pretty: string
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
  --watch: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, conditions: list, kind: string, metadata: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allow_watch_bookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/componentstatuses" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# read the specified ComponentStatus
#
# GET /api/v1/componentstatuses/{name}
# operationId: readCoreV1ComponentStatus
export def "componentstatuses readCoreV1ComponentStatus" [
  name: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --pretty: string
]: nothing -> record<apiVersion: string, conditions: table<error: string, message: string, status: string, type: string>, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "pretty" $pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name} | format pattern "/api/v1/componentstatuses/{name}") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# list or watch objects of kind ConfigMap
#
# GET /api/v1/configmaps
# operationId: listCoreV1ConfigMapForAllNamespaces
export def "configmaps list-core-v1-config-map-for-all-namespaces" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-2 # Response content type
  --allow-watch-bookmarks: oneof<nothing, bool>
  --qp-continue: string
  --field-selector: string
  --label-selector: string
  --limit: int
  --pretty: string
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
  --watch: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allow_watch_bookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/configmaps" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# list or watch objects of kind Endpoints
#
# GET /api/v1/endpoints
# operationId: listCoreV1EndpointsForAllNamespaces
export def "endpoints list-core-v1-endpoints-for-all-namespaces" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-2 # Response content type
  --allow-watch-bookmarks: oneof<nothing, bool>
  --qp-continue: string
  --field-selector: string
  --label-selector: string
  --limit: int
  --pretty: string
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
  --watch: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, kind: string, metadata: record, subsets: list>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allow_watch_bookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/endpoints" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# list or watch objects of kind Event
#
# GET /api/v1/events
# operationId: listCoreV1EventForAllNamespaces
export def "events list-core-v1-event-for-all-namespaces" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-2 # Response content type
  --allow-watch-bookmarks: oneof<nothing, bool>
  --qp-continue: string
  --field-selector: string
  --label-selector: string
  --limit: int
  --pretty: string
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
  --watch: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, items: table<action: string, apiVersion: string, count: int, eventTime: string, firstTimestamp: string, involvedObject: record, kind: string, lastTimestamp: string, message: string, metadata: record, reason: string, related: record, reportingComponent: string, reportingInstance: string, series: record, source: record, type: string>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allow_watch_bookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/events" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# list or watch objects of kind LimitRange
#
# GET /api/v1/limitranges
# operationId: listCoreV1LimitRangeForAllNamespaces
export def "limitranges list-core-v1-limit-range-for-all-namespaces" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-2 # Response content type
  --allow-watch-bookmarks: oneof<nothing, bool>
  --qp-continue: string
  --field-selector: string
  --label-selector: string
  --limit: int
  --pretty: string
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
  --watch: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, kind: string, metadata: record, spec: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allow_watch_bookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/limitranges" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# list or watch objects of kind Namespace
#
# GET /api/v1/namespaces
# operationId: listCoreV1Namespace
export def "namespaces list-core-v1-namespace" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-2 # Response content type
  --allow-watch-bookmarks: oneof<nothing, bool>
  --qp-continue: string
  --field-selector: string
  --label-selector: string
  --limit: int
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
  --watch: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, kind: string, metadata: record, spec: record, status: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allow_watch_bookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/namespaces" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# create a Namespace
#
# POST /api/v1/namespaces
# operationId: createCoreV1Namespace
export def "namespaces create-core-v1-namespace" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --field-manager: string
  --field-validation: string
  --api-version: string
  --kind: string
  --metadata: record
  --spec: record
  --status: record
]: any -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, spec: record<finalizers: list<string>>, status: record<conditions: list<record>, phase: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldManager" $field_manager "scalar") (serialize-qp "fieldValidation" $field_validation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/namespaces" $qp)
  let body = {"apiVersion": $api_version, "kind": $kind, "metadata": $metadata, "spec": $spec, "status": $status} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# create a Binding
#
# POST /api/v1/namespaces/{namespace}/bindings
# operationId: createCoreV1NamespacedBinding
export def "namespaces-bindings create-core-v1-namespaced-binding" [
  namespace: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --field-manager: string
  --field-validation: string
  --pretty: string
  --api-version: string
  --kind: string
  --metadata: record
  target: record
]: any -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, target: record<apiVersion: string, fieldPath: string, kind: string, name: string, namespace: string, resourceVersion: string, uid: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldManager" $field_manager "scalar") (serialize-qp "fieldValidation" $field_validation "scalar") (serialize-qp "pretty" $pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/bindings") $qp)
  let body = {"apiVersion": $api_version, "kind": $kind, "metadata": $metadata, "target": $target} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# delete collection of ConfigMap
#
# DELETE /api/v1/namespaces/{namespace}/configmaps
# operationId: deleteCoreV1CollectionNamespacedConfigMap
export def "namespaces-configmaps delete-core-v1-collection-namespaced-config-map" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-continue: string
  --qp-dry-run: string
  --field-selector: string
  --grace-period-seconds: int
  --ignore-store-read-error-with-cluster-breaking-potential: oneof<nothing, bool>
  --label-selector: string
  --limit: int
  --orphan-dependents: oneof<nothing, bool>
  --propagation-policy: string
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
]: nothing -> record<apiVersion: string, code: int, details: record<causes: list<record>, group: string, kind: string, name: string, retryAfterSeconds: int, uid: string>, kind: string, message: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>, reason: string, status: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "continue" $qp_continue "scalar") (serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "gracePeriodSeconds" $grace_period_seconds "scalar") (serialize-qp "ignoreStoreReadErrorWithClusterBreakingPotential" $ignore_store_read_error_with_cluster_breaking_potential "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "orphanDependents" $orphan_dependents "scalar") (serialize-qp "propagationPolicy" $propagation_policy "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/configmaps") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# list or watch objects of kind ConfigMap
#
# GET /api/v1/namespaces/{namespace}/configmaps
# operationId: listCoreV1NamespacedConfigMap
export def "namespaces-configmaps list-core-v1-namespaced-config-map" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-2 # Response content type
  --allow-watch-bookmarks: oneof<nothing, bool>
  --qp-continue: string
  --field-selector: string
  --label-selector: string
  --limit: int
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
  --watch: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allow_watch_bookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/configmaps") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# create a ConfigMap
#
# POST /api/v1/namespaces/{namespace}/configmaps
# operationId: createCoreV1NamespacedConfigMap
export def "namespaces-configmaps create-core-v1-namespaced-config-map" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --field-manager: string
  --field-validation: string
  --api-version: string
  --binary-data: record
  --data: record
  --immutable: oneof<nothing, bool>
  --kind: string
  --metadata: record
]: any -> record<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldManager" $field_manager "scalar") (serialize-qp "fieldValidation" $field_validation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/configmaps") $qp)
  let body = {"apiVersion": $api_version, "binaryData": $binary_data, "data": $data, "immutable": $immutable, "kind": $kind, "metadata": $metadata} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# delete a ConfigMap
#
# DELETE /api/v1/namespaces/{namespace}/configmaps/{name}
# operationId: deleteCoreV1NamespacedConfigMap
export def "namespaces-configmaps delete-core-v1-namespaced-config-map" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --grace-period-seconds: int
  --ignore-store-read-error-with-cluster-breaking-potential: oneof<nothing, bool>
  --orphan-dependents: oneof<nothing, bool>
  --propagation-policy: string
]: nothing -> record<apiVersion: string, code: int, details: record<causes: list<record>, group: string, kind: string, name: string, retryAfterSeconds: int, uid: string>, kind: string, message: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>, reason: string, status: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "gracePeriodSeconds" $grace_period_seconds "scalar") (serialize-qp "ignoreStoreReadErrorWithClusterBreakingPotential" $ignore_store_read_error_with_cluster_breaking_potential "scalar") (serialize-qp "orphanDependents" $orphan_dependents "scalar") (serialize-qp "propagationPolicy" $propagation_policy "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name, namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/configmaps/{name}") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# read the specified ConfigMap
#
# GET /api/v1/namespaces/{namespace}/configmaps/{name}
# operationId: readCoreV1NamespacedConfigMap
export def "namespaces-configmaps readCoreV1NamespacedConfigMap" [
  name: string
  namespace: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --pretty: string
]: nothing -> record<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "pretty" $pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name, namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/configmaps/{name}") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# partially update the specified ConfigMap
#
# PATCH /api/v1/namespaces/{namespace}/configmaps/{name}
# operationId: patchCoreV1NamespacedConfigMap
export def "namespaces-configmaps update-core-v1-namespaced-config-map" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --field-manager: string
  --field-validation: string
  --force: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldManager" $field_manager "scalar") (serialize-qp "fieldValidation" $field_validation "scalar") (serialize-qp "force" $force "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name, namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/configmaps/{name}") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# replace the specified ConfigMap
#
# PUT /api/v1/namespaces/{namespace}/configmaps/{name}
# operationId: replaceCoreV1NamespacedConfigMap
export def "namespaces-configmaps replaceCoreV1NamespacedConfigMap" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --field-manager: string
  --field-validation: string
  --api-version: string
  --binary-data: record
  --data: record
  --immutable: oneof<nothing, bool>
  --kind: string
  --metadata: record
]: any -> record<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldManager" $field_manager "scalar") (serialize-qp "fieldValidation" $field_validation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name, namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/configmaps/{name}") $qp)
  let body = {"apiVersion": $api_version, "binaryData": $binary_data, "data": $data, "immutable": $immutable, "kind": $kind, "metadata": $metadata} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# delete collection of Endpoints
#
# DELETE /api/v1/namespaces/{namespace}/endpoints
# operationId: deleteCoreV1CollectionNamespacedEndpoints
export def "namespaces-endpoints delete-core-v1-collection-namespaced-endpoints" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-continue: string
  --qp-dry-run: string
  --field-selector: string
  --grace-period-seconds: int
  --ignore-store-read-error-with-cluster-breaking-potential: oneof<nothing, bool>
  --label-selector: string
  --limit: int
  --orphan-dependents: oneof<nothing, bool>
  --propagation-policy: string
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
]: nothing -> record<apiVersion: string, code: int, details: record<causes: list<record>, group: string, kind: string, name: string, retryAfterSeconds: int, uid: string>, kind: string, message: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>, reason: string, status: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "continue" $qp_continue "scalar") (serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "gracePeriodSeconds" $grace_period_seconds "scalar") (serialize-qp "ignoreStoreReadErrorWithClusterBreakingPotential" $ignore_store_read_error_with_cluster_breaking_potential "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "orphanDependents" $orphan_dependents "scalar") (serialize-qp "propagationPolicy" $propagation_policy "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/endpoints") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# list or watch objects of kind Endpoints
#
# GET /api/v1/namespaces/{namespace}/endpoints
# operationId: listCoreV1NamespacedEndpoints
export def "namespaces-endpoints list-core-v1-namespaced-endpoints" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-2 # Response content type
  --allow-watch-bookmarks: oneof<nothing, bool>
  --qp-continue: string
  --field-selector: string
  --label-selector: string
  --limit: int
  --resource-version: string
  --resource-version-match: string
  --send-initial-events: oneof<nothing, bool>
  --shard-selector: string
  --timeout-seconds: int
  --watch: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, kind: string, metadata: record, subsets: list>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allow_watch_bookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $field_selector "scalar") (serialize-qp "labelSelector" $label_selector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "resourceVersion" $resource_version "scalar") (serialize-qp "resourceVersionMatch" $resource_version_match "scalar") (serialize-qp "sendInitialEvents" $send_initial_events "scalar") (serialize-qp "shardSelector" $shard_selector "scalar") (serialize-qp "timeoutSeconds" $timeout_seconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/endpoints") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# create Endpoints
#
# POST /api/v1/namespaces/{namespace}/endpoints
# operationId: createCoreV1NamespacedEndpoints
export def "namespaces-endpoints create-core-v1-namespaced-endpoints" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --field-manager: string
  --field-validation: string
  --api-version: string
  --kind: string
  --metadata: record
  --subsets: list
]: any -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, subsets: table<addresses: list, notReadyAddresses: list, ports: list>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldManager" $field_manager "scalar") (serialize-qp "fieldValidation" $field_validation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/endpoints") $qp)
  let body = {"apiVersion": $api_version, "kind": $kind, "metadata": $metadata, "subsets": $subsets} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}

# delete Endpoints
#
# DELETE /api/v1/namespaces/{namespace}/endpoints/{name}
# operationId: deleteCoreV1NamespacedEndpoints
export def "namespaces-endpoints delete-core-v1-namespaced-endpoints" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --grace-period-seconds: int
  --ignore-store-read-error-with-cluster-breaking-potential: oneof<nothing, bool>
  --orphan-dependents: oneof<nothing, bool>
  --propagation-policy: string
]: nothing -> record<apiVersion: string, code: int, details: record<causes: list<record>, group: string, kind: string, name: string, retryAfterSeconds: int, uid: string>, kind: string, message: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>, reason: string, status: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "gracePeriodSeconds" $grace_period_seconds "scalar") (serialize-qp "ignoreStoreReadErrorWithClusterBreakingPotential" $ignore_store_read_error_with_cluster_breaking_potential "scalar") (serialize-qp "orphanDependents" $orphan_dependents "scalar") (serialize-qp "propagationPolicy" $propagation_policy "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name, namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/endpoints/{name}") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# read the specified Endpoints
#
# GET /api/v1/namespaces/{namespace}/endpoints/{name}
# operationId: readCoreV1NamespacedEndpoints
export def "namespaces-endpoints readCoreV1NamespacedEndpoints" [
  name: string
  namespace: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --pretty: string
]: nothing -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, subsets: table<addresses: list, notReadyAddresses: list, ports: list>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "pretty" $pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name, namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/endpoints/{name}") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# partially update the specified Endpoints
#
# PATCH /api/v1/namespaces/{namespace}/endpoints/{name}
# operationId: patchCoreV1NamespacedEndpoints
export def "namespaces-endpoints update-core-v1-namespaced-endpoints" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --field-manager: string
  --field-validation: string
  --force: oneof<nothing, bool>
]: nothing -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, subsets: table<addresses: list, notReadyAddresses: list, ports: list>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldManager" $field_manager "scalar") (serialize-qp "fieldValidation" $field_validation "scalar") (serialize-qp "force" $force "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name, namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/endpoints/{name}") $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json"
}

# replace the specified Endpoints
#
# PUT /api/v1/namespaces/{namespace}/endpoints/{name}
# operationId: replaceCoreV1NamespacedEndpoints
export def "namespaces-endpoints replaceCoreV1NamespacedEndpoints" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --accept: string@accept-completer-1 # Response content type
  --qp-dry-run: string
  --field-manager: string
  --field-validation: string
  --api-version: string
  --kind: string
  --metadata: record
  --subsets: list
]: any -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, subsets: table<addresses: list, notReadyAddresses: list, ports: list>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $qp_dry_run "scalar") (serialize-qp "fieldManager" $field_manager "scalar") (serialize-qp "fieldValidation" $field_validation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base ({name: $name, namespace: $namespace} | format pattern "/api/v1/namespaces/{namespace}/endpoints/{name}") $qp)
  let body = {"apiVersion": $api_version, "kind": $kind, "metadata": $metadata, "subsets": $subsets} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
}
