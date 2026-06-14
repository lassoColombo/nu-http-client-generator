# http-gen — OpenAPI 3.x / Swagger 2.0 to Nushell client generator.
#
# Usage:
#   use http-gen
#   http-gen ./spec.yaml -o ./client.nu
#   http-gen preview ./spec.yaml

use src/spec
use src/render.nu
use src/log.nu
use src/build.nu

# Format a list for log output: first 5 + "... (N total)" if longer than 5.
def truncated-display [items: list]: nothing -> string {
  if ($items | length) > 5 { $"($items | first 5 | str join ', '), ... \(($items | length) total\)" } else { $items | str join ", " }
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
    let display = (truncated-display ($list_candidates | each {|n| $n | split row ' ' | first }))
    log info $"($list_candidates | length) GET collection/item collision\(s\) resolved via list rename: ($display)"
  }
  if ($suffix_candidates | length) > 0 {
    log info $"($suffix_candidates | length) duplicate command name\(s\) disambiguated with path-param suffix: (truncated-display $suffix_candidates)"
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

  log info $"($dup_names2 | length) command name\(s\) still collide after path-param disambiguation, adding numeric suffixes: (truncated-display $dup_names2)"

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

# Shared pipeline: parse spec, resolve refs, extract metadata, build & dedupe commands.
# Returns {commands, auth_schemes, default_auth, base_url, all_urls}.
def process-spec [spec_data: record, config: record] {
  let info = (spec detect $spec_data)
  let h = match $info.schema {
    "openapi" => (spec oa3 helpers)
    "swagger" => (spec swagger2 helpers)
  }
  let raw_schemas = (do $h.get-schemas $spec_data)
  let schemas = (spec build-resolved-schemas $raw_schemas)
  let auth_schemes = (do $h.get-auth-schemes $spec_data)
  let default_auth = (spec get-default-auth $spec_data $auth_schemes)
  let commands = (build build-command-list $spec_data $schemas $h $auth_schemes $default_auth $config)
  {
    commands: (deduplicate-commands $commands)
    auth_schemes: $auth_schemes
    default_auth: $default_auth
    base_url: (do $h.get-base-url $spec_data)
    all_urls: (do $h.get-all-urls $spec_data)
  }
}

# Generate a Nushell HTTP client module from an OpenAPI/Swagger spec
export def main [
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
  --spec-headers: record        # Headers for fetching remote specs (e.g. {Authorization: "Bearer tok"})
] {
  let loaded = (build load-spec $source ($spec_headers | default {}))
  if ($loaded.data.paths? | is-empty) {
    error make --unspanned { msg: "not a valid OpenAPI/Swagger spec: missing 'paths' field" }
  }
  let config = {
    filter_tags: ($tags | default [])
    filter_prefixes: ($prefixes | default [])
    filter_methods: ($methods | default [] | each { $in | str downcase })
    exclude_deprecated: $exclude_deprecated
    verb_map: ($verb_map | default {})
    token_env_var: (if ($token_env_var | default "" | is-empty) { null } else { $token_env_var })
    default_timeout: $default_timeout
    default_headers: ($default_headers | default {})
    body_threshold: $body_threshold
    no_introspection: $no_introspection
    no_descriptions: $no_descriptions
    default_base_url: (if ($default_base_url | default "" | is-empty) { null } else { $default_base_url })
  }

  let title = if ($name | is-not-empty) { $name } else {
    $loaded.data.info?.title? | default ($loaded.source | path parse | get stem)
  }
  let result = (process-spec $loaded.data $config)
  if ($result.commands | is-empty) {
    log error "no commands were generated — check your spec content or filter flags"
  }
  let extra_urls = (($urls | default []) | append $result.all_urls)
  let output_content = (render render-module $loaded.data $result.commands $loaded.source $title $result.base_url $extra_urls $result.auth_schemes $result.default_auth $config)
  let out_path = if ($output | is-not-empty) { $output } else { $"./($title).nu" }
  $output_content | save --force $out_path
}

# Preview what commands would be generated from an OpenAPI/Swagger spec
export def preview [
  source: string                # OpenAPI/Swagger spec file path or URL
  --tags: list<string>          # Filter: only operations with these tags
  --prefixes: list<string>      # Filter: only paths matching these prefixes
  --methods: list<string>       # Filter: only these HTTP methods
  --exclude-deprecated          # Filter: skip deprecated operations
  --verb-map: record            # Naming: override action verbs e.g. {retrieve: "fetch"}
  --spec-headers: record        # Headers for fetching remote specs
] {
  let loaded = (build load-spec $source ($spec_headers | default {}))
  let config = {
    filter_tags: ($tags | default [])
    filter_prefixes: ($prefixes | default [])
    filter_methods: ($methods | default [] | each { $in | str downcase })
    exclude_deprecated: $exclude_deprecated
    verb_map: ($verb_map | default {})
    body_threshold: 0
  }

  let result = (process-spec $loaded.data $config)
  if ($result.commands | is-empty) {
    log error "no commands were generated — check your spec content or filter flags"
  }
  $result.commands | each {|c|
    {name: $c.name, method: $c.method, path_template: $c.path_template}
  }
}
