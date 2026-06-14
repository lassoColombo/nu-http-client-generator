# render.nu — Code generation / rendering for the Nushell HTTP client module.
#
# All functions in this file take the command model (built by mod.nu + spec.nu)
# and produce Nushell source code strings.

# Build a NUON-like shape description from a list of body-field-like records.
# Example output: {name: string, tag?: string, status: "active"|"inactive"}
export def build-shape-doc [fields: list] {
  let entries = ($fields | each {|f|
    let nu_type = (openapi-to-nu-type $f.type)
    let suffix = if ($f.required? | default false) { "" } else { "?" }
    let type_str = if ($f.enum | length) > 0 {
      $f.enum | each { $'"($in)"' } | str join "|"
    } else {
      $nu_type
    }
    $"($f.name)($suffix): ($type_str)"
  } | str join ", ")
  $"{($entries)}"
}

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
  base_url token auth_scheme insecure max_time raw allow_errors dry_run accept
  # generated body-code internal variables
  auth base url qp full_url body extra_headers cookie_str accept_val
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
def render-param-record [params: list, prefix: string, --quote-keys] {
  $params | each {|p|
    let var = (effective-flag-var $p.name $prefix)
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
    $'def ($c.name) [] { [($vals)] }'
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
      $'  ($flag_name): ($nu_type)@($cname)($desc)'
    } else {
      $'  ($flag_name): ($nu_type)($desc)'
    }
  } else if $nu_type == "bool" {
    $'  --($flag_name): oneof<nothing, bool>($desc)'
  } else if ($cname | is-not-empty) {
    $'  --($flag_name): ($nu_type)@($cname)($desc)'
  } else {
    $'  --($flag_name): ($nu_type)($desc)'
  }
}

# Render a group of parameter flags/positionals for the signature.
# Each item in `params` must have: flag_name, shape_key (for lookup-shape),
# completer_key (record with name+enum for resolve-completer),
# plus the original param fields (type, description, deprecated?, required?, name).
# Returns {parts: list<string>, dep_flags: list<record>}.
def render-param-group [params: list, mapping: record, config: record, shapes: list] {
  mut parts = []
  mut dep_flags = []
  for q in $params {
    let nu_type = (openapi-to-nu-type $q.type)
    let flag_name = $q.flag_name
    let shape_hint = (lookup-shape $q.shape_key $shapes)
    let desc_text = if ($q.description | is-not-empty) { $q.description | lines | str join " " } else { "" }
    let desc_with_shape = if ($shape_hint != null) and ($desc_text | is-not-empty) { $"($desc_text) — ($shape_hint)" } else if ($shape_hint != null) { $shape_hint } else { $desc_text }
    let desc = if $config.no_descriptions { "" } else if ($desc_with_shape | is-not-empty) { $" # ($desc_with_shape)" } else { "" }
    let cname = if ($q.enum | length) > 0 { resolve-completer $q.completer_key $mapping } else { null }
    $parts = ($parts | append (render-param-sig $flag_name $nu_type $desc $cname))
    if ($q.deprecated? | default false) {
      $dep_flags = ($dep_flags | append {flag_name: $flag_name, reason: ($q.description? | default "")})
    }
  }
  {parts: $parts, dep_flags: $dep_flags}
}

# Look up a shape description for a flag name from the field_shapes list.
def lookup-shape [flag: string, shapes: list] {
  let matched = ($shapes | where { $in.flag == $flag })
  if ($matched | is-empty) { null } else {
    let s = ($matched | first)
    let label = if ($s.is_item? | default false) { "item shape" } else { "shape" }
    $"($label): ($s.shape)"
  }
}

