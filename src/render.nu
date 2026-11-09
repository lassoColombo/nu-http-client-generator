# render.nu — Code generation / rendering for the Nushell HTTP client module.
#
# All functions in this file take the command model (built by mod.nu + spec.nu)
# and produce Nushell source code strings.

# The config-independent helpers every client carries (`serialize-qp`,
# `build-url`, `handle-response`, …) live as real Nushell source next to this
# file — `runtime.nu` always, `runtime-multipart.nu` when an operation needs
# the envelope builder — so they get highlighting and direct unit tests
# (`tests/test_runtime.nu`). render only splices their lines into the module.
use names.nu [SIGNATURE_FLAGS]

const RUNTIME_DIR = (path self | path dirname)
def runtime-source [file: string]: nothing -> list<string> {
  open --raw ($RUNTIME_DIR | path join $file) | lines
}

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
      $kept ++= [$"... \(($remaining) more fields\)"]
      break
    }
    $kept ++= [$entry]
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

# Stringify a type descriptor (from spec's `schema-to-type-descriptor`) into
# Nushell type syntax — the deep counterpart to `nu-type-for`. Both live here
# because producing Nushell type text is the render layer's job. Owns the two
# syntax decisions the descriptor deliberately leaves out: a list-of-record
# collapses to `table<…>` (nicer than `list<record<…>>`), and record field
# names are sanitized to valid Nushell type identifiers.
export def nu-type-string [td: any]: nothing -> string {
  if not (($td | describe) | str starts-with "record") { return $td }
  let cols = ($td | columns)
  if ("list" in $cols) {
    let inner = (nu-type-string $td.list)
    if ($inner | str starts-with "record<") {
      $"table<($inner | str substring 7..-2)>"
    } else {
      $"list<($inner)>"
    }
  } else if ("record" in $cols) {
    let fields = ($td.record | each {|f|
      let safe_name = ($f.name | str replace --all --regex '[^a-zA-Z0-9_]' '_')
      $"($safe_name): (nu-type-string $f.type)"
    } | str join ", ")
    if ($fields | is-empty) { "record" } else { $"record<($fields)>" }
  } else {
    "any"
  }
}

# A duration as Nushell source: the unit form when it is a single unit
# (`30min`), else the nuon nanosecond form — `into string` renders `90sec` as
# `1min 30sec`, which is not a literal.
def duration-literal [d: duration]: nothing -> string {
  let text = ($d | into string)
  if ($text =~ '^\d+[a-z]+$') { $text } else { $d | to nuon }
}

# Whether the generated client should carry Unix-socket transport logic. Gated:
# emitted only when the user baked a default socket (--default-unix-socket) or
# supplied completion sockets (--autocompletion-unix-sockets) at generation time.
# When on, the effective default socket is --default-unix-socket, falling back to
# the first --autocompletion-unix-sockets entry (mirrors the base-url rule).
def unix-socket-enabled [config: record]: nothing -> bool {
  (($config.default_unix_socket? | default null) | is-not-empty) or (($config.autocompletion_unix_sockets? | default []) | is-not-empty)
}

# Variable names a generated command must not bind for a spec-side param or
# body field. Anything else — `sort`, `from`, `to`, `get`, `if`, `let`,
# `null`, `true`, … — is a legal flag or positional in nushell (variables and
# commands live in separate namespaces, and keywords are only keywords in
# command position), so it is NOT listed. A colliding name gets a prefix
# (`--qp-`, `--hdr-`, `--ck-`, `--body-`) or, for positionals, the `_arg`
# suffix. Nushell accepts a duplicate binding silently (the later one wins),
# so this list is the only thing keeping a value from being dropped.
const RESERVED_VARS = (
  # built-in variables
  [in nu env]
  # the signature flags' variables, and nushell's own `--help`: a
  # `--help: string` param parses but is routed to the help path, so the user
  # could never pass it.
  ++ ($SIGNATURE_FLAGS ++ [unix-socket help] | str replace --all '-' '_')
  # body-code internals. `input` and `sock` are bound BEFORE path params are
  # validated and the body/query are assembled, so a same-named param would be
  # shadowed and silently dropped; the rest bind after their params are
  # consumed but are listed so the set stays complete.
  ++ [input sock auth base qp full_url req_body req_body_wire effective_ct extra_headers cookie_str accept_val mp req]
)

# Variables a query/header/cookie flag must not bind: the reserved set plus
# `body`, the fallback flag a command declares when its body has no per-field
# flags. A spec-side `?body=` would otherwise emit a second `--body` and
# nushell keeps the first, dropping the value. Body FIELDS stay off this list:
# a field named `body` only gets a flag when `--body` itself is not emitted.
const RESERVED_FLAG_VARS = ($RESERVED_VARS ++ [body])

# Convert a param name to a nushell flag name. A name nothing survives of
# (`:`) becomes `param`; reserved names are the caller's business
# (`effective-flag-name`, `decorate-body-fields`, `effective-positional-var`).
export def to-flag-name [name: string] {
  let cleaned = ($name | str kebab-case)
  if ($cleaned | is-empty) { "param" } else { $cleaned }
}

# Convert a parameter name to a nushell variable name (flag-style then underscored)
def to-flag-var [name: string] {
  flag-var (to-flag-name $name)
}

# Flag name with collision prefix for query/header/cookie params
def effective-flag-name [name: string, prefix: string] {
  let raw = (to-flag-name $name)
  let var = (to-flag-var $name)
  if ($var in $RESERVED_FLAG_VARS) { $"($prefix)-($raw)" } else { $raw }
}

# The variable a flag binds: `--user-id` → `$user_id`. Every collision check
# below compares variables, not flag spellings, because that is what nushell
# binds: a positional `user_id` and a flag `--user-id` are the same variable
# and nushell accepts the pair silently (the later one wins).
def flag-var [flag_name: string]: nothing -> string {
  $flag_name | str replace --all '-' '_'
}

# Disambiguate a flag name against the variables already bound. Returns
# {flag_name, suffix} — suffix is the disambiguating tail ("" if untouched,
# otherwise "-list", "-2", "-3", ...). Two query params whose kebab-case forms
# collide (e.g. `dataSegmentCode` and `dataSegmentCode[]`) would otherwise
# both bind the same flag, silently dropping the user's value. The
# array-shaped variant gets `-list`; subsequent collisions get `-2`, `-3`, etc.
def disambiguate-flag-name [proposed: string, is_array: bool, seen_vars: list<string>]: nothing -> record {
  if not ((flag-var $proposed) in $seen_vars) { return {flag_name: $proposed, suffix: ""} }
  if $is_array {
    let candidate = $"($proposed)-list"
    if not ((flag-var $candidate) in $seen_vars) { return {flag_name: $candidate, suffix: "-list"} }
  }
  let n = (2.. | where {|n| not ((flag-var $"($proposed)-($n)") in $seen_vars) } | first)
  {flag_name: $"($proposed)-($n)", suffix: $"-($n)"}
}

# Walk a list of params (query/header/cookie) and assign each a
# collision-free flag_name and flag_var, threading the set of bound variables
# so later groups (and the body) avoid colliding with earlier groups. Returns
# {items, seen} where items has the original params merged with
# {flag_name, flag_var, name_suffix} — `name_suffix` is the disambiguating
# tail (empty when no collision) so callers can append origin notes to the
# description text.
#
# `path_vars` are the path positionals' variable names. OpenAPI keys a
# parameter by name AND location, so a path `{id}` next to a query `id` is
# legal (DRF emits it for every detail route with an `id` filter), but both
# would bind `$id`: the flag, declared later, wins and the path value is lost.
# The positional keeps the name and the flag takes the group prefix, the same
# way reserved names do (`decorate-body-fields` gives body fields `body-`).
def decorate-param-group [params: list, prefix: string, path_vars: list<string>, seen: list<string>]: nothing -> record {
  mut items = []
  mut acc = $seen
  for p in $params {
    let base = (effective-flag-name $p.name $prefix)
    let proposed = if ((flag-var $base) in $path_vars) { $"($prefix)-($base)" } else { $base }
    let is_array = ($p.type == "array") or ($p.name | str ends-with "[]")
    let res = (disambiguate-flag-name $proposed $is_array $acc)
    let flag_var = (flag-var $res.flag_name)
    $items ++= [($p | merge {flag_name: $res.flag_name, flag_var: $flag_var, name_suffix: $res.suffix})]
    $acc ++= [$flag_var]
  }
  {items: $items, seen: $acc}
}

