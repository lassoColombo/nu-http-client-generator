# http-gen v2 — OpenAPI 3.x / Swagger 2.0 to Nushell client generator.
#
# Usage:
#   use http-gen
#   http-gen ./spec.yaml -o ./client.nu
#   http-gen preview ./spec.yaml

use spec.nu
use render.nu

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
    {
      name: $p.name
      type: (do $h.get-param-type $p)
      required: ($p.required? | default false)
      description: (build-description $desc_base [(if ($example != null) { $"e.g. ($example)" } else { null })])
      enum: (do $h.get-param-enum $p)
    }
  }
}

# Extract body field info from a resolved request body schema
def extract-body-fields [schema: record, schemas: record] {
  # merge properties from allOf sub-schemas
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

  # merge properties from oneOf/anyOf variants (all marked optional)
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

  # discriminator: make property required with enum from mapping keys
  if ($disc_prop != null) and ($disc_prop in ($merged_props | columns)) {
    $merged_required = ($merged_required | append $disc_prop | uniq)
    let disc_mapping = ($discriminator.mapping? | default {})
    if ($disc_mapping | columns | length) > 0 {
      $merged_props = ($merged_props | upsert $disc_prop ($merged_props | get $disc_prop | upsert enum ($disc_mapping | columns)))
    }
  }

  let props = $merged_props
  let required = $merged_required
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
    }
  }
}

# Map OpenAPI method actions to command verbs
def action-verb [action: string] {
  match $action {
    "retrieve" => "get"
    "destroy" => "delete"
    _ => $action
  }
}

