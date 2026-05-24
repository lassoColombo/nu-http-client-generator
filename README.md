# http-gen

A Nushell module that reads an OpenAPI 3.x or Swagger 2.0 spec and generates a typed HTTP client module.

## Usage

```nushell
use http-gen

# Generate a client
http-gen ./spec.yaml -o ./client.nu

# Preview commands without generating
http-gen preview ./spec.yaml
```

Then use the generated client:

```nushell
use client.nu

# List resources
client resources list --token $token

# Create with body fields as parameters
client resources create "my-resource" --optional-field "value"

# Override base URL and auth scheme
client resources list --base-url "https://other.host" --auth-scheme "bearer" --token $token
```

## Features

- Auto-detects spec version (OpenAPI 3.x or Swagger 2.0)
- Generates typed parameters: path params as positionals, query params as flags
- Request body fields are individual parameters (required fields are positional, optional are flags)
- Enum values get tab-completion via generated completer functions
- Auth via `--token` flag or service-specific env var (e.g. `$env.{{ CLIENT }}_TOKEN`)
- Multiple auth schemes: `jwt`, `bearer`, `basic`, `static`, `private-token`
- `--insecure (-k)` flag for self-signed certificates
- Command naming follows `object verb` order to avoid shadowing nushell builtins

## Architecture

- `mod.nu` -- main logic: spec loading, command model building, code rendering. Spec-version agnostic.
- `spec.nu` -- dispatch table of version-specific helpers (schema extraction, param types, body detection, base URL). Adding a new spec version means adding an entry to the table.

## Options

```
http-gen <file> [-o <output>] [--name <name>]
```

| Flag | Description |
|------|-------------|
| `-o, --output` | Output file path (default: `./{title}.nu`) |
| `--name` | Override module name (affects env var and filename) |
