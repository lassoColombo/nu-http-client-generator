# nu-http-client-generator

Reads an OpenAPI 3.x, Swagger 2.0, or GraphQL introspection schema and generates a typed Nushell HTTP client module.

## Quick start

```nushell
use http-gen

# Generate a GitLab client from the Swagger spec URL
http-gen openapi "https://gitlab.com/gitlab-org/gitlab/-/raw/master/doc/api/openapi/openapi_v2.yaml" -o ./gitlab.nu --name gitlab

# Generate from a local spec file
http-gen openapi ./gitlab.yaml -o ./gitlab.nu --name gitlab

# Preview what commands would be generated (no file written)
http-gen openapi preview ./gitlab.yaml

# Generate only merge request and tag endpoints
http-gen openapi ./gitlab.yaml -o ./gitlab.nu --name gitlab --prefixes ["/api/v4/projects/{id}/merge_requests" "/api/v4/projects/{id}/repository/tags"]

# Generate from a GraphQL endpoint (auto-introspects via POST)
http-gen graphql "https://gitlab.com/-/graphql" -o ./gitlab-gql.nu --default-base-url "https://gitlab.com/-/graphql" --name gitlab-gql
```

Then use the generated client:

```nushell
use gitlab.nu

# List merge requests for a project
gitlab projects-merge-requests list 3347 --base-url "https://git.example.com" --token $pat --state opened

# Create a merge request
gitlab projects-merge-requests post 3347 "Add CI pipeline" "feature/ci" "main" --base-url "https://git.example.com" --token $pat --description "Adds CI/CD configuration" --labels [ci automation] --remove-source-branch true

# List repository tags
gitlab projects-repository-tags list 3347 --base-url "https://git.example.com" --token $pat --order-by name --search "v2.*"

# Pipe results through nushell — filter MRs by author, select columns
gitlab projects-merge-requests list 3347 --token $pat --base-url "https://git.example.com" | where author.username == "jdoe" | select iid title state
```

GraphQL example:

```nushell
use countries.nu

countries query country "IT" --fields [name capital emoji]
countries query countries --filter {code: {eq: "IT"}} --fields [name capital]
```

## Supported specs

| Format | Version | Detection |
|--------|---------|-----------|
| OpenAPI | 3.0.x | `openapi` field |
| Swagger | 2.0 | `swagger` field |
| GraphQL | Introspection | `data.__schema` field |

Auto-detected from the spec. The source can be a local file path or URL. For GraphQL URLs, if GET fails or returns an unrecognized format, `http-gen` automatically POSTs an introspection query.

## Subcommands

| Command | Description |
|---------|-------------|
| `http-gen openapi <spec> -o <output>` | Generate from OpenAPI/Swagger |
| `http-gen openapi preview <spec>` | Preview OpenAPI commands |
| `http-gen graphql <spec> -o <output>` | Generate from GraphQL schema |
| `http-gen graphql preview <spec>` | Preview GraphQL commands |

## Generator flags

### OpenAPI / Swagger

```nushell
http-gen openapi <spec> [-o <output>] [--name <name>] [-u <urls>]
    [--tags <list>] [--prefixes <list>] [--methods <list>]
    [--exclude-deprecated] [--verb-map <record>]
    [--token-env-var <string>] [--default-timeout <string>]
    [--default-headers <record>] [--default-base-url <string>]
    [--body-threshold <int>] [--no-introspection] [--no-descriptions]
```

### GraphQL

```nushell
http-gen graphql <spec> [-o <output>] [--name <name>] [-u <urls>]
    [--prefixes <list>] [--exclude-deprecated] [--verb-map <record>]
    [--default-base-url <string>]
    [--token-env-var <string>] [--default-timeout <string>]
    [--default-headers <record>] [--body-threshold <int>]
    [--no-introspection] [--no-descriptions]
```

### Flag reference

**Common flags** (both `openapi` and `graphql`):

| Flag | Description |
|------|-------------|
| `-o, --output` | Output file path (default: `./{title}.nu`) |
| `--name` | Override module name (affects env var and filename) |
| `-u, --urls` | Additional base URLs for tab-completion |
| `--token-env-var` | Override auto-derived token env var name |
| `--default-timeout` | Override default request timeout (default: `30min`) |
| `--default-headers` | Static headers added to every request (e.g. `{X-Tenant-Id: "acme"}`) |
| `--default-base-url` | Override default base URL (required for GraphQL) |
| `--body-threshold` | Collapse body fields to `--body: record` above this count (0 = never) |
| `--no-introspection` | Omit the `commands` subcommand from generated client |
| `--no-descriptions` | Omit inline `# description` comments on parameter flags |

**OpenAPI-only filter flags** (also available on `openapi preview`):

| Flag | Description |
|------|-------------|
| `--tags` | Only operations with matching tags |
| `--prefixes` | Only paths matching these prefixes (e.g. `["/pet"]`) |
| `--methods` | Only these HTTP methods (e.g. `[get post]`) |
| `--exclude-deprecated` | Skip deprecated operations |
| `--verb-map` | Override action verb mapping (e.g. `{retrieve: "fetch", list: "ls"}`) |

