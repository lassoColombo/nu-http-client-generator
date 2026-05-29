# spec-oa3.nu — OpenAPI 3.x dispatch closures.
# Extracted from the unified dispatch table in spec.nu.

use spec.nu [
  CT_JSON CT_MULTIPART CT_FORM CT_PRIORITY
  DEFAULT_HOST RESPONSE_CODE_PRIORITY
]
use spec.nu
use warn.nu

# ── Private helpers (moved from spec.nu) ───────────────────────────

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

# ── Exported dispatch record ───────────────────────────────────────

export def helpers [] {
  {
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
        let rb = (spec resolve-ref $request_body $schemas)
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
                $found_schema = (spec resolve-ref $s $schemas)
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
    get-response-type: {|op, spec, schemas|
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
      spec schema-to-nu-type $found_schema $schemas
    }
    get-auth-schemes: {|spec|
      let schemes = ($spec.components?.securitySchemes? | default {})
      $schemes | transpose spec_name def | each {|entry|
        let d = $entry.def
        if ($d.type? == "http") {
          let s = ($d.scheme? | default "bearer") | str downcase
          {spec_name: $entry.spec_name, name: $s, header_name: "Authorization", prefix: ($s | str capitalize), in: "header"}
        } else {
          let shared = (spec build-auth-scheme $entry)
          if ($shared != null) { $shared } else {
            warn fallback $"unknown security scheme type '($d.type? | default 'unset')' for '($entry.spec_name)', defaulting to bearer"
            {spec_name: $entry.spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
          }
        }
      }
    }
  }
}
