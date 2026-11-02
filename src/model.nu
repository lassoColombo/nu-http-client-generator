# model.nu — OpenAPI/Swagger command-model builder.
#
# Extracts operations from an OpenAPI 3.x / Swagger 2.0 spec and produces
# the command model consumed by render.nu. Spec loading/parsing lives in
# `src/spec/` (`spec load-spec`).

use spec/spec.nu
use log.nu

# ── Private helpers ────────────────────────────────────────────────

# The command-model record for one query/header/cookie param. OpenAPI 3 keeps
# the value facts under `.schema`, Swagger 2 puts them on the param itself, so
# each is read from the schema first and the param second.
def build-param [p: record, h: record] {
  let schema = ($p.schema? | default {})
  let default_val = ($schema.default? | default $p.default?)
  let format = ($schema.format? | default $p.format?)
  let example = ($schema.example? | default ($p.example? | default ($p | get -o "x-example")))
  let deprecated = ($p.deprecated? | default false)
  let nullable = (spec is-nullable $schema)
  let allow_empty = ($p.allowEmptyValue? | default false)
  let required = ($p.required? | default false)
  let enum = (spec clean-enum-values (do $h.get-param-enum $p))
  # The value a REQUIRED param takes when the caller gives none: the spec
  # `default`, else a single-member enum (AWS JSON-RPC's `X-Amz-Target`
  # header is `required: true, enum: [one-value]`). Optional params keep
  # their default documentary only — sending it explicitly would change the
  # wire for callers who left the flag out.
  let required_default = if not $required { null } else if ($default_val != null) { $default_val } else if ($enum | length) == 1 { $enum | first } else { null }
  {
    name: $p.name
    type: (do $h.get-param-type $p)
    items_type: (do $h.get-param-items-type $p)
    required: $required
    required_default: $required_default
    description: (spec build-description ($p.description? | default "") [
      (if $required { "required" } else { null })
      (if $deprecated { "DEPRECATED" } else { null })
      (if $nullable { "nullable" } else { null })
      (if ($format != null) { $"format: ($format)" } else { null })
      (default-note $default_val)
      (if ($example != null) { $"e.g. ($example)" } else { null })
      (if $allow_empty { "allows empty value" } else { null })
    ])
    enum: $enum
    collection_style: (do $h.get-param-collection-style $p)
    deprecated: $deprecated
  }
}

# `default: X` description note; an empty-string default is shown as `""`
# rather than vanishing into `(default: , e.g. NONE)`.
def default-note [default_val: any]: nothing -> any {
  if ($default_val == null) { return null }
  let text = $"($default_val)"
  if ($text | is-empty) { 'default: ""' } else { $"default: ($text)" }
}

# Normalize a discriminator into {propertyName, mapping}. OAS 3.x discriminators
# are records; Swagger 2.0 encodes them as bare strings (just the propertyName).
# Returns null when there is no discriminator.
def normalize-discriminator [disc: any] {
  let t = ($disc | describe)
  if ($t | str starts-with "record") {
    {propertyName: ($disc.propertyName? | default ""), mapping: ($disc.mapping? | default {})}
  } else if ($t == "string") {
    {propertyName: $disc, mapping: {}}
  } else {
    null
  }
}

# Merge properties from a body schema, handling allOf/oneOf/anyOf/discriminator.
# Returns {props: record, required: list<string>}.
def merge-body-props [schema: record, doc: record] {
  let all_of_resolved = (($schema.allOf? | default [])
    | each {|sub| spec resolve-ref $sub $doc }
    | where {($in | describe) | str starts-with "record"})

  let props_after_allof = ($all_of_resolved | reduce -f ($schema.properties? | default {}) {|s, acc|
    $acc | merge ($s.properties? | default {})
  })
  let required_after_allof = ($all_of_resolved | reduce -f ($schema.required? | default []) {|s, acc|
    $acc | append ($s.required? | default [])
  })

  let disc = (normalize-discriminator ($schema.discriminator? | default null))
  let disc_prop = if ($disc != null) { $disc.propertyName } else { null }
  let disc_mapping = if ($disc != null) { $disc.mapping } else { {} }

  let poly_resolved = (($schema.oneOf? | default ($schema.anyOf? | default []))
    | each {|v| spec resolve-ref $v $doc }
    | where {($in | describe) | str starts-with "record"})

  let merged_props_pre_disc = ($poly_resolved | reduce -f $props_after_allof {|v, acc|
    let v_props = ($v.properties? | default {})
    $v_props | items {|col, val|
      if $col in ($acc | columns) { null } else { {col: $col, val: $val} }
    } | compact | reduce -f $acc {|kv, a| $a | insert $kv.col $kv.val }
  })
  let merged_required_pre_disc = $required_after_allof

  let merged_required = if ($disc_prop in ($merged_props_pre_disc | columns)) {
    $merged_required_pre_disc | append $disc_prop | uniq
  } else {
    $merged_required_pre_disc
  }
  let merged_props = if ($disc_prop in ($merged_props_pre_disc | columns)) and ($disc_mapping | is-not-empty) {
    $merged_props_pre_disc | upsert $disc_prop ($merged_props_pre_disc | get $disc_prop | upsert enum ($disc_mapping | columns))
  } else {
    $merged_props_pre_disc
  }

  {props: $merged_props, required: $merged_required}
}

