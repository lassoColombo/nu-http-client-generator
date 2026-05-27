# render.nu — Code generation / rendering for the Nushell HTTP client module.
#
# All functions in this file take the command model (built by mod.nu + spec.nu)
# and produce Nushell source code strings.

# Map OpenAPI types to Nushell types
export def openapi-to-nu-type [t: string] {
  match $t {
    "string" => "string"
    "integer" => "int"
    "number" => "float"
    "boolean" => "bool"
    "array" => "list"
    "object" => "record"
    "file" => "path"
    "record" => "record"
    "list" => "list"
    _ => "any"
  }
}

# Nushell reserved names that cannot be standalone command/flag names
const RESERVED_NAMES = [in nu nothing]

# Variable names reserved in generated commands — body/query/header fields that
# match any of these get a prefix to avoid shadowing.
const RESERVED_VARS = [
  # nushell language keywords
  in nu nothing null true false
  if else match for while loop break continue return
  let mut const def export use module source overlay
  where each error try catch not do
  # generated signature flags
  base_url token auth_scheme insecure max_time raw allow_errors accept
  # generated body-code internal variables
  auth base url qp full_url body extra_headers cookie_str accept_val
  # graphql body-code variables
  result sel query fields variables
  # nushell builtins that cause issues as variable names
  sort from to get open save into split str
]

# Convert param names to valid nushell flag names
export def to-flag-name [name: string] {
  let cleaned = $name | str replace --all '_' '-' | str replace --all --regex '[\\$()\[\].*/\x27"#!@%^&+=~`]' '' | str replace --regex '-{2,}' '-' | str trim --char '-'
  if ($cleaned in $RESERVED_NAMES) or ($cleaned | is-empty) {
    $"($cleaned)-param" | str trim --char '-'
  } else {
    $cleaned
  }
}

# Sanitize a field name to a valid nushell variable name (underscores, no special chars)
def to-var-name [name: string] {
  $name | str replace --all '-' '_' | str replace --all --regex '[\\$()\[\].*/\x27"#!@%^&+=~`]' '' | str replace --regex '_{2,}' '_' | str trim --char '_'
}

# Convert a parameter name to a nushell variable name (flag-style then underscored)
def to-flag-var [name: string] {
  to-flag-name $name | str replace --all '-' '_'
}

# Flag name with collision prefix for query/header/cookie params
def effective-flag-name [name: string, prefix: string] {
  let raw = (to-flag-name $name)
  let var = (to-flag-var $name)
  if ($var in $RESERVED_VARS) { $"($prefix)-($raw)" } else { $raw }
}

# Variable name with collision prefix for query/header/cookie params
def effective-flag-var [name: string, prefix: string] {
  effective-flag-name $name $prefix | str replace --all '-' '_'
}

# Render a list of params as a nushell record literal string (e.g. "key": $var, ...)
def render-param-record [params: list, --quote-keys, --prefix: string = ""] {
  $params | each {|p|
    let var = if ($prefix | is-not-empty) { effective-flag-var $p.name $prefix } else { to-flag-var $p.name }
    if $quote_keys { $'"($p.name)": $($var)' } else { $'($p.name): $($var)' }
  } | str join ", "
}

# Collect all unique enum sets and map each (flag_name, enum_values) to a completer name.
export def collect-completers [commands: list] {
  mut completers = {}
  mut mapping = {}
  mut name_counts = {}

  for cmd in $commands {
    let accept_source = if ($cmd.accept_types | length) > 1 { [{name: "accept", enum: $cmd.accept_types}] } else { [] }
    let enum_sources = ($cmd.query_params | append $cmd.body_fields | append $cmd.header_params | append $cmd.cookie_params | append $accept_source)
    for q in $enum_sources {
      if ($q.enum | length) > 0 {
        let flag_name = (to-flag-name $q.name)
        let vals = ($q.enum | each { $"($in)" } | sort)
        let fingerprint = $"($flag_name):($vals | str join ',')"

        if not ($fingerprint in ($mapping | columns)) {
          let count = ($name_counts | get -o $flag_name | default 0)
          let cname = if $count == 0 {
            $"($flag_name)-completer"
          } else {
            $"($flag_name)-completer-($count)"
          }
          $name_counts = ($name_counts | upsert $flag_name ($count + 1))
          $completers = ($completers | insert $cname $vals)
          $mapping = ($mapping | insert $fingerprint $cname)
        }
      }
    }
  }
  {completers: $completers, mapping: $mapping}
}

