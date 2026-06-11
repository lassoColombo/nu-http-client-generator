# Auto-generated client for pokeapi v0.0.0
# Source: <spec>
# Auth: --token flag or $env.POKEAPI_TOKEN

const BASE_URL = "https://example.com/graphql"
const DEFAULT_AUTH = "bearer"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o POKEAPI_TOKEN | default "" }
  let scheme = ($auth_scheme | default "bearer")
  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }
  match $scheme {
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

# Unwrap a GraphQL response: extract data.{field} and surface errors
def unwrap-graphql [resp: any, field: string] {
  if ($resp | describe) == "string" { return $resp }
  let errors = ($resp.errors? | default [])
  if ($errors | length) > 0 {
    let msgs = ($errors | each {|e| $e.message? | default "unknown error" } | str join "; ")
    error make --unspanned { msg: $"GraphQL error: ($msgs)" }
  }
  $resp.data? | get -o $field | default $resp.data?
}

def bool-completer [] { ["'true'" "'false'"] }
def base-url-completer [] { ["https://example.com/graphql"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def distinct-on-completer [] { ["generation_id" "id" "is_main_series" "name"] }
def distinct-on-completer-1 [] { ["ability_id" "id" "version_group_id"] }
def distinct-on-completer-2 [] { ["ability_change_id" "effect" "id" "language_id"] }
def distinct-on-completer-3 [] { ["ability_id" "effect" "id" "language_id" "short_effect"] }
def distinct-on-completer-4 [] { ["ability_id" "flavor_text" "id" "language_id" "version_group_id"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "query pokemon-v2-ability" } } | get name | first)
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

# fetch data from the table: "pokemon_v2_ability"
#
# operationId: pokemon_v2_ability
# --where shape: {_and?: record, _not?: record, _or?: record, generation_id?: record, id?: record, is_main_series?: record, name?: record, pokemon_v2_abilitychanges?: record, pokemon_v2_abilitychanges_aggregate?: record, pokemon_v2_abilityeffecttexts?: record, pokemon_v2_abilityeffecttexts_aggregate?: record, pokemon_v2_abilityflavortexts?: record, pokemon_v2_abilityflavortexts_aggregate?: record, pokemon_v2_abilitynames?: record, pokemon_v2_abilitynames_aggregate?: record, pokemon_v2_generation?: record, pokemon_v2_pokemonabilities?: record, pokemon_v2_pokemonabilities_aggregate?: record, pokemon_v2_pokemonabilitypasts?: record, pokemon_v2_pokemonabilitypasts_aggregate?: record}
# --order-by item shape: {generation_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", is_main_series?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", name?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_abilitychanges_aggregate?: record, pokemon_v2_abilityeffecttexts_aggregate?: record, pokemon_v2_abilityflavortexts_aggregate?: record, pokemon_v2_abilitynames_aggregate?: record, pokemon_v2_generation?: record, pokemon_v2_pokemonabilities_aggregate?: record, pokemon_v2_pokemonabilitypasts_aggregate?: record}
export def "query pokemon-v2-ability" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {generation_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", is_main_series?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", name?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_abilitychanges_aggregate?: record, pokemon_v2_abilityeffecttexts_aggregate?: record, pokemon_v2_abilityflavortexts_aggregate?: record, pokemon_v2_abilitynames_aggregate?: record, pokemon_v2_generation?: record, pokemon_v2_pokemonabilities_aggregate?: record, pokemon_v2_pokemonabilitypasts_aggregate?: record}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, generation_id?: record, id?: record, is_main_series?: record, name?: record, pokemon_v2_abilitychanges?: record, pokemon_v2_abilitychanges_aggregate?: record, pokemon_v2_abilityeffecttexts?: record, pokemon_v2_abilityeffecttexts_aggregate?: record, pokemon_v2_abilityflavortexts?: record, pokemon_v2_abilityflavortexts_aggregate?: record, pokemon_v2_abilitynames?: record, pokemon_v2_abilitynames_aggregate?: record, pokemon_v2_generation?: record, pokemon_v2_pokemonabilities?: record, pokemon_v2_pokemonabilities_aggregate?: record, pokemon_v2_pokemonabilitypasts?: record, pokemon_v2_pokemonabilitypasts_aggregate?: record}
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "generation_id id is_main_series name" }
    let body = {query: ("query($distinct_on: [pokemon_v2_ability_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_ability_order_by!], $where: pokemon_v2_ability_bool_exp) { pokemon_v2_ability(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_ability" }
}

