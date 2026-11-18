# spec.nu — The format oracle: everything that depends on the wire shape of an
# OpenAPI 3 document. Loading, `$ref` resolution, format detection, servers,
# parameter facts, request bodies, responses, security, type descriptors.
# A Swagger 2.0 document is converted to OpenAPI 3 first (`swagger2.nu`,
# wired by mod.nu), so this file reads one format only.

use ../log.nu

# ── Module-level constants ──────────────────────────────────────────

export const CT_JSON      = "application/json"
export const CT_MULTIPART = "multipart/form-data"
export const CT_FORM      = "application/x-www-form-urlencoded"
export const CT_PRIORITY  = [$CT_JSON $CT_MULTIPART $CT_FORM]

export const DEFAULT_HOST = "localhost"

export const RESPONSE_CODE_PRIORITY = ["200" "201" "202" "2XX" "default"]

# ── Version-independent helpers ─────────────────────────────────────

# Fetch a URL as raw text, decoding binary responses to UTF-8.
#
# Used by the spec loader to bypass `http get`'s auto-parser. The auto-parser
# would be ideal — one call, parsed record back — but it doesn't survive
# real-world specs served with content-types nushell doesn't recognize (e.g.
# `application/vnd.oai.openapi+json` from api.weather.gov). When the auto-
# parser doesn't know a media type, it hands back a bare string and downstream
# `from json` / `spec detect` panics. Fetching raw and parsing explicitly
# downstream sidesteps the issue.
export def fetch-text [url: string, headers: record = {}] {
  # `url parse | url join` percent-encodes path components, leaves already-
  # encoded sequences alone, and preserves query/fragment structure. Without
  # this, Nushell's `http get` rejects URLs with literal-space path segments
  # (e.g. `v2.0 preview/swagger.json` from the apis.guru registry).
  let safe_url = ($url | url parse | url join)
  let raw = (http get --raw --headers $headers $safe_url)
  if (($raw | describe) | str starts-with "binary") { $raw | decode utf-8 } else { $raw }
}

# Load an OpenAPI/Swagger spec from a local file or a URL.
# Returns {data: record, source: string}.
#
# The URL path goes through `fetch-text` (raw fetch + UTF-8 decode) instead of
# `http get`'s auto-parser — see that helper for the rationale.
export def load-spec [source: string, headers: record = {}] {
  if ($source | str starts-with "http://") or ($source | str starts-with "https://") {
    let body = (fetch-text $source $headers)
    {data: (parse-spec-text $body $source), source: $source}
  } else {
    # `open --raw` + parse-spec-text instead of `open`'s extension-driven
    # parser, so an extension-less spec (or `.txt`) still parses and a
    # non-spec file fails with the same clear error as the URL path.
    let expanded = ($source | path expand | into string)
    {data: (parse-spec-text (open --raw $expanded) $expanded), source: $expanded}
  }
}

# Parse a raw spec body, picking JSON or YAML based on the source URL's
# extension and falling back to "try JSON then YAML" when there's no hint.
def parse-spec-text [body: string, source: string]: nothing -> any {
  let parsed = if ($source | str ends-with ".json") {
    $body | from json
  } else if ($source | str ends-with ".yaml") or ($source | str ends-with ".yml") {
    $body | from yaml
  } else {
    try {
      $body | from json
    } catch {
      try {
        $body | from yaml
      } catch {
        # YAML accepts bare HTML/text as a scalar string, so a successful parse
        # here means we got real JSON or structured YAML — anything else is a
        # server returning an error page (HTML, plain text) with HTTP 200.
        error make --unspanned { msg: $"could not parse spec from ($source): not valid JSON or YAML" }
      }
    }
  }
  if not (($parsed | describe) | str starts-with "record") {
    let preview = ($body | str trim | str substring 0..120)
    error make --unspanned { msg: $"spec at ($source) did not parse to a record \(got ($parsed | describe)\); response begins: ($preview)" }
  }
  $parsed
}

# Drop OpenAPI/Swagger vendor extensions (`x-*` keys) from a record.
# Per the spec, vendor extensions are allowed at most object levels and
# tools that don't understand them must ignore them. Centralized here so
# iteration sites (paths, path-items, operations) all use the same rule.
export def drop-vendor-extensions []: any -> any {
  let obj = $in
  if not (($obj | describe) | str starts-with "record") { return $obj }
  let vendor_keys = ($obj | columns | where {|c| $c | str starts-with "x-" })
  if ($vendor_keys | is-empty) { $obj } else { $obj | reject ...$vendor_keys }
}

