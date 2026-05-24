# spec.nu — Abstraction layer for OpenAPI 3.x and Swagger 2.0 specs.
# Each helper normalizes spec-version differences so mod.nu stays spec-agnostic.

# Resolve a $ref pointer against a schemas lookup table
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

# Detect spec version. Returns "openapi3" or "swagger2".
# Errors if neither marker is found.
export def detect-version [spec: record] {
  if ($spec.openapi? | is-not-empty) {
    "openapi3"
  } else if ($spec.swagger? | is-not-empty) {
    "swagger2"
  } else {
    error make { msg: "unknown spec format: missing 'openapi' or 'swagger' field" }
  }
}

# Get all referenceable objects (schemas + parameters + responses) as a flat lookup table.
# This allows $ref resolution for any component type.
export def get-schemas [spec: record] {
  let v = (detect-version $spec)
  match $v {
    "openapi3" => {
      let schemas = ($spec.components?.schemas? | default {})
      let params = ($spec.components?.parameters? | default {})
      let responses = ($spec.components?.responses? | default {})
      $schemas | merge $params | merge $responses
    }
    "swagger2" => ($spec.definitions? | default {})
  }
}

# Get the base URL string
export def get-base-url [spec: record] {
  let v = (detect-version $spec)
  match $v {
    "openapi3" => ($spec.servers?.0?.url? | default "http://localhost")
    "swagger2" => {
      let host = ($spec.host? | default "localhost")
      let base_path = ($spec.basePath? | default "")
      let schemes = ($spec.schemes? | default ["https"])
      let scheme = ($schemes | first)
      $"($scheme)://($host)($base_path)"
    }
  }
}

# Get the type from a parameter (path or query)
export def get-param-type [param: record] {
  # openapi3 nests type under schema, swagger2 has it directly
  if ($param.schema? | is-not-empty) {
    $param.schema.type? | default "string"
  } else {
    $param.type? | default "string"
  }
}

# Get the enum values from a parameter
export def get-param-enum [param: record] {
  if ($param.schema? | is-not-empty) {
    $param.schema.enum? | default []
  } else {
    $param.enum? | default []
  }
}

# Get the description from a parameter
export def get-param-description [param: record] {
  $param.description? | default ""
}

# Extract body info from an operation.
# Returns {has_body: bool, body_schema: record}
export def get-body-info [op: record, schemas: record, version: string] {
  match $version {
    "openapi3" => {
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
    "swagger2" => {
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

# Filter parameters: return only path/query params (exclude body params used in swagger2)
export def get-non-body-params [params: list] {
  $params | where {|p|
    let loc = ($p.in? | default "")
    $loc in ["path" "query"]
  }
}
