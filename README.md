# nu-http-client-generator

Reads an API specification and generates a typed Nushell HTTP client module.

[![asciicast](https://asciinema.org/a/IQtLxd5nJoZSf0AW.svg)](https://asciinema.org/a/IQtLxd5nJoZSf0AW)

## Supported specs

| Format | Version |
|--------|---------|
| OpenAPI | 3.0.x |
| Swagger | 2.0 |
| GraphQL | Introspection |


## Installation

```nushell
# clone this repository into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) nu-http-client-generator] | path join
git clone git@github.com:lassoColombo/nu-http-client-generator.git $dest

# use the module
use nu-http-client-generator
nu-http-client-generator --help
```

## Quick start

```nushell
use nu-http-client-generator

# Generate a client from a spec file
nu-http-client-generator openapi ./gitlab.yaml -o ./gitlab.nu --name gitlab

# Generate from a URL
nu-http-client-generator openapi "https://gitlab.com/gitlab-org/gitlab/-/raw/master/doc/api/openapi/openapi_v2.yaml" -o ./gitlab.nu --name gitlab

# Preview what commands would be generated (no file written)
nu-http-client-generator openapi preview ./gitlab.yaml

# Generate only specific endpoints
nu-http-client-generator openapi ./gitlab.yaml -o ./gitlab.nu --name gitlab --prefixes ["/api/v4/projects/{id}/merge_requests"]

# Generate from a GraphQL endpoint (auto-introspects)
nu-http-client-generator graphql "https://countries.trevorblades.com/graphql" -o ./countries.nu --default-base-url "https://countries.trevorblades.com/graphql"

# Generate from a GraphQL endpoint that requires authentication
nu-http-client-generator graphql "https://gitlab.com/-/graphql" -o ./gitlab-gql.nu --default-base-url "https://gitlab.com/-/graphql" --name gitlab-gql --spec-headers {Authorization: "Bearer ghp_xxx"}
```

Then use the generated client:

```nushell
use gitlab.nu

# List merge requests for a project
gitlab projects-merge-requests list 3347 --base-url "https://git.example.com" --token $pat --state opened

# Pipe results through nushell
gitlab projects-merge-requests list 3347 --token $pat --base-url "https://git.example.com" | where author.username == "jdoe" | select iid title state
```

GraphQL example:

```nushell
use countries.nu

countries query country "IT" --fields [name capital emoji]
countries query countries --filter {code: {eq: "IT"}} --fields [name capital]
```


## Subcommands

| Command | Description |
|---------|-------------|
| `nu-http-client-generator openapi <spec> -o <output>` | Generate from OpenAPI/Swagger |
| `nu-http-client-generator openapi preview <spec>` | Preview OpenAPI commands |
| `nu-http-client-generator graphql <spec> -o <output>` | Generate from GraphQL schema |
| `nu-http-client-generator graphql preview <spec>` | Preview GraphQL commands |

## Flags

### Filter flags

| Flag | Applies to | Description |
|------|-----------|-------------|
| `--tags` | OpenAPI | Only operations with matching tags |
| `--prefixes` | Both | Only paths/fields matching these prefixes |
| `--methods` | OpenAPI | Only these HTTP methods (e.g. `[get post]`) |
| `--exclude-deprecated` | Both | Skip deprecated operations/fields |
| `--verb-map` | Both | Override action verb mapping (e.g. `{retrieve: "fetch"}`) |

### Output flags

| Flag | Description |
|------|-------------|
| `-o, --output` | Output file path (default: `./{title}.nu`) |
| `--name` | Override module name |
| `-u, --urls` | Additional base URLs for tab-completion |
| `--default-base-url` | Override default base URL (required for GraphQL) |
| `--token-env-var` | Override auto-derived token env var name |
| `--default-timeout` | Override default request timeout (default: `30min`) |
| `--default-headers` | Static headers added to every request (e.g. `{X-Tenant-Id: "acme"}`) |
| `--body-threshold` | Collapse body fields to `--body: record` above this count (0 = never) |
| `--no-introspection` | Omit the `commands` subcommand from generated client |
| `--no-descriptions` | Omit inline description comments on flags |

## Auth

Auth scheme is auto-detected from the spec. Token is resolved from `--token` flag or `$env.<SERVICE>_TOKEN` (e.g. `$env.GITLAB_TOKEN`). Override with `--auth-scheme`.

Supported schemes: `jwt`, `bearer`, `basic`, `private-token`, `query-*`, `cookie-*`, `none`.

## Generated command conventions

- **Object verb** order: `projects list`, `tags get` (not `list projects`)
- Required params are positional, optional params are flags
- Enum params get tab-completion
- Boolean query params are switches
- GraphQL commands are prefixed `query` or `mutation`
- GraphQL commands support `--fields` (select returned fields) and `--query` (raw GraphQL override)

### Common flags on every generated command

| Flag | Short | Description |
|------|-------|-------------|
| `--base-url` | `-b` | Override base URL |
| `--token` | `-t` | Auth token |
| `--auth-scheme` | `-a` | Override auth scheme |
| `--insecure` | `-k` | Skip TLS verification |
| `--max-time` | `-m` | Request timeout |
| `--raw` | `-r` | Return response as text |
| `--allow-errors` | `-e` | Return full response record instead of error |

## Acknowledgments

Tests are powered by [nutest](https://github.com/vyadh/nutest), a testing framework for Nushell.
