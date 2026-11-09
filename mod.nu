# http-gen — OpenAPI 3.x / Swagger 2.0 to Nushell client generator.
#
# Usage:
#   use http-gen
#   http-gen ./spec.yaml -o ./client.nu
#   http-gen preview ./spec.yaml

use src/spec/spec.nu
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
  {
    commands: (model command-list $doc $h $auth_schemes (spec root-auth $doc $auth_schemes) $config)
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

# The default output file stem for a title: lowercased, every run of
# characters outside `[a-z0-9._-]` collapsed to `-`. A raw title such as
# `Pets / Store API` would otherwise make `save` write into a `Pets ` directory.
def default-file-stem [title: string]: nothing -> string {
  # Edge `.`/`-` would make a hidden file (`.internal.nu`) or a doubled dot
  # (`foo-inc..nu`); a title that already ends in `.nu` would double the
  # extension. Trim, drop the extension, trim what that exposes.
  let trim_edges = {|s| $s | str replace --all --regex '^[.-]+|[.-]+$' '' }
  let stem = ($title | str lowercase | str replace --all --regex '[^a-z0-9._-]+' '-')
  let stem = (do $trim_edges (do $trim_edges $stem | str replace --regex '\.nu$' ''))
  if ($stem | is-empty) { "client" } else { $stem }
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
  --default-timeout: duration = 30min  # Override default request timeout
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
  # The three optional strings stay null when unset; render tests them with
  # `is-not-empty`, which treats null and "" alike.
  let config = (filter-config $tags $prefixes $methods $exclude_deprecated $name_fn) | merge {
    token_env_var: $token_env_var
    default_timeout: $default_timeout
    default_headers: ($default_headers | default {})
    body_threshold: $body_threshold
    no_introspection: $no_introspection
    no_descriptions: $no_descriptions
    default_base_url: $default_base_url
    autocompletion_base_urls: ($autocompletion_base_urls | default [])
    default_unix_socket: $default_unix_socket
    autocompletion_unix_sockets: ($autocompletion_unix_sockets | default [])
  }

  # The module name drives the token env var and the default file stem; render
  # takes the header's display title from `info.title` itself. Interpolated:
  # an unquoted YAML title such as `title: 2024` is a number.
  let module_name = if ($name | is-not-empty) { $name } else {
    $"($loaded.data.info?.title? | default ($loaded.source | path parse | get stem))"
  }
  let result = (process-spec $loaded.data $config)
  # An error, not a warning: the caller asked for a file and would otherwise
  # get exit status 0 and no output. `preview` keeps returning [] since an
  # empty preview is a legitimate answer.
  if ($result.commands | is-empty) {
    error make --unspanned { msg: $"spec at ($loaded.source) yields no commands after filtering — nothing to generate" }
  }
  let output_content = (render client $loaded $module_name $result $config)
  let out_path = if ($output | is-not-empty) { $output } else { $"./(default-file-stem $module_name).nu" }
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
