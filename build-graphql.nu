# build-graphql.nu — GraphQL command-model builder and spec loading helpers.
#
# Extracts Query/Mutation fields from a GraphQL introspection schema and
# produces the unified command model consumed by render.nu.

use spec.nu
use render.nu
use warn.nu

# ── GraphQL spec loading ──────────────────────────────────────────

const INTROSPECTION_QUERY = '{ __schema { queryType { name } mutationType { name } subscriptionType { name } types { kind name description specifiedByURL isOneOf fields(includeDeprecated: true) { name description args { name description type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } } } defaultValue isDeprecated deprecationReason } type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } } } isDeprecated deprecationReason } inputFields { name description type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } } } defaultValue isDeprecated deprecationReason } interfaces { kind name } enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason } possibleTypes { kind name } } } }'

# Node.js script that converts GraphQL SDL to introspection JSON via the graphql package.
const SDL_CONVERT_SCRIPT = 'const g=require("graphql");let s="";process.stdin.setEncoding("utf8");process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const schema=g.buildSchema(s);const q=g.getIntrospectionQuery({inputValueDeprecation:true});const r=g.graphqlSync({schema,source:q});console.log(JSON.stringify(r))}catch(e){console.error(e.message);process.exit(1)}})'

# Detect whether raw content is GraphQL SDL text.
export def is-sdl [content: any] {
  (($content | describe) == "string") and ($content =~ '(?m)^\s*(type |input |enum |scalar |schema\s*\{)')
}

# Parse GraphQL SDL text into introspection JSON via Node.js + graphql package.
export def parse-sdl [sdl_text: string] {
  try {
    $sdl_text | node -e $SDL_CONVERT_SCRIPT | from json
  } catch {
    error make --unspanned { msg: "Cannot parse GraphQL SDL: this requires Node.js with the 'graphql' npm package. Install with: npm install -g graphql. Alternatively, convert your .graphql file to introspection JSON first." }
  }
}

# Fetch a GraphQL introspection schema from an endpoint via POST.
export def load-introspection [url: string, headers: record = {}] {
  http post --content-type "application/json" --headers $headers $url {query: $INTROSPECTION_QUERY}
}

# ── Command model builder ─────────────────────────────────────────

# Build command model + metadata from a GraphQL spec.
# Returns {commands, auth_schemes, default_auth, base_url, all_urls}.
export def build-commands [spec_data: record, schemas: record, config: record] {
  let commands = build-command-list $spec_data $schemas $config
  {commands: $commands, auth_schemes: [], default_auth: "bearer", base_url: ($config.default_base_url | default ""), all_urls: []}
}

# ── Private helpers ────────────────────────────────────────────────

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
    let description = (spec build-description $resolved.desc_base [
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
def build-command-list [spec_data: record, schemas: record, config: record] {
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

      let gql_extra_enum_sources = ($expansion.gql_input_fields | each {|g| $g.fields | each {|f| $f | update name $"($g.arg_flag)-($f.name)" }} | flatten)

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
        summary_fallback: $"GraphQL ($root.op_type): ($field.name)"
        extra_doc_lines: []
        accepts_input: true
        extra_enum_sources: $gql_extra_enum_sources
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
