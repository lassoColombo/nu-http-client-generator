# nu-http-client-generator

Reads an API specification and generates a typed Nushell HTTP client module — one command per operation, with tab-completion, auth, and validated input.

[![asciicast](https://asciinema.org/a/IQtLxd5nJoZSf0AW.svg)](https://asciinema.org/a/IQtLxd5nJoZSf0AW)

---

## Supported specs

| Format  | Versions               |
| ------- | ---------------------- |
| OpenAPI | 3.0.x, 3.1.x           |
| Swagger | 2.0                    |
| GraphQL | Introspection JSON, SDL |

Specs can be loaded from a local file or fetched directly from a URL.

---

## Installation

```nu
# Clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) nu-http-client-generator] | path join
git clone git@github.com:lassoColombo/nu-http-client-generator.git $dest

# Use the module
use nu-http-client-generator
nu-http-client-generator --help
```

---

## Quick start

```nu
use nu-http-client-generator

# Generate from a file
nu-http-client-generator openapi ./docker-hub.yaml -o ./docker-hub.nu

# Generate from a URL
nu-http-client-generator openapi "https://api.apis.guru/v2/specs/docker.com/hub/beta/openapi.json" -o ./docker-hub.nu

# Preview what would be generated (no file written)
nu-http-client-generator openapi preview ./docker-hub.yaml

# GraphQL — auto-introspects the endpoint
nu-http-client-generator graphql "https://countries.trevorblades.com/graphql" \
  -o ./countries.nu --default-base-url "https://countries.trevorblades.com/graphql"
```

Then use it:

```nu
use docker-hub.nu

docker-hub namespaces-repositories-tags list "library" "nginx" --page-size 50 | get results | where tag_status == "active"
docker-hub access-tokens get "f0c3a1ce-8cf4-4..."
docker-hub access-tokens list --token $env.DOCKER_HUB_API_TOKEN
```

---

## Subcommands

| Command                                     | Purpose                                       |
| ------------------------------------------- | --------------------------------------------- |
| `nu-http-client-generator openapi <src>`    | Generate a client from OpenAPI/Swagger.       |
| `nu-http-client-generator openapi preview <src>` | List the commands that would be generated. |
| `nu-http-client-generator graphql <src>`    | Generate a client from a GraphQL schema.      |
| `nu-http-client-generator graphql preview <src>` | List the commands that would be generated. |

`<src>` is either a local file path or an `http(s)://` URL.

---

## Generation flags

### Source & output

| Flag                       | Default            | Description                                                                                                                |
| -------------------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `-o, --output: path`       | `./{title}.nu`     | Where to write the generated module.                                                                                       |
| `--name: string`           | spec `info.title`  | Module name. Used as the file stem (when `-o` is not set), as the prefix of the token env var, and as the command namespace. |
| `-u, --urls: list<string>` | spec servers       | Additional base URLs added to `--base-url`'s tab-completer.                                                                |
| `--default-base-url: string` | spec / none      | Override the base URL embedded in the module. **Required** for GraphQL (introspection schemas don't carry an endpoint URL). |
| `--spec-headers: record`   | `{}`               | Headers used when fetching a remote spec (e.g. `{Authorization: "Bearer …"}`). Does not appear in the generated client.    |

### Filtering

Filters apply to both `<format>` and `<format> preview`. Combine freely.

| Flag                            | Applies to | Description                                                                              |
| ------------------------------- | ---------- | ---------------------------------------------------------------------------------------- |
| `--tags: list<string>`          | OpenAPI    | Only operations tagged with one of these.                                                |
| `--prefixes: list<string>`      | Both       | OpenAPI: paths starting with the prefix (e.g. `["/pet"]`). GraphQL: kebab-cased field-name prefixes. |
| `--methods: list<string>`       | OpenAPI    | Only these HTTP methods (e.g. `[get post]`). Case-insensitive.                           |
| `--exclude-deprecated`          | Both       | Skip operations/fields marked deprecated in the spec.                                    |

### Naming

| Flag                  | Default | Description                                                                                                                                                |
| --------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--verb-map: record`  | `{}`    | Override the action verb in command names. The key is the original verb (from the `operationId` or HTTP method), the value is the replacement. Example: `{retrieve: "fetch", list: "ls"}`. |

Default action-verb rewrites baked in: `retrieve` → `get`, `destroy` → `delete`, `partial_update` → `patch`.

### Runtime defaults baked into the module

These flags control the behaviour of the *generated* commands. They don't affect generation itself — they get embedded as defaults.

| Flag                            | Default     | Description                                                                                                                |
| ------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------- |
| `--token-env-var: string`       | `<NAME>_TOKEN` | The env-var the generated `build-auth` helper falls back to when `--token` is not passed. Derived from `--name` by default. |
| `--default-timeout: string`     | `"30min"`   | Default request timeout. Overridable per-call via `--max-time`.                                                            |
| `--default-headers: record`     | `{}`        | Headers merged into every request the client makes (e.g. `{X-Tenant-Id: "acme"}`).                                          |

### Module behaviour

| Flag                  | Default | Description                                                                                                                          |
| --------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `--body-threshold: int` | `0`     | When the body has more than this many fields, collapse them into a single `--body: record` flag. `0` = never collapse. Same flag also controls the analogous collapse of GraphQL `INPUT_OBJECT` args. |
| `--no-introspection`  | off     | Omit the auto-generated `commands` subcommand from the module.                                                                       |
| `--no-descriptions`   | off     | Omit the `# description` comments next to each parameter in the generated signatures. Keeps doc lines above each `def` regardless.   |

---

## Using a generated client

Generated clients are regular Nushell modules. Import them namespaced — never glob-imported — so the command names don't shadow Nushell builtins like `get`, `delete`, or `in`.

```nu
use docker-hub.nu

docker-hub namespaces-repositories-tags list "library" "nginx"
```

Each generated command is `<resource> <verb>`: object first, action second. This avoids the verb-first form (`get pet`, `delete user`) that collides with Nushell builtins.

### Built-in flags on every command

| Flag              | Short | Type       | Purpose                                                                                          |
| ----------------- | ----- | ---------- | ------------------------------------------------------------------------------------------------ |
| `--base-url`      | `-b`  | `string`   | Override the base URL. Tab-completes from spec servers + `--urls`.                               |
| `--token`         | `-t`  | `string`   | Auth token. Falls back to `$env.<NAME>_TOKEN`.                                                   |
| `--auth-scheme`   | `-a`  | `string`   | Override the auth scheme. Tab-completes from schemes the spec declared.                          |
| `--insecure`      | `-k`  | switch     | Skip TLS certificate verification.                                                               |
| `--max-time`      | `-m`  | `duration` | Per-request timeout. Defaults to `--default-timeout` from generation.                            |
| `--raw`           | `-r`  | switch     | Return the response body as text (no JSON parsing).                                              |
| `--allow-errors` | `-e`  | switch     | Return the full HTTP response record instead of erroring on non-2xx.                              |
| `--dry-run`       | `-n`  | switch     | Return the request that *would* be sent (method, url, headers, body, …) without executing it.    |

### Passing inputs

#### Path parameters

Required path params are **positional**:

```nu
docker-hub access-tokens get "f0c3a1ce-8cf4-4..."
docker-hub namespaces-repositories-tags get "library" "nginx" "latest"
```

#### Query, header, cookie parameters

All `--flag`. Enum-typed params get tab-completion. Boolean query params are switches (no `: bool` annotation, just `--flag`).

```nu
docker-hub namespaces-repositories-tags list "library" "nginx" --page-size 50
docker-hub namespaces-repositories-tags list "library" "nginx" --page-size 50 --page 2
```

When a query param's name collides with a Nushell keyword or with a built-in flag (e.g. `token`, `raw`), it's automatically prefixed with `qp-` / `hdr-` / `ck-`.

#### Request body

Bodies can be passed three ways, often interchangeably:

**Per-field flags** — when the spec exposes flat top-level body fields, each becomes its own flag (required scalars become positional). Whether you get this shape depends on the spec — many service-style APIs use deeply nested or freeform schemas and end up with the `--body` flag below instead.

**The `--body` flag** — when the body schema is freeform, has no enumerable top-level fields, or has been collapsed via `--body-threshold`, the whole payload goes in one flag:

```nu
docker-hub scim-20-users post --body {userName: "alice", emails: [{value: "alice@example.com", primary: true}], active: true}
```

**Pipeline input** — every command with a body accepts a piped record. Every body-bearing command has signature `]: any -> any` and starts with `let input = $in`; the piped value is merged deeply with whatever the flags produced:

```nu
{userName: "alice", emails: [{value: "alice@example.com", primary: true}], active: true} | docker-hub scim-20-users post
open new-user.json | docker-hub scim-20-users post
```

When flags and pipeline input conflict, **flags win** — the flag-built body is merged on top of the pipeline value.

#### `--body-threshold`

If you generated with `--body-threshold N` and a particular endpoint has more than N body fields, the per-field flags collapse into a single `--body: record`. Same mechanism applies to GraphQL `INPUT_OBJECT` args. Use this on huge specs where the per-endpoint flag count would otherwise blow past Nushell's signature limits.

#### Field-name collisions

Body fields whose sanitized name collides with a path param, with Nushell keywords, or with the built-in flags above get a `body-` prefix in the signature. The wire payload still uses the original spec name — only the flag name changes.

#### Multipart / file uploads

Body fields typed as `file` accept a path (string). The generator opens the file with `open --raw` and inserts the bytes into the multipart body before sending. For example, Box's file-content endpoint takes the file id as a path param and the file bytes as a body field:

```nu
box files-content content-by-file_id 12345 {name: "report.pdf", parent: {id: "0"}} ~/Documents/report.pdf
```

#### `DELETE` with a body

Nushell's `http delete` uses `--data` for the body rather than a positional argument. The generated `do-request` helper handles this — you don't see it, but it's why `delete` endpoints with request bodies work.

### Auth

Auth scheme and token are resolved at call time:

1. `--token` flag if set, otherwise `$env.<NAME>_TOKEN`.
2. `--auth-scheme` flag if set, otherwise the spec-default scheme (or `bearer` if the spec didn't declare one).
3. If the resolved scheme is `none` or no token is available, the request goes out unauthenticated.

Schemes the generator recognises and renders match-arms for: `jwt`, `bearer`, `basic`, `private-token`, `query-*` (token goes in the query string), `cookie-*` (token goes in a cookie), and `none`. Anything unrecognised falls back to `Authorization: Bearer <token>`.

The default scheme and the env-var name are baked into the generated module header:

```nu
# Auth: --token flag or $env.DOCKER_HUB_API_TOKEN
const BASE_URL = "https://hub.docker.com"
const DEFAULT_AUTH = "bearer"
```

### Tab completion

- `--base-url` completes from the spec's `servers` list plus anything passed via `--urls`.
- `--auth-scheme` completes from the schemes the spec declared (plus `none` if any operation is marked public).
- Any enum-typed parameter gets its own completer. Identical enum sets are deduplicated across the module — one completer per unique enum.

### `--dry-run`

Returns the request that would be sent, without sending it:

```nu
> docker-hub scim-20-users post --body {userName: "alice", active: true} --dry-run
╭────────────────┬────────────────────────────────────────────────────────╮
│ method         │ post                                                   │
│ url            │ https://hub.docker.com/v2/scim/2.0/Users               │
│ headers        │ {Authorization: "Bearer …", Accept: "application/json"}│
│ query_string   │                                                        │
│ content_type   │ application/json                                       │
│ timeout        │ 30min                                                  │
│ body           │ {userName: "alice", active: true}                      │
╰────────────────┴────────────────────────────────────────────────────────╯
```

### The `commands` subcommand

Every generated module exposes a `commands` introspection subcommand (unless generated with `--no-introspection`). It returns a table of every command with its parameters, types, optional/required-ness, descriptions, and return type — useful for scripting against the client itself.

```nu
docker-hub commands | where name =~ "access-tokens" | select name return_type
docker-hub commands | get params | first 5
```

---

## Command-name conventions

- Names are `<resource> <verb>` — object first, action second. Path segments form the resource (path params and version segments like `v1`/`v2` are stripped); the verb comes from `operationId` (last camelCase chunk) or the HTTP method.
- **Collection vs item collisions**: when two GET endpoints differ only by one path parameter (`GET /access-tokens` and `GET /access-tokens/{uuid}`), the collection variant is renamed `list` rather than suffixed.
- **Other collisions**: disambiguated by appending `-by-<path-param-name>` (e.g. `access-tokens get-by-uuid`). If that still leaves duplicates, a numeric suffix is appended (`-1`, `-2`).
- **`operationId` ending in `_<number>`** (a common pattern in machine-generated specs for de-duplication) triggers the `-by-<params>` rename pre-emptively.
- Reserved Nushell names (`get`, `delete`, `in`, `version`, `nothing`) are forbidden as standalone command/flag names and are sanitized accordingly.

---

## GraphQL specifics

### Generation

GraphQL clients are generated from one of:

- A live endpoint URL — the generator fetches `GET <url>`; if that fails it POSTs an introspection query directly. The POST cascade tries four progressively shallower queries (`full → compat → minimal → shallow`); the shallowest one stays within depth-7 query-complexity limits used by Shopify, locked-down GitHub, etc. If POST is rejected entirely, falls back to GET with `?query=...` for servers like older Apollo/Express-GraphQL.
- A pre-downloaded introspection JSON file.
- A GraphQL **SDL** text file (`.graphql`). Conversion requires Node.js with the `graphql` npm package.

If the server blocks introspection entirely, use a pre-downloaded schema file.

### Generated GraphQL commands

Every command is prefixed `query` or `mutation`:

```nu
countries query country "IT" --fields [name capital emoji]
countries query countries --filter {code: {eq: "IT"}} --fields [name capital]
```

Two extra flags on every GraphQL command:

| Flag                   | Description                                                                                                          |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `--fields: list<string>` | Fields to include in the selection set. Each entry may be a single field name or a nested chunk like `"title { romaji }"`. |
| `--query: string`      | Raw GraphQL query string — overrides the auto-built one entirely. The auto-generated `variables` record is still sent. |

#### `INPUT_OBJECT` arguments

By default the generator **expands** each `INPUT_OBJECT` arg into individual prefixed flags. For an arg `filter: CountryFilterInput { code, continent }` you get `--filter-code` and `--filter-continent` rather than a single `--filter: record`. `--body-threshold N` collapses back to the single-flag form when the total expanded field count would exceed N.

#### Default selection set

When `--fields` is not passed, the generator picks all scalar fields at depth 1 of the return type. Use `--fields` for nested types or to trim.

For commands that return a scalar (`String`, `[String]`, an enum, etc.) no selection set is generated at all — the field returns directly.

#### Variables

Required scalar args are positional. Other args become flags. Arg values are sent in the `variables` map alongside the auto-built query. Pipeline input (a record) is merged deeply into `variables`, same as the REST body behaviour.

---

## Acknowledgments

Tests are powered by [nutest](https://github.com/vyadh/nutest).
