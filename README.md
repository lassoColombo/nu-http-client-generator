# nu-http-client-generator

Reads an OpenAPI 3.x or Swagger 2.0 spec and generates a typed Nushell HTTP client module.

## Quick start

```nushell
use http-gen

# generate a client
http-gen ./petstore.yaml -o ./petstore.nu

# preview commands without generating
http-gen preview ./petstore.yaml

# generate with extra base URLs for tab-completion
http-gen ./spec.yaml -o ./client.nu -u [https://staging.example.com https://dev.example.com]
```

Then use the generated client:

```nushell
use petstore.nu

petstore pets list --limit 10
petstore pets create "Fido" --tag "dog"
petstore pets get 42 --allow-errors | to yaml
```

## What gets generated

Each generated client contains:

- `build-auth` -- resolves token from flag or env var, returns headers + query auth
- `serialize-qp` -- serializes query params respecting collection styles (csv, multi, pipes, ssv)
- `do-request` -- HTTP method dispatch with `--insecure`, `--raw`, `--max-time` support
- `base-url-completer` / `auth-scheme-completer` -- tab-completion for base URLs and auth schemes
- One `export def` per API operation

## Supported specs

| Format | Version | Detection |
|--------|---------|-----------|
| OpenAPI | 3.0.x | `openapi` field |
| Swagger | 2.0 | `swagger` field |

Auto-detected from the spec file. No flags needed.

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

- **Object verb** order: `pets list`, `users get` (not `list pets`, which conflicts with nushell builtins)
- **Required params** are positional, **optional params** are flags
- **Enum params** get tab-completion
- **Boolean query params** are switches (no `: bool` annotation)
- **File upload fields** accept a `path` and are read with `open -r`
- **Deprecated operations** are marked with `# DEPRECATED`
- **readOnly fields** are excluded from request body params
- **nullable required fields** become flags (user can omit them)

## Common flags on every command

| Flag | Short | Description |
|------|-------|-------------|
| `--base-url` | `-b` | Override base URL (with tab-completion) |
| `--token` | `-t` | Auth token |
| `--auth-scheme` | `-a` | Override auth scheme (with tab-completion) |
| `--insecure` | `-k` | Skip TLS verification |
| `--max-time` | `-m` | Request timeout (default: 30min) |
| `--raw` | `-r` | Return response as text |
| `--allow-errors` | `-e` | Return full response record instead of error |

## Generator flags

```
http-gen <file> [-o <output>] [--name <name>] [-u <urls>]
```

| Flag | Description |
|------|-------------|
| `-o, --output` | Output file path (default: `./{title}.nu`) |
| `--name` | Override module name (affects env var and filename) |
| `-u, --urls` | Additional base URLs for tab-completion |

## Architecture

- `mod.nu` -- entry point and main logic: spec loading, command model building (`build-commands`, `extract-body-fields`, `deduplicate-commands`, `process-spec`), code generation orchestration, and the two exported commands (`main`, `preview`). Spec-version agnostic; delegates version-specific logic to `spec.nu`, rendering to `render.nu`.
- `spec.nu` -- dispatch table of closures keyed by `{schema, version}`. Provides `detect`, `get-default-auth`, `resolve-ref`, `get-non-body-params`, `get-param-description`, and per-version helpers (`get-schemas`, `get-base-url`, `get-param-type`, `get-param-enum`, `get-param-collection-style`, `get-body-info`, `get-auth-schemes`). Adding a new spec version means adding an entry to the table.
- `render.nu` -- code generation: type mapping, flag name sanitization, completer collection/dedup, signature building, body code generation, helper rendering, full module rendering.

## Spec coverage

Handles: paths, operations, path/query/header/cookie parameters, JSON and multipart/form-data request bodies, `$ref` resolution (including PathItem-level), `allOf` schema composition, parameter serialization styles, `deprecated`/`nullable`/`readOnly` fields, `default`/`format` hints, per-operation security and server overrides.

Not handled: response headers, content negotiation, `discriminator`, server variables, `oneOf`/`anyOf` structural flattening (validation-only use is fine), `encoding` for multipart, `allowEmptyValue`, parameter `content` field. See `docs/missing-features.yaml` for details.