# fetch aggregated fields from the table: "pokemon_v2_ability"
#
# operationId: pokemon_v2_ability_aggregate
# --where shape: {_and?: record, _not?: record, _or?: record, generation_id?: record, id?: record, is_main_series?: record, name?: record, pokemon_v2_abilitychanges?: record, pokemon_v2_abilitychanges_aggregate?: record, pokemon_v2_abilityeffecttexts?: record, pokemon_v2_abilityeffecttexts_aggregate?: record, pokemon_v2_abilityflavortexts?: record, pokemon_v2_abilityflavortexts_aggregate?: record, pokemon_v2_abilitynames?: record, pokemon_v2_abilitynames_aggregate?: record, pokemon_v2_generation?: record, pokemon_v2_pokemonabilities?: record, pokemon_v2_pokemonabilities_aggregate?: record, pokemon_v2_pokemonabilitypasts?: record, pokemon_v2_pokemonabilitypasts_aggregate?: record}
# --order-by item shape: {generation_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", is_main_series?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", name?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_abilitychanges_aggregate?: record, pokemon_v2_abilityeffecttexts_aggregate?: record, pokemon_v2_abilityflavortexts_aggregate?: record, pokemon_v2_abilitynames_aggregate?: record, pokemon_v2_generation?: record, pokemon_v2_pokemonabilities_aggregate?: record, pokemon_v2_pokemonabilitypasts_aggregate?: record}
export def "query pokemon-v2-ability-aggregate" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {generation_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", is_main_series?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", name?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_abilitychanges_aggregate?: record, pokemon_v2_abilityeffecttexts_aggregate?: record, pokemon_v2_abilityflavortexts_aggregate?: record, pokemon_v2_abilitynames_aggregate?: record, pokemon_v2_generation?: record, pokemon_v2_pokemonabilities_aggregate?: record, pokemon_v2_pokemonabilitypasts_aggregate?: record}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, generation_id?: record, id?: record, is_main_series?: record, name?: record, pokemon_v2_abilitychanges?: record, pokemon_v2_abilitychanges_aggregate?: record, pokemon_v2_abilityeffecttexts?: record, pokemon_v2_abilityeffecttexts_aggregate?: record, pokemon_v2_abilityflavortexts?: record, pokemon_v2_abilityflavortexts_aggregate?: record, pokemon_v2_abilitynames?: record, pokemon_v2_abilitynames_aggregate?: record, pokemon_v2_generation?: record, pokemon_v2_pokemonabilities?: record, pokemon_v2_pokemonabilities_aggregate?: record, pokemon_v2_pokemonabilitypasts?: record, pokemon_v2_pokemonabilitypasts_aggregate?: record}
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($distinct_on: [pokemon_v2_ability_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_ability_order_by!], $where: pokemon_v2_ability_bool_exp) { pokemon_v2_ability_aggregate(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_ability_aggregate" }
}

# fetch data from the table: "pokemon_v2_ability" using primary key columns
#
# operationId: pokemon_v2_ability_by_pk
export def "query pokemon-v2-ability-by-pk" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  id: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "generation_id id is_main_series name" }
    let body = {query: ("query($id: Int!) { pokemon_v2_ability_by_pk(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_ability_by_pk" }
}

# fetch data from the table: "pokemon_v2_abilitychange"
#
# operationId: pokemon_v2_abilitychange
# --where shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, id?: record, pokemon_v2_ability?: record, pokemon_v2_abilitychangeeffecttexts?: record, pokemon_v2_abilitychangeeffecttexts_aggregate?: record, pokemon_v2_versiongroup?: record, version_group_id?: record}
# --order-by item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_abilitychangeeffecttexts_aggregate?: record, pokemon_v2_versiongroup?: record, version_group_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
export def "query pokemon-v2-abilitychange" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer-1 # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_abilitychangeeffecttexts_aggregate?: record, pokemon_v2_versiongroup?: record, version_group_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, id?: record, pokemon_v2_ability?: record, pokemon_v2_abilitychangeeffecttexts?: record, pokemon_v2_abilitychangeeffecttexts_aggregate?: record, pokemon_v2_versiongroup?: record, version_group_id?: record}
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "ability_id id version_group_id" }
    let body = {query: ("query($distinct_on: [pokemon_v2_abilitychange_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_abilitychange_order_by!], $where: pokemon_v2_abilitychange_bool_exp) { pokemon_v2_abilitychange(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilitychange" }
}