# Resolve PathItem-level $ref. Returns the methods record.
def resolve-path-item [path_entry: record, schemas: record] {
  if ($path_entry.methods | columns | any {|c| $c == "$ref"}) {
    let ref_path = ($path_entry.methods | get "$ref")
    if (($ref_path | describe) == "string") {
      let schema_name = ($ref_path | split row '/' | last)
      if ($schema_name in ($schemas | columns)) {
        $schemas | get $schema_name
      } else {
        $path_entry.methods
      }
    } else {
      $path_entry.methods
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

  let body_fields = if ($body_schema | is-not-empty) and (($body_schema | describe) | str starts-with "record") and (($body_schema | columns | length) > 0) {
    extract-body-fields $body_schema $schemas
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

  {has_body: $has_body, content_type: $content_type, body_fields: $body_fields, discriminator: $discriminator}
}

# Extract response info: accept_types, return_type, returns_body.
def extract-response-info [method: string, op: record, spec_data: record, h: record] {
  let accept_types = (do $h.get-response-content-types $op $spec_data)

  let return_type = if ($method in ["head" "options"]) {
    "record"
  } else {
    do $h.get-response-type $op $spec_data
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
def derive-command-name [url_path: string, method: string, operation_id: string, tags: list, path_params: list] {
  let path_segments = ($url_path | split row '/' | where {|s|
    ($s | is-not-empty) and ($s != "api") and (not ($s | str starts-with "{")) and (not ($s =~ '^v\d+$'))
  })
  let resource = if ($path_segments | length) > 0 {
    $path_segments | where {|s| $s != "-" and $s != "--" }
    | each {|s| $s | str replace --all --regex '[\\$()*\[\]=\x27",.$#!@%^&+~`]' '' }
    | where {|s| $s | is-not-empty }
    | str join '-' | str downcase | str replace --all '_' '-'
    | str replace --regex '-{2,}' '-' | str trim --char '-'
  } else if ($tags | length) > 0 {
    $tags.0 | str downcase | str replace --all '_' '-' | str replace --all ' ' '-'
  } else {
    "api"
  }

  let action_raw = if ($operation_id | is-not-empty) {
    let parts = ($operation_id | split row '_')
    let last_part = ($parts | last)
    if ($last_part =~ '^\d+$') and ($parts | length) >= 2 {
      let action_part = ($parts | get (($parts | length) - 2))
      $action_part
    } else {
      $last_part
    }
  } else {
    $method
  }

  # camelCase operationIds starting with HTTP verb -> fall back to method
  let action = if ($action_raw =~ '^(get|post|put|patch|delete)[A-Z]') {
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
def build-commands [spec_data: record, schemas: record, h: record, auth_schemes: list, root_default_auth: string] {
  $spec_data.paths | transpose path methods | each {|path_entry|
    let methods = (resolve-path-item $path_entry $schemas)

    $methods | transpose method op | where {|m|
      $m.method in [get post put patch delete head options]
    } | each {|method_entry|
      let method = $method_entry.method
      let op = $method_entry.op

      # skip if op is not a record (e.g. "parameters", "servers", "$ref" at path level)
      if not (($op | describe) | str starts-with "record") {
        return null
      }

      let meta = (extract-op-metadata $op $auth_schemes $root_default_auth $methods)
      let params = (classify-params $op $methods $schemas $h)
      let body = (extract-body-info $op $schemas $h)
      let resp = (extract-response-info $method $op $spec_data $h)
      let cmd_name = (derive-command-name $path_entry.path $method $meta.operation_id ($op.tags? | default []) $params.path_params)

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
        returns_body: $resp.returns_body
        description: $meta.description
        operation_id: $meta.operation_id
        deprecated: $meta.deprecated
        external_docs: $meta.external_docs
        default_auth: $meta.default_auth
        base_url: $meta.base_url
        accept_types: $resp.accept_types
        discriminator: $body.discriminator
        return_type: $resp.return_type
      }
    }
  } | flatten | where { $in != null }
}

# Deduplicate command names.
def deduplicate-commands [commands: list] {
  # pass 1: append path param suffix where names collide
  let dup_names = $commands | group-by name | transpose name entries
    | where { ($in.entries | length) > 1 } | get name

  let pass1 = $commands | each {|cmd|
    if ($cmd.name in $dup_names) and ($cmd.path_params | length) > 0 {
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

# Shared pipeline: parse spec, resolve refs, build commands
def process-spec [spec_data: record] {
  let info = (spec detect $spec_data)
  let h = (spec helpers) | get $info.schema | get $info.version
  let schemas = (do $h.get-schemas $spec_data)

  # No upfront path resolution — pass raw spec + schemas to build-commands.
  # $ref resolution happens at the per-operation level inside build-commands.
  let auth_schemes = (do $h.get-auth-schemes $spec_data)
  let default_auth = (spec get-default-auth $spec_data $auth_schemes)
  let base_url = (do $h.get-base-url $spec_data)
  let all_urls = (do $h.get-all-urls $spec_data)
  let commands = build-commands $spec_data $schemas $h $auth_schemes $default_auth
  let deduped = deduplicate-commands $commands
  {spec: $spec_data, commands: $deduped, helpers: $h, auth_schemes: $auth_schemes, default_auth: $default_auth, base_url: $base_url, all_urls: $all_urls}
}

# Preview what commands would be generated from a spec
export def preview [
  file: path  # OpenAPI 3.x or Swagger 2.0 spec file
] {
  let spec_data = open $file
  let result = process-spec $spec_data
  $result.commands | select name method path_template
}

# Generate a Nushell HTTP client module from a spec
export def main [
  file: path                    # OpenAPI 3.x or Swagger 2.0 spec file
  --output(-o): path            # Output .nu file (default: ./{title}.nu)
  --name: string                # Override module name
  --urls(-u): list<string>      # Additional base URLs for autocompletion
] {
  let spec_data = open $file

  if ($spec_data.paths? | is-empty) {
    error make --unspanned { msg: "not a valid spec: missing 'paths' field" }
  }

  let title = if ($name | is-not-empty) { $name } else { $spec_data.info?.title? | default "api" }
  let result = process-spec $spec_data

  let extra_urls = ($urls | default [] | append $result.all_urls)
  let output_content = render render-module $result.spec $result.commands ($file | path expand | into string) $title $result.base_url $extra_urls $result.auth_schemes $result.default_auth
  let out_path = if ($output | is-not-empty) {
    $output
  } else {
    $"./($title).nu"
  }

  $output_content | save --force $out_path
  print $"Generated ($result.commands | length) commands -> ($out_path)"
}
