# http-gen — OpenAPI 3.x / Swagger 2.0 / GraphQL to Nushell client generator.
#
# Usage:
#   use http-gen
#   http-gen openapi ./spec.yaml -o ./client.nu
#   http-gen graphql ./schema.json -o ./client.nu --default-base-url "https://api.example.com/graphql"
#   http-gen openapi preview ./spec.yaml
#   http-gen graphql preview ./schema.json

use spec.nu
use spec-oa3.nu
use spec-swagger2.nu
use spec-graphql.nu
use render.nu
use warn.nu

# Load a spec from a local file or a URL.
# Returns {data: record, source: string} where source is the resolved path or URL.
const INTROSPECTION_QUERY = '{ __schema { queryType { name } mutationType { name } subscriptionType { name } types { kind name description specifiedByURL isOneOf fields(includeDeprecated: true) { name description args { name description type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } } } defaultValue isDeprecated deprecationReason } type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } } } isDeprecated deprecationReason } inputFields { name description type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } } } defaultValue isDeprecated deprecationReason } interfaces { kind name } enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason } possibleTypes { kind name } } } }'

# Fetch a GraphQL introspection schema from an endpoint via POST.
def load-graphql-introspection [url: string] {
  http post --content-type "application/json" $url {query: $INTROSPECTION_QUERY}
}

def load-spec [source: string] {
  if ($source | str starts-with "http://") or ($source | str starts-with "https://") {
    let raw = try { http get $source } catch { null }
    if ($raw != null) and (($raw.openapi? | is-not-empty) or ($raw.swagger? | is-not-empty) or ($raw.data?.__schema? | is-not-empty)) {
      {data: $raw, source: $source}
    } else {
      # GET failed or returned unrecognized format — try GraphQL introspection
      warn fallback $"GET ($source) returned unrecognized format, attempting GraphQL introspection via POST"
      let intro = (load-graphql-introspection $source)
      {data: $intro, source: $source}
    }
  } else {
    let expanded = ($source | path expand | into string)
    {data: (open $expanded), source: $expanded}
  }
}

# Build a normalized config record from CLI flags
def build-config [
  filter_tags: list = []
  filter_prefixes: list = []
  filter_methods: list = []
  exclude_deprecated: bool = false
  verb_map: record = {}
  token_env_var: string = ""
  default_timeout: string = "30min"
  default_headers: record = {}
  body_threshold: int = 0
  no_introspection: bool = false
  no_descriptions: bool = false
  default_base_url: string = ""
] {
  {
    filter_tags: $filter_tags
    filter_prefixes: $filter_prefixes
    filter_methods: ($filter_methods | each { $in | str downcase })
    exclude_deprecated: $exclude_deprecated
    verb_map: $verb_map
    token_env_var: (if ($token_env_var | is-empty) { null } else { $token_env_var })
    default_timeout: $default_timeout
    default_headers: $default_headers
    body_threshold: $body_threshold
    no_introspection: $no_introspection
    no_descriptions: $no_descriptions
    default_base_url: (if ($default_base_url | is-empty) { null } else { $default_base_url })
  }
}