# Build the signature string for a command.
# Returns {signature: string, deprecated_flags: list<record {flag_name: string, reason: string}>}.
export def build-signature [cmd: record, completers: record, mapping: record, config: record] {
  mut parts = []
  mut dep_flags = []
  let shapes = if $config.no_descriptions { [] } else { $cmd.field_shapes? | default [] }

  for p in $cmd.path_params {
    let nu_type = (openapi-to-nu-type $p.type)
    $parts = ($parts | append $"  ($p.name): ($nu_type)")
  }

  $parts = ($parts | append [
    '  --base-url(-b): string@base-url-completer # API base URL'
    '  --token(-t): string # Auth token'
    '  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme'
    '  --insecure(-k) # Skip TLS verification'
    '  --max-time(-m): duration # Timeout'
    '  --raw(-r) # Fetch as text'
    '  --allow-errors(-e) # Return full response without error handling'
    '  --dry-run(-n) # Return the request that would be sent without executing it'
  ])

  # Accept header flag (only when multiple response content types)
  if ($cmd.accept_types | length) > 1 {
    let cname = resolve-completer {name: "accept", enum: $cmd.accept_types} $mapping
    if ($cname | is-not-empty) {
      $parts = ($parts | append $'  --accept: string@($cname) # Response content type')
    } else {
      $parts = ($parts | append '  --accept: string # Response content type')
    }
  }

  # Query params
  let qp_items = ($cmd.query_params | each {|q| $q | merge {flag_name: (effective-flag-name $q.name "qp"), shape_key: ($q.name | str kebab-case), completer_key: $q} })
  let qp_result = (render-param-group $qp_items $mapping $config $shapes)
  $parts = ($parts | append $qp_result.parts)
  $dep_flags = ($dep_flags | append $qp_result.dep_flags)

  # Header params
  let hdr_items = ($cmd.header_params | each {|q| $q | merge {flag_name: (effective-flag-name $q.name "hdr"), shape_key: (effective-flag-name $q.name "hdr"), completer_key: $q} })
  let hdr_result = (render-param-group $hdr_items $mapping $config $shapes)
  $parts = ($parts | append $hdr_result.parts)
  $dep_flags = ($dep_flags | append $hdr_result.dep_flags)

  # Cookie params
  let ck_items = ($cmd.cookie_params | each {|q| $q | merge {flag_name: (effective-flag-name $q.name "ck"), shape_key: (effective-flag-name $q.name "ck"), completer_key: $q} })
  let ck_result = (render-param-group $ck_items $mapping $config $shapes)
  $parts = ($parts | append $ck_result.parts)
  $dep_flags = ($dep_flags | append $ck_result.dep_flags)

  if $cmd.has_body {
    let use_collapsed = ($config.body_threshold > 0) and (($cmd.body_fields | length) > $config.body_threshold)
    if $use_collapsed {
      let body_shape = (lookup-shape "body" $shapes)
      let body_desc = if ($body_shape != null) { $" # ($body_shape)" } else { " # Request body" }
      $parts = ($parts | append $"  --body: record($body_desc)")
    } else {
      let path_param_names = ($cmd.path_params | each {|p| $p.name })
      for f in $cmd.body_fields {
        let nu_type = (openapi-to-nu-type $f.type)
        let shape_hint = (lookup-shape $f.name $shapes)
        let desc_text = if ($f.description | is-not-empty) { $f.description | lines | str join " " } else { "" }
        let desc_with_shape = if ($shape_hint != null) and ($desc_text | is-not-empty) { $"($desc_text) — ($shape_hint)" } else if ($shape_hint != null) { $shape_hint } else { $desc_text }
        let desc = if $config.no_descriptions { "" } else if ($desc_with_shape | is-not-empty) { $" # ($desc_with_shape)" } else { "" }
        let sanitized_name = (to-var-name $f.name)
        let collides = ($sanitized_name in $path_param_names) or ($sanitized_name in $RESERVED_VARS) or ($sanitized_name | is-empty)
        let cname = if ($f.enum | length) > 0 { resolve-completer $f $mapping } else { null }
        let is_nullable = ($f.nullable? | default false)
        if $f.required and (not $collides) and ($nu_type != "bool") and (not $is_nullable) {
          $parts = ($parts | append (render-param-sig $sanitized_name $nu_type $desc $cname --positional))
          # @deprecated --flag doesn't work on positional params — skip
        } else {
          let flag_name = if $collides { $"body-(to-flag-name $f.name)" } else { to-flag-name $f.name }
          $parts = ($parts | append (render-param-sig $flag_name $nu_type $desc $cname))
          if ($f.deprecated? | default false) {
            $dep_flags = ($dep_flags | append {flag_name: $flag_name, reason: ($f.description? | default "")})
          }
        }
      }
      if ($cmd.body_fields | length) == 0 {
        $parts = ($parts | append "  --body: record")
      }
    }
  }

  {signature: ($parts | str join "\n"), deprecated_flags: $dep_flags}
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
    '  let n = ($name | url encode)'
    '  let is_list = ($value | describe | str starts-with "list")'
    '  if ($value | describe | str starts-with "record") { return ($value | transpose k v | each { $"($n)[($in.k | into string | url encode)]=($in.v | into string | url encode)" }) }'
    '  if not $is_list { return [$"($n)=($value | into string | url encode)"] }'
    '  match $style {'
    '    "multi" => { $value | each {|v| $"($n)=($v | into string | url encode)" } }'
    '    "csv" => { let joined = ($value | each { $in | into string | url encode } | str join ","); [$"($n)=($joined)"] }'
    '    "ssv" => { let joined = ($value | each { $in | into string | url encode } | str join "%20"); [$"($n)=($joined)"] }'
    '    "tsv" => { let joined = ($value | each { $in | into string | url encode } | str join "%09"); [$"($n)=($joined)"] }'
    '    "pipes" => { let joined = ($value | each { $in | into string | url encode } | str join "|"); [$"($n)=($joined)"] }'
    '    "deepObject" => { $value | each {|v| $"($n)[]=($v | into string | url encode)" } }'
    '    _ => { $value | each {|v| $"($n)=($v | into string | url encode)" } }'
    '  }'
    '}'
    ''
    '# Build URL from base, path, and optional query string'
    'def build-url [base: string, path: string, query?: string]: nothing -> string {'
    '  let parsed = ($base | url parse | reject params)'
    "  let full_path = if ($path | is-empty) { $parsed.path } else { [$parsed.path $path] | str join \"/\" | str replace --all --regex '/+' '/' }"
    '  let result = ($parsed | upsert path $full_path)'
    '  if ($query != null) and ($query | is-not-empty) { $result | upsert query $query | url join } else { $result | url join }'
    '}'
    ''
    '# Execute HTTP request with method dispatch'
    'def do-request [method: string, url: string, auth: record, insecure: bool, raw: bool, dry_run: bool, max_time?: duration, allow_errors?: bool, content_type?: string, body?: any]: nothing -> any {'
    '  let req_url = if ($auth.query | is-not-empty) { if ($url | str contains "?") { $"($url)&($auth.query)" } else { $"($url)?($auth.query)" } } else { $url }'
    ('  let timeout = ($max_time | default ' + $default_timeout + ')')
    '  let ct = ($content_type | default "application/json")'
  ] | if ($default_headers | columns | length) > 0 {
    let header_pairs = ($default_headers | transpose k v | each {|h| $'"($h.k)": "($h.v)"' } | str join ", ")
    $in | append ('  let auth = {headers: ({' + $header_pairs + '} | merge $auth.headers), query: $auth.query}')
  } else {
    $in
  } | append [
    '  if $dry_run { return {method: $method, url: $req_url, headers: $auth.headers, query_string: $auth.query, content_type: $ct, timeout: $timeout, body: $body} }'
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

  if $cmd.has_body {
    $lines = ($lines | append '  let input = $in')
  }

  $lines = ($lines | append ($"  let auth = \(build-auth $token \($auth_scheme | default \"($cmd.default_auth)\"\)\)"))
  if ($cmd.base_url | is-not-empty) {
    $lines = ($lines | append ($"  let base = \($base_url | default \"($cmd.base_url)\"\)"))
  } else {
    $lines = ($lines | append '  let base = ($base_url | default $BASE_URL)')
  }

  let path_expr = if ($cmd.path_params | length) > 0 {
    mut path_str = $cmd.path_template
    for p in $cmd.path_params {
      let orig = ($p.original_name? | default $p.name)
      let placeholder = $'{($orig)}'
      let replacement = $"\($($p.name)\)"
      $path_str = ($path_str | str replace $placeholder $replacement)
    }
    $"$\"($path_str)\""
  } else {
    $"\"($cmd.path_template)\""
  }

  if ($cmd.query_params | length) > 0 {
    let calls = $cmd.query_params | each {|q|
      let var_name = $"$(effective-flag-var $q.name "qp")"
      $"\(serialize-qp \"($q.name)\" ($var_name) \"($q.collection_style)\"\)"
    } | str join " "
    $lines = ($lines | append ($"  let qp = [($calls)] | flatten | str join \"&\""))
    $lines = ($lines | append ($"  let full_url = \(build-url $base ($path_expr) $qp\)"))
  } else {
    $lines = ($lines | append ($"  let full_url = \(build-url $base ($path_expr)\)"))
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
      $lines = ($lines | append ($"  let body = {($body_parts)} | compact"))
    }
  }

  if $cmd.has_body {
    $lines = ($lines | append '  let body = if ($input | describe | str starts-with "record") { $input | merge deep ($body | default {}) } else { $body }')
  }

  if ($cmd.header_params | length) > 0 {
    let hp_record = (render-param-record $cmd.header_params "hdr" --quote-keys)
    $lines = ($lines | append ($"  let extra_headers = {($hp_record)} | compact"))
    $lines = ($lines | append '  let auth = ($auth | update headers ($auth.headers | merge $extra_headers))')
  }

  if ($cmd.cookie_params | length) > 0 {
    let cp_record = (render-param-record $cmd.cookie_params "ck")
    $lines = ($lines | append ($"  let cookie_str = {($cp_record)} | transpose k v | where { $in.v != null } | each { $\"\($in.k\)=\($in.v\)\" } | str join \"; \""))
    $lines = ($lines | append '  let auth = if ($cookie_str | is-not-empty) { $auth | update headers ($auth.headers | merge {Cookie: $cookie_str}) } else { $auth }')
  }

  let default_accept = ($cmd.accept_types | first)
  if ($cmd.accept_types | length) > 1 {
    $lines = ($lines | append ($"  let accept_val = \($accept | default \"($default_accept)\"\)"))
  } else {
    $lines = ($lines | append ($"  let accept_val = \"($default_accept)\""))
  }
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
  $lines = ($lines | append $'  do-request "($cmd.method)" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors "($cmd.content_type)"($body_arg)')

  $lines | str join "\n"
}

