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
  let t = ($schema.type? | default null)
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

# Resolve OA3 server URL with variable substitution
def resolve-server-url [server: record] {
  let raw = ($server.url? | default $"http://($DEFAULT_HOST)")
  let vars = ($server.variables? | default {})
  let substituted = if ($vars | columns | length) == 0 {
    $raw
  } else {
    mut result = $raw
    for v in ($vars | transpose name def) {
      let default_val = ($v.def.default? | default "")
      $result = ($result | str replace $"{($v.name)}" $default_val)
    }
    $result
  }
  # Prepend localhost for relative URLs
  let absolute = if ($substituted | str starts-with "/") {
    $"http://($DEFAULT_HOST)($substituted)"
  } else {
    $substituted
  }
  # Remove trailing slash to avoid double-slash in constructed URLs
  $absolute | str trim --right --char '/'
}

# Collect all server URLs from OA3 spec (root + path + operation level)
def collect-oa3-urls [spec: record] {
  mut urls = []
  # root-level servers
  let root_servers = ($spec.servers? | default [])
  for s in $root_servers {
    $urls = ($urls | append (resolve-server-url $s))
    # also add enum variants for each variable
    let vars = ($s.variables? | default {})
    for v in ($vars | transpose name def) {
      let enum_vals = ($v.def.enum? | default [])
      for ev in $enum_vals {
        let variant_url = ($s.url? | default "" | str replace $"{($v.name)}" $ev)
        # resolve other vars with defaults
        mut resolved = $variant_url
        for v2 in ($vars | transpose name def) {
          if $v2.name != $v.name {
            $resolved = ($resolved | str replace $"{($v2.name)}" ($v2.def.default? | default ""))
          }
        }
        let resolved_abs = if ($resolved | str starts-with "/") { $"http://($DEFAULT_HOST)($resolved)" } else { $resolved }
        $urls = ($urls | append ($resolved_abs | str trim --right --char '/'))
      }
    }
  }
  # path-level and operation-level servers
  let paths = ($spec.paths? | default {})
  for entry in ($paths | transpose path methods) {
    let path_servers = ($entry.methods.servers? | default [])
    for s in $path_servers {
      $urls = ($urls | append (resolve-server-url $s))
    }
    for m in ($entry.methods | transpose method op) {
      if $m.method in [get post put patch delete head options] {
        let op = $m.op
        if (($op | describe) | str starts-with "record") {
          let op_servers = ($op.servers? | default [])
          for s in $op_servers {
            $urls = ($urls | append (resolve-server-url $s))
          }
        }
      }
    }
  }
  $urls | uniq
}

