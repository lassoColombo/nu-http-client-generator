# render.nu — Code generation / rendering for the Nushell HTTP client module.
#
# All functions in this file take the command model (built by model.nu) and
# produce Nushell source code strings. A generated client is three parts:
# the `CLIENT` constant (what the generator knew about the client as a
# whole), the request runtime (`runtime.nu`, emitted verbatim), and one
# command per operation whose body is a single `http-request` call carrying
# the operation's descriptor (`op-descriptor`) and its arguments. Everything
# the request does at run time lives in the runtime, as real Nushell source
# with its own unit tests (`tests/test_runtime.nu`); render writes signatures
# and data.
use names.nu [SIGNATURE_FLAGS]

const RUNTIME_DIR = (path self | path dirname)
def runtime-source [file: string]: nothing -> list<string> {
  open --raw ($RUNTIME_DIR | path join $file) | lines
}

# A value as Nushell source. Records and lists are written element by element,
# so a list of records stays `[{…}, {…}]` where `to nuon` would switch to
# table syntax; other scalars go through `to nuon`, which quotes and escapes.
def nu-literal []: any -> string {
  let v = $in
  match ($v | describe | str replace --regex '<.*' '') {
    "record" => $"{($v | items {|k, x| $'($k | str-literal): ($x | nu-literal)' } | str join ', ')}"
    "list" | "table" => $"[($v | each { nu-literal } | str join ', ')]"
    "string" => ($v | str-literal)
    _ => ($v | to nuon)
  }
}

