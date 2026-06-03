# GraphQL HTTP Client Generator — Requirements

This document defines the requirements for a complete, production-ready GraphQL HTTP client generator. The generator reads a GraphQL schema (via introspection or SDL) and produces a typed HTTP client module with one command per query/mutation field.

---

## 1. Schema Acquisition

### 1.1 Introspection from a live endpoint

- **POST-based introspection**: send the standard introspection query (`__schema { types, directives, ... }`) via `POST` to any GraphQL endpoint.
- **Sufficient `ofType` depth**: the introspection query must recurse `ofType` at least 7–9 levels deep (the `graphql-js` reference implementation uses 9). Shallow introspection silently truncates wrapped types (`[NonNull(List(NonNull(T)))]`), producing incorrect signatures.
- **Auth headers during introspection**: accept arbitrary headers (bearer tokens, API keys, cookies) so the generator can introspect authenticated endpoints.
- **GET fallback**: some CDN-fronted endpoints (e.g. Shopify Storefront) only accept GET with `?query=...`. The generator should try POST first, then fall back to GET with URL-encoded query.
- **Truncation detection**: if a type's `ofType` chain ends in `null` at an unexpected depth (i.e. we hit the recursion ceiling), warn the user that the schema may be incomplete.

### 1.2 Schema from file

- Accept pre-downloaded introspection JSON (`{ "data": { "__schema": ... } }` or the unwrapped `{ "__schema": ... }` form).
- Accept SDL files (`.graphql`, `.gql`) — parse the SDL and build the same internal type model.
- Auto-detect format by content inspection, not file extension alone.

### 1.3 Schema from URL (auto-detect)

- If the URL returns valid JSON with `__schema`, treat it as a pre-downloaded introspection result.
- If the URL returns SDL text, parse it.
- Otherwise, attempt a live introspection POST.
- If all strategies fail, produce a clear error explaining what was tried.

---

## 2. Type System Mapping

### 2.1 Scalar types

Map GraphQL scalars to the target language's type system:

| GraphQL Scalar | Typical Target Type |
|---|---|
| `String` | `string` |
| `Int` | `int` |
| `Float` | `float` / `number` |
| `Boolean` | `bool` (or switch flag) |
| `ID` | `string` |

- **Custom scalars** (e.g. `DateTime`, `JSON`, `BigInt`, `UUID`, `Upload`): map to `string` or `any` by default. Allow user-provided scalar-to-type mappings.
- Document unrecognized custom scalars in the generated output so users know what to expect.

### 2.2 Enum types

- Generate tab-completion / validation for every enum used as an argument.
- Enum values must preserve their exact GraphQL casing (typically `UPPER_SNAKE`), since the server expects verbatim values.
- If the target language has a concept of completers or validators, wire enums into it.

### 2.3 Wrapper types (`NON_NULL`, `LIST`)

- Unwrap `NON_NULL(LIST(NON_NULL(T)))` chains correctly to determine:
  - **Nullability** → whether the flag/argument is required or optional.
  - **List wrapping** → whether the value accepts a list.
  - **Inner type** → the base scalar, enum, input object, or object type.
- `NON_NULL` at the outermost position → required argument / positional parameter.
- `LIST` → the flag accepts a list value (`list<T>`).
- Nested combinations (e.g. `[String!]!`, `[[Int]]`) must all be handled.

### 2.4 Input Object types (`INPUT_OBJECT`)

- Expand input object fields into individual, prefixed flags (e.g. `UserInput { name, email }` → `--user-name`, `--user-email`).
- Support nested input objects: prefix-chain the field path (e.g. `--filter-status-eq`).
- **Body threshold**: when an input object has more than N fields, collapse it into a single `--<arg-name>: record` flag instead of expanding. This threshold must be configurable (e.g. `--body-threshold 8`).
- Respect `NON_NULL` on individual input fields — mark expanded flags as required/optional accordingly.
- Recursive input types (e.g. `FilterInput { and: [FilterInput] }`) must be detected and handled without infinite loops. Collapse recursive fields to `record` or `any`.

### 2.5 Object types (output)

- Object types are not used for argument generation, but drive the default field selection (see §5).

### 2.6 Interface and Union types

