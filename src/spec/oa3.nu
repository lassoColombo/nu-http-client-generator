# oa3.nu — OpenAPI 3.x answers to the `helpers` dispatch record (see spec.nu):
# servers, request/response media types, parameter facts, security schemes.

use spec.nu
use ../log.nu

# ── Private helpers ───────────────────────────────────────────────

# Resolve a server-URL template against a record of OAS server `variables`,
# with optional per-call overrides. Backfills any `{var}` placeholder that
# isn't declared in `variables[]` with empty string — preserves the old
# lenient behavior (str-replace silently no-op'd unknown vars), since
# `format pattern` errors on missing keys.
def resolve-server-template [raw: string, vars: record, overrides: record = {}]: nothing -> string {
  if ($vars | is-empty) and ($overrides | is-empty) {
    return $raw
  }
  let defaults = ($vars | transpose name def | reduce -f {} {|v, acc|
    let val = ($overrides | get -o $v.name | default ($v.def.default? | default ""))
    $acc | upsert $v.name $val })
  let placeholders = ($raw | parse --regex '\{(?P<n>[A-Za-z0-9_]+)\}' | get n | uniq)
  let full = ($placeholders | reduce -f $defaults {|n, acc|
    if ($n in ($acc | columns)) { $acc } else { $acc | upsert $n "" }
  })
  $full | format pattern $raw
}

# Resolve an OA3 server object to an absolute URL: `{var}` placeholders take
# the per-call `overrides`, else the variable's `default`; a relative URL is
# anchored on localhost; a trailing slash is dropped so path joins stay single.
def resolve-server-url [server: record, overrides: record = {}] {
  let raw = ($server.url? | default $"http://($spec.DEFAULT_HOST)")
  let substituted = (resolve-server-template $raw ($server.variables? | default {}) $overrides)
  let absolute = if ($substituted | str starts-with "/") { $"http://($spec.DEFAULT_HOST)($substituted)" } else { $substituted }
  $absolute | str trim --right --char '/'
}

# Every server URL the spec mentions, for `--base-url` completion: each root
# server followed by one URL per enum value of each of its variables, then the
# path-level and operation-level overrides, in document order.
def collect-oa3-urls [spec_data: record] {
  let root = ($spec_data.servers? | default [] | each {|s|
    let variants = ($s.variables? | default {} | items {|name, def|
      $def.enum? | default [] | each {|ev| resolve-server-url $s {$name: $ev} }
    } | flatten)
    [(resolve-server-url $s)] ++ $variants
  } | flatten)
  let overrides = ($spec_data.paths? | default {} | spec drop-vendor-extensions | values | each {|item|
    let op_servers = ($item | items {|method, op|
      if ($method in [get post put patch delete head options]) and (($op | describe) | str starts-with "record") { $op.servers? | default [] } else { [] }
    } | flatten)
    ($item.servers? | default []) ++ $op_servers
  } | flatten | each {|s| resolve-server-url $s })
  $root ++ $overrides | uniq
}

def get-base-url-impl [spec_data: record] {
  let servers = ($spec_data.servers? | default [])
  if ($servers | is-not-empty) {
    resolve-server-url ($servers | first)
  } else {
    $"http://($spec.DEFAULT_HOST)"
  }
}

def get-body-info-impl [op: record, doc: record] {
  let request_body = $op.requestBody?
  if ($request_body | is-empty) {
    {has_body: false, body_schema: {}, content_type: $spec.CT_JSON}
  } else {
    let content = ((spec resolve-ref $request_body $doc).content? | default {})
    # Prefer a media type the client can encode; with none declared (text/plain,
    # text/xml, application/vnd.X+json, …) take the first one and its schema, so
    # model can still derive `body_scalar_type` for a typed `--body` flag.
    let preferred = ($spec.CT_PRIORITY | where {|ct| $content | get -o $ct | is-not-empty } | get -o 0)
    let declared = ($content | columns | get -o 0 | default $spec.CT_JSON)
    # An empty media-type key (spoonacular writes `content: {"": {schema}}`) or
    # a bare `*/*` is no content type a request can carry: fall back to JSON.
    let ct = ($preferred | default (if ($declared | is-empty) or ($declared == "*/*") { $spec.CT_JSON } else { $declared }))
    # The schema must come from the media type the client will send, not the
    # first one declared: `application/xml` listed before `application/json`
    # would otherwise expose the XML schema's fields on a JSON request.
    let s = ($content | get -o $ct | default ($content | get -o $declared | default {}) | get -o schema)
    let schema = if ($s | is-not-empty) { spec resolve-ref $s $doc } else { {} }
    {has_body: true, body_schema: $schema, content_type: $ct}
  }
}