# Render completer functions as nushell source
export def render-completers [completers: record] {
  $completers | transpose name values | each {|c|
    let vals = $c.values | each {|v| $'"($v)"' } | str join ' '
    $'def "($c.name)" [] { [($vals)] }'
  } | str join "\n"
}

# Resolve the completer name for a param given the mapping
export def resolve-completer [q: record, mapping: record] {
  let flag_name = (to-flag-name $q.name)
  let vals = ($q.enum | each { $"($in)" } | sort)
  let fingerprint = $"($flag_name):($vals | str join ',')"
  $mapping | get -o $fingerprint
}

# Render a single flag/positional line for the signature.
# Used by query, header, cookie params and body fields to avoid duplication.
def render-param-sig [flag_name: string, nu_type: string, desc: string, cname?: string, --positional] {
  if $positional {
    if ($cname | is-not-empty) {
      $'  ($flag_name): ($nu_type)@"($cname)"($desc)'
    } else {
      $'  ($flag_name): ($nu_type)($desc)'
    }
  } else if $nu_type == "bool" {
    $'  --($flag_name): string@"bool-completer"($desc)'
  } else if ($cname | is-not-empty) {
    $'  --($flag_name): ($nu_type)@"($cname)"($desc)'
  } else {
    $'  --($flag_name): ($nu_type)($desc)'
  }
}

