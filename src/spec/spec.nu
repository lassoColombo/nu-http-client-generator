# spec.nu — Dispatch table for OpenAPI/Swagger spec helpers.
# Version-specific logic is encapsulated in closures, looked up by schema type + version.
# Version-independent helpers are plain exported functions.

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
    let t = ($current | describe)
    if ($t | str starts-with "record") {
      if not ($seg in ($current | columns)) { return null }
      $current = ($current | get $seg)
    } else if ($t | str starts-with "list") or ($t | str starts-with "table") {
      let idx = (try { $seg | into int } catch { -1 })
      if $idx < 0 or $idx >= ($current | length) { return null }
      $current = ($current | get $idx)
    } else {
      return null
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
  ] | where {|t| ($t | describe) | str starts-with "record" } | each {|t| $t | get -o $ref_path } | compact | get -o 0
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
    if not (($current | describe) | str starts-with "record") { return $current }
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
# like `"weird"middle"` (no matching outer pair) are left untouched.
export def clean-enum-values [vals: list]: nothing -> list {
  # `each` drops nulls; wrap each item in a record so nulls survive, then unwrap.
  $vals | each {|v| {v: $v} } | each {|w|
    let v = $w.v
    if (($v | describe) == "string") and (($v | str length) >= 2) {
      let n = ($v | str length)
      let first = ($v | str substring 0..<1)
      let last = ($v | str substring ($n - 1)..<$n)
      if (($first == '"') and ($last == '"')) or (($first == "'") and ($last == "'")) {
        {v: ($v | str substring 1..<($n - 1))}
      } else {
        $w
      }
    } else {
      $w
    }
  } | get v
}

# Normalize OAS 3.1 type value: ["string", "null"] → "string", "string" → "string"
export def normalize-type [type_val: any] {
  if ($type_val == null) { return null }
  if ($type_val | describe | str starts-with "list") {
    $type_val | where { $in != "null" } | first | default "any"
  } else {
    $type_val
  }
}

# Check if a schema is nullable (OAS 3.0 nullable:true or OAS 3.1 type array containing "null")
export def is-nullable [schema: record] {
  if ($schema.nullable? | default false) { return true }
  let t = ($schema.type? | default null)
  if ($t | describe | str starts-with "list") { "null" in $t } else { false }
}

# Detect schema type and major version from a parsed spec.
export def detect [spec: record] {
  if ($spec.openapi? | is-not-empty) {
    let major = ($spec.openapi | split row '.' | first)
    {schema: "openapi", version: $major}
  } else if ($spec.swagger? | is-not-empty) {
    let major = ($spec.swagger | split row '.' | first)
    {schema: "swagger", version: $major}
  } else {
    error make --unspanned { msg: "unknown spec format: missing 'openapi' or 'swagger' field" }
  }
}

# Determine default auth scheme from root-level security + parsed auth schemes
export def get-default-auth [spec: record, auth_schemes: list] {
  let security = ($spec.security? | default [])
  if ($security | is-not-empty) {
    let first_req = ($security | first)
    if (($first_req | describe) | str starts-with "record") {
      let ref_name = ($first_req | columns | first)
      let matched = $auth_schemes | where {|s| $s.spec_name == $ref_name }
      if ($matched | is-not-empty) {
        return ($matched | first | get name)
      }
    }
  }
  if ($auth_schemes | is-not-empty) {
    $auth_schemes | first | get name
  } else {
    "bearer"
  }
}

# The GLOBAL (top-level) AND-form security set, mirroring the
# per-op detection in `extract-op-metadata`. When the spec's top-level
# `security` is a single requirement object listing >1 scheme (e.g. VTEX's
# `[{appKey: [], appToken: []}]`), EVERY op that does not override `security`
# inherits the requirement to send ALL of them. Returns the resolved scheme
# records (length >1) or [] when there is no global AND-form.
export def get-default-auth-required [spec: record, auth_schemes: list] {
  let security = ($spec.security? | default [])
  if ($security | is-empty) { return [] }
  let first_req = ($security | first)
  if (($first_req | describe) | str starts-with "record") and ($first_req | is-not-empty) {
    let cols = ($first_req | columns)
    if ($cols | length) > 1 {
      return ($cols | each {|rn| $auth_schemes | where {|s| $s.spec_name == $rn } | first } | compact)
    }
  }
  []
}

# The response codes to consult, in order, when picking the success schema.
# `default` is the error envelope in practice (Azure ARM: `200` without a
# schema + `default: ErrorResponse`), so it is only a candidate when the
# operation declares NO 2xx response at all.
export def response-type-candidates [responses: record]: nothing -> list<string> {
  let has_2xx = ($responses | columns | any {|c| $c =~ '^2' })
  if $has_2xx { $RESPONSE_CODE_PRIORITY | where {|c| $c != "default" } } else { $RESPONSE_CODE_PRIORITY }
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
# description instead of an untyped `any`. Members' own allOf fold too, to a
# small depth so a self-referencing schema cannot loop. A schema without
# allOf comes back unchanged.
export def merge-all-of [schema: any, doc: record, --depth: int = 0]: nothing -> any {
  if not (($schema | describe) | str starts-with "record") { return $schema }
  let members = ($schema.allOf? | default [] | each {|sub| resolve-ref $sub $doc }
    | where {|sub| ($sub | describe) | str starts-with "record" }
    | each {|sub| if $depth < 3 { merge-all-of $sub $doc --depth ($depth + 1) } else { $sub } })
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

# Build an auth scheme record from a security definition entry.
# Handles apiKey (header/query/cookie), oauth2, and fallback cases
# shared by both OA3 and Swagger 2 closures.
# Returns null when the entry requires version-specific handling.
export def build-auth-scheme [entry: record] {
  let d = $entry.def
  let desc = ($d.description? | default "")
  if ($d.type? == "apiKey") {
    let loc = ($d.in? | default "header")
    let hdr = ($d.name? | default "Authorization")
    if $loc == "query" {
      {spec_name: $entry.spec_name, name: $"query-($hdr)", header_name: $hdr, prefix: "", in: "query"}
    } else if $loc == "cookie" {
      {spec_name: $entry.spec_name, name: $"cookie-($hdr)", header_name: $hdr, prefix: "", in: "cookie"}
    } else if ($hdr | str lowercase) == "authorization" {
      let pfx = if ($desc =~ '(?i)jwt') { "JWT" } else if ($desc =~ '(?i)static') { "STATIC" } else { "Bearer" }
      let scheme_name = ($pfx | str lowercase)
      {spec_name: $entry.spec_name, name: $scheme_name, header_name: "Authorization", prefix: $pfx, in: "header"}
    } else {
      let scheme_name = ($hdr | str lowercase)
      {spec_name: $entry.spec_name, name: $scheme_name, header_name: $hdr, prefix: "", in: "header"}
    }
  } else if ($d.type? == "oauth2") or ($d.type? == "openIdConnect") {
    {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
  } else {
    null
  }
}

# ── Shared helpers ─────────────────────────────────────────────────

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