# A response may be a `$ref` into `#/components/responses` (apideck, chompthis
# do this for every operation), so each one is resolved before its `content`
# is read — here and in get-response-schemas-impl.
def get-response-content-types-impl [op: record, doc: record] {
  let responses = ($op.responses? | default {})
  $responses | transpose code resp | where {|r|
    ($r.code | str starts-with "2") or ($r.code == "default") or ($r.code =~ '^[12][xX]{2}$')
  } | each {|r|
    (spec resolve-ref $r.resp $doc).content? | default {} | columns
  } | flatten | uniq | if ($in | is-empty) { [$spec.CT_JSON] } else { $in }
}

# The success responses' schemas (unresolved — model resolves and walks
# them), best candidate first (see `spec success-response-codes`); responses
# without a schema are skipped. The first entry is the return type; the
# others still contribute a discriminator.
def get-response-schemas-impl [op: record, doc: record] {
  let responses = ($op.responses? | default {})
  spec success-response-codes $responses | each {|code|
    let resp = (spec resolve-ref ($responses | get -o $code) $doc)
    if ($resp | is-empty) { return null }
    let content = ($resp.content? | default {})
    # Prefer application/json's schema; if this response has no JSON media
    # (e.g. text/plain, application/xml, a vendor +json variant), fall back
    # to the first media type that declares a schema. Without this, a
    # non-JSON scalar response (`text/plain` `{type: string}`) derives `any`
    # and loses the typed `oneof<…>` output annotation.
    let json_schema = ($content | get -o "application/json" | default {} | get -o schema)
    if ($json_schema | is-not-empty) {
      $json_schema
    } else {
      $content | values | each {|m| $m | get -o schema } | get -o 0
    }
  }
}

def get-auth-schemes-impl [spec_data: record] {
  let schemes = ($spec_data.components?.securitySchemes? | default {})
  $schemes | items {|spec_name, d|
    if ($d.type? == "http") {
      let s = ($d.scheme? | default "bearer") | str lowercase
      {spec_name: $spec_name, name: $s, header_name: "Authorization", prefix: ($s | str capitalize), in: "header"}
    } else {
      let shared = (spec build-auth-scheme {spec_name: $spec_name, def: $d})
      if ($shared != null) { $shared } else {
        log warn $"unknown security scheme type '($d.type? | default 'unset')' for '($spec_name)', defaulting to bearer"
        {spec_name: $spec_name, name: "bearer", header_name: "Authorization", prefix: "Bearer", in: "header"}
      }
    }
  }
}

# ── Exported dispatch record ───────────────────────────────────────

export def helpers [] {
  {
    get-base-url: {|spec| get-base-url-impl $spec }
    get-all-urls: {|spec| collect-oa3-urls $spec }
    # The operation's own server, else its path item's; null when neither
    # overrides the root servers.
    get-op-base-url: {|op, path_item|
      let server = ($op.servers?.0? | default $path_item.servers?.0?)
      if ($server == null) { null } else { resolve-server-url $server }
    }
    # A parameter's value facts, read from its `schema` (a `$ref` resolved).
    # A `content`-typed param (OAS 3 §4.8.12.5) is one serialized value whose
    # schema says nothing about the wire, so it reads as an empty schema: a
    # scalar `string`. `default`/`format`/`example` fall back to the param
    # itself, where some specs put them.
    param-facts: {|param, doc|
      let raw = if ($param.content? | is-not-empty) { {} } else { spec resolve-ref ($param.schema? | default {}) $doc }
      let schema = if (($raw | describe) | str starts-with "record") { $raw } else { {} }
      # normalize-type: OAS 3.1 `type: [array, "null"]` is still an array
      let t = (spec normalize-type ($schema.type? | default "string"))
      let style = ($param.style? | default "form")
      let explode = ($param.explode? | default ($style == "form"))
      {
        type: $t
        # `list<string>` / `list<int>` in the signature instead of bare `list`;
        # null when the items have no usable primitive type.
        items_type: (if $t == "array" { spec normalize-type ($schema.items?.type? | default null) } else { null })
        enum: ($schema.enum? | default [])
        # For an object value the emitted serializer reads "multi" as exploded
        # `k=v` pairs and "csv" as `name=k,v,k,v` (OAS 3 §4.8.12.4).
        collection_style: (if $style == "deepObject" { "deepObject" } else if $t not-in ["array" "object"] { "scalar" } else {
          match $style {
            "form" => { if $explode { "multi" } else { "csv" } }
            "spaceDelimited" => "ssv"
            "pipeDelimited" => "pipes"
            _ => "csv"
          }
        })
        default: ($schema.default? | default $param.default?)
        format: ($schema.format? | default $param.format?)
        example: ($schema.example? | default ($param.example? | default ($param | get -o "x-example")))
        nullable: (spec is-nullable $schema)
      }
    }
    get-body-info: {|op, doc| get-body-info-impl $op $doc }
    get-response-content-types: {|op, doc| get-response-content-types-impl $op $doc }
    get-response-schemas: {|op, doc| get-response-schemas-impl $op $doc }
    get-auth-schemes: {|spec| get-auth-schemes-impl $spec }
  }
}
