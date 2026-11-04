# model.nu — OpenAPI/Swagger command-model builder.
#
# Extracts operations from an OpenAPI 3.x / Swagger 2.0 spec and produces
# the command model consumed by render.nu. Spec loading/parsing lives in
# `src/spec/` (`spec load-spec`).

use spec/spec.nu
use log.nu
use names.nu [EMITTED_DEF_NAMES]

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
    description: (spec build-description ($p.description? | default "") (
      [(if $required { "required" } else { null })]
      ++ (value-notes $deprecated $nullable $format $default_val $example)
      ++ [(if $allow_empty { "allows empty value" } else { null })]
    ))
    enum: $enum
    collection_style: (do $h.get-param-collection-style $p)
    deprecated: $deprecated
  }
}

# The description annotations a param and a body field share, in display
# order; null entries are dropped by `build-description`. An empty-string
# default is shown as `""` rather than vanishing into `(default: , e.g. NONE)`.
def value-notes [deprecated: bool, nullable: bool, format: any, default_val: any, example: any]: nothing -> list {
  let default_text = $"($default_val)"
  [
    (if $deprecated { "DEPRECATED" } else { null })
    (if $nullable { "nullable" } else { null })
    (if ($format != null) { $"format: ($format)" } else { null })
    (if ($default_val == null) { null } else if ($default_text | is-empty) { 'default: ""' } else { $"default: ($default_text)" })
    (if ($example != null) { $"e.g. ($example)" } else { null })
  ]
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
# Returns {props: record, required: list<string>, has_array_variant: bool}.
# `has_array_variant` is true when a oneOf/anyOf variant is a bare array: the
# per-field flags only cover the object variants, so render accepts a piped
# list as the whole body (GitHub's branch-protection contexts).
def merge-body-props [schema: record, doc: record] {
  # allOf is folded by spec's merge-all-of — recursively, so a chain of
  # allOf-only wrappers (`Base: allOf [Mid]`, `Mid: allOf [Leaf, {props}]`)
  # still surfaces the leaf's properties and `required`.
  let schema = (spec merge-all-of $schema $doc)
  let props_after_allof = ($schema.properties? | default {})
  let required_after_allof = ($schema.required? | default [])

  let disc = (normalize-discriminator ($schema.discriminator? | default null))
  let disc_prop = if ($disc != null) { $disc.propertyName } else { null }
  let disc_mapping = if ($disc != null) { $disc.mapping } else { {} }

  # Each variant is resolved and its own allOf folded: the common union shape
  # is `Cat: allOf: [Pet, {meow}]`, whose fields all live inside the allOf.
  let poly_resolved = (($schema.oneOf? | default ($schema.anyOf? | default []))
    | each {|v| spec merge-all-of (spec resolve-ref $v $doc) $doc }
    | where {($in | describe) | str starts-with "record"})

  # Variant properties join in document order; a name the base (or an earlier
  # variant) already has keeps its first definition.
  let merged_props = ($poly_resolved | reduce -f $props_after_allof {|v, acc|
    ($v.properties? | default {}) | items {|col, val|
      if $col in ($acc | columns) { null } else { {col: $col, val: $val} }
    } | compact | reduce -f $acc {|kv, a| $a | insert $kv.col $kv.val }
  })

  # A field is required when the base requires it or when EVERY variant does:
  # a field only some variants require may be legitimately absent from the
  # body the caller picks. The discriminator property is implicitly required,
  # and its mapping keys are its enum.
  let variant_required = if ($poly_resolved | is-empty) { [] } else {
    $poly_resolved | each {|v| $v.required? | default [] } | reduce {|r, acc| $acc | where {|n| $n in $r } }
  }
  let has_disc = ($disc_prop in ($merged_props | columns))
  let required = ($required_after_allof | append $variant_required | append (if $has_disc { [$disc_prop] } else { [] }) | uniq)
  let props = if $has_disc and ($disc_mapping | is-not-empty) {
    $merged_props | upsert $disc_prop ($merged_props | get $disc_prop | upsert enum ($disc_mapping | columns))
  } else {
    $merged_props
  }
  # Plain `type: array` or an OAS 3.1 list-typed union containing "array".
  let has_array_variant = ($poly_resolved | any {|v|
    let t = ($v.type? | default null)
    ($t == "array") or ((($t | describe) | str starts-with "list") and ("array" in $t))
  })

  {props: $props, required: $required, has_array_variant: $has_array_variant}
}

# Body field info for a request body schema: merge, resolve, extract.
def extract-body-fields [schema: record, doc: record] {
  let merged = (merge-body-props $schema $doc)
  body-fields-from-resolved (resolve-body-props $merged.props $doc) $merged.required $doc
}

# Resolve every property of a merged props record ONCE: `$ref` followed, allOf
# folded (so an AWS-style `{allOf: [{$ref}, {description}]}` wrapper yields the
# member's type), readOnly and malformed entries dropped (meilisearch uses
# `$ref` as a property name, leaving a bare string sibling that would crash
# cell-path access). Both the body fields and the shape docs derive from this
# list. Returns list<{name, spec}>.
def resolve-body-props [props: record, doc: record]: nothing -> list {
  $props | items {|name, field_spec| {name: $name, spec: $field_spec} }
    | where {|f| ($f.spec | describe) | str starts-with "record" }
    | each {|f| {name: $f.name, spec: (spec merge-all-of (spec resolve-ref $f.spec $doc) $doc)} }
    | where {|f| (($f.spec | describe) | str starts-with "record") and (not ($f.spec.readOnly? | default false)) }
}

# Body field records from resolved props (see resolve-body-props).
def body-fields-from-resolved [resolved: list, required: list, doc: record] {
  $resolved | each {|field|
    # Defensive guard: a malformed spec may leave `.type` as a record (e.g.
    # codat.io/accounting nests `definitions.itemType` one level too deep, so
    # the JSON-Pointer resolves to `{type: {description, enum, type}}` instead
    # of the inner schema). Records can't be coerced to a render-time type
    # string, so fall back to "any". OAS 3.1 list-typed unions (e.g.
    # `[string, null]`) are still handled by `normalize-type`. Logged as a
    # warning so a legitimate generator regression doesn't degrade silently.
    let raw_type = ($field.spec.type? | default "any")
    let field_type = if (($raw_type | describe) | str starts-with "record") {
      log warn $"field ($field.name): record-typed `.type` \(malformed spec\) → coerced to any"
      "any"
    } else {
      spec normalize-type $raw_type
    }
    let items_type = if $field_type == "array" {
      let items = (spec resolve-ref ($field.spec.items? | default {}) $doc)
      spec normalize-type ($items.type? | default null)
    } else { null }
    let enum_vals = (spec clean-enum-values ($field.spec.enum? | default []))
    let nullable = (spec is-nullable $field.spec)
    let default_val = ($field.spec.default? | default null)
    let format = ($field.spec.format? | default null)
    let example = ($field.spec.example? | default null)
    let deprecated = ($field.spec.deprecated? | default false)
    let desc = (spec build-description ($field.spec.description? | default "") (value-notes $deprecated $nullable $format $default_val $example))
    # Swagger 2 formData arrays carry a `collectionFormat` (synthesized onto
    # the property by spec/swagger2); render joins csv/ssv/tsv/pipes lists
    # before the form body is url-encoded. Null means "repeat the key".
    let collection_style = if $field_type == "array" { $field.spec.collectionFormat? | default null } else { null }
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

# Shape documentation entries for the complex-typed (record / list-of-record)
# fields among resolved props (see resolve-body-props).
# Returns list of {flag: string, fields: list, is_item: bool}.
def field-shapes-from-resolved [resolved: list, doc: record] {
  $resolved | each {|f|
    let fs = $f.spec
    let ft = (spec normalize-type ($fs.type? | default ""))
    if ($ft == "object") or (($ft == "" or $ft == "any") and ($fs.properties? | is-not-empty)) {
      let sub_fields = (extract-body-fields $fs $doc)
      if ($sub_fields | is-empty) { null } else { {flag: $f.name, fields: $sub_fields, is_item: false} }
    } else if $ft == "array" {
      let items = (spec resolve-ref ($fs.items? | default {}) $doc)
      if ($items.properties? | is-not-empty) or ($items.allOf? | is-not-empty) {
        let sub_fields = (extract-body-fields $items $doc)
        if ($sub_fields | is-empty) { null } else { {flag: $f.name, fields: $sub_fields, is_item: true} }
      } else { null }
    } else { null }
  }
}

# A schema's discriminator as the command-model record {context, propertyName,
# mapping}, or null when the schema has none (or is not a record).
def schema-discriminator [schema: any, context: string] {
  if not (($schema | describe) | str starts-with "record") { return null }
  let d = (normalize-discriminator ($schema.discriminator? | default null))
  if ($d == null) { null } else { {context: $context, propertyName: $d.propertyName, mapping: $d.mapping} }
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
#   3. The module's own defs (`EMITTED_DEF_NAMES` in `names.nu`) and the enum
#      completers (`*-completer`). A collision is
#      `nu::parser::duplicate_command_def`.
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
const UNUSABLE_NAMES = ($PARSER_KEYWORDS ++ $NU_BUILTIN_COMMANDS ++ $EMITTED_DEF_NAMES)

# Is this a name the generated module cannot export? See UNUSABLE_NAMES; the
# `-completer` suffix is reserved because every enum param gets a
# `<flag>-completer` def of its own.
def name-unusable [name: string]: nothing -> bool {
  # Completers are `<flag>-completer`, and `<flag>-completer-<n>` when two
  # enum sets share a flag name.
  ($name in $UNUSABLE_NAMES) or ($name =~ '-completer(-\d+)?$')
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
  # The slug may itself be unusable (`GET /` → `get`); deduplicate-commands
  # gives every final name, slug or --name-fn result, its `-op` suffix.
  if ($from_op_id | is-empty) or (name-unusable $from_op_id) {
    {name: (path-slug $method $url_path), source: "path"}
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
def extract-op-metadata [op: record, auth_schemes: list, root_auth: record, methods: record, h: record] {
  let operation_id = ($op.operationId? | default "")
  let summary = ($op.summary? | default "")
  let description_text = ($op.description? | default "")
  let description = (spec normalize-description (if ($summary | is-not-empty) { $summary } else { $description_text }))
  let deprecated = ($op.deprecated? | default false)
  let external_docs = ($op.externalDocs? | default null)

  # per-operation security override. OAS3 §4.8.30: `security: []` removes the
  # top-level requirement (a public op); the legacy `[{}]` form means the same.
  # Otherwise the first requirement object decides: one resolved scheme is the
  # op's default; more than one is the AND-form (every scheme sent together —
  # render emits one `--token-<scheme>` flag per scheme and merges their
  # headers/query); an unknown name keeps the root default. No override
  # inherits the root answer, including the global AND-set (the VTEX shape).
  let op_security = $op.security?
  let req = if ($op_security == null) { null } else { spec requirement-schemes $op_security $auth_schemes }
  let default_auth = if ($req == null) {
    $root_auth.default
  } else if ($req.declared | is-empty) {
    "none"
  } else if ($req.schemes | is-empty) {
    $root_auth.default
  } else {
    $req.schemes | first | get name
  }
  let auth_required = if ($req == null) { $root_auth.required } else if ($req.schemes | length) > 1 { $req.schemes } else { [] }

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

# Merge path+op params, resolve refs, split into path/query/header/cookie categories.
def classify-params [op: record, methods: record, doc: record, h: record] {
  # Resolve $ref in params FIRST: the path-level/op dedup below keys on
  # `name:in`, and an unresolved `{$ref: …}` has neither, so it would survive
  # next to the op's own same-named param and emit a duplicate flag.
  # resolve-ref is shallow, so also resolve the nested .schema if it's a ref.
  # An API Gateway export declares a greedy label with its `+` (`name: proxy+`
  # for `/{proxy+}`). The `+` is no part of the name: strip it here, before the
  # merge, so the param binds `$proxy` like the normalized template, and keep
  # the fact as `greedy`.
  let resolve = {|p|
    let resolved = (spec resolve-ref $p $doc)
    let s = ($resolved.schema? | default null)
    let resolved = if (($s | describe) | str starts-with "record") and ("$ref" in ($s | columns)) {
      $resolved | upsert schema (spec resolve-ref $s $doc)
    } else {
      $resolved
    }
    let name = ($resolved.name? | default "")
    if ($resolved.in? == "path") and (($name | describe) == "string") and ($name | str ends-with "+") {
      $resolved | update name ($name | str replace --regex '\+$' '') | upsert greedy true
    } else {
      $resolved
    }
  }
  let path_level_params = ($methods.parameters? | default [] | each $resolve)
  let op_params = ($op.parameters? | default [] | each $resolve)

  # merge path-level params with operation params (op overrides path-level).
  # The merged list keeps every location: Swagger 2 `body`/`formData` params
  # are inherited from the path item too, and the body helper reads them here.
  # A param is identified by name+location, except a Swagger 2 `body`: an
  # operation has at most one, so the op's own replaces the inherited one even
  # when the two are named differently.
  let param_key = {|p|
    let loc = ($p.in? | default '')
    if $loc == "body" { "body" } else { $"($p.name? | default ''):($loc)" }
  }
  let op_param_keys = ($op_params | each $param_key)
  let all_params = ($path_level_params | where {|p| not ((do $param_key $p) in $op_param_keys) } | append $op_params)
  let resolved_params = ($all_params | where {|p| ($p.in? | default "") in ["path" "query" "header" "cookie"] })

  # Path params keep the spec name, the (items) type and the enum: render
  # derives the positional variable name from the spec name, types an array
  # positional `list<string>` (a bare `list` would parse `[01 02]` as ints and
  # send `1,2`), and wires an enum completer like it does for flags.
  let path_params = $resolved_params | where {|p| ($p.in? | default "") == "path" } | each {|p|
    {name: $p.name, type: (do $h.get-param-type $p), items_type: (do $h.get-param-items-type $p), enum: (spec clean-enum-values (do $h.get-param-enum $p)), greedy: ($p.greedy? | default false)}
  }
  let in_location = {|loc| $resolved_params | where {|p| ($p.in? | default "") == $loc } | each {|p| build-param $p $h } }

  {
    all_params: $all_params
    path_params: $path_params
    query_params: (do $in_location "query")
    header_params: (do $in_location "header")
    cookie_params: (do $in_location "cookie")
  }
}

# Extract body info: has_body, content_type, body_fields, request discriminator.
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
  # `body_kind` is the one place this is decided, and render matches on it
  # instead of re-reading content-type strings:
  #   none      — no request body (or a GET/HEAD/OPTIONS that cannot send one)
  #   json      — JSON-family; nushell's `http` encodes a record itself
  #   form      — x-www-form-urlencoded; render emits `url build-query`
  #   multipart — multipart/form-data; render emits `build-multipart-body`
  #   opaque    — anything else; the caller supplies the wire form
  let body_kind = if not $has_body { "none" } else if ($content_type | str starts-with "application/json") { "json" } else if $content_type == $spec.CT_FORM { "form" } else if $content_type == $spec.CT_MULTIPART { "multipart" } else { "opaque" }
  # A body the command cannot send has no shape worth computing: render reads
  # every body field, scalar type and array variant under `has_body` only.
  let has_schema = $has_body and (($body_schema | describe) | str starts-with "record") and ($body_schema | is-not-empty)
  let expand_fields = $has_schema and ($body_kind in ["json" "form" "multipart"])
  # Merged for every sendable schema-bearing body (an opaque one still reports
  # its array variant); its fields only become flags when they can be encoded.
  let merged = if $has_schema { merge-body-props $body_schema $doc } else { {props: {}, required: [], has_array_variant: false} }
  let resolved = if $expand_fields { resolve-body-props $merged.props $doc } else { [] }
  let body_fields = (body-fields-from-resolved $resolved $merged.required $doc)
  let field_shapes = (field-shapes-from-resolved $resolved $doc)

  # The request-side discriminator; the response side is extract-response-info's.
  let discriminator = (schema-discriminator $body_schema "request")

  # Determine the body schema's scalar type so the renderer can emit a typed
  # `--body: <type>` flag (and accept matching pipeline input) when the body
  # has no enumerable fields. "any" covers record-shaped, missing, and
  # unresolvable schemas — those keep the existing `--body: record` path.
  let body_scalar_type = if (not $has_schema) {
    "any"
  } else {
    let normalized = (spec normalize-type ($body_schema.type? | default null))
    if ($normalized == null) or ($normalized == "object") { "any" } else { $normalized }
  }

  {has_body: $has_body, content_type: $content_type, body_kind: $body_kind, body_fields: $body_fields, field_shapes: $field_shapes, discriminator: $discriminator, body_polymorphic_array: $merged.has_array_variant, body_scalar_type: $body_scalar_type}
}

# Extract response info: accept_types, return_type, success_codes, discriminator.
def extract-response-info [method: string, op: record, doc: record, h: record] {
  let accept_types = (do $h.get-response-content-types $op $doc)
  # Best candidate first; the return type is the first schema, the
  # discriminator the first one any success response declares (a `201` next
  # to a plain `200` still documents its discriminator).
  let schemas = (do $h.get-response-schemas $op $doc)
  let return_type = if ($method in ["head" "options"]) {
    "record"
  } else if ($schemas | is-empty) {
    "any"
  } else {
    spec schema-to-type-descriptor ($schemas | first) $doc
  }
  # Spec-declared success codes (2xx/3xx) gate handle-response's error throw.
  # Empty list → spec enumerated none → the client falls back to `< 400`.
  {
    accept_types: $accept_types
    return_type: $return_type
    success_codes: (spec get-success-codes $op)
    discriminator: ($schemas | each {|s| schema-discriminator (spec resolve-ref $s $doc) "response" } | get -o 0)
  }
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
# returns. An unusable name (a closure returning `let` or `status-completer`)
# first takes the same `-op` suffix `derive-command-name` gives an unusable
# slug, so the module always parses.
def deduplicate-commands []: list -> list {
  mut taken = {}
  mut out = []
  mut renamed = []
  for cmd in $in {
    let base = if (name-unusable $cmd.name) { $"($cmd.name)-op" } else { $cmd.name }
    mut name = $base
    mut n = 1
    while (($taken | get -o $name) != null) or (name-unusable $name) {
      $name = $"($base)-($n)"
      $n = $n + 1
    }
    if $name != $cmd.name {
      $renamed ++= [$cmd.name]
    }
    $taken = ($taken | upsert $name true)
    $out ++= [($cmd | update name $name)]
  }
  if ($renamed | is-not-empty) {
    log info $"($renamed | uniq | length) command name\(s\) renamed to stay unique and legal: ($renamed | uniq | str join ', ')"
  }
  $out
}

# Build the command model list from a parsed+resolved REST spec.
export def command-list [doc: record, h: record, auth_schemes: list, root_auth: record, config: record] {
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

      let meta = (extract-op-metadata $op $auth_schemes $root_auth $methods $h)

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
      # AWS greedy labels (`/{Bucket}/{Key+}`) match the rest of the path,
      # slashes included. The `+` is not part of the name (AWS declares `Key`;
      # API Gateway declares `Key+`, stripped by classify-params), so the
      # template is normalized to `{Key}` and the param is marked greedy:
      # render encodes it per segment, keeping its `/`.
      let greedy_names = ($clean_path | parse --regex '\{(?P<n>[^{}]+)\+\}' | get n)
      let clean_path = ($clean_path | str replace --all --regex '\{([^{}]+)\+\}' '{${1}}')

      let params = (classify-params $op $methods $doc $h)
      # Synthesize path params for undeclared URL template placeholders
      let declared = ($params.path_params | each {|p| $p.name })
      let template_placeholders = ($clean_path | split row '{' | skip 1 | each {|s| $s | split row '}' | first } | where {|s| $s =~ '^\w+$' })
      let extra_path_params = $template_placeholders | where {|ph| not ($ph in $declared) } | each {|ph|
        {name: $ph, type: "any", items_type: null, enum: [], greedy: false}
      }
      # Order path params as the URL template does. Path-param emission and
      # positional order are taken straight from this list, so a spec that
      # declares params in a different order (e.g. alphabetical) than the URL
      # template would route calls to the wrong endpoint (e.g. `{namespace}/{name}`
      # called as `(name, namespace)` would swap them).
      # One positional per name: two params binding the same variable would
      # silently keep only the later value, so a spec that declares a name
      # twice (`Key` and `Key+`) keeps the first.
      let params = $params | update path_params ($params.path_params | append $extra_path_params | sort-by {|p|
        let idx = ($clean_path | str index-of $"{($p.name)}")
        if $idx < 0 { 999999 } else { $idx }
      } | uniq-by name | each {|p| $p | update greedy ($p.greedy or ($p.name in $greedy_names)) })
      let body = (extract-body-info $method ($op | upsert parameters $params.all_params) $doc $h $"($method | str uppercase) ($path_entry.path)")
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
        body_kind: $body.body_kind
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
        discriminator: ($body.discriminator | default $resp.discriminator)
        return_type: $resp.return_type
      }
    }
  } | flatten | deduplicate-commands
}