# Extract body field info from a resolved request body schema
def extract-body-fields [schema: record, doc: record] {
  body-fields-from-props (merge-body-props $schema $doc) $doc
}

# Body field info from an already-merged {props, required} (see merge-body-props).
def body-fields-from-props [merged: record, doc: record] {
  let props = $merged.props
  let required = $merged.required
  # Filter out malformed entries where a property value isn't a schema record
  # (e.g. meilisearch's open-api.yaml uses `$ref` as a property name, leaving
  # a bare string sibling that would crash subsequent cell-path accesses).
  $props | items {|name, field_spec|
    if (($field_spec | describe) | str starts-with "record") {
      # resolve, then fold allOf so a `{allOf: [{$ref}, {description}]}`
      # wrapper (every AWS property) yields the member's type + the description
      {name: $name, field_spec: (spec merge-all-of (spec resolve-ref $field_spec $doc) $doc)}
    } else {
      {name: $name, field_spec: $field_spec}
    }
  } | where {|field|
    ($field.field_spec | describe | str starts-with "record")
  } | where {|field|
    not ($field.field_spec.readOnly? | default false)
  } | each {|field|
    # Defensive guard: a malformed spec may leave `.type` as a record (e.g.
    # codat.io/accounting nests `definitions.itemType` one level too deep, so
    # the JSON-Pointer resolves to `{type: {description, enum, type}}` instead
    # of the inner schema). Records can't be coerced to a render-time type
    # string, so fall back to "any". OAS 3.1 list-typed unions (e.g.
    # `[string, null]`) are still handled by `normalize-type`. Logged as a
    # warning so a legitimate generator regression doesn't degrade silently.
    let raw_type = ($field.field_spec.type? | default "any")
    let raw_type_desc = ($raw_type | describe)
    let field_type = if ($raw_type_desc | str starts-with "record") {
      log warn $"field ($field.name): record-typed `.type` \(malformed spec\) → coerced to any"
      "any"
    } else {
      spec normalize-type $raw_type
    }
    let items_type = if $field_type == "array" {
      let items = (spec resolve-ref ($field.field_spec.items? | default {}) $doc)
      spec normalize-type ($items.type? | default null)
    } else { null }
    let enum_vals = (spec clean-enum-values ($field.field_spec.enum? | default []))
    let nullable = (spec is-nullable $field.field_spec)
    let desc_base = ($field.field_spec.description? | default "")
    let default_val = ($field.field_spec.default? | default null)
    let format = ($field.field_spec.format? | default null)
    let example = ($field.field_spec.example? | default null)
    let deprecated = ($field.field_spec.deprecated? | default false)
    let desc = (spec build-description $desc_base [
      (if $deprecated { "DEPRECATED" } else { null })
      (if $nullable { "nullable" } else { null })
      (if ($format != null) { $"format: ($format)" } else { null })
      (default-note $default_val)
      (if ($example != null) { $"e.g. ($example)" } else { null })
    ])
    # Swagger 2 formData arrays carry a `collectionFormat` (synthesized onto
    # the property by spec/swagger2); render joins csv/ssv/tsv/pipes lists
    # before the form body is url-encoded. Null means "repeat the key".
    let collection_style = if $field_type == "array" { $field.field_spec.collectionFormat? | default null } else { null }
    {
      name: $field.name
      type: $field_type
      items_type: $items_type
      required: ($field.name in $required)
      nullable: $nullable
      enum: $enum_vals
      description: $desc
      deprecated: $deprecated
      format: $format
      collection_style: $collection_style
    }
  }
}

