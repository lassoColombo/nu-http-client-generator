# swagger2.nu — Swagger 2.0 to OpenAPI 3 conversion.
#
# The generator reads one format. A Swagger 2.0 document is rewritten into the
# OpenAPI 3 shape `spec.nu` reads (`to-openapi3`), once, before modelling, so
# nothing downstream knows Swagger 2 exists. The rewrite covers what the reader
# consults:
#
#   host, basePath, schemes, x-ms-parameterized-host  -> servers
#   securityDefinitions (basic -> http/basic)         -> components.securitySchemes
#   param type/items/enum/default/format              -> param.schema
#   param collectionFormat                            -> param.style/explode
#   body and formData params, consumes                -> requestBody
#   response schema, produces                         -> response.content
#   produces, for undocumented responses              -> a `default` response
#
# The rewrite only adds: each OpenAPI 3 spelling goes next to the Swagger 2
# one, and nothing a `$ref` can point at moves. Specs do point into
# operations (`#/paths/~1word~1%7Bid%7D/get/responses/200/schema/items/…`,
# `#/paths/…/parameters/2`), so a response keeps its `schema`, a param its
# Swagger 2 keys, and body/formData params stay in their lists, which model
# filters by location.

use spec.nu
use ../log.nu

const METHODS = [get put post delete options head patch]

# The parameter keys that describe its value, which OpenAPI 3 keeps under
# `schema`. `collectionFormat` is not one: OpenAPI 3 spells it as
# `style`/`explode`.
const SCHEMA_KEYS = [
  type format items default enum maximum exclusiveMaximum minimum exclusiveMinimum
  maxLength minLength pattern maxItems minItems uniqueItems multipleOf
]

# Rebuild a record with every value mapped by `f`, which receives the key and
# the value. An empty record stays a record (`transpose` would make it a list).
def map-values [f: closure]: record -> record {
  let r = $in
  if ($r | is-empty) { return {} }
  $r | transpose k v | each {|e| {k: $e.k, v: (do $f $e.k $e.v)} } | transpose -r -d
}

# A non-body parameter as OpenAPI 3: its value facts are copied under
# `schema`, and an array's `collectionFormat` is spelled as `style`/`explode`
# (`array-style`). OpenAPI 3 keys a Swagger 2 document should not have
# (`schema`, `style`, `explode`, `content`; the httpbin spec mixes them in)
# are replaced, as the Swagger 2 reader always ignored them. A `$ref` is left
# alone (its target is converted where it lives), and so are body and
# formData params, which `request-body` turns into the requestBody.
def convert-param [p: any]: nothing -> any {
  if not (($p | describe) | str starts-with "record") { return $p }
  if ("$ref" in ($p | columns)) or (($p.in? | default "") in [body formData]) { return $p }
  let present = ($SCHEMA_KEYS | where {|k| $k in ($p | columns) })
  let schema = if ($present | is-empty) { {} } else { $p | select ...$present }
  $p | reject -o schema style explode content | insert schema $schema | merge (array-style $p)
}

# An array param's `collectionFormat` (csv when absent, the Swagger 2
# default) as OpenAPI 3 `style`/`explode`; {} for any other param. `tsv` has
# no OpenAPI 3 style; it becomes `tabDelimited`, which spec reads like the
# standard delimiters.
def array-style [p: record]: nothing -> record {
  if ($p.type? != "array") { return {} }
  match ($p.collectionFormat? | default "csv") {
    "multi" => {style: form, explode: true}
    "ssv" => {style: spaceDelimited, explode: false}
    "pipes" => {style: pipeDelimited, explode: false}
    "tsv" => {style: tabDelimited, explode: false}
    _ => {style: form, explode: false}
  }
}

