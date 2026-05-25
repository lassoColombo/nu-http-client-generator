# http-gen — OpenAPI 3.x / Swagger 2.0 to Nushell client generator.
#
# Usage:
#   use http-gen
#   http-gen ./spec.yaml -o ./client.nu
#   http-gen preview ./spec.yaml

use spec.nu

# Map OpenAPI types to Nushell types
def openapi-to-nu-type [t: string] {
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

# Map OpenAPI method actions to command verbs
def action-verb [action: string] {
  match $action {
    "retrieve" => "get"
    "destroy" => "delete"
    _ => $action
  }
}

# Nushell reserved variable names that cannot be used as flags
const RESERVED_NAMES = [in nu nothing]

# Variable names reserved in generated commands — body/query/header fields that
# match any of these get a "body-" prefix to avoid shadowing.
# Sources:
#   - nushell keywords/builtins that cannot be parameter names
#   - built-in flags from the generated signature (--raw, --token, etc.)
#   - internal variables from the generated body code (auth, base, url, etc.)
const RESERVED_VARS = [
  # nushell language keywords
  in nu nothing null true false
  if else match for while loop break continue return
  let mut const def export use module source overlay
  where each error try catch not do
  # generated signature flags
  base_url token auth_scheme insecure max_time raw allow_errors accept
  # generated body-code internal variables
  auth base url qp full_url body extra_headers cookie_str accept_val
]

# Convert param names to valid nushell flag names
def to-flag-name [name: string] {
  let cleaned = $name | str replace --all '_' '-' | str replace --all --regex '[\\$()\[\].*/\x27"#!@%^&+=~`]' '' | str replace --regex '-{2,}' '-' | str trim --char '-'
  if ($cleaned in $RESERVED_NAMES) or ($cleaned | is-empty) {
    $"($cleaned)-param" | str trim --char '-'
  } else {
    $cleaned
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
      # merge variant props without overwriting existing
      for col in ($v_props | columns) {
        if not ($col in ($merged_props | columns)) {
          $merged_props = ($merged_props | insert $col ($v_props | get $col))
        }
      }
      # do NOT merge variant required — variant fields are optional since only one variant applies
    }
  }

  # if discriminator exists, make its property required with enum of valid values
  if ($disc_prop != null) and ($disc_prop in ($merged_props | columns)) {
    $merged_required = ($merged_required | append $disc_prop | uniq)
    let disc_mapping = ($discriminator.mapping? | default {})
    if ($disc_mapping | columns | length) > 0 {
      # use mapping keys as enum values
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
    let extra = [
      (if $nullable { "nullable" } else { null })
      (if ($format != null) { $"format: ($format)" } else { null })
      (if ($default_val != null) { $"default: ($default_val)" } else { null })
    ] | where { $in != null } | str join ", "
    let desc = if ($extra | is-not-empty) and ($desc_base | is-not-empty) {
      $"($desc_base) \(($extra)\)"
    } else if ($extra | is-not-empty) {
      $extra
    } else {
      $desc_base
    }
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

# Build the command model from a parsed+resolved spec
def build-commands [spec_data: record, schemas: record, h: record, auth_schemes: list, root_default_auth: string] {
  $spec_data.paths | transpose path methods | each {|path_entry|
    let url_path = $path_entry.path
    let methods = $path_entry.methods

    $methods | transpose method op | where {|m|
      $m.method in [get post put patch delete]
    } | each {|method_entry|
      let method = $method_entry.method
      let op = $method_entry.op
      let operation_id = ($op.operationId? | default "")
      let tags = ($op.tags? | default [])
      let description = ($op.summary? | default ($op.description? | default ""))
      let deprecated = ($op.deprecated? | default false)

      # per-operation security override
      let op_security = ($op.security?)
      let cmd_default_auth = if ($op_security | is-not-empty) {
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

      # per-operation/path servers override
      let op_base_url = ($op.servers?.0?.url? | default ($methods.servers?.0?.url? | default null))

      # merge path-level params with operation params (op overrides path-level)
      let path_level_params = ($methods.parameters? | default [])
      let op_params = ($op.parameters? | default [])
      let op_param_keys = $op_params | each {|p| $"($p.name? | default ''):($p.in? | default '')" }
      let parameters = ($path_level_params | where {|p|
        let key = $"($p.name? | default ''):($p.in? | default '')"
        not ($key in $op_param_keys)
      } | append $op_params)

      # resolve $ref in params first, then filter out body params
      let resolved_params = $parameters | each {|p|
        if ($p | columns | any {|c| $c == "$ref"}) {
          spec resolve-ref $p $schemas
        } else {
          $p
        }
      } | spec get-non-body-params $in

      # classify params using spec helpers
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
        let param_type = (do $h.get-param-type $p)
        let collection_style = (do $h.get-param-collection-style $p)
        let extra = [
          (if ($format != null) { $"format: ($format)" } else { null })
          (if ($default_val != null) { $"default: ($default_val)" } else { null })
        ] | where { $in != null } | str join ", "
        let desc_base = (spec get-param-description $p)
        let description = if ($extra | is-not-empty) and ($desc_base | is-not-empty) {
          $"($desc_base) \(($extra)\)"
        } else if ($extra | is-not-empty) {
          $extra
        } else {
          $desc_base
        }
        {
          name: $p.name
          type: $param_type
          required: ($p.required? | default false)
          description: $description
          enum: (do $h.get-param-enum $p)
          collection_style: $collection_style
        }
      }

      let header_params = $resolved_params | where {|p| ($p.in? | default "") == "header" } | each {|p|
        {
          name: $p.name
          type: (do $h.get-param-type $p)
          required: ($p.required? | default false)
          description: (spec get-param-description $p)
          enum: (do $h.get-param-enum $p)
        }
      }

      let cookie_params = $resolved_params | where {|p| ($p.in? | default "") == "cookie" } | each {|p|
        {
          name: $p.name
          type: (do $h.get-param-type $p)
          required: ($p.required? | default false)
          description: (spec get-param-description $p)
          enum: (do $h.get-param-enum $p)
        }
      }

      # request body via spec helper
      let body_info = (do $h.get-body-info $op $schemas)
      let has_body = $body_info.has_body
      let body_schema = $body_info.body_schema
      let content_type = ($body_info.content_type? | default "application/json")

      let body_fields = if ($body_schema | is-not-empty) and (($body_schema | describe) | str starts-with "record") and (($body_schema | columns | length) > 0) {
        extract-body-fields $body_schema $schemas
      } else {
        []
      }

      # discriminator info from body and response schemas
      let body_disc = ($body_schema.discriminator? | default null)
      let responses = ($op.responses? | default {})
      let resp_discs = $responses | transpose code resp | where {|r|
        ($r.code | str starts-with "2") or ($r.code == "default")
      } | each {|r|
        # OpenAPI 3: look inside response content schemas
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

      # response content types for Accept header
      let accept_types = (do $h.get-response-content-types $op $spec_data)

      # response: does it return a body?
      let returns_body = if ($method == "delete") {
        let resp_204 = ($responses | get -o "204")
        ($resp_204 | is-empty)
      } else {
        true
      }

      # derive command name from path segments
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
        $tags.0 | str downcase | str replace --all '_' '-'
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

      # for camelCase operationIds (e.g. getApiV4Projects), fall back to HTTP method
      let action = if ($action_raw =~ '^(get|post|put|patch|delete)[A-Z]') {
        # camelCase operationId starting with HTTP verb — use the method
        $method
      } else {
        action-verb $action_raw
      }

      # disambiguate _2 etc by appending path param names
      let is_duplicate = if ($operation_id | is-not-empty) {
        let parts = ($operation_id | split row '_')
        let last_part = ($parts | last)
        ($last_part =~ '^\d+$') and ($parts | length) >= 2
      } else {
        false
      }

      let cmd_name = if $is_duplicate {
        let param_suffix = $path_params | each {|p| $p.name } | str join '-'
        $"($resource) ($action)-by-($param_suffix)"
      } else {
        $"($resource) ($action)"
      }

      {
        name: $cmd_name
        method: $method
        path_template: $url_path
        path_params: $path_params
        query_params: $query_params
        header_params: $header_params
        cookie_params: $cookie_params
        has_body: $has_body
        content_type: $content_type
        body_fields: $body_fields
        returns_body: $returns_body
        description: $description
        operation_id: $operation_id
        deprecated: $deprecated
        default_auth: $cmd_default_auth
        base_url: $op_base_url
        accept_types: $accept_types
        discriminator: $discriminator
      }
    }
  } | flatten
}

# Collect all unique enum sets and map each (flag_name, enum_values) to a completer name.
# Different enum sets for the same flag name get separate completers (e.g., state-completer, state-completer-1).
# Returns {completers: record<name, values>, mapping: record<fingerprint, completer_name>}
def collect-completers [commands: list] {
  mut completers = {}    # completer_name -> enum values
  mut mapping = {}       # fingerprint (flag_name + sorted values) -> completer_name
  mut name_counts = {}   # flag_name -> count of distinct enum sets seen

  for cmd in $commands {
    # collect from query params, body fields, and accept types
    let accept_source = if ($cmd.accept_types | length) > 1 { [{name: "accept", enum: $cmd.accept_types}] } else { [] }
    let enum_sources = ($cmd.query_params | append $cmd.body_fields | append $cmd.header_params | append $cmd.cookie_params | append $accept_source)
    for q in $enum_sources {
      if ($q.enum | length) > 0 {
        let flag_name = (to-flag-name $q.name)
        let vals = ($q.enum | each { $"($in)" } | sort)
        let fingerprint = $"($flag_name):($vals | str join ',')"

        if not ($fingerprint in ($mapping | columns)) {
          let count = ($name_counts | get -o $flag_name | default 0)
          let cname = if $count == 0 {
            $"($flag_name)-completer"
          } else {
            $"($flag_name)-completer-($count)"
          }
          $name_counts = ($name_counts | upsert $flag_name ($count + 1))
          $completers = ($completers | insert $cname $vals)
          $mapping = ($mapping | insert $fingerprint $cname)
        }
      }
    }
  }
  {completers: $completers, mapping: $mapping}
}

# Render completer functions as nushell source
def render-completers [completers: record] {
  $completers | transpose name values | each {|c|
    let vals = $c.values | each {|v| $'"($v)"' } | str join ' '
    $"def \"($c.name)\" [] { [($vals)] }"
  } | str join "\n"
}

# Resolve the completer name for a query param given the mapping
def resolve-completer [q: record, mapping: record] {
  let flag_name = (to-flag-name $q.name)
  let vals = ($q.enum | each { $"($in)" } | sort)
  let fingerprint = $"($flag_name):($vals | str join ',')"
  $mapping | get -o $fingerprint
}

# Build the signature string for a command
def build-signature [cmd: record, completers: record, mapping: record] {
  mut parts = []

  for p in $cmd.path_params {
    let nu_type = (openapi-to-nu-type $p.type)
    $parts = ($parts | append $"  ($p.name): ($nu_type)")
  }

  $parts = ($parts | append "  --base-url(-b): string@\"base-url-completer\"")
  $parts = ($parts | append "  --token(-t): string")
  $parts = ($parts | append "  --auth-scheme(-a): string@\"auth-scheme-completer\"")
  $parts = ($parts | append "  --insecure(-k) # Skip TLS verification")
  $parts = ($parts | append "  --max-time(-m): duration # Timeout")
  $parts = ($parts | append "  --raw(-r) # Fetch as text")
  $parts = ($parts | append "  --allow-errors(-e) # Return full response without error handling")

  # Accept header flag with completer when multiple response types
  if ($cmd.accept_types | length) > 1 {
    let cname = resolve-completer {name: "accept", enum: $cmd.accept_types} $mapping
    if ($cname | is-not-empty) {
      $parts = ($parts | append $"  --accept: string@\"($cname)\" # Response content type")
    } else {
      $parts = ($parts | append "  --accept: string # Response content type")
    }
  } else {
    $parts = ($parts | append "  --accept: string # Response content type")
  }

  for q in $cmd.query_params {
    let nu_type = (openapi-to-nu-type $q.type)
    let flag_name = (to-flag-name $q.name)
    let desc_text = if ($q.description | is-not-empty) { $q.description | lines | str join " " } else { "" }
    let desc = if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
    let cname = if ($q.enum | length) > 0 { resolve-completer $q $mapping } else { null }
    # boolean params use string with completer so null = "don't filter"
    if $nu_type == "bool" {
      $parts = ($parts | append $"  --($flag_name): string@\"bool-completer\"($desc)")
    } else if ($cname | is-not-empty) {
      $parts = ($parts | append $"  --($flag_name): ($nu_type)@\"($cname)\"($desc)")
    } else {
      $parts = ($parts | append $"  --($flag_name): ($nu_type)($desc)")
    }
  }

  for hp in $cmd.header_params {
    let nu_type = (openapi-to-nu-type $hp.type)
    let flag_name = (to-flag-name $hp.name)
    let desc_text = if ($hp.description | is-not-empty) { $hp.description | lines | str join " " } else { "" }
    let desc = if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
    let cname = if ($hp.enum | length) > 0 { resolve-completer $hp $mapping } else { null }
    if $nu_type == "bool" {
      $parts = ($parts | append $"  --($flag_name): string@\"bool-completer\"($desc)")
    } else if ($cname | is-not-empty) {
      $parts = ($parts | append $"  --($flag_name): ($nu_type)@\"($cname)\"($desc)")
    } else {
      $parts = ($parts | append $"  --($flag_name): ($nu_type)($desc)")
    }
  }

  for cp in $cmd.cookie_params {
    let nu_type = (openapi-to-nu-type $cp.type)
    let flag_name = (to-flag-name $cp.name)
    let desc_text = if ($cp.description | is-not-empty) { $cp.description | lines | str join " " } else { "" }
    let desc = if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
    let cname = if ($cp.enum | length) > 0 { resolve-completer $cp $mapping } else { null }
    if $nu_type == "bool" {
      $parts = ($parts | append $"  --($flag_name): string@\"bool-completer\"($desc)")
    } else if ($cname | is-not-empty) {
      $parts = ($parts | append $"  --($flag_name): ($nu_type)@\"($cname)\"($desc)")
    } else {
      $parts = ($parts | append $"  --($flag_name): ($nu_type)($desc)")
    }
  }

  if $cmd.has_body {
    let path_param_names = ($cmd.path_params | each {|p| $p.name })
    for f in $cmd.body_fields {
      let nu_type = (openapi-to-nu-type $f.type)
      let desc_text = if ($f.description | is-not-empty) { $f.description | lines | str join " " } else { "" }
      let desc = if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
      let sanitized_name = ($f.name | str replace --all '-' '_' | str replace --all --regex '[\\$()\[\].*/\x27"#!@%^&+=~`]' '' | str replace --regex '_{2,}' '_' | str trim --char '_')
      let collides = ($sanitized_name in $path_param_names) or ($sanitized_name in $RESERVED_VARS) or ($sanitized_name | is-empty)
      let cname = if ($f.enum | length) > 0 { resolve-completer $f $mapping } else { null }
      let is_nullable = ($f.nullable? | default false)
      if $f.required and (not $collides) and ($nu_type != "bool") and (not $is_nullable) {
        # required → positional param (with completer if enum)
        if ($cname | is-not-empty) {
          $parts = ($parts | append $"  ($sanitized_name): ($nu_type)@\"($cname)\"($desc)")
        } else {
          $parts = ($parts | append $"  ($sanitized_name): ($nu_type)($desc)")
        }
      } else {
        # optional, bool, or name collision → flag
        let flag_name = if $collides { $"body-(to-flag-name $f.name)" } else { to-flag-name $f.name }
        if $nu_type == "bool" {
          $parts = ($parts | append $"  --($flag_name): string@\"bool-completer\"($desc)")
        } else if ($cname | is-not-empty) {
          $parts = ($parts | append $"  --($flag_name): ($nu_type)@\"($cname)\"($desc)")
        } else {
          $parts = ($parts | append $"  --($flag_name): ($nu_type)($desc)")
        }
      }
    }
    # fallback: if body exists but no fields extracted, accept raw record
    if ($cmd.body_fields | length) == 0 {
      $parts = ($parts | append "  --body: record")
    }
  }

  $parts | str join "\n"
}

# Render the helper functions that go into every generated client
def render-helpers [token_env_var: string, auth_schemes: list, default_auth: string] {
  # build match arms from detected auth schemes (deduplicated by name)
  mut match_arms = []
  mut seen_names = []
  for s in $auth_schemes {
    if not ($s.name in $seen_names) {
      $seen_names = ($seen_names | append $s.name)
      if $s.in == "query" {
        $match_arms = ($match_arms | append ($'    "' + $s.name + '" => { {headers: {}, query: $"' + $s.header_name + '=($token_val)"} }'))
      } else if $s.in == "cookie" {
        $match_arms = ($match_arms | append ($'    "' + $s.name + '" => { {headers: {Cookie: $"' + $s.header_name + '=($token_val)"}, query: ""} }'))
      } else if $s.prefix == "" {
        # custom header without prefix (e.g. PRIVATE-TOKEN)
        $match_arms = ($match_arms | append ($'    "' + $s.name + '" => { {headers: {' + $s.header_name + ': $token_val}, query: ""} }'))
      } else {
        # Authorization header with prefix
        $match_arms = ($match_arms | append ($'    "' + $s.name + '" => { {headers: {' + $s.header_name + ': $"' + $s.prefix + ' ($token_val)"}, query: ""} }'))
      }
    }
  }
  # add "none" arm for public endpoints + fallback
  $match_arms = ($match_arms | append '    "none" => { {headers: {}, query: ""} }')
  $match_arms = ($match_arms | append '    _ => { {headers: {Authorization: $"Bearer ($token_val)"}, query: ""} }')
  let match_body = $match_arms | str join "\n"

  [
    '# Build auth: returns {headers: record, query: string}'
    'def build-auth [token?: string, auth_scheme?: string] {'
    ('  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o ' + $token_env_var + ' | default "" }')
    '  let scheme = ($auth_scheme | default "bearer")'
    '  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }'
    '  match $scheme {'
    $match_body
    '  }'
    '}'
    ''
    '# Serialize a single query parameter based on collection style'
    '# Returns a list of "key=value" strings (multi style can return multiple)'
    'def serialize-qp [name: string, value: any, style: string] {'
    '  if ($value == null) { return [] }'
    '  let is_list = ($value | describe | str starts-with "list")'
    '  if not $is_list { return [$"($name)=($value)"] }'
    '  match $style {'
    '    "multi" => { $value | each {|v| $"($name)=($v)" } }'
    ('    "csv" => { let joined = ($value | each { $in | into string } | str join ","); [$"($name)=($joined)"] }')
    ('    "ssv" => { let joined = ($value | each { $in | into string } | str join "%20"); [$"($name)=($joined)"] }')
    ('    "pipes" => { let joined = ($value | each { $in | into string } | str join "|"); [$"($name)=($joined)"] }')
    '    _ => { $value | each {|v| $"($name)=($v)" } }'
    '  }'
    '}'
    ''
    '# Execute HTTP request with method dispatch'
    'def do-request [method: string, url: string, auth: record, insecure: bool, raw: bool, max_time?: duration, allow_errors?: bool, content_type?: string, body?: any] {'
    '  let req_url = if ($auth.query | is-not-empty) { if ($url | str contains "?") { $"($url)&($auth.query)" } else { $"($url)?($auth.query)" } } else { $url }'
    '  let timeout = ($max_time | default 30min)'
    '  let ct = ($content_type | default "application/json")'
    '  let resp = match $method {'
    '    "get" => { http get --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url }'
    '    "post" => { http post --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body }'
    '    "put" => { http put --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body }'
    '    "patch" => { http patch --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url $body }'
    '    "delete" => { http delete --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url }'
    '  }'
    '  if $allow_errors { $resp } else if $resp.status == 204 { null } else if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }'
    '}'
  ] | str join "\n"
}

# Build the body code for a command
def build-body-code [cmd: record] {
  mut lines = []

  $lines = ($lines | append ('  let auth = (build-auth $token ($auth_scheme | default "' + $cmd.default_auth + '"))'))
  if ($cmd.base_url | is-not-empty) {
    $lines = ($lines | append ('  let base = ($base_url | default "' + $cmd.base_url + '")'))
  } else {
    $lines = ($lines | append '  let base = ($base_url | default $BASE_URL)')
  }

  if ($cmd.path_params | length) > 0 {
    mut path_str = $cmd.path_template
    for p in $cmd.path_params {
      let orig = ($p.original_name? | default $p.name)
      let placeholder = '{' + $orig + '}'
      let replacement = '($' + $p.name + ')'
      $path_str = ($path_str | str replace $placeholder $replacement)
    }
    $lines = ($lines | append ('  let url = $"($base)' + $path_str + '"'))
  } else {
    $lines = ($lines | append ('  let url = $"($base)' + $cmd.path_template + '"'))
  }

  if ($cmd.query_params | length) > 0 {
    mut serialize_calls = []
    for q in $cmd.query_params {
      let flag_name = (to-flag-name $q.name)
      let var_name = '$' + ($flag_name | str replace --all '-' '_')
      $serialize_calls = ($serialize_calls | append ('(serialize-qp "' + $q.name + '" ' + $var_name + ' "' + $q.collection_style + '")'))
    }
    let calls = $serialize_calls | str join " "
    $lines = ($lines | append ('  let qp = [' + $calls + '] | flatten | str join "&"'))
    $lines = ($lines | append '  let full_url = if ($qp | is-empty) { $url } else { $"($url)?($qp)" }')
  } else {
    $lines = ($lines | append '  let full_url = $url')
  }

  # build body record from individual params
  if $cmd.has_body and ($cmd.body_fields | length) > 0 {
    let path_param_names = ($cmd.path_params | each {|p| $p.name })
    mut body_parts = []
    for f in $cmd.body_fields {
      let sanitized_name = ($f.name | str replace --all '-' '_' | str replace --all --regex '[\\$()\[\].*/\x27"#!@%^&+=~`]' '' | str replace --regex '_{2,}' '_' | str trim --char '_')
      let collides = ($sanitized_name in $path_param_names) or ($sanitized_name in $RESERVED_VARS) or ($sanitized_name | is-empty)
      let nu_type = (openapi-to-nu-type $f.type)
      let is_nullable = ($f.nullable? | default false)
      let var_name = if $f.required and (not $collides) and ($nu_type != "bool") and (not $is_nullable) {
        '$' + $sanitized_name
      } else {
        let flag = if $collides { 'body_' + ((to-flag-name $f.name) | str replace --all '-' '_') } else { (to-flag-name $f.name) | str replace --all '-' '_' }
        '$' + $flag
      }
      $body_parts = ($body_parts | append ($f.name + ': ' + $var_name))
    }
    let body_record = $body_parts | str join ", "
    $lines = ($lines | append ('  let body = {' + $body_record + '} | transpose k v | where { $in.v != null } | transpose -r -d'))
  }

  # merge header params into auth headers
  if ($cmd.header_params | length) > 0 {
    mut hp_parts = []
    for hp in $cmd.header_params {
      let flag_name = (to-flag-name $hp.name)
      let var_name = '$' + ($flag_name | str replace --all '-' '_')
      $hp_parts = ($hp_parts | append ('"' + $hp.name + '": ' + $var_name))
    }
    let hp_record = $hp_parts | str join ", "
    $lines = ($lines | append ('  let extra_headers = {' + $hp_record + '} | transpose k v | where { $in.v != null } | transpose -r -d'))
    $lines = ($lines | append '  let auth = ($auth | update headers ($auth.headers | merge $extra_headers))')
  }

  # merge cookie params into auth headers as Cookie header
  if ($cmd.cookie_params | length) > 0 {
    mut cp_parts = []
    for cp in $cmd.cookie_params {
      let flag_name = (to-flag-name $cp.name)
      let var_name = '$' + ($flag_name | str replace --all '-' '_')
      $cp_parts = ($cp_parts | append ($cp.name + ': ' + $var_name))
    }
    let cp_record = $cp_parts | str join ", "
    $lines = ($lines | append ('  let cookie_str = {' + $cp_record + '} | transpose k v | where { $in.v != null } | each { $"($in.k)=($in.v)" } | str join "; "'))
    $lines = ($lines | append '  let auth = if ($cookie_str | is-not-empty) { $auth | update headers ($auth.headers | merge {Cookie: $cookie_str}) } else { $auth }')
  }

  # Accept header: default to first declared response type, allow override
  let default_accept = ($cmd.accept_types | first)
  $lines = ($lines | append ('  let accept_val = ($accept | default "' + $default_accept + '")'))
  $lines = ($lines | append '  let auth = ($auth | update headers ($auth.headers | merge {Accept: $accept_val}))')

  # for multipart with file fields, wrap file paths with open -r
  if $cmd.has_body and ($cmd.content_type == "multipart/form-data") and ($cmd.body_fields | length) > 0 {
    let has_file_fields = ($cmd.body_fields | where {|f| $f.type == "file" } | length) > 0
    if $has_file_fields {
      mut file_wraps = []
      for f in $cmd.body_fields {
        if $f.type == "file" {
          let sanitized = ($f.name | str replace --all '-' '_')
          let var_name = if $f.required { '$' + $sanitized } else { '$' + ((to-flag-name $f.name) | str replace --all '-' '_') }
          $file_wraps = ($file_wraps | append ('  let body = if (' + $var_name + ' | is-not-empty) { $body | upsert ' + $f.name + ' (open -r ' + $var_name + ') } else { $body }'))
        }
      }
      $lines = ($lines | append ($file_wraps | str join "\n"))
    }
  }

  # call do-request helper
  let body_arg = if $cmd.has_body { ' $body' } else { '' }
  let ct_arg = ' "' + $cmd.content_type + '"'
  $lines = ($lines | append ('  do-request "' + $cmd.method + '" $full_url $auth $insecure $raw $max_time $allow_errors' + $ct_arg + $body_arg))

  $lines | str join "\n"
}

# Render the full module file
def render-module [spec_data: record, commands: table, spec_file: string, module_name: string, h: record, extra_urls: list<string>, auth_schemes: list, default_auth: string] {
  let title = ($spec_data.info?.title? | default "api")
  let version_str = ($spec_data.info?.version? | default "0.0.0")
  let spec_url = (do $h.get-base-url $spec_data)
  let token_env_var = ($module_name | str upcase | str replace --all '-' '_' | str replace --all ' ' '_') + "_TOKEN"

  # merge spec url with extra urls, deduplicate
  let all_urls = ([$spec_url] | append $extra_urls | uniq)
  let default_url = if ($spec_url in $all_urls) { $spec_url } else { $all_urls | first }

  mut sections = []

  # collect and render completers
  let completer_data = (collect-completers $commands)
  let completers = $completer_data.completers
  let mapping = $completer_data.mapping
  let completers_code = if ($completers | columns | length) > 0 {
    "# Completers for enum parameters\n" + (render-completers $completers) + "\n"
  } else {
    ""
  }

  # base-url completer — include per-operation URLs
  let per_op_urls = ($commands | where {|c| $c.base_url != null } | each {|c| $c.base_url } | uniq)
  let all_completer_urls = ($all_urls | append $per_op_urls | uniq)
  let base_url_vals = $all_completer_urls | each {|u| $'"($u)"' } | str join ' '
  let bool_completer = "def \"bool-completer\" [] { [\"'true'\" \"'false'\"] }"
  let base_url_completer = $'def "base-url-completer" [] { [($base_url_vals)] }'

  # auth-scheme completer — include "none" if any op uses security: []
  let has_public = ($commands | where {|c| $c.default_auth == "none" } | length) > 0
  let auth_names = $auth_schemes | each {|s| $s.name } | uniq
  let auth_names_with_none = if $has_public { $auth_names | append "none" } else { $auth_names }
  let auth_completer_vals = if ($auth_names_with_none | length) > 0 {
    $auth_names_with_none | each {|n| $'"($n)"' } | str join ' '
  } else {
    '"bearer"'
  }
  let auth_completer = $'def "auth-scheme-completer" [] { [($auth_completer_vals)] }'

  let helpers_code = render-helpers $token_env_var $auth_schemes $default_auth

  $sections = ($sections | append ([
    $"# Auto-generated client for ($title) v($version_str)"
    $"# Source: ($spec_file)"
    $"# Auth: --token flag or $env.($token_env_var)"
    ""
    $"const BASE_URL = \"($default_url)\""
    $"const DEFAULT_AUTH = \"($default_auth)\""
    ""
    $helpers_code
    ""
    $bool_completer
    $base_url_completer
    $auth_completer
    ""
    $completers_code
    $"# Root command for namespace resolution"
    $"export def main [] { print \"($title) v($version_str) — ($commands | length) commands\" }"
    ""
  ] | str join "\n"))

  for cmd in $commands {
    mut cmd_lines = []

    let desc = if ($cmd.description | is-not-empty) {
      $cmd.description
    } else {
      $"($cmd.method | str upcase) ($cmd.path_template)"
    }
    let desc_lines = $desc | lines | each {|l| $"# ($l)" } | str join "\n"
    $cmd_lines = ($cmd_lines | append $desc_lines)

    if $cmd.deprecated {
      $cmd_lines = ($cmd_lines | append "# DEPRECATED")
    }

    if ($cmd.discriminator != null) {
      let d = $cmd.discriminator
      let mapping_keys = ($d.mapping | columns)
      if ($mapping_keys | length) > 0 {
        let variants = $mapping_keys | str join ", "
        $cmd_lines = ($cmd_lines | append $"# Discriminator \(($d.context)\): ($d.propertyName) = ($variants)")
      } else {
        $cmd_lines = ($cmd_lines | append $"# Discriminator \(($d.context)\): ($d.propertyName)")
      }
    }

    let sig = (build-signature $cmd $completers $mapping)
    $cmd_lines = ($cmd_lines | append $"export def \"($cmd.name)\" [")
    $cmd_lines = ($cmd_lines | append $sig)
    $cmd_lines = ($cmd_lines | append "] {")

    let body_code = (build-body-code $cmd)
    $cmd_lines = ($cmd_lines | append $body_code)
    $cmd_lines = ($cmd_lines | append "}")
    $cmd_lines = ($cmd_lines | append "")

    $sections = ($sections | append ($cmd_lines | str join "\n"))
  }

  $sections | str join "\n"
}

# Deduplicate command names.
# First pass: append path param names. Second pass: append numeric suffix for remaining dupes.
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

  # pass 2: numeric suffix for any remaining dupes
  let dup_names2 = $pass1 | group-by name | transpose name entries
    | where { ($in.entries | length) > 1 } | get name

  if ($dup_names2 | length) == 0 {
    return $pass1
  }

  # track seen counts per name
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

  # resolve refs in paths
  let resolved_paths = $spec_data.paths | transpose path methods | each {|entry|
    # resolve PathItem-level $ref first
    let path_item = if ($entry.methods | columns | any {|c| $c == "$ref"}) {
      spec resolve-ref $entry.methods $schemas
    } else {
      $entry.methods
    }
    let resolved_methods = $path_item | transpose method op | each {|m|
      let resolved_op = spec resolve-ref $m.op $schemas
      {$m.method: $resolved_op}
    } | reduce {|it, acc| $acc | merge $it}
    {$entry.path: $resolved_methods}
  } | reduce {|it, acc| $acc | merge $it}

  let resolved_spec = $spec_data | upsert paths $resolved_paths
  let auth_schemes = (do $h.get-auth-schemes $spec_data)
  let default_auth = (spec get-default-auth $spec_data $auth_schemes)
  let commands = build-commands $resolved_spec $schemas $h $auth_schemes $default_auth
  let deduped = deduplicate-commands $commands
  {spec: $resolved_spec, commands: $deduped, helpers: $h, auth_schemes: $auth_schemes, default_auth: $default_auth}
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
    error make { msg: "not a valid spec: missing 'paths' field" }
  }

  let title = if ($name | is-not-empty) { $name } else { $spec_data.info?.title? | default "api" }
  let result = process-spec $spec_data

  let output_content = render-module $result.spec $result.commands ($file | path expand | into string) $title $result.helpers ($urls | default []) $result.auth_schemes $result.default_auth
  let out_path = if ($output | is-not-empty) {
    $output
  } else {
    $"./($title).nu"
  }

  $output_content | save --force $out_path
  print $"Generated ($result.commands | length) commands -> ($out_path)"
}