# Build shape documentation entries for complex-typed body fields (record/list)
# from an already-merged props record (see merge-body-props).
# Returns list of {flag: string, fields: list, is_item: bool}.
def build-field-shapes [props: record, doc: record] {
  $props | items {|name, field_spec|
    if (not (($field_spec | describe) | str starts-with "record")) {
      null
    } else {
      let fs = (spec merge-all-of (spec resolve-ref $field_spec $doc) $doc)
      let ft = (spec normalize-type ($fs.type? | default ""))
      if ($ft == "object") or (($ft == "" or $ft == "any") and ($fs.properties? | is-not-empty)) {
        let sub_fields = (extract-body-fields $fs $doc)
        if ($sub_fields | is-empty) { null } else {
          {flag: $name, fields: $sub_fields, is_item: false}
        }
      } else if $ft == "array" {
        let items = ($fs.items? | default {})
        let resolved_items = (spec resolve-ref $items $doc)
        if ($resolved_items.properties? | is-not-empty) or ($resolved_items.allOf? | is-not-empty) {
          let sub_fields = (extract-body-fields $resolved_items $doc)
          if ($sub_fields | is-empty) { null } else {
            {flag: $name, fields: $sub_fields, is_item: true}
          }
        } else { null }
      } else { null }
    }
  } | compact
}

# ── Command naming ─────────────────────────────────────────────────
#
# The operationId IS the name. OpenAPI requires it to be unique per document
# and real specs honour that, so the generator sanitizes it and gets out of the
# way — no verb vocabulary, no path curation, no namespace/action split.
#
#   1. operationId, sanitized to a valid `def` name.
#   2. absent, or sanitizing to something unusable -> a mechanical method+path
#      slug, which is unique per (method, path) by construction.
#
# A user `--name-fn` closure can replace the result per operation (see
# `apply-name-fn`). `deduplicate-commands` then guarantees every name is unique
# and legal — it is the ONLY collision machinery left.

# Names a generated command must not take. Three families, all fatal or
# silently wrong inside the emitted module:
#   1. Parser keywords — `nu::parser::name_is_keyword`, a hard parse error.
#   2. Nushell builtin commands. A module-level `export def "get"` shadows the
#      builtin for every helper in the SAME module, so `$env | get -o X` inside
#      `build-auth` resolves to the generated command (`unknown_flag` /
#      `extra_positional` at parse time, or a silent wrong call at runtime for
#      input-only builtins like `is-not-empty`). Every single-word builtin of
#      nushell 0.116 is listed; the set rarely changes and the cost of an
#      unneeded entry is one slug-named command, not a broken client.
#   3. The module's own defs: the static helper library (`send-post`,
#      `build-url`, …), the completers (`*-completer`) and `main`/`commands`.
#      A collision is `nu::parser::duplicate_command_def`.
# An unusable operationId falls back to the method+path slug; an unusable slug
# (`GET /` → `get`) gets an `-op` suffix. NOT the flag/variable reserved list
# — that one lives in render and is about variables, not commands.
const PARSER_KEYWORDS = [
  alias break collect const continue def export export-env extern for hide if let loop match module
  mut overlay plugin return run source source-env try use where while
]
const NU_BUILTIN_COMMANDS = [
  abbr all ansi any append ast attr bits bytes cal cd char chunk-by chunks clear columns combinations
  commandline compact complete config cp date debug decode default describe detect difference do drop
  du each echo encode enumerate error every exec exit explain explore fill filter find first flatten
  format from generate get glob grid group-by hash headers help hide-env histogram history http idx
  ignore input insert inspect interleave intersect into is-admin is-empty is-not-empty is-redirected
  is-terminal items job join keybindings kill last length let-env lines load-env ls math matrix merge
  metadata mkdir mktemp move mv nu-check nu-highlight open panic par-each parse path peek
  permutations port prepend print ps random reduce reject rename reverse rm roll rotate
  run-external run-internal save schema scope select semver seq shuffle skip sleep slice sort sort-by
  split start stor str sys table take tee term timeit to touch transpose tui tutor ulimit umask uname
  union uniq uniq-by unlet update upsert url values version view watch which whoami window with-env
  wrap zip
]
const EMITTED_DEF_NAMES = [
  main commands
  build-auth merge-auth serialize-qp encode-path-segment encode-path-array build-url status-ok
  handle-response build-multipart-body
  send-get send-post send-put send-patch send-delete send-head send-options
  base-url-completer auth-scheme-completer unix-socket-completer
]
const UNUSABLE_NAMES = ($PARSER_KEYWORDS ++ $NU_BUILTIN_COMMANDS ++ $EMITTED_DEF_NAMES)

# Is this a name the generated module cannot export? See UNUSABLE_NAMES; the
# `-completer` suffix is reserved because every enum param gets a
# `<flag>-completer` def of its own.
def name-unusable [name: string]: nothing -> bool {
  ($name in $UNUSABLE_NAMES) or ($name | str ends-with "-completer")
}