# Generic JSON Pointer traversal (RFC 6901) over a full document.
# Each segment indexes a record by string key or a list by integer index.
# `~1` decodes to `/` and `~0` decodes to `~`. Returns null on any miss.
def json-pointer-lookup [doc: any, ref_path: string]: nothing -> any {
  if not ($ref_path | str starts-with "#/") { return null }
  let stripped = ($ref_path | str substring 2..)
  if ($stripped | is-empty) { return $doc }
  let segments = ($stripped | split row '/' | each {|s|
    # A `$ref` is a URI fragment, so `%7B`/`%7D` (OBS writes
    # `#/paths/~1x~1%7Bname%7D/get/parameters/0`) are percent-decoded first
    # (RFC 6901 §6), then `~1` MUST be decoded before `~0` — otherwise `~01`
    # round-trips to `/` instead of `~1`.
    $s | url decode | str replace --all '~1' '/' | str replace --all '~0' '~'
  })
  mut current = $doc
  for seg in $segments {
    # A match pattern tells a record from a list; `describe` would render the
    # whole nested type, milliseconds on the root (the whole document) for
    # every lookup.
    match $current {
      {} => {
        if not ($seg in ($current | columns)) { return null }
        $current = ($current | get $seg)
      }
      [..$_] => {
        let idx = (try { $seg | into int } catch { -1 })
        if $idx < 0 or $idx >= ($current | length) { return null }
        $current = ($current | get $idx)
      }
      _ => { return null }
    }
  }
  $current
}

# Where a `$ref` points in the spec document. JSON Pointer refs
# (`#/components/schemas/Pet`, `#/definitions/Pet`, DigitalOcean's cross-path
# `#/paths/~1v2~1x/get/parameters/0`, a pointer into a schema such as
# `#/components/schemas/Pet/properties/status`) are all walked generically. A
# bare name (`Pet`, the pre-pointer Swagger style) is looked up in the schema
# and component tables. Returns null when nothing is there.
def ref-target [ref_path: string, doc: record]: nothing -> any {
  if ($ref_path | str starts-with "#") { return (json-pointer-lookup $doc $ref_path) }
  [
    $doc.components?.schemas? $doc.components?.parameters? $doc.components?.responses? $doc.components?.requestBodies?
    $doc.definitions? $doc.parameters? $doc.responses?
  ] | where {|t| ($t | describe) | str starts-with "record" } | each {|t| $t | get -o $ref_path } | get -o 0
}

# Resolve a `$ref` against the spec document. Follows chains (A → B → C) to
# the first non-ref value; the result's OWN nested $refs are left in place and
# callers re-resolve as they descend. Shallow on purpose: Nushell has no shared
# object references, so deep-inlining a heavily-shared schema graph (Confluence,
# GitLab, GitHub) blows up memory by the fan-out factor. A non-ref value, a
# dangling ref, or a cycle comes back unchanged.
export def resolve-ref [val: any, doc: record] {
  mut current = $val
  mut visited = []
  loop {
    # Not `describe`: it renders the whole nested type of a large value.
    match $current { {} => {}, _ => { return $current } }
    let ref_path = ($current | get -o "$ref")
    if (($ref_path | describe) != "string") { return $current }
    if ($ref_path in $visited) { return $current }
    let target = (ref-target $ref_path $doc)
    if ($target == null) { return $current }
    $visited = ($visited | append $ref_path)
    $current = $target
  }
}

# Clean enum values: strip a matching pair of outer ASCII quotes once.
# Some specs encode string-literal enum values with the literal quotes
# included (e.g. value `"\"Ashburn, VA\""` whose payload is the 13-character
# `"Ashburn, VA"`). Tab-completion would then offer the quoted form and the
# API would reject it. This strips exactly one matching outer pair; values
# like `"weird"middle"` (no matching outer pair) are left untouched. A `null`
# member (the OAS 3.0 way to spell a nullable enum) is dropped: it is not a
# value a completer can offer.
export def clean-enum-values [vals: list]: nothing -> list {
  $vals | each {|v|
    if (($v | describe) == "string") and ($v =~ "^\"[^\"]*\"$|^'[^']*'$") {
      $v | str substring 1..<(($v | str length) - 1)
    } else {
      $v
    }
  }
}