- For output selection: document that interfaces/unions require explicit `--fields` with inline fragments (`... on ConcreteType { field }`).
- For arguments: these types don't appear as inputs in standard GraphQL, but the generator should not crash if they appear in unusual positions.

---

## 3. Command Generation

### 3.1 Scope

- Generate one command per **root field** in the `Query` and `Mutation` types.
- Optionally generate commands for `Subscription` fields (with a clear caveat that subscriptions use WebSocket, not HTTP POST — the generated command could send the subscription query over HTTP for APIs that support it, or be omitted entirely).

### 3.2 Command naming

- **Prefix by operation type**: `query <field-name>`, `mutation <field-name>` — this disambiguates fields that exist on both Query and Mutation, and makes the operation type explicit.
- **Name sanitization**: convert `camelCase` field names to `kebab-case` (e.g. `createUser` → `create-user`). Strip or replace characters invalid in the target language's command names.
- **Deduplication**: if two fields produce the same kebab-case name (unlikely but possible across Query/Mutation), disambiguate with a suffix.

### 3.3 Arguments → Flags / Positional parameters

- **Required scalar arguments** (`NON_NULL` without a `defaultValue`) → positional parameters, in the order they appear in the schema.
- **Optional scalar arguments** → named flags with defaults where the schema provides them.
- **Enum arguments** → flags with tab-completion wired to the enum's values.
- **List arguments** → flags typed as `list<T>`.
- **Input object arguments** → expanded into prefixed flags (see §2.4), or collapsed to a single record flag if over threshold.
- **Boolean arguments** → switch flags (no explicit `true`/`false` needed).
- **Arguments with `defaultValue`** → reflect the default in the flag definition, even if the argument is `NON_NULL` (a non-null arg with a default is effectively optional at the call site because the server applies the default).
- **Deprecation**: if an argument is deprecated (`isDeprecated: true`), either omit it (with `--exclude-deprecated`) or annotate it in the flag description.

### 3.4 Descriptions

- Each command should include the field's `description` from the schema as a doc comment / help text.
- Each flag should include the argument's `description`.
- A `--no-descriptions` flag should suppress all descriptions for smaller output.

---

## 4. Query Construction

### 4.1 Building the GraphQL query string

The generated command must construct a valid GraphQL document at runtime:

```graphql
query ($var1: Type1!, $var2: Type2) {
  fieldName(arg1: $var1, arg2: $var2) {
    ...selectionSet
  }
}
```

- Use **variables** for all arguments (never interpolate values into the query string — this prevents injection and handles complex types correctly).
- The variable definitions in the query must include the correct GraphQL type signature, including `!` for non-null and `[T]` for lists.
- For mutations, use `mutation` as the operation keyword.

### 4.2 Variable serialization

- Variables are sent in the `variables` JSON object alongside the `query` string.
- Scalar values: serialize directly.
- Enum values: serialize as plain strings (not quoted within the JSON string).
- Input objects: serialize as nested JSON objects matching the GraphQL input structure.
- Lists: serialize as JSON arrays.
- When flags are expanded from an input object, the generated code must reassemble them into the correct nested structure for the `variables` payload.

### 4.3 Raw query override

- Provide a `--query` flag that accepts a raw GraphQL query string, bypassing the auto-constructed query entirely. This is the escape hatch for queries that need inline fragments, aliases, directives, or anything the generator doesn't model.
- When `--query` is used, variables from flags should still be passed in `variables` if provided.

---

## 5. Field Selection (Selection Sets)

### 5.1 Default selection

- If the user doesn't specify `--fields`, automatically select all **scalar and enum fields at depth 1** of the return type.
- Do NOT auto-select nested object fields (this would cause unbounded recursion on deep/cyclic schemas).
- For list return types, apply the same rule to the list's element type.
- For scalar return types (`String`, `Int`, etc.) and list-of-scalar, omit the selection set entirely (GraphQL requires no selection set for leaf types).

### 5.2 User-specified fields (`--fields`)

- Accept a list of field names: `--fields [id name email]`.
- Support nested selection via string syntax: `--fields [id "title { romaji english }" "genres"]`.
- The generator should merge user-specified fields into a syntactically valid selection set.

### 5.3 Fragment and inline fragment support

