# OpenAPI HTTP Client Generator — Requirements

This document defines the requirements for a complete, production-ready OpenAPI/Swagger HTTP client generator. The generator reads an OpenAPI 3.x or Swagger 2.0 specification and produces a typed HTTP client module with one command per operation.

---

## 1. Spec Acquisition & Parsing

### 1.1 Supported formats

- **OpenAPI 3.0.x** and **3.1.x** (JSON and YAML).
- **Swagger 2.0** (JSON and YAML).
- Auto-detect the spec version from the top-level `openapi` or `swagger` field.

### 1.2 Input sources

- **Local file path**: read from disk, detect JSON vs YAML by content (not extension alone).
- **URL**: fetch the spec via HTTP GET. Support authentication headers for private spec endpoints.
- Auto-detect: if the source string looks like a URL (starts with `http://` or `https://`), fetch it; otherwise treat it as a file path.

### 1.3 `$ref` resolution

- **Local references**: resolve `$ref: "#/components/schemas/Pet"` (OAS3) and `$ref: "#/definitions/Pet"` (Swagger 2) by navigating the JSON pointer within the same document.
- **Cycle detection**: track the ref resolution path and break cycles. A circular `$ref` must not cause infinite recursion — collapse to `any`/`record` at the cycle point.
- **External references** (`$ref: "other-file.yaml#/..."`) : optional. If not supported, produce a clear error when encountered rather than silently ignoring. Most real-world specs are self-contained after bundling, so this is a lower priority.
- **Deeply nested refs**: a `$ref` that points to a schema that itself contains `$ref`s must be resolved transitively.

### 1.4 Spec validation (lightweight)

- Verify required top-level fields exist (`openapi`/`swagger`, `info`, `paths`).
- Warn on missing `servers` (OAS3) or `host` (Swagger 2) — the spec is valid without them, but the generated client won't know the base URL.
- Do not attempt full JSON Schema validation of the spec — that's the job of linters like Spectral. Focus on structural correctness sufficient for generation.

---

## 2. Path & Operation Discovery

### 2.1 Operation enumeration

- Iterate every path in `paths` and every HTTP method (`get`, `post`, `put`, `patch`, `delete`, `head`, `options`, `trace`) defined on each path.
- Each `(path, method)` pair with an operation object becomes one generated command.

### 2.2 Path-level parameters

- Parameters defined at the path level (outside any method) apply to all operations on that path.
- Method-level parameters override path-level parameters with the same `name` + `in` combination.

### 2.3 `operationId`

- If present, use `operationId` as the basis for the command name (after sanitization).
- If absent, synthesize a name from the HTTP method and path segments (e.g. `GET /pets/{id}` → `pets get-by-id`).

### 2.4 Servers / Base URL

**OpenAPI 3.x:**
- Extract from the `servers` array. Use the first entry as the default.
- Support server variables (`{protocol}`, `{host}`) — substitute defaults or allow override.
- Path-level and operation-level `servers` override the global list.

**Swagger 2.0:**
- Construct from `host` + `basePath` + `schemes[0]` (default `https`).

- `--default-base-url` at generation time bakes in a URL. Individual commands accept `--base-url` to override at runtime.

---

## 3. Command Naming

### 3.1 Object-verb order

- Commands follow **resource verb** order (e.g. `pets list`, `pets get-by-id`, `users create`), not verb-resource order (which would collide with language builtins like `get`, `delete`, `list`).
- Extract the resource name from path segments. Strip path parameters and version prefixes (e.g. `/api/v1/users/{id}` → resource `users`).

### 3.2 Verb derivation

- Derive the action verb from the HTTP method and `operationId`:
  - `GET` (collection) → `list`
  - `GET` (single, has path param) → `get`
  - `POST` → `create`
  - `PUT` → `update` (full replace)
  - `PATCH` → `patch` (partial update)
  - `DELETE` → `delete` (but sanitized — see §3.4)
- `--verb-map` allows overriding these defaults (e.g. `{list: "ls", create: "new", delete: "rm"}`).

### 3.3 Name sanitization

- Convert `camelCase` and `snake_case` to `kebab-case`.
- Strip or replace characters invalid in the target language's identifiers (`$`, `[`, `(`, `\`, etc.).
- Collapse consecutive separators and trim leading/trailing hyphens.
- Handle path segments with special patterns: `$metadata`, `{+path}`, `*wildcard`, regex groups — strip or simplify.

