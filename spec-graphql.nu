# spec-graphql.nu — GraphQL introspection dispatch table.
# Extracted from spec.nu; returns the closure record for graphql/introspection.

use spec.nu [unwrap-gql-type gql-leaf-kind gql-scalar-to-openapi]

# Return the GraphQL introspection helper closures (flat record).
export def helpers [] {
  {
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
    get-response-type: {|op, spec, schemas|
      # We'll compute this at the mod.nu level instead
      "record"
    }
    get-auth-schemes: {|spec| [] }
  }
}
