# build-rest.nu — REST/OpenAPI command-model builder.
#
# Extracts operations from an OpenAPI 3.x / Swagger 2.0 spec and produces
# the unified command model consumed by render.nu.

use ../spec/spec.nu
use ../render
use ../log

# ─── Spec loading ──────────────────────────────────────────────────
#
# The URL path goes through `spec fetch-text` (raw fetch + UTF-8 decode)
# instead of `http get`'s auto-parser — see the helper for the rationale.

# Load an OpenAPI/Swagger spec from a local file or a URL.
# Returns {data: record, source: string}.
export def load-spec [source: string, headers: record = {}] {
  if ($source | str starts-with "http://") or ($source | str starts-with "https://") {
    let body = (spec fetch-text $source $headers)
    {data: (parse-spec-text $body $source), source: $source}
  } else {
    let expanded = ($source | path expand | into string)
    {data: (open $expanded), source: $expanded}
  }
}

# Parse a raw spec body, picking JSON or YAML based on the source URL's
# extension and falling back to "try JSON then YAML" when there's no hint.
def parse-spec-text [body: string, source: string]: nothing -> any {
  if ($source | str ends-with ".json") {
    return ($body | from json)
  }
  if ($source | str ends-with ".yaml") or ($source | str ends-with ".yml") {
    return ($body | from yaml)
  }
  try {
    $body | from json
  } catch {
    try {
      $body | from yaml
    } catch {
      error make --unspanned { msg: $"could not parse spec from ($source): not valid JSON or YAML" }
    }
  }
}

# Build command model + metadata from a REST spec.
# Returns {commands, auth_schemes, default_auth, base_url, all_urls}.
export def build-commands [spec_data: record, schemas: record, h: record, config: record] {
  let auth_schemes = (do $h.get-auth-schemes $spec_data)
  let default_auth = (spec get-default-auth $spec_data $auth_schemes)
  let base_url = (do $h.get-base-url $spec_data)
  let all_urls = (do $h.get-all-urls $spec_data)
  let commands = build-command-list $spec_data $schemas $h $auth_schemes $default_auth $config
  {commands: $commands, auth_schemes: $auth_schemes, default_auth: $default_auth, base_url: $base_url, all_urls: $all_urls}
}

# ── Private helpers ────────────────────────────────────────────────