# Build the signature string for a command
export def build-signature [cmd: record, completers: record, mapping: record, config: record] {
  mut parts = []

  for p in $cmd.path_params {
    let nu_type = (openapi-to-nu-type $p.type)
    $parts = ($parts | append $"  ($p.name): ($nu_type)")
  }

  $parts = ($parts | append [
    '  --base-url(-b): string@"base-url-completer" # API base URL'
    '  --token(-t): string # Auth token'
    '  --auth-scheme(-a): string@"auth-scheme-completer" # Auth scheme'
    '  --insecure(-k) # Skip TLS verification'
    '  --max-time(-m): duration # Timeout'
    '  --raw(-r) # Fetch as text'
    '  --allow-errors(-e) # Return full response without error handling'
  ])

  # GraphQL-specific flags
  let is_graphql = ($cmd.method | str starts-with "graphql-")
  if $is_graphql {
    $parts = ($parts | append [
      '  --fields: list<string> # Fields to select'
      '  --query: string # Raw GraphQL query (overrides auto-generated)'
    ])
  }

  # Accept header flag
  if ($cmd.accept_types | length) > 1 {
    let cname = resolve-completer {name: "accept", enum: $cmd.accept_types} $mapping
    if ($cname | is-not-empty) {
      $parts = ($parts | append $'  --accept: string@"($cname)" # Response content type')
    } else {
      $parts = ($parts | append '  --accept: string # Response content type')
    }
  } else {
    $parts = ($parts | append '  --accept: string # Response content type')
  }

  # Query params
  for q in $cmd.query_params {
    let nu_type = (openapi-to-nu-type $q.type)
    let flag_name = (effective-flag-name $q.name "qp")
    let desc_text = if ($q.description | is-not-empty) { $q.description | lines | str join " " } else { "" }
    let desc = if $config.no_descriptions { "" } else if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
    let cname = if ($q.enum | length) > 0 { resolve-completer $q $mapping } else { null }
    let is_required = ($q.required? | default false)
    if $is_graphql and $is_required and ($nu_type != "record") and ($nu_type != "bool") {
      let var_name = ($q.name | str replace --all '-' '_')
      $parts = ($parts | append (render-param-sig $var_name $nu_type $desc $cname --positional))
    } else {
      $parts = ($parts | append (render-param-sig $flag_name $nu_type $desc $cname))
    }
  }

  # Header params
  for q in $cmd.header_params {
    let nu_type = (openapi-to-nu-type $q.type)
    let flag_name = (effective-flag-name $q.name "hdr")
    let desc_text = if ($q.description | is-not-empty) { $q.description | lines | str join " " } else { "" }
    let desc = if $config.no_descriptions { "" } else if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
    let cname = if ($q.enum | length) > 0 { resolve-completer $q $mapping } else { null }
    $parts = ($parts | append (render-param-sig $flag_name $nu_type $desc $cname))
  }

  # Cookie params
  for q in $cmd.cookie_params {
    let nu_type = (openapi-to-nu-type $q.type)
    let flag_name = (effective-flag-name $q.name "ck")
    let desc_text = if ($q.description | is-not-empty) { $q.description | lines | str join " " } else { "" }
    let desc = if $config.no_descriptions { "" } else if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
    let cname = if ($q.enum | length) > 0 { resolve-completer $q $mapping } else { null }
    $parts = ($parts | append (render-param-sig $flag_name $nu_type $desc $cname))
  }

  if $cmd.has_body {
    let use_collapsed = ($config.body_threshold > 0) and (($cmd.body_fields | length) > $config.body_threshold)
    if $use_collapsed {
      $parts = ($parts | append "  --body: record # Request body")
    } else {
      let path_param_names = ($cmd.path_params | each {|p| $p.name })
      for f in $cmd.body_fields {
        let nu_type = (openapi-to-nu-type $f.type)
        let desc_text = if ($f.description | is-not-empty) { $f.description | lines | str join " " } else { "" }
        let desc = if $config.no_descriptions { "" } else if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
        let sanitized_name = (to-var-name $f.name)
        let collides = ($sanitized_name in $path_param_names) or ($sanitized_name in $RESERVED_VARS) or ($sanitized_name | is-empty)
        let cname = if ($f.enum | length) > 0 { resolve-completer $f $mapping } else { null }
        let is_nullable = ($f.nullable? | default false)
        if $f.required and (not $collides) and ($nu_type != "bool") and (not $is_nullable) {
          $parts = ($parts | append (render-param-sig $sanitized_name $nu_type $desc $cname --positional))
        } else {
          let flag_name = if $collides { $"body-(to-flag-name $f.name)" } else { to-flag-name $f.name }
          $parts = ($parts | append (render-param-sig $flag_name $nu_type $desc $cname))
        }
      }
      if ($cmd.body_fields | length) == 0 {
        $parts = ($parts | append "  --body: record")
      }
    }
  }

  $parts | str join "\n"
}