# The requestBody of one operation, from the body or formData params it
# declares or inherits from its path item; null when it has none. An op's own
# param replaces an inherited one with the same name and location, and an own
# `body` param replaces the inherited one whatever either is named: Swagger 2
# allows one per operation. formData fields win over a body param.
#
# formData fields become an object schema, sent as multipart when a field is
# a file or the op (else the document) `consumes` multipart, else urlencoded.
# Each field keeps `items`, an array field's `collectionFormat` becomes the
# media type's `encoding` for it, as a param's becomes its style, and a
# `type: file` field stays `file`, which render types as a path. A body
# param is sent as the first
# `consumes` type nushell can encode: JSON when listed (or `*/*`, which `http`
# rejects as a content type), then merge-patch JSON (the safe Kubernetes PATCH
# type), then the first concrete type.
def request-body [op: record, inherited: list, doc: record]: nothing -> any {
  let key = {|p| if ($p.in? == "body") { "body" } else { $"($p.name? | default ''):($p.in? | default '')" } }
  let own = ($op.parameters? | default [] | each {|p| spec resolve-ref $p $doc })
  let own_keys = ($own | each $key)
  let params = ($inherited | where {|p| (do $key $p) not-in $own_keys } | append $own)
  let consumes = ($op.consumes? | default ($doc.consumes? | default []))

  let form = ($params | where {|p| ($p.in? | default "") == "formData" })
  if ($form | is-not-empty) {
    let has_file = ($form | any {|p| ($p.type? | default "") == "file" })
    let ct = if $has_file or ($spec.CT_MULTIPART in $consumes) { $spec.CT_MULTIPART } else { $spec.CT_FORM }
    mut props = {}
    mut required = []
    mut encoding = {}
    for fp in $form {
      let prop = {type: ($fp.type? | default "string"), description: ($fp.description? | default ""), enum: ($fp.enum? | default [])}
      let prop = if ($fp.items? | is-not-empty) { $prop | insert items $fp.items } else { $prop }
      $props = ($props | insert $fp.name $prop)
      if ($fp.type? == "array") {
        $encoding = ($encoding | insert $fp.name (array-style $fp))
      }
      if ($fp.required? | default false) {
        $required = ($required | append $fp.name)
      }
    }
    let media = {schema: {type: "object", properties: $props, required: $required}}
    return {content: {$ct: (if ($encoding | is-empty) { $media } else { $media | insert encoding $encoding })}}
  }

  let bodies = ($params | where {|p| ($p.in? | default "") == "body" })
  if ($bodies | is-empty) { return null }
  if ($bodies | length) > 1 {
    log warn $"operation ($op.operationId? | default '<no operationId>') declares ($bodies | length) body params; Swagger 2 allows one, using '($bodies | first | get -o name)'"
  }
  let body = ($bodies | first)
  let ct = if ($consumes | is-empty) or ($spec.CT_JSON in $consumes) or ("*/*" in $consumes) {
    $spec.CT_JSON
  } else if ("application/merge-patch+json" in $consumes) {
    "application/merge-patch+json"
  } else {
    $consumes | where {|x| $x != "*/*" } | first | default $spec.CT_JSON
  }
  let media = if ($body.schema? | is-not-empty) { {schema: $body.schema} } else { {} }
  {content: {$ct: $media}}
}

# A response as OpenAPI 3: its `schema` is served as each type the operation
# produces, so the reader derives the same Accept types and success schema
# from it. A `$ref` into `#/responses` is inlined first, since one shared
# response can sit under operations that produce different types.
def convert-response [resp: any, produces: list<string>, doc: record]: nothing -> any {
  let r = (spec resolve-ref $resp $doc)
  if not (($r | describe) | str starts-with "record") { return $resp }
  let media = if ($r.schema? == null) { {} } else { {schema: $r.schema} }
  $r | upsert content ($produces | reduce --fold {} {|ct, acc| $acc | upsert $ct $media })
}

# One operation: params converted in place, the requestBody built from the
# body/formData params, responses given `content`. `produces` is the op's own
# list, else the document's, else JSON. It describes every response, the
# undocumented ones included, which OpenAPI 3 spells as a `default` response:
# an op without one gets one, so an op documenting only a 302 still accepts
# its `image/png`.
def convert-operation [op: record, inherited: list, doc: record]: nothing -> record {
  let own_produces = ($op.produces? | default [])
  let produces = if ($own_produces | is-not-empty) { $own_produces } else { $doc.produces? | default [] }
  let produces = if ($produces | is-empty) { [$spec.CT_JSON] } else { $produces | uniq }
  let body = (request-body $op $inherited $doc)
  let op = if ($op.parameters? == null) { $op } else { $op | update parameters ($op.parameters | each {|p| convert-param $p }) }
  let op = if not (($op.responses? | default {} | describe) | str starts-with "record") { $op } else {
    let responses = ($op.responses? | default {} | map-values {|code, r|
      if ($code | str starts-with "x-") { $r } else { convert-response $r $produces $doc }
    })
    let responses = if ("default" in ($responses | columns)) { $responses } else {
      $responses | insert default (convert-response {description: ""} $produces $doc)
    }
    $op | upsert responses $responses
  }
  if ($body == null) { $op } else { $op | upsert requestBody $body }
}

# One path item. A path-item `$ref` is followed first (a dangling one is left
# for model to report). Path-level params are converted in place, and every
# operation inherits the body/formData ones among them.
def convert-path-item [item: any, doc: record]: nothing -> any {
  let item = (spec resolve-ref $item $doc)
  if not (($item | describe) | str starts-with "record") or ("$ref" in ($item | columns)) { return $item }
  let inherited = ($item.parameters? | default [] | each {|p| spec resolve-ref $p $doc })
  $item | map-values {|key, val|
    if $key == "parameters" {
      $val | each {|p| convert-param $p }
    } else if ($key in $METHODS) and (($val | describe) | str starts-with "record") {
      convert-operation $val $inherited $doc
    } else {
      $val
    }
  }
}

