# model.nu — OpenAPI/Swagger command-model builder.
#
# Extracts operations from an OpenAPI 3.x / Swagger 2.0 spec and produces
# the command model consumed by render.nu. Spec loading/parsing lives in
# `src/spec/` (`spec load-spec`).

use spec/spec.nu
use log.nu

# ── Private helpers ────────────────────────────────────────────────

# Process header or cookie params into a uniform record list.
def process-simple-params [params: list, location: string, h: record] {
  $params | where {|p| ($p.in? | default "") == $location } | each {|p|
    let example = ($p.schema?.example? | default $p.example?)
    let desc_base = ($p.description? | default "")
    let deprecated = ($p.deprecated? | default false)
    {
      name: $p.name
      type: (do $h.get-param-type $p)
      items_type: (do $h.get-param-items-type $p)
      required: ($p.required? | default false)
      description: (spec build-description $desc_base [
        (if $deprecated { "DEPRECATED" } else { null })
        (if ($example != null) { $"e.g. ($example)" } else { null })
      ])
      enum: (spec clean-enum-values (do $h.get-param-enum $p))
      deprecated: $deprecated
    }
  }
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
def merge-body-props [schema: record, schemas: record] {
  let all_of_resolved = (($schema.allOf? | default [])
    | each {|sub| spec resolve-ref $sub $schemas }
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
    | each {|v| spec resolve-ref $v $schemas }
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
def extract-body-fields [schema: record, schemas: record] {
  let merged = (merge-body-props $schema $schemas)
  let props = $merged.props
  let required = $merged.required
  # Filter out malformed entries where a property value isn't a schema record
  # (e.g. meilisearch's open-api.yaml uses `$ref` as a property name, leaving
  # a bare string sibling that would crash subsequent cell-path accesses).
  $props | items {|name, field_spec|
    if (($field_spec | describe) | str starts-with "record") {
      {name: $name, field_spec: (spec resolve-ref $field_spec $schemas)}
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
    # Issue 13.A.
    let raw_type = ($field.field_spec.type? | default "any")
    let raw_type_desc = ($raw_type | describe)
    let field_type = if ($raw_type_desc | str starts-with "record") {
      log warn $"field ($field.name): record-typed `.type` \(malformed spec\) → coerced to any"
      "any"
    } else {
      spec normalize-type $raw_type
    }
    let items_type = if $field_type == "array" {
      let items = (spec resolve-ref ($field.field_spec.items? | default {}) $schemas)
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
      (if ($default_val != null) { $"default: ($default_val)" } else { null })
      (if ($example != null) { $"e.g. ($example)" } else { null })
    ])
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
    }
  }
}

# Build shape documentation entries for complex-typed body fields (record/list).
# Returns list of {flag: string, shape: string, is_item: bool}.
def build-field-shapes [schema: record, schemas: record] {
  let merged = (merge-body-props $schema $schemas)
  $merged.props | items {|name, field_spec|
    if (not (($field_spec | describe) | str starts-with "record")) {
      null
    } else {
      let fs = (spec resolve-ref $field_spec $schemas)
      let ft = (spec normalize-type ($fs.type? | default ""))
      if ($ft == "object") or (($ft == "" or $ft == "any") and ($fs.properties? | is-not-empty)) {
        let sub_fields = (extract-body-fields $fs $schemas)
        if ($sub_fields | is-empty) { null } else {
          {flag: $name, fields: $sub_fields, is_item: false}
        }
      } else if $ft == "array" {
        let items = ($fs.items? | default {})
        let resolved_items = (spec resolve-ref $items $schemas)
        if ($resolved_items.properties? | is-not-empty) or ($resolved_items.allOf? | is-not-empty) {
          let sub_fields = (extract-body-fields $resolved_items $schemas)
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

# Names Nushell refuses as a `def`: parser keywords cannot be shadowed, and
# `main` / `commands` are already defined by the generated module itself.
# NOT the flag/variable reserved list (that one lives in render): `get`,
# `delete`, `in`, `version` and `nothing` are all fine as module command names.
const UNUSABLE_NAMES = [
  use let mut const def module source overlay export export-env alias hide extern
  if match for while loop break continue return where try
  main commands
]

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
  sanitize-command-name $"($method) ($url_path | str replace --all --regex '[{}]' ' ')"
}

# The generator's own answer for one operation, before any `--name-fn` override.
# Returns {name, source} — `source` tells the override closure which rule fired.
def derive-command-name [op: record, method: string, url_path: string]: nothing -> record {
  let from_op_id = (sanitize-command-name ($op.operationId? | default ""))
  if ($from_op_id | is-empty) or ($from_op_id in $UNUSABLE_NAMES) {
    {name: (path-slug $method $url_path), source: "path"}
  } else {
    {name: $from_op_id, source: "operation-id"}
  }
}

# Resolve PathItem-level $ref. Returns the methods record.
def resolve-path-item [path_entry: record, schemas: record] {
  if ("$ref" in ($path_entry.methods | columns)) {
    let resolved = (spec resolve-ref $path_entry.methods $schemas)
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
  # "none". 42.A.
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

  # D-7 (issue 51): AND-form security. A SINGLE requirement object listing
  # MULTIPLE schemes means ALL of them must be sent together on every request
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
        $cols | each {|rn| $auth_schemes | where {|s| $s.spec_name == $rn } | first } | compact
      } else { [] }
    } else { [] }
  }

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
def classify-params [op: record, methods: record, schemas: record, h: record] {
  # merge path-level params with operation params (op overrides path-level)
  let path_level_params = ($methods.parameters? | default [])
  let op_params = ($op.parameters? | default [])
  let op_param_keys = $op_params | each {|p| $"($p.name? | default ''):($p.in? | default '')" }
  let parameters = ($path_level_params | where {|p|
    let key = $"($p.name? | default ''):($p.in? | default '')"
    not ($key in $op_param_keys)
  } | append $op_params)

  # resolve $ref in params, filter out body params
  # resolve-ref is shallow, so we also resolve the nested .schema if it's a ref
  let resolved_params = $parameters | each {|p|
    let resolved = if ("$ref" in ($p | columns)) {
      spec resolve-ref $p $schemas
    } else { $p }
    let s = ($resolved.schema? | default null)
    if (($s | describe) | str starts-with "record") and ("$ref" in ($s | columns)) {
      $resolved | upsert schema (spec resolve-ref $s $schemas)
    } else {
      $resolved
    }
  } | where {|p| ($p.in? | default "") in ["path" "query" "header" "cookie"] }

  # classify params
  let path_params = $resolved_params | where {|p| ($p.in? | default "") == "path" } | each {|p|
    {
      name: ($p.name | str replace --all '-' '_')
      original_name: $p.name
      type: (do $h.get-param-type $p)
      required: ($p.required? | default true)
    }
  }

  let query_params = $resolved_params | where {|p| ($p.in? | default "") == "query" } | each {|p|
    let default_val = ($p.schema?.default? | default $p.default?)
    let format = ($p.schema?.format? | default $p.format?)
    let example = ($p.schema?.example? | default ($p.example? | default ($p | get -o "x-example")))
    let param_type = (do $h.get-param-type $p)
    let collection_style = (do $h.get-param-collection-style $p)
    let deprecated = ($p.deprecated? | default false)
    let nullable = ($p.schema?.nullable? | default false)
    let allow_empty = ($p.allowEmptyValue? | default false)
    let desc_base = ($p.description? | default "")
    let description = (spec build-description $desc_base [
      (if $deprecated { "DEPRECATED" } else { null })
      (if $nullable { "nullable" } else { null })
      (if ($format != null) { $"format: ($format)" } else { null })
      (if ($default_val != null) { $"default: ($default_val)" } else { null })
      (if ($example != null) { $"e.g. ($example)" } else { null })
      (if $allow_empty { "allows empty value" } else { null })
    ])
    {
      name: $p.name
      type: $param_type
      items_type: (do $h.get-param-items-type $p)
      required: ($p.required? | default false)
      description: $description
      enum: (spec clean-enum-values (do $h.get-param-enum $p))
      collection_style: $collection_style
      deprecated: $deprecated
    }
  }

  let header_params = (process-simple-params $resolved_params "header" $h)
  let cookie_params = (process-simple-params $resolved_params "cookie" $h)

  {path_params: $path_params, query_params: $query_params, header_params: $header_params, cookie_params: $cookie_params}
}

# Extract body info: has_body, content_type, body_fields, discriminator.
def extract-body-info [op: record, schemas: record, h: record, spec_data: record] {
  let body_info = (do $h.get-body-info $op $schemas $spec_data)
  let has_body = $body_info.has_body
  let content_type = ($body_info.content_type? | default $spec.CT_JSON)

  # Issue 25.A: when the body content-type is non-priority (e.g. text/plain,
  # text/xml, application/vnd.X+json), `get-body-info` records the
  # content_type but returns an empty `body_schema` because it only resolves
  # schemas for application/json / multipart / form-urlencoded. To surface
  # `body_scalar_type` for those endpoints, bridge here by re-reading the
  # schema directly from op.requestBody.content.{content_type}.schema (OA3
  # shape only — Swagger 2 always uses application/json so its body_schema
  # is already populated by get-body-info).
  let body_schema = if ($body_info.body_schema | is-empty) and $has_body and (($op.requestBody? | describe) | str starts-with "record") {
    let rb = (spec resolve-ref ($op.requestBody) $schemas)
    let content = ($rb.content? | default {})
    let s = ($content | get -o $content_type | default {} | get -o schema)
    if ($s | is-not-empty) {
      spec resolve-ref $s $schemas
    } else {
      {}
    }
  } else {
    $body_info.body_schema
  }

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
  let has_schema = ($body_schema | is-not-empty) and (($body_schema | describe) | str starts-with "record") and ($body_schema | is-not-empty)
  let expand_fields = $has_schema and ($priority_ct or (not $has_body))
  let body_fields = if $expand_fields {
    extract-body-fields $body_schema $schemas
  } else {
    []
  }
  let field_shapes = if $expand_fields {
    build-field-shapes $body_schema $schemas
  } else {
    []
  }

  # discriminator info
  let body_disc = (normalize-discriminator (if (($body_schema | describe) | str starts-with "record") { $body_schema.discriminator? | default null } else { null }))
  let responses = ($op.responses? | default {})
  let resp_discs = $responses | transpose code resp | where {|r|
    ($r.code | str starts-with "2") or ($r.code == "default") or ($r.code =~ '^[12][xX]{2}$')
  } | each {|r|
    let content = ($r.resp.content? | default {})
    let json_schema = ($content | get -o "application/json" | default {} | get -o schema | default {})
    let resolved = (spec resolve-ref $json_schema $schemas)
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
  # the request body (e.g. GitHub branch-protection contexts). Issue 13.B.
  let body_polymorphic_array = if (($body_schema | describe) | str starts-with "record") {
    let variants = ($body_schema.oneOf? | default ($body_schema.anyOf? | default []))
    $variants | any {|v|
      let resolved = (spec resolve-ref $v $schemas)
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
  # Issue 25.A: non-record schemas (`type: string`/`integer`/etc.) and
  # non-JSON content-types like text/xml were unreachable because the
  # generator hardcoded `--body: record` and the pipeline-merge dropped
  # non-record input.
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

# Extract response info: accept_types, return_type, returns_body.
def extract-response-info [method: string, op: record, spec_data: record, schemas: record, h: record] {
  let accept_types = (do $h.get-response-content-types $op $spec_data)

  let return_type = if ($method in ["head" "options"]) {
    "record"
  } else {
    do $h.get-response-type $op $spec_data $schemas
  }

  let responses = ($op.responses? | default {})
  let returns_body = if ($method == "delete") {
    let resp_204 = ($responses | get -o "204")
    ($resp_204 | is-empty)
  } else if ($method in ["head" "options"]) {
    false
  } else {
    true
  }

  # Spec-declared success codes (2xx/3xx) gate handle-response's error throw.
  # Empty list → spec enumerated none → the client falls back to `< 400`.
  let success_codes = (do $h.get-success-codes $op)

  {accept_types: $accept_types, return_type: $return_type, returns_body: $returns_body, success_codes: $success_codes}
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
      path: ($params.path_params | each {|p| $p.original_name? | default $p.name })
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
export def command-list [spec_data: record, schemas: record, h: record, auth_schemes: list, root_default_auth: string, root_auth_required: list, config: record] {
  ($spec_data.paths | spec drop-vendor-extensions) | transpose path methods | each {|path_entry|
    # PATH PREFIX FILTER
    if ($config.filter_prefixes | is-not-empty) {
      let matches = ($config.filter_prefixes | any {|prefix| $path_entry.path | str starts-with $prefix })
      if not $matches { return null }
    }

    let methods = (resolve-path-item $path_entry $schemas)

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

      let params = (classify-params $op $methods $schemas $h)
      # Synthesize path params for undeclared URL template placeholders
      let declared_originals = ($params.path_params | each {|p| $p.original_name? | default $p.name })
      let template_placeholders = ($clean_path | split row '{' | skip 1 | each {|s| $s | split row '}' | first } | where {|s| $s =~ '^\w+$' })
      let extra_path_params = $template_placeholders | where {|ph| not ($ph in $declared_originals) } | each {|ph|
        {name: ($ph | str replace --all '-' '_'), original_name: $ph, type: "any", required: true}
      }
      let params = if ($extra_path_params | is-empty) { $params } else {
        $params | update path_params ($params.path_params | append $extra_path_params)
      }
      # Reorder path_params to match URL template order. Path-param emission and
      # positional-flag order are taken straight from this list, so a spec that
      # declares params in a different order (e.g. alphabetical) than the URL
      # template would route calls to the wrong endpoint (e.g. `{namespace}/{name}`
      # called as `(name, namespace)` would swap them).
      let params = $params | update path_params ($params.path_params | sort-by {|p|
        let token = $"{($p.original_name? | default $p.name)}"
        let idx = ($clean_path | str index-of $token)
        if $idx < 0 { 999999 } else { $idx }
      })
      let body = (extract-body-info $op $schemas $h $spec_data)
      let resp = (extract-response-info $method $op $spec_data $schemas $h)
      let derived_name = (derive-command-name $op $method $clean_path)
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

      let endpoint_line = $"($method | str uppercase) ($clean_path)"

      {
        name: $cmd_name
        method: $method
        path_template: $clean_path
        path_params: $params.path_params
        query_params: $params.query_params
        header_params: $params.header_params
        cookie_params: $params.cookie_params
        # D-11: GET/HEAD/OPTIONS cannot carry a request body — Nushell's
        # `http get`/`head`/`options` builtins take no body argument, so
        # do-request silently drops it. Suppress all body plumbing (body
        # flags, req_body construction, the do-request body arg, and the
        # dry-run body) for these methods so the client never advertises a
        # body it cannot send and --dry-run matches what goes on the wire.
        has_body: ($body.has_body and not ($method in [get head options]))
        content_type: $body.content_type
        body_fields: $body.body_fields
        body_polymorphic_array: $body.body_polymorphic_array
        body_scalar_type: $body.body_scalar_type
        field_shapes: $field_shapes
        body_collapsed: $body_collapsed
        returns_body: $resp.returns_body
        description: $meta.description
        extra_doc_lines: (if ($meta.description | is-not-empty) { [$"# ($endpoint_line)"] } else { [] })
        operation_id: $meta.operation_id
        deprecated: $meta.deprecated
        deprecation_reason: null
        external_docs: $meta.external_docs
        default_auth: $meta.default_auth
        auth_required: $meta.auth_required
        base_url: $meta.base_url
        accept_types: $resp.accept_types
        success_codes: $resp.success_codes
        discriminator: $body.discriminator
        return_type: $resp.return_type
        tags: ($op.tags? | default [])
      }
    }
  } | flatten | compact | deduplicate-commands
}