# Render the helper functions that go into every generated client.
#
export def render-helpers [token_env_var: string, auth_schemes: list, default_auth: string, default_timeout: string, default_headers: record] {
  mut match_arms = []
  mut seen_names = []
  for s in $auth_schemes {
    if not ($s.name in $seen_names) {
      $seen_names = ($seen_names | append $s.name)
      if $s.in == "query" {
        $match_arms = ($match_arms | append ($"    \"($s.name)\" => { {headers: {}, query: $\"($s.header_name)=\($token_val\)\"} }"))
      } else if $s.in == "cookie" {
        $match_arms = ($match_arms | append ($"    \"($s.name)\" => { {headers: {Cookie: $\"($s.header_name)=\($token_val\)\"}, query: \"\"} }"))
      } else if $s.prefix == "" {
        $match_arms = ($match_arms | append $"    \"($s.name)\" => { {headers: {($s.header_name): $token_val}, query: \"\"} }")
      } else {
        $match_arms = ($match_arms | append ($"    \"($s.name)\" => { {headers: {($s.header_name): $\"($s.prefix) \($token_val\)\"}, query: \"\"} }"))
      }
    }
  }
  $match_arms = ($match_arms | append '    "none" => { {headers: {}, query: ""} }')
  $match_arms = ($match_arms | append '    _ => { {headers: {Authorization: $"Bearer ($token_val)"}, query: ""} }')
  let match_body = $match_arms | str join "\n"

  [
    '# Build auth: returns {headers: record, query: string}'
    'def build-auth [token?: string, auth_scheme?: string]: nothing -> record {'
    $"  let token_val = if \($token != null\) and \($token | is-not-empty\) { $token } else { $env | get -o ($token_env_var) | default \"\" }"
    '  let scheme = ($auth_scheme | default "bearer")'
    '  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }'
    '  match $scheme {'
    $match_body
    '  }'
    '}'
    ''
    '# Serialize a single query parameter based on collection style'
    'def serialize-qp [name: string, value: any, style: string]: nothing -> list<string> {'
    '  if ($value == null) { return [] }'
    '  let is_list = ($value | describe | str starts-with "list")'
    '  if ($value | describe | str starts-with "record") { return ($value | transpose k v | each { $"($name)[($in.k)]=($in.v)" }) }'
    '  if not $is_list { return [$"($name)=($value)"] }'
    '  match $style {'
    '    "multi" => { $value | each {|v| $"($name)=($v)" } }'
    '    "csv" => { let joined = ($value | each { $in | into string } | str join ","); [$"($name)=($joined)"] }'
    '    "ssv" => { let joined = ($value | each { $in | into string } | str join "%20"); [$"($name)=($joined)"] }'
    '    "tsv" => { let joined = ($value | each { $in | into string } | str join "\t"); [$"($name)=($joined)"] }'
    '    "pipes" => { let joined = ($value | each { $in | into string } | str join "|"); [$"($name)=($joined)"] }'
    '    "deepObject" => { $value | each {|v| $"($name)[]=($v)" } }'
    '    _ => { $value | each {|v| $"($name)=($v)" } }'
    '  }'
    '}'
    ''
    '# Execute HTTP request with method dispatch'
    'def do-request [method: string, url: string, auth: record, insecure: bool, raw: bool, max_time?: duration, allow_errors?: bool, content_type?: string, body?: any]: nothing -> any {'
    '  let req_url = if ($auth.query | is-not-empty) { if ($url | str contains "?") { $"($url)&($auth.query)" } else { $"($url)?($auth.query)" } } else { $url }'
    ('  let timeout = ($max_time | default ' + $default_timeout + ')')
    '  let ct = ($content_type | default "application/json")'
  ] | if ($default_headers | columns | length) > 0 {
    let header_pairs = ($default_headers | transpose k v | each {|h| $'"($h.k)": "($h.v)"' } | str join ", ")
    $in | append ('  let auth = {headers: ({' + $header_pairs + '} | merge $auth.headers), query: $auth.query}')
  } else {
    $in
  } | append [
    '  let resp = match $method {'
    '    "get" => { http get --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url }'
    '    "head" => { http head --headers $auth.headers --max-time $timeout --insecure=$insecure $req_url }'
    '    "options" => { http options --headers $auth.headers --max-time $timeout --insecure=$insecure $req_url }'
    '    "post" => { http post --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }'
    '    "put" => { http put --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }'
    '    "patch" => { http patch --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }'
    '    "delete" => { if ($body | is-empty) { http delete --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } else { http delete --headers $auth.headers --content-type $ct --data $body --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } }'
    '  }'
    '  if ($method in ["head" "options"]) { return $resp }'
    '  if $allow_errors { $resp } else if $resp.status == 204 { null } else if $resp.status >= 400 { error make --unspanned { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }'
    '}'
  ] | str join "\n"
}