# Sanitize an arbitrary string to a valid `def "<name>"`: drop path
# placeholders, turn `/ . _ :` and whitespace runs into `-`, and let
# `str kebab-case` do the camelCase splitting and lowercasing
# (`Databases_Get` -> `databases-get`, `repos/get-release` -> `repos-get-release`).
# Returns "" when nothing survives — callers decide the fallback.
def sanitize-command-name [name: string]: nothing -> string {
  $name
  | str replace --all --regex '\{[^}]*\}' ''
  | str replace --all --regex '[^A-Za-z0-9 _./:-]' ''
  | str replace --all --regex '[ _./:]+' '-'
  | str kebab-case
  | str trim --char '-'
}

# Mechanical name for operations with no usable operationId. Braces become
# separators rather than being dropped, so path-param names survive as segments
# (`GET /pet/{petId}` -> `get-pet-pet-id`). That is what makes the slug unique
# per (method, path) — dropping the params instead collides 80x more often.
def path-slug [method: string, url_path: string]: nothing -> string {
  sanitize-command-name $"($method) ($url_path | str replace --all --regex '[{}?=&]' ' ')"
}

# The generator's own answer for one operation, before any `--name-fn` override.
# Returns {name, source} — `source` tells the override closure which rule fired.
def derive-command-name [op: record, method: string, url_path: string]: nothing -> record {
  let from_op_id = (sanitize-command-name ($op.operationId? | default ""))
  if ($from_op_id | is-empty) or (name-unusable $from_op_id) {
    let slug = (path-slug $method $url_path)
    {name: (if (name-unusable $slug) { $"($slug)-op" } else { $slug }), source: "path"}
  } else {
    {name: $from_op_id, source: "operation-id"}
  }
}

# Resolve PathItem-level $ref. Returns the methods record.
def resolve-path-item [path_entry: record, doc: record] {
  if ("$ref" in ($path_entry.methods | columns)) {
    let resolved = (spec resolve-ref $path_entry.methods $doc)
    if ("$ref" in ($resolved | columns)) {
      log warn $"unresolved PathItem $ref for path '($path_entry.path)', skipping referenced operations"
      $path_entry.methods
    } else {
      $resolved
    }
  } else {
    $path_entry.methods
  }
}

# Extract operation-level metadata: description, auth, server override, etc.
def extract-op-metadata [op: record, auth_schemes: list, root_default_auth: string, root_auth_required: list, methods: record, h: record] {
  let operation_id = ($op.operationId? | default "")
  let summary = ($op.summary? | default "")
  let description_text = ($op.description? | default "")
  let description = (spec normalize-description (if ($summary | is-not-empty) { $summary } else { $description_text }))
  let deprecated = ($op.deprecated? | default false)
  let external_docs = ($op.externalDocs? | default null)

  # per-operation security override.
  # OAS3 §4.8.30: `security: []` (empty array) removes the top-level security
  # declaration for this operation. Use `!= null` (not `is-not-empty`) so
  # an empty array enters the override branch and yields "none". The legacy
  # `[{}]` form (one empty record meaning "no auth required") also yields
  # "none".
  let op_security = ($op.security?)
  let default_auth = if ($op_security != null) {
    if ($op_security | is-empty) {
      "none"
    } else {
      let first_req = ($op_security | first)
      if (($first_req | describe) | str starts-with "record") and ($first_req | is-not-empty) {
        let ref_name = ($first_req | columns | first)
        let matched = $auth_schemes | where {|s| $s.spec_name == $ref_name }
        if ($matched | is-not-empty) { $matched | first | get name } else { $root_default_auth }
      } else {
        "none"
      }
    }
  } else {
    $root_default_auth
  }

  # AND-form security. A SINGLE requirement object listing MULTIPLE schemes
  # means ALL of them must be sent together on every request
  # (OA3 §4.8.30 / Swagger 2.0). The `default_auth` above keeps only the first
  # scheme — correct for the OR-form OUTER array (where each object is an
  # alternative), but wrong for the inner AND-set. Detect AND-form as the first
  # requirement object having >1 column and resolve EVERY named scheme to its
  # record. Downstream render emits one `--token-<scheme>` flag per scheme and
  # merges all their headers/query. A single-column object (including the
  # `basic` -> `basic-credentials` render-time expansion, which is still ONE
  # column at the requirement level) stays on the single-scheme path with an
  # empty list here. An op with NO `security` override inherits the GLOBAL
  # AND-set (`root_auth_required`) — this is the VTEX shape, where the AND-form
  # lives at the top level. `security: []` (public) overrides to no auth.
  let auth_required = if ($op_security == null) {
    $root_auth_required
  } else if ($op_security | is-empty) {
    []
  } else {
    let first_req = ($op_security | first)
    if (($first_req | describe) | str starts-with "record") and ($first_req | is-not-empty) {
      let cols = ($first_req | columns)
      if ($cols | length) > 1 {
        collapse-wire-identical ($cols | each {|rn| $auth_schemes | where {|s| $s.spec_name == $rn } | first } | compact)
      } else { [] }
    } else { [] }
  }
  # An AND-set that collapsed to one wire credential is a single-scheme op.
  let default_auth = if ($auth_required | length) == 1 { $auth_required | first | get name } else { $default_auth }
  let auth_required = if ($auth_required | length) == 1 { [] } else { $auth_required }

  # per-operation/path server overrides — resolve {var} placeholders via dispatch helper
  let chosen_server = ($op.servers?.0? | default $methods.servers?.0?)
  let base_url = if ($chosen_server == null) { null } else { do $h.resolve-server-url $chosen_server }

  {
    description: $description
    operation_id: $operation_id
    deprecated: $deprecated
    external_docs: $external_docs
    default_auth: $default_auth
    auth_required: $auth_required
    base_url: $base_url
  }
}