# Decide the flag/positional naming for body fields, threading the set of
# bound variables so body fields avoid colliding with each other or with
# earlier query/header/cookie flags. Returns {items, seen} where each item is
# the original field merged with:
#   is_positional : rendered as a positional arg (required, non-colliding,
#                   non-bool, non-nullable) rather than a `--flag`
#   flag_name     : the flag name when a flag; the positional var name otherwise
#   var_name      : the Nushell variable to reference in the body (flag_name
#                   with '-' → '_')
#   collision     : "" | "cross-group" | "reserved" — drives the "(body field)"
#                   note and the `-body` / `body-` prefix choice
def decorate-body-fields [body_fields: list, path_vars: list<string>, seen: list<string>]: nothing -> record {
  mut items = []
  mut body_seen = $seen
  for f in $body_fields {
    let flag = (to-flag-name $f.name)
    let var = (flag-var $flag)
    # Reserved-word collision (path positional / builtin variable / body-code
    # internal) or a name nothing survives of (`:`): the field becomes a
    # `body-` prefixed flag.
    let reserved_collision = ($var in $path_vars) or ($var in $RESERVED_VARS) or ($f.name | str kebab-case | is-empty)
    # A body field whose variable is already bound — by a query/header/cookie
    # flag or by an earlier body field (`user_id` next to `userId`) — is a
    # separate collision class: suffix with `-body`.
    let cross_group_collision = (not $reserved_collision) and ($var in $body_seen)
    let collides = $reserved_collision or $cross_group_collision
    # Only `!= "bool"` matters here; nu-type-for and openapi-to-nu-type agree on
    # bool-ness, so the cheaper mapping is enough for the positional decision.
    let is_bool = ((openapi-to-nu-type $f.type) == "bool")
    let is_positional = $f.required and (not $collides) and (not $is_bool) and (not ($f.nullable? | default false))
    let decided = if $is_positional {
      {flag_name: $var, collision: ""}
    } else if $cross_group_collision {
      {flag_name: $"($flag)-body", collision: "cross-group"}
    } else if $reserved_collision {
      {flag_name: $"body-($flag)", collision: "reserved"}
    } else {
      {flag_name: $flag, collision: ""}
    }
    # The prefixed/suffixed candidate can itself be bound already (three
    # spellings of one name, two reserved names differing only by case), so a
    # flag goes through the same numeric sweep the param groups use; a
    # positional is unbound by construction.
    let flag_name = if $is_positional { $decided.flag_name } else { (disambiguate-flag-name $decided.flag_name false $body_seen).flag_name }
    let var_name = (flag-var $flag_name)
    $items ++= [($f | merge {is_positional: $is_positional, flag_name: $flag_name, var_name: $var_name, collision: $decided.collision})]
    $body_seen ++= [$var_name]
  }
  {items: $items, seen: $body_seen}
}

# Effective positional path-param variable name. Sanitizes the path param's
# variable form and, if it collides with a reserved variable, suffixes with
# `_arg` so the placeholder name stays at the front — the user reading
# `<input_arg>` can map it to URL `{input}` at a glance.
export def effective-positional-var [name: string] {
  let var = (to-flag-var $name)
  if ($var in $RESERVED_VARS) { $"($var)_arg" } else { $var }
}

# Resolve every parameter's flag and variable name once, before emission.
# `build-signature` (which declares the flags) and `build-body-code` (which
# references the variables) both read the names decided here, so the two
# cannot disagree. Groups are walked query → header → cookie → body, each
# avoiding the names taken by the ones before it and by the path positionals.
def decorate-command [cmd: record]: nothing -> record {
  let path_params = ($cmd.path_params | each {|p| $p | insert var_name (effective-positional-var $p.name) })
  let path_vars = ($path_params | each {|p| $p.var_name })
  let qp = (decorate-param-group $cmd.query_params "qp" $path_vars [])
  let hdr = (decorate-param-group $cmd.header_params "hdr" $path_vars $qp.seen)
  let ck = (decorate-param-group $cmd.cookie_params "ck" $path_vars $hdr.seen)
  let body = (decorate-body-fields $cmd.body_fields $path_vars $ck.seen)
  $cmd | merge {
    path_params: $path_params
    query_params: $qp.items
    header_params: $hdr.items
    cookie_params: $ck.items
    body_fields: $body.items
  }
}

# Collapse a multi-line description into one line: it lands in a `#` comment
# inside the `def [...]` block, where a newline would end the comment.
def flatten-description [text: string]: nothing -> string {
  $text | lines | str join " "
}

# Render a list of params as a nushell record literal string (e.g. "key": $var, ...)
#
# Header- and cookie-param values are emitted into a record that's then merged
# into `--headers`. Nushell's `http get --headers {…}` silently drops values
# typed `list<…>`, so array-typed params must be serialized to a
# single string. Per OpenAPI `style: simple` (default for headers) and RFC 7230
# §3.2.6, multi-value headers are comma-joined regardless of `explode` — HTTP
# headers can't repeat. The runtime check handles `null` (compact-friendly) and
# scalar values unchanged, so this is safe even when the user passes a single
# string into a list-typed flag. Keyed on the param's type, not its item type:
# an array of `$ref` items has no primitive `items_type` but is still a list.
def render-param-record [params: list] {
  $params | each {|p|
    let var = $p.flag_var
    let value_expr = if $p.type == "array" {
      $"\(if \($($var) | describe | str starts-with \"list\"\) { $($var) | compact | each { into string } | str join \",\" } else { $($var) }\)"
    } else {
      $"$($var)"
    }
    $'($p.name | to nuon): ($value_expr)'
  } | str join ", "
}

# The identity of a param's enum completer: {flag_name, vals, fingerprint}.
# Two params share one completer def when their flag name and (sorted,
# stringified) values match. `collect-completers` registers under the
# fingerprint; `resolve-completer` looks it up.
def completer-key [q: record]: nothing -> record {
  let flag_name = (to-flag-name $q.name)
  let vals = ($q.enum | each { $"($in)" } | sort)
  {flag_name: $flag_name, vals: $vals, fingerprint: $"($flag_name):($vals | str join ',')"}
}

# Collect all unique enum sets and map each (flag_name, enum_values) to a completer name.
export def collect-completers [commands: list] {
  let initial = {completers: {}, mapping: {}, name_counts: {}}
  let final = ($commands | reduce -f $initial {|cmd, state|
    let accept_source = if ($cmd.accept_types | length) > 1 { [{name: "accept", enum: $cmd.accept_types}] } else { [] }
    # A collapsed body (`--body: record`) declares no per-field flags, so its
    # fields' enums would only produce completers nothing references.
    let body_source = if ($cmd.body_collapsed? | default false) { [] } else { $cmd.body_fields }
    let enum_sources = ($cmd.path_params | append $cmd.query_params | append $body_source
      | append $cmd.header_params | append $cmd.cookie_params | append $accept_source)
    $enum_sources | reduce -f $state {|q, st|
      if ($q.enum | is-empty) { return $st }
      let key = (completer-key $q)
      let flag_name = $key.flag_name
      if ($key.fingerprint in ($st.mapping | columns)) { return $st }
      let count = ($st.name_counts | get -o $flag_name | default 0)
      let cname = if $count == 0 {
        $"($flag_name)-completer"
      } else {
        $"($flag_name)-completer-($count)"
      }
      $st | merge {
        name_counts: ($st.name_counts | upsert $flag_name ($count + 1))
        completers: ($st.completers | insert $cname $key.vals)
        mapping: ($st.mapping | insert $key.fingerprint $cname)
      }
    }
  })
  {completers: $final.completers, mapping: $final.mapping}
}

# Render completer functions as nushell source.
# Values may contain embedded double-quotes or backslashes (e.g. specs that
# include `"\"Latency\""` as an enum value). Escape those so the emitted
# string literal is well-formed.
def render-completers [completers: record] {
  $completers | items {|name, values|
    let vals = ($values | each {|v| ($v | to nuon) } | str join ' ')
    $'def ($name) [] { [($vals)] }'
  } | str join "\n"
}