- Not required in auto-generated selection, but `--query` (§4.3) must allow users to write fragments manually.
- If the return type is an interface or union, the default selection should either:
  - Select only fields defined on the interface itself (safe but limited), or
  - Warn the user that `--fields` with inline fragments is needed.

---

## 6. HTTP Transport

### 6.1 Request construction

- **Method**: `POST` (the universal default for GraphQL over HTTP).
- **Content-Type**: `application/json`.
- **Body**: `{ "query": "...", "variables": {...}, "operationName": "..." }`.
- **Endpoint URL**: configurable via `--base-url` flag on each command, or baked in at generation time with `--default-base-url`.

### 6.2 Authentication

- **Token-based auth**: `--token` flag and/or environment variable (configurable name via `--token-env-var`).
- **Auth scheme selection**: `--auth-scheme` flag to control the `Authorization` header format:
  - `bearer` → `Authorization: Bearer <token>` (default for most GraphQL APIs).
  - `basic` → `Authorization: Basic <token>`.
  - Custom header name (e.g. `X-API-Key`) for APIs that use non-standard auth.
- **Static headers**: `--default-headers` to bake in headers at generation time (e.g. `{X-Hasura-Admin-Secret: "..."}` for Hasura).

### 6.3 Timeout

- Configurable per-request `--timeout` flag.
- Default timeout configurable at generation time (`--default-timeout`).

### 6.4 Response handling

- Parse the JSON response and extract `data.<fieldName>`.
- If `errors` is present in the response:
  - If `data` is also present (partial success): return the data but surface errors as warnings.
  - If `data` is null/absent: raise an error with the first error message.
- Preserve the response structure — don't silently drop fields.

---

## 7. Filtering & Scoping

### 7.1 Prefix filtering

- `--prefixes [media user]` → only generate commands for root fields whose names start with the given prefixes (e.g. `mediaList`, `mediaSearch`, `userById`).

### 7.2 Deprecation filtering

- `--exclude-deprecated` → skip fields marked `isDeprecated: true` in the schema.
- When not filtering, deprecated fields should be annotated (description or comment).

### 7.3 Operation type filtering

- Optionally allow generating only queries, only mutations, or both (default: both).

---

## 8. Naming & Customization

### 8.1 Module / client name

- `--name` flag to override the generated module name (default: derived from the schema or file name).

### 8.2 Verb mapping

- `--verb-map` to rename operation verbs (e.g. `{create: "new", delete: "rm", list: "ls"}`).
- Applied after the camelCase → kebab-case conversion.

### 8.3 Base URL

- `--default-base-url` bakes the endpoint URL into the generated code so users don't need to pass it on every call.
- Individual commands should still accept `--base-url` to override at runtime.

---

## 9. Introspection / Self-Documentation

### 9.1 `commands` subcommand

- Generate a `commands` subcommand that lists all available commands with their operation type, argument count, and description.
- Allow suppressing this with `--no-introspection`.

### 9.2 Help text

- Each generated command should include help text derived from the schema description.
- Include argument descriptions, types, and defaults in flag help.

---

## 10. Edge Cases & Robustness

### 10.1 Large schemas

- Handle schemas with 1000+ types and 100+ root fields without crashing or producing excessively slow output.
- Parallel processing of independent commands where the target language supports it.

### 10.2 Circular references

- Detect cycles in type references (`Type A → field of Type B → field of Type A`).
- For output types: limit default selection depth (§5.1 already handles this).
- For input types: detect and collapse recursive input objects to `record`/`any`.

### 10.3 Reserved words

- The target language may reserve certain words (`get`, `delete`, `type`, `in`, `match`, etc.). The generator must sanitize command and flag names to avoid collisions.

### 10.4 Empty or unusual schemas

- Schema with no `Query` type → error with clear message.
- Schema with `Query` but no fields → warn and produce an empty client.
- Schema with only `Mutation` (no `Query`) → generate mutation commands only.
- Fields with zero arguments → generate commands with no positional params or flags (just `--fields`).

### 10.5 Custom directives

- The generator does not need to interpret arbitrary custom directives, but must not crash on schemas that contain them.
- `@deprecated(reason: "...")` is the one directive that should be handled (see §7.2).