### 3.4 Reserved word avoidance

- Maintain a list of reserved words in the target language (`get`, `delete`, `in`, `match`, `type`, `version`, `nothing`, etc.).
- When a generated name collides, apply a disambiguation strategy (e.g. contextual suffix from the path).

### 3.5 Deduplication

- When two operations produce the same command name:
  1. **First pass**: disambiguate by path parameter suffix (e.g. `get-by-id`, `get-by-name`, `get-by-slug`).
  2. **Second pass**: if still duplicate, append a numeric counter (`_2`, `_3`).
- Deduplication must be deterministic — same spec always produces the same names.

---

## 4. Parameter Mapping

### 4.1 Parameter locations (`in`)

**Path parameters** (`in: path`):
- Always required (the spec mandates this, but validate anyway).
- Map to positional parameters in the command signature, ordered by their appearance in the URL path template.
- Interpolate into the URL at runtime using the path template (e.g. `/pets/{petId}` → substitute `{petId}` with the positional value).

**Query parameters** (`in: query`):
- Map to named flags.
- Required query params → required flags. Optional → optional flags with defaults where the schema provides them.
- Boolean query params → switch flags (presence = `true`, absence = omit the parameter entirely).

**Header parameters** (`in: header`):
- Map to named flags, prefixed or grouped to distinguish from query params if needed.
- Common headers like `Accept`, `Content-Type`, `Authorization` should be handled internally, not exposed as user flags (they are transport-level concerns).

**Cookie parameters** (`in: cookie`):
- Map to named flags. Serialize into a `Cookie` header at runtime.
- Less common in practice — support is optional but the generator must not crash on them.

### 4.2 Parameter schema mapping

- Map `type` + `format` to the target language's type system:

| OpenAPI Type | Format | Target Type |
|---|---|---|
| `string` | — | `string` |
| `string` | `date` | `string` (or date type) |
| `string` | `date-time` | `string` (or datetime type) |
| `string` | `binary` | `binary` / file path |
| `string` | `uuid` | `string` |
| `integer` | `int32` | `int` |
| `integer` | `int64` | `int` |
| `number` | `float` | `float` |
| `number` | `double` | `float` |
| `boolean` | — | `bool` / switch |
| `array` | — | `list<T>` (recurse on `items`) |
| `object` | — | `record` |

- **Enums** (`enum` array on a string/integer schema): generate tab-completers / validators with the enum values.
- **`default`**: reflect as the flag's default value.

### 4.3 Collection-format serialization (query & header arrays)

**Swagger 2.0** (`collectionFormat`):
| Value | Serialization | Example |
|---|---|---|
| `csv` (default) | `a,b,c` | `?tags=a,b,c` |
| `ssv` | `a b c` | `?tags=a%20b%20c` |
| `tsv` | `a\tb\tc` | `?tags=a%09b%09c` |
| `pipes` | `a\|b\|c` | `?tags=a%7Cb%7Cc` |
| `multi` | repeated key | `?tags=a&tags=b&tags=c` |

**OpenAPI 3.x** (`style` + `explode`):
| Style | Explode | Location | Serialization |
|---|---|---|---|
| `form` (default for query) | `true` (default) | query | `?tags=a&tags=b` |
| `form` | `false` | query | `?tags=a,b,c` |
| `simple` (default for path) | `false` (default) | path | `a,b,c` |
| `simple` | `true` | path | `a,b,c` (same) |
| `label` | `false` | path | `.a,b,c` |
| `label` | `true` | path | `.a.b.c` |
| `matrix` | `false` | path | `;tags=a,b,c` |
| `matrix` | `true` | path | `;tags=a;tags=b` |
| `spaceDelimited` | — | query | `?tags=a%20b%20c` |
| `pipeDelimited` | — | query | `?tags=a%7Cb%7Cc` |
| `deepObject` | `true` | query | `?filter[status]=active&filter[type]=dog` |

- The generator must serialize array and object parameters according to their declared style. Default to `form`/`explode: true` for query, `simple`/`explode: false` for path and header.
- `deepObject` is important for filter-style APIs — many real-world APIs use it (e.g. Stripe).

### 4.4 `allowReserved`, `allowEmptyValue`