# Resolve the completer name for a param given the mapping
export def resolve-completer [q: record, mapping: record] {
  $mapping | get -o (completer-key $q).fingerprint
}

# Render a single flag/positional line for the signature.
# Used by query, header, cookie params and body fields to avoid duplication.
def render-param-sig [flag_name: string, nu_type: string, desc: string, cname?: string, --positional] {
  let completer = if ($cname | is-not-empty) { $"@($cname)" } else { "" }
  if $positional {
    $'  ($flag_name): ($nu_type)($completer)($desc)'
  } else if $nu_type == "bool" {
    $'  --($flag_name): oneof<nothing, bool>($desc)'
  } else {
    $'  --($flag_name): ($nu_type)($completer)($desc)'
  }
}

# The comment text for a decorated query/header/cookie flag: its description,
# plus an origin note when the flag was disambiguated by a suffix, so users can
# tell which spec-side parameter it maps to.
def param-doc [q: record]: nothing -> string {
  let note = match ($q.name_suffix? | default "") {
    "" => ""
    "-list" => " (array variant)"
    $s => $" \(disambiguated($s)\)"
  }
  $"(flatten-description $q.description)($note)"
}

# The comment text for a decorated body field: its description and the shape
# of a record-typed value joined by ` — `, then `(body field)` when the flag
# took the `-body` suffix to avoid a query/header/cookie flag.
def body-field-doc [f: record, shapes: list]: nothing -> string {
  let text = ([(flatten-description $f.description) (lookup-shape $f.name $shapes)] | where {|t| $t | is-not-empty } | str join " — ")
  [$text (if $f.collision == "cross-group" { "(body field)" } else { "" })] | where {|t| $t | is-not-empty } | str join " "
}

# Render decorated params or body fields for the signature. Each item carries
# its comment text as `doc`; a body field may be a positional. Returns
# {parts: list<string>, dep_flags: list<string>} — dep_flags are the flag names
# that get an `@deprecated --flag` attribute (positionals cannot take one).
def render-param-group [params: list, mapping: record, config: record] {
  mut parts = []
  mut dep_flags = []
  for q in $params {
    let nu_type = (nu-type-for $q.type ($q.items_type? | default null))
    let desc = if $config.no_descriptions or ($q.doc | is-empty) { "" } else { $" # ($q.doc)" }
    let cname = if ($q.enum | is-not-empty) { resolve-completer $q $mapping } else { null }
    let positional = ($q.is_positional? | default false)
    $parts ++= [(render-param-sig $q.flag_name $nu_type $desc $cname --positional=$positional)]
    if (not $positional) and ($q.deprecated? | default false) {
      $dep_flags ++= [$q.flag_name]
    }
  }
  {parts: $parts, dep_flags: $dep_flags}
}

# Look up a shape description for a body flag from the field_shapes list.
def lookup-shape [flag: string, shapes: list] {
  let matched = ($shapes | where { $in.flag == $flag })
  if ($matched | is-empty) { null } else {
    let s = ($matched | first)
    let label = if ($s.is_item? | default false) { "item shape" } else { "shape" }
    $"($label): (build-shape-doc $s.fields)"
  }
}

# Build the signature string for a decorated command (see `decorate-command`).
# Returns {signature: string, deprecated_flags: list<string>}.
export def build-signature [cmd: record, mapping: record, config: record] {
  mut parts = []
  mut dep_flags = []
  let shapes = if $config.no_descriptions { [] } else { $cmd.field_shapes? | default [] }

  for p in $cmd.path_params {
    let nu_type = (nu-type-for $p.type ($p.items_type? | default null))
    let cname = if ($p.enum? | default [] | is-not-empty) { resolve-completer $p $mapping } else { null }
    $parts ++= [(render-param-sig $p.var_name $nu_type "" $cname --positional)]
  }

  # AND-form security (>1 scheme in one requirement object) gets one
  # `--token-<scheme>` flag per required scheme and NO `--auth-scheme` (there
  # is nothing to choose — all schemes are sent together). Single-scheme and
  # OR-form ops keep the standard `--token` + `--auth-scheme` pair.
  let auth_req = ($cmd.auth_required? | default [])
  let token_flags = if ($auth_req | length) > 1 {
    $auth_req | each {|s| $"  --token-($s.flag_slug): string # Auth token for ($s.spec_name) \(($s.header_name)\)" }
  } else {
    [
      '  --token(-t): string # Auth token'
      '  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme'
    ]
  }
  $parts ++= ['  --base-url(-b): string@base-url-completer # API base URL'] ++ $token_flags ++ [
    '  --insecure(-k) # Skip TLS verification'
    '  --max-time(-m): duration # Timeout'
    '  --raw(-r) # Fetch as text'
    '  --allow-errors(-e) # Return full response without error handling'
    '  --full(-F) # Return full response record {status, headers, body} while still raising on 4xx/5xx'
    '  --dry-run(-n) # Return the request that would be sent without executing it'
  ]

  # Unix-socket transport flag (gated): completes from the baked default plus any
  # --autocompletion-unix-sockets. Default $UNIX_SOCKET is applied in the body.
  if (unix-socket-enabled $config) {
    $parts ++= ['  --unix-socket(-U): string@unix-socket-completer # Connect to the API over a Unix socket instead of TCP']
  }

  # Accept header flag (only when multiple response content types)
  if ($cmd.accept_types | length) > 1 {
    # collect-completers always registers this enum, so the lookup cannot miss.
    let cname = resolve-completer {name: "accept", enum: $cmd.accept_types} $mapping
    $parts ++= [$'  --accept: string@($cname) # Response content type']
  }

  let body_fields = if $cmd.has_body and (not $cmd.body_collapsed) {
    $cmd.body_fields | each {|f| $f | insert doc (body-field-doc $f $shapes) }
  } else { [] }
  for group in [$cmd.query_params $cmd.header_params $cmd.cookie_params] {
    let result = (render-param-group ($group | each {|q| $q | insert doc (param-doc $q) }) $mapping $config)
    $parts ++= $result.parts
    $dep_flags ++= $result.dep_flags
  }
  let body_result = (render-param-group $body_fields $mapping $config)
  $parts ++= $body_result.parts
  $dep_flags ++= $body_result.dep_flags

  if $cmd.has_body and $cmd.body_collapsed {
    let body_shape = (lookup-shape "body" $shapes)
    let body_desc = if ($body_shape != null) { $" # ($body_shape)" } else { " # Request body" }
    $parts ++= [$"  --body: record($body_desc)"]
  } else if $cmd.has_body and ($cmd.body_fields | is-empty) {
    # When the body schema is non-record (e.g. `type: string` for a
    # `text/plain` body), emit a typed flag matching the scalar so callers
    # can pass a raw value. For non-JSON content-types whose schema IS
    # record-shaped (e.g. AWS text/xml AttachInstancesQuery), emit
    # `--body: any` — `http post --content-type text/xml <record>` rejects
    # records, so the caller has to pre-serialize to a string; `any` lets
    # them pass either a record or a string. JSON-family records keep the
    # `--body: record` typing.
    let scalar = ($cmd.body_scalar_type? | default "any")
    let body_t = if ($scalar != "any") { nu-type-for $scalar } else if $cmd.body_kind == "opaque" { "any" } else { "record" }
    $parts ++= [$"  --body: ($body_t)"]
  }

  {signature: ($parts | str join "\n"), deprecated_flags: $dep_flags}
}

# When the spec advertises HTTP Basic, the client exposes a sibling
# `basic-credentials` scheme that base64-encodes the token per RFC 7617.
# `basic` itself stays the literal-prefix path for users who pre-encode; pick
# `basic-credentials` to pass `user:pass` raw. Consulted by the `build-auth`
# match arms and the `auth-scheme-completer`.
def offers-basic-credentials [auth_schemes: list]: nothing -> bool {
  $auth_schemes | any {|s| $s.prefix == "Basic" and $s.in == "header" }
}

