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
def base-url-completer [] { ["https://localhost"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def accept-completer [] { ["application/json" "application/vnd.kubernetes.protobuf" "application/yaml"] }
def accept-completer-1 [] { ["application/cbor" "application/json" "application/vnd.kubernetes.protobuf" "application/yaml"] }
def accept-completer-2 [] { ["application/cbor" "application/cbor-seq" "application/json" "application/json;stream=watch" "application/vnd.kubernetes.protobuf" "application/vnd.kubernetes.protobuf;stream=watch" "application/yaml"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "well-known-openid-configuration get" } } | get name | first)
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
# operationId: getServiceAccountIssuerOpenIDConfiguration
export def "well-known-openid-configuration get" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
]: nothing -> string {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/.well-known/openid-configuration/")
  let accept_val = "application/json"
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# get available API versions
#
# operationId: getCoreAPIVersions
export def "core get" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer # Response content type
]: nothing -> record<apiVersion: string, kind: string, serverAddressByClientCIDRs: table<clientCIDR: string, serverAddress: string>, versions: list<string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/")
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# get available resources
#
# operationId: getCoreV1APIResources
export def "core-v1 get" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
]: nothing -> record<apiVersion: string, groupVersion: string, kind: string, resources: table<categories: list, group: string, kind: string, name: string, namespaced: bool, shortNames: list, singularName: string, storageVersionHash: string, verbs: list, version: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let full_url = (build-url $base "/api/v1/")
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# list objects of kind ComponentStatus
#
# operationId: listCoreV1ComponentStatus
export def "componentstatuses listCoreV1ComponentStatus" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-2 # Response content type
  --allowWatchBookmarks: string@bool-completer
  --qp-continue: string
  --fieldSelector: string
  --labelSelector: string
  --limit: int
  --pretty: string
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
  --watch: string@bool-completer
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, conditions: list, kind: string, metadata: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allowWatchBookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/componentstatuses" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# read the specified ComponentStatus
#
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
  --accept: string@accept-completer-1 # Response content type
  --pretty: string
]: nothing -> record<apiVersion: string, conditions: table<error: string, message: string, status: string, type: string>, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "pretty" $pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/componentstatuses/($name)" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# list or watch objects of kind ConfigMap
#
# operationId: listCoreV1ConfigMapForAllNamespaces
export def "configmaps listCoreV1ConfigMapForAllNamespaces" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-2 # Response content type
  --allowWatchBookmarks: string@bool-completer
  --qp-continue: string
  --fieldSelector: string
  --labelSelector: string
  --limit: int
  --pretty: string
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
  --watch: string@bool-completer
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allowWatchBookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/configmaps" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# list or watch objects of kind Endpoints
#
# operationId: listCoreV1EndpointsForAllNamespaces
export def "endpoints listCoreV1EndpointsForAllNamespaces" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-2 # Response content type
  --allowWatchBookmarks: string@bool-completer
  --qp-continue: string
  --fieldSelector: string
  --labelSelector: string
  --limit: int
  --pretty: string
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
  --watch: string@bool-completer
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, kind: string, metadata: record, subsets: list>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allowWatchBookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/endpoints" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# list or watch objects of kind Event
#
# operationId: listCoreV1EventForAllNamespaces
export def "events listCoreV1EventForAllNamespaces" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-2 # Response content type
  --allowWatchBookmarks: string@bool-completer
  --qp-continue: string
  --fieldSelector: string
  --labelSelector: string
  --limit: int
  --pretty: string
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
  --watch: string@bool-completer
]: nothing -> record<apiVersion: string, items: table<action: string, apiVersion: string, count: int, eventTime: string, firstTimestamp: string, involvedObject: record, kind: string, lastTimestamp: string, message: string, metadata: record, reason: string, related: record, reportingComponent: string, reportingInstance: string, series: record, source: record, type: string>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allowWatchBookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/events" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# list or watch objects of kind LimitRange
#
# operationId: listCoreV1LimitRangeForAllNamespaces
export def "limitranges listCoreV1LimitRangeForAllNamespaces" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-2 # Response content type
  --allowWatchBookmarks: string@bool-completer
  --qp-continue: string
  --fieldSelector: string
  --labelSelector: string
  --limit: int
  --pretty: string
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
  --watch: string@bool-completer
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, kind: string, metadata: record, spec: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allowWatchBookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "pretty" $pretty "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/limitranges" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# list or watch objects of kind Namespace
#
# operationId: listCoreV1Namespace
export def "namespaces listCoreV1Namespace" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-2 # Response content type
  --allowWatchBookmarks: string@bool-completer
  --qp-continue: string
  --fieldSelector: string
  --labelSelector: string
  --limit: int
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
  --watch: string@bool-completer
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, kind: string, metadata: record, spec: record, status: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allowWatchBookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/namespaces" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# create a Namespace
#
# operationId: createCoreV1Namespace
export def "namespaces createCoreV1Namespace" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --fieldManager: string
  --fieldValidation: string
  --apiVersion: string
  --kind: string
  --metadata: record
  --spec: record
  --status: record
]: any -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, spec: record<finalizers: list<string>>, status: record<conditions: list<record>, phase: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldManager" $fieldManager "scalar") (serialize-qp "fieldValidation" $fieldValidation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base "/api/v1/namespaces" $qp)
  let body = {apiVersion: $apiVersion, kind: $kind, metadata: $metadata, spec: $spec, status: $status} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# create a Binding
