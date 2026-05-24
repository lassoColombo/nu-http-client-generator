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

# Filter parameters: return only path/query params (version-independent)
export def get-non-body-params [params: list] {
  $params | where {|p|
    let loc = ($p.in? | default "")
    $loc in ["path" "query"]
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

# Return the dispatch table: schema_type -> version -> helper closures.
# Each helper set provides: get-schemas, get-base-url, get-param-type, get-param-enum, get-body-info.
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
        get-body-info: {|op, schemas|
          let request_body = $op.requestBody?
          if ($request_body | is-empty) {
            {has_body: false, body_schema: {}}
          } else {
            let content = ($request_body.content? | default {})
            let json_content = ($content | get -o "application/json")
            if ($json_content | is-not-empty) {
              let s = $json_content.schema?
              if ($s | is-not-empty) {
                {has_body: true, body_schema: (resolve-ref $s $schemas)}
              } else {
                {has_body: true, body_schema: {}}
              }
            } else {
              {has_body: true, body_schema: {}}
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
        get-body-info: {|op, schemas|
          let params = ($op.parameters? | default [])
          let body_param = $params | where {|p| ($p.in? | default "") == "body" } | first | default null
          if ($body_param | is-empty) {
            {has_body: false, body_schema: {}}
          } else {
            let s = $body_param.schema?
            if ($s | is-not-empty) {
              {has_body: true, body_schema: (resolve-ref $s $schemas)}
            } else {
              {has_body: true, body_schema: {}}
            }
          }
        }
      }
    }
  }
}