- `allowReserved: true` → do not percent-encode reserved characters (`:/?#[]@!$&'()*+,;=`) in query values.
- `allowEmptyValue: true` → allow `?param=` (empty string) and `?param` (absent value). Niche, but must not crash.

---

## 5. Request Body Handling

### 5.1 OpenAPI 3.x request bodies

- Defined in `requestBody.content` as a map of media types to schemas.
- **Priority**: prefer `application/json`, fall back to `application/x-www-form-urlencoded`, then `multipart/form-data`, then others.
- `required: true` on the request body → all body-derived flags are collectively required.

### 5.2 Swagger 2.0 body parameters

- A single parameter with `in: body` contains the body schema.
- Parameters with `in: formData` are form-encoded fields.
- `consumes` at the operation or spec level determines the content type.

### 5.3 Body field expansion

- For JSON request bodies with an object schema, expand top-level properties into individual flags (e.g. `{ name: string, age: integer }` → `--name: string`, `--age: int`).
- Respect `required` array on the schema — required properties → required flags.
- **Body threshold** (`--body-threshold N`): when the object has more than N properties, collapse all body fields into a single `--body: record` flag instead of expanding. `0` = never expand (always use `--body`).
- Nested objects within the body: collapse to `record` type (don't deep-expand — it produces unmanageable flag counts).

### 5.4 Form data

- `application/x-www-form-urlencoded`: serialize fields as URL-encoded key-value pairs.
- `multipart/form-data`: serialize as multipart, supporting file upload fields (`type: string, format: binary`).

### 5.5 Other content types

- `application/octet-stream`: accept a file path or binary input.
- `text/plain`, `application/xml`, etc.: accept a raw string.
- If multiple content types are supported, prefer JSON. Optionally allow a `--content-type` flag to override.

---

## 6. Response Handling

### 6.1 Status code interpretation

- `2xx` responses: success. Parse the response body according to the response's content type.
- `4xx` / `5xx` responses: raise an error with the status code and response body.
- The generator should set the expected output type based on the `200`/`201` response schema (for type annotations in languages that support it).

### 6.2 Response content type

- Parse `application/json` responses as structured data.
- Return `text/*` responses as strings.
- Return binary responses as raw bytes or save to file.
- The `Accept` header should be set based on what the operation declares in `responses.{code}.content`.

### 6.3 Response schema (for type annotations)

- If the target language supports output type annotations, derive them from the response schema.
- Array responses → `list<record>` or `table`.
- Object responses → `record`.
- Scalar responses → the appropriate primitive type.
- No response body (`204`) → null/nothing.

---

## 7. Authentication

### 7.1 Security scheme extraction

**OpenAPI 3.x** (`components.securitySchemes`):

| Type | Scheme | Generated Behavior |
|---|---|---|
| `http` | `bearer` | `Authorization: Bearer <token>` |
| `http` | `basic` | `Authorization: Basic <token>` |
| `apiKey` (header) | — | `<name>: <token>` (custom header) |
| `apiKey` (query) | — | `?<name>=<token>` (query param) |
| `apiKey` (cookie) | — | `Cookie: <name>=<token>` |
| `oauth2` | — | `Authorization: Bearer <token>` (same as bearer at the HTTP level) |
| `openIdConnect` | — | `Authorization: Bearer <token>` |

**Swagger 2.0** (`securityDefinitions`):

| Type | Generated Behavior |
|---|---|
| `basic` | `Authorization: Basic <token>` |
| `apiKey` (header/query) | same as OAS3 |
| `oauth2` | `Authorization: Bearer <token>` |

### 7.2 Token sourcing

- `--token` flag on every command.
- `--token-env-var` at generation time sets which environment variable to read from when `--token` is not provided (e.g. `$env.GITHUB_TOKEN`). Default: derive from spec title (e.g. `PETSTORE_TOKEN`).
- `--auth-scheme` flag to override the auth header format at runtime.

### 7.3 Per-operation security

- Operations can override the global `security` array. The generator should respect per-operation security requirements.
- If an operation has `security: []` (empty array), it requires no auth — don't add auth flags/headers.
- If multiple schemes are listed (OR logic), pick the first supported one. AND logic (multiple schemes in the same array entry) should combine headers.

### 7.4 Multiple auth schemes

- If the spec defines multiple security schemes, the generator should detect the primary one heuristically (first in global `security` array) or let the user specify with `--auth-scheme`.
- Don't generate a separate flag per scheme — a single `--token` + `--auth-scheme` pair handles all cases.

---

## 8. Filtering & Scoping

### 8.1 Tag filtering

- `--tags [pet store]` → only generate commands for operations tagged with at least one of the given tags.
- Operations without tags: include by default, exclude when `--tags` is specified (unless a `--include-untagged` flag is added).

### 8.2 Path prefix filtering

- `--prefixes ["/api/v1/users" "/api/v1/orders"]` → only operations whose path starts with one of the given prefixes.
- Useful for large specs where you only need a subset (e.g. generating a client for just the user-management portion of a 1000-endpoint API).

### 8.3 Method filtering

- `--methods [get post]` → only generate commands for the specified HTTP methods.
- Useful when you only need read-only (GET) commands.

### 8.4 Deprecation filtering

- `--exclude-deprecated` → skip operations marked `deprecated: true`.
- When not filtering, annotate deprecated commands with a warning in the description.

### 8.5 Combining filters

- All filters are AND-combined: an operation must match all active filters to be included.
- Within a single filter (e.g. multiple tags), the logic is OR (match any).

---

## 9. Naming & Customization

### 9.1 Module name

- `--name` overrides the module/namespace name.
- Default: derive from `info.title`, sanitized to a valid identifier.

### 9.2 Verb mapping

- `--verb-map {retrieve: "fetch", list: "ls", delete: "rm"}` — remap action verbs globally.

### 9.3 Description control

- `--no-descriptions` — suppress all inline description comments. Reduces generated file size for large specs.

### 9.4 Introspection command

- Generate a `commands` subcommand listing all available commands with their HTTP method, path, and description.
- `--no-introspection` suppresses this.

---

## 10. HTTP Transport Details

### 10.1 Method-specific body handling

- `GET`, `HEAD`, `DELETE` (typically), `OPTIONS`: no request body. Some APIs (Elasticsearch) use body with GET — this is non-standard and generally not supported.
- `DELETE` with body: some APIs send a body with DELETE. The generator should support this if the spec declares a `requestBody` on a DELETE operation.
- `POST`, `PUT`, `PATCH`: standard body methods. Body is a positional argument or assembled from flags.

### 10.2 URL construction

- Assemble from: base URL + path template + query parameters.
- Path parameter substitution: replace `{paramName}` in the path template with the URL-encoded value.
- Query parameter assembly: only include parameters that were actually provided (don't send `?param=null` for omitted optional params).

### 10.3 Headers

- `Content-Type`: set based on the request body media type.
- `Accept`: set based on the response content types declared in the spec. Default to `application/json`.
- `Authorization`: set based on the security scheme (§7).
- `--default-headers` at generation time bakes in static headers for every request.

### 10.4 Timeout

- `--default-timeout` at generation time (default: `30min` or similar).
- Per-command `--timeout` flag at runtime.

---

## 11. Edge Cases & Robustness

### 11.1 Large specs

- Handle specs with 1000+ operations (GitHub has ~1100, Kubernetes has ~1100) without excessive memory use or generation time.
- The generated output for large specs will be large — ensure the generator streams or buffers efficiently.

### 11.2 Polymorphism (`oneOf`, `anyOf`, `allOf`, `discriminator`)

**`allOf`** (composition / inheritance):
- Merge all sub-schemas into a single combined schema.
- Property name conflicts: last-writer-wins (later schemas override earlier ones), matching the JSON Schema merge semantics.
- Common pattern: `allOf: [{ $ref: "#/.../Base" }, { properties: { extra } }]` — merge the base schema with overrides.

**`oneOf`** / **`anyOf`** (variant types):
- For request bodies: collapse to `record` / `any`. These are inherently dynamic — the client can't enforce the constraint statically without a discriminator.
- If a `discriminator` is present, optionally generate guidance comments listing the valid types.
- For parameters: collapse to the broadest type.

**Swagger 2.0**: no `oneOf`/`anyOf` — only `allOf` and the non-standard `x-oneOf` extension (ignore extensions unless explicitly supported).

### 11.3 Nullable types

**OpenAPI 3.0**: `nullable: true` alongside `type`.
**OpenAPI 3.1**: `type: ["string", "null"]` (JSON Schema 2020-12 style).
**Swagger 2.0**: `x-nullable: true` (extension).

- Nullable parameters should be optional flags (nullable implies the absence of a value is acceptable).

### 11.4 `additionalProperties`

- `additionalProperties: true` (or absent, which defaults to true in JSON Schema) → the object can have arbitrary keys. Type as `record` / `any`.
- `additionalProperties: { type: string }` → a string-valued map. Type as `record<string>` if the language supports it.
- Do not expand arbitrary-key objects into flags — they must be a single `record` flag.

### 11.5 `readOnly` / `writeOnly`

- `readOnly: true` properties should be excluded from request body flags (they appear only in responses).
- `writeOnly: true` properties should be excluded from response type annotations (they appear only in requests).
- This prevents generating flags for server-computed fields like `id`, `createdAt`.

### 11.6 Free-form parameters

- `type: object` with no `properties` and `additionalProperties: true` → accept any record.
- `{}` (empty schema, OAS 3.1) → accept anything.

### 11.7 Path items with `$ref`

- OpenAPI 3.x allows `$ref` at the path item level (`paths: { "/pets": { "$ref": "..." } }`). Resolve like any other ref.

### 11.8 Webhooks (OAS 3.1)

- `webhooks` defines callback operations. These are not client-callable endpoints — skip them, or optionally generate documentation comments.

### 11.9 Links and Callbacks (OAS 3.x)

- `links` describe relationships between operations — informational, not needed for generation.
- `callbacks` define webhook-style endpoints the API will call back to — skip for client generation.

### 11.10 `x-` extensions

- Ignore vendor extensions gracefully. Do not crash on `x-custom-field` at any level of the spec.
- Optionally support well-known extensions:
  - `x-codegen-request-body-name` (common in specs converted from Swagger 2 → OAS3, names the body parameter).

---

## 12. Output Quality

### 12.1 Deterministic output

- Given the same spec and flags, the generator must produce byte-identical output on every run.
- Sort operations, parameters, completers, and helpers in a stable order (e.g. by path then method, alphabetical for schemas).

### 12.2 Source annotation

- Comment at the top of the generated file with: source spec path/URL, generator version, generation timestamp (optional — but if included, provide a way to suppress for reproducibility).

### 12.3 Readability

- Generated code should be clean, well-formatted, and idiomatic for the target language.
- Use consistent indentation and naming conventions.
- Humans will read, review, and version-control the output.

### 12.4 Minimal footprint

- Only generate completers for enums actually referenced by parameters.
- Only generate helper functions that are actually called.
- Don't emit dead code or unused imports.

---

## 13. Preview / Dry-Run Mode

- A `preview` subcommand that lists all commands that would be generated, with their HTTP method, path, parameter count, and tags — without writing any file.
- Supports the same filtering flags as the generation command.
- Useful for exploring large specs and validating filters before committing to generation.

---

## 14. Summary of Generator Flags

| Flag | Phase | Description |
|---|---|---|
| `--output`, `-o` | Generation | Output file path |
| `--name` | Generation | Override module/client name |
| `--default-base-url` | Generation | Bake in the API base URL |
| `--token-env-var` | Generation | Override the token env var name |
| `--default-timeout` | Generation | Default request timeout |
| `--default-headers` | Generation | Static headers for every request |
| `--body-threshold` | Generation | Collapse body fields above N properties |
| `--no-introspection` | Generation | Omit the `commands` subcommand |
| `--no-descriptions` | Generation | Omit description comments |
| `--tags` | Filtering | Only operations with matching tags |
| `--prefixes` | Filtering | Only paths matching given prefixes |
| `--methods` | Filtering | Only specified HTTP methods |
| `--exclude-deprecated` | Filtering | Skip deprecated operations |
| `--verb-map` | Naming | Override action verb mappings |

---

## Appendix A: Comparison with Existing Tools

| Capability | openapi-generator | swagger-codegen | Kiota | Orval | openapi-ts | Autorest |
|---|---|---|---|---|---|---|
| OAS 3.0 | Yes | Yes | Yes | Yes | Yes | Yes |
| OAS 3.1 | Partial | No | Yes | Yes | Yes | Partial |
| Swagger 2.0 | Yes | Yes | Yes (converts) | No | No | Yes |
| `$ref` cycle detection | Yes | Yes | Yes | Yes | Yes | Yes |
| `allOf` merging | Yes | Yes | Yes | Yes | Yes | Yes |
| `oneOf`/`anyOf` | Partial | No | Yes | Yes | Yes | Yes |
| Enum completers | Language-dependent | Language-dependent | Yes | Yes (TS) | Yes (TS) | Yes |
| Body field expansion | No (typed models) | No | No | No | No | No |
| Body threshold | No | No | No | No | No | No |
| `style`/`explode` serialization | Partial | No | Yes | Partial | Yes | Partial |
| `deepObject` support | Partial | No | Yes | Yes | Yes | No |
| `readOnly`/`writeOnly` | Yes | Partial | Yes | Yes | Yes | Yes |
| Tag filtering | Yes (by generation target) | Yes | No | Yes | No | No |
| Path prefix filtering | No | No | No | No | No | No |
| Method filtering | No | No | No | No | No | No |
| Preview mode | No (uses `--dry-run` for file ops) | No | No | No | No | No |
| Deterministic output | Mostly | No | Yes | Yes | Yes | Mostly |

The "body field expansion," "body threshold," "preview mode," and "prefix/method filtering" features are uncommon in existing tools — they are particularly valuable for CLI-oriented clients where each operation maps to a standalone command with flags rather than a method on a typed client object.

---

## Appendix B: Key Differences Between OAS 3.x and Swagger 2.0

The generator must abstract over these differences internally while presenting a uniform command model.

| Concern | Swagger 2.0 | OpenAPI 3.x |
|---|---|---|
| Version field | `swagger: "2.0"` | `openapi: "3.0.x"` / `"3.1.x"` |
| Base URL | `host` + `basePath` + `schemes` | `servers[].url` (with variables) |
| Request body | `parameters` with `in: body` or `in: formData` | `requestBody.content.{mediaType}.schema` |
| Schema location | `definitions` | `components.schemas` |
| Parameter location | `parameters` (top-level or in-operation) | `components.parameters` + inline |
| Auth definitions | `securityDefinitions` | `components.securitySchemes` |
| File upload | `type: file` in formData | `type: string, format: binary` in multipart |
| Nullable | `x-nullable` (extension) | `nullable: true` (3.0) / `type: [T, "null"]` (3.1) |
| Collection format | `collectionFormat` (csv, ssv, tsv, pipes, multi) | `style` + `explode` |
| Composition | `allOf` only | `allOf`, `oneOf`, `anyOf` + `discriminator` |
| Examples | `example` on schema | `example` / `examples` on media type, parameter, schema |
| Callbacks / Links | Not supported | `callbacks`, `links` |
| Cookie params | Not supported | `in: cookie` |
| `content` on params | Not supported | `parameter.content.{mediaType}.schema` as alternative to `parameter.schema` |

---

## Appendix C: Parameter Serialization Reference

A complete reference for how array and object parameters are serialized across all `style` + `explode` combinations, since this is the most error-prone area of OpenAPI client generation.

### Arrays

Given `color = ["blue", "black", "brown"]`:

| Style | Explode | `in` | Result |
|---|---|---|---|
| `simple` | `false` | path, header | `blue,black,brown` |
| `simple` | `true` | path, header | `blue,black,brown` |
| `label` | `false` | path | `.blue,black,brown` |
| `label` | `true` | path | `.blue.black.brown` |
| `matrix` | `false` | path | `;color=blue,black,brown` |
| `matrix` | `true` | path | `;color=blue;color=black;color=brown` |
| `form` | `false` | query, cookie | `color=blue,black,brown` |
| `form` | `true` | query, cookie | `color=blue&color=black&color=brown` |
| `spaceDelimited` | `false` | query | `color=blue%20black%20brown` |
| `pipeDelimited` | `false` | query | `color=blue%7Cblack%7Cbrown` |

### Objects

Given `color = { R: 100, G: 200, B: 150 }`:

| Style | Explode | `in` | Result |
|---|---|---|---|
| `simple` | `false` | path, header | `R,100,G,200,B,150` |
| `simple` | `true` | path, header | `R=100,G=200,B=150` |
| `form` | `false` | query | `color=R,100,G,200,B,150` |
| `form` | `true` | query | `R=100&G=200&B=150` |
| `deepObject` | `true` | query | `color[R]=100&color[G]=200&color[B]=150` |
