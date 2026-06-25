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
    let expanded = ($source | path expand | into string)
    {data: (open $expanded), source: $expanded}
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
    # `~1` MUST be decoded before `~0` — per RFC 6901 — otherwise `~01`
    # round-trips to `/` instead of `~1`.
    $s | str replace --all '~1' '/' | str replace --all '~0' '~'
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

# Look up a $ref target in a nested schemas record (keyed by namespace).
# Parses the ref path to find the right sub-record, with two fallbacks:
# (1) search all known namespaces by entity name, and (2) generic JSON Pointer
# traversal of the full spec document when it's been stashed under `__spec__`
# (DigitalOcean uses cross-path refs like `#/paths/~1v2~1.../get/parameters/0`
# to dedupe pagination params; those don't name a schemas-table entity and
# can only be resolved by walking the original spec).
# Returns null if not found.
def ref-lookup [ref_path: string, schemas: record] {
  let parts = ($ref_path | split row '/')
  let name = ($parts | last)
  # OA3: #/components/{ns}/{name} (4 parts) — Swagger 2: #/{ns}/{name} (3 parts)
  let ns = if ($parts | length) >= 4 {
    $parts | get 2
  } else if ($parts | length) == 3 {
    $parts | get 1
  } else {
    null
  }
  if ($ns in ($schemas | columns)) {
    let sub = ($schemas | get $ns)
    if (($sub | describe) | str starts-with "record") and ($name in ($sub | columns)) {
      return ($sub | get $name)
    }
  }
  # Fallback 1: search known schemas-table namespaces by entity name. Skip
  # `__spec__` so we don't accidentally return a top-level spec field that
  # happens to share a name with the target.
  for col in ($schemas | columns) {
    if $col == "__spec__" { continue }
    let sub = ($schemas | get $col)
    if (($sub | describe) | str starts-with "record") and ($name in ($sub | columns)) {
      return ($sub | get $name)
    }
  }
  # Fallback 2: generic JSON Pointer traversal of the original spec document.
  let spec_doc = ($schemas.__spec__? | default null)
  if $spec_doc != null {
    let target = (json-pointer-lookup $spec_doc $ref_path)
    if $target != null { return $target }
  }
  null
}

# Pre-resolve $ref chains in a raw schemas record. Each entry has any top-
# level $ref chain (A → B → C) collapsed to the final concrete value, but
# inner $refs inside that value are LEFT IN PLACE. Callers re-invoke
# resolve-ref to resolve those inner refs when they actually need them.
#
# Why shallow rather than deep: Nushell has no shared object references —
# every "share" is a copy. Deep-inlining a heavily-shared schema graph
# (Confluence, GitLab, GitHub) blows up memory by the fan-out factor.
# Shallow resolution keeps the table size O(sum of schema sizes) and
# pushes resolution work to where it's actually needed.
#
# Cycles: a {$ref} that points back into its own chain is returned as-is
# ("first wins" semantics, same as the previous implementation).
export def resolve-schemas [raw_schemas: record] {
  mut output = {}
  for ns in ($raw_schemas | columns) {
    let sub = ($raw_schemas | get $ns)
    if not (($sub | describe) | str starts-with "record") {
      $output = ($output | upsert $ns $sub)
      continue
    }
    mut resolved_sub = {}
    for name in ($sub | columns) {
      let val = ($sub | get $name)
      let collapsed = (collapse-ref-chain $val $raw_schemas [])
      $resolved_sub = ($resolved_sub | upsert $name $collapsed)
    }
    $output = ($output | upsert $ns $resolved_sub)
  }
  $output
}

# Internal: follow a $ref chain to the first non-$ref value (or to a cycle).
# Does NOT descend into the resolved value's structure.
def collapse-ref-chain [val: any, schemas: record, visited: list<string>] {
  let t = ($val | describe)
  if not ($t | str starts-with "record") { return $val }
  if not ("$ref" in ($val | columns)) { return $val }
  let ref_path = ($val | get "$ref")
  if not (($ref_path | describe) == "string") { return $val }
  if ($ref_path in $visited) { return $val }
  let target = (ref-lookup $ref_path $schemas)
  if ($target == null) { return $val }
  collapse-ref-chain $target $schemas ($visited | append $ref_path)
}

