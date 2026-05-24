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
    "file" => "any"
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
def extract-body-fields [schema: record] {
  let props = ($schema.properties? | default {})
  let required = ($schema.required? | default [])
  $props | transpose name field_spec | each {|field|
    let field_type = ($field.field_spec.type? | default "any")
    let enum_vals = ($field.field_spec.enum? | default [])
    let desc = ($field.field_spec.description? | default "")
    {
      name: $field.name
      type: $field_type
      required: ($field.name in $required)
      enum: $enum_vals
      description: $desc
    }
  }
}

# Build the command model from a parsed+resolved spec
def build-commands [spec_data: record, schemas: record, h: record] {
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
      let parameters = ($op.parameters? | default [])

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

      let body_fields = if ($body_schema | is-not-empty) and (($body_schema | describe) | str starts-with "record") and (($body_schema | columns | length) > 0) {
        extract-body-fields $body_schema
      } else {
        []
      }

      # response: does it return a body?
      let responses = ($op.responses? | default {})
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
        has_body: $has_body
        body_fields: $body_fields
        returns_body: $returns_body
        description: $description
        operation_id: $operation_id
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
    # collect from query params and body fields
    let enum_sources = ($cmd.query_params | append $cmd.body_fields)
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

  $parts = ($parts | append "  --base-url: string")
  $parts = ($parts | append "  --token: string")
  $parts = ($parts | append "  --auth-scheme: string")
  $parts = ($parts | append "  --insecure(-k) # Skip TLS verification")
  $parts = ($parts | append "  --max-time(-m): duration # Timeout")
  $parts = ($parts | append "  --raw(-r) # Fetch as text")
  $parts = ($parts | append "  --allow-errors(-e) # Return full response without error handling")

  for q in $cmd.query_params {
    let nu_type = (openapi-to-nu-type $q.type)
    let flag_name = (to-flag-name $q.name)
    let desc_text = if ($q.description | is-not-empty) { $q.description | lines | str join " " } else { "" }
    let desc = if ($desc_text | is-not-empty) { $" # ($desc_text)" } else { "" }
    let cname = if ($q.enum | length) > 0 { resolve-completer $q $mapping } else { null }
    # boolean flags in nushell are switches — no type annotation
    if $nu_type == "bool" {
      $parts = ($parts | append $"  --($flag_name)($desc)")
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
      let sanitized_name = ($f.name | str replace --all '-' '_')
      let collides = ($sanitized_name in $path_param_names)
      let cname = if ($f.enum | length) > 0 { resolve-completer $f $mapping } else { null }
      if $f.required and (not $collides) and ($nu_type != "bool") {
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
          $parts = ($parts | append $"  --($flag_name)($desc)")
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

# Build the body code for a command
def build-body-code [cmd: record, token_env_var: string] {
  mut lines = []

  $lines = ($lines | append ('  let token_val = if ($token | is-not-empty) { $token } else { $env.' + $token_env_var + '? | default "" }'))
  $lines = ($lines | append '  let scheme = ($auth_scheme | default "jwt")')
  $lines = ($lines | append '  let prefix = match $scheme { "jwt" => "JWT", "bearer" => "Bearer", "basic" => "Basic", "static" => "STATIC", "private-token" => "PRIVATE-TOKEN", _ => "JWT" }')
  $lines = ($lines | append '  let headers = if ($token_val | is-empty) { {} } else if $scheme == "private-token" { {PRIVATE-TOKEN: $token_val} } else { {Authorization: $"($prefix) ($token_val)"} }')

  $lines = ($lines | append '  let base = ($base_url | default $BASE_URL)')

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
    mut qp_parts = []
    for q in $cmd.query_params {
      let flag_name = (to-flag-name $q.name)
      let var_name = '$' + ($flag_name | str replace --all '-' '_')
      $qp_parts = ($qp_parts | append ($q.name + ': ' + $var_name))
    }
    let qp_record = $qp_parts | str join ", "
    $lines = ($lines | append ('  let qp = {' + $qp_record + '} | transpose k v | where { $in.v != null } | each { $"($in.k)=($in.v)" } | str join "&"'))
    $lines = ($lines | append '  let full_url = if ($qp | is-empty) { $url } else { $"($url)?($qp)" }')
  } else {
    $lines = ($lines | append '  let full_url = $url')
  }

  # build body record from individual params
  if $cmd.has_body and ($cmd.body_fields | length) > 0 {
    let path_param_names = ($cmd.path_params | each {|p| $p.name })
    mut body_parts = []
    for f in $cmd.body_fields {
      let sanitized_name = ($f.name | str replace --all '-' '_')
      let collides = ($sanitized_name in $path_param_names)
      let nu_type = (openapi-to-nu-type $f.type)
      let var_name = if $f.required and (not $collides) and ($nu_type != "bool") {
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

  $lines = ($lines | append '  let timeout = ($max_time | default 30min)')

  let http_method = $cmd.method
  if $http_method in ["post" "put" "patch"] {
    let body_arg = if $cmd.has_body { " $body" } else { " {}" }
    let base = 'http ' + $http_method + ' --headers $headers --content-type application/json --full --allow-errors --max-time $timeout'
    $lines = ($lines | append ('  let resp = if $insecure and $raw { ' + $base + ' --insecure --raw $full_url' + $body_arg + ' } else if $insecure { ' + $base + ' --insecure $full_url' + $body_arg + ' } else if $raw { ' + $base + ' --raw $full_url' + $body_arg + ' } else { ' + $base + ' $full_url' + $body_arg + ' }'))
  } else if $http_method == "delete" {
    let base = 'http delete --headers $headers --full --allow-errors --max-time $timeout'
    $lines = ($lines | append ('  let resp = if $insecure and $raw { ' + $base + ' --insecure --raw $full_url } else if $insecure { ' + $base + ' --insecure $full_url } else if $raw { ' + $base + ' --raw $full_url } else { ' + $base + ' $full_url }'))
  } else {
    let base = 'http ' + $http_method + ' --headers $headers --full --allow-errors --max-time $timeout'
    $lines = ($lines | append ('  let resp = if $insecure and $raw { ' + $base + ' --insecure --raw $full_url } else if $insecure { ' + $base + ' --insecure $full_url } else if $raw { ' + $base + ' --raw $full_url } else { ' + $base + ' $full_url }'))
  }

  if not $cmd.returns_body {
    $lines = ($lines | append '  if $allow_errors { $resp } else if $resp.status == 204 { null } else if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status)" } } else { $resp.body }')
  } else {
    $lines = ($lines | append '  if $allow_errors { $resp } else if $resp.status >= 400 { error make { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }')
  }

  $lines | str join "\n"
}

# Render the full module file
def render-module [spec_data: record, commands: table, spec_file: string, module_name: string, h: record] {
  let title = ($spec_data.info?.title? | default "api")
  let version_str = ($spec_data.info?.version? | default "0.0.0")
  let base_url = (do $h.get-base-url $spec_data)
  let token_env_var = ($module_name | str upcase | str replace --all '-' '_' | str replace --all ' ' '_') + "_TOKEN"

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

  $sections = ($sections | append ([
    $"# Auto-generated client for ($title) v($version_str)"
    $"# Source: ($spec_file)"
    $"# Auth: --token flag or $env.($token_env_var)"
    ""
    $"const BASE_URL = \"($base_url)\""
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

    let sig = (build-signature $cmd $completers $mapping)
    $cmd_lines = ($cmd_lines | append $"export def \"($cmd.name)\" [")
    $cmd_lines = ($cmd_lines | append $sig)
    $cmd_lines = ($cmd_lines | append "] {")

    let body_code = (build-body-code $cmd $token_env_var)
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
    let resolved_methods = $entry.methods | transpose method op | each {|m|
      let resolved_op = spec resolve-ref $m.op $schemas
      {$m.method: $resolved_op}
    } | reduce {|it, acc| $acc | merge $it}
    {$entry.path: $resolved_methods}
  } | reduce {|it, acc| $acc | merge $it}

  let resolved_spec = $spec_data | upsert paths $resolved_paths
  let commands = build-commands $resolved_spec $schemas $h
  let deduped = deduplicate-commands $commands
  {spec: $resolved_spec, commands: $deduped, helpers: $h}
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
] {
  let spec_data = open $file

  if ($spec_data.paths? | is-empty) {
    error make { msg: "not a valid spec: missing 'paths' field" }
  }

  let title = if ($name | is-not-empty) { $name } else { $spec_data.info?.title? | default "api" }
  let result = process-spec $spec_data

  let output_content = render-module $result.spec $result.commands ($file | path expand | into string) $title $result.helpers
  let out_path = if ($output | is-not-empty) {
    $output
  } else {
    $"./($title).nu"
  }

  $output_content | save --force $out_path
  print $"Generated ($result.commands | length) commands -> ($out_path)"
}