# Azure data-plane specs template the host with the `x-ms-parameterized-host`
# extension (`{searchServiceName}.{searchDnsSuffix}`) and set `host:
# azure.local` as a sentinel. A placeholder whose parameter has a `default`
# is substituted; the others stay as `{var}`, so `url parse` fails loudly
# instead of a call silently going to azure.local. Null without the extension.
def resolve-parameterized-host [doc: record] {
  let pham = ($doc | get -o "x-ms-parameterized-host")
  if ($pham | is-empty) { return null }
  let tmpl = ($pham | get -o hostTemplate | default "")
  if ($tmpl | is-empty) { return null }
  let use_scheme = ($pham | get -o useSchemePrefix | default true)
  let defaults = ($pham | get -o parameters | default [] | reduce -f {} {|p, acc|
    let resolved = (spec resolve-ref $p $doc)
    let name = ($resolved.name? | default null)
    let def = ($resolved.default? | default null)
    if ($name != null) and ($def != null) { $acc | upsert $name ($def | into string) } else { $acc }
  })
  let placeholders = ($tmpl | parse --regex '\{(?P<n>[A-Za-z0-9_]+)\}' | get n | uniq)
  let full = ($placeholders | reduce -f $defaults {|n, acc|
    if ($n in ($acc | columns)) { $acc } else { $acc | upsert $n $"{($n)}" }
  })
  let substituted = ($full | format pattern $tmpl)
  if $use_scheme {
    let raw_schemes = ($doc.schemes? | default [])
    let scheme = (if ($raw_schemes | is-empty) { "https" } else { $raw_schemes | first })
    $"($scheme)://($substituted)"
  } else {
    $substituted
  }
}

# A `basePath` may hold `{name}` templates no parameter declares
# (`/v2.0/{apikey}`); `url parse` would percent-encode the braces into a
# guaranteed 404. They are dropped, and the caller substitutes the real value
# with `--base-url`.
def strip-base-path-template [base_path: string]: nothing -> string {
  if not ($base_path =~ '\{[^}]+\}') { return $base_path }
  let cleaned = ($base_path | str replace --all --regex '/\{[^}]+\}' '' | str replace --all --regex '\{[^}]+\}' '')
  log warn $"basePath contains undeclared template variable\(s\); stripped to '($cleaned)'. Pass --base-url at call time to substitute."
  $cleaned
}

# The servers: one per declared scheme (https when none) on `host` + `basePath`,
# or the single parameterized host. Without `host` the API is on the host
# serving the document, so the server is the relative `basePath`, which spec
# anchors like an OpenAPI 3 relative server URL.
def servers [doc: record]: nothing -> list<record> {
  let base_path = (strip-base-path-template ($doc.basePath? | default ""))
  let parameterized = (resolve-parameterized-host $doc)
  let urls = if ($parameterized != null) {
    [$"($parameterized)($base_path)"]
  } else if ($doc.host? | is-empty) {
    [$"/($base_path | str trim --left --char '/')"]
  } else {
    let host = $doc.host
    let schemes = ($doc.schemes? | default [])
    let schemes = if ($schemes | is-empty) { ["https"] } else { $schemes }
    $schemes | each {|s| {scheme: $s, host: $host, path: $base_path} | url join }
  }
  $urls | each {|u| {url: ($u | str trim --right --char '/' | if ($in | is-empty) { "/" } else { $in })} }
}

# `type: basic` is OpenAPI 3's `http` scheme `basic`; apiKey and oauth2 read
# the same in both formats.
def convert-security-scheme [d: any]: nothing -> any {
  if (($d | describe) | str starts-with "record") and ($d.type? == "basic") {
    $d | update type "http" | upsert scheme "basic"
  } else {
    $d
  }
}

# Rewrite a Swagger 2.0 document as OpenAPI 3 (see the file header).
export def to-openapi3 [doc: record]: nothing -> record {
  let paths = ($doc.paths? | default {} | map-values {|path, item|
    if ($path | str starts-with "x-") { $item } else { convert-path-item $item $doc }
  })
  let parameters = if (($doc.parameters? | describe) | str starts-with "record") {
    $doc.parameters | map-values {|_, p| convert-param $p }
  } else {
    $doc.parameters?
  }
  let schemes = ($doc.securityDefinitions? | default {} | map-values {|_, d| convert-security-scheme $d })
  $doc
  | upsert openapi "3.0.3"
  | upsert servers (servers $doc)
  | upsert components {securitySchemes: $schemes}
  | upsert paths $paths
  | if ($parameters == null) { $in } else { $in | upsert parameters $parameters }
}
