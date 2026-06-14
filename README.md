# nu-http-client-generator

Reads an API specification and generates a typed Nushell HTTP client module.

[![asciicast](https://asciinema.org/a/IQtLxd5nJoZSf0AW.svg)](https://asciinema.org/a/IQtLxd5nJoZSf0AW)

# Table of contents
- [nu-http-client-generator](#nu-http-client-generator)
  - [Supported specs](#supported-specs)
  - [Quick start](#quick-start)
  - [Installation](#installation)
  - [Subcommands](#subcommands)
  - [Generation flags](#generation-flags)
    - [Source & output](#source-&-output)
    - [Filtering](#filtering)
    - [Naming](#naming)
    - [Runtime defaults](#runtime-defaults)
    - [Module behaviour](#module-behaviour)
  - [Using a generated client](#using-a-generated-client)
    - [Passing inputs](#passing-inputs)
    - [Request bodies](#request-bodies)
    - [Auth](#auth)
    - [Tab completion and dry runs](#tab-completion-and-dry-runs)
    - [Introspecting the client](#introspecting-the-client)
  - [How command names get built](#how-command-names-get-built)
  - [GraphQL specifics](#graphql-specifics)
  - [Acknowledgments](#acknowledgments)


## Supported specs

| Format  | Versions               |
| ------- | ---------------------- |
| OpenAPI | 3.0.x, 3.1.x           |
| Swagger | 2.0                    |
| GraphQL | Introspection JSON, SDL  |

Specs can be loaded from a local file or fetched directly from a URL.

---

## Quick start

```nu
use nu-http-client-generator

# Generate from a file
nu-http-client-generator openapi ./petstore.yaml -o ./petstore.nu

# Generate from a URL
nu-http-client-generator openapi https://petstore3.swagger.io/api/v3/openapi.json -o ./petstore.nu

# Preview what would be generated (no file written)
nu-http-client-generator openapi preview ./petstore.yaml

# GraphQL - auto-introspects the endpoint
(nu-http-client-generator graphql https://countries.trevorblades.com/graphql
  -o ./countries.nu --default-base-url "https://countries.trevorblades.com/graphql")
```

Then use it:

```nu
use petstore.nu

petstore pet-find-by-status findPetsByStatus --status available | where status == "available"
petstore pet get 10
petstore store-inventory get --token $env.PETSTORE_TOKEN
```

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

### Runtime defaults

These flags control the behaviour of the *generated* commands. They don't affect generation itself - they get embedded as defaults.

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

A generated client is a regular Nushell module:
```nu
use petstore.nu
petstore pet get 10
```

Every command follows the same `<resource> <verb>` shape, object first and action second.   
Alongside the spec-derived flags, every command also ships with the same set of built-in flags:

| Flag              | Short | Type       | Purpose                                                                                          |
| ----------------- | ----- | ---------- | ------------------------------------------------------------------------------------------------ |
| `--base-url`      | `-b`  | `string`   | Override the base URL. Tab-completes from spec servers + `--urls`.                               |
| `--token`         | `-t`  | `string`   | Auth token. Falls back to `$env.<NAME>_TOKEN`.                                                   |
| `--auth-scheme`   | `-a`  | `string`   | Override the auth scheme. Tab-completes from schemes the spec declared.                          |
| `--insecure`      | `-k`  | switch     | Skip TLS certificate verification.                                                               |
| `--max-time`      | `-m`  | `duration` | Per-request timeout. Defaults to `--default-timeout` from generation.                            |
| `--raw`           | `-r`  | switch     | Return the response body as text (no JSON parsing).                                              |
| `--allow-errors`  | `-e`  | switch     | Return the full HTTP response record instead of erroring on non-2xx.                             |
| `--dry-run`       | `-n`  | switch     | Return the request that *would* be sent (method, url, headers, body, …) without executing it.    |
| `--accept`        |       | `string`   | Override the `Accept` header. Only present on operations whose spec declares more than one response content type; tab-completes from those types. |

### Passing inputs

Required path parameters are positional, in the order they appear in the path.   
Everything else - query strings, headers, cookies - becomes a `--flag`.   
Enum-typed params get tab-completion automatically, and boolean query params render as plain switches:
```nu
petstore pet get 10
petstore pet-find-by-status findPetsByStatus --status available
```

If a query, header, or cookie name happens to collide with a Nushell keyword or with one of the built-in flags above (`token`, `raw`, …), the generator prefixes the flag with `qp-`, `hdr-`, or `ck-` accordingly.

### Request bodies

Request bodies show up in one of two shapes, depending on the spec. When the body schema exposes flat top-level fields, each one becomes its own flag and required scalars become positional - the most ergonomic form, but only available when the schema is clean enough to enumerate. When the schema is freeform, deeply nested, or has been collapsed by `--body-threshold`, the entire payload goes through a single `--body: record` flag instead:

```nu
petstore user createUser --body {
  username: "alice"
  firstName: "Alice"
  email: "alice@example.com"
  password: "s3cret"
}
```

Either form also accepts pipeline input. In practice this means you can shape the bulk of the payload from a file or upstream pipe and then patch in last-moment overrides via flags:

```nu
open new-user.json | petstore user createUser --userStatus 1
```

A few edge cases bake in transparently. File-typed body fields accept a path: the generator opens it with `open --raw` and inlines the bytes into a multipart request - so a file upload command like `petstore pet-upload-image uploadFile 10 ~/photos/rex.jpg` will read the file from disk and attach it for you. And `DELETE` endpoints with a body work despite Nushell's `http delete` expecting `--data` rather than a positional argument.

If you generated with `--body-threshold N`, any endpoint with more than N body fields collapses its per-field flags into the single `--body: record` form.

### Auth

At call time the client resolves a token by checking `--token` first, then `$env.<NAME>_TOKEN`. You can customize the default token name at generation time by using the `--token-env-var` flag.
The scheme comes from `--auth-scheme` if set, otherwise the default the spec declared - or `bearer` if the spec didn't declare one. If the scheme resolves to `none` or no token turns up, the request goes out unauthenticated.

The generator knows about `jwt`, `bearer`, `basic`, `private-token`, `query-*` (token in the query string), `cookie-*` (token in a cookie), and `none`. Anything else falls back to `Authorization: Bearer <token>`. The defaults are baked into the module header so you can see them at a glance:

```nu
# Auth: --token flag or $env.PETSTORE_TOKEN
const BASE_URL = "https://petstore3.swagger.io/api/v3"
const DEFAULT_AUTH = "bearer"
```

### Tab completion and dry runs

`--base-url` completes from the spec's `servers` list plus anything you passed via `--urls` at generation time, and `--auth-scheme` completes from the schemes the spec declared (plus `none` if any operation was marked public). Enum-typed parameters each get their own completer, with identical enum sets deduplicated across the module - one completer per unique enum, not one per parameter.

`--dry-run` is useful when you want to see what a call would do without actually making it. It returns the full request record - method, URL, headers, query string, body, timeout - so you can sanity-check the shape before it hits production:

```nu
> petstore user createUser --body {username: "alice", email: "alice@example.com"} --dry-run
╭────────────────┬─────────────────────────────────────────────────────────╮
│ method         │ post                                                    │
│ url            │ https://petstore3.swagger.io/api/v3/user                │
│ headers        │ {Authorization: "Bearer …", Accept: "application/json"} │
│ query_string   │                                                         │
│ content_type   │ application/json                                        │
│ timeout        │ 30min                                                   │
│ body           │ {username: "alice", email: "alice@example.com"}         │
╰────────────────┴─────────────────────────────────────────────────────────╯
```

### Introspecting the client

Unless you generated with `--no-introspection`, the module exposes a `commands` subcommand that returns a table of every command, its parameters and their types, whether each is optional, the descriptions, and the return type. It's handy both for scripting against the client itself and for browsing what's available when you're new to a spec:

```nu
petstore commands | where name =~ "pet" | select name return_type
petstore commands | get params | first 5
```

---

## How command names get built

Names follow `<resource> <verb>`: the path segments form the resource - with path params and version chunks like `v1`/`v2` stripped - and the verb comes from the operation's `operationId` (its trailing camelCase chunk) or the HTTP method. So `GET /pet/{petId}` becomes `pet get`, and `POST /pet/{petId}/uploadImage` becomes `pet-upload-image uploadFile`.

Collisions get resolved in a few specific ways. The most common case is a collection-vs-item pair, where two GET endpoints differ only by a single path parameter (imagine a spec with both `GET /users` and `GET /users/{userId}`); in that case the collection variant is renamed `list` rather than suffixed. Any other collision is disambiguated by appending `-by-<path-param-name>` - you'd end up with `users get-by-userId` - and if even that leaves duplicates, a numeric suffix (`-1`, `-2`) is appended on top. An `operationId` ending in `_<number>` (a common pattern in machine-generated specs) triggers the `-by-<params>` rename pre-emptively so you don't end up with numeric suffixes everywhere. Reserved Nushell identifiers (`get`, `delete`, `in`, `version`, `nothing`) are forbidden as standalone names and get sanitized whenever they'd otherwise appear bare.

---

## GraphQL specifics

GraphQL clients can be generated from a live endpoint URL, a pre-downloaded introspection JSON file, or a GraphQL SDL text file (`.graphql` - conversion needs Node.js with the `graphql` npm package). When you point at a URL the generator tries `GET <url>` first, and if that doesn't yield introspection it POSTs an introspection query, falling through a cascade of progressively shallower variants (`full → compat → minimal → shallow`).

Generated commands look much like the REST ones, except every name is prefixed `query` or `mutation` and every command picks up two extra flags. `--fields` controls the selection set: each entry is either a bare field name or a nested chunk like `"title { romaji }"`. `--query` lets you bypass the auto-built query and supply your own raw GraphQL string instead; the auto-generated `variables` record is still sent, so you can mix a hand-written query with the flag-built variables when you need to:

```nu
countries query country "IT" --fields [name capital emoji]
countries query countries --filter {code: {eq: "IT"}} --fields [name capital]
```

`INPUT_OBJECT` arguments behave a lot like REST bodies. By default the generator expands each one into individual prefixed flags - an arg `filter: CountryFilterInput { code, continent }` becomes `--filter-code` and `--filter-continent` rather than a single `--filter: record` - and `--body-threshold N` collapses it back to the single-flag form when the expanded count would exceed N. Required scalar args are positional, the rest are flags, and a piped record gets merged deeply into the `variables` map the same way REST bodies do.

If you don't pass `--fields`, the generator picks every scalar field at depth 1 of the return type, so you get something useful out of the box and reach for `--fields` only when you need nested types or a tighter selection. Commands that return a bare scalar (`String`, `[String]`, an enum, …) skip the selection set entirely - the field just comes back directly.

---

## Acknowledgments

Tests are powered by [nutest](https://github.com/vyadh/nutest), an incredible testing framework for nushell.