# Drop AND-set members that put the same credential in the same place.
# Google declares `{Oauth2: [...], Oauth2c: [...]}` — two oauth2 schemes that
# both become `Authorization: Bearer` — so two `--token-*` flags would write
# one header and the second would silently win. Keyed on the wire facts
# (location, header/param name, prefix), first occurrence kept.
def collapse-wire-identical [schemes: list]: nothing -> list {
  $schemes | reduce --fold [] {|s, acc|
    let same = ($acc | any {|a| ($a.in == $s.in) and ($a.header_name == $s.header_name) and ($a.prefix == $s.prefix) })
    if $same { $acc } else { $acc | append $s }
  }
}

# Merge path+op params, resolve refs, split into path/query/header/cookie categories.
def classify-params [op: record, methods: record, doc: record, h: record] {
  # Resolve $ref in params FIRST: the path-level/op dedup below keys on
  # `name:in`, and an unresolved `{$ref: …}` has neither, so it would survive
  # next to the op's own same-named param and emit a duplicate flag.
  # resolve-ref is shallow, so also resolve the nested .schema if it's a ref.
  let resolve = {|p|
    let resolved = (spec resolve-ref $p $doc)
    let s = ($resolved.schema? | default null)
    if (($s | describe) | str starts-with "record") and ("$ref" in ($s | columns)) {
      $resolved | upsert schema (spec resolve-ref $s $doc)
    } else {
      $resolved
    }
  }
  let path_level_params = ($methods.parameters? | default [] | each $resolve)
  let op_params = ($op.parameters? | default [] | each $resolve)

  # merge path-level params with operation params (op overrides path-level)
  let op_param_keys = $op_params | each {|p| $"($p.name? | default ''):($p.in? | default '')" }
  let resolved_params = ($path_level_params | where {|p|
    let key = $"($p.name? | default ''):($p.in? | default '')"
    not ($key in $op_param_keys)
  } | append $op_params
  ) | where {|p| ($p.in? | default "") in ["path" "query" "header" "cookie"] }

  # Path params keep the spec name, the (items) type and the enum: render
  # derives the positional variable name from the spec name, types an array
  # positional `list<string>` (a bare `list` would parse `[01 02]` as ints and
  # send `1,2`), and wires an enum completer like it does for flags.
  let path_params = $resolved_params | where {|p| ($p.in? | default "") == "path" } | each {|p|
    {name: $p.name, type: (do $h.get-param-type $p), items_type: (do $h.get-param-items-type $p), enum: (spec clean-enum-values (do $h.get-param-enum $p))}
  }
  let in_location = {|loc| $resolved_params | where {|p| ($p.in? | default "") == $loc } | each {|p| build-param $p $h } }

  {
    path_params: $path_params
    query_params: (do $in_location "query")
    header_params: (do $in_location "header")
    cookie_params: (do $in_location "cookie")
  }
}