# A string as a record key or value in Nushell source: bare when it is a
# plain word (`post`, `pet_id`, `X-Rate-Limit`), else quoted by `to nuon`.
# A bare `true`/`false`/`null` is no string, and `inf`/`infinity`/`nan` (any
# case) are floats, so those are quoted too.
def str-literal []: string -> string {
  let s = $in
  let plain = ($s =~ '^[A-Za-z_][A-Za-z0-9_-]*$') and (($s | str lowercase) not-in ["true" "false" "null" "inf" "infinity" "nan"])
  if $plain { $s } else { $s | to nuon }
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
# collapses to `table<…>` (nicer than `list<record<…>>`), and a record field
# name is written bare when it is a plain word and quoted otherwise
# (`"@odata.type"`), so `help` shows the key the response really has.
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
      $"($f.name | str-literal): (nu-type-string $f.type)"
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
# command position), so it is NOT listed. A command body binds no variables
# of its own (it is one `http-request` call), so the list is the builtin
# variables and the generator's own flags. A colliding name gets a prefix
# (`--qp-`, `--hdr-`, `--ck-`, `--body-`) or, for positionals, the `_arg`
# suffix. Nushell accepts a duplicate binding silently (the later one wins),
# so this list is the only thing keeping a value from being dropped. An
# AND-form op's `--token-<scheme>` flags are reserved per command
# (`decorate-command`).
const RESERVED_VARS = (
  # built-in variables
  [in nu env]
  # the signature flags' variables, and nushell's own `--help`: a
  # `--help: string` param parses but is routed to the help path, so the user
  # could never pass it.
  ++ ($SIGNATURE_FLAGS ++ [unix-socket help] | str replace --all '-' '_')
)

# Variables a query/header/cookie flag must not bind: the reserved set plus
# `body`, the fallback flag a command declares when its body has no per-field
# flags. A spec-side `?body=` would otherwise emit a second `--body` and
# nushell keeps the first, dropping the value. Body FIELDS stay off this list:
# a field named `body` only gets a flag when `--body` itself is not emitted.
const RESERVED_FLAG_VARS = ($RESERVED_VARS ++ [body])

# Convert a param name to a nushell flag name. A name nothing survives of
# (`:`) becomes `param`; collisions are `claim-flag`'s business. The result
# never holds an underscore, so the runtime spells a flag back from its
# variable (`qp_id` → `--qp-id`) in its error messages.
export def to-flag-name [name: string] {
  let cleaned = ($name | str kebab-case)
  if ($cleaned | is-empty) { "param" } else { $cleaned }
}

# Convert a parameter name to a nushell variable name (flag-style then underscored)
def to-flag-var [name: string] {
  flag-var (to-flag-name $name)
}

# The variable a flag binds: `--user-id` → `$user_id`. Every collision check
# below compares variables, not flag spellings, because that is what nushell
# binds: a positional `user_id` and a flag `--user-id` are the same variable
# and nushell accepts the pair silently (the later one wins).
def flag-var [flag_name: string]: nothing -> string {
  $flag_name | str replace --all '-' '_'
}

# The one naming rule for a spec-side flag. The flag is the spec name,
# kebab-cased. When its variable is taken (a reserved variable, a path
# positional, or a flag claimed before it) it takes its group prefix (`qp-`,
# `hdr-`, `ck-`, `body-`); when that is taken too, the first free numeric
# suffix (`-2`, `-3`, …). Examples: a query `id` next to a path `{id}` is
# `--qp-id`; a body field `userId` after a field `user_id` is
# `--body-user-id`, and a third spelling `user-id` is `--body-user-id-2`.
def claim-flag [name: string, group: string, taken: list<string>]: nothing -> string {
  let plain = (to-flag-name $name)
  if (flag-var $plain) not-in $taken { return $plain }
  let prefixed = $"($group)-($plain)"
  if (flag-var $prefixed) not-in $taken { return $prefixed }
  let n = (2.. | where {|n| (flag-var $"($prefixed)-($n)") not-in $taken } | first)
  $"($prefixed)-($n)"
}

# Claim a flag for each query/header/cookie param of one group, in order.
# `taken` holds the variables bound so far (path positionals and earlier
# groups); `RESERVED_FLAG_VARS` is added here. Returns {items, taken}: each
# item is the param merged with {flag_name, flag_var, renamed}.
def decorate-param-group [params: list, group: string, taken: list<string>]: nothing -> record {
  $params | reduce --fold {items: [], taken: $taken} {|p, acc|
    let flag_name = (claim-flag $p.name $group ($acc.taken ++ $RESERVED_FLAG_VARS))
    let flag_var = (flag-var $flag_name)
    let item = ($p | merge {flag_name: $flag_name, flag_var: $flag_var, renamed: ($flag_name != (to-flag-name $p.name))})
    {items: ($acc.items | append $item), taken: ($acc.taken | append $flag_var)}
  }
}

# Name the body fields after every other group, so a field yields to the
# params. A required field is a positional when its plain name is free; a bool
# (a three-state flag) and a nullable field (null is a value) stay flags, and
# every flag is claimed with the `body` group. Returns {items, taken}: each
# item is the field merged with
#   is_positional : rendered as a positional arg rather than a `--flag`
#   flag_name     : the flag name when a flag; the positional var name otherwise
#   var_name      : the Nushell variable the body code reads
#   renamed       : the flag is not the plain spec name (see `rename-note`)
def decorate-body-fields [body_fields: list, taken: list<string>]: nothing -> record {
  $body_fields | reduce --fold {items: [], taken: $taken} {|f, acc|
    let reserved = ($acc.taken ++ $RESERVED_VARS)
    let plain = (to-flag-name $f.name)
    # nu-type-for and openapi-to-nu-type agree on bool-ness, so the cheaper
    # mapping is enough for the positional decision.
    let is_bool = ((openapi-to-nu-type $f.type) == "bool")
    let is_positional = $f.required and ((flag-var $plain) not-in $reserved) and (not $is_bool) and (not ($f.nullable? | default false))
    let flag_name = if $is_positional { flag-var $plain } else { claim-flag $f.name "body" $reserved }
    let var_name = (flag-var $flag_name)
    let item = ($f | merge {is_positional: $is_positional, flag_name: $flag_name, var_name: $var_name, renamed: ((not $is_positional) and ($flag_name != $plain))})
    {items: ($acc.items | append $item), taken: ($acc.taken | append $var_name)}
  }
}

# Effective positional path-param variable name. Sanitizes the path param's
# variable form and, if it collides with a reserved variable (or one of
# `reserved`, the command's own), suffixes with `_arg` so the placeholder name
# stays at the front — the user reading `<env_arg>` can map it to URL `{env}`
# at a glance.
export def effective-positional-var [name: string, reserved: list<string> = []] {
  let var = (to-flag-var $name)
  if ($var in $RESERVED_VARS) or ($var in $reserved) { $"($var)_arg" } else { $var }
}

# The variables of an AND-form op's `--token-<scheme>` flags; none for an op
# that sends one scheme (it has `--token` and `--auth-scheme` instead).
def and-token-vars [cmd: record]: nothing -> list<string> {
  let req = ($cmd.auth_required? | default [])
  if ($req | length) > 1 { $req | each {|s| $"token_($s.flag_slug)" } } else { [] }
}

# Resolve every parameter's flag and variable name once, before emission.
# `build-signature` (which declares the flags) and `op-descriptor` (which
# references the variables) both read the names decided here, so the two
# cannot disagree. Groups are walked query → header → cookie → body, each
# avoiding the names taken by the ones before it and by the path positionals.
# OpenAPI keys a parameter by name AND location, so a path `{id}` next to a
# query `id` is legal (DRF emits it for every detail route with an `id`
# filter); the positional keeps the name and the flag yields. An AND-form op's
# `--token-<scheme>` flags are taken before any of them.
def decorate-command [cmd: record]: nothing -> record {
  let token_vars = (and-token-vars $cmd)
  let path_params = ($cmd.path_params | each {|p| $p | insert var_name (effective-positional-var $p.name $token_vars) })
  let qp = (decorate-param-group $cmd.query_params "qp" (($path_params | each {|p| $p.var_name }) ++ $token_vars))
  let hdr = (decorate-param-group $cmd.header_params "hdr" $qp.taken)
  let ck = (decorate-param-group $cmd.cookie_params "ck" $hdr.taken)
  let body = (decorate-body-fields $cmd.body_fields $ck.taken)
  $cmd | merge {
    path_params: $path_params
    query_params: $qp.items
    header_params: $hdr.items
    cookie_params: $ck.items
    body_fields: $body.items
  }
}

# Collapse spec text into one line before it lands in a `#` comment: a newline
# would end the comment and leave the rest as code (a YAML block-scalar
# `title: |` made the module unparseable). Every comment that carries spec
# text — the module header, the command's extra lines, the signature docs —
# goes through here.
def flatten-description [text: string]: nothing -> string {
  $text | lines | str join " "
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
# The module's fixed completers count as taken, so an enum param named
# `baseUrl` gets `base-url-completer-1` instead of a second
# `base-url-completer` (a `duplicate_command_def`).
export def collect-completers [commands: list] {
  let initial = {completers: {}, mapping: {}, name_counts: {base-url: 1, auth-scheme: 1, unix-socket: 1}}
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

# The note a renamed flag carries: the spec name it stands for. The flag
# spelling alone may not say which spec param it is (`user_id` and `userId`
# both kebab to `user-id`, so the second one is `--body-user-id`).
def rename-note [item: record]: nothing -> string {
  if ($item.renamed? | default false) { $"\(spec name: ($item.name)\)" } else { "" }
}

# The comment text for a decorated query/header/cookie flag: its description
# and, when the flag was renamed, the spec name it stands for.
def param-doc [q: record]: nothing -> string {
  [$q.description (rename-note $q)] | where {|t| $t | is-not-empty } | str join " "
}

# The comment text for a decorated body field: its description and the shape
# of a record-typed value joined by ` — `, then the rename note.
def body-field-doc [f: record, shapes: list]: nothing -> string {
  let text = ([$f.description (lookup-shape $f.name $shapes)] | where {|t| $t | is-not-empty } | str join " — ")
  [$text (rename-note $f)] | where {|t| $t | is-not-empty } | str join " "
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
    let desc = if $config.no_descriptions or ($q.doc | is-empty) { "" } else { $" # (flatten-description $q.doc)" }
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
    $auth_req | each {|s| $"  --token-($s.flag_slug): string # (flatten-description $"Auth token for ($s.spec_name) \(($s.header_name)\)")" }
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
  # --autocompletion-unix-sockets. The default, `CLIENT.unix_socket`, is applied
  # by the runtime.
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
# `basic-credentials` to pass `user:pass` raw. Consulted by `client-const`
# (the scheme row) and the `auth-scheme-completer`.
def offers-basic-credentials [auth_schemes: list]: nothing -> bool {
  $auth_schemes | any {|s| $s.prefix == "Basic" and $s.in == "header" }
}

# The `CLIENT` constant: what the runtime needs to know about the client as a
# whole. `auth_schemes` has one row per `--auth-scheme` value (the first
# declaration of a name wins) saying where the credential goes, plus the
# `basic-credentials` row when the spec offers HTTP Basic. `unix_socket` is
# present only for a client generated with one.
def client-const [ctx: record, config: record, default_sock: any]: nothing -> list<string> {
  let schemes = ($ctx.auth_schemes | uniq-by name | each {|s| {name: $s.name, in: $s.in, header_name: $s.header_name, prefix: $s.prefix} })
  let schemes = if (offers-basic-credentials $ctx.auth_schemes) and ("basic-credentials" not-in ($schemes | each {|s| $s.name })) {
    $schemes | append {name: "basic-credentials", in: "header", header_name: "Authorization", prefix: "Basic", base64: true}
  } else { $schemes }
  let scheme_lines = if ($schemes | is-empty) { ['  auth_schemes: []'] } else {
    ['  auth_schemes: ['] ++ ($schemes | each {|s| $"    ($s | nu-literal)" }) ++ ['  ]']
  }
  [
    'const CLIENT = {'
    $'  base_url: ($ctx.base_url | to nuon)'
    $'  token_env_var: ($ctx.token_env_var | to nuon)'
    $'  timeout: (duration-literal $config.default_timeout)'
    $'  default_headers: ($config.default_headers? | default {} | nu-literal)'
    ...$scheme_lines
    ...(if (unix-socket-enabled $config) { [$'  unix_socket: ($default_sock | to nuon)'] } else { [] })
    '}'
  ]
}

# The body part of a descriptor: the media type and its encoding
# (`body_kind`), both decided by model; what pipeline input the body takes
# (`merge-body-input`'s `accepts`); the per-field flags unless the body is one
# `--body` value; and the multipart fields sent as files.
def body-descriptor [cmd: record]: nothing -> record {
  # A oneOf/anyOf with an array variant takes a piped list as the whole body;
  # a scalar or opaque body takes any piped value; else only a record merges.
  let accepts = if ($cmd.body_polymorphic_array? | default false) {
    "list"
  } else if ($cmd.body_kind == "opaque") or (($cmd.body_scalar_type? | default "any") != "any") {
    "scalar"
  } else { "record" }
  let per_field = ($cmd.body_fields | is-not-empty) and (not $cmd.body_collapsed)
  let fields = if not $per_field { [] } else {
    $cmd.body_fields | enumerate | each {|it|
      let f = $it.item
      # A form or multipart array whose encoding is csv/ssv/tsv/pipes (a
      # Swagger 2 formData `collectionFormat`) is sent as one joined value;
      # `url build-query` would otherwise repeat the key and the multipart
      # envelope JSON-stringify the list.
      let join = if ($cmd.body_kind in [form multipart]) {
        match ($f.collection_style? | default null) { "csv" => ",", "ssv" => " ", "tsv" => "\t", "pipes" => "|", _ => null }
      } else { null }
      # A required field the runtime must check after the pipeline merge: a
      # positional is always given, and null is a legal nullable value.
      let check = ($f.required? | default false) and (not $f.is_positional) and (not ($f.nullable? | default false))
      # The spec name is the body key; one nothing survives of gets a
      # synthetic name.
      {name: (if ($f.name | is-empty) { $"field-($it.index + 1)" } else { $f.name }), var: $f.var_name}
      | merge (if $join == null { {} } else { {join: $join} })
      | merge (if $check { {required: true} } else { {} })
    }
  }
  # File fields: Swagger 2 `type: file` and OpenAPI 3 `format: binary`.
  let files = if $cmd.body_kind != "multipart" { [] } else {
    $cmd.body_fields | where {|f|
      ($f.type? | default "") == "file" or (($f.type? | default "") == "string" and ($f.format? | default null) == "binary")
    } | each {|f| $f.name }
  }
  {content_type: $cmd.content_type, kind: $cmd.body_kind}
  | merge (if $accepts == "record" { {} } else { {accepts: $accepts} })
  | merge (if ($fields | is-empty) { {} } else { {fields: $fields} })
  | merge (if ($files | is-empty) { {} } else { {files: $files} })
}

# The descriptor of a decorated command (see `decorate-command`): the facts
# the runtime's `build-request` needs to build its request, as data. Keys
# that would be empty are left out; `build-request` documents every key.
# Each spec param names the variable that holds its value.
def op-descriptor [cmd: record]: nothing -> record {
  # A required query/header/cookie param, and the value it takes when the
  # flag is left out (the spec default, or a single-member enum).
  let required = {|p|
    if not ($p.required? | default false) { {} } else if ($p.required_default? == null) { {required: true} } else { {required: true, default: $p.required_default} }
  }
  let path_params = ($cmd.path_params | each {|p|
    # An array is comma-joined in its segment; a greedy label (`{Key+}`)
    # keeps its `/` between encoded segments.
    let encode = if ($p.type == "array") { {encode: array} } else if ($p.greedy? | default false) { {encode: greedy} } else { {} }
    {name: $p.name, var: $p.var_name} | merge $encode
  })
  let query = ($cmd.query_params | each {|q|
    {name: $q.name, var: $q.flag_var} | merge (if $q.collection_style == "scalar" { {} } else { {style: $q.collection_style} }) | merge (do $required $q)
  })
  # A header or cookie can't repeat, so an array is comma-joined (`array`).
  let simple = {|p| {name: $p.name, var: $p.flag_var} | merge (if $p.type == "array" { {array: true} } else { {} }) | merge (do $required $p) }
  let auth_req = ($cmd.auth_required? | default [])
  let auth = if ($auth_req | length) > 1 {
    [[auth_all ($auth_req | each {|s| {scheme: $s.name, var: $"token_($s.flag_slug)", env: $s.env_var} })]]
  } else {
    [[auth $cmd.default_auth]]
  }
  [
    [method $cmd.method]
    [path $cmd.path_template]
    [fixed_query ($cmd.fixed_query? | default "")]
    [path_params $path_params]
    [query $query]
    [header ($cmd.header_params | each $simple)]
    [cookie ($cmd.cookie_params | each $simple)]
    [body (if $cmd.has_body { body-descriptor $cmd } else { null })]
    [accept $cmd.accept_types]
    [ok ($cmd.success_codes? | default [])]
    [base_url $cmd.base_url]
  ] ++ $auth
  | where {|kv| ($kv.0 == "ok") or ($kv.1 | is-not-empty) }
  | reduce --fold {} {|kv, acc| $acc | insert $kv.0 $kv.1 }
}

# The body of a decorated command: one `http-request` call with its
# descriptor and every argument the command received, keyed by variable
# name: the spec params in signature order, then the generator's flags.
def build-call [cmd: record, config: record]: nothing -> string {
  let desc = (op-descriptor $cmd)
  let per_field = ($cmd.body_fields | is-not-empty) and (not $cmd.body_collapsed)
  let spec_vars = (
    ($cmd.path_params | each {|p| $p.var_name })
    ++ ($cmd.query_params | each {|q| $q.flag_var })
    ++ ($cmd.header_params | each {|q| $q.flag_var })
    ++ ($cmd.cookie_params | each {|q| $q.flag_var })
    ++ (if not $cmd.has_body { [] } else if $per_field { $cmd.body_fields | each {|f| $f.var_name } } else { [body] })
  )
  let token_vars = (and-token-vars $cmd)
  let generic_vars = (
    [base_url]
    ++ (if ($token_vars | is-empty) { [token auth_scheme] } else { $token_vars })
    ++ [insecure max_time raw allow_errors full dry_run]
    ++ (if (unix-socket-enabled $config) { [unix_socket] } else { [] })
    ++ (if ($cmd.accept_types | length) > 1 { [accept] } else { [] })
  )
  let arg_line = {|vars| $vars | each {|v| $"($v | str-literal): $($v)" } | str join ", " }
  let pipe = if $cmd.has_body { "$in | " } else { "" }
  [
    $"  ($pipe)http-request {"
    ...($desc | items {|k, v| $"    ($k): ($v | nu-literal)" })
    '  } {'
    ...(if ($spec_vars | is-empty) { [] } else { [$"    (do $arg_line $spec_vars)"] })
    $"    (do $arg_line $generic_vars)"
    '  }'
  ] | str join "\n"
}

# Render the module header: comment header, the `CLIENT` constant, the
# runtime, completers, introspection command. `ctx` is {title, version_str,
# spec_file, token_env_var, base_url, all_urls, commands, auth_schemes,
# completers}, built by `client`.
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
    | append ($and_schemes | each {|s| flatten-description $"# Auth \(($s.spec_name)\): --token-($s.flag_slug) flag or $env.($s.env_var)" })
  )
  # `help` is listed defensively: nushell's `scope` (0.117) does not report it
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
    ...(client-const $ctx $config $default_sock)
    ""
    ...(runtime-source "runtime.nu")
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
    $cmd_lines ++= ($extra | each { flatten-description $in })
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
  # and `commands`; so it is left out there. `http-request` is `any -> any`,
  # so the annotation is never runtime-checked against the actual body —
  # purely a parse-time + doc improvement.
  let return_str = (nu-type-string $cmd.return_type)
  let output_type = if $return_str == "any" { "any" } else {
    let record_member = if ($return_str | str starts-with "record") { [] } else { ["record"] }
    $"oneof<([$return_str "string"] ++ $record_member ++ ["nothing"] | uniq | str join ', ')>"
  }
  $cmd_lines ++= [$"]: ($input_type) -> ($output_type) {"]

  $cmd_lines ++= [(build-call $cmd $config)]
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
  # and `into string` would render it `1`. Both land in the header comment.
  let title = (flatten-description $"($loaded.data.info?.title? | default $module_name)")
  let version_str = (flatten-description $"($loaded.data.info?.version? | default '0.0.0')")
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

  let completer_data = (collect-completers $commands)
  let completers = $completer_data.completers
  let mapping = $completer_data.mapping

  let header = render-module-header {
    title: $title, version_str: $version_str, spec_file: $loaded.source, token_env_var: $token_env_var
    base_url: $base_url, all_urls: $all_urls, commands: $commands, auth_schemes: $auth_schemes
    completers: $completers
  } $config

  let command_sections = ($commands | each {|cmd| render-command $cmd $mapping $config })

  [$header] | append $command_sections | str join "\n"
}
