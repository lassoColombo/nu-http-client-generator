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
  let raw = (http get --raw --headers $headers $url)
  if (($raw | describe) | str starts-with "binary") { $raw | decode utf-8 } else { $raw }
}

# Look up a $ref target in a nested schemas record (keyed by namespace).
# Parses the ref path to find the right sub-record, with fallback search.
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
  if ($ns != null) and ($ns in ($schemas | columns)) {
    let sub = ($schemas | get $ns)
    if (($sub | describe) | str starts-with "record") and ($name in ($sub | columns)) {
      return ($sub | get $name)
    }
  }
  # Fallback: search all sub-records
  for col in ($schemas | columns) {
    let sub = ($schemas | get $col)
    if (($sub | describe) | str starts-with "record") and ($name in ($sub | columns)) {
      return ($sub | get $name)
    }
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
export def build-resolved-schemas [raw_schemas: record] {
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
  if not ($val | columns | any {|c| $c == "$ref" }) { return $val }
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
# Combined with `build-resolved-schemas`, ref chains (A → B → C) collapse
# to C in a single lookup, and each ref resolution is O(1).
export def resolve-ref [val: any, schemas: record] {
  let t = ($val | describe)
  if not ($t | str starts-with "record") { return $val }
  if not ($val | columns | any {|c| $c == "$ref" }) { return $val }
  let ref_path = ($val | get "$ref")
  if not (($ref_path | describe) == "string") { return $val }
  let resolved = (ref-lookup $ref_path $schemas)
  if ($resolved == null) { $val } else { $resolved }
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
  if ($t != null) and ($t | describe | str starts-with "list") { "null" in $t } else { false }
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
  if ($security | length) > 0 {
    let first_req = ($security | first)
    if (($first_req | describe) | str starts-with "record") {
      let ref_name = ($first_req | columns | first)
      let matched = $auth_schemes | where {|s| $s.spec_name == $ref_name }
      if ($matched | length) > 0 {
        return ($matched | first | get name)
      }
    }
  }
  if ($auth_schemes | length) > 0 {
    $auth_schemes | first | get name
  } else {
    "bearer"
  }
}

# Convert an OpenAPI schema to a nushell type string.
# Recursively builds typed records/tables. Depth-limited to avoid huge types.
export def schema-to-nu-type [schema: any, schemas: record, --depth: int = 0, --max-depth: int = 3, --visited: list<string> = []] {
  if ($schema == null) or (not (($schema | describe) | str starts-with "record")) { return "any" }

  # resolve $ref
  if ($schema | columns | any { $in == "$ref" }) {
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
        if ($merged_props | columns | length) > 0 {
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

# Build "field1: type1, field2: type2" string from a properties map
def build-record-fields [properties: record, schemas: record, depth: int, max_depth: int, visited: list<string>] {
  $properties | transpose name prop_schema | each {|entry|
    let field_type = (schema-to-nu-type $entry.prop_schema $schemas --depth $depth --max-depth $max_depth --visited $visited)
    # sanitize field names: nushell doesn't allow special chars in record type keys
    let safe_name = ($entry.name | str replace --all --regex '[^a-zA-Z0-9_]' '_')
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

# Merge a base description with a list of nullable metadata annotations.
# Filters nulls, joins with ", ", and conditionally appends to base description.
export def build-description [desc_base: string, extras: list] {
  let extra = $extras | where { $in != null } | str join ", "
  if ($extra | is-not-empty) and ($desc_base | is-not-empty) {
    $"($desc_base) \(($extra)\)"
  } else if ($extra | is-not-empty) {
    $extra
  } else {
    $desc_base
  }
}