# Process header or cookie params into a uniform record list.
def process-simple-params [params: list, location: string, h: record] {
  $params | where {|p| ($p.in? | default "") == $location } | each {|p|
    let example = ($p.schema?.example? | default ($p.example? | default null))
    let desc_base = (spec get-param-description $p)
    let deprecated = ($p.deprecated? | default false)
    {
      name: $p.name
      type: (do $h.get-param-type $p)
      required: ($p.required? | default false)
      description: (spec build-description $desc_base [
        (if $deprecated { "DEPRECATED" } else { null })
        (if ($example != null) { $"e.g. ($example)" } else { null })
      ])
      enum: (do $h.get-param-enum $p)
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
  mut merged_props = ($schema.properties? | default {})
  mut merged_required = ($schema.required? | default [])
  let all_of = ($schema.allOf? | default [])
  for sub in $all_of {
    let resolved_sub = (spec resolve-ref $sub $schemas)
    if (($resolved_sub | describe) | str starts-with "record") {
      let sub_props = ($resolved_sub.properties? | default {})
      let sub_req = ($resolved_sub.required? | default [])
      $merged_props = ($merged_props | merge $sub_props)
      $merged_required = ($merged_required | append $sub_req)
    }
  }

  let disc = (normalize-discriminator ($schema.discriminator? | default null))
  let disc_prop = if ($disc != null) { $disc.propertyName } else { null }
  let disc_mapping = if ($disc != null) { $disc.mapping } else { {} }
  let poly_variants = ($schema.oneOf? | default ($schema.anyOf? | default []))
  for variant in $poly_variants {
    let resolved_variant = (spec resolve-ref $variant $schemas)
    if (($resolved_variant | describe) | str starts-with "record") {
      let v_props = ($resolved_variant.properties? | default {})
      for col in ($v_props | columns) {
        if not ($col in ($merged_props | columns)) {
          $merged_props = ($merged_props | insert $col ($v_props | get $col))
        }
      }
    }
  }

  if ($disc_prop != null) and ($disc_prop in ($merged_props | columns)) {
    $merged_required = ($merged_required | append $disc_prop | uniq)
    if ($disc_mapping | columns | length) > 0 {
      $merged_props = ($merged_props | upsert $disc_prop ($merged_props | get $disc_prop | upsert enum ($disc_mapping | columns)))
    }
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
  $props | transpose name field_spec | where {|field|
    ($field.field_spec | describe | str starts-with "record")
  } | where {|field|
    not ($field.field_spec.readOnly? | default false)
  } | each {|field|
    let field_type = (spec normalize-type ($field.field_spec.type? | default "any"))
    let enum_vals = ($field.field_spec.enum? | default [])
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
      required: ($field.name in $required)
      nullable: $nullable
      enum: $enum_vals
      description: $desc
      deprecated: $deprecated
    }
  }
}

# Build shape documentation entries for complex-typed body fields (record/list).
# Returns list of {flag: string, shape: string, is_item: bool}.
def build-field-shapes [schema: record, schemas: record] {
  let merged = (merge-body-props $schema $schemas)
  $merged.props | transpose name field_spec | where {|field|
    ($field.field_spec | describe | str starts-with "record")
  } | each {|field|
    let fs = (spec resolve-ref $field.field_spec $schemas)
    let ft = (spec normalize-type ($fs.type? | default ""))
    if ($ft == "object") or (($ft == "" or $ft == "any") and ($fs.properties? | is-not-empty)) {
      let sub_fields = (extract-body-fields $fs $schemas)
      if ($sub_fields | is-empty) { null } else {
        {flag: $field.name, shape: (render build-shape-doc $sub_fields), is_item: false}
      }
    } else if $ft == "array" {
      let items = ($fs.items? | default {})
      let resolved_items = (spec resolve-ref $items $schemas)
      if ($resolved_items.properties? | is-not-empty) or ($resolved_items.allOf? | is-not-empty) {
        let sub_fields = (extract-body-fields $resolved_items $schemas)
        if ($sub_fields | is-empty) { null } else {
          {flag: $field.name, shape: (render build-shape-doc $sub_fields), is_item: true}
        }
      } else { null }
    } else { null }
  } | compact
}

# Map OpenAPI method actions to command verbs
def action-verb [action: string] {
  match $action {
    "retrieve" => "get"
    "destroy" => "delete"
    "partial_update" => "patch"
    _ => $action
  }
}

# Resolve PathItem-level $ref. Returns the methods record.
def resolve-path-item [path_entry: record, schemas: record] {
  if ($path_entry.methods | columns | any {|c| $c == "$ref"}) {
    let resolved = (spec resolve-ref $path_entry.methods $schemas)
    if ($resolved | columns | any {|c| $c == "$ref"}) {
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
def extract-op-metadata [op: record, auth_schemes: list, root_default_auth: string, methods: record] {
  let operation_id = ($op.operationId? | default "")
  let summary = ($op.summary? | default "")
  let description_text = ($op.description? | default "")
  let description = if ($summary | is-not-empty) { $summary } else { $description_text }
  let deprecated = ($op.deprecated? | default false)
  let external_docs = ($op.externalDocs? | default null)

  # per-operation security override
  let op_security = ($op.security?)
  let default_auth = if ($op_security | is-not-empty) {
    if ($op_security | length) == 0 {
      "none"
    } else {
      let first_req = ($op_security | first)
      if (($first_req | describe) | str starts-with "record") and (($first_req | columns | length) > 0) {
        let ref_name = ($first_req | columns | first)
        let matched = $auth_schemes | where {|s| $s.spec_name == $ref_name }
        if ($matched | length) > 0 { $matched | first | get name } else { $root_default_auth }
      } else {
        $root_default_auth
      }
    }
  } else {
    $root_default_auth
  }

  # per-operation/path server overrides
  let base_url = ($op.servers?.0?.url? | default ($methods.servers?.0?.url? | default null))

  {
    description: $description
    operation_id: $operation_id
    deprecated: $deprecated
    external_docs: $external_docs
    default_auth: $default_auth
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
  let resolved_params = $parameters | each {|p|
    if ($p | columns | any {|c| $c == "$ref"}) {
      spec resolve-ref $p $schemas
    } else {
      $p
    }
  } | spec get-non-body-params $in

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
    let default_val = ($p.schema?.default? | default ($p.default? | default null))
    let format = ($p.schema?.format? | default ($p.format? | default null))
    let example = ($p.schema?.example? | default ($p.example? | default ($p | get -o "x-example" | default null)))
    let param_type = (do $h.get-param-type $p)
    let collection_style = (do $h.get-param-collection-style $p)
    let deprecated = ($p.deprecated? | default false)
    let nullable = ($p.schema?.nullable? | default false)
    let allow_empty = ($p.allowEmptyValue? | default false)
    let desc_base = (spec get-param-description $p)
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
      required: ($p.required? | default false)
      description: $description
      enum: (do $h.get-param-enum $p)
      collection_style: $collection_style
      deprecated: $deprecated
    }
  }

  let header_params = (process-simple-params $resolved_params "header" $h)
  let cookie_params = (process-simple-params $resolved_params "cookie" $h)

  {path_params: $path_params, query_params: $query_params, header_params: $header_params, cookie_params: $cookie_params}
}

# Extract body info: has_body, content_type, body_fields, discriminator.
def extract-body-info [op: record, schemas: record, h: record] {
  let body_info = (do $h.get-body-info $op $schemas)
  let has_body = $body_info.has_body
  let body_schema = $body_info.body_schema
  let content_type = ($body_info.content_type? | default $spec.CT_JSON)

  let has_schema = ($body_schema | is-not-empty) and (($body_schema | describe) | str starts-with "record") and (($body_schema | columns | length) > 0)
  let body_fields = if $has_schema {
    extract-body-fields $body_schema $schemas
  } else {
    []
  }
  let field_shapes = if $has_schema {
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
  } | where { $in != null }
  let resp_disc = if ($resp_discs | length) > 0 { $resp_discs | first } else { null }
  let discriminator = if ($body_disc != null) {
    {context: "request", propertyName: $body_disc.propertyName, mapping: $body_disc.mapping}
  } else if ($resp_disc != null) {
    {context: "response", propertyName: $resp_disc.propertyName, mapping: $resp_disc.mapping}
  } else {
    null
  }

  {has_body: $has_body, content_type: $content_type, body_fields: $body_fields, field_shapes: $field_shapes, discriminator: $discriminator}
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

  {accept_types: $accept_types, return_type: $return_type, returns_body: $returns_body}
}

# Derive command name from path, method, operationId, tags, and path params.
def derive-command-name [url_path: string, method: string, operation_id: string, tags: list, path_params: list, verb_map: record] {
  let path_segments = ($url_path | split row '/' | where {|s|
    ($s | is-not-empty) and ($s != "api") and (not ($s | str starts-with "{")) and (not ($s =~ '^v\d+$'))
  })
  let resource = if ($path_segments | length) > 0 {
    $path_segments | where {|s| $s != "-" and $s != "--" }
    | each {|s| $s | str replace --all --regex '[\\$()*\[\]=\x27",.$#!@%^&+~`]' '' }
    | where {|s| $s | is-not-empty }
    | str join '-' | str kebab-case
  } else if ($tags | length) > 0 {
    $tags.0 | str kebab-case
  } else {
    "api"
  }

  let action_raw = if ($operation_id | is-not-empty) {
    let parts = ($operation_id | split row '_')
    let last_part = ($parts | last)
    if ($last_part =~ '^\d+$') and ($parts | length) >= 2 {
      let action_part = ($parts | get (($parts | length) - 2))
      $action_part
    } else if ($parts | length) >= 2 and ($parts | last 2 | str join '_') == "partial_update" {
      "partial_update"
    } else {
      $last_part
    }
  } else {
    $method
  }

  # Apply custom verb map override, then camelCase check, then default mapping
  let action_mapped = ($verb_map | get -o $action_raw | default null)
  let action_picked = if ($action_mapped != null) {
    $action_mapped
  } else if ($action_raw =~ '^(get|post|put|patch|delete)[A-Z]') {
    $method
  } else {
    action-verb $action_raw
  }

  # Strip chars that break `def "..." [...]` names. Some specs (e.g. Sentry)
  # use free-text operationIds like "Retrieve Statuses (Alpha)" — without
  # this, the parens/spaces flow straight into the generated def name.
  # Only kicks in when the action has unsafe chars — leaves clean camelCase
  # action names (findPetsByStatus, etc.) untouched.
  let action = if ($action_picked =~ '[\s\\$()*\[\]=\x27",.#!@%^&+~`]') {
    let cleaned = (
      $action_picked
      | str replace --all --regex '[\\$()*\[\]=\x27",.$#!@%^&+~`]' ''
      | str trim
      | str replace --all --regex '\s+' '-'
    )
    if ($cleaned | is-empty) { $method } else { $cleaned }
  } else {
    $action_picked
  }

  # detect _2 deduplication pattern
  let is_duplicate = if ($operation_id | is-not-empty) {
    let parts = ($operation_id | split row '_')
    let last_part = ($parts | last)
    ($last_part =~ '^\d+$') and ($parts | length) >= 2
  } else {
    false
  }

  if $is_duplicate {
    let param_suffix = $path_params | each {|p| $p.name } | str join '-'
    $"($resource) ($action)-by-($param_suffix)"
  } else {
    $"($resource) ($action)"
  }
}

# Build the command model list from a parsed+resolved REST spec.
def build-command-list [spec_data: record, schemas: record, h: record, auth_schemes: list, root_default_auth: string, config: record] {
  $spec_data.paths | transpose path methods | each {|path_entry|
    # PATH PREFIX FILTER
    if ($config.filter_prefixes | length) > 0 {
      let matches = ($config.filter_prefixes | any {|prefix| $path_entry.path | str starts-with $prefix })
      if not $matches { return null }
    }

    let methods = (resolve-path-item $path_entry $schemas)

    $methods | transpose method op | where {|m|
      ($m.method in [get post put patch delete head options]) and (
        ($config.filter_methods | length) == 0 or ($m.method in $config.filter_methods)
      )
    } | each {|method_entry|
      let method = $method_entry.method
      let op = $method_entry.op

      # skip if op is not a record (e.g. "parameters", "servers", "$ref" at path level)
      if not (($op | describe) | str starts-with "record") {
        return null
      }

      # TAG FILTER
      if ($config.filter_tags | length) > 0 {
        let op_tags = ($op.tags? | default [])
        let has_match = ($config.filter_tags | any {|t| $t in $op_tags })
        if not $has_match { return null }
      }

      let meta = (extract-op-metadata $op $auth_schemes $root_default_auth $methods)

      # DEPRECATED FILTER
      if $config.exclude_deprecated and $meta.deprecated {
        return null
      }

      let params = (classify-params $op $methods $schemas $h)
      # Synthesize path params for undeclared URL template placeholders
      let declared_originals = ($params.path_params | each {|p| $p.original_name? | default $p.name })
      let template_placeholders = ($path_entry.path | split row '{' | skip 1 | each {|s| $s | split row '}' | first } | where {|s| $s =~ '^\w+$' })
      let extra_path_params = $template_placeholders | where {|ph| not ($ph in $declared_originals) } | each {|ph|
        {name: ($ph | str replace --all '-' '_'), original_name: $ph, type: "any", required: true}
      }
      let params = if ($extra_path_params | is-empty) { $params } else {
        $params | update path_params ($params.path_params | append $extra_path_params)
      }
      let body = (extract-body-info $op $schemas $h)
      let resp = (extract-response-info $method $op $spec_data $schemas $h)
      let cmd_name = (derive-command-name $path_entry.path $method $meta.operation_id ($op.tags? | default []) $params.path_params $config.verb_map)

      # Build unified field_shapes: collapsed body shape + per-field shapes
      let body_collapsed = ($config.body_threshold > 0) and (($body.body_fields | length) > $config.body_threshold)
      let field_shapes = if $body_collapsed {
        [{flag: "body", shape: (render build-shape-doc $body.body_fields), is_item: false}]
      } else {
        $body.field_shapes
      }

      let endpoint_line = $"($method | str upcase) ($path_entry.path)"

      {
        name: $cmd_name
        method: $method
        path_template: $path_entry.path
        path_params: $params.path_params
        query_params: $params.query_params
        header_params: $params.header_params
        cookie_params: $params.cookie_params
        has_body: $body.has_body
        content_type: $body.content_type
        body_fields: $body.body_fields
        field_shapes: $field_shapes
        returns_body: $resp.returns_body
        description: $meta.description
        summary_fallback: $endpoint_line
        extra_doc_lines: (if ($meta.description | is-not-empty) { [$"# ($endpoint_line)"] } else { [] })
        accepts_input: $body.has_body
        extra_enum_sources: []
        operation_id: $meta.operation_id
        deprecated: $meta.deprecated
        deprecation_reason: null
        external_docs: $meta.external_docs
        default_auth: $meta.default_auth
        base_url: $meta.base_url
        accept_types: $resp.accept_types
        discriminator: $body.discriminator
        return_type: $resp.return_type
        tags: ($op.tags? | default [])
      }
    }
  } | flatten | compact
}