# Merge a base description with a list of nullable metadata annotations.
# Filters nulls, joins with ", ", and conditionally appends to base description.
def build-description [desc_base: string, extras: list] {
  let extra = $extras | where { $in != null } | str join ", "
  if ($extra | is-not-empty) and ($desc_base | is-not-empty) {
    $"($desc_base) \(($extra)\)"
  } else if ($extra | is-not-empty) {
    $extra
  } else {
    $desc_base
  }
}

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
      description: (build-description $desc_base [
        (if $deprecated { "DEPRECATED" } else { null })
        (if ($example != null) { $"e.g. ($example)" } else { null })
      ])
      enum: (do $h.get-param-enum $p)
      deprecated: $deprecated
    }
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

  let discriminator = ($schema.discriminator? | default null)
  let disc_prop = if ($discriminator != null) { $discriminator.propertyName? | default null } else { null }
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
    let disc_mapping = ($discriminator.mapping? | default {})
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
  $props | transpose name field_spec | where {|field|
    not ($field.field_spec.readOnly? | default false)
  } | each {|field|
    let field_type = ($field.field_spec.type? | default "any")
    let enum_vals = ($field.field_spec.enum? | default [])
    let nullable = ($field.field_spec.nullable? | default false)
    let desc_base = ($field.field_spec.description? | default "")
    let default_val = ($field.field_spec.default? | default null)
    let format = ($field.field_spec.format? | default null)
    let example = ($field.field_spec.example? | default null)
    let deprecated = ($field.field_spec.deprecated? | default false)
    let desc = (build-description $desc_base [
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
  $merged.props | transpose name field_spec | each {|field|
    let fs = (spec resolve-ref $field.field_spec $schemas)
    let ft = ($fs.type? | default "")
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
      warn data $"unresolved PathItem $ref for path '($path_entry.path)', skipping referenced operations"
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
    let description = (build-description $desc_base [
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
  let body_disc = ($body_schema.discriminator? | default null)
  let responses = ($op.responses? | default {})
  let resp_discs = $responses | transpose code resp | where {|r|
    ($r.code | str starts-with "2") or ($r.code == "default") or ($r.code =~ '^[12][xX]{2}$')
  } | each {|r|
    let content = ($r.resp.content? | default {})
    let json_schema = ($content | get -o "application/json" | default {} | get -o schema | default {})
    let resolved = (spec resolve-ref $json_schema $schemas)
    $resolved.discriminator? | default null
  } | where { $in != null }
  let resp_disc = if ($resp_discs | length) > 0 { $resp_discs | first } else { null }
  let discriminator = if ($body_disc != null) {
    {context: "request", propertyName: ($body_disc.propertyName? | default ""), mapping: ($body_disc.mapping? | default {})}
  } else if ($resp_disc != null) {
    {context: "response", propertyName: ($resp_disc.propertyName? | default ""), mapping: ($resp_disc.mapping? | default {})}
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
  let action = if ($action_mapped != null) {
    $action_mapped
  } else if ($action_raw =~ '^(get|post|put|patch|delete)[A-Z]') {
    $method
  } else {
    action-verb $action_raw
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

# Build the command model from a parsed+resolved spec
def build-commands [spec_data: record, schemas: record, h: record, auth_schemes: list, root_default_auth: string, config: record] {
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

# Deduplicate command names.
def deduplicate-commands [commands: list] {
  # pass 1: resolve collisions via list-rename or path-param suffix
  let dup_names = $commands | group-by name | transpose name entries
    | where { ($in.entries | length) > 1 } | get name

  # Identify GET collection/item pairs: all dupes are GET, exactly 2 members,
  # and one has exactly 1 more path param than the other.  Rename the member
  # with fewer params to "list" — cleaner than suffixing both with -by-{param}.
  let list_candidates = if ($dup_names | length) > 0 {
    $dup_names | where {|name|
      let group = ($commands | where { $in.name == $name })
      if (($group | length) != 2) or (not ($group | all {|c| $c.method == "get" })) { return false }
      let counts = ($group | each {|c| $c.path_params | length } | sort)
      ($counts | last) - ($counts | first) == 1
    }
  } else { [] }

  # For each list-candidate pair, record the min param count so we know which
  # member is the collection endpoint.
  let list_min_params = if ($list_candidates | length) > 0 {
    $list_candidates | each {|name|
      let group = ($commands | where { $in.name == $name })
      let min_count = ($group | each {|c| $c.path_params | length } | math min)
      {name: $name, min_params: $min_count}
    }
  } else { [] }

  let suffix_candidates = $dup_names | where { $in not-in $list_candidates }

  if ($list_candidates | length) > 0 {
    let display = if ($list_candidates | length) > 5 { $"($list_candidates | first 5 | each {|n| $n | split row ' ' | first } | str join ', '), ... \(($list_candidates | length) total\)" } else { $list_candidates | each {|n| $n | split row ' ' | first } | str join ", " }
    warn dedup $"($list_candidates | length) GET collection/item collision\(s\) resolved via list rename: ($display)"
  }
  if ($suffix_candidates | length) > 0 {
    let display = if ($suffix_candidates | length) > 5 { $"($suffix_candidates | first 5 | str join ', '), ... \(($suffix_candidates | length) total\)" } else { $suffix_candidates | str join ", " }
    warn dedup $"($suffix_candidates | length) duplicate command name\(s\) disambiguated with path-param suffix: ($display)"
  }

  let pass1 = $commands | each {|cmd|
    if ($cmd.name in $list_candidates) {
      let entry = ($list_min_params | where { $in.name == $cmd.name } | first)
      if ($cmd.path_params | length) == $entry.min_params {
        # Collection GET (fewer params): rename action to "list"
        let resource = ($cmd.name | split row ' ' | first)
        $cmd | update name $"($resource) list"
      } else {
        # Item GET (more params): keep original name
        $cmd
      }
    } else if ($cmd.name in $suffix_candidates) and ($cmd.path_params | length) > 0 {
      let suffix = $cmd.path_params | each {|p| $p.name } | str join '-'
      $cmd | update name $"($cmd.name)-by-($suffix)"
    } else {
      $cmd
    }
  }

  # pass 2: numeric suffix for remaining dupes
  let dup_names2 = $pass1 | group-by name | transpose name entries
    | where { ($in.entries | length) > 1 } | get name

  if ($dup_names2 | length) == 0 {
    return $pass1
  }

  let display2 = if ($dup_names2 | length) > 5 { $"($dup_names2 | first 5 | str join ', '), ... \(($dup_names2 | length) total\)" } else { $dup_names2 | str join ", " }
  warn dedup $"($dup_names2 | length) command name\(s\) still collide after path-param disambiguation, adding numeric suffixes: ($display2)"

  mut result = []
  mut seen = {}
  for cmd in $pass1 {
    if ($cmd.name in $dup_names2) {
      let count = ($seen | get -o $cmd.name | default 0)
      $seen = ($seen | upsert $cmd.name ($count + 1))
      if $count > 0 {
        $result = ($result | append ($cmd | update name $"($cmd.name)-($count)"))
      } else {
        $result = ($result | append $cmd)
      }
    } else {
      $result = ($result | append $cmd)
    }
  }
  $result
}

# Check whether a GraphQL field should be included based on config filters.
# Returns true if the field passes all filters (deprecated, prefix).
def filter-gql-field [field: record, config: record] {
  if $config.exclude_deprecated and ($field.isDeprecated? | default false) { return false }
  let field_name_kebab = ($field.name | str kebab-case)
  if ($config.filter_prefixes | length) > 0 {
    let matches = ($config.filter_prefixes | any {|p| $field_name_kebab | str starts-with $p })
    if not $matches { return false }
  }
  true
}

# Map GraphQL field args to the query_params command model format.
def build-gql-query-params [args: list, type_index: record] {
  $args | each {|arg|
    let resolved = (spec resolve-gql-field $arg $type_index)
    let scalar_type = ($type_index | get -o $resolved.unwrapped.name | default {})
    let spec_url = ($scalar_type | get -o specifiedByURL | default null)
    let description = (build-description $resolved.desc_base [
      (if $resolved.deprecated and ($resolved.deprecation_reason != null) { $"DEPRECATED: ($resolved.deprecation_reason)" } else if $resolved.deprecated { "DEPRECATED" } else { null })
      (if $spec_url != null { $"See: ($spec_url)" } else { null })
    ])
    {
      name: ($arg.name | str kebab-case)
      original_name: $arg.name
      type: $resolved.type
      required: $resolved.required
      description: $description
      enum: $resolved.enum
      collection_style: (if $resolved.unwrapped.is_list { "multi" } else { "scalar" })
      deprecated: $resolved.deprecated
    }
  }
}

# Determine which INPUT_OBJECT args should be expanded into individual flags,
# and extract their sub-fields. Returns {gql_input_fields, expanded_arg_names,
# expand_inputs, input_object_args}.
def expand-gql-inputs [args: list, type_index: record, body_threshold: int] {
  let input_object_args = ($args | where {|arg|
    let unwrapped = (spec unwrap-gql-type $arg.type)
    let leaf_kind = (spec gql-leaf-kind $arg.type)
    $leaf_kind == "INPUT_OBJECT" and (not $unwrapped.is_list)
  })
  let total_expanded = if ($input_object_args | is-empty) { 0 } else {
    $input_object_args | each {|arg|
      let unwrapped = (spec unwrap-gql-type $arg.type)
      spec extract-gql-input-fields $unwrapped.name $type_index | length
    } | math sum
  }
  let expand_inputs = ($body_threshold == 0) or ($total_expanded <= $body_threshold)

  let gql_input_fields = if $expand_inputs {
    $input_object_args | each {|arg|
      let unwrapped = (spec unwrap-gql-type $arg.type)
      let arg_flag = ($arg.name | str kebab-case)
      let fields = (spec extract-gql-input-fields $unwrapped.name $type_index)
      {
        arg_name: $arg.name
        arg_flag: $arg_flag
        gql_type_name: $unwrapped.name
        gql_type_sig: (spec gql-type-to-signature $arg.type)
        fields: $fields
      }
    }
  } else { [] }

  let expanded_arg_names = ($gql_input_fields | each {|g| $g.arg_name })

  {gql_input_fields: $gql_input_fields, expanded_arg_names: $expanded_arg_names, expand_inputs: $expand_inputs, input_object_args: $input_object_args}
}

# Build shape documentation for GraphQL INPUT_OBJECT args.
# Handles collapsed shapes, expanded sub-field shapes, and list-of-INPUT_OBJECT shapes.
def build-gql-field-shapes [args: list, type_index: record, expansion: record] {
  # Collapsed shapes: INPUT_OBJECT args kept as single --flag: record
  let collapsed_shapes = if $expansion.expand_inputs { [] } else {
    $expansion.input_object_args | each {|arg|
      let unwrapped = (spec unwrap-gql-type $arg.type)
      let fields = (spec extract-gql-input-fields $unwrapped.name $type_index)
      let shape = (render build-shape-doc $fields)
      let is_one_of = ($type_index | get -o $unwrapped.name | default {} | get -o isOneOf | default false)
      let shape = if $is_one_of { $"one of: ($shape)" } else { $shape }
      {flag: ($arg.name | str kebab-case), shape: $shape, is_item: false}
    }
  }

  # Expanded sub-field shapes: sub-fields that are themselves INPUT_OBJECT
  let expanded_shapes = if (not $expansion.expand_inputs) or ($expansion.gql_input_fields | is-empty) { [] } else {
    $expansion.gql_input_fields | each {|g|
      let parent_type = ($type_index | get $g.gql_type_name | default {inputFields: []})
      let raw_fields = ($parent_type.inputFields? | default [])
      $raw_fields | each {|raw_f|
        let leaf_kind = (spec gql-leaf-kind $raw_f.type)
        if $leaf_kind == "INPUT_OBJECT" {
          let sub_unwrapped = (spec unwrap-gql-type $raw_f.type)
          let sub_fields = (spec extract-gql-input-fields $sub_unwrapped.name $type_index)
          if ($sub_fields | is-empty) { null } else {
            let shape = (render build-shape-doc $sub_fields)
            let is_one_of = ($type_index | get -o $sub_unwrapped.name | default {} | get -o isOneOf | default false)
            let shape = if $is_one_of { $"one of: ($shape)" } else { $shape }
            {flag: $"($g.arg_flag)-(render to-flag-name $raw_f.name)", shape: $shape, is_item: ($sub_unwrapped.is_list)}
          }
        } else { null }
      }
    } | flatten | compact
  }

  # List-of-INPUT_OBJECT shapes: list args not expanded
  let list_input_shapes = $args | each {|arg|
    let unwrapped = (spec unwrap-gql-type $arg.type)
    let leaf_kind = (spec gql-leaf-kind $arg.type)
    if ($leaf_kind == "INPUT_OBJECT") and $unwrapped.is_list {
      let fields = (spec extract-gql-input-fields $unwrapped.name $type_index)
      if ($fields | is-empty) { null } else {
        let shape = (render build-shape-doc $fields)
        let is_one_of = ($type_index | get -o $unwrapped.name | default {} | get -o isOneOf | default false)
        let shape = if $is_one_of { $"one of: ($shape)" } else { $shape }
        {flag: ($arg.name | str kebab-case), shape: $shape, is_item: true}
      }
    } else { null }
  } | compact

  $collapsed_shapes | append $expanded_shapes | append $list_input_shapes
}

# Build command records from a GraphQL introspection result.
# Each top-level field on Query/Mutation becomes one command.
def build-graphql-commands [spec_data: record, schemas: record, config: record] {
  let schema = $spec_data.data.__schema
  let type_index = $schemas.types

  # Collect root operation types
  mut root_types = []
  if ($schema.queryType? != null) {
    $root_types = ($root_types | append {op_type: "query", type_name: $schema.queryType.name})
  }
  if ($schema.mutationType? != null) {
    $root_types = ($root_types | append {op_type: "mutation", type_name: $schema.mutationType.name})
  }

  mut commands = []
  mut truncated_fields = []
  for root in $root_types {
    let root_type = ($type_index | get -o $root.type_name)
    if ($root_type == null) or ($root_type.fields? == null) { continue }

    # Tag filter: tags for GraphQL are "Query" and "Mutation"
    let tag = if $root.op_type == "query" { "Query" } else { "Mutation" }
    if ($config.filter_tags | length) > 0 {
      if $tag not-in $config.filter_tags { continue }
    }

    for field in $root_type.fields {
      if not (filter-gql-field $field $config) { continue }

      let field_name_kebab = ($field.name | str kebab-case)
      let args = ($field.args? | default [])

      # Track truncated types (insufficient ofType depth in introspection)
      for arg in $args {
        if ((spec unwrap-gql-type $arg.type).is_truncated? | default false) {
          $truncated_fields = ($truncated_fields | append $"($field.name).($arg.name)")
        }
      }

      let query_params = (build-gql-query-params $args $type_index)
      let expansion = (expand-gql-inputs $args $type_index $config.body_threshold)
      let field_shapes = (build-gql-field-shapes $args $type_index $expansion)

      # Remove expanded INPUT_OBJECT args from query_params
      let query_params = ($query_params | where {|p| ($p.original_name? | default $p.name) not-in $expansion.expanded_arg_names })

      # Compute return type
      let return_unwrapped = (spec unwrap-gql-type $field.type)
      if ($return_unwrapped.is_truncated? | default false) {
        $truncated_fields = ($truncated_fields | append $"($field.name) (return type)")
      }
      let return_type = if $return_unwrapped.is_list { "list" } else {
        let leaf_kind = (spec gql-leaf-kind $field.type)
        if $leaf_kind == "SCALAR" { render openapi-to-nu-type (spec gql-scalar-to-openapi $return_unwrapped.name) } else { "record" }
      }

      # Check if return type is scalar (no selection set needed)
      let return_leaf_kind = (spec gql-leaf-kind $field.type)
      let scalar_return = ($return_leaf_kind == "SCALAR" or $return_leaf_kind == "ENUM")

      # Default selection: scalar fields of the return type
      let default_selection = if $scalar_return { "" } else { spec compute-default-selection $return_unwrapped.name $type_index }

      # Variable declarations for the GraphQL query header
      let var_declarations = ($args | each {|arg|
        $"$($arg.name): (spec gql-type-to-signature $arg.type)"
      } | str join ", ")

      let cmd_name = $"($root.op_type) ($field_name_kebab)"

      $commands = ($commands | append {
        name: $cmd_name
        method: $"graphql-($root.op_type)"
        path_template: ""
        path_params: []
        query_params: $query_params
        header_params: []
        cookie_params: []
        has_body: false
        content_type: "application/json"
        body_fields: []
        returns_body: true
        description: ($field.description? | default $"GraphQL ($root.op_type): ($field.name)")
        operation_id: $field.name
        deprecated: ($field.isDeprecated? | default false)
        deprecation_reason: ($field.deprecationReason? | default null)
        external_docs: null
        default_auth: "bearer"
        base_url: null
        accept_types: ["application/json"]
        discriminator: null
        return_type: $return_type
        tags: [$tag]
        gql_field_name: $field.name
        gql_op_type: $root.op_type
        gql_default_selection: $default_selection
        gql_var_declarations: $var_declarations
        gql_scalar_return: $scalar_return
        field_shapes: $field_shapes
        gql_input_fields: $expansion.gql_input_fields
      })
    }
  }

  let truncated_fields = ($truncated_fields | uniq)
  if ($truncated_fields | length) > 0 {
    let display = if ($truncated_fields | length) > 5 { $"($truncated_fields | first 5 | str join ', '), ... \(($truncated_fields | length) total\)" } else { $truncated_fields | str join ", " }
    warn data $"($truncated_fields | length) truncated type reference\(s\) detected — these resolve to 'any' due to insufficient ofType depth in introspection: ($display)"
  }

  $commands
}

# Shared pipeline: parse spec, resolve refs, build commands
def process-spec [spec_data: record, config: record] {
  let info = (spec detect $spec_data)
  let h = match $info.schema {
    "openapi" => (spec-oa3 helpers)
    "swagger" => (spec-swagger2 helpers)
    "graphql" => (spec-graphql helpers)
  }

  if $info.schema == "graphql" {
    let schemas = (do $h.get-schemas $spec_data)
    let commands = build-graphql-commands $spec_data $schemas $config
    let deduped = deduplicate-commands $commands
    {spec: $spec_data, commands: $deduped, helpers: $h, auth_schemes: [], default_auth: "bearer", base_url: ($config.default_base_url | default ""), all_urls: []}
  } else {
    let schemas = (do $h.get-schemas $spec_data)
    let auth_schemes = (do $h.get-auth-schemes $spec_data)
    let default_auth = (spec get-default-auth $spec_data $auth_schemes)
    let base_url = (do $h.get-base-url $spec_data)
    let all_urls = (do $h.get-all-urls $spec_data)
    let commands = build-commands $spec_data $schemas $h $auth_schemes $default_auth $config
    let deduped = deduplicate-commands $commands
    {spec: $spec_data, commands: $deduped, helpers: $h, auth_schemes: $auth_schemes, default_auth: $default_auth, base_url: $base_url, all_urls: $all_urls}
  }
}

# Shared generation pipeline — called by openapi and graphql subcommands.
def generate-module [loaded: record, config: record, name_flag: any, output_flag: any, urls_flag: list] {
  let title = if ($name_flag | is-not-empty) { $name_flag } else {
    $loaded.data.info?.title? | default ($loaded.source | path parse | get stem)
  }
  let result = process-spec $loaded.data $config
  if ($result.commands | is-empty) {
    warn config "no commands were generated — check your spec content or filter flags"
  }
  let extra_urls = ($urls_flag | append $result.all_urls)
  let output_content = render render-module $result.spec $result.commands $loaded.source $title $result.base_url $extra_urls $result.auth_schemes $result.default_auth $config
  let out_path = if ($output_flag | is-not-empty) { $output_flag } else { $"./($title).nu" }
  $output_content | save --force $out_path
}

# Shared preview pipeline — called by openapi and graphql preview subcommands.
def preview-commands [loaded: record, config: record] {
  let result = process-spec $loaded.data $config
  if ($result.commands | is-empty) {
    warn config "no commands were generated — check your spec content or filter flags"
  }
  $result.commands | each {|c|
    {name: $c.name, method: $c.method, path_template: (if ($c.path_template | is-empty) { $c.gql_field_name? | default "" } else { $c.path_template })}
  }
}

# Root command — prints usage guidance for the two subcommands.
export def main [] {
  print "http-gen: Generate typed Nushell HTTP clients from API specs."
  print ""
  print "Subcommands:"
  print "  http-gen openapi <spec> -o <output>    Generate from OpenAPI/Swagger spec"
  print "  http-gen graphql <spec> -o <output>    Generate from GraphQL schema"
  print "  http-gen openapi preview <spec>        Preview OpenAPI commands"
  print "  http-gen graphql preview <spec>        Preview GraphQL commands"
  print ""
  print "Run `http-gen openapi --help` or `http-gen graphql --help` for full options."
}

# Generate a Nushell HTTP client module from an OpenAPI/Swagger spec
export def openapi [
  source: string                # OpenAPI/Swagger spec file path or URL
  --output(-o): path            # Output .nu file (default: ./{title}.nu)
  --name: string                # Override module name
  --urls(-u): list<string>      # Additional base URLs for autocompletion
  --tags: list<string>          # Filter: only operations with these tags
  --prefixes: list<string>      # Filter: only paths matching these prefixes
  --methods: list<string>       # Filter: only these HTTP methods
  --exclude-deprecated          # Filter: skip deprecated operations
  --verb-map: record            # Naming: override action verbs e.g. {retrieve: "fetch"}
  --token-env-var: string       # Override auto-derived token env var name
  --default-timeout: string = "30min"  # Override default request timeout
  --default-headers: record     # Static headers added to every request
  --body-threshold: int = 0     # Collapse body fields to --body:record above this count (0 = never)
  --no-introspection            # Omit the commands subcommand
  --no-descriptions             # Omit parameter descriptions
  --default-base-url: string    # Override default base URL from spec
] {
  let loaded = (load-spec $source)
  let info = (spec detect $loaded.data)
  if $info.schema == "graphql" {
    error make --unspanned { msg: "spec is GraphQL, not OpenAPI/Swagger — use `http-gen graphql` instead" }
  }
  if ($loaded.data.paths? | is-empty) {
    error make --unspanned { msg: "not a valid OpenAPI/Swagger spec: missing 'paths' field" }
  }
  let config = (build-config
    ($tags | default []) ($prefixes | default []) ($methods | default [])
    $exclude_deprecated ($verb_map | default {}) ($token_env_var | default "")
    $default_timeout ($default_headers | default {}) $body_threshold
    $no_introspection $no_descriptions ($default_base_url | default ""))
  generate-module $loaded $config ($name | default "") $output ($urls | default [])
}

# Preview what commands would be generated from an OpenAPI/Swagger spec
export def "openapi preview" [
  source: string                # OpenAPI/Swagger spec file path or URL
  --tags: list<string>          # Filter: only operations with these tags
  --prefixes: list<string>      # Filter: only paths matching these prefixes
  --methods: list<string>       # Filter: only these HTTP methods
  --exclude-deprecated          # Filter: skip deprecated operations
  --verb-map: record            # Naming: override action verbs e.g. {retrieve: "fetch"}
] {
  let loaded = (load-spec $source)
  let info = (spec detect $loaded.data)
  if $info.schema == "graphql" {
    error make --unspanned { msg: "spec is GraphQL, not OpenAPI/Swagger — use `http-gen graphql preview` instead" }
  }
  let config = (build-config
    ($tags | default []) ($prefixes | default []) ($methods | default [])
    $exclude_deprecated ($verb_map | default {}))
  preview-commands $loaded $config
}

# Generate a Nushell HTTP client module from a GraphQL schema
export def graphql [
  source: string                # GraphQL introspection schema file path or endpoint URL
  --output(-o): path            # Output .nu file (default: ./{title}.nu)
  --name: string                # Override module name
  --urls(-u): list<string>      # Additional base URLs for autocompletion
  --prefixes: list<string>      # Filter: only fields matching these name prefixes
  --exclude-deprecated          # Filter: skip deprecated fields
  --verb-map: record            # Naming: override action verbs e.g. {retrieve: "fetch"}
  --token-env-var: string       # Override auto-derived token env var name
  --default-timeout: string = "30min"  # Override default request timeout
  --default-headers: record     # Static headers added to every request
  --body-threshold: int = 0     # Collapse INPUT_OBJECT fields to --body:record above this count (0 = never)
  --no-introspection            # Omit the commands subcommand
  --no-descriptions             # Omit parameter descriptions
  --default-base-url: string    # Base URL for the GraphQL endpoint
] {
  let loaded = (load-spec $source)
  let info = (spec detect $loaded.data)
  if $info.schema != "graphql" {
    error make --unspanned { msg: $"spec is ($info.schema), not GraphQL — use `http-gen openapi` instead" }
  }
  if ($loaded.data.data?.__schema?.types? | is-empty) {
    error make --unspanned { msg: "not a valid GraphQL introspection result: missing types" }
  }
  if ($default_base_url | default "" | is-empty) {
    warn config "--default-base-url not set for GraphQL spec; generated client will have an empty base URL"
  }
  let config = (build-config
    [] ($prefixes | default []) []
    $exclude_deprecated ($verb_map | default {}) ($token_env_var | default "")
    $default_timeout ($default_headers | default {}) $body_threshold
    $no_introspection $no_descriptions ($default_base_url | default ""))
  generate-module $loaded $config ($name | default "") $output ($urls | default [])
}

# Preview what commands would be generated from a GraphQL schema
export def "graphql preview" [
  source: string                # GraphQL introspection schema file path or endpoint URL
  --prefixes: list<string>      # Filter: only fields matching these name prefixes
  --exclude-deprecated          # Filter: skip deprecated fields
  --verb-map: record            # Naming: override action verbs e.g. {retrieve: "fetch"}
] {
  let loaded = (load-spec $source)
  let info = (spec detect $loaded.data)
  if $info.schema != "graphql" {
    error make --unspanned { msg: $"spec is ($info.schema), not GraphQL — use `http-gen openapi preview` instead" }
  }
  let config = (build-config
    [] ($prefixes | default []) []
    $exclude_deprecated ($verb_map | default {}))
  preview-commands $loaded $config
}