# fetch aggregated fields from the table: "pokemon_v2_abilitychange"
#
# operationId: pokemon_v2_abilitychange_aggregate
# --where shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, id?: record, pokemon_v2_ability?: record, pokemon_v2_abilitychangeeffecttexts?: record, pokemon_v2_abilitychangeeffecttexts_aggregate?: record, pokemon_v2_versiongroup?: record, version_group_id?: record}
# --order-by item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_abilitychangeeffecttexts_aggregate?: record, pokemon_v2_versiongroup?: record, version_group_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
export def "query pokemon-v2-abilitychange-aggregate" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer-1 # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_abilitychangeeffecttexts_aggregate?: record, pokemon_v2_versiongroup?: record, version_group_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, id?: record, pokemon_v2_ability?: record, pokemon_v2_abilitychangeeffecttexts?: record, pokemon_v2_abilitychangeeffecttexts_aggregate?: record, pokemon_v2_versiongroup?: record, version_group_id?: record}
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($distinct_on: [pokemon_v2_abilitychange_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_abilitychange_order_by!], $where: pokemon_v2_abilitychange_bool_exp) { pokemon_v2_abilitychange_aggregate(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilitychange_aggregate" }
}

# fetch data from the table: "pokemon_v2_abilitychange" using primary key columns
#
# operationId: pokemon_v2_abilitychange_by_pk
export def "query pokemon-v2-abilitychange-by-pk" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  id: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "ability_id id version_group_id" }
    let body = {query: ("query($id: Int!) { pokemon_v2_abilitychange_by_pk(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilitychange_by_pk" }
}

# fetch data from the table: "pokemon_v2_abilitychangeeffecttext"
#
# operationId: pokemon_v2_abilitychangeeffecttext
# --where shape: {_and?: record, _not?: record, _or?: record, ability_change_id?: record, effect?: record, id?: record, language_id?: record, pokemon_v2_abilitychange?: record, pokemon_v2_language?: record}
# --order-by item shape: {ability_change_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_abilitychange?: record, pokemon_v2_language?: record}
export def "query pokemon-v2-abilitychangeeffecttext" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer-2 # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {ability_change_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_abilitychange?: record, pokemon_v2_language?: record}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, ability_change_id?: record, effect?: record, id?: record, language_id?: record, pokemon_v2_abilitychange?: record, pokemon_v2_language?: record}
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "ability_change_id effect id language_id" }
    let body = {query: ("query($distinct_on: [pokemon_v2_abilitychangeeffecttext_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_abilitychangeeffecttext_order_by!], $where: pokemon_v2_abilitychangeeffecttext_bool_exp) { pokemon_v2_abilitychangeeffecttext(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilitychangeeffecttext" }
}

# fetch aggregated fields from the table: "pokemon_v2_abilitychangeeffecttext"
#
# operationId: pokemon_v2_abilitychangeeffecttext_aggregate
# --where shape: {_and?: record, _not?: record, _or?: record, ability_change_id?: record, effect?: record, id?: record, language_id?: record, pokemon_v2_abilitychange?: record, pokemon_v2_language?: record}
# --order-by item shape: {ability_change_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_abilitychange?: record, pokemon_v2_language?: record}
export def "query pokemon-v2-abilitychangeeffecttext-aggregate" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer-2 # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {ability_change_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_abilitychange?: record, pokemon_v2_language?: record}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, ability_change_id?: record, effect?: record, id?: record, language_id?: record, pokemon_v2_abilitychange?: record, pokemon_v2_language?: record}
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($distinct_on: [pokemon_v2_abilitychangeeffecttext_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_abilitychangeeffecttext_order_by!], $where: pokemon_v2_abilitychangeeffecttext_bool_exp) { pokemon_v2_abilitychangeeffecttext_aggregate(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilitychangeeffecttext_aggregate" }
}

# fetch data from the table: "pokemon_v2_abilitychangeeffecttext" using primary key columns
#
# operationId: pokemon_v2_abilitychangeeffecttext_by_pk
export def "query pokemon-v2-abilitychangeeffecttext-by-pk" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  id: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "ability_change_id effect id language_id" }
    let body = {query: ("query($id: Int!) { pokemon_v2_abilitychangeeffecttext_by_pk(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilitychangeeffecttext_by_pk" }
}

# fetch data from the table: "pokemon_v2_abilityeffecttext"
#
# operationId: pokemon_v2_abilityeffecttext
# --where shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, effect?: record, id?: record, language_id?: record, pokemon_v2_ability?: record, pokemon_v2_language?: record, short_effect?: record}
# --order-by item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_language?: record, short_effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
export def "query pokemon-v2-abilityeffecttext" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer-3 # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_language?: record, short_effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, effect?: record, id?: record, language_id?: record, pokemon_v2_ability?: record, pokemon_v2_language?: record, short_effect?: record}
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "ability_id effect id language_id short_effect" }
    let body = {query: ("query($distinct_on: [pokemon_v2_abilityeffecttext_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_abilityeffecttext_order_by!], $where: pokemon_v2_abilityeffecttext_bool_exp) { pokemon_v2_abilityeffecttext(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilityeffecttext" }
}

