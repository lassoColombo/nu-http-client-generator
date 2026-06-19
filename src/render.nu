# render.nu — Code generation / rendering for the Nushell HTTP client module.
#
# All functions in this file take the command model (built by mod.nu + spec.nu)
# and produce Nushell source code strings.

# Build a NUON-like shape description from a list of body-field-like records.
# Example output: {name: string, tag?: string, status: "active"|"inactive"}
#
# Caps total output width to keep help text readable in a terminal. Wide
# records (DocuSign's account-settings has 200+ fields, ~25k chars) get
# truncated with a `... (N more fields)` tail so users still see the leading
# fields and the count of what's hidden.
export def build-shape-doc [fields: list, --max-width: int = 500] {
  let entries = ($fields | each {|f|
    let nu_type = (nu-type-for $f.type ($f.items_type? | default null))
    let suffix = if ($f.required? | default false) { "" } else { "?" }
    let type_str = if ($f.enum | is-not-empty) {
      $f.enum | each { $'"($in)"' } | str join "|"
    } else {
      $nu_type
    }
    $"($f.name)($suffix): ($type_str)"
  })
  let total = ($entries | length)
  mut kept = []
  mut len = 0
  for entry in $entries {
    let entry_len = ($entry | str length)
    let proj = $len + $entry_len + (if ($kept | is-empty) { 0 } else { 2 })
    if ($proj > $max_width) and ($kept | is-not-empty) {
      let remaining = ($total - ($kept | length))
      $kept = ($kept | append $"... \(($remaining) more fields\)")
      break
    }
    $kept = ($kept | append $entry)
    $len = $proj
  }
  $"{($kept | str join ', ')}"
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

# Map an OpenAPI (type, items.type) pair to a Nushell type. Emits parameterized
# `list<string>` / `list<int>` etc. when the items have a usable primitive
# type; falls back to bare `list` for record/$ref/unknown item types — the
# extra-doc `shape:` line covers those.
export def nu-type-for [t: string, items_t?: string]: nothing -> string {
  let base = (openapi-to-nu-type $t)
  if $base != "list" { return $base }
  if ($items_t | is-empty) { return "list" }
  let inner = (openapi-to-nu-type $items_t)
  match $inner {
    "string" | "int" | "float" | "bool" | "path" => $"list<($inner)>"
    _ => "list"
  }
}

# Nushell reserved names that cannot be standalone command/flag names
const RESERVED_NAMES = [in nu nothing]

# Variable names reserved in generated commands — body/query/header fields that
# match any of these get a prefix to avoid shadowing.
const RESERVED_VARS = [
  # nushell language keywords and built-in variables
  in nu nothing null true false env
  if else match for while loop break continue return
  let mut const def export use module source overlay
  where each error try catch not do
  # generated signature flags
  base_url token auth_scheme insecure max_time raw allow_errors full dry_run accept
  # generated body-code internal variables. `body` was renamed to `req_body`
  # to free up spec-side `body` fields (GitHub discussion post body, etc.) —
  # the user-facing `--body` flag no longer collides with anything internal.
  auth base qp full_url req_body extra_headers cookie_str accept_val
  # nushell builtins that cause issues as variable names
  sort from to get open save into split str
]

# Convert param names to valid nushell flag names
export def to-flag-name [name: string] {
  let cleaned = ($name | str kebab-case)
  if ($cleaned in $RESERVED_NAMES) or ($cleaned | is-empty) {
    $"($cleaned)-param" | str trim --char '-'
  } else {
    $cleaned
  }
}

# Sanitize a field name to a valid nushell variable name (underscores, no special chars)
def to-var-name [name: string] {
  $name | str snake-case
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

# Disambiguate a flag name against an already-seen set. Returns
# {flag_name, suffix} — suffix is the disambiguating tail ("" if untouched,
# otherwise "-list", "-2", "-3", ...). Issue 27.A: two query params whose
# kebab-case forms collide (e.g. `dataSegmentCode` and `dataSegmentCode[]`)
# would otherwise both bind the same flag, silently dropping the user's
# value. The array-shaped variant gets `-list`; subsequent collisions get
# `-2`, `-3`, etc.
def disambiguate-flag-name [proposed: string, is_array: bool, seen: list<string>]: nothing -> record {
  if not ($proposed in $seen) { return {flag_name: $proposed, suffix: ""} }
  if $is_array {
    let candidate = $"($proposed)-list"
    if not ($candidate in $seen) { return {flag_name: $candidate, suffix: "-list"} }
  }
  mut n = 2
  mut result: record<flag_name: string, suffix: string> = {flag_name: "", suffix: ""}
  mut done = false
  while not $done {
    let candidate = $"($proposed)-($n)"
    if not ($candidate in $seen) {
      $result = {flag_name: $candidate, suffix: $"-($n)"}
      $done = true
    } else {
      $n = $n + 1
    }
  }
  $result
}

# Walk a list of params (query/header/cookie) and assign each a
# collision-free flag_name and flag_var, threading a seen-names set so
# later groups (and the body) avoid colliding with earlier groups. Returns
# {items, seen} where items has the original params merged with
# {flag_name, flag_var, name_suffix} — `name_suffix` is the disambiguating
# tail (empty when no collision) so callers can append origin notes to the
# description text. Issue 27.A.
def decorate-param-group [params: list, prefix: string, seen: list<string>]: nothing -> record {
  mut items = []
  mut acc = $seen
  for p in $params {
    let proposed = (effective-flag-name $p.name $prefix)
    let is_array = (($p.items_type? | default null) != null) or (($p.name | str ends-with "[]"))
    let res = (disambiguate-flag-name $proposed $is_array $acc)
    let flag_var = ($res.flag_name | str replace --all '-' '_')
    $items = ($items | append ($p | merge {flag_name: $res.flag_name, flag_var: $flag_var, name_suffix: $res.suffix}))
    $acc = ($acc | append $res.flag_name)
  }
  {items: $items, seen: $acc}
}

# Names that cannot appear as a positional parameter on a generated `def`.
# Narrower than RESERVED_VARS — body-code `let` bindings can safely shadow
# positionals, so we only block actual language keywords, built-in variables,
# and the universal signature flags that share the same def block.
const RESERVED_POSITIONALS = [
  in nu nothing null true false env
  if else match for while loop break continue return
  let mut const def export use module overlay
  base_url token auth_scheme insecure max_time raw allow_errors full dry_run accept
]

# Effective positional path-param variable name. Sanitizes the path param's
# variable form and, if it collides with a Nushell reserved name, suffixes
# with `_arg` so the placeholder name stays at the front — the user reading
# `<source_arg>` can map it to URL `{source}` at a glance.
export def effective-positional-var [name: string] {
  let sanitized = (to-var-name $name)
  let cleaned = if ($sanitized | is-empty) { "param" } else { $sanitized }
  if ($cleaned in $RESERVED_POSITIONALS) { $"($cleaned)_arg" } else { $cleaned }
}

# Render a list of params as a nushell record literal string (e.g. "key": $var, ...)
#
# Header- and cookie-param values are emitted into a record that's then merged
# into `--headers`. Nushell's `http get --headers {…}` silently drops values
# typed `list<…>` (Issue 18.A), so array-typed params must be serialized to a
# single string. Per OpenAPI `style: simple` (default for headers) and RFC 7230
# §3.2.6, multi-value headers are comma-joined regardless of `explode` — HTTP
# headers can't repeat. The runtime check handles `null` (compact-friendly) and
# scalar values unchanged, so this is safe even when the user passes a single
# string into a list-typed flag.
def render-param-record [params: list, --quote-keys] {
  $params | each {|p|
    let var = $p.flag_var
    let value_expr = if (($p.items_type? | default null) != null) {
      $"\(if \($($var) | describe | str starts-with \"list\"\) { $($var) | each { into string } | str join \",\" } else { $($var) }\)"
    } else {
      $"$($var)"
    }
    if $quote_keys {
      $'($p.name | to nuon): ($value_expr)'
    } else {
      $'($p.name): ($value_expr)'
    }
  } | str join ", "
}

# Collect all unique enum sets and map each (flag_name, enum_values) to a completer name.
export def collect-completers [commands: list] {
  let initial = {completers: {}, mapping: {}, name_counts: {}}
  let final = ($commands | reduce -f $initial {|cmd, state|
    let accept_source = if ($cmd.accept_types | length) > 1 { [{name: "accept", enum: $cmd.accept_types}] } else { [] }
    let enum_sources = ($cmd.query_params | append $cmd.body_fields
      | append $cmd.header_params | append $cmd.cookie_params | append $accept_source)
    $enum_sources | reduce -f $state {|q, st|
      if ($q.enum | is-empty) { return $st }
      let flag_name = (to-flag-name $q.name)
      let vals = ($q.enum | each { $"($in)" } | sort)
      let fingerprint = $"($flag_name):($vals | str join ',')"
      if ($fingerprint in ($st.mapping | columns)) { return $st }
      let count = ($st.name_counts | get -o $flag_name | default 0)
      let cname = if $count == 0 {
        $"($flag_name)-completer"
      } else {
        $"($flag_name)-completer-($count)"
      }
      $st | merge {
        name_counts: ($st.name_counts | upsert $flag_name ($count + 1))
        completers: ($st.completers | insert $cname $vals)
        mapping: ($st.mapping | insert $fingerprint $cname)
      }
    }
  })
  {completers: $final.completers, mapping: $final.mapping}
}

# Render completer functions as nushell source.
# Values may contain embedded double-quotes or backslashes (e.g. specs that
# include `"\"Latency\""` as an enum value). Escape those so the emitted
# string literal is well-formed.
export def render-completers [completers: record] {
  $completers | items {|name, values|
    let vals = ($values | each {|v| ($v | to nuon) } | str join ' ')
    $'def ($name) [] { [($vals)] }'
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
    let nu_type = (nu-type-for $q.type ($q.items_type? | default null))
    let flag_name = $q.flag_name
    let shape_hint = (lookup-shape $q.shape_key $shapes)
    let desc_text = if ($q.description | is-not-empty) { $q.description | lines | str join " " } else { "" }
    # Append origin note when this flag was disambiguated via suffix
    # (issue 27.A) so users can tell which spec-side parameter the flag
    # actually maps to.
    let suffix_note = match ($q.name_suffix? | default "") {
      "" => ""
      "-list" => " (array variant)"
      $s => $" \(disambiguated($s)\)"
    }
    let desc_with_shape = if ($shape_hint != null) and ($desc_text | is-not-empty) { $"($desc_text) — ($shape_hint)" } else if ($shape_hint != null) { $shape_hint } else { $desc_text }
    let desc_final = $"($desc_with_shape)($suffix_note)"
    let desc = if $config.no_descriptions { "" } else if ($desc_final | is-not-empty) { $" # ($desc_final)" } else { "" }
    let cname = if ($q.enum | is-not-empty) { resolve-completer $q.completer_key $mapping } else { null }
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
    let pname = (effective-positional-var $p.name)
    $parts = ($parts | append $"  ($pname): ($nu_type)")
  }

  $parts = ($parts | append [
    '  --base-url(-b): string@base-url-completer # API base URL'
    '  --token(-t): string # Auth token'
    '  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme'
    '  --insecure(-k) # Skip TLS verification'
    '  --max-time(-m): duration # Timeout'
    '  --raw(-r) # Fetch as text'
    '  --allow-errors(-e) # Return full response without error handling'
    '  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx'
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

  # Query params — decorate with collision-aware flag names, threading
  # the seen-flag-name set into header/cookie/body groups so cross-group
  # collisions (e.g. body field `NextToken` vs query param `NextToken`,
  # AWS Smithy pattern) get suffixed instead of silently dropping values.
  # Issue 27.A.
  let qp_decorated = (decorate-param-group ($cmd.query_params | each {|q| $q | merge {shape_key: ($q.name | str kebab-case), completer_key: $q} }) "qp" [])
  let qp_result = (render-param-group $qp_decorated.items $mapping $config $shapes)
  $parts = ($parts | append $qp_result.parts)
  $dep_flags = ($dep_flags | append $qp_result.dep_flags)

  # Header params
  let hdr_decorated = (decorate-param-group ($cmd.header_params | each {|q| $q | merge {completer_key: $q} | insert shape_key (effective-flag-name $q.name "hdr") }) "hdr" $qp_decorated.seen)
  let hdr_result = (render-param-group $hdr_decorated.items $mapping $config $shapes)
  $parts = ($parts | append $hdr_result.parts)
  $dep_flags = ($dep_flags | append $hdr_result.dep_flags)

  # Cookie params
  let ck_decorated = (decorate-param-group ($cmd.cookie_params | each {|q| $q | merge {completer_key: $q} | insert shape_key (effective-flag-name $q.name "ck") }) "ck" $hdr_decorated.seen)
  let ck_result = (render-param-group $ck_decorated.items $mapping $config $shapes)
  $parts = ($parts | append $ck_result.parts)
  $dep_flags = ($dep_flags | append $ck_result.dep_flags)

  if $cmd.has_body {
    let use_collapsed = ($config.body_threshold > 0) and (($cmd.body_fields | length) > $config.body_threshold)
    if $use_collapsed {
      let body_shape = (lookup-shape "body" $shapes)
      let body_desc = if ($body_shape != null) { $" # ($body_shape)" } else { " # Request body" }
      $parts = ($parts | append $"  --body: record($body_desc)")
    } else {
      let path_param_names = ($cmd.path_params | each {|p| (effective-positional-var $p.name) })
      mut body_seen = $ck_decorated.seen
      for f in $cmd.body_fields {
        let nu_type = (nu-type-for $f.type ($f.items_type? | default null))
        let shape_hint = (lookup-shape $f.name $shapes)
        let desc_text = if ($f.description | is-not-empty) { $f.description | lines | str join " " } else { "" }
        let desc_with_shape = if ($shape_hint != null) and ($desc_text | is-not-empty) { $"($desc_text) — ($shape_hint)" } else if ($shape_hint != null) { $shape_hint } else { $desc_text }
        let sanitized_name = (to-var-name $f.name)
        let flag_var = (to-flag-var $f.name)
        let proposed_flag = (to-flag-name $f.name)
        # Pre-existing reserved-word collision (path positional / language
        # keyword): keep the `body-` PREFIX disambiguation that's been in
        # place since the generator's earliest cycles — emitting clients
        # already use those names, so changing the disambiguation would
        # break callers.
        let reserved_collision = ($sanitized_name in $path_param_names) or ($sanitized_name in $RESERVED_VARS) or ($flag_var in $RESERVED_VARS) or ($sanitized_name | is-empty)
        # Issue 27.A: a body field whose flag-name matches one already
        # used by query/header/cookie is a NEW collision class. Suffix
        # with `-body` (so `--max-items` query stays, body becomes
        # `--max-items-body`). This silently-data-loss bug previously
        # affected 216 client files / 1778 operations.
        let cross_group_collision = (not $reserved_collision) and ($proposed_flag in $body_seen)
        let collides = $reserved_collision or $cross_group_collision
        let cname = if ($f.enum | is-not-empty) { resolve-completer $f $mapping } else { null }
        let is_nullable = ($f.nullable? | default false)
        if $f.required and (not $collides) and ($nu_type != "bool") and (not $is_nullable) {
          let desc = if $config.no_descriptions { "" } else if ($desc_with_shape | is-not-empty) { $" # ($desc_with_shape)" } else { "" }
          $parts = ($parts | append (render-param-sig $sanitized_name $nu_type $desc $cname --positional))
          $body_seen = ($body_seen | append $sanitized_name)
          # @deprecated --flag doesn't work on positional params — skip
        } else {
          let flag_name = if $cross_group_collision {
            $"($proposed_flag)-body"
          } else if $reserved_collision {
            $"body-($proposed_flag)"
          } else {
            $proposed_flag
          }
          let body_note = if $cross_group_collision { " (body field)" } else { "" }
          let desc_with_note = $"($desc_with_shape)($body_note)"
          let desc = if $config.no_descriptions { "" } else if ($desc_with_note | is-not-empty) { $" # ($desc_with_note)" } else { "" }
          $parts = ($parts | append (render-param-sig $flag_name $nu_type $desc $cname))
          $body_seen = ($body_seen | append $flag_name)
          if ($f.deprecated? | default false) {
            $dep_flags = ($dep_flags | append {flag_name: $flag_name, reason: ($f.description? | default "")})
          }
        }
      }
      if ($cmd.body_fields | is-empty) {
        # Issue 25.A: when the body schema is non-record (e.g. `type: string`
        # for a `text/plain` body), emit a typed flag matching the scalar so
        # callers can pass a raw value. For non-JSON content-types whose
        # schema IS record-shaped (e.g. AWS text/xml AttachInstancesQuery),
        # emit `--body: any` — `http post --content-type text/xml <record>`
        # rejects records, so the caller has to pre-serialize to a string;
        # `any` lets them pass either a record or a string. JSON-family
        # records keep the historical `--body: record` typing.
        let scalar = ($cmd.body_scalar_type? | default "any")
        let ct = ($cmd.content_type? | default "")
        let body_t = if ($scalar == "any") {
          if ($ct | str starts-with "application/json") or ($ct == "multipart/form-data") or ($ct == "application/x-www-form-urlencoded") or ($ct | is-empty) { "record" } else { "any" }
        } else {
          (nu-type-for $scalar)
        }
        $parts = ($parts | append $"  --body: ($body_t)")
      }
    }
  }

  {signature: ($parts | str join "\n"), deprecated_flags: $dep_flags}
}

# Render the helper functions that go into every generated client.
# `needs_multipart` controls emission of the `build-multipart-body` helper —
# only generated when at least one operation uses `multipart/form-data` so
# clients that never upload files stay slim.
export def render-helpers [token_env_var: string, auth_schemes: list, default_timeout: string, default_headers: record, needs_multipart: bool = false] {
  mut match_arms = []
  mut seen_names = []
  for s in $auth_schemes {
    if not ($s.name in $seen_names) {
      $seen_names = ($seen_names | append $s.name)
      if $s.in == "query" {
        $match_arms = ($match_arms | append ($"    \"($s.name)\" => { {headers: {}, query: $\"\(encode-path-segment \"($s.header_name)\"\)=\(encode-path-segment $token_val\)\"} }"))
      } else if $s.in == "cookie" {
        $match_arms = ($match_arms | append ($"    \"($s.name)\" => { {headers: {Cookie: $\"\(encode-path-segment \"($s.header_name)\"\)=\(encode-path-segment $token_val\)\"}, query: \"\"} }"))
      } else if $s.prefix == "" {
        $match_arms = ($match_arms | append $"    \"($s.name)\" => { {headers: {($s.header_name): $token_val}, query: \"\"} }")
      } else {
        $match_arms = ($match_arms | append ($"    \"($s.name)\" => { {headers: {($s.header_name): $\"($s.prefix) \($token_val\)\"}, query: \"\"} }"))
      }
    }
  }
  # When the spec advertises HTTP Basic, expose a sibling `basic-credentials`
  # scheme that base64-encodes the token per RFC 7617. `basic` itself stays as
  # the literal-prefix path for users who already pre-encode (no behaviour
  # change). Pick `basic-credentials` when you'd rather pass `user:pass` raw.
  let has_basic = ($auth_schemes | any {|s| $s.prefix == "Basic" and $s.in == "header" })
  if $has_basic and (not ("basic-credentials" in $seen_names)) {
    $seen_names = ($seen_names | append "basic-credentials")
    $match_arms = ($match_arms | append '    "basic-credentials" => { {headers: {Authorization: $"Basic ($token_val | encode base64)"}, query: ""} }')
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
    '# Uses encode-path-segment for keys and values: RFC 3986 unreserved chars'
    '# ([A-Za-z0-9-._~]) stay literal; everything else gets %XX.'
    'def serialize-qp [name: string, value: any, style: string]: nothing -> list<string> {'
    '  if ($value == null) { return [] }'
    '  let is_list = ($value | describe | str starts-with "list")'
    '  if $is_list and ($value | is-empty) { return [] }'
    '  let n = (encode-path-segment $name)'
    '  if ($value | describe | str starts-with "record") { return ($value | transpose k v | each { $"($n)[(encode-path-segment $in.k)]=(encode-path-segment $in.v)" }) }'
    '  if not $is_list { return [$"($n)=(encode-path-segment $value)"] }'
    '  match $style {'
    '    "multi" => { $value | each {|v| $"($n)=(encode-path-segment $v)" } }'
    '    "csv" => { let joined = ($value | each { encode-path-segment $in } | str join ","); [$"($n)=($joined)"] }'
    '    "ssv" => { let joined = ($value | each { encode-path-segment $in } | str join "%20"); [$"($n)=($joined)"] }'
    '    "tsv" => { let joined = ($value | each { encode-path-segment $in } | str join "%09"); [$"($n)=($joined)"] }'
    '    "pipes" => { let joined = ($value | each { encode-path-segment $in } | str join "|"); [$"($n)=($joined)"] }'
    '    "deepObject" => { $value | each {|v| $"($n)[]=(encode-path-segment $v)" } }'
    '    _ => { $value | each {|v| $"($n)=(encode-path-segment $v)" } }'
    '  }'
    '}'
    ''
    '# Percent-encode a path-segment value per RFC 3986.'
    '# Unreserved chars ([A-Za-z0-9-._~]) stay literal; everything else gets %XX.'
    '# Trick: `url encode --all` over-encodes, then we decode the four unreserved'
    '# punctuation chars back. Pre-existing %XX sequences in the input survive'
    '# because `url encode --all` first turns their % into %25.'
    'def encode-path-segment [v: any]: nothing -> string {'
    '  $v | into string | url encode --all | str replace --all "%2D" "-" | str replace --all "%2E" "." | str replace --all "%5F" "_" | str replace --all "%7E" "~"'
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
    'def do-request [method: string, url: string, auth: record, insecure: bool, raw: bool, dry_run: bool, max_time?: duration, allow_errors?: bool, full?: bool, content_type?: string, body?: any]: nothing -> any {'
    '  let req_url = if ($auth.query | is-not-empty) { if ($url | str contains "?") { $"($url)&($auth.query)" } else { $"($url)?($auth.query)" } } else { $url }'
    ('  let timeout = ($max_time | default ' + $default_timeout + ')')
    '  let ct = ($content_type | default "application/json")'
  ] | if ($default_headers | is-not-empty) {
    let header_pairs = ($default_headers | items {|k, v| $'"($k)": "($v)"' } | str join ", ")
    $in | append ('  let auth = {headers: ({' + $header_pairs + '} | merge $auth.headers), query: $auth.query}')
  } else {
    $in
  } | append [
    '  if $dry_run { return {method: $method, url: $req_url, headers: $auth.headers, query_string: $auth.query, content_type: $ct, timeout: $timeout, body: $body} }'
    '  let resp = match $method {'
    '    "get" => { http get --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url }'
    '    "head" => { http head --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure $req_url }'
    '    "options" => { http options --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure $req_url }'
    '    "post" => { if ($body | is-empty) { http post --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http post --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }'
    '    "put" => { if ($body | is-empty) { http put --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http put --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }'
    '    "patch" => { if ($body | is-empty) { http patch --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url "" } else { http patch --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body } }'
    '    "delete" => { if ($body | is-empty) { http delete --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } else { http delete --headers $auth.headers --content-type $ct --data $body --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } }'
    '  }'
    '  if ($method == "head") and (not $full) and (not $allow_errors) and $resp.status < 400 { return $resp.headers }'
    '  if $allow_errors { $resp } else if $resp.status >= 400 { error make --unspanned { msg: $"HTTP ($resp.status): ($resp.body)" } } else if $full { {status: $resp.status, headers: $resp.headers, body: $resp.body} } else if $resp.status == 204 { null } else { $resp.body }'
    '}'
  ] | append (if $needs_multipart { [
    ''
    '# Build a `multipart/form-data` envelope per RFC 7578. `file_fields` lists'
    '# the field names whose value should be read from disk as bytes; every'
    '# other field is sent as a text part (records/lists JSON-stringified).'
    '# Returns {content_type, body} ready to pass to `do-request`.'
    '# When `$dry_run` is true, file fields are NOT read from disk — they emit'
    '# an empty-bytes placeholder so callers can inspect the request shape'
    '# without the file existing on disk (issue 11.B).'
    'def build-multipart-body [parts: record, file_fields: list<string>, dry_run: bool = false]: nothing -> record {'
    '  let boundary = $"----nu-(random chars --length 24)"'
    '  let crlf = "\r\n"'
    '  let chunks = ($parts | items {|name, val|'
    '    if $val == null { null } else if $name in $file_fields {'
    '      let filename = ($val | into string | path basename)'
    '      let bytes = if $dry_run { (0x[] | into binary) } else { (open --raw $val | into binary | collect) }'
    '      let head = ($"--($boundary)($crlf)Content-Disposition: form-data; name=\"($name)\"; filename=\"($filename)\"($crlf)Content-Type: application/octet-stream($crlf)($crlf)" | into binary)'
    '      $head ++ $bytes ++ ($crlf | into binary)'
    '    } else {'
    '      let dt = ($val | describe)'
    '      let s = if (($dt | str starts-with "record") or ($dt | str starts-with "list") or ($dt | str starts-with "table")) { ($val | to json --raw) } else { ($val | into string) }'
    '      let head = ($"--($boundary)($crlf)Content-Disposition: form-data; name=\"($name)\"($crlf)($crlf)" | into binary)'
    '      $head ++ ($"($s)($crlf)" | into binary)'
    '    }'
    '  } | compact)'
    '  let trailer = ($"--($boundary)--($crlf)" | into binary)'
    '  let body = ($chunks | reduce --fold (0x[] | into binary) {|chunk, acc| $acc ++ $chunk }) ++ $trailer'
    '  {content_type: $"multipart/form-data; boundary=($boundary)", body: $body}'
    '}'
  ] } else { [] }) | str join "\n"
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

  # Issue 30.A: validate each required path param is non-empty before URL
  # substitution. Without this guard, `format pattern` substitutes the empty
  # string, leaving `/foo//bar` in the templated path which `build-url`'s
  # `/+ -> /` collapse then erases — silently routing the request to a
  # different endpoint. Naming the original spec param in the error gives the
  # caller a clear pointer to which arg was passed empty.
  for p in $cmd.path_params {
    let pvar = (effective-positional-var $p.name)
    let orig = ($p.original_name? | default $p.name)
    $lines = ($lines | append ($"  if \($($pvar) | is-empty\) { error make --unspanned { msg: \"path parameter '($orig)' must be non-empty\" } }"))
  }

  let path_expr = if ($cmd.path_params | is-not-empty) {
    # Emit a `format pattern` call so the path text is a plain string literal —
    # parens, quotes, backslashes pass through untouched (only `{` and `}` are
    # meta to format pattern). Translate each spec placeholder name to its
    # sanitized var name so it matches the record field.
    mut pattern = $cmd.path_template
    for p in $cmd.path_params {
      let orig = ($p.original_name? | default $p.name)
      let pvar = (effective-positional-var $p.name)
      $pattern = ($pattern | str replace $'{($orig)}' $'{($pvar)}')
    }
    let record_fields = ($cmd.path_params | each {|p|
      let pvar = (effective-positional-var $p.name)
      # Percent-encode each value per RFC 3986 segment grammar — without this
      # a path param like "feature/auth-fix" would render as a literal "/" in
      # the URL and break routing (issue #10-1). The path-template literal
      # (the `/{x}/{y}/` structure) stays intact; only the substituted values
      # get encoded.
      $"($pvar): \(encode-path-segment $($pvar)\)"
    } | str join ", ")
    $"\({($record_fields)} | format pattern ($pattern | to nuon)\)"
  } else {
    $cmd.path_template | to nuon
  }

  # Issue 27.A: decorate query/header/cookie param lists with
  # collision-aware flag_name/flag_var so the variable references emitted
  # here match the signature flags declared in build-signature. Walked in
  # the same priority order (query → header → cookie → body).
  let qp_decorated = (decorate-param-group $cmd.query_params "qp" [])
  let hdr_decorated = (decorate-param-group $cmd.header_params "hdr" $qp_decorated.seen)
  let ck_decorated = (decorate-param-group $cmd.cookie_params "ck" $hdr_decorated.seen)
  let pre_body_seen = $ck_decorated.seen

  if ($qp_decorated.items | is-not-empty) {
    let calls = $qp_decorated.items | each {|q|
      let var_name = $"$($q.flag_var)"
      $"\(serialize-qp \"($q.name)\" ($var_name) \"($q.collection_style)\"\)"
    } | str join " "
    $lines = ($lines | append ($"  let qp = [($calls)] | flatten | str join \"&\""))
    $lines = ($lines | append ($"  let full_url = \(build-url $base ($path_expr) $qp\)"))
  } else {
    $lines = ($lines | append ($"  let full_url = \(build-url $base ($path_expr)\)"))
  }

  # Build the initial $req_body before the input-merge line. Two paths:
  #   per-field: signature exposes individual --field flags; we assemble them
  #              into a record literal.
  #   collapsed: signature exposes a single `--body: record` flag, which
  #              Nushell binds to $body. We seed $req_body from $body so the
  #              merge line below has the same shape in both paths.
  # Without the seed in the collapsed branch, $req_body would be undefined
  # when the merge line tries to read it (regression #9-B).
  if $cmd.has_body {
    let use_collapsed = ($config.body_threshold > 0) and (($cmd.body_fields | length) > $config.body_threshold)
    let has_per_field = ($cmd.body_fields | is-not-empty) and (not $use_collapsed)
    if $has_per_field {
      let path_param_names = ($cmd.path_params | each {|p| (effective-positional-var $p.name) })
      # Mirror the body-field naming logic from build-signature so the
      # variable references here line up with the flag declarations.
      # Issue 27.A.
      mut body_seen = $pre_body_seen
      mut body_parts_list = []
      for item in ($cmd.body_fields | enumerate) {
        let f = $item.item
        let idx = $item.index
        let sanitized_name = (to-var-name $f.name)
        let flag_base = (to-flag-var $f.name)
        let proposed_flag = (to-flag-name $f.name)
        let reserved_collision = ($sanitized_name in $path_param_names) or ($sanitized_name in $RESERVED_VARS) or ($flag_base in $RESERVED_VARS) or ($sanitized_name | is-empty)
        let cross_group_collision = (not $reserved_collision) and ($proposed_flag in $body_seen)
        let collides = $reserved_collision or $cross_group_collision
        let nu_type = (openapi-to-nu-type $f.type)
        let is_nullable = ($f.nullable? | default false)
        let var_name = if $f.required and (not $collides) and ($nu_type != "bool") and (not $is_nullable) {
          $body_seen = ($body_seen | append $sanitized_name)
          $'$($sanitized_name)'
        } else if $cross_group_collision {
          let flag_var = $"($flag_base)_body"
          $body_seen = ($body_seen | append $"($proposed_flag)-body")
          $'$($flag_var)'
        } else if $reserved_collision {
          let flag_var = $'body_($flag_base)'
          $body_seen = ($body_seen | append $"body-($proposed_flag)")
          $'$($flag_var)'
        } else {
          $body_seen = ($body_seen | append $proposed_flag)
          $'$($flag_base)'
        }
        # Use the original spec field name as the body key, but fall back to a
        # synthetic name when it is empty (e.g. the field name was ":" and the
        # sanitizer reduced it to ""). Always quote the key so names with
        # spaces, slashes, or colons are valid Nushell record syntax.
        let key = if ($f.name | is-empty) { $"field-($idx + 1)" } else { $f.name }
        $body_parts_list = ($body_parts_list | append $'($key | to nuon): ($var_name)')
      }
      let body_parts = ($body_parts_list | str join ", ")
      $lines = ($lines | append ($"  let req_body = {($body_parts)} | compact"))
    } else {
      $lines = ($lines | append '  let req_body = $body')
    }
    # Pipeline-input merge: records merge deep into the assembled body. When
    # the spec declares `oneOf: [{object}, {array}]` (or anyOf), we also accept
    # a bare list and pass it straight through — the object variant remains
    # reachable via flags, and the array variant via pipeline. Issue 13.B.
    # Issue 25.A: when the body schema is a non-record scalar (string, int,
    # etc.) OR the content-type is non-JSON-family (`text/xml`, `text/plain`,
    # `application/vnd.X+json`, `application/octet-stream`, …), accept the
    # raw pipeline input as the body so callers can `"text" | op` without a
    # flag. Nushell's `http` only auto-encodes records for content-types
    # matching `application/json*`; for everything else the wire format is
    # the user's responsibility.
    let ct = ($cmd.content_type? | default "")
    let priority_ct = ($ct | str starts-with "application/json") or ($ct == "multipart/form-data") or ($ct == "application/x-www-form-urlencoded") or ($ct | is-empty)
    let non_record_body = (($cmd.body_scalar_type? | default "any") != "any")
    if ($cmd.body_polymorphic_array? | default false) {
      $lines = ($lines | append '  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else if ($input | describe | str starts-with "list") { $input } else { $req_body }')
    } else if (not $priority_ct) or $non_record_body {
      $lines = ($lines | append '  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else if (($input | is-not-empty) and ($req_body | is-empty)) { $input } else { $req_body }')
    } else {
      $lines = ($lines | append '  let req_body = if ($input | describe | str starts-with "record") { $input | merge deep ($req_body | default {}) } else { $req_body }')
    }
  }

  # Emit the hardcoded `Accept` default FIRST, then merge user-driven
   # `extra_headers` (which may carry the user's `--hdr-accept` value) on top.
   # Nushell's `merge` is right-biased — the last operand wins on key collision,
   # so this ordering guarantees user-supplied Accept (and any other header
   # param the user set) overrides the spec-default. Without this swap, the
   # hardcoded `accept_val` clobbered the user value (issue #11-7).
  let default_accept = ($cmd.accept_types | first)
  if ($cmd.accept_types | length) > 1 {
    $lines = ($lines | append ($"  let accept_val = \($accept | default \"($default_accept)\"\)"))
  } else {
    $lines = ($lines | append ($"  let accept_val = \"($default_accept)\""))
  }
  $lines = ($lines | append '  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))')

  if ($hdr_decorated.items | is-not-empty) {
    let hp_record = (render-param-record $hdr_decorated.items --quote-keys)
    $lines = ($lines | append ($"  let extra_headers = {($hp_record)} | compact"))
    $lines = ($lines | append '  let auth = ($auth | update headers ($auth.headers | merge $extra_headers))')
  }

  if ($ck_decorated.items | is-not-empty) {
    let cp_record = (render-param-record $ck_decorated.items --quote-keys)
    $lines = ($lines | append ($"  let cookie_str = {($cp_record)} | items {|k, v| if $v == null { null } else { $\"\($k\)=\($v\)\" } } | compact | str join \"; \""))
    $lines = ($lines | append '  let auth = if ($cookie_str | is-not-empty) { $auth | update headers ($auth.headers | merge {Cookie: $cookie_str}) } else { $auth }')
  }

  # multipart/form-data: encode the request body as an RFC 7578 envelope so
  # binary file fields are sent as bytes (not as a literal path string) and
  # other fields are JSON-stringified per the common multipart convention.
  # The `build-multipart-body` helper (emitted by `render-helpers` only when
  # this spec needs it) does the actual envelope construction at runtime.
  # Both Swagger-2 (`type: file`) and OAS3 (`type: string, format: binary`)
  # shapes contribute to the file-fields list. Issue #11-6.
  #
  # The gate keys on content-type alone, not on a non-empty file-fields list:
  # some multipart specs have empty/array/bare-binary body schemas (Jira
  # setColumns, Codat push-*-attachments, Jira addAttachment). The helper
  # accepts an empty `file_fields` list and still builds a well-formed
  # envelope (records JSON-stringified). Issue 11.A.
  let is_multipart = $cmd.has_body and ($cmd.content_type == "multipart/form-data")
  if $is_multipart {
    let file_field_names = ($cmd.body_fields | where {|f|
      ($f.type? | default "") == "file" or (($f.type? | default "") == "string" and ($f.format? | default null) == "binary")
    } | each {|f| $f.name })
    let file_list_lit = ($file_field_names | each {|n| $n | to nuon } | str join ' ')
    # Guard against $req_body being a non-record (bare array/string body, or
    # the empty-schema case where $req_body comes from `--body: record` but
    # the user might pass nothing). Coerce to {} so the helper's `transpose`
    # works; the empty body yields a multipart envelope with just the trailer.
    $lines = ($lines | append '  let req_body = if ($req_body | describe | str starts-with "record") { $req_body } else { {} }')
    $lines = ($lines | append ($"  let mp = \(build-multipart-body $req_body [($file_list_lit)] $dry_run\)"))
  }

  # Detect a user-facing `--content-type` flag. Some Swagger-2 specs declare
  # Content-Type as a header parameter rather than via `consumes` (Akeneo's
  # OAuth token endpoint is the canonical case). When that flag exists, the
  # user can override the spec's default at runtime — but the body still
  # needs to be serialized to match. Issue #11-8.
  let ct_matches = ($hdr_decorated.items | where {|p| ($p.name | str downcase) == "content-type" })
  let has_ct_override = ($ct_matches | is-not-empty) and $cmd.has_body
  let ct_var = if $has_ct_override {
    let v = ($ct_matches | first | get flag_var)
    $"$($v)"
  } else { null }

  if $has_ct_override {
    # Effective content-type for body serialization and the request.
    $lines = ($lines | append ($"  let effective_ct = \(($ct_var) | default \"($cmd.content_type)\"\)"))
    # Runtime serialization branch: when the user (or the spec default) picks
    # x-www-form-urlencoded, serialize the body record to `k=v&k=v`. Other
    # content types pass the body through unchanged — JSON is what Nushell's
    # `http post` already does by default.
    $lines = ($lines | append '  let req_body = if $effective_ct == "application/x-www-form-urlencoded" { $req_body | transpose k v | where v != null | reduce -f {} {|p, acc| $acc | upsert $p.k $p.v } | url build-query } else { $req_body }')
  } else if $cmd.has_body and ($cmd.content_type == "application/x-www-form-urlencoded") {
    # application/x-www-form-urlencoded: HTTP body must be a `k1=v1&k2=v2`
    # string, not a JSON record. Nushell's `http post --content-type "..."`
    # sets the header but doesn't reshape the body. Spec-conformance with
    # RFC 6749 (OAuth token endpoints) requires explicit serialization here.
    # Nulls are dropped — caller's --field with no value shouldn't appear.
    $lines = ($lines | append '  let req_body = ($req_body | transpose k v | where v != null | reduce -f {} {|p, acc| $acc | upsert $p.k $p.v } | url build-query)')
  }

  let body_arg = if $is_multipart { ' $mp.body' } else if $cmd.has_body { " $req_body" } else { "" }
  let ct_arg = if $is_multipart { '$mp.content_type' } else if $has_ct_override { '$effective_ct' } else { $'"($cmd.content_type)"' }
  $lines = ($lines | append $'  do-request "($cmd.method)" $full_url $auth $insecure $raw $dry_run $max_time $allow_errors $full ($ct_arg)($body_arg)')

  $lines | str join "\n"
}

# Render the module header: comment header, constants, helpers, completers, introspection command.
def render-module-header [
  title: string, version_str: string, spec_file: string, token_env_var: string,
  base_url: string, all_urls: list, commands: list,
  auth_schemes: list, completers: record, helpers_code: string,
  config: record
] {
  let completers_code = if ($completers | is-not-empty) {
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
  let has_public = ($commands | where {|c| $c.default_auth == "none" } | is-not-empty)
  let auth_names = $auth_schemes | each {|s| $s.name } | uniq
  let auth_names_with_none = if $has_public { $auth_names | append "none" } else { $auth_names }
  # If the spec offers HTTP Basic, expose `basic-credentials` as a completion
  # option too — it base64-encodes `user:pass` per RFC 7617 (vs. `basic` which
  # treats the token literally).
  let has_basic = ($auth_schemes | any {|s| $s.prefix == "Basic" and $s.in == "header" })
  let auth_names_final = if $has_basic and (not ("basic-credentials" in $auth_names_with_none)) {
    $auth_names_with_none | append "basic-credentials"
  } else { $auth_names_with_none }
  let auth_completer_vals = if ($auth_names_final | is-not-empty) {
    $auth_names_final | each {|n| $'"($n)"' } | str join ' '
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
      '  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "full" "dry-run" "accept" "help"]'
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
    if ($mapping_keys | is-not-empty) {
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
  if ($extra | is-not-empty) {
    $cmd_lines = ($cmd_lines | append "#")
    $cmd_lines = ($cmd_lines | append $extra)
  }

  let sig_result = (build-signature $cmd $completers $mapping $config)

  # Emit @deprecated attributes (must come immediately before export def)
  mut annotations = []
  if $cmd.deprecated {
    let reason = ($cmd.deprecation_reason? | default null)
    if ($reason != null) and ($reason | is-not-empty) {
      let flat = ($reason | str replace --all "\n" " ")
      $annotations = ($annotations | append $"@deprecated ($flat | to nuon)")
    } else {
      $annotations = ($annotations | append '@deprecated')
    }
  }
  for df in $sig_result.deprecated_flags {
    $annotations = ($annotations | append $'@deprecated --flag ($df.flag_name)')
  }
  if ($annotations | is-not-empty) {
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
export def render-module [spec_data: record, commands: table, spec_file: string, module_name: string, base_url: string, extra_urls: list<string>, auth_schemes: list, config: record] {
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

  # Only emit the multipart envelope builder when at least one operation in
  # this spec uses `multipart/form-data`. The gate keys on the operation's
  # content-type, not on a non-empty file-fields list — some multipart specs
  # (Jira, Codat) have empty/array/bare-binary body schemas where the file-
  # field detector returns nothing, but the operation still needs to send a
  # well-formed multipart envelope at runtime. Issue 11.D.
  let needs_multipart = ($commands | any {|c|
    ($c.content_type? | default "") == "multipart/form-data" and ($c.has_body? | default false)
  })

  let helpers_code = render-helpers $token_env_var $auth_schemes $config.default_timeout $config.default_headers $needs_multipart

  let header = render-module-header $title $version_str $spec_file $token_env_var $base_url $all_urls $commands $auth_schemes $completers $helpers_code $config

  let command_sections = ($commands | each {|cmd| render-command $cmd $completers $mapping $config })

  [$header] | append $command_sections | str join "\n"
}