# Build the body code for a command.
export def build-body-code [cmd: record, config: record] {
  mut lines = []

  $lines = ($lines | append ($"  let auth = \(build-auth $token \($auth_scheme | default \"($cmd.default_auth)\"\)\)"))
  if ($cmd.base_url | is-not-empty) {
    $lines = ($lines | append ($"  let base = \($base_url | default \"($cmd.base_url)\"\)"))
  } else {
    $lines = ($lines | append '  let base = ($base_url | default $BASE_URL)')
  }

  if ($cmd.path_params | length) > 0 {
    mut path_str = $cmd.path_template
    for p in $cmd.path_params {
      let orig = ($p.original_name? | default $p.name)
      let placeholder = $'{($orig)}'
      let replacement = $"\($($p.name)\)"
      $path_str = ($path_str | str replace $placeholder $replacement)
    }
    $lines = ($lines | append ($"  let url = $\"\($base\)($path_str)\""))
  } else {
    $lines = ($lines | append ($"  let url = $\"\($base\)($cmd.path_template)\""))
  }

  if ($cmd.query_params | length) > 0 {
    let calls = $cmd.query_params | each {|q|
      let var_name = $"$(effective-flag-var $q.name "qp")"
      $"\(serialize-qp \"($q.name)\" ($var_name) \"($q.collection_style)\"\)"
    } | str join " "
    $lines = ($lines | append ($"  let qp = [($calls)] | flatten | str join \"&\""))
    $lines = ($lines | append '  let full_url = if ($qp | is-empty) { $url } else { $"($url)?($qp)" }')
  } else {
    $lines = ($lines | append '  let full_url = $url')
  }

  if $cmd.has_body and ($cmd.body_fields | length) > 0 {
    let use_collapsed = ($config.body_threshold > 0) and (($cmd.body_fields | length) > $config.body_threshold)
    if not $use_collapsed {
      let path_param_names = ($cmd.path_params | each {|p| $p.name })
      let body_parts = $cmd.body_fields | each {|f|
        let sanitized_name = (to-var-name $f.name)
        let collides = ($sanitized_name in $path_param_names) or ($sanitized_name in $RESERVED_VARS) or ($sanitized_name | is-empty)
        let nu_type = (openapi-to-nu-type $f.type)
        let is_nullable = ($f.nullable? | default false)
        let var_name = if $f.required and (not $collides) and ($nu_type != "bool") and (not $is_nullable) {
          $'$($sanitized_name)'
        } else {
          let flag_base = (to-flag-var $f.name)
          let flag = if $collides { $'body_($flag_base)' } else { $flag_base }
          $'$($flag)'
        }
        $'($f.name): ($var_name)'
      } | str join ", "
      $lines = ($lines | append ($"  let body = {($body_parts)} | transpose k v | where { $in.v != null } | if \($in | is-empty\) { {} } else { $in | transpose -r -d }"))
    }
  }

  if ($cmd.header_params | length) > 0 {
    let hp_record = (render-param-record $cmd.header_params --quote-keys --prefix "hdr")
    $lines = ($lines | append ($"  let extra_headers = {($hp_record)} | transpose k v | where { $in.v != null } | if \($in | is-empty\) { {} } else { $in | transpose -r -d }"))
    $lines = ($lines | append '  let auth = ($auth | update headers ($auth.headers | merge $extra_headers))')
  }

  if ($cmd.cookie_params | length) > 0 {
    let cp_record = (render-param-record $cmd.cookie_params --prefix "ck")
    $lines = ($lines | append ($"  let cookie_str = {($cp_record)} | transpose k v | where { $in.v != null } | each { $\"\($in.k\)=\($in.v\)\" } | str join \"; \""))
    $lines = ($lines | append '  let auth = if ($cookie_str | is-not-empty) { $auth | update headers ($auth.headers | merge {Cookie: $cookie_str}) } else { $auth }')
  }

  let default_accept = ($cmd.accept_types | first)
  $lines = ($lines | append ($"  let accept_val = \($accept | default \"($default_accept)\"\)"))
  $lines = ($lines | append '  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))')

  if $cmd.has_body and ($cmd.content_type == "multipart/form-data") and ($cmd.body_fields | length) > 0 {
    let file_fields = ($cmd.body_fields | where {|f| $f.type == "file" })
    for f in $file_fields {
      let sanitized = (to-var-name $f.name)
      let flag_var = (to-flag-var $f.name)
      let var = if $f.required { $'$($sanitized)' } else { $'$($flag_var)' }
      $lines = ($lines | append ($"  let body = if \(($var) | is-not-empty\) { $body | upsert ($f.name) \(open -r ($var)\) } else { $body }"))
    }
  }

  let body_arg = if $cmd.has_body { " $body" } else { "" }
  $lines = ($lines | append $'  do-request "($cmd.method)" $full_url $auth $insecure $raw $max_time $allow_errors "($cmd.content_type)"($body_arg)')

  $lines | str join "\n"
}