# fetch aggregated fields from the table: "pokemon_v2_abilityeffecttext"
#
# operationId: pokemon_v2_abilityeffecttext_aggregate
# --where shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, effect?: record, id?: record, language_id?: record, pokemon_v2_ability?: record, pokemon_v2_language?: record, short_effect?: record}
# --order-by item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_language?: record, short_effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
export def "query pokemon-v2-abilityeffecttext-aggregate" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer-3 # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_language?: record, short_effect?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, effect?: record, id?: record, language_id?: record, pokemon_v2_ability?: record, pokemon_v2_language?: record, short_effect?: record}
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($distinct_on: [pokemon_v2_abilityeffecttext_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_abilityeffecttext_order_by!], $where: pokemon_v2_abilityeffecttext_bool_exp) { pokemon_v2_abilityeffecttext_aggregate(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilityeffecttext_aggregate" }
}

# fetch data from the table: "pokemon_v2_abilityeffecttext" using primary key columns
#
# operationId: pokemon_v2_abilityeffecttext_by_pk
export def "query pokemon-v2-abilityeffecttext-by-pk" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  id: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "ability_id effect id language_id short_effect" }
    let body = {query: ("query($id: Int!) { pokemon_v2_abilityeffecttext_by_pk(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilityeffecttext_by_pk" }
}

# fetch data from the table: "pokemon_v2_abilityflavortext"
#
# operationId: pokemon_v2_abilityflavortext
# --where shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, flavor_text?: record, id?: record, language_id?: record, pokemon_v2_ability?: record, pokemon_v2_language?: record, pokemon_v2_versiongroup?: record, version_group_id?: record}
# --order-by item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", flavor_text?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_language?: record, pokemon_v2_versiongroup?: record, version_group_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
export def "query pokemon-v2-abilityflavortext" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer-4 # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", flavor_text?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_language?: record, pokemon_v2_versiongroup?: record, version_group_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, flavor_text?: record, id?: record, language_id?: record, pokemon_v2_ability?: record, pokemon_v2_language?: record, pokemon_v2_versiongroup?: record, version_group_id?: record}
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "ability_id flavor_text id language_id version_group_id" }
    let body = {query: ("query($distinct_on: [pokemon_v2_abilityflavortext_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_abilityflavortext_order_by!], $where: pokemon_v2_abilityflavortext_bool_exp) { pokemon_v2_abilityflavortext(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilityflavortext" }
}

# fetch aggregated fields from the table: "pokemon_v2_abilityflavortext"
#
# operationId: pokemon_v2_abilityflavortext_aggregate
# --where shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, flavor_text?: record, id?: record, language_id?: record, pokemon_v2_ability?: record, pokemon_v2_language?: record, pokemon_v2_versiongroup?: record, version_group_id?: record}
# --order-by item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", flavor_text?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_language?: record, pokemon_v2_versiongroup?: record, version_group_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
export def "query pokemon-v2-abilityflavortext-aggregate" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --distinct-on: string@distinct-on-completer-4 # distinct select on columns
  --limit: int # limit the number of rows returned
  --offset: int # skip the first n rows. Use only with order_by
  --order-by: record # sort the rows by one or more columns — item shape: {ability_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", flavor_text?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", language_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last", pokemon_v2_ability?: record, pokemon_v2_language?: record, pokemon_v2_versiongroup?: record, version_group_id?: "asc"|"asc_nulls_first"|"asc_nulls_last"|"desc"|"desc_nulls_first"|"desc_nulls_last"}
  --qp-where: record # filter the rows returned — shape: {_and?: record, _not?: record, _or?: record, ability_id?: record, flavor_text?: record, id?: record, language_id?: record, pokemon_v2_ability?: record, pokemon_v2_language?: record, pokemon_v2_versiongroup?: record, version_group_id?: record}
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $qp_where} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($distinct_on: [pokemon_v2_abilityflavortext_select_column!], $limit: Int, $offset: Int, $order_by: [pokemon_v2_abilityflavortext_order_by!], $where: pokemon_v2_abilityflavortext_bool_exp) { pokemon_v2_abilityflavortext_aggregate(distinct_on: $distinct_on, limit: $limit, offset: $offset, order_by: $order_by, where: $where) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilityflavortext_aggregate" }
}

# fetch data from the table: "pokemon_v2_abilityflavortext" using primary key columns
#
# operationId: pokemon_v2_abilityflavortext_by_pk
export def "query pokemon-v2-abilityflavortext-by-pk" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  id: int
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "ability_id flavor_text id language_id version_group_id" }
    let body = {query: ("query($id: Int!) { pokemon_v2_abilityflavortext_by_pk(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body
  }
  if $raw or $allow_errors { $result } else { unwrap-graphql $result "pokemon_v2_abilityflavortext_by_pk" }
}