# Render the helper functions that go into every generated client.
# `needs_multipart` controls emission of the `build-multipart-body` helper —
# only generated when at least one operation uses `multipart/form-data` so
# clients that never upload files stay slim.
def render-helpers [token_env_var: string, auth_schemes: list, needs_multipart: bool = false, needs_and_auth: bool = false, methods_used: list<string> = [], needs_unix_socket: bool = false] {
  mut match_arms = []
  mut seen_names = []
  for s in $auth_schemes {
    if not ($s.name in $seen_names) {
      $seen_names ++= [$s.name]
      if $s.in == "query" {
        $match_arms ++= [$"    ($s.name | to nuon) => { {scheme: $scheme, headers: {}, query: $\"\(encode-path-segment ($s.header_name | to nuon)\)=\(encode-path-segment $token_val\)\", location: \"query\"} }"]
      } else if $s.in == "cookie" {
        $match_arms ++= [$"    ($s.name | to nuon) => { {scheme: $scheme, headers: {Cookie: $\"\(encode-path-segment ($s.header_name | to nuon)\)=\(encode-path-segment $token_val\)\"}, query: \"\", location: \"cookie\"} }"]
      } else if $s.prefix == "" {
        $match_arms ++= [$"    ($s.name | to nuon) => { {scheme: $scheme, headers: {($s.header_name | to nuon): $token_val}, query: \"\", location: \"header\"} }"]
      } else {
        $match_arms ++= [$"    ($s.name | to nuon) => { {scheme: $scheme, headers: {($s.header_name | to nuon): $\"($s.prefix) \($token_val\)\"}, query: \"\", location: \"header\"} }"]
      }
    }
  }
  if (offers-basic-credentials $auth_schemes) and (not ("basic-credentials" in $seen_names)) {
    $seen_names ++= ["basic-credentials"]
    $match_arms ++= ['    "basic-credentials" => { {scheme: $scheme, headers: {Authorization: $"Basic ($token_val | encode base64)"}, query: "", location: "header"} }']
  }
  $match_arms ++= ['    _ => { {scheme: $scheme, headers: {Authorization: $"Bearer ($token_val)"}, query: "", location: "header"} }']
  let match_body = $match_arms | str join "\n"

  # Emitted only for clients with at least one AND-form op.
  # Merges N per-scheme auth records (each built by `build-auth`) into one:
  # headers union (right-biased), query strings joined with '&', distinct
  # non-"none" locations joined with '+'. Schemes whose token was absent return
  # location "none" from build-auth and contribute nothing.
  let merge_auth_block = if $needs_and_auth { [
    ''
    '# Merge multiple auth records (AND-form security: every scheme must be sent).'
    'def merge-auth [parts: list]: nothing -> record {'
    '  let active = ($parts | where {|p| $p.location != "none" })'
    '  let headers = ($parts | reduce --fold {} {|p, acc| $acc | merge $p.headers })'
    '  let query = ($parts | each {|p| $p.query } | where {|q| $q | is-not-empty } | str join "&")'
    '  let locs = ($active | each {|p| $p.location } | uniq)'
    '  let location = if ($locs | is-empty) { "none" } else { $locs | str join "+" }'
    '  {scheme: ($parts | each {|p| $p.scheme } | str join "+"), headers: $headers, query: $query, location: $location}'
    '}'
  ] } else { [] }

  # Per-verb send helpers — emitted only for the HTTP methods this client uses.
  # Each builds the request from the $req record the op assembled, then unwraps
  # via handle-response. No `match $method`, no arms for verbs this client never
  # calls. This is the composition core: an op invokes exactly one sender.
  #
  # When `needs_unix_socket` is set each sender branches at runtime on
  # `$req.unix_socket`: a non-empty path adds `--unix-socket <path>` to the
  # `http <verb>` call, an empty one connects over TCP. nushell's --unix-socket
  # has no "no socket" sentinel (both null and "" error), so the flag must be
  # physically present-or-absent — hence the branch rather than a passed value.
  # The non-socket form is byte-identical to the pre-feature output.
  let f_base = '--headers $req.headers --full --allow-errors --max-time $req.timeout --insecure=$insecure'
  let f_get = $f_base + ' --raw=$raw'
  let f_body = '--headers $req.headers --content-type $req.content_type --full --allow-errors --max-time $req.timeout --insecure=$insecure --raw=$raw'
  let f_del_body = '--headers $req.headers --content-type $req.content_type --data $body --full --allow-errors --max-time $req.timeout --insecure=$insecure --raw=$raw'
  let sig_bodyless = 'req: record, insecure: bool, allow_errors: bool, full: bool, ok_codes: list<int>'
  let sig_get = 'req: record, insecure: bool, raw: bool, allow_errors: bool, full: bool, ok_codes: list<int>'
  let sig_body = 'req: record, body: any, insecure: bool, raw: bool, allow_errors: bool, full: bool, ok_codes: list<int>'
  # One row per verb. `call` is the `http <verb>` expression with `@SOCK@`
  # marking where the socket flag goes. Every sender binds `let resp` and
  # unwraps it; HEAD first surfaces just the headers on success.
  let with_body = {|verb, flags, empty_arg| 'if ($body | is-empty) { http ' + $verb + ' ' + $f_get + '@SOCK@ $req.url' + $empty_arg + ' } else { http ' + $verb + ' ' + $flags + '@SOCK@ $req.url' + (if $verb == 'delete' { '' } else { ' $body' }) + ' }' }
  let senders = [
    {verb: 'get', doc: 'GET — bodyless, honours --raw', sig: $sig_get, call: ('http get ' + $f_get + '@SOCK@ $req.url')}
    {verb: 'head', doc: 'HEAD — bodyless; default surfaces just the headers on success', sig: $sig_bodyless, call: ('http head ' + $f_base + '@SOCK@ $req.url')}
    {verb: 'options', doc: 'OPTIONS — bodyless', sig: $sig_bodyless, call: ('http options ' + $f_base + '@SOCK@ $req.url')}
    {verb: 'post', doc: 'POST — body + content-type', sig: $sig_body, call: (do $with_body 'post' $f_body ' ""')}
    {verb: 'put', doc: 'PUT — body + content-type', sig: $sig_body, call: (do $with_body 'put' $f_body ' ""')}
    {verb: 'patch', doc: 'PATCH — body + content-type', sig: $sig_body, call: (do $with_body 'patch' $f_body ' ""')}
    {verb: 'delete', doc: 'DELETE — body via --data', sig: $sig_body, call: (do $with_body 'delete' $f_del_body '')}
  ]
  let head_unwrap = '  if (not $full) and (not $allow_errors) and (status-ok $resp.status $ok_codes) { return $resp.headers }'
  let sender_block = ($senders | where verb in $methods_used | each {|s|
    let nosock = ($s.call | str replace --all '@SOCK@' '')
    let call = if $needs_unix_socket {
      let sock = ($s.call | str replace --all '@SOCK@' ' --unix-socket $req.unix_socket')
      'if ($req.unix_socket | is-empty) { ' + $nosock + ' } else { ' + $sock + ' }'
    } else { $nosock }
    let body = [('  let resp = ' + $call)] ++ (if $s.verb == 'head' { [$head_unwrap] } else { [] }) ++ ['  $resp | handle-response $allow_errors $full $ok_codes']
    ['' $"# ($s.doc)" $"def send-($s.verb) [($s.sig)]: nothing -> any {"] ++ $body ++ ['}']
  } | flatten)

  [
    '# Build auth: returns {scheme: string, headers: record, query: string, location: string}.'
    '# `location` is "header" | "query" | "cookie" | "none" and tells dry-run callers'
    '# where the token went without inspecting headers/query themselves.'
    'def build-auth [token?: string, auth_scheme?: string]: nothing -> record {'
    $"  let token_val = if \($token | is-not-empty\) { $token } else { $env | get -o ($token_env_var) | default \"\" }"
    '  let scheme = ($auth_scheme | default "bearer")'
    '  if ($scheme == "none") or ($token_val | is-empty) { return {scheme: $scheme, headers: {}, query: "", location: "none"} }'
    '  match $scheme {'
    $match_body
    '  }'
    '}'
    ...$merge_auth_block
    ''
    ...(runtime-source "runtime.nu")
  ] | append $sender_block | append (if $needs_multipart { [''] ++ (runtime-source "runtime-multipart.nu") } else { [] }) | str join "\n"
}

