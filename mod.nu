# http-gen — OpenAPI 3.x / Swagger 2.0 / GraphQL to Nushell client generator.
#
# Usage:
#   use http-gen
#   http-gen openapi ./spec.yaml -o ./client.nu
#   http-gen graphql ./schema.json -o ./client.nu --default-base-url "https://api.example.com/graphql"
#   http-gen openapi preview ./spec.yaml
#   http-gen graphql preview ./schema.json

use src/spec
use src/render
use src/log
use src/build

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
    log info $"($list_candidates | length) GET collection/item collision\(s\) resolved via list rename: ($display)"
  }
  if ($suffix_candidates | length) > 0 {
    let display = if ($suffix_candidates | length) > 5 { $"($suffix_candidates | first 5 | str join ', '), ... \(($suffix_candidates | length) total\)" } else { $suffix_candidates | str join ", " }
    log info $"($suffix_candidates | length) duplicate command name\(s\) disambiguated with path-param suffix: ($display)"
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
  log info $"($dup_names2 | length) command name\(s\) still collide after path-param disambiguation, adding numeric suffixes: ($display2)"

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
def process-spec [spec_data: record, config: record] {
  let info = (spec detect $spec_data)
  let h = match $info.schema {
    "openapi" => (spec oa3 helpers)
    "swagger" => (spec swagger2 helpers)
    "graphql" => (spec graphql helpers)
  }
  let strategy = match $info.schema {
    "graphql" => (render graphql-render-strategy)
    _ => (render rest-render-strategy)
  }
  let schemas = (do $h.get-schemas $spec_data)

  let built = match $info.schema {
    "graphql" => (build graphql build-commands $spec_data $schemas $config)
    _ => (build rest build-commands $spec_data $schemas $h $config)
  }

  let deduped = deduplicate-commands $built.commands
  {spec: $spec_data, commands: $deduped, helpers: $h, auth_schemes: $built.auth_schemes, default_auth: $built.default_auth, base_url: $built.base_url, all_urls: $built.all_urls, strategy: $strategy}
}

# Shared generation pipeline — called by openapi and graphql subcommands.
def generate-module [loaded: record, config: record, name_flag: any, output_flag: any, urls_flag: list] {
  let title = if ($name_flag | is-not-empty) { $name_flag } else {
    $loaded.data.info?.title? | default ($loaded.source | path parse | get stem)
  }
  let result = process-spec $loaded.data $config
  if ($result.commands | is-empty) {
    log error "no commands were generated — check your spec content or filter flags"
  }
  let extra_urls = ($urls_flag | append $result.all_urls)
  let output_content = render render-module $result.spec $result.commands $loaded.source $title $result.base_url $extra_urls $result.auth_schemes $result.default_auth $config $result.strategy
  let out_path = if ($output_flag | is-not-empty) { $output_flag } else { $"./($title).nu" }
  $output_content | save --force $out_path
}

# Shared preview pipeline — called by openapi and graphql preview subcommands.
def preview-commands [loaded: record, config: record] {
  let result = process-spec $loaded.data $config
  if ($result.commands | is-empty) {
    log error "no commands were generated — check your spec content or filter flags"
  }
  $result.commands | each {|c|
    {name: $c.name, method: $c.method, path_template: (if ($c.path_template | is-empty) { $c.gql_field_name? | default "" } else { $c.path_template })}
  }
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
  --spec-headers: record        # Headers for fetching remote specs (e.g. {Authorization: "Bearer tok"})
] {
  let loaded = (build rest load-spec $source ($spec_headers | default {}))
  let info = (spec detect $loaded.data)
  if $info.schema == "graphql" {
    error make --unspanned { msg: $"spec is ($info.schema), not OpenAPI/Swagger" }
  }
  if ($loaded.data.paths? | is-empty) {
    error make --unspanned { msg: "not a valid OpenAPI/Swagger spec: missing 'paths' field" }
  }
  let config = (
    build-config
    ($tags | default [])
    ($prefixes | default [])
    ($methods | default [])
    $exclude_deprecated
    ($verb_map | default {})
    ($token_env_var | default "")
    $default_timeout
    ($default_headers | default {})
    $body_threshold
    $no_introspection
    $no_descriptions
    ($default_base_url | default "")
  )

  (
    generate-module
    $loaded
    $config
    ($name | default "")
    $output
    ($urls | default [])
  )
}

# Preview what commands would be generated from an OpenAPI/Swagger spec
export def "openapi preview" [
  source: string                # OpenAPI/Swagger spec file path or URL
  --tags: list<string>          # Filter: only operations with these tags
  --prefixes: list<string>      # Filter: only paths matching these prefixes
  --methods: list<string>       # Filter: only these HTTP methods
  --exclude-deprecated          # Filter: skip deprecated operations
  --verb-map: record            # Naming: override action verbs e.g. {retrieve: "fetch"}
  --spec-headers: record        # Headers for fetching remote specs
] {
  let loaded = (build rest load-spec $source ($spec_headers | default {}))
  let info = (spec detect $loaded.data)
  if $info.schema == "graphql" {
    error make --unspanned { msg: $"spec is ($info.schema), not OpenAPI/Swagger" }
  }
  let config = (
    build-config
    ($tags | default [])
    ($prefixes | default [])
    ($methods | default [])
    $exclude_deprecated
    ($verb_map | default {})
  )

  (
    preview-commands 
    $loaded 
    $config
  )
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
  --spec-headers: record        # Headers for fetching remote specs (e.g. {Authorization: "Bearer tok"})
] {
  let loaded = (build graphql load-spec $source ($spec_headers | default {}))
  let info = (spec detect $loaded.data)
  if $info.schema != "graphql" {
    error make --unspanned { msg: $"spec is ($info.schema), not GraphQL" }
  }
  if ($loaded.data.data?.__schema?.types? | is-empty) {
    error make --unspanned { msg: "not a valid GraphQL introspection result: missing types" }
  }
  if ($default_base_url | default "" | is-empty) {
    log error "--default-base-url not set for GraphQL spec; generated client will have an empty base URL"
  }
  let config = (
    build-config
    []
    ($prefixes | default [])
    []
    $exclude_deprecated
    ($verb_map | default {})
    ($token_env_var | default "")
    $default_timeout
    ($default_headers | default {})
    $body_threshold
    $no_introspection
    $no_descriptions
    ($default_base_url | default "")
  )

  (
    generate-module 
    $loaded 
    $config 
    ($name | default "") 
    $output 
    ($urls | default [])
  )
}

# Preview what commands would be generated from a GraphQL schema
export def "graphql preview" [
  source: string                # GraphQL introspection schema file path or endpoint URL
  --prefixes: list<string>      # Filter: only fields matching these name prefixes
  --exclude-deprecated          # Filter: skip deprecated fields
  --verb-map: record            # Naming: override action verbs e.g. {retrieve: "fetch"}
  --spec-headers: record        # Headers for fetching remote specs
] {
  let loaded = (build graphql load-spec $source ($spec_headers | default {}))
  let info = (spec detect $loaded.data)
  if $info.schema != "graphql" {
    error make --unspanned { msg: $"spec is ($info.schema), not GraphQL" }
  }
  let config = (
    build-config
    []
    ($prefixes | default []) 
    []
    $exclude_deprecated 
    ($verb_map | default {})
  )

  (
    preview-commands
    $loaded
    $config
  )
}