### 10.6 Schema extensions and SDL stitching

- If reading SDL, handle `extend type Query { ... }` by merging extensions into the base type.
- Multiple SDL files: accept a directory or glob and merge them.

---

## 11. Output Quality

### 11.1 Source annotation

- Include a comment at the top of the generated file indicating the source schema, generation timestamp, and generator version.

### 11.2 Deterministic output

- Given the same schema and flags, the generator must produce byte-identical output. This is critical for diffing, code review, and golden-file testing.
- Sort types, commands, and completers in a stable order (alphabetical by name is the simplest).

### 11.3 Readability

- Generated code should be formatted and readable — it will be checked into version control and read by humans.
- Use consistent indentation, spacing, and naming conventions native to the target language.

### 11.4 Minimal footprint

- Don't generate dead code (unused helpers, unreachable branches).
- Don't generate completers for enums that no command references.
- Don't generate type mappings that nothing uses.

---

## 12. Preview / Dry-Run Mode

- A `preview` subcommand that shows the list of commands that would be generated, with their arguments and types, without writing any file.
- Useful for exploring unfamiliar APIs and validating filter flags before committing to generation.

---

## 13. Summary of Generator Flags

| Flag | Phase | Description |
|---|---|---|
| `--output`, `-o` | Generation | Output file path |
| `--name` | Generation | Override module/client name |
| `--default-base-url` | Generation | Bake in the GraphQL endpoint URL |
| `--token-env-var` | Generation | Override the token env var name |
| `--default-timeout` | Generation | Default request timeout |
| `--default-headers` | Generation | Static headers baked into every request |
| `--body-threshold` | Generation | Collapse input objects above N fields |
| `--no-introspection` | Generation | Omit the `commands` self-doc subcommand |
| `--no-descriptions` | Generation | Omit description comments |
| `--prefixes` | Filtering | Only fields matching name prefixes |
| `--exclude-deprecated` | Filtering | Skip deprecated fields |
| `--verb-map` | Naming | Override verb mappings |

---

## Appendix A: Comparison with Existing Tools

For reference, here is how major GraphQL client generators approach these requirements:

| Capability | graphql-codegen | Apollo Codegen | Relay Compiler | genqlient | graphql-zeus |
|---|---|---|---|---|---|
| Introspection from URL | Yes | Yes | No (SDL only) | Yes | Yes |
| SDL input | Yes | Yes | Yes | Yes | Yes |
| Type-safe variables | Yes | Yes | Yes (strict) | Yes | Yes |
| Enum completers | Language-dependent | Yes (TS enums) | Yes (Flow enums) | Yes (Go consts) | Yes (TS) |
| Input object expansion | No (uses typed objects) | No | No | Partial | No |
| Default field selection | No (requires explicit) | No | No | No | Yes (deep) |
| Raw query escape hatch | Yes (write your own) | Yes | Yes (tagged templates) | Yes (.graphql files) | Yes |
| Body threshold collapse | No | No | No | No | No |
| Preview mode | No | No | No | No | No |
| Filtering by prefix | No | No | No | No | No |
| Exclude deprecated | Plugin-dependent | No | No | No | No |

The "input object expansion" and "body threshold" features, as well as "preview mode" and "prefix filtering," are uncommon in existing tools — they are particularly valuable for CLI-oriented clients where each command is a standalone invocation with flags rather than a programmatic API call.

---

## Appendix B: GraphQL Over HTTP Specification

The generator should conform to the [GraphQL over HTTP spec](https://graphql.github.io/graphql-over-http/) (currently a draft, widely adopted in practice):

- **POST requests**: `Content-Type: application/json`, body is `{"query": "...", "variables": {...}}`.
- **Accept header**: `application/graphql-response+json` (preferred) with fallback to `application/json`.
- **Status codes**: `200` for successful responses (even with `errors`), `400` for malformed requests.
- **GET requests** (optional): query and variables as URL-encoded query parameters. Only for queries (not mutations), and only when the URL length is manageable.
- **`operationName`**: required when the document contains multiple operations (not typical for generated clients, but supported via `--query`).
- **Batching**: not part of the spec but supported by some servers (Apollo, Hasura). Out of scope for initial implementation.