# Extract body info: has_body, content_type, body_fields, discriminator.
#
# GET/HEAD/OPTIONS cannot carry a request body — Nushell's `http get`/`head`/
# `options` builtins take no body argument — so for those methods every body
# artefact (has_body, fields, shapes) is suppressed together: the client must
# never advertise a flag it cannot send, and --dry-run must match the wire.
def extract-body-info [method: string, op: record, doc: record, h: record, label: string] {
  let body_info = (do $h.get-body-info $op $doc)
  let bodyless_method = ($method in ["get" "head" "options"])
  if $body_info.has_body and $bodyless_method {
    log warn $"($label): ($method | str uppercase) cannot carry a request body in nushell; the declared body/formData params are dropped and the command may be uncallable"
  }
  let has_body = $body_info.has_body and (not $bodyless_method)
  let content_type = ($body_info.content_type? | default $spec.CT_JSON)
  let body_schema = $body_info.body_schema

  # For non-JSON content-types (text/xml, application/vnd.X+json, …) we do
  # NOT expand record schemas into per-field flags: there is no canonical
  # Nushell-record-to-XML codec, no canonical record-to-octet-stream codec,
  # etc. Callers pre-serialize and either pass a string via --body or pipe
  # one into the operation. Per-field flags would be misleading. JSON-family
  # content-types still expand because `http post --content-type application/json
  # <record>` auto-encodes correctly. Multipart and form-urlencoded also
  # expand — the renderer has dedicated `build-multipart-body` and
  # `url build-query` codecs for them.
  let priority_ct = ($content_type | str starts-with "application/json") or ($content_type == "multipart/form-data") or ($content_type == "application/x-www-form-urlencoded")
  let has_schema = (($body_schema | describe) | str starts-with "record") and ($body_schema | is-not-empty)
  let expand_fields = $has_body and $has_schema and $priority_ct
  let merged = if $expand_fields { merge-body-props $body_schema $doc } else { {props: {}, required: []} }
  let body_fields = (body-fields-from-props $merged $doc)
  let field_shapes = (build-field-shapes $merged.props $doc)

  # discriminator info
  let body_disc = (normalize-discriminator (if (($body_schema | describe) | str starts-with "record") { $body_schema.discriminator? | default null } else { null }))
  let responses = ($op.responses? | default {})
  let resp_discs = $responses | transpose code resp | where {|r|
    ($r.code | str starts-with "2") or ($r.code == "default") or ($r.code =~ '^[12][xX]{2}$')
  } | each {|r|
    let content = ($r.resp.content? | default {})
    let json_schema = ($content | get -o "application/json" | default {} | get -o schema | default {})
    let resolved = (spec resolve-ref $json_schema $doc)
    if (($resolved | describe) | str starts-with "record") {
      normalize-discriminator ($resolved.discriminator? | default null)
    } else {
      null
    }
  } | compact
  let resp_disc = if ($resp_discs | is-not-empty) { $resp_discs | first } else { null }
  let discriminator = if ($body_disc != null) {
    {context: "request", propertyName: $body_disc.propertyName, mapping: $body_disc.mapping}
  } else if ($resp_disc != null) {
    {context: "response", propertyName: $resp_disc.propertyName, mapping: $resp_disc.mapping}
  } else {
    null
  }

  # Detect polymorphic body schemas where one oneOf/anyOf variant is a bare
  # array. The per-field signature only covers object variants; the array
  # variant is unreachable through any flag. We flag the command so the
  # renderer can accept a list pipeline input and pass it straight through as
  # the request body (e.g. GitHub branch-protection contexts).
  let body_polymorphic_array = if (($body_schema | describe) | str starts-with "record") {
    let variants = ($body_schema.oneOf? | default ($body_schema.anyOf? | default []))
    $variants | any {|v|
      let resolved = (spec resolve-ref $v $doc)
      if (($resolved | describe) | str starts-with "record") {
        let t = ($resolved.type? | default null)
        # Plain "array" or OAS 3.1 list-typed union containing "array".
        ($t == "array") or ((($t | describe) | str starts-with "list") and ("array" in ($t | default [])))
      } else {
        false
      }
    }
  } else {
    false
  }

  # Determine the body schema's scalar type so the renderer can emit a typed
  # `--body: <type>` flag (and accept matching pipeline input) when the body
  # has no enumerable fields. "any" covers record-shaped, missing, and
  # unresolvable schemas — those keep the existing `--body: record` path.
  let body_scalar_type = if (not $has_schema) {
    "any"
  } else {
    let raw = ($body_schema.type? | default null)
    let normalized = (spec normalize-type $raw)
    if ($normalized == null) or ($normalized == "object") {
      "any"
    } else if (($normalized | describe) | str starts-with "record") {
      "any"
    } else {
      $normalized
    }
  }

  {has_body: $has_body, content_type: $content_type, body_fields: $body_fields, field_shapes: $field_shapes, discriminator: $discriminator, body_polymorphic_array: $body_polymorphic_array, body_scalar_type: $body_scalar_type}
}