# Render the module header: comment header, constants, helpers, completers, introspection command.
def render-module-header [
  title: string, version_str: string, spec_file: string, token_env_var: string,
  base_url: string, default_auth: string, all_urls: list, commands: list,
  auth_schemes: list, completers: record, helpers_code: string,
  config: record
] {
  let completers_code = if ($completers | columns | length) > 0 {
    $"# Completers for enum parameters\n(render-completers $completers)\n"
  } else {
    ""
  }

  # base-url completer
  let per_op_urls = ($commands | where {|c| $c.base_url != null } | each {|c| $c.base_url } | uniq)
  let all_completer_urls = ($all_urls | append $per_op_urls | uniq)
  let base_url_vals = $all_completer_urls | each {|u| $'"($u)"' } | str join ' '
  let base_url_completer = $'def base-url-completer [] { [($base_url_vals)] }'

  # auth-scheme completer
  let has_public = ($commands | where {|c| $c.default_auth == "none" } | length) > 0
  let auth_names = $auth_schemes | each {|s| $s.name } | uniq
  let auth_names_with_none = if $has_public { $auth_names | append "none" } else { $auth_names }
  let auth_completer_vals = if ($auth_names_with_none | length) > 0 {
    $auth_names_with_none | each {|n| $'"($n)"' } | str join ' '
  } else {
    '"bearer"'
  }
  let auth_completer = $'def auth-scheme-completer [] { [($auth_completer_vals)] }'

  # Only generate introspection command when not disabled
  let introspection_code = if not $config.no_introspection {
    let first_cmd_name = ($commands | first | get name)
    [
      "# List all available API commands with their parameters"
      'export def commands []: nothing -> table {'
      '  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "dry-run" "accept" "help"]'
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

  [
    $'# Auto-generated client for ($title) v($version_str)'
    $'# Source: ($spec_file)'
    $'# Auth: --token flag or $env.($token_env_var)'
    ""
    $'const BASE_URL = "($base_url)"'
    $'const DEFAULT_AUTH = "($default_auth)"'
    ""
    $helpers_code
    ""
    $base_url_completer
    $auth_completer
    ""
    $completers_code
    $introspection_code
  ] | str join "\n"
}

# Render a single command as a complete string (doc comment + annotations + export def + signature + body).
def render-command [cmd: record, completers: record, mapping: record, config: record] {
  mut cmd_lines = []

  let endpoint_line = $"($cmd.method | str upcase) ($cmd.path_template)"
  let summary = if ($cmd.description | is-not-empty) {
    $cmd.description | lines | str join " "
  } else {
    $endpoint_line
  }
  $cmd_lines = ($cmd_lines | append $"# ($summary)")

  # Add endpoint line so it always appears in help output
  mut extra = ($cmd.extra_doc_lines? | default [])
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
  # Shape docs for complex-typed flags (record/list with known sub-structure)
  if not $config.no_descriptions {
    for shape in ($cmd.field_shapes? | default []) {
      let label = if ($shape.is_item? | default false) { "item shape" } else { "shape" }
      $extra = ($extra | append $"# --($shape.flag) ($label): ($shape.shape)")
    }
  }
  if ($extra | length) > 0 {
    $cmd_lines = ($cmd_lines | append "#")
    $cmd_lines = ($cmd_lines | append $extra)
  }

  let sig_result = (build-signature $cmd $completers $mapping $config)

  # Emit @deprecated attributes (must come immediately before export def)
  mut annotations = []
  if $cmd.deprecated {
    let reason = ($cmd.deprecation_reason? | default null)
    if ($reason != null) and ($reason | is-not-empty) {
      let escaped = ($reason | str replace --all '"' '\"' | str replace --all "\n" " ")
      $annotations = ($annotations | append $'@deprecated "($escaped)"')
    } else {
      $annotations = ($annotations | append '@deprecated')
    }
  }
  for df in $sig_result.deprecated_flags {
    $annotations = ($annotations | append $'@deprecated --flag ($df.flag_name)')
  }
  if ($annotations | length) > 0 {
    $cmd_lines = ($cmd_lines | append $annotations)
  }

  $cmd_lines = ($cmd_lines | append $'export def "($cmd.name)" [')
  $cmd_lines = ($cmd_lines | append $sig_result.signature)
  let input_type = if $cmd.has_body { "any" } else { "nothing" }
  $cmd_lines = ($cmd_lines | append $"]: ($input_type) -> ($cmd.return_type) {")

  let body_code = (build-body-code $cmd $config)
  $cmd_lines = ($cmd_lines | append $body_code)
  $cmd_lines = ($cmd_lines | append "}")
  $cmd_lines = ($cmd_lines | append "")

  $cmd_lines | str join "\n"
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

  let completer_data = (collect-completers $commands)
  let completers = $completer_data.completers
  let mapping = $completer_data.mapping

  let helpers_code = render-helpers $token_env_var $auth_schemes $default_auth $config.default_timeout $config.default_headers

  let header = render-module-header $title $version_str $spec_file $token_env_var $base_url $default_auth $all_urls $commands $auth_schemes $completers $helpers_code $config

  let command_sections = ($commands | each {|cmd| render-command $cmd $completers $mapping $config })

  [$header] | append $command_sections | str join "\n"
}