# Build an auth scheme record from a security definition entry.
# Handles apiKey (header/query/cookie), oauth2, and fallback cases
# shared by both OA3 and Swagger 2 closures.
# Returns null when the entry requires version-specific handling.
def build-auth-scheme [entry: record] {
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

# ── GraphQL introspection helpers ───────────────────────────────────

# Recursively peel NON_NULL/LIST wrappers from a GraphQL type reference.
# Returns {name: string, is_list: bool, is_required: bool}.
export def unwrap-gql-type [type_ref: record, is_list: bool = false, is_required: bool = false] {
  if $type_ref.kind == "NON_NULL" {
    if ($type_ref.ofType? != null) {
      unwrap-gql-type $type_ref.ofType $is_list true
    } else {
      {name: "any", is_list: $is_list, is_required: true}
    }
  } else if $type_ref.kind == "LIST" {
    if ($type_ref.ofType? != null) {
      unwrap-gql-type $type_ref.ofType true $is_required
    } else {
      {name: "any", is_list: true, is_required: $is_required}
    }
  } else {
    {name: $type_ref.name, is_list: $is_list, is_required: $is_required}
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
export def compute-default-selection [type_name: string, type_index: record] {
  let typ = ($type_index | get -o $type_name)
  if ($typ == null) or ($typ.fields? == null) { return "" }
  $typ.fields
  | where {|f|
    let leaf_kind = (gql-leaf-kind $f.type)
    # Include only scalar and enum fields (not objects/interfaces/unions that need sub-selection)
    $leaf_kind == "SCALAR" or $leaf_kind == "ENUM"
  }
  | get name
  | str join " "
}

# Return the dispatch table: schema_type -> version -> helper closures.
export def helpers [] {
  {
    openapi: {
      "3": {
        get-schemas: {|spec|
          {
            schemas: ($spec.components?.schemas? | default {})
            parameters: ($spec.components?.parameters? | default {})
            responses: ($spec.components?.responses? | default {})
            requestBodies: ($spec.components?.requestBodies? | default {})
          }
        }
        get-base-url: {|spec|
          let servers = ($spec.servers? | default [])
          if ($servers | length) > 0 {
            resolve-server-url ($servers | first)
          } else {
            $"http://($DEFAULT_HOST)"
          }
        }
        get-all-urls: {|spec|
          collect-oa3-urls $spec
        }
        get-param-type: {|param|
          # support `content` field as alternative to `schema` (OA3 5.9)
          if ($param.content? | is-not-empty) {
            "string"
          } else {
            $param.schema?.type? | default "string"
          }
        }
        get-param-enum: {|param|
          if ($param.content? | is-not-empty) {
            []
          } else {
            $param.schema?.enum? | default []
          }
        }
        get-param-collection-style: {|param|
          if ($param.content? | is-not-empty) {
            "scalar"
          } else {
            let t = ($param.schema?.type? | default "string")
            let style = ($param.style? | default "form")
            if $style == "deepObject" { "deepObject" } else if $t not-in ["array" "object"] { "scalar" } else {
              let explode = ($param.explode? | default ($style == "form"))
              match $style {
                "form" => { if $explode { "multi" } else { "csv" } }
                "spaceDelimited" => "ssv"
                "pipeDelimited" => "pipes"
                _ => "csv"
              }
            }
          }
        }
        get-body-info: {|op, schemas|
          let request_body = $op.requestBody?
          if ($request_body | is-empty) {
            {has_body: false, body_schema: {}, content_type: $CT_JSON}
          } else {
            let rb = (resolve-ref $request_body $schemas)
            let content = ($rb.content? | default {})
            let ct_order = $CT_PRIORITY
            mut found_ct = null
            mut found_schema = {}
            for ct in $ct_order {
              if ($found_ct == null) {
                let ct_content = ($content | get -o $ct)
                if ($ct_content | is-not-empty) {
                  $found_ct = $ct
                  let s = $ct_content.schema?
                  if ($s | is-not-empty) {
                    $found_schema = (resolve-ref $s $schemas)
                  }
                }
              }
            }
            if ($found_ct != null) {
              {has_body: true, body_schema: $found_schema, content_type: $found_ct}
            } else {
              let first_ct = ($content | columns | first | default $CT_JSON)
              {has_body: true, body_schema: {}, content_type: $first_ct}
            }
          }
        }
        get-response-content-types: {|op, _spec|
          let responses = ($op.responses? | default {})
          $responses | transpose code resp | where {|r|
            ($r.code | str starts-with "2") or ($r.code == "default") or ($r.code =~ '^[12][xX]{2}$')
          } | each {|r|
            $r.resp.content? | default {} | columns
          } | flatten | uniq | if ($in | is-empty) { [$CT_JSON] } else { $in }
        }
        get-response-type: {|op, spec|
          let schemas = {
            schemas: ($spec.components?.schemas? | default {})
            parameters: ($spec.components?.parameters? | default {})
            responses: ($spec.components?.responses? | default {})
            requestBodies: ($spec.components?.requestBodies? | default {})
          }
          let responses = ($op.responses? | default {})
          mut found_schema = null
          for code in $RESPONSE_CODE_PRIORITY {
            if ($found_schema == null) {
              let resp = ($responses | get -o $code)
              if ($resp | is-not-empty) {
                let content = ($resp.content? | default {})
                let json_media = ($content | get -o "application/json" | default {})
                let s = ($json_media | get -o schema | default null)
                if ($s | is-not-empty) { $found_schema = $s }
              }
            }
          }
          if ($found_schema == null) { return "any" }
          schema-to-nu-type $found_schema $schemas
        }
        get-auth-schemes: {|spec|
          let schemes = ($spec.components?.securitySchemes? | default {})
          $schemes | transpose spec_name def | each {|entry|
            let d = $entry.def
            if ($d.type? == "http") {
              let s = ($d.scheme? | default "bearer") | str downcase
              {spec_name: $entry.spec_name, name: $s, header_name: "Authorization", prefix: ($s | str capitalize), in: "header"}
            } else {
              let shared = (build-auth-scheme $entry)
              if ($shared != null) { $shared } else {
                {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
              }
            }
          }
        }
      }
    }
    swagger: {
      "2": {
        get-schemas: {|spec|
          {
            definitions: ($spec.definitions? | default {})
            parameters: ($spec.parameters? | default {})
            responses: ($spec.responses? | default {})
          }
        }
        get-base-url: {|spec|
          let host = ($spec.host? | default $DEFAULT_HOST)
          let base_path = ($spec.basePath? | default "")
          let schemes = ($spec.schemes? | default ["https"])
          let scheme = ($schemes | first)
          $"($scheme)://($host)($base_path)" | str trim --right --char '/'
        }
        get-all-urls: {|spec|
          let host = ($spec.host? | default $DEFAULT_HOST)
          let base_path = ($spec.basePath? | default "")
          let schemes = ($spec.schemes? | default ["https"])
          $schemes | each {|s| $"($s)://($host)($base_path)" | str trim --right --char '/' }
        }
        get-param-type: {|param|
          $param.type? | default "string"
        }
        get-param-enum: {|param|
          $param.enum? | default []
        }
        get-param-collection-style: {|param|
          let t = ($param.type? | default "string")
          if $t != "array" { "scalar" } else {
            let cf = ($param.collectionFormat? | default "csv")
            match $cf { "csv" => "csv", "ssv" => "ssv", "tsv" => "tsv", "pipes" => "pipes", "multi" => "multi", _ => "csv" }
          }
        }
        get-body-info: {|op, schemas|
          let params = ($op.parameters? | default [])
          let form_params = $params | where {|p| ($p.in? | default "") == "formData" }
          if ($form_params | length) > 0 {
            let has_file = ($form_params | where {|p| ($p.type? | default "") == "file" } | length) > 0
            let ct = if $has_file { $CT_MULTIPART } else { $CT_FORM }
            mut props = {}
            mut required = []
            for fp in $form_params {
              $props = ($props | insert $fp.name {type: ($fp.type? | default "string"), description: ($fp.description? | default ""), enum: ($fp.enum? | default [])})
              if ($fp.required? | default false) {
                $required = ($required | append $fp.name)
              }
            }
            {has_body: true, body_schema: {type: "object", properties: $props, required: $required}, content_type: $ct}
          } else {
            let body_param = $params | where {|p| ($p.in? | default "") == "body" } | first | default null
            if ($body_param | is-empty) {
              {has_body: false, body_schema: {}, content_type: $CT_JSON}
            } else {
              let s = $body_param.schema?
              if ($s | is-not-empty) {
                {has_body: true, body_schema: (resolve-ref $s $schemas), content_type: $CT_JSON}
              } else {
                {has_body: true, body_schema: {}, content_type: $CT_JSON}
              }
            }
          }
        }
        get-response-content-types: {|op, spec|
          let op_produces = ($op.produces? | default [])
          let global_produces = ($spec.produces? | default [])
          let types = if ($op_produces | is-not-empty) { $op_produces } else { $global_produces }
          if ($types | is-empty) { [$CT_JSON] } else { $types | uniq }
        }
        get-response-type: {|op, spec|
          let schemas = {
            definitions: ($spec.definitions? | default {})
            parameters: ($spec.parameters? | default {})
            responses: ($spec.responses? | default {})
          }
          let responses = ($op.responses? | default {})
          mut found_schema = null
          for code in $RESPONSE_CODE_PRIORITY {
            if ($found_schema == null) {
              let resp = ($responses | get -o $code)
              if ($resp | is-not-empty) {
                let s = ($resp.schema? | default null)
                if ($s | is-not-empty) { $found_schema = $s }
              }
            }
          }
          if ($found_schema == null) { return "any" }
          schema-to-nu-type $found_schema $schemas
        }
        get-auth-schemes: {|spec|
          let schemes = ($spec.securityDefinitions? | default {})
          $schemes | transpose spec_name def | each {|entry|
            let d = $entry.def
            if ($d.type? == "basic") {
              {spec_name: $entry.spec_name, name: "basic", header_name: "Authorization", prefix: "Basic", in: "header"}
            } else {
              let shared = (build-auth-scheme $entry)
              if ($shared != null) { $shared } else {
                {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
              }
            }
          }
        }
      }
    }
    graphql: {
      introspection: {
        get-schemas: {|spec|
          let types = ($spec.data.__schema.types | where { not ($in.name | str starts-with "__") })
          { types: ($types | reduce -f {} {|t, acc| $acc | insert $t.name $t }) }
        }
        get-base-url: {|spec| "" }
        get-all-urls: {|spec| [] }
        get-param-type: {|param|
          # param here is a GraphQL arg record with .type field
          let unwrapped = (unwrap-gql-type $param.type)
          if $unwrapped.name == null { "string" }
          else {
            let leaf_kind = (gql-leaf-kind $param.type)
            if $leaf_kind == "INPUT_OBJECT" { "record" }
            else if $leaf_kind == "ENUM" { "string" }
            else { gql-scalar-to-openapi $unwrapped.name }
          }
        }
        get-param-enum: {|param, schemas|
          let unwrapped = (unwrap-gql-type $param.type)
          let leaf_kind = (gql-leaf-kind $param.type)
          if $leaf_kind == "ENUM" {
            let type_index = $schemas.types
            let enum_type = ($type_index | get -o $unwrapped.name)
            if ($enum_type != null) and ($enum_type.enumValues? != null) {
              $enum_type.enumValues | get name
            } else { [] }
          } else { [] }
        }
        get-param-collection-style: {|param|
          let unwrapped = (unwrap-gql-type $param.type)
          if $unwrapped.is_list { "multi" } else { "scalar" }
        }
        get-body-info: {|op, schemas| {has_body: false, body_schema: {}, content_type: "application/json"} }
        get-response-content-types: {|op, spec| ["application/json"] }
        get-response-type: {|op, spec|
          # We'll compute this at the mod.nu level instead
          "record"
        }
        get-auth-schemes: {|spec| [] }
      }
    }
  }
}