# Extract response info: accept_types, return_type, success_codes.
def extract-response-info [method: string, op: record, doc: record, h: record] {
  let accept_types = (do $h.get-response-content-types $op $doc)

  let return_type = if ($method in ["head" "options"]) {
    "record"
  } else {
    do $h.get-response-type $op $doc
  }

  # Spec-declared success codes (2xx/3xx) gate handle-response's error throw.
  # Empty list → spec enumerated none → the client falls back to `< 400`.
  {accept_types: $accept_types, return_type: $return_type, success_codes: (spec get-success-codes $op)}
}

# Apply a user `--name-fn` closure to override the derived command name.
# The closure receives spec-derived context — `raw` (untouched operation
# fields), `params` (resolved param names per location), and `derived` (the
# generator's own answer plus which rule produced it) — and returns a
# replacement name, or null/"" to keep the default. The result is sanitized to
# a valid `def` name; global uniqueness is still guaranteed downstream by
# `deduplicate-commands`.
def apply-name-fn [
  name_fn: closure
  derived_name: record
  op: record
  method: string
  raw_path: string
  clean_path: string
  params: record
]: nothing -> string {
  let ctx = {
    raw: {
      operation_id: ($op.operationId? | default "")
      method: $method
      path: $raw_path
      summary: ($op.summary? | default "")
      description: ($op.description? | default "")
      tags: ($op.tags? | default [])
      deprecated: ($op.deprecated? | default false)
      op: $op
    }
    params: {
      path: ($params.path_params | each {|p| $p.name })
      query: ($params.query_params | each {|p| $p.name })
      header: ($params.header_params | each {|p| $p.name })
      cookie: ($params.cookie_params | each {|p| $p.name })
    }
    derived: {
      path: $clean_path
      default_name: $derived_name.name
      source: $derived_name.source
    }
  }
  let custom = try {
    do $name_fn $ctx
  } catch {|e|
    log warn $"name-fn threw for '($op.operationId? | default '<no opId>')': ($e.msg); using default '($derived_name.name)'"
    null
  }
  let chosen = if (($custom | describe) == "string") and ($custom | is-not-empty) { $custom } else { $derived_name.name }
  let cleaned = (sanitize-command-name $chosen)
  if ($cleaned | is-empty) { $derived_name.name } else { $cleaned }
}

# Guarantee every command name is unique and legal — the final pass of
# `command-list`. Nushell rejects a repeated `def` outright
# (`nu::parser::duplicate_command_def`), so this is a correctness requirement,
# not cosmetics. It rarely fires: operationIds are unique per spec and the path
# slug is unique per (method, path), so only two things reach it — distinct
# operationIds that kebab to the same string, and whatever a `--name-fn`
# returns. `taken` is seeded with UNUSABLE_NAMES so a closure returning `let`
# can never produce an unparseable module.
def deduplicate-commands []: list -> list {
  mut taken = ($UNUSABLE_NAMES | reduce --fold {} {|n, acc| $acc | upsert $n true })
  mut out = []
  mut renamed = []
  for cmd in $in {
    mut name = $cmd.name
    mut n = 1
    while (($taken | get -o $name) != null) {
      $name = $"($cmd.name)-($n)"
      $n = $n + 1
    }
    if $name != $cmd.name {
      $renamed = ($renamed | append $cmd.name)
    }
    $taken = ($taken | upsert $name true)
    $out = ($out | append ($cmd | update name $name))
  }
  if ($renamed | is-not-empty) {
    log info $"($renamed | uniq | length) command name\(s\) disambiguated with a numeric suffix: ($renamed | uniq | str join ', ')"
  }
  $out
}