# Normalize OAS 3.1 type value: ["string", "null"] → "string", "string" → "string"
def normalize-type [type_val: any] {
  if ($type_val == null) { return null }
  if ($type_val | describe | str starts-with "list") {
    $type_val | where { $in != "null" } | get -o 0 | default "any"
  } else {
    $type_val
  }
}

# Check if a schema is nullable (OAS 3.0 nullable:true or OAS 3.1 type array containing "null")
def is-nullable [schema: record] {
  if ($schema.nullable? | default false) { return true }
  let t = ($schema.type? | default null)
  if ($t | describe | str starts-with "list") { "null" in $t } else { false }
}

# Detect the spec format: "openapi" or "swagger". The version field only has
# to be present; an unquoted YAML `swagger: 2.0` is a float, which
# `is-not-empty` accepts like a string.
export def detect [spec: record]: nothing -> string {
  if ($spec.openapi? | is-not-empty) {
    "openapi"
  } else if ($spec.swagger? | is-not-empty) {
    "swagger"
  } else {
    error make --unspanned { msg: "unknown spec format: missing 'openapi' or 'swagger' field" }
  }
}

# The schemes named by a security requirement list's first non-empty
# requirement object, resolved against the parsed auth schemes. Shared by the
# root-level `security` (`root-auth`) and the per-op override in model, so the
# two read the same thing. Returns
# {declared: list<string>, schemes: list<record>}: `declared` is the raw
# scheme names (empty when every requirement is `{}`, the list is empty, or
# nothing in it is a record); `schemes` is the resolved records, unknown names
# dropped, wire-identical duplicates collapsed. A list longer than one is the
# AND-form (every scheme must be sent together); the OR-form outer array only
# contributes its first alternative. An empty requirement next to a real one
# (`[{}, {key: []}]`) is optional auth: the key is the scheme, and the runtime
# sends nothing when no token is given.
export def requirement-schemes [security: any, auth_schemes: list]: nothing -> record {
  let first_req = ($security | default [] | where {|r| ($r | describe | str starts-with "record") and ($r | is-not-empty) } | get -o 0)
  let declared = if ($first_req == null) { [] } else { $first_req | columns }
  let schemes = ($declared | each {|n| $auth_schemes | where {|s| $s.spec_name == $n } | get -o 0 } | collapse-wire-identical)
  {declared: $declared, schemes: $schemes}
}

# Drop AND-set members that put the same credential in the same place.
# Google declares `{Oauth2: [...], Oauth2c: [...]}` — two oauth2 schemes that
# both become `Authorization: Bearer` — so two `--token-*` flags would write
# one header and the second would silently win. Keyed on the wire facts
# (location, header/param name, prefix), first occurrence kept.
def collapse-wire-identical []: list -> list {
  reduce --fold [] {|s, acc|
    let same = ($acc | any {|a| ($a.in == $s.in) and ($a.header_name == $s.header_name) and ($a.prefix == $s.prefix) })
    if $same { $acc } else { $acc | append $s }
  }
}

# What an operation without its own `security` sends: {default, required}.
# `default` is the scheme name — the first the root-level `security` names,
# else the first declared scheme, else "bearer". `required` is the global
# AND-form set: when the root `security` names >1 scheme in one requirement
# object (VTEX's `[{appKey: [], appToken: []}]`) every such op must send ALL of
# them, so it holds the resolved scheme records (length >1), else [].
export def root-auth [spec: record, auth_schemes: list]: nothing -> record {
  let named = (requirement-schemes $spec.security? $auth_schemes).schemes
  let default = if ($named | is-not-empty) {
    $named | first | get name
  } else if ($auth_schemes | is-not-empty) {
    $auth_schemes | first | get name
  } else {
    "bearer"
  }
  {default: $default, required: (if ($named | length) > 1 { $named } else { [] })}
}

# The response codes to consult, in order, when picking the success schema:
# the priority codes first, then every other 2xx the operation declares, in
# document order. `default` is the error envelope in practice (Azure ARM:
# `200` without a schema + `default: ErrorResponse`), so it is only a
# candidate when the operation declares NO 2xx response at all.
export def success-response-codes [responses: record]: nothing -> list<string> {
  let declared_2xx = ($responses | columns | where {|c| $c =~ '^2' })
  let priority = if ($declared_2xx | is-empty) { $RESPONSE_CODE_PRIORITY } else { $RESPONSE_CODE_PRIORITY | where {|c| $c != "default" } }
  $priority | append $declared_2xx | uniq
}