# Build the body code for a GraphQL command.
export def build-graphql-body-code [cmd: record, config: record] {
  mut lines = []

  # Auth
  $lines = ($lines | append '  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))')

  # Base URL
  if ($cmd.base_url | is-not-empty) {
    $lines = ($lines | append ($"  let base = \($base_url | default \"($cmd.base_url)\"\)"))
  } else {
    $lines = ($lines | append '  let base = ($base_url | default $BASE_URL)')
  }

  # Build variables record from query_params (which are GraphQL args)
  # Must match variable names from build-signature: positional args use raw names,
  # flag args use effective-flag-var with "qp" prefix for reserved names.
  let var_entries = ($cmd.query_params | each {|p|
    let nu_type = (openapi-to-nu-type $p.type)
    let is_required = ($p.required? | default false)
    let is_positional = ($is_required and ($nu_type != "record") and ($nu_type != "bool"))
    let var_name = if $is_positional {
      $p.name | str replace --all '-' '_'
    } else {
      effective-flag-var $p.name "qp"
    }
    let orig = ($p.original_name? | default $p.name)
    $'"($orig)": $($var_name)'
  })

  if ($var_entries | length) > 0 {
    let entries_str = ($var_entries | str join ", ")
    $lines = ($lines | append ($"  let variables = {($entries_str)} | transpose k v | where { $in.v != null } | transpose -r -d"))
  } else {
    $lines = ($lines | append "  let variables = {}")
  }

  # Raw query override
  $lines = ($lines | append '  let result = if ($query | is-not-empty) {')
  $lines = ($lines | append '    let body = {query: $query, variables: $variables}')
  $lines = ($lines | append '    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body')
  $lines = ($lines | append "  } else {")

  # Auto-built query
  let field_name = $cmd.gql_field_name
  let op_type = $cmd.gql_op_type
  let var_decl = $cmd.gql_var_declarations
  let scalar_return = ($cmd.gql_scalar_return? | default false)

  # Build args pass-through: continent(code: $code)
  let args_pass = ($cmd.query_params | each {|p|
    let orig = ($p.original_name? | default $p.name)
    $"($orig): $($orig)"
  } | str join ", ")

  if $scalar_return {
    # Scalar return: no selection set needed (e.g. GenreCollection returns [String])
    if ($var_decl | is-empty) {
      $lines = ($lines | append ($"    let body = {query: \"($op_type) { ($field_name) }\", variables: $variables}"))
    } else {
      $lines = ($lines | append ($"    let body = {query: \"($op_type)\(($var_decl)\) { ($field_name)\(($args_pass)\) }\", variables: $variables}"))
    }
  } else {
    let default_sel = if ($cmd.gql_default_selection | is-empty) { "__typename" } else { $cmd.gql_default_selection }
    $lines = ($lines | append ($"    let sel = if \($fields | is-not-empty\) { $fields | str join \" \" } else { \"($default_sel)\" }"))

    if ($var_decl | is-empty) {
      $lines = ($lines | append ($"    let body = {query: \(\"($op_type) { ($field_name) { \" + $sel + \" } }\"\), variables: $variables}"))
    } else {
      $lines = ($lines | append ($"    let body = {query: \(\"($op_type)\(($var_decl)\) { ($field_name)\(($args_pass)\) { \" + $sel + \" } }\"\), variables: $variables}"))
    }
  }

  $lines = ($lines | append '    do-request "post" $base $auth $insecure $raw $max_time $allow_errors "application/json" $body')
  $lines = ($lines | append "  }")

  # Unwrap response
  $lines = ($lines | append ($"  if $raw or $allow_errors { $result } else { unwrap-graphql $result \"($field_name)\" }"))

  $lines | str join "\n"
}