#
# operationId: createCoreV1NamespacedBinding
export def "namespaces-bindings createCoreV1NamespacedBinding" [
  namespace: string
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --fieldManager: string
  --fieldValidation: string
  --pretty: string
  --apiVersion: string
  --kind: string
  --metadata: record
  target: record
]: any -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, target: record<apiVersion: string, fieldPath: string, kind: string, name: string, namespace: string, resourceVersion: string, uid: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldManager" $fieldManager "scalar") (serialize-qp "fieldValidation" $fieldValidation "scalar") (serialize-qp "pretty" $pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/bindings" $qp)
  let body = {apiVersion: $apiVersion, kind: $kind, metadata: $metadata, target: $target} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# delete collection of ConfigMap
#
# operationId: deleteCoreV1CollectionNamespacedConfigMap
export def "namespaces-configmaps delete-by-namespace" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --qp-continue: string
  --dryRun: string
  --fieldSelector: string
  --gracePeriodSeconds: int
  --ignoreStoreReadErrorWithClusterBreakingPotential: string@bool-completer
  --labelSelector: string
  --limit: int
  --orphanDependents: string@bool-completer
  --propagationPolicy: string
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
]: nothing -> record<apiVersion: string, code: int, details: record<causes: list<record>, group: string, kind: string, name: string, retryAfterSeconds: int, uid: string>, kind: string, message: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>, reason: string, status: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "continue" $qp_continue "scalar") (serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "gracePeriodSeconds" $gracePeriodSeconds "scalar") (serialize-qp "ignoreStoreReadErrorWithClusterBreakingPotential" $ignoreStoreReadErrorWithClusterBreakingPotential "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "orphanDependents" $orphanDependents "scalar") (serialize-qp "propagationPolicy" $propagationPolicy "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/configmaps" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# list or watch objects of kind ConfigMap
#
# operationId: listCoreV1NamespacedConfigMap
export def "namespaces-configmaps listCoreV1NamespacedConfigMap" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-2 # Response content type
  --allowWatchBookmarks: string@bool-completer
  --qp-continue: string
  --fieldSelector: string
  --labelSelector: string
  --limit: int
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
  --watch: string@bool-completer
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allowWatchBookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/configmaps" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# create a ConfigMap
#
# operationId: createCoreV1NamespacedConfigMap
export def "namespaces-configmaps createCoreV1NamespacedConfigMap" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --fieldManager: string
  --fieldValidation: string
  --apiVersion: string
  --binaryData: record
  --data: record
  --immutable: string@bool-completer
  --kind: string
  --metadata: record
]: any -> record<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldManager" $fieldManager "scalar") (serialize-qp "fieldValidation" $fieldValidation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/configmaps" $qp)
  let body = {apiVersion: $apiVersion, binaryData: $binaryData, data: $data, immutable: $immutable, kind: $kind, metadata: $metadata} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# delete a ConfigMap