# Explicit success status codes (2xx/3xx numerics) declared by the operation.
# Ignores `default`, `2XX`-style wildcards, and documented error codes — none
# enumerate a concrete acceptable set, so those fall callers back to `< 400`.
export def get-success-codes [op: record]: nothing -> list<int> {
  $op.responses? | default {} | columns
    | where {|c| $c =~ '^[23][0-9][0-9]$' }
    | each {|c| $c | into int }
    | sort
}

# Walk an OpenAPI schema and produce a structured *type descriptor* (NOT a
# Nushell type string). Recursively builds records/lists. Depth-limited to
# avoid huge types. render's `nu-type-string` turns a descriptor into emitted
# Nushell type syntax — keeping all Nushell-syntax production in the render
# layer (see the layer contracts in CLAUDE.md). The walk needs the schema graph
# (refs, items, properties), which is spec's domain; the stringification needs
# Nushell's type grammar, which is render's — so the two are split here.
#
# Descriptor grammar:
#   scalar leaf : "any" | "string" | "int" | "float" | "bool" | "record" | "list"
#   list        : {list: <descriptor>}
#   record      : {record: [{name: string, type: <descriptor>}, ...]}
export def schema-to-type-descriptor [schema: any, doc: record, --depth: int = 0, --max-depth: int = 3, --visited: list<string> = []] {
  if ($schema == null) or (not (($schema | describe) | str starts-with "record")) { return "any" }

  # resolve $ref
  if ("$ref" in ($schema | columns)) {
    let ref_path = ($schema | get "$ref")
    if not (($ref_path | describe) == "string") { return "any" }
    if ($ref_path in $visited) { return "any" }  # circular ref
    let resolved = (ref-target $ref_path $doc)
    if ($resolved != null) {
      return (schema-to-type-descriptor $resolved $doc --depth $depth --max-depth $max_depth --visited ($visited | append $ref_path))
    }
    return "any"
  }

  # Fold allOf members in (an untyped schema with allOf is a record too;
  # `type: object` alongside allOf still inherits; an AWS-style
  # `allOf: [{$ref: Scalar}, {description}]` wrapper takes the member's type).
  let had_all_of = ($schema.allOf? | is-not-empty)
  let schema = (merge-all-of $schema $doc)
  let t = (normalize-type ($schema.type? | default null))
  let props = ($schema.properties? | default {})
  let has_props = ($props | is-not-empty)
  let has_items = ($schema.items? | is-not-empty)

  if $depth >= $max_depth {
    # past max depth: no recursion into fields — collapse to a bare leaf
    return (match $t {
      "array" => "list"
      "object" => "record"
      "string" => "string"
      "integer" => "int"
      "number" => "float"
      "boolean" => "bool"
      _ => {
        if $has_props or $had_all_of { "record" } else if $has_items { "list" } else { "any" }
      }
    })
  }

  let record_of = {||
    let fields = (build-td-fields $props $doc ($depth + 1) $max_depth $visited)
    if ($fields | is-empty) { "record" } else { {record: $fields} }
  }
  let list_of = {||
    {list: (schema-to-type-descriptor ($schema.items? | default {}) $doc --depth ($depth + 1) --max-depth $max_depth --visited $visited)}
  }
  match $t {
    "array" => (do $list_of)
    "object" => (do $record_of)
    "string" => "string"
    "integer" => "int"
    "number" => "float"
    "boolean" => "bool"
    _ => {
      # no explicit type — infer from structure
      if $has_props or $had_all_of { do $record_of } else if $has_items { do $list_of } else { "any" }
    }
  }
}

