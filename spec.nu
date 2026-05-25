# spec.nu — Dispatch table for OpenAPI/Swagger spec helpers.
# Version-specific logic is encapsulated in closures, looked up by schema type + version.
# Version-independent helpers are plain exported functions.

# Resolve a $ref pointer against a schemas lookup table (version-independent)
export def resolve-ref [val: any, schemas: record] {
  let t = ($val | describe)
  if ($t | str starts-with "record") {
    if ($val | columns | any {|c| $c == "$ref" }) {
      let ref_path = ($val | get "$ref")
      let schema_name = ($ref_path | split row '/' | last)
      if ($schema_name in ($schemas | columns)) {
        $schemas | get $schema_name
      } else {
        $val
      }
    } else {
      # resolve refs in each column value in-place
      mut result = $val
      for col in ($val | columns) {
        let v = ($val | get $col)
        let vt = ($v | describe)
        if ($vt | str starts-with "record") {
          $result = ($result | upsert $col (resolve-ref $v $schemas))
        } else if ($vt | str starts-with "list") {
          $result = ($result | upsert $col ($v | each {|item|
            if (($item | describe) | str starts-with "record") {
              resolve-ref $item $schemas
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

# Filter parameters: return path/query/header/cookie params, exclude body (version-independent)
export def get-non-body-params [params: list] {
  $params | where {|p|
    let loc = ($p.in? | default "")
    $loc in ["path" "query" "header" "cookie"]
  }
}

# Get the description from a parameter (version-independent)
export def get-param-description [param: record] {
  $param.description? | default ""
}

# Detect schema type and major version from a parsed spec.
# Returns {schema: string, version: string} e.g. {schema: "openapi", version: "3"}
export def detect [spec: record] {
  if ($spec.openapi? | is-not-empty) {
    let major = ($spec.openapi | split row '.' | first)
    {schema: "openapi", version: $major}
  } else if ($spec.swagger? | is-not-empty) {
    let major = ($spec.swagger | split row '.' | first)
    {schema: "swagger", version: $major}
  } else {
    error make { msg: "unknown spec format: missing 'openapi' or 'swagger' field" }
  }
}

# Determine default auth scheme from root-level security + parsed auth schemes (version-independent)
export def get-default-auth [spec: record, auth_schemes: list] {
  # try root-level security array → first referenced scheme name
  let security = ($spec.security? | default [])
  if ($security | length) > 0 {
    let first_req = ($security | first)
    if (($first_req | describe) | str starts-with "record") {
      let ref_name = ($first_req | columns | first)
      # find matching parsed scheme by spec_name
      let matched = $auth_schemes | where {|s| $s.spec_name == $ref_name }
      if ($matched | length) > 0 {
        return ($matched | first | get name)
      }
    }
  }
  # fallback: first available scheme, or "bearer"
  if ($auth_schemes | length) > 0 {
    $auth_schemes | first | get name
  } else {
    "bearer"
  }
}

# Return the dispatch table: schema_type -> version -> helper closures.
# Each helper set provides: get-schemas, get-base-url, get-param-type, get-param-enum, get-body-info, get-auth-schemes.
export def helpers [] {
  {
    openapi: {
      "3": {
        get-schemas: {|spec|
          let schemas = ($spec.components?.schemas? | default {})
          let params = ($spec.components?.parameters? | default {})
          let responses = ($spec.components?.responses? | default {})
          $schemas | merge $params | merge $responses
        }
        get-base-url: {|spec|
          $spec.servers?.0?.url? | default "http://localhost"
        }
        get-param-type: {|param|
          $param.schema?.type? | default "string"
        }
        get-param-enum: {|param|
          $param.schema?.enum? | default []
        }
        get-param-collection-style: {|param|
          let t = ($param.schema?.type? | default "string")
          if $t != "array" { "scalar" } else {
            let style = ($param.style? | default "form")
            let explode = ($param.explode? | default ($style == "form"))
            match $style {
              "form" => { if $explode { "multi" } else { "csv" } }
              "spaceDelimited" => "ssv"
              "pipeDelimited" => "pipes"
              _ => "csv"
            }
          }
        }
        get-body-info: {|op, schemas|
          let request_body = $op.requestBody?
          if ($request_body | is-empty) {
            {has_body: false, body_schema: {}, content_type: "application/json"}
          } else {
            let content = ($request_body.content? | default {})
            # try content types in order of preference
            let ct_order = ["application/json" "multipart/form-data" "application/x-www-form-urlencoded"]
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
              # fallback: use first available content type
              let first_ct = ($content | columns | first | default "application/json")
              {has_body: true, body_schema: {}, content_type: $first_ct}
            }
          }
        }
        get-auth-schemes: {|spec|
          let schemes = ($spec.components?.securitySchemes? | default {})
          $schemes | transpose spec_name def | each {|entry|
            let d = $entry.def
            let desc = ($d.description? | default "")
            if ($d.type? == "http") {
              let s = ($d.scheme? | default "bearer") | str downcase
              {spec_name: $entry.spec_name, name: $s, header_name: "Authorization", prefix: ($s | str capitalize), in: "header"}
            } else if ($d.type? == "apiKey") {
              let loc = ($d.in? | default "header")
              let hdr = ($d.name? | default "Authorization")
              if $loc == "query" {
                {spec_name: $entry.spec_name, name: $"query-($hdr)", header_name: $hdr, prefix: "", in: "query"}
              } else if $loc == "cookie" {
                # Cookie-based API key
                {spec_name: $entry.spec_name, name: $"cookie-($hdr)", header_name: $hdr, prefix: "", in: "cookie"}
              } else if ($hdr | str downcase) == "authorization" {
                # detect prefix from description
                let pfx = if ($desc =~ '(?i)jwt') { "JWT" } else if ($desc =~ '(?i)static') { "STATIC" } else { "Bearer" }
                let scheme_name = ($pfx | str downcase)
                {spec_name: $entry.spec_name, name: $scheme_name, header_name: "Authorization", prefix: $pfx, in: "header"}
              } else {
                # custom header (e.g. PRIVATE-TOKEN)
                let scheme_name = ($hdr | str downcase)
                {spec_name: $entry.spec_name, name: $scheme_name, header_name: $hdr, prefix: "", in: "header"}
              }
            } else if ($d.type? == "oauth2") or ($d.type? == "openIdConnect") {
              {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
            } else {
              {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
            }
          }
        }
      }
    }
    swagger: {
      "2": {
        get-schemas: {|spec|
          $spec.definitions? | default {}
        }
        get-base-url: {|spec|
          let host = ($spec.host? | default "localhost")
          let base_path = ($spec.basePath? | default "")
          let schemes = ($spec.schemes? | default ["https"])
          let scheme = ($schemes | first)
          $"($scheme)://($host)($base_path)"
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
            match $cf { "csv" => "csv", "ssv" => "ssv", "pipes" => "pipes", "multi" => "multi", _ => "csv" }
          }
        }
        get-body-info: {|op, schemas|
          let params = ($op.parameters? | default [])
          # check for formData params first
          let form_params = $params | where {|p| ($p.in? | default "") == "formData" }
          if ($form_params | length) > 0 {
            # build a synthetic schema from formData params
            let has_file = ($form_params | where {|p| ($p.type? | default "") == "file" } | length) > 0
            let ct = if $has_file { "multipart/form-data" } else { "application/x-www-form-urlencoded" }
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
              {has_body: false, body_schema: {}, content_type: "application/json"}
            } else {
              let s = $body_param.schema?
              if ($s | is-not-empty) {
                {has_body: true, body_schema: (resolve-ref $s $schemas), content_type: "application/json"}
              } else {
                {has_body: true, body_schema: {}, content_type: "application/json"}
              }
            }
          }
        }
        get-auth-schemes: {|spec|
          let schemes = ($spec.securityDefinitions? | default {})
          $schemes | transpose spec_name def | each {|entry|
            let d = $entry.def
            if ($d.type? == "basic") {
              {spec_name: $entry.spec_name, name: "basic", header_name: "Authorization", prefix: "Basic", in: "header"}
            } else if ($d.type? == "apiKey") {
              let loc = ($d.in? | default "header")
              let hdr = ($d.name? | default "Authorization")
              if $loc == "query" {
                {spec_name: $entry.spec_name, name: $"query-($hdr)", header_name: $hdr, prefix: "", in: "query"}
              } else if ($hdr | str downcase) == "authorization" {
                let desc = ($d.description? | default "")
                let pfx = if ($desc =~ '(?i)bearer') { "Bearer" } else { "Bearer" }
                {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: $pfx, in: "header"}
              } else {
                let scheme_name = ($hdr | str downcase)
                {spec_name: $entry.spec_name, name: $scheme_name, header_name: $hdr, prefix: "", in: "header"}
              }
            } else if ($d.type? == "oauth2") {
              {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
            } else {
              {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
            }
          }
        }
      }
    }
  }
}