#
# operationId: deleteCoreV1NamespacedConfigMap
export def "namespaces-configmaps delete-by-name-namespace" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --gracePeriodSeconds: int
  --ignoreStoreReadErrorWithClusterBreakingPotential: string@bool-completer
  --orphanDependents: string@bool-completer
  --propagationPolicy: string
]: nothing -> record<apiVersion: string, code: int, details: record<causes: list<record>, group: string, kind: string, name: string, retryAfterSeconds: int, uid: string>, kind: string, message: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>, reason: string, status: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "gracePeriodSeconds" $gracePeriodSeconds "scalar") (serialize-qp "ignoreStoreReadErrorWithClusterBreakingPotential" $ignoreStoreReadErrorWithClusterBreakingPotential "scalar") (serialize-qp "orphanDependents" $orphanDependents "scalar") (serialize-qp "propagationPolicy" $propagationPolicy "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/configmaps/($name)" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# read the specified ConfigMap
#
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
  --accept: string@accept-completer-1 # Response content type
  --pretty: string
]: nothing -> record<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "pretty" $pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/configmaps/($name)" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# partially update the specified ConfigMap
#
# operationId: patchCoreV1NamespacedConfigMap
export def "namespaces-configmaps patch" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --fieldManager: string
  --fieldValidation: string
  --force: string@bool-completer
]: nothing -> record<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldManager" $fieldManager "scalar") (serialize-qp "fieldValidation" $fieldValidation "scalar") (serialize-qp "force" $force "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/configmaps/($name)" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# replace the specified ConfigMap
#
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
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --fieldManager: string
  --fieldValidation: string
  --apiVersion: string
  --binaryData: record
  --data: record
  --immutable: string@bool-completer
  --kind: string
  --metadata: record
]: any -> record<apiVersion: string, binaryData: record, data: record, immutable: bool, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldManager" $fieldManager "scalar") (serialize-qp "fieldValidation" $fieldValidation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/configmaps/($name)" $qp)
  let body = {apiVersion: $apiVersion, binaryData: $binaryData, data: $data, immutable: $immutable, kind: $kind, metadata: $metadata} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# delete collection of Endpoints
#
# operationId: deleteCoreV1CollectionNamespacedEndpoints
export def "namespaces-endpoints delete-by-namespace" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --qp-continue: string
  --dryRun: string
  --fieldSelector: string
  --gracePeriodSeconds: int
  --ignoreStoreReadErrorWithClusterBreakingPotential: string@bool-completer
  --labelSelector: string
  --limit: int
  --orphanDependents: string@bool-completer
  --propagationPolicy: string
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
]: nothing -> record<apiVersion: string, code: int, details: record<causes: list<record>, group: string, kind: string, name: string, retryAfterSeconds: int, uid: string>, kind: string, message: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>, reason: string, status: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "continue" $qp_continue "scalar") (serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "gracePeriodSeconds" $gracePeriodSeconds "scalar") (serialize-qp "ignoreStoreReadErrorWithClusterBreakingPotential" $ignoreStoreReadErrorWithClusterBreakingPotential "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "orphanDependents" $orphanDependents "scalar") (serialize-qp "propagationPolicy" $propagationPolicy "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/endpoints" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# list or watch objects of kind Endpoints
#
# operationId: listCoreV1NamespacedEndpoints
export def "namespaces-endpoints listCoreV1NamespacedEndpoints" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-2 # Response content type
  --allowWatchBookmarks: string@bool-completer
  --qp-continue: string
  --fieldSelector: string
  --labelSelector: string
  --limit: int
  --resourceVersion: string
  --resourceVersionMatch: string
  --sendInitialEvents: string@bool-completer
  --shardSelector: string
  --timeoutSeconds: int
  --watch: string@bool-completer
]: nothing -> record<apiVersion: string, items: table<apiVersion: string, kind: string, metadata: record, subsets: list>, kind: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "allowWatchBookmarks" $allowWatchBookmarks "scalar") (serialize-qp "continue" $qp_continue "scalar") (serialize-qp "fieldSelector" $fieldSelector "scalar") (serialize-qp "labelSelector" $labelSelector "scalar") (serialize-qp "limit" $limit "scalar") (serialize-qp "resourceVersion" $resourceVersion "scalar") (serialize-qp "resourceVersionMatch" $resourceVersionMatch "scalar") (serialize-qp "sendInitialEvents" $sendInitialEvents "scalar") (serialize-qp "shardSelector" $shardSelector "scalar") (serialize-qp "timeoutSeconds" $timeoutSeconds "scalar") (serialize-qp "watch" $watch "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/endpoints" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# create Endpoints
#
# operationId: createCoreV1NamespacedEndpoints
export def "namespaces-endpoints createCoreV1NamespacedEndpoints" [
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --fieldManager: string
  --fieldValidation: string
  --apiVersion: string
  --kind: string
  --metadata: record
  --subsets: list
]: any -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, subsets: table<addresses: list, notReadyAddresses: list, ports: list>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldManager" $fieldManager "scalar") (serialize-qp "fieldValidation" $fieldValidation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/endpoints" $qp)
  let body = {apiVersion: $apiVersion, kind: $kind, metadata: $metadata, subsets: $subsets} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "post" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}