# Fold a schema's `allOf` members into the schema itself. Members are
# resolved (shallow) and merged in order: `properties` accumulate, `required`
# concatenates, and every other facet (`type`, `items`, `enum`, `format`,
# `default`, `nullable`, `description`) is taken from the first member that
# has it when the outer schema does not. This is what makes the AWS shape
# `{allOf: [{$ref: '#/…/Date'}, {description: …}]}` a `string` field with a
# description instead of an untyped `any`. Members' own allOf fold too, all
# the way down: `visited` carries the `$ref`s on the current path, and a
# member that refers back to one of them is skipped, so a self-referencing
# schema cannot loop and a long chain of allOf-only wrappers still reaches
# the leaf. A schema without allOf comes back unchanged.
export def merge-all-of [schema: any, doc: record, --visited: list<string> = []]: nothing -> any {
  if not (($schema | describe) | str starts-with "record") { return $schema }
  let members = ($schema.allOf? | default []
    | where {|sub| ($sub | describe) | str starts-with "record" }
    | each {|sub|
      let ref_path = ($sub | get -o "$ref")
      let is_ref = (($ref_path | describe) == "string")
      if $is_ref and ($ref_path in $visited) { return null }
      let seen = if $is_ref { $visited | append $ref_path } else { $visited }
      merge-all-of (resolve-ref $sub $doc) $doc --visited $seen
    }
    | where {|sub| ($sub | describe) | str starts-with "record" })
  if ($members | is-empty) { return $schema }
  let base = ($schema | reject allOf)
  $members | reduce --fold $base {|m, acc|
    let acc = ($acc | upsert properties (($acc.properties? | default {}) | merge ($m.properties? | default {})))
    let acc = ($acc | upsert required (($acc.required? | default []) | append ($m.required? | default []) | uniq))
    [type items enum format default nullable description] | reduce --fold $acc {|k, a|
      if (($a | get -o $k) == null) and (($m | get -o $k) != null) { $a | upsert $k ($m | get $k) } else { $a }
    }
  }
}

# A schema reduced to the one shape its value takes: `$ref` followed, allOf
# folded, and a nullable union (`anyOf`/`oneOf` of one schema and `{type:
# "null"}`, what pydantic and OAS 3.1 tools write for `Optional[T]`) replaced
# by that schema, marked `nullable` and with the outer keys (description,
# default) kept over the variant's. A schema with its own `type`, and a real
# union, come back unchanged. A non-record is {}.
export def fold-schema [schema: any, doc: record]: nothing -> record {
  let s = (merge-all-of (resolve-ref $schema $doc) $doc)
  match $s { {} => {}, _ => { return {} } }
  if ($s.type? != null) { return $s }
  let variants = ($s.anyOf? | default ($s.oneOf? | default []) | each {|v| merge-all-of (resolve-ref $v $doc) $doc })
  let is_null = {|v| ($v.type? == "null") or ($v.type? == ["null"]) }
  let values = ($variants | where {|v| not (do $is_null $v) })
  if (($values | length) != 1) or (($variants | length) != 2) { return $s }
  $values | first | merge ($s | reject -o anyOf oneOf) | upsert nullable true
}

# The value facts of a schema (see fold-schema): {type, items_type, enum,
# default, format, example, nullable, deprecated}. `type` is the OpenAPI type
# (OAS 3.1 `[T, "null"]` read as T), null when the schema has none or a
# malformed one; `items_type` is an array's item type, its items resolved the
# same way. The one reader of value facts for params and body fields alike.
export def schema-facts [schema: any, doc: record]: nothing -> record {
  let s = (fold-schema $schema $doc)
  let type_of = {|x|
    let t = ($x.type? | default null)
    if ($t == null) or (($t | describe) == "string") or ($t | describe | str starts-with "list") { normalize-type $t } else {
      log warn $"a schema's `type` is a ($t | describe | str replace --regex '<.*' ''), not a type name \(malformed spec\); read as untyped"
      null
    }
  }
  let t = (do $type_of $s)
  {
    type: $t
    items_type: (if $t == "array" { do $type_of (fold-schema ($s.items? | default {}) $doc) } else { null })
    enum: ($s.enum? | default [])
    default: $s.default?
    format: $s.format?
    example: $s.example?
    nullable: (is-nullable $s)
    deprecated: ($s.deprecated? | default false)
  }
}

# How an array (or object) value is serialized: "multi" repeats the key, and
# "csv"/"ssv"/"pipes"/"tsv" join the values with `,`/space/`|`/tab.
# `tabDelimited` is no OpenAPI 3 style: it is the converted Swagger 2
# `collectionFormat: tsv` (see swagger2.nu).
def array-style [style: string, explode: bool]: nothing -> string {
  if $explode { return "multi" }
  match $style {
    "spaceDelimited" => "ssv"
    "pipeDelimited" => "pipes"
    "tabDelimited" => "tsv"
    _ => "csv"
  }
}

# A form or multipart field's array serialization, from its media type's
# `encoding` (a Swagger 2 formData `collectionFormat`, converted): "multi",
# the default, sends the field once per value; a join style sends one value.
export def field-collection-style [encoding: record, name: string]: nothing -> string {
  let e = ($encoding | get -o $name | default {})
  let style = ($e.style? | default "form")
  array-style $style ($e.explode? | default ($style == "form"))
}