**GraphQL-only filter flags** (also available on `graphql preview`):

| Flag | Description |
|------|-------------|
| `--prefixes` | Only fields matching these name prefixes |
| `--exclude-deprecated` | Skip deprecated fields |
| `--verb-map` | Override action verb mapping |

## What gets generated

Each generated client contains:

- `build-auth` -- resolves token from flag or env var, returns headers + query auth
- `serialize-qp` -- serializes query params respecting collection styles (csv, multi, pipes, ssv)
- `do-request` -- HTTP method dispatch with `--insecure`, `--raw`, `--max-time` support
- `base-url-completer` / `auth-scheme-completer` -- tab-completion for base URLs and auth schemes
- One `export def` per API operation (REST) or per Query/Mutation field (GraphQL)
- Optional `commands` subcommand for runtime introspection (disable with `--no-introspection`)

## Common flags on every generated command

| Flag | Short | Description |
|------|-------|-------------|
| `--base-url` | `-b` | Override base URL (with tab-completion) |
| `--token` | `-t` | Auth token |
| `--auth-scheme` | `-a` | Override auth scheme (with tab-completion) |
| `--insecure` | `-k` | Skip TLS verification |
| `--max-time` | `-m` | Request timeout (default: 30min) |
| `--raw` | `-r` | Return response as text |
| `--allow-errors` | `-e` | Return full response record instead of error |

## Auth

Auth scheme is auto-detected from the spec's `securitySchemes` (OpenAPI 3.x) or `securityDefinitions` (Swagger 2.0).
Per-operation security overrides are respected.

| Scheme | Header |
|--------|--------|
| `jwt` | `Authorization: JWT <token>` |
| `bearer` | `Authorization: Bearer <token>` |
| `basic` | `Authorization: Basic <token>` |
| `private-token` | `PRIVATE-TOKEN: <token>` |
| `query-*` | Appends token to query string |
| `cookie-*` | `Cookie: <name>=<token>` |
| `none` | No auth (public endpoints) |

Token source: `--token (-t)` flag or `$env.<SERVICE>_TOKEN` (e.g. `$env.GITLAB_TOKEN`).
Override with `--auth-scheme (-a)`.

## Generated command conventions

### REST (OpenAPI / Swagger)

- **Object verb** order: `projects-merge-requests list`, `projects-repository-tags get` (not `list merge-requests`, which conflicts with nushell builtins)
- **Required params** are positional, **optional params** are flags
- **Enum params** get tab-completion
- **Boolean query params** are switches (no `: bool` annotation)
- **File upload fields** accept a `path` and are read with `open -r`
- **Deprecated operations** are marked with `# DEPRECATED`
- **readOnly fields** are excluded from request body params
- **nullable required fields** become flags (user can omit them)
- Duplicate command names are disambiguated: first by path param suffix (`-by-id`, `-by-name`), then by numeric counter

### GraphQL

- Commands are prefixed `query` or `mutation` (e.g. `query country`, `mutation save-user`)
- Each command has `--fields` (select returned fields) and `--query` (raw GraphQL override)
- Required scalar args are positional
- Default field selection includes only scalar fields at depth 1; use `--fields` for nested types
- Scalar-return queries (e.g. `[String]`) omit the selection set entirely
- Enum args get tab completers
- INPUT_OBJECT args are expanded into individual prefixed flags (e.g. `CountryFilterInput` with fields `code`, `continent` becomes `--filter-code: record`, `--filter-continent: record`); `--body-threshold` controls collapsing back to a single `--filter: record`
- `--default-base-url` is required since GraphQL schemas have no embedded endpoint URL

## Architecture

- **`mod.nu`** -- Entry point: spec loading (file or URL; auto-introspects GraphQL endpoints via POST), command model building, config construction, and four exported subcommands (`openapi`, `openapi preview`, `graphql`, `graphql preview`).
- **`spec.nu`** -- Dispatch table of closures keyed by `{schema, version}`. Provides `detect`, `get-default-auth`, `resolve-ref`, `get-non-body-params`, `get-param-description`, and per-version helpers. Adding a new spec version means adding an entry to the table.
- **`render.nu`** -- Code generation: type mapping, flag name sanitization, completer collection/dedup, signature building, body code generation, helper rendering, full module rendering.

## Spec coverage

Handles: paths, operations, path/query/header/cookie parameters, JSON and multipart/form-data request bodies, `$ref` resolution (including PathItem-level), `allOf` schema composition, parameter serialization styles, `deprecated`/`nullable`/`readOnly` fields, `default`/`format` hints, per-operation security and server overrides, GraphQL queries/mutations with INPUT_OBJECT expansion and default selection sets.

Not handled: response headers, content negotiation, `discriminator`, server variables, `oneOf`/`anyOf` structural flattening (validation-only use is fine), `encoding` for multipart, `allowEmptyValue`, parameter `content` field, GraphQL subscriptions.

## Acknowledgments

Golden-file tests are powered by [nutest](https://github.com/vyadh/nutest), a testing framework for Nushell.