# delete Endpoints
#
# operationId: deleteCoreV1NamespacedEndpoints
export def "namespaces-endpoints delete-by-name-namespace" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --gracePeriodSeconds: int
  --ignoreStoreReadErrorWithClusterBreakingPotential: string@bool-completer
  --orphanDependents: string@bool-completer
  --propagationPolicy: string
]: nothing -> record<apiVersion: string, code: int, details: record<causes: list<record>, group: string, kind: string, name: string, retryAfterSeconds: int, uid: string>, kind: string, message: string, metadata: record<continue: string, remainingItemCount: int, resourceVersion: string, selfLink: string, shardInfo: record<selector: string>>, reason: string, status: string> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "gracePeriodSeconds" $gracePeriodSeconds "scalar") (serialize-qp "ignoreStoreReadErrorWithClusterBreakingPotential" $ignoreStoreReadErrorWithClusterBreakingPotential "scalar") (serialize-qp "orphanDependents" $orphanDependents "scalar") (serialize-qp "propagationPolicy" $propagationPolicy "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/endpoints/($name)" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "delete" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# read the specified Endpoints
#
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
  --accept: string@accept-completer-1 # Response content type
  --pretty: string
]: nothing -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, subsets: table<addresses: list, notReadyAddresses: list, ports: list>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "pretty" $pretty "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/endpoints/($name)" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "get" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# partially update the specified Endpoints
#
# operationId: patchCoreV1NamespacedEndpoints
export def "namespaces-endpoints patch" [
  name: string
  namespace: any
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --fieldManager: string
  --fieldValidation: string
  --force: string@bool-completer
]: nothing -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, subsets: table<addresses: list, notReadyAddresses: list, ports: list>> {
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldManager" $fieldManager "scalar") (serialize-qp "fieldValidation" $fieldValidation "scalar") (serialize-qp "force" $force "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/endpoints/($name)" $qp)
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "patch" $full_url $auth $insecure $raw $max_time $allow_errors "application/json"
}

# replace the specified Endpoints
#
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
  --accept: string@accept-completer-1 # Response content type
  --dryRun: string
  --fieldManager: string
  --fieldValidation: string
  --apiVersion: string
  --kind: string
  --metadata: record
  --subsets: list
]: any -> record<apiVersion: string, kind: string, metadata: record<annotations: record, creationTimestamp: string, deletionGracePeriodSeconds: int, deletionTimestamp: string, finalizers: list<string>, generateName: string, generation: int, labels: record, managedFields: list<record>, name: string, namespace: string, ownerReferences: list<record>, resourceVersion: string, selfLink: string, uid: string>, subsets: table<addresses: list, notReadyAddresses: list, ports: list>> {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default "bearer"))
  let base = ($base_url | default $BASE_URL)
  let qp = [(serialize-qp "dryRun" $dryRun "scalar") (serialize-qp "fieldManager" $fieldManager "scalar") (serialize-qp "fieldValidation" $fieldValidation "scalar")] | flatten | str join "&"
  let full_url = (build-url $base $"/api/v1/namespaces/($namespace)/endpoints/($name)" $qp)
  let body = {apiVersion: $apiVersion, kind: $kind, metadata: $metadata, subsets: $subsets} | compact
  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }
  let accept_val = ($accept | default "application/json")
  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))
  do-request "put" $full_url $auth $insecure $raw $max_time $allow_errors "application/json" $body
}