# Build a list of {name, type: descriptor} field entries from a properties map.
#
# Field names are kept RAW: render's `nu-type-string` sanitizes them to valid
# Nushell record-type identifiers when it stringifies the descriptor. No
# truncation here either — depth is already bounded by `max_depth`, and wide
# records produce long-but-valid signatures (terminals wrap; parsers don't fix
# bad syntax). Insertion order is preserved so the rendered field order is
# stable.
def build-td-fields [properties: record, doc: record, depth: int, max_depth: int, visited: list<string>] {
  $properties | items {|name, prop_schema|
    {name: $name, type: (schema-to-type-descriptor $prop_schema $doc --depth $depth --max-depth $max_depth --visited $visited)}
  }
}

# ── Security schemes ────────────────────────────────────────────────

# The security schemes as the wire facts the client needs:
# {spec_name, name, header_name, prefix, in}. `name` is the `--auth-scheme`
# value: the HTTP scheme (`bearer`, `basic`, prefix capitalized); for an
# apiKey `query-<param>` / `cookie-<name>`, the lowercased header name, or,
# for an `Authorization` header, the prefix the description names: `bearer`
# when it mentions Bearer (Swashbuckle's stock "JWT Authorization header using
# the Bearer scheme"), else `jwt` or `static` on those words, else `bearer`;
# `bearer` for oauth2 and openIdConnect. An unknown type is logged and treated
# as bearer.
export def auth-schemes [doc: record]: nothing -> list<record> {
  $doc.components?.securitySchemes? | default {} | items {|spec_name, d|
    let type = ($d.type? | default "unset")
    if $type == "http" {
      let s = ($d.scheme? | default "bearer" | str lowercase)
      {spec_name: $spec_name, name: $s, header_name: "Authorization", prefix: ($s | str capitalize), in: "header"}
    } else if $type == "apiKey" {
      let loc = ($d.in? | default "header")
      let hdr = ($d.name? | default "Authorization")
      if $loc == "query" {
        {spec_name: $spec_name, name: $"query-($hdr)", header_name: $hdr, prefix: "", in: "query"}
      } else if $loc == "cookie" {
        {spec_name: $spec_name, name: $"cookie-($hdr)", header_name: $hdr, prefix: "", in: "cookie"}
      } else if ($hdr | str lowercase) == "authorization" {
        let desc = ($d.description? | default "")
        let pfx = if ($desc =~ '(?i)bearer') { "Bearer" } else if ($desc =~ '(?i)jwt') { "JWT" } else if ($desc =~ '(?i)static') { "STATIC" } else { "Bearer" }
        {spec_name: $spec_name, name: ($pfx | str lowercase), header_name: "Authorization", prefix: $pfx, in: "header"}
      } else {
        {spec_name: $spec_name, name: ($hdr | str lowercase), header_name: $hdr, prefix: "", in: "header"}
      }
    } else {
      if $type not-in [oauth2 openIdConnect] {
        log warn $"unknown security scheme type '($type)' for '($spec_name)', defaulting to bearer"
      }
      {spec_name: $spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
    }
  }
}

# ── Servers ─────────────────────────────────────────────────────────

# Resolve a server-URL template against a record of OAS server `variables`,
# with optional per-call overrides. Backfills any `{var}` placeholder that
# isn't declared in `variables[]` with empty string — preserves the old
# lenient behavior (str-replace silently no-op'd unknown vars), since
# `format pattern` errors on missing keys.
def resolve-server-template [raw: string, vars: record, overrides: record = {}]: nothing -> string {
  if ($vars | is-empty) and ($overrides | is-empty) {
    return $raw
  }
  let defaults = ($vars | transpose name def | reduce -f {} {|v, acc|
    let val = ($overrides | get -o $v.name | default ($v.def.default? | default ""))
    $acc | upsert $v.name $val })
  let placeholders = ($raw | parse --regex '\{(?P<n>[A-Za-z0-9_]+)\}' | get n | uniq)
  let full = ($placeholders | reduce -f $defaults {|n, acc|
    if ($n in ($acc | columns)) { $acc } else { $acc | upsert $n "" }
  })
  $full | format pattern $raw
}

# Resolve a server object to an absolute URL: `{var}` placeholders take the
# per-call `overrides`, else the variable's `default`; a relative URL is
# anchored on localhost; a trailing slash is dropped so path joins stay single.
def resolve-server-url [server: record, overrides: record = {}] {
  let raw = ($server.url? | default $"http://($DEFAULT_HOST)")
  let substituted = (resolve-server-template $raw ($server.variables? | default {}) $overrides)
  let absolute = if ($substituted | str starts-with "/") { $"http://($DEFAULT_HOST)($substituted)" } else { $substituted }
  $absolute | str trim --right --char '/'
}

# The base URL: the first root server, else `http://localhost`.
export def base-url [doc: record]: nothing -> string {
  let servers = ($doc.servers? | default [])
  if ($servers | is-not-empty) {
    resolve-server-url ($servers | first)
  } else {
    $"http://($DEFAULT_HOST)"
  }
}

# Every server URL the spec mentions, for `--base-url` completion: each root
# server followed by one URL per enum value of each of its variables, then the
# path-level and operation-level overrides, in document order.
export def all-urls [doc: record]: nothing -> list<string> {
  let root = ($doc.servers? | default [] | each {|s|
    let variants = ($s.variables? | default {} | items {|name, def|
      $def.enum? | default [] | each {|ev| resolve-server-url $s {$name: $ev} }
    } | flatten)
    [(resolve-server-url $s)] ++ $variants
  } | flatten)
  let overrides = ($doc.paths? | default {} | drop-vendor-extensions | values | each {|item|
    let op_servers = ($item | items {|method, op|
      if ($method in [get post put patch delete head options]) and (($op | describe) | str starts-with "record") { $op.servers? | default [] } else { [] }
    } | flatten)
    ($item.servers? | default []) ++ $op_servers
  } | flatten | each {|s| resolve-server-url $s })
  $root ++ $overrides | uniq
}

# The operation's own server, else its path item's; null when neither
# overrides the root servers.
export def op-base-url [op: record, path_item: record] {
  let server = ($op.servers?.0? | default $path_item.servers?.0?)
  if ($server == null) { null } else { resolve-server-url $server }
}

# ── Parameters, bodies, responses ───────────────────────────────────

# A parameter's value facts: its schema's (`schema-facts`), an untyped one
# read as `string`, plus how the value is serialized. A `content`-typed param
# (OAS 3 §4.8.12.5) is one serialized value whose schema says nothing about
# the wire, so it reads as an empty schema: a scalar `string`.
# `default`/`format`/`example` fall back to the param itself, where some specs
# put them.
export def param-facts [param: record, doc: record]: nothing -> record {
  let facts = (schema-facts (if ($param.content? | is-not-empty) { {} } else { $param.schema? | default {} }) $doc)
  let t = ($facts.type | default "string")
  let style = ($param.style? | default "form")
  {
    type: $t
    # `list<string>` / `list<int>` in the signature instead of bare `list`;
    # null when the items have no usable primitive type.
    items_type: $facts.items_type
    enum: $facts.enum
    # For an object value the emitted serializer reads "multi" as exploded
    # `k=v` pairs and "csv" as `name=k,v,k,v` (OAS 3 §4.8.12.4).
    collection_style: (if $style == "deepObject" { "deepObject" } else if $t not-in ["array" "object"] { "scalar" } else {
      array-style $style ($param.explode? | default ($style == "form"))
    })
    default: ($facts.default | default $param.default?)
    format: ($facts.format | default $param.format?)
    example: ($facts.example | default ($param.example? | default ($param | get -o "x-example")))
    nullable: $facts.nullable
  }
}

# The request body: {has_body, body_schema, content_type, encoding}. Prefers a
# media type the client can encode; with none declared (text/plain, text/xml,
# application/vnd.X+json, …) the first one and its schema, so model can still
# derive a typed `--body` flag. `encoding` is the media type's per-field
# encoding (see `field-collection-style`).
export def body-info [op: record, doc: record]: nothing -> record {
  let request_body = $op.requestBody?
  if ($request_body | is-empty) {
    return {has_body: false, body_schema: {}, content_type: null, encoding: {}}
  }
  let content = ((resolve-ref $request_body $doc).content? | default {})
  let preferred = ($CT_PRIORITY | where {|ct| $content | get -o $ct | is-not-empty } | get -o 0)
  let declared = ($content | columns | get -o 0 | default $CT_JSON)
  # An empty media-type key (spoonacular writes `content: {"": {schema}}`) or
  # a bare `*/*` is no content type a request can carry: fall back to JSON.
  let ct = ($preferred | default (if ($declared | is-empty) or ($declared == "*/*") { $CT_JSON } else { $declared }))
  # The schema must come from the media type the client will send, not the
  # first one declared: `application/xml` listed before `application/json`
  # would otherwise expose the XML schema's fields on a JSON request.
  let media = ($content | get -o $ct | default ($content | get -o $declared | default {}))
  let s = ($media | get -o schema)
  let schema = if ($s | is-not-empty) { resolve-ref $s $doc } else { {} }
  let encoding = ($media | get -o encoding)
  {has_body: true, body_schema: $schema, content_type: $ct, encoding: (if ($encoding | describe | str starts-with "record") { $encoding } else { {} })}
}

# The media types the success responses declare (the `--accept` values),
# JSON when none does. A response may be a `$ref` into
# `#/components/responses` (apideck, chompthis do this for every operation),
# so each one is resolved before its `content` is read.
export def response-content-types [op: record, doc: record]: nothing -> list<string> {
  let responses = ($op.responses? | default {})
  $responses | transpose code resp | where {|r|
    ($r.code | str starts-with "2") or ($r.code == "default") or ($r.code =~ '^[12][xX]{2}$')
  } | each {|r|
    (resolve-ref $r.resp $doc).content? | default {} | columns
  } | flatten | uniq | if ($in | is-empty) { [$CT_JSON] } else { $in }
}

# The success responses' schemas (unresolved — model resolves and walks
# them), best candidate first (see `success-response-codes`); responses
# without a schema are skipped. The first entry is the return type; the
# others still contribute a discriminator.
export def response-schemas [op: record, doc: record]: nothing -> list {
  let responses = ($op.responses? | default {})
  success-response-codes $responses | each {|code|
    let resp = (resolve-ref ($responses | get -o $code) $doc)
    if ($resp | is-empty) { return null }
    let content = ($resp.content? | default {})
    # Prefer application/json's schema; if this response has no JSON media
    # (e.g. text/plain, application/xml, a vendor +json variant), fall back
    # to the first media type that declares a schema. Without this, a
    # non-JSON scalar response (`text/plain` `{type: string}`) derives `any`
    # and loses the typed `oneof<…>` output annotation.
    let json_schema = ($content | get -o "application/json" | default {} | get -o schema)
    if ($json_schema | is-not-empty) {
      $json_schema
    } else {
      $content | values | each {|m| $m | get -o schema } | get -o 0
    }
  }
}

# ── Descriptions ────────────────────────────────────────────────────


# Normalize spec-supplied description text for the terminal `help` medium.
# Strips HTML tags, decodes common entities, and collapses whitespace runs
# (newlines/tabs/multi-space) into single spaces. Markdown is left alone —
# users who pipe `help` into a markdown-aware tool keep the formatting.
#
# Without this, raw spec descriptions leak HTML (`<p>`, `<code>`, `<a href>`)
# and multi-paragraph prose into single-line flag-comment slots, producing
# unreadable help. Applied centrally by `build-description` so every call
# site benefits without per-site changes.
export def normalize-description [text: string]: nothing -> string {
  if ($text | is-empty) { return "" }
  $text
  # Anchor-tag handling: keep both the visible text and the URL.
  | str replace --all --regex '(?s)<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>' '${2} (${1})'
  # Strip remaining HTML tags (block, inline, void, comments) but keep contents.
  | str replace --all --regex '(?s)<!--.*?-->' ''
  | str replace --all --regex '<[/!?][a-zA-Z][^>]*>' ''
  | str replace --all --regex '<[a-zA-Z][a-zA-Z0-9]*(\s[^>]*)?/?>' ''
  # Common HTML entities.
  | str replace --all '&lt;' '<'
  | str replace --all '&gt;' '>'
  | str replace --all '&quot;' '"'
  | str replace --all '&#39;' "'"
  | str replace --all '&apos;' "'"
  | str replace --all '&nbsp;' ' '
  | str replace --all '&amp;' '&'
  # Collapse whitespace runs (newlines, tabs, repeated spaces).
  | str replace --all --regex '\s+' ' '
  | str trim
}

# Merge a base description with a list of nullable metadata annotations.
# `desc_base` is normalized for terminal display via `normalize-description`;
# extras come from the generator itself (DEPRECATED, format: X, ...) and pass
# through unchanged.
export def build-description [desc_base: string, extras: list] {
  let normalized = (normalize-description $desc_base)
  let extra = $extras | compact | str join ", "
  if ($extra | is-not-empty) and ($normalized | is-not-empty) {
    $"($normalized) \(($extra)\)"
  } else if ($extra | is-not-empty) {
    $extra
  } else {
    $normalized
  }
}
