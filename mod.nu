# http-gen — OpenAPI 3.x / Swagger 2.0 to Nushell client generator.
#
# Usage:
#   use http-gen
#   http-gen ./spec.yaml -o ./client.nu
#   http-gen preview ./spec.yaml

use src/spec
# nu 0.114 stopped exposing a directory module's submodules through the parent
# namespace (`spec oa3 ...` no longer resolves after `use src/spec`), so import
# the version-specific helper submodules directly.
use src/spec/oa3.nu
use src/spec/swagger2.nu
use src/render.nu
use src/log.nu
use src/model.nu

# Assert that a loaded spec has callable endpoints; errors otherwise with a
# message naming the reason (webhooks-only, empty `paths`, or no `paths` at
# all — the last isn't a valid OpenAPI/Swagger shape).
def check-spec-generatable [loaded: record] {
  let has_paths = ($loaded.data.paths? | is-not-empty)
  let has_webhooks = ($loaded.data.webhooks? | is-not-empty)
  if $has_paths { return }
  # OpenAPI 3.1 promoted `webhooks` to a top-level Paths-sibling for specs
  # that describe only inbound server-to-client events.
  if $has_webhooks {
    error make --unspanned $"spec at ($loaded.source) defines only webhooks \(server-to-client events\), no callable endpoints — nothing to generate"
  }
  if ($loaded.data.paths? | describe -d | get type) == "record" {
    error make --unspanned $"spec at ($loaded.source) defines no operations \(empty 'paths' object\) — nothing to generate"
  }
  error make --unspanned { msg: $"not a valid OpenAPI/Swagger spec: missing 'paths' field \(source: ($loaded.source)\)" }
}

# Shared pipeline: detect the format, extract auth metadata, build the
# command model. Returns {commands, auth_schemes, base_url, all_urls}.
def process-spec [doc: record, config: record] {
  let info = (spec detect $doc)
  let h = match $info.schema {
    "openapi" => (oa3 helpers)
    "swagger" => (swagger2 helpers)
  }
  let auth_schemes = (do $h.get-auth-schemes $doc)
  let default_auth = (spec get-default-auth $doc $auth_schemes)
  let default_auth_required = (spec get-default-auth-required $doc $auth_schemes)
  {
    commands: (model command-list $doc $h $auth_schemes $default_auth $default_auth_required $config)
    auth_schemes: $auth_schemes
    base_url: (do $h.get-base-url $doc)
    all_urls: (do $h.get-all-urls $doc)
  }
}

# The config keys model reads: operation filters and the naming override.
# Shared by `main` and `preview`.
def filter-config [tags: any, prefixes: any, methods: any, exclude_deprecated: bool, name_fn: any] {
  {
    filter_tags: ($tags | default [])
    filter_prefixes: ($prefixes | default [])
    filter_methods: ($methods | default [] | each { $in | str lowercase })
    exclude_deprecated: $exclude_deprecated
    name_fn: $name_fn
  }
}

# Generate a Nushell HTTP client module from an OpenAPI/Swagger spec
export def main [
  source: string                # OpenAPI/Swagger spec file path or URL
  --output(-o): path            # Output .nu file (default: ./{title}.nu)
  --name: string                # Override module name
  --autocompletion-base-urls: list<string>  # Extra base URLs for tab-completion (first becomes default if --default-base-url unset)
  --tags: list<string>          # Filter: only operations with these tags
  --prefixes: list<string>      # Filter: only paths matching these prefixes
  --methods: list<string>       # Filter: only these HTTP methods
  --exclude-deprecated          # Filter: skip deprecated operations
  --name-fn: closure            # Naming: override command names (receives raw/params/derived context, returns a name or null)
  --token-env-var: string       # Override auto-derived token env var name
  --default-timeout: string = "30min"  # Override default request timeout
  --default-headers: record     # Static headers added to every request
  --body-threshold: int = 0     # Collapse body fields to --body:record above this count (0 = never)
  --no-introspection            # Omit the commands subcommand
  --no-descriptions             # Omit parameter descriptions
  --default-base-url: string    # Override default base URL from spec
  --default-unix-socket: string # Talk to the API over this Unix socket by default
  --autocompletion-unix-sockets: list<string>  # Unix socket paths for tab-completion (first becomes default if --default-unix-socket unset)
  --spec-headers: record        # Headers for fetching remote specs (e.g. {Authorization: "Bearer tok"})
] {
  let loaded = (spec load-spec $source ($spec_headers | default {}))
  check-spec-generatable $loaded
  let config = (filter-config $tags $prefixes $methods $exclude_deprecated $name_fn) | merge {
    token_env_var: (if ($token_env_var | is-empty) { null } else { $token_env_var })
    default_timeout: $default_timeout
    default_headers: ($default_headers | default {})
    body_threshold: $body_threshold
    no_introspection: $no_introspection
    no_descriptions: $no_descriptions
    default_base_url: (if ($default_base_url | is-empty) { null } else { $default_base_url })
    autocompletion_base_urls: ($autocompletion_base_urls | default [])
    default_unix_socket: (if ($default_unix_socket | is-empty) { null } else { $default_unix_socket })
    autocompletion_unix_sockets: ($autocompletion_unix_sockets | default [])
  }

  let title = if ($name | is-not-empty) { $name } else {
    $loaded.data.info?.title? | default ($loaded.source | path parse | get stem)
  }
  let result = (process-spec $loaded.data $config)
  if ($result.commands | is-empty) {
    log warn $"spec at ($loaded.source) yields no commands after filtering — nothing to generate"
    return null
  }
  let output_content = (render client $loaded.data $result.commands $loaded.source $title $result.base_url $result.all_urls $result.auth_schemes $config)
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
  --name-fn: closure            # Naming: override command names (receives raw/params/derived context, returns a name or null)
  --spec-headers: record        # Headers for fetching remote specs
] {
  let loaded = (spec load-spec $source ($spec_headers | default {}))
  check-spec-generatable $loaded
  let config = (filter-config $tags $prefixes $methods $exclude_deprecated $name_fn) | merge {body_threshold: 0}

  let result = (process-spec $loaded.data $config)
  if ($result.commands | is-empty) {
    log warn $"spec at ($loaded.source) yields no commands after filtering — nothing to preview"
    return []
  }
  $result.commands | each {|c|
    {name: $c.name, method: $c.method, path_template: $c.path_template}
  }
}