# Build the command model list from a parsed+resolved REST spec.
export def command-list [doc: record, h: record, auth_schemes: list, root_default_auth: string, root_auth_required: list, config: record] {
  # The global AND-set collapses the same way the per-op one does.
  let root_auth_required = (collapse-wire-identical $root_auth_required)
  let root_default_auth = if ($root_auth_required | length) == 1 { $root_auth_required | first | get name } else { $root_default_auth }
  let root_auth_required = if ($root_auth_required | length) == 1 { [] } else { $root_auth_required }
  ($doc.paths | spec drop-vendor-extensions) | transpose path methods | each {|path_entry|
    # PATH PREFIX FILTER
    if ($config.filter_prefixes | is-not-empty) {
      let matches = ($config.filter_prefixes | any {|prefix| $path_entry.path | str starts-with $prefix })
      if not $matches { return null }
    }

    let methods = (resolve-path-item $path_entry $doc)

    $methods | transpose method op | where {|m|
      ($m.method in [get post put patch delete head options]) and (
        ($config.filter_methods | is-empty) or ($m.method in $config.filter_methods)
      )
    } | each {|method_entry|
      let method = $method_entry.method
      let op = $method_entry.op

      # skip if op is not a record (e.g. "parameters", "servers", "$ref" at path level)
      if not (($op | describe) | str starts-with "record") {
        return null
      }

      # TAG FILTER
      if ($config.filter_tags | is-not-empty) {
        let op_tags = ($op.tags? | default [])
        let has_match = ($config.filter_tags | any {|t| $t in $op_tags })
        if not $has_match { return null }
      }

      let meta = (extract-op-metadata $op $auth_schemes $root_default_auth $root_auth_required $methods $h)

      # DEPRECATED FILTER
      if $config.exclude_deprecated and $meta.deprecated {
        return null
      }

      # Strip OpenAPI path-key fragment (e.g. AWS `#tagKeys`, `#Content-Type`)
      # used to disambiguate ops sharing method+path. Servers treat `#…` as a
      # client-side fragment, so it must not leak into the runtime URL, command
      # name, or doc comment.
      let clean_path = ($path_entry.path | str replace --regex '#.*$' '')
      # A path key may carry a fixed query (OBS keys `/request?view=collection`
      # next to `/request`). The query part is not path text: it becomes a
      # constant query fragment appended at request time, so caller params
      # join it with `&` instead of a second `?`.
      let fixed_query = ($clean_path | split row '?' | get -o 1 | default "")
      let clean_path = ($clean_path | split row '?' | first)

      let params = (classify-params $op $methods $doc $h)
      # Synthesize path params for undeclared URL template placeholders
      let declared = ($params.path_params | each {|p| $p.name })
      let template_placeholders = ($clean_path | split row '{' | skip 1 | each {|s| $s | split row '}' | first } | where {|s| $s =~ '^\w+$' })
      let extra_path_params = $template_placeholders | where {|ph| not ($ph in $declared) } | each {|ph|
        {name: $ph, type: "any", items_type: null, enum: []}
      }
      # Order path params as the URL template does. Path-param emission and
      # positional order are taken straight from this list, so a spec that
      # declares params in a different order (e.g. alphabetical) than the URL
      # template would route calls to the wrong endpoint (e.g. `{namespace}/{name}`
      # called as `(name, namespace)` would swap them).
      let params = $params | update path_params ($params.path_params | append $extra_path_params | sort-by {|p|
        let idx = ($clean_path | str index-of $"{($p.name)}")
        if $idx < 0 { 999999 } else { $idx }
      })
      let body = (extract-body-info $method $op $doc $h $"($method | str uppercase) ($path_entry.path)")
      let resp = (extract-response-info $method $op $doc $h)
      let derived_name = (derive-command-name $op $method (if ($fixed_query | is-empty) { $clean_path } else { $"($clean_path)?($fixed_query)" }))
      let cmd_name = if ($config.name_fn? == null) {
        $derived_name.name
      } else {
        apply-name-fn $config.name_fn $derived_name $op $method $path_entry.path $clean_path $params
      }

      # Build unified field_shapes: collapsed body shape + per-field shapes.
      # field_shapes carry STRUCTURED fields; render's build-shape-doc renders
      # them to the NUON-like doc string at emit time, so model no longer
      # depends on render. `body_collapsed` is the single source of truth for
      # the --body-threshold collapse decision — render's signature and
      # body-code emitters read it verbatim instead of recomputing it.
      let body_collapsed = ($config.body_threshold > 0) and (($body.body_fields | length) > $config.body_threshold)
      let field_shapes = if $body_collapsed {
        [{flag: "body", fields: $body.body_fields, is_item: false}]
      } else {
        $body.field_shapes
      }

      {
        name: $cmd_name
        method: $method
        path_template: $clean_path
        fixed_query: $fixed_query
        path_params: $params.path_params
        query_params: $params.query_params
        header_params: $params.header_params
        cookie_params: $params.cookie_params
        has_body: $body.has_body
        content_type: $body.content_type
        body_fields: $body.body_fields
        body_polymorphic_array: $body.body_polymorphic_array
        body_scalar_type: $body.body_scalar_type
        field_shapes: $field_shapes
        body_collapsed: $body_collapsed
        description: $meta.description
        operation_id: $meta.operation_id
        deprecated: $meta.deprecated
        external_docs: $meta.external_docs
        default_auth: $meta.default_auth
        auth_required: $meta.auth_required
        base_url: $meta.base_url
        accept_types: $resp.accept_types
        success_codes: $resp.success_codes
        discriminator: $body.discriminator
        return_type: $resp.return_type
      }
    }
  } | flatten | compact | deduplicate-commands
}