# Render the full module file
export def render-module [spec_data: record, commands: table, spec_file: string, module_name: string, base_url: string, extra_urls: list<string>, auth_schemes: list, default_auth: string, config: record] {
  let title = ($spec_data.info?.title? | default $module_name)
  let version_str = ($spec_data.info?.version? | default "0.0.0")
  let token_env_var = if ($config.token_env_var != null) and ($config.token_env_var | is-not-empty) {
    $config.token_env_var
  } else {
    $"($module_name | str upcase | str replace --all --regex '[^A-Z0-9]' '_' | str replace --regex '_{2,}' '_' | str trim --char '_')_TOKEN"
  }

  let base_url = if ($config.default_base_url != null) and ($config.default_base_url | is-not-empty) { $config.default_base_url } else { $base_url }
  let all_urls = ([$base_url] | append $extra_urls | uniq)

  mut sections = []

  let completer_data = (collect-completers $commands)
  let completers = $completer_data.completers
  let mapping = $completer_data.mapping
  let completers_code = if ($completers | columns | length) > 0 {
    $"# Completers for enum parameters\n(render-completers $completers)\n"
  } else {
    ""
  }

  # base-url completer
  let per_op_urls = ($commands | where {|c| $c.base_url != null } | each {|c| $c.base_url } | uniq)
  let all_completer_urls = ($all_urls | append $per_op_urls | uniq)
  let base_url_vals = $all_completer_urls | each {|u| $'"($u)"' } | str join ' '
  let bool_completer = "def \"bool-completer\" [] { [\"'true'\" \"'false'\"] }"
  let base_url_completer = $'def "base-url-completer" [] { [($base_url_vals)] }'

  # auth-scheme completer
  let has_public = ($commands | where {|c| $c.default_auth == "none" } | length) > 0
  let auth_names = $auth_schemes | each {|s| $s.name } | uniq
  let auth_names_with_none = if $has_public { $auth_names | append "none" } else { $auth_names }
  let auth_completer_vals = if ($auth_names_with_none | length) > 0 {
    $auth_names_with_none | each {|n| $'"($n)"' } | str join ' '
  } else {
    '"bearer"'
  }
  let auth_completer = $'def "auth-scheme-completer" [] { [($auth_completer_vals)] }'

  let helpers_code = render-helpers $token_env_var $auth_schemes $default_auth $config.default_timeout $config.default_headers

  # Conditionally include unwrap-graphql helper for GraphQL commands
  let has_graphql = ($commands | any {|c| $c.method | str starts-with "graphql-" })
  let helpers_code = if $has_graphql {
    $helpers_code + "\n\n" + ([
      '# Unwrap a GraphQL response: extract data.{field} and surface errors'
      'def unwrap-graphql [resp: any, field: string] {'
      '  if ($resp | describe) == "string" { return $resp }'
      '  let errors = ($resp.errors? | default [])'
      '  if ($errors | length) > 0 {'
      '    let msgs = ($errors | each {|e| $e.message? | default "unknown error" } | str join "; ")'
      '    error make --unspanned { msg: $"GraphQL error: ($msgs)" }'
      '  }'
      '  $resp.data? | get -o $field | default $resp.data?'
      '}'
    ] | str join "\n")
  } else {
    $helpers_code
  }

  # Only generate introspection command when not disabled
  let introspection_code = if not $config.no_introspection {
    let first_cmd_name = ($commands | first | get name)
    [
      "# List all available API commands with their parameters"
      'export def "commands" []: nothing -> table {'
      '  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "accept" "help"]'
      $"  let mod_name = \(scope modules | where { $in.commands | any { $in.name == \"($first_cmd_name)\" } } | get name | first\)"
      '  let mod_cmds = (scope modules | where name == $mod_name | get commands | first)'
      '  let cmd_ids = ($mod_cmds | where name not-in [$mod_name "commands"] | get decl_id)'
      '  scope commands | where decl_id in $cmd_ids | each {|cmd|'
      '    let sig = $cmd.signatures | values | first'
      '    let params = $sig'
      '      | where parameter_type not-in ["input" "output"]'
      '      | where parameter_name not-in $builtin_flags'
      '      | select parameter_name parameter_type syntax_shape is_optional description'
      '    let return_type = ($sig | where parameter_type == "output" | get -o syntax_shape | first | default "any")'
      '    {'
      '      name: ($cmd.name | str replace $"($mod_name) " "")'
      '      description: $cmd.description'
      '      extra_description: $cmd.extra_description'
      '      return_type: $return_type'
      '      params: $params'
      '    }'
      '  }'
      '}'
      ""
    ] | str join "\n"
  } else {
    ""
  }

  $sections = ($sections | append ([
    $'# Auto-generated client for ($title) v($version_str)'
    $'# Source: ($spec_file)'
    $'# Auth: --token flag or $env.($token_env_var)'
    ""
    $'const BASE_URL = "($base_url)"'
    $'const DEFAULT_AUTH = "($default_auth)"'
    ""
    $helpers_code
    ""
    $bool_completer
    $base_url_completer
    $auth_completer
    ""
    $completers_code
    "# Root command for namespace resolution"
    $'export def main []: nothing -> nothing { print "($title) v($version_str) — ($commands | length) commands" }'
    ""
    $introspection_code
  ] | str join "\n"))

  for cmd in $commands {
    mut cmd_lines = []

    let is_graphql_cmd = ($cmd.method | str starts-with "graphql-")
    let summary = if ($cmd.description | is-not-empty) {
      $cmd.description | lines | str join " "
    } else if $is_graphql_cmd {
      $"GraphQL ($cmd.gql_op_type?) ($cmd.gql_field_name?)"
    } else {
      $"($cmd.method | str upcase) ($cmd.path_template)"
    }
    $cmd_lines = ($cmd_lines | append $"# ($summary)")

    mut extra = []
    if $cmd.deprecated {
      $extra = ($extra | append "# DEPRECATED")
    }
    if ($cmd.discriminator != null) {
      let d = $cmd.discriminator
      let mapping_keys = ($d.mapping | columns)
      if ($mapping_keys | length) > 0 {
        $extra = ($extra | append $"# Discriminator \(($d.context)\): ($d.propertyName) = ($mapping_keys | str join ', ')")
      } else {
        $extra = ($extra | append $"# Discriminator \(($d.context)\): ($d.propertyName)")
      }
    }
    if ($cmd.external_docs != null) {
      let url = ($cmd.external_docs.url? | default "")
      let edesc = ($cmd.external_docs.description? | default "")
      if ($url | is-not-empty) {
        if ($edesc | is-not-empty) {
          $extra = ($extra | append $"# Docs: ($url) — ($edesc)")
        } else {
          $extra = ($extra | append $"# Docs: ($url)")
        }
      }
    }
    if ($cmd.operation_id | is-not-empty) {
      $extra = ($extra | append $"# operationId: ($cmd.operation_id)")
    }
    if ($extra | length) > 0 {
      $cmd_lines = ($cmd_lines | append "#")
      $cmd_lines = ($cmd_lines | append $extra)
    }

    let sig = (build-signature $cmd $completers $mapping $config)
    $cmd_lines = ($cmd_lines | append $'export def "($cmd.name)" [')
    $cmd_lines = ($cmd_lines | append $sig)
    $cmd_lines = ($cmd_lines | append $"]: nothing -> ($cmd.return_type) {")

    let body_code = if $is_graphql_cmd { build-graphql-body-code $cmd $config } else { build-body-code $cmd $config }
    $cmd_lines = ($cmd_lines | append $body_code)
    $cmd_lines = ($cmd_lines | append "}")
    $cmd_lines = ($cmd_lines | append "")

    $sections = ($sections | append ($cmd_lines | str join "\n"))
  }

  $sections | str join "\n"
}