# Resolve a $ref pointer against a (pre-resolved) schemas table.
#
# Behaviour is intentionally SHALLOW — only the top-level $ref is followed:
# - If $val is a {$ref: X} record, return ref-lookup of X. The returned
#   value is the target schema with its OWN $refs still inline; the caller
#   must re-invoke resolve-ref on any sub-field it wants resolved.
# - Otherwise return $val unchanged.
#
# Combined with `resolve-schemas`, ref chains (A → B → C) collapse
# to C in a single lookup, and each ref resolution is O(1).
export def resolve-ref [val: any, schemas: record] {
  let t = ($val | describe)
  if not ($t | str starts-with "record") { return $val }
  if not ("$ref" in ($val | columns)) { return $val }
  let ref_path = ($val | get "$ref")
  if not (($ref_path | describe) == "string") { return $val }
  let resolved = (ref-lookup $ref_path $schemas)
  if ($resolved == null) { $val } else { $resolved }
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

# D-7 (issue 51): the GLOBAL (top-level) AND-form security set, mirroring the
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

# Convert an OpenAPI schema to a nushell type string.
# Recursively builds typed records/tables. Depth-limited to avoid huge types.
export def schema-to-nu-type [schema: any, schemas: record, --depth: int = 0, --max-depth: int = 3, --visited: list<string> = []] {
  if ($schema == null) or (not (($schema | describe) | str starts-with "record")) { return "any" }

  # resolve $ref
  if ("$ref" in ($schema | columns)) {
    let ref_path = ($schema | get "$ref")
    if not (($ref_path | describe) == "string") { return "any" }
    if ($ref_path in $visited) { return "any" }  # circular ref
    let resolved = (ref-lookup $ref_path $schemas)
    if ($resolved != null) {
      return (schema-to-nu-type $resolved $schemas --depth $depth --max-depth $max_depth --visited ($visited | append $ref_path))
    }
    return "any"
  }

  # if we're past max depth, use simple types
  let t = (normalize-type ($schema.type? | default null))
  let has_props = ($schema.properties? | is-not-empty)
  let has_allof = ($schema.allOf? | is-not-empty)
  let has_items = ($schema.items? | is-not-empty)

  if $depth >= $max_depth {
    # simplified: no recursion into fields
    return (match $t {
      "array" => "list"
      "object" => "record"
      "string" => "string"
      "integer" => "int"
      "number" => "float"
      "boolean" => "bool"
      _ => {
        if $has_props or $has_allof { "record" } else if $has_items { "list" } else { "any" }
      }
    })
  }

  match $t {
    "array" => {
      let items_schema = ($schema.items? | default {})
      let item_type = (schema-to-nu-type $items_schema $schemas --depth ($depth + 1) --max-depth $max_depth --visited $visited)
      if ($item_type | str starts-with "record<") {
        # table<fields> is nicer than list<record<fields>>
        $"table<($item_type | str substring 7..-2)>"
      } else {
        $"list<($item_type)>"
      }
    }
    "object" => {
      if $has_props {
        let fields = (build-record-fields ($schema.properties? | default {}) $schemas ($depth + 1) $max_depth $visited)
        if ($fields | is-empty) { "record" } else { $"record<($fields)>" }
      } else { "record" }
    }
    "string" => "string"
    "integer" => "int"
    "number" => "float"
    "boolean" => "bool"
    _ => {
      # no explicit type — infer from structure
      if $has_allof {
        # merge allOf properties
        mut merged_props = ($schema.properties? | default {})
        for sub in ($schema.allOf? | default []) {
          let resolved = (resolve-ref $sub $schemas)
          if (($resolved | describe) | str starts-with "record") {
            $merged_props = ($merged_props | merge ($resolved.properties? | default {}))
          }
        }
        if ($merged_props | is-not-empty) {
          let fields = (build-record-fields $merged_props $schemas ($depth + 1) $max_depth $visited)
          if ($fields | is-empty) { "record" } else { $"record<($fields)>" }
        } else { "record" }
      } else if $has_props {
        let fields = (build-record-fields ($schema.properties? | default {}) $schemas ($depth + 1) $max_depth $visited)
        if ($fields | is-empty) { "record" } else { $"record<($fields)>" }
      } else if $has_items {
        let item_type = (schema-to-nu-type ($schema.items? | default {}) $schemas --depth ($depth + 1) --max-depth $max_depth --visited $visited)
        $"list<($item_type)>"
      } else { "any" }
    }
  }
}

# Build "field1: type1, field2: type2" string from a properties map.
#
# Output goes into a `record<...>` TYPE SIGNATURE — must be valid Nushell type
# syntax. No truncation: a `... (N more fields)` marker would be a parse error.
# Catastrophic depth is already bounded by `max_depth`; wide records produce
# long-but-valid signatures, which is the correct tradeoff (terminals wrap,
# parsers don't fix bad syntax).
def build-record-fields [properties: record, schemas: record, depth: int, max_depth: int, visited: list<string>] {
  $properties | items {|name, prop_schema|
    let field_type = (schema-to-nu-type $prop_schema $schemas --depth $depth --max-depth $max_depth --visited $visited)
    # sanitize field names: nushell doesn't allow special chars in record type keys
    let safe_name = ($name | str replace --all --regex '[^a-zA-Z0-9_]' '_')
    $"($safe_name): ($field_type)"
  } | str join ", "
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
    } else if ($hdr | str downcase) == "authorization" {
      let pfx = if ($desc =~ '(?i)jwt') { "JWT" } else if ($desc =~ '(?i)static') { "STATIC" } else { "Bearer" }
      let scheme_name = ($pfx | str downcase)
      {spec_name: $entry.spec_name, name: $scheme_name, header_name: "Authorization", prefix: $pfx, in: "header"}
    } else {
      let scheme_name = ($hdr | str downcase)
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
