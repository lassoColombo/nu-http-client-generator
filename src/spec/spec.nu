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
# Used by both REST and GraphQL spec loaders to bypass `http get`'s
# auto-parser. The auto-parser would be ideal — one call, parsed record
# back — but it doesn't survive real-world specs served with content-types
# nushell doesn't recognize (e.g. `application/vnd.oai.openapi+json` from
# api.weather.gov, or `application/graphql+json` from some GraphQL servers).
# When the auto-parser doesn't know a media type, it hands back a bare string
# and downstream `from json` / `spec detect` panics. Fetching raw and parsing
# explicitly downstream sidesteps the issue.
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

# Resolve a $ref pointer against a schemas lookup table (version-independent).
# Tracks visited refs to break cycles.
export def resolve-ref [val: any, schemas: record, --visited: list<string> = []] {
  let t = ($val | describe)
  if ($t | str starts-with "record") {
    if ($val | columns | any {|c| $c == "$ref" }) {
      let ref_path = ($val | get "$ref")
      # guard: $ref must be a string
      if not (($ref_path | describe) == "string") {
        return $val
      }
      # cycle detection
      if ($ref_path in $visited) {
        return $val
      }
      let resolved = (ref-lookup $ref_path $schemas)
      if ($resolved != null) {
        resolve-ref $resolved $schemas --visited ($visited | append $ref_path)
      } else {
        $val
      }
    } else {
      mut result = $val
      for col in ($val | columns) {
        let v = ($val | get $col)
        let vt = ($v | describe)
        if ($vt | str starts-with "record") {
          $result = ($result | upsert $col (resolve-ref $v $schemas --visited $visited))
        } else if ($vt | str starts-with "list") {
          $result = ($result | upsert $col ($v | each {|item|
            if (($item | describe) | str starts-with "record") {
              resolve-ref $item $schemas --visited $visited
            } else {
              $item
            }
          }))
        }
      }
      $result
    }
  } else {
    $val
  }
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

# Filter parameters: return path/query/header/cookie params, exclude body/formData
export def get-non-body-params [params: list] {
  $params | where {|p|
    let loc = ($p.in? | default "")
    $loc in ["path" "query" "header" "cookie"]
  }
}

# Get the description from a parameter
export def get-param-description [param: record] {
  $param.description? | default ""
}

# Detect schema type and major version from a parsed spec.
export def detect [spec: record] {
  if ($spec.openapi? | is-not-empty) {
    let major = ($spec.openapi | split row '.' | first)
    {schema: "openapi", version: $major}
  } else if ($spec.swagger? | is-not-empty) {
    let major = ($spec.swagger | split row '.' | first)
    {schema: "swagger", version: $major}
  } else if ($spec.data?.__schema? | is-not-empty) {
    {schema: "graphql", version: "introspection"}
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
          let resolved = (resolve-ref $sub $schemas --visited $visited)
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

# ── GraphQL introspection helpers ───────────────────────────────────

# Recursively peel NON_NULL/LIST wrappers from a GraphQL type reference.
# Returns {name: string, is_list: bool, is_required: bool}.
export def unwrap-gql-type [type_ref: record, is_list: bool = false, is_required: bool = false] {
  if $type_ref.kind == "NON_NULL" {
    if ($type_ref.ofType? != null) {
      unwrap-gql-type $type_ref.ofType $is_list true
    } else {
      {name: "any", is_list: $is_list, is_required: true, is_truncated: true}
    }
  } else if $type_ref.kind == "LIST" {
    # Once inside a LIST, inner NON_NULL marks element nullability, not field requiredness.
    # Stop propagating is_required from inner wrappers.
    if ($type_ref.ofType? != null) {
      let inner = (unwrap-gql-type $type_ref.ofType true false)
      {name: $inner.name, is_list: true, is_required: $is_required, is_truncated: ($inner.is_truncated? | default false)}
    } else {
      {name: "any", is_list: true, is_required: $is_required, is_truncated: true}
    }
  } else {
    {name: $type_ref.name, is_list: $is_list, is_required: $is_required, is_truncated: false}
  }
}

# Reconstruct GraphQL type syntax string from a type_ref for variable declarations.
# E.g. NON_NULL(LIST(NON_NULL(SCALAR "Country"))) → "[Country!]!"
export def gql-type-to-signature [type_ref: record] {
  if $type_ref.kind == "NON_NULL" {
    if ($type_ref.ofType? != null) {
      $"(gql-type-to-signature $type_ref.ofType)!"
    } else {
      "any!"
    }
  } else if $type_ref.kind == "LIST" {
    if ($type_ref.ofType? != null) {
      $"[(gql-type-to-signature $type_ref.ofType)]"
    } else {
      "[any]"
    }
  } else {
    $type_ref.name? | default "any"
  }
}

# Map a GraphQL scalar name to an OpenAPI-style type string.
export def gql-scalar-to-openapi [name: string] {
  match $name {
    "String" => "string"
    "Int" => "integer"
    "Float" => "number"
    "Boolean" => "boolean"
    "ID" => "string"
    "JSON" | "Json" | "jsonb" | "JSONObject" | "JsonString" => "any"
    "BigInt" | "Long" => "integer"
    "Date" | "DateTime" | "ISO8601Date" | "ISO8601DateTime"
      | "Time" | "Timestamp" | "timestamptz" | "Duration" => "string"
    "Upload" => "file"
    _ => "string"  # custom scalars default to string
  }
}

# Walk the type chain to find the leaf's kind (SCALAR, ENUM, INPUT_OBJECT, etc.)
export def gql-leaf-kind [type_ref: record] {
  if $type_ref.kind == "NON_NULL" or $type_ref.kind == "LIST" {
    if ($type_ref.ofType? != null) { gql-leaf-kind $type_ref.ofType } else { "OBJECT" }
  } else {
    $type_ref.kind? | default "OBJECT"
  }
}

# Given a type name and a type index, collect scalar/enum field names at depth=1.
# For UNION types, generates inline fragments for up to 3 possible types.
export def compute-default-selection [type_name: string, type_index: record] {
  let typ = ($type_index | get -o $type_name)
  if ($typ == null) { return "" }

  # UNION types: no fields, but possibleTypes with concrete members
  if ($typ.kind? == "UNION") and ($typ.possibleTypes? != null) {
    let fragments = ($typ.possibleTypes | first ([($typ.possibleTypes | length) 3] | math min) | each {|pt|
      let member = ($type_index | get -o $pt.name)
      if ($member == null) or ($member.fields? == null) { return $"... on ($pt.name) { __typename }" }
      let fields = ($member.fields
        | where {|f|
          let leaf_kind = (gql-leaf-kind $f.type)
          $leaf_kind == "SCALAR" or $leaf_kind == "ENUM"
        }
        | get name
        | str join " ")
      if ($fields | is-empty) { $"... on ($pt.name) { __typename }" } else { $"... on ($pt.name) { ($fields) }" }
    })
    return (["__typename"] | append $fragments | str join " ")
  }

  if ($typ.fields? == null) { return "" }
  let base_fields = ($typ.fields
    | where {|f|
      let leaf_kind = (gql-leaf-kind $f.type)
      $leaf_kind == "SCALAR" or $leaf_kind == "ENUM"
    }
    | get name)
  let base_selection = ($base_fields | str join " ")

  # INTERFACE types: append inline fragments for extra fields from implementing types
  if ($typ.kind? == "INTERFACE") and ($typ.possibleTypes? != null) {
    let fragments = ($typ.possibleTypes | first ([($typ.possibleTypes | length) 3] | math min) | each {|pt|
      let member = ($type_index | get -o $pt.name)
      if ($member == null) or ($member.fields? == null) { return null }
      let extra_fields = ($member.fields
        | where {|f|
          let leaf_kind = (gql-leaf-kind $f.type)
          ($leaf_kind == "SCALAR" or $leaf_kind == "ENUM") and ($f.name not-in $base_fields)
        }
        | get name
        | str join " ")
      if ($extra_fields | is-empty) { null } else { $"... on ($pt.name) { ($extra_fields) }" }
    } | compact)
    if ($fragments | is-not-empty) {
      return ($base_selection + " " + ($fragments | str join " "))
    }
  }

  $base_selection
}

# Resolve shared GraphQL type-resolution pipeline for a single field/arg record.
# The record must have .type, and optionally .description?, .defaultValue?, .isDeprecated?, .deprecationReason?.
# Returns {type: string, enum: list, required: bool, deprecated: bool, desc_base: string, deprecation_reason: any, unwrapped: record}.
export def resolve-gql-field [field: record, type_index: record] {
  let unwrapped = (unwrap-gql-type $field.type)
  let leaf_kind = (gql-leaf-kind $field.type)
  let param_type = if $leaf_kind == "INPUT_OBJECT" { "record" } else if $leaf_kind == "ENUM" { "string" } else { gql-scalar-to-openapi $unwrapped.name }
  let enum_vals = if $leaf_kind == "ENUM" {
    let enum_type = ($type_index | get -o $unwrapped.name)
    if ($enum_type != null) and ($enum_type.enumValues? != null) { $enum_type.enumValues | get name } else { [] }
  } else { [] }
  let is_required = if ($field.defaultValue? != null) { false } else { $unwrapped.is_required }
  let deprecated = ($field.isDeprecated? | default false)
  let reason = ($field.deprecationReason? | default null)
  let desc_base = ($field.description? | default "")
  {
    type: $param_type
    enum: $enum_vals
    required: $is_required
    deprecated: $deprecated
    desc_base: $desc_base
    deprecation_reason: $reason
    unwrapped: $unwrapped
  }
}

# Extract inputFields from a GraphQL INPUT_OBJECT type, returning body-field-like records.
export def extract-gql-input-fields [type_name: string, type_index: record] {
  let typ = ($type_index | get -o $type_name)
  if ($typ == null) or ($typ.inputFields? == null) { return [] }
  $typ.inputFields | each {|f|
    let resolved = (resolve-gql-field $f $type_index)
    let description = if $resolved.deprecated and ($resolved.deprecation_reason != null) { $"DEPRECATED: ($resolved.deprecation_reason) ($resolved.desc_base)" | str trim } else if $resolved.deprecated { $"DEPRECATED ($resolved.desc_base)" | str trim } else { $resolved.desc_base }
    {
      name: $f.name
      type: $resolved.type
      required: $resolved.required
      nullable: false
      enum: $resolved.enum
      description: $description
      deprecated: $resolved.deprecated
    }
  }
}
