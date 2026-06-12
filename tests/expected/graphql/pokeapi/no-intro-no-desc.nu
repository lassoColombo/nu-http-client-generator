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

def base-url-completer [] { ["https://example.com/graphql"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def distinct-on-completer [] { ["generation_id" "id" "is_main_series" "name"] }
def distinct-on-completer-1 [] { ["ability_id" "id" "version_group_id"] }
def distinct-on-completer-2 [] { ["ability_change_id" "effect" "id" "language_id"] }
def distinct-on-completer-3 [] { ["ability_id" "effect" "id" "language_id" "short_effect"] }
def distinct-on-completer-4 [] { ["ability_id" "flavor_text" "id" "language_id" "version_group_id"] }


# fetch data from the table: "pokemon_v2_ability"
#
# operationId: pokemon_v2_ability
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
  --distinct-on: string@distinct-on-completer
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-generation-id: record
  --where-id: record
  --where-is-main-series: record
  --where-name: record
  --where-pokemon-v2-abilitychanges: record
  --where-pokemon-v2-abilitychanges-aggregate: record
  --where-pokemon-v2-abilityeffecttexts: record
  --where-pokemon-v2-abilityeffecttexts-aggregate: record
  --where-pokemon-v2-abilityflavortexts: record
  --where-pokemon-v2-abilityflavortexts-aggregate: record
  --where-pokemon-v2-abilitynames: record
  --where-pokemon-v2-abilitynames-aggregate: record
  --where-pokemon-v2-generation: record
  --where-pokemon-v2-pokemonabilities: record
  --where-pokemon-v2-pokemonabilities-aggregate: record
  --where-pokemon-v2-pokemonabilitypasts: record
  --where-pokemon-v2-pokemonabilitypasts-aggregate: record
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "generation_id": $where_generation_id, "id": $where_id, "is_main_series": $where_is_main_series, "name": $where_name, "pokemon_v2_abilitychanges": $where_pokemon_v2_abilitychanges, "pokemon_v2_abilitychanges_aggregate": $where_pokemon_v2_abilitychanges_aggregate, "pokemon_v2_abilityeffecttexts": $where_pokemon_v2_abilityeffecttexts, "pokemon_v2_abilityeffecttexts_aggregate": $where_pokemon_v2_abilityeffecttexts_aggregate, "pokemon_v2_abilityflavortexts": $where_pokemon_v2_abilityflavortexts, "pokemon_v2_abilityflavortexts_aggregate": $where_pokemon_v2_abilityflavortexts_aggregate, "pokemon_v2_abilitynames": $where_pokemon_v2_abilitynames, "pokemon_v2_abilitynames_aggregate": $where_pokemon_v2_abilitynames_aggregate, "pokemon_v2_generation": $where_pokemon_v2_generation, "pokemon_v2_pokemonabilities": $where_pokemon_v2_pokemonabilities, "pokemon_v2_pokemonabilities_aggregate": $where_pokemon_v2_pokemonabilities_aggregate, "pokemon_v2_pokemonabilitypasts": $where_pokemon_v2_pokemonabilitypasts, "pokemon_v2_pokemonabilitypasts_aggregate": $where_pokemon_v2_pokemonabilitypasts_aggregate} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-generation-id: record
  --where-id: record
  --where-is-main-series: record
  --where-name: record
  --where-pokemon-v2-abilitychanges: record
  --where-pokemon-v2-abilitychanges-aggregate: record
  --where-pokemon-v2-abilityeffecttexts: record
  --where-pokemon-v2-abilityeffecttexts-aggregate: record
  --where-pokemon-v2-abilityflavortexts: record
  --where-pokemon-v2-abilityflavortexts-aggregate: record
  --where-pokemon-v2-abilitynames: record
  --where-pokemon-v2-abilitynames-aggregate: record
  --where-pokemon-v2-generation: record
  --where-pokemon-v2-pokemonabilities: record
  --where-pokemon-v2-pokemonabilities-aggregate: record
  --where-pokemon-v2-pokemonabilitypasts: record
  --where-pokemon-v2-pokemonabilitypasts-aggregate: record
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "generation_id": $where_generation_id, "id": $where_id, "is_main_series": $where_is_main_series, "name": $where_name, "pokemon_v2_abilitychanges": $where_pokemon_v2_abilitychanges, "pokemon_v2_abilitychanges_aggregate": $where_pokemon_v2_abilitychanges_aggregate, "pokemon_v2_abilityeffecttexts": $where_pokemon_v2_abilityeffecttexts, "pokemon_v2_abilityeffecttexts_aggregate": $where_pokemon_v2_abilityeffecttexts_aggregate, "pokemon_v2_abilityflavortexts": $where_pokemon_v2_abilityflavortexts, "pokemon_v2_abilityflavortexts_aggregate": $where_pokemon_v2_abilityflavortexts_aggregate, "pokemon_v2_abilitynames": $where_pokemon_v2_abilitynames, "pokemon_v2_abilitynames_aggregate": $where_pokemon_v2_abilitynames_aggregate, "pokemon_v2_generation": $where_pokemon_v2_generation, "pokemon_v2_pokemonabilities": $where_pokemon_v2_pokemonabilities, "pokemon_v2_pokemonabilities_aggregate": $where_pokemon_v2_pokemonabilities_aggregate, "pokemon_v2_pokemonabilitypasts": $where_pokemon_v2_pokemonabilitypasts, "pokemon_v2_pokemonabilitypasts_aggregate": $where_pokemon_v2_pokemonabilitypasts_aggregate} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer-1
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-ability-id: record
  --where-id: record
  --where-pokemon-v2-ability: record
  --where-pokemon-v2-abilitychangeeffecttexts: record
  --where-pokemon-v2-abilitychangeeffecttexts-aggregate: record
  --where-pokemon-v2-versiongroup: record
  --where-version-group-id: record
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "ability_id": $where_ability_id, "id": $where_id, "pokemon_v2_ability": $where_pokemon_v2_ability, "pokemon_v2_abilitychangeeffecttexts": $where_pokemon_v2_abilitychangeeffecttexts, "pokemon_v2_abilitychangeeffecttexts_aggregate": $where_pokemon_v2_abilitychangeeffecttexts_aggregate, "pokemon_v2_versiongroup": $where_pokemon_v2_versiongroup, "version_group_id": $where_version_group_id} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer-1
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-ability-id: record
  --where-id: record
  --where-pokemon-v2-ability: record
  --where-pokemon-v2-abilitychangeeffecttexts: record
  --where-pokemon-v2-abilitychangeeffecttexts-aggregate: record
  --where-pokemon-v2-versiongroup: record
  --where-version-group-id: record
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "ability_id": $where_ability_id, "id": $where_id, "pokemon_v2_ability": $where_pokemon_v2_ability, "pokemon_v2_abilitychangeeffecttexts": $where_pokemon_v2_abilitychangeeffecttexts, "pokemon_v2_abilitychangeeffecttexts_aggregate": $where_pokemon_v2_abilitychangeeffecttexts_aggregate, "pokemon_v2_versiongroup": $where_pokemon_v2_versiongroup, "version_group_id": $where_version_group_id} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer-2
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-ability-change-id: record
  --where-effect: record
  --where-id: record
  --where-language-id: record
  --where-pokemon-v2-abilitychange: record
  --where-pokemon-v2-language: record
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "ability_change_id": $where_ability_change_id, "effect": $where_effect, "id": $where_id, "language_id": $where_language_id, "pokemon_v2_abilitychange": $where_pokemon_v2_abilitychange, "pokemon_v2_language": $where_pokemon_v2_language} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer-2
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-ability-change-id: record
  --where-effect: record
  --where-id: record
  --where-language-id: record
  --where-pokemon-v2-abilitychange: record
  --where-pokemon-v2-language: record
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "ability_change_id": $where_ability_change_id, "effect": $where_effect, "id": $where_id, "language_id": $where_language_id, "pokemon_v2_abilitychange": $where_pokemon_v2_abilitychange, "pokemon_v2_language": $where_pokemon_v2_language} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer-3
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-ability-id: record
  --where-effect: record
  --where-id: record
  --where-language-id: record
  --where-pokemon-v2-ability: record
  --where-pokemon-v2-language: record
  --where-short-effect: record
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "ability_id": $where_ability_id, "effect": $where_effect, "id": $where_id, "language_id": $where_language_id, "pokemon_v2_ability": $where_pokemon_v2_ability, "pokemon_v2_language": $where_pokemon_v2_language, "short_effect": $where_short_effect} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer-3
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-ability-id: record
  --where-effect: record
  --where-id: record
  --where-language-id: record
  --where-pokemon-v2-ability: record
  --where-pokemon-v2-language: record
  --where-short-effect: record
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "ability_id": $where_ability_id, "effect": $where_effect, "id": $where_id, "language_id": $where_language_id, "pokemon_v2_ability": $where_pokemon_v2_ability, "pokemon_v2_language": $where_pokemon_v2_language, "short_effect": $where_short_effect} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer-4
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-ability-id: record
  --where-flavor-text: record
  --where-id: record
  --where-language-id: record
  --where-pokemon-v2-ability: record
  --where-pokemon-v2-language: record
  --where-pokemon-v2-versiongroup: record
  --where-version-group-id: record
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "ability_id": $where_ability_id, "flavor_text": $where_flavor_text, "id": $where_id, "language_id": $where_language_id, "pokemon_v2_ability": $where_pokemon_v2_ability, "pokemon_v2_language": $where_pokemon_v2_language, "pokemon_v2_versiongroup": $where_pokemon_v2_versiongroup, "version_group_id": $where_version_group_id} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
  --distinct-on: string@distinct-on-completer-4
  --limit: int
  --offset: int
  --order-by: record
  --where-and: record
  --where-not: record
  --where-or: record
  --where-ability-id: record
  --where-flavor-text: record
  --where-id: record
  --where-language-id: record
  --where-pokemon-v2-ability: record
  --where-pokemon-v2-language: record
  --where-pokemon-v2-versiongroup: record
  --where-version-group-id: record
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let where = ({"_and": $where_and, "_not": $where_not, "_or": $where_or, "ability_id": $where_ability_id, "flavor_text": $where_flavor_text, "id": $where_id, "language_id": $where_language_id, "pokemon_v2_ability": $where_pokemon_v2_ability, "pokemon_v2_language": $where_pokemon_v2_language, "pokemon_v2_versiongroup": $where_pokemon_v2_versiongroup, "version_group_id": $where_version_group_id} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"distinct_on": $distinct_on, "limit": $limit, "offset": $offset, "order_by": $order_by, "where": $where} | compact
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