# Build the body code for a decorated command (see `decorate-command`).
export def build-body-code [cmd: record, config: record] {
  mut lines = []

  if $cmd.has_body {
    $lines ++= ['  let input = $in']
  }

  # AND-form ops merge every required scheme's auth. Each per-scheme token
  # comes from its `--token-<scheme>` flag, falling back to the per-scheme
  # env-var, then build-auth's own shared fallback.
  let auth_req = ($cmd.auth_required? | default [])
  if ($auth_req | length) > 1 {
    let auth_parts = ($auth_req | each {|s|
      $"\(build-auth \($token_($s.flag_slug) | default \($env | get -o ($s.env_var) | default \"\"\)\) ($s.name | to nuon)\)"
    } | str join " ")
    $lines ++= [$"  let auth = \(merge-auth [($auth_parts)]\)"]
  } else {
    $lines ++= [$"  let auth = \(build-auth $token \($auth_scheme | default ($cmd.default_auth | to nuon)\)\)"]
  }
  if ($cmd.base_url | is-not-empty) {
    $lines ++= [$"  let base = \($base_url | default ($cmd.base_url | to nuon)\)"]
  } else {
    $lines ++= ['  let base = ($base_url | default $BASE_URL)']
  }
  # Effective Unix socket: --unix-socket flag, else the baked-in $UNIX_SOCKET
  # default. Empty means "no socket" — the senders branch on it at runtime.
  if (unix-socket-enabled $config) {
    $lines ++= ['  let sock = ($unix_socket | default $UNIX_SOCKET)']
  }

  # Validate each path param is non-empty before URL substitution. Without
  # this guard, `format pattern` substitutes the empty string, leaving
  # `/foo//bar` in the templated path which `build-url`'s `/+ -> /` collapse
  # then erases — silently routing the request to a different endpoint. Naming
  # the spec param in the error tells the caller which arg was passed empty.
  for p in $cmd.path_params {
    let msg = $"path parameter '($p.name)' must be non-empty"
    $lines ++= [$"  if \($($p.var_name) | is-empty\) { error make --unspanned { msg: ($msg | to nuon) } }"]
  }

  # Required query/header/cookie params: apply the spec default (or the
  # single-member enum) when the flag was left out, then refuse to build a
  # request the spec says is invalid. Without this an AWS JSON-RPC call went
  # out with no `X-Amz-Target` and VTEX calls with no `accountName`.
  for group in [[query $cmd.query_params] [header $cmd.header_params] [cookie $cmd.cookie_params]] {
    let loc = ($group | first)
    for q in ($group | last | where {|q| $q.required? | default false }) {
      let rd = ($q.required_default? | default null)
      if ($rd != null) {
        $lines ++= [$"  let ($q.flag_var) = \($($q.flag_var) | default ($rd | to nuon)\)"]
      }
      # `Content-Type` / `Accept` header params always have an effective value
      # (the body's content type, the response media type), so they are never
      # "missing" — only their explicit default is applied above.
      let always_set = ($loc == "header") and (($q.name | str lowercase) in ["content-type" "accept"])
      if ($rd == null) and (not $always_set) {
        let msg = $"required ($loc) parameter '($q.name)' missing: pass --($q.flag_name)"
        $lines ++= [$"  if \($($q.flag_var) == null\) { error make --unspanned { msg: ($msg | to nuon) } }"]
      }
    }
  }

  let path_expr = if ($cmd.path_params | is-not-empty) {
    # Emit a `format pattern` call so the path text is a plain string literal —
    # parens, quotes, backslashes pass through untouched (only `{` and `}` are
    # meta to format pattern). Translate each spec placeholder name to its
    # sanitized var name so it matches the record field.
    let pattern = ($cmd.path_params | reduce --fold $cmd.path_template {|p, acc|
      $acc | str replace $'{($p.name)}' $'{($p.var_name)}'
    })
    let record_fields = ($cmd.path_params | each {|p|
      # Percent-encode each value per RFC 3986 segment grammar — without this
      # a path param like "feature/auth-fix" would render as a literal "/" in
      # the URL and break routing. The path-template literal (the `/{x}/{y}/`
      # structure) stays intact; only the substituted values get encoded.
      # Array-typed path params (OA3 style:simple / Swagger2
      # collectionFormat:csv) comma-join their elements within the segment;
      # a greedy label (`{Key+}`) keeps its `/` between encoded segments.
      let encoder = if ($p.type == "array") { "encode-path-array" } else if ($p.greedy? | default false) { "encode-path-greedy" } else { "encode-path-segment" }
      $"($p.var_name): \(($encoder) $($p.var_name)\)"
    } | str join ", ")
    $"\({($record_fields)} | format pattern ($pattern | to nuon)\)"
  } else {
    $cmd.path_template | to nuon
  }

  # A fixed query from the path key (`/request?view=collection`) is a constant
  # fragment ahead of the caller's params; build-url owns the `?`/`&` joins.
  let fixed_q = if (($cmd.fixed_query? | default "") | is-empty) { "" } else { $" ($cmd.fixed_query | to nuon)" }
  if ($cmd.query_params | is-not-empty) {
    let calls = $cmd.query_params | each {|q|
      let var_name = $"$($q.flag_var)"
      $"\(serialize-qp ($q.name | to nuon) ($var_name) \"($q.collection_style)\"\)"
    } | str join " "
    $lines ++= [$"  let qp = [($calls)] | flatten | str join \"&\""]
    $lines ++= [$"  let full_url = \(build-url $base ($path_expr)($fixed_q) $qp $auth.query\)"]
  } else {
    $lines ++= [$"  let full_url = \(build-url $base ($path_expr)($fixed_q) $auth.query\)"]
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
    let has_per_field = ($cmd.body_fields | is-not-empty) and (not $cmd.body_collapsed)
    if $has_per_field {
      let body_parts_list = ($cmd.body_fields | enumerate | each {|item|
        let f = $item.item
        let idx = $item.index
        let var_ref = $"$($f.var_name)"
        # Use the original spec field name as the body key, but fall back to a
        # synthetic name when it is empty (e.g. the field name was ":" and the
        # sanitizer reduced it to ""). Always quote the key so names with
        # spaces, slashes, or colons are valid Nushell record syntax.
        let key = if ($f.name | is-empty) { $"field-($idx + 1)" } else { $f.name }
        # Swagger 2 formData arrays with a csv/ssv/tsv/pipes collectionFormat
        # are joined into one value; `url build-query` would otherwise repeat
        # the key (`multi`) and the multipart envelope would JSON-stringify
        # the list. Only form bodies (urlencoded or multipart) carry a style.
        let sep = match ($f.collection_style? | default null) { "csv" => ",", "ssv" => " ", "tsv" => "\t", "pipes" => "|", _ => null }
        let value_expr = if ($sep != null) and ($cmd.body_kind in ["form" "multipart"]) {
          $"\(if \(($var_ref) | describe | str starts-with \"list\"\) { ($var_ref) | compact | each { into string } | str join ($sep | to nuon) } else { ($var_ref) }\)"
        } else { $var_ref }
        $'($key | to nuon): ($value_expr)'
      })
      let body_parts = ($body_parts_list | str join ", ")
      $lines ++= [$"  let req_body = {($body_parts)} | compact"]
    } else {
      $lines ++= ['  let req_body = $body']
    }
    # Pipeline-input merge (`merge-body-input` in runtime.nu): a piped record
    # merges deep into the assembled body. When the spec declares
    # `oneOf: [{object}, {array}]` (or anyOf), a piped list is the body — the
    # object variant stays reachable via flags, the array variant via the
    # pipeline. When the body schema is a non-record scalar (string, int, …) or
    # the content type is opaque (`text/xml`, `application/octet-stream`, …),
    # any piped value is the body, so callers can `"text" | op` without a flag.
    let accepts = if ($cmd.body_polymorphic_array? | default false) {
      "list"
    } else if ($cmd.body_kind == "opaque") or (($cmd.body_scalar_type? | default "any") != "any") {
      "scalar"
    } else { "record" }
    $lines ++= [$"  let req_body = \(merge-body-input $input $req_body ($accepts | to nuon)\)"]
    # A required body field that could not be a positional (it collides with a
    # reserved name, or is a bool) is still required: refuse an empty value
    # once flags and pipeline input are merged. Nullable fields are exempt —
    # `null` is a legal value for them and `compact` would drop it anyway. A
    # polymorphic body may be a list by now (the array variant was piped in),
    # and `get -o` on a list of scalars errors, so the check is record-only.
    if $has_per_field {
      let only_record = if ($cmd.body_polymorphic_array? | default false) { '($req_body | describe | str starts-with "record") and ' } else { "" }
      for f in ($cmd.body_fields | where {|f| ($f.required? | default false) and (not $f.is_positional) and (not ($f.nullable? | default false)) }) {
        let msg = $"required body field '($f.name)' missing: pass --($f.flag_name) or pipe a record"
        $lines ++= [$"  if ($only_record)\(\($req_body | get -o ($f.name | to nuon)\) == null\) { error make --unspanned { msg: ($msg | to nuon) } }"]
      }
    }
  }

  # Emit the hardcoded `Accept` default FIRST, then merge user-driven
  # `extra_headers` (which may carry the user's `--hdr-accept` value) on top.
  # Nushell's `merge` is right-biased — the last operand wins on key collision,
  # so this ordering guarantees user-supplied Accept (and any other header
  # param the user set) overrides the spec-default.
  let default_accept = ($cmd.accept_types | first)
  if ($cmd.accept_types | length) > 1 {
    $lines ++= [$"  let accept_val = \($accept | default ($default_accept | to nuon)\)"]
  } else {
    $lines ++= [$"  let accept_val = ($default_accept | to nuon)"]
  }
  $lines ++= ['  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))']

  if ($cmd.header_params | is-not-empty) {
    let hp_record = (render-param-record $cmd.header_params)
    $lines ++= [$"  let extra_headers = {($hp_record)} | compact"]
    $lines ++= ['  let auth = ($auth | update headers ($auth.headers | merge $extra_headers))']
  }

  if ($cmd.cookie_params | is-not-empty) {
    let cp_record = (render-param-record $cmd.cookie_params)
    $lines ++= [$"  let cookie_str = {($cp_record)} | items {|k, v| if $v == null { null } else { $\"\($k\)=\($v\)\" } } | compact | str join \"; \""]
    $lines ++= ['  let auth = if ($cookie_str | is-not-empty) { $auth | update headers ($auth.headers | merge {Cookie: $cookie_str}) } else { $auth }']
  }

  # multipart/form-data: encode the request body as an RFC 7578 envelope so
  # binary file fields are sent as bytes (not as a literal path string) and
  # other fields are JSON-stringified per the common multipart convention.
  # The `build-multipart-body` helper (emitted by `render-helpers` only when
  # this spec needs it) does the actual envelope construction at runtime.
  # Both Swagger-2 (`type: file`) and OAS3 (`type: string, format: binary`)
  # shapes contribute to the file-fields list.
  #
  # The gate keys on content-type alone, not on a non-empty file-fields list:
  # some multipart specs have empty/array/bare-binary body schemas (Jira
  # setColumns, Codat push-*-attachments, Jira addAttachment). The helper
  # accepts an empty `file_fields` list and still builds a well-formed
  # envelope (records JSON-stringified).
  let is_multipart = ($cmd.body_kind == "multipart")
  if $is_multipart {
    let file_field_names = ($cmd.body_fields | where {|f|
      ($f.type? | default "") == "file" or (($f.type? | default "") == "string" and ($f.format? | default null) == "binary")
    } | each {|f| $f.name })
    let file_list_lit = ($file_field_names | each {|n| $n | to nuon } | str join ' ')
    # An omitted body (`--body: record` left out) is an empty record, which
    # yields an envelope with just the trailer. A record gets the envelope.
    # Anything else (a multipart op whose schema is a bare `type: string` —
    # spoonacular's recipe card, libretranslate's file token — binds
    # `--body: string`) is sent verbatim rather than silently replaced by an
    # empty envelope.
    $lines ++= ['  let req_body = ($req_body | default {})']
    $lines ++= [$"  let mp = if \($req_body | describe | str starts-with \"record\"\) { build-multipart-body $req_body [($file_list_lit)] $dry_run } else { {body: $req_body, content_type: \"multipart/form-data\"} }"]
  }

  # Detect a user-facing `--content-type` flag. Some Swagger-2 specs declare
  # Content-Type as a header parameter rather than via `consumes` (Akeneo's
  # OAuth token endpoint is the canonical case). When that flag exists, the
  # user can override the spec's default at runtime — but the body still
  # needs to be serialized to match.
  let ct_matches = ($cmd.header_params | where {|p| ($p.name | str lowercase) == "content-type" })
  let has_ct_override = ($ct_matches | is-not-empty) and $cmd.has_body
  let ct_var = if $has_ct_override {
    let v = ($ct_matches | first | get flag_var)
    $"$($v)"
  } else { null }

  # `$req_body_wire` is the post-serialization body sent on the wire (only bound
  # when form-urlencoded conversion happens). `$req_body` keeps the logical
  # record, threaded into the dry-run meta below so callers see what they
  # expressed instead of `k=v&k=v` strings.
  #
  # application/x-www-form-urlencoded: the HTTP body must be a `k1=v1&k2=v2`
  # string, not a JSON record. Nushell's `http post --content-type "..."` sets
  # the header but doesn't reshape the body, so RFC 6749 (OAuth token
  # endpoints) needs explicit serialization. Nulls are dropped — a --field with
  # no value shouldn't appear. $req_body is guarded against a non-record: the
  # `--body` fallback binds it straight from `--body`, so it is null when
  # omitted and a string/list for `--body: string|list`, and `transpose` only
  # accepts a record/table. record → compact+build-query; null → "" (empty
  # form body); else → `into string` (the caller already supplied the wire form).
  let form_encode = 'if (($req_body | describe) | str starts-with "record") { $req_body | compact | url build-query } else if ($req_body == null) { "" } else { $req_body | into string }'
  # A `+json` suffix type (`application/merge-patch+json`): nushell's `http`
  # encodes a record only for `application/json…` and rejects one for any
  # other type, but sends a string verbatim under the declared type. So a
  # structured body is encoded here; a string is taken as already encoded.
  let json_encode = r#'if (($req_body | describe) =~ '^(record|list|table)') { $req_body | to json -r } else { $req_body }'#
  let static_encode = match $cmd.body_kind { "form" => $form_encode, "json-text" => $json_encode, _ => null }
  let emitted_wire_body = $has_ct_override or ($static_encode != null)
  if $has_ct_override {
    # Effective content-type for body serialization and the request. The
    # user (or the spec default) may pick x-www-form-urlencoded or a `+json`
    # type, which are encoded as above; other content types pass the body
    # through unchanged — JSON is what Nushell's `http post` already does by
    # default.
    $lines ++= [$"  let effective_ct = \(($ct_var) | default ($cmd.content_type | to nuon)\)"]
    $lines ++= [('  let req_body_wire = if $effective_ct == "application/x-www-form-urlencoded" { (' + $form_encode + r#') } else if ($effective_ct =~ '\+json\s*(;|$)') { ('# + $json_encode + ') } else { $req_body }')]
  } else if $emitted_wire_body {
    $lines ++= [('  let req_body_wire = (' + $static_encode + ')')]
  }

  # Wire body handed to the sender: multipart envelope, form-urlencoded or
  # JSON-encoded string, or the logical record. Bodyless verbs pass null.
  let wire_body_expr = if $is_multipart { '$mp.body' } else if $emitted_wire_body { '$req_body_wire' } else if $cmd.has_body { '$req_body' } else { 'null' }

  # The $req record is the fully-resolved request AND the dry-run shape. The op
  # owns it: under --dry-run it returns $req verbatim; otherwise the same $req
  # drives the sender, so dry-run and the wire request cannot diverge. GET/HEAD/
  # OPTIONS carry no body on the wire, so report null body/content_type rather
  # than advertising a phantom.
  let bodyless = ($cmd.method in ["get" "head" "options"])
  let req_ct_expr = if $bodyless { 'null' } else if $is_multipart { '$mp.content_type' } else if $has_ct_override { '$effective_ct' } else { $cmd.content_type | to nuon }
  let req_body_expr = if $bodyless { 'null' } else if $cmd.has_body { '$req_body' } else { 'null' }
  let dr_query_expr = if ($cmd.query_params | is-not-empty) {
    let entries = ($cmd.query_params | each {|q| $"($q.name | to nuon): $($q.flag_var)" } | str join ", ")
    $"\({($entries)} | compact\)"
  } else { '{}' }
  # Final request headers: $auth.headers already carries auth token + Accept +
  # header/cookie params; fold any static default-headers UNDER them so an
  # op-set value wins on collision (matches the old do-request merge order).
  let req_headers_expr = if ($config.default_headers? | is-not-empty) {
    let pairs = ($config.default_headers | items {|k, v| $'($k | to nuon): ($v | to nuon)' } | str join ", ")
    $"\({($pairs)} | merge $auth.headers\)"
  } else { '$auth.headers' }
  # ok_codes: the spec's declared success codes; [] falls back to < 400 at runtime.
  let ok_codes_expr = $"[($cmd.success_codes? | default [] | each {|c| $c | into string } | str join ' ')]"
  let timeout_expr = $"\($max_time | default (duration-literal $config.default_timeout))"

  $lines ++= [
    '  let req = {'
    $'    method: "($cmd.method)"'
    '    url: $full_url'
    $'    query: ($dr_query_expr)'
    $'    headers: ($req_headers_expr)'
    $'    body: ($req_body_expr)'
    $'    content_type: ($req_ct_expr)'
    $'    timeout: ($timeout_expr)'
    '    auth: {scheme: $auth.scheme, location: $auth.location}'
  ]
  if (unix-socket-enabled $config) {
    $lines ++= ['    unix_socket: $sock']
  }
  $lines ++= ['  }' '  if $dry_run { return ({dry_run: true} | merge $req) }']

  # One sender, picked at generation time — no runtime `match $method`.
  let send_line = match $cmd.method {
    "get" => $'  send-get $req $insecure $raw $allow_errors $full ($ok_codes_expr)'
    "head" => $'  send-head $req $insecure $allow_errors $full ($ok_codes_expr)'
    "options" => $'  send-options $req $insecure $allow_errors $full ($ok_codes_expr)'
    "post" => $'  send-post $req ($wire_body_expr) $insecure $raw $allow_errors $full ($ok_codes_expr)'
    "put" => $'  send-put $req ($wire_body_expr) $insecure $raw $allow_errors $full ($ok_codes_expr)'
    "patch" => $'  send-patch $req ($wire_body_expr) $insecure $raw $allow_errors $full ($ok_codes_expr)'
    "delete" => $'  send-delete $req ($wire_body_expr) $insecure $raw $allow_errors $full ($ok_codes_expr)'
  }
  $lines ++= [$send_line]

  $lines | str join "\n"
}

# Render the module header: comment header, constants, helpers, completers, introspection command.
# `ctx` is {title, version_str, spec_file, token_env_var, base_url, all_urls,
# commands, auth_schemes, completers, helpers_code}, built by `client`.
def render-module-header [ctx: record, config: record] {
  let completers_code = if ($ctx.completers | is-not-empty) {
    $"# Completers for enum parameters\n(render-completers $ctx.completers)\n"
  } else {
    ""
  }

  # base-url completer
  let per_op_urls = ($ctx.commands | where {|c| $c.base_url != null } | each {|c| $c.base_url } | uniq)
  let all_completer_urls = ($ctx.all_urls | append $per_op_urls | uniq)
  let base_url_vals = $all_completer_urls | each {|u| $u | to nuon } | str join ' '
  let base_url_completer = $'def base-url-completer [] { [($base_url_vals)] }'

  # auth-scheme completer
  let has_public = ($ctx.commands | where {|c| $c.default_auth == "none" } | is-not-empty)
  let auth_names = $ctx.auth_schemes | each {|s| $s.name } | uniq
  let auth_names_with_none = if $has_public { $auth_names | append "none" } else { $auth_names }
  let auth_names_final = if (offers-basic-credentials $ctx.auth_schemes) and (not ("basic-credentials" in $auth_names_with_none)) {
    $auth_names_with_none | append "basic-credentials"
  } else { $auth_names_with_none }
  let auth_completer_vals = if ($auth_names_final | is-not-empty) {
    $auth_names_final | each {|n| $n | to nuon } | str join ' '
  } else {
    '"bearer"'
  }
  let auth_completer = $'def auth-scheme-completer [] { [($auth_completer_vals)] }'

  # Unix-socket transport (gated). Effective default = --default-unix-socket,
  # else the first --autocompletion-unix-sockets entry. The completer offers the
  # default plus all completion sockets, deduped.
  let unix_socket_enabled = (unix-socket-enabled $config)
  let default_sock = if not $unix_socket_enabled { "" } else if (($config.default_unix_socket? | default null) | is-not-empty) {
    $config.default_unix_socket
  } else {
    ($config.autocompletion_unix_sockets? | default []) | first
  }
  let unix_socket_const = if $unix_socket_enabled { [$'const UNIX_SOCKET = ($default_sock | to nuon)'] } else { [] }
  let unix_socket_completer = if $unix_socket_enabled {
    let socks = ([$default_sock] | append ($config.autocompletion_unix_sockets? | default []) | where {|s| $s | is-not-empty } | uniq)
    let vals = ($socks | each {|s| $s | to nuon } | str join ' ')
    [$"def unix-socket-completer [] { [($vals)] }"]
  } else { [] }

  # Auth header lines: the shared `--token` only when some command has it;
  # AND-form ops (one `--token-<scheme>` per required scheme) list theirs.
  let and_schemes = ($ctx.commands | each {|c| $c.auth_required? | default [] } | flatten | uniq-by flag_slug)
  let has_single_auth = ($ctx.commands | any {|c| (($c.auth_required? | default []) | length) <= 1 })
  let auth_lines = (
    (if $has_single_auth { [$'# Auth: --token flag or $env.($ctx.token_env_var)'] } else { [] })
    | append ($and_schemes | each {|s| $"# Auth \(($s.spec_name)\): --token-($s.flag_slug) flag or $env.($s.env_var)" })
  )
  # `help` is listed defensively: nushell 0.116's `scope` does not report it
  # for custom commands, but hiding it costs nothing if a version does.
  let hidden_flags = ($SIGNATURE_FLAGS ++ [help] ++ (if $unix_socket_enabled { [unix-socket] } else { [] }) ++ ($and_schemes | each {|s| $"token-($s.flag_slug)" }))

  # Only generate introspection command when not disabled. The command finds
  # its own module by the exact set of exported command names: a single name
  # is ambiguous when two generated clients share an operationId, while two
  # modules with the same whole set are the same client. Both sides are
  # sorted at runtime so the comparison never depends on the generating
  # nushell's `sort` order.
  let introspection_code = if not $config.no_introspection {
    let cmd_names = ($ctx.commands | get name | append "commands" | each {|n| $n | to nuon } | str join ' ')
    [
      "# List all available API commands with their parameters"
      'export def commands []: nothing -> table {'
      $"  let builtin_flags = [($hidden_flags | each { to nuon } | str join ' ')]"
      $"  let mod_name = \(scope modules | where { \($in.commands | get name | sort\) == \([($cmd_names)] | sort\) } | get name | first\)"
      '  let mod_cmds = (scope modules | where name == $mod_name | get commands | first)'
      '  let cmd_ids = ($mod_cmds | where name != "commands" | get decl_id)'
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
    $'# Auto-generated client for ($ctx.title) (if ($ctx.version_str =~ "^[vV]") { "" } else { "v" })($ctx.version_str)'
    $'# Source: ($ctx.spec_file)'
    ...$auth_lines
    ""
    $'const BASE_URL = ($ctx.base_url | to nuon)'
    ...$unix_socket_const
    ""
    $ctx.helpers_code
    ""
    $base_url_completer
    $auth_completer
    ...$unix_socket_completer
    ""
    $completers_code
    $introspection_code
  ] | str join "\n"
}

# Render a single command as a complete string (doc comment + annotations + export def + signature + body).
def render-command [cmd: record, mapping: record, config: record] {
  let cmd = (decorate-command $cmd)
  mut cmd_lines = []

  # The description is the summary line; the endpoint always appears in help,
  # as the summary itself when there is no description, otherwise as the first
  # extra line.
  let fixed_q = if (($cmd.fixed_query? | default "") | is-empty) { "" } else { $"?($cmd.fixed_query)" }
  let endpoint_line = $"($cmd.method | str uppercase) ($cmd.path_template)($fixed_q)"
  let has_description = ($cmd.description | is-not-empty)
  let summary = if $has_description { flatten-description $cmd.description } else { $endpoint_line }
  $cmd_lines ++= [$"# ($summary)"]

  mut extra = if $has_description { [$"# ($endpoint_line)"] } else { [] }
  if $cmd.deprecated {
    $extra ++= ["# DEPRECATED"]
  }
  if ($cmd.discriminator != null) {
    let d = $cmd.discriminator
    let mapping_keys = ($d.mapping | columns)
    if ($mapping_keys | is-not-empty) {
      $extra ++= [$"# Discriminator \(($d.context)\): ($d.propertyName) = ($mapping_keys | str join ', ')"]
    } else {
      $extra ++= [$"# Discriminator \(($d.context)\): ($d.propertyName)"]
    }
  }
  if ($cmd.external_docs != null) {
    let url = ($cmd.external_docs.url? | default "")
    let edesc = ($cmd.external_docs.description? | default "")
    if ($url | is-not-empty) {
      if ($edesc | is-not-empty) {
        $extra ++= [$"# Docs: ($url) — ($edesc)"]
      } else {
        $extra ++= [$"# Docs: ($url)"]
      }
    }
  }
  if ($cmd.operation_id | is-not-empty) {
    $extra ++= [$"# operationId: ($cmd.operation_id)"]
  }
  if ($extra | is-not-empty) {
    $cmd_lines ++= ["#"]
    $cmd_lines ++= $extra
  }

  let sig_result = (build-signature $cmd $mapping $config)

  # Emit @deprecated attributes (must come immediately before export def)
  mut annotations = []
  if $cmd.deprecated {
    $annotations ++= ['@deprecated']
  }
  for df in $sig_result.deprecated_flags {
    $annotations ++= [$'@deprecated --flag ($df)']
  }
  if ($annotations | is-not-empty) {
    $cmd_lines ++= $annotations
  }

  $cmd_lines ++= [$'export def "($cmd.name)" [']
  $cmd_lines ++= [$sig_result.signature]
  let input_type = if $cmd.has_body { "any" } else { "nothing" }
  # Any concrete response type is a parse-time lie: the command is polymorphic
  # over its flags — a *record* under --dry-run/--full, a *string* under
  # --raw, *nothing* on 204, and the response type on a normal call. Nushell
  # type-checks the downstream pipe against the declared output at parse time,
  # so a bare `-> string` makes `cmd | get …` a parse error and a bare
  # `-> record<…>` makes `cmd --raw | from json` one, while plain `any` erases
  # the response type from `help` and the `commands` table. So every non-`any`
  # type is wrapped in a `oneof<…>` of the real flag-driven shapes: the
  # documented type first, then `string` (--raw), `record` (--dry-run/--full)
  # and `nothing` (204). A record-typed response already admits the dry-run
  # record, and a bare `record` next to `record<…>` would make nushell widen
  # the whole member to `record`, erasing the documented fields from `help`
  # and `commands`; so it is left out there. The senders are `nothing -> any`,
  # so the annotation is never runtime-checked against the actual body —
  # purely a parse-time + doc improvement.
  let return_str = (nu-type-string $cmd.return_type)
  let output_type = if $return_str == "any" { "any" } else {
    let record_member = if ($return_str | str starts-with "record") { [] } else { ["record"] }
    $"oneof<([$return_str "string"] ++ $record_member ++ ["nothing"] | uniq | str join ', ')>"
  }
  $cmd_lines ++= [$"]: ($input_type) -> ($output_type) {"]

  let body_code = (build-body-code $cmd $config)
  $cmd_lines ++= [$body_code]
  $cmd_lines ++= ["}"]
  $cmd_lines ++= [""]

  $cmd_lines | str join "\n"
}

# Render the full client module file
# `loaded` is `spec load-spec`'s {data, source}; `spec` is mod.nu's
# `process-spec` result {commands, auth_schemes, base_url, all_urls}.
export def client [loaded: record, module_name: string, spec: record, config: record] {
  let auth_schemes = $spec.auth_schemes
  # Interpolated, not `into string`: unquoted YAML `version: 1.0` is a float,
  # and `into string` would render it `1`.
  let title = $"($loaded.data.info?.title? | default $module_name)"
  let version_str = $"($loaded.data.info?.version? | default '0.0.0')"
  let token_env_var = if ($config.token_env_var | is-not-empty) {
    $config.token_env_var
  } else {
    $"($module_name | str uppercase | str replace --all --regex '[^A-Z0-9]' '_' | str replace --all --regex '_{2,}' '_' | str trim --char '_')_TOKEN"
  }

  let completion_urls = ($config.autocompletion_base_urls? | default [])
  let base_url = if ($config.default_base_url | is-not-empty) {
    $config.default_base_url
  } else if ($completion_urls | is-not-empty) {
    # No explicit default but completion URLs were given: bake the first as default.
    $completion_urls | first
  } else {
    $spec.base_url
  }
  let all_urls = ([$base_url] | append $completion_urls | append $spec.all_urls | uniq)

  # Enrich AND-form auth requirements with the per-scheme flag slug (derived
  # from the scheme's spec_name) and the per-scheme env-var fallback name
  # (derived from the module token env-var base). Done here, not in model,
  # because the env-var base is only known at render time.
  # One slug per scheme, decided over all schemes in document order so every
  # command agrees: `appKey` and `app_key` both strip to `appkey`, and two
  # `--token-appkey` flags would bind one variable (nushell keeps the first),
  # so a taken slug gets a numeric suffix (`appkey2`). Kept alphanumeric: the
  # slug is spliced into the flag's variable and the env-var name as is.
  let slug_of = ($auth_schemes | reduce --fold {} {|s, acc|
    let base = ($s.spec_name | str lowercase | str replace --all --regex '[^a-z0-9]' '' | if ($in | is-empty) { "scheme" } else { $in })
    let taken = ($acc | values)
    let slug = if ($base not-in $taken) { $base } else { 2.. | each {|n| $"($base)($n)" } | where {|c| $c not-in $taken } | first }
    $acc | upsert $s.spec_name $slug
  })
  let and_env_base = ($token_env_var | str replace --regex '_TOKEN$' '')
  let commands = ($spec.commands | each {|c|
    let ar = ($c.auth_required? | default [])
    if ($ar | length) > 1 {
      $c | update auth_required ($ar | each {|s|
        let slug = ($slug_of | get $s.spec_name)
        $s | insert flag_slug $slug | insert env_var $"($and_env_base)_($slug | str uppercase)_TOKEN"
      })
    } else { $c }
  })
  let needs_and_auth = ($commands | any {|c| (($c.auth_required? | default []) | length) > 1 })

  let completer_data = (collect-completers $commands)
  let completers = $completer_data.completers
  let mapping = $completer_data.mapping

  # Only emit the multipart envelope builder when at least one operation in
  # this spec uses `multipart/form-data`. The gate keys on the operation's
  # content-type, not on a non-empty file-fields list — some multipart specs
  # (Jira, Codat) have empty/array/bare-binary body schemas where the file-
  # field detector returns nothing, but the operation still needs to send a
  # well-formed multipart envelope at runtime.
  let needs_multipart = ($commands | any {|c| $c.body_kind == "multipart" })

  # Set of HTTP verbs across this client's operations — gates which per-verb
  # send-* helpers get emitted. A read-only client never ships post/put/etc.
  let methods_used = ($commands | each {|c| $c.method } | uniq)

  let needs_unix_socket = (unix-socket-enabled $config)
  let helpers_code = render-helpers $token_env_var $auth_schemes $needs_multipart $needs_and_auth $methods_used $needs_unix_socket

  let header = render-module-header {
    title: $title, version_str: $version_str, spec_file: $loaded.source, token_env_var: $token_env_var
    base_url: $base_url, all_urls: $all_urls, commands: $commands, auth_schemes: $auth_schemes
    completers: $completers, helpers_code: $helpers_code
  } $config

  let command_sections = ($commands | each {|cmd| render-command $cmd $mapping $config })

  [$header] | append $command_sections | str join "\n"
}
