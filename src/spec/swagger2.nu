# spec-swagger2.nu — Swagger 2.0 dispatch closures.
# Extracted from the unified dispatch table in spec.nu.

use spec.nu
use ../log.nu

# ── Private helpers ───────────────────────────────────────────────

# Issue 40.A: Azure data-plane specs use the `x-ms-parameterized-host` vendor
# extension to template the host (e.g. `{searchServiceName}.{searchDnsSuffix}`)
# and set `host: "azure.local"` as a sentinel. Honor the extension when present;
# substitute placeholders whose referenced parameter has a `default:`, and leave
# unresolved placeholders in place (mirrors cycle 16.A's OAS3 resolve-server-url
# behavior — `url parse` will then fail loudly on the unsubstituted `{var}`
# instead of silently dispatching to azure.local).
def resolve-parameterized-host [spec_data: record]: nothing -> string {
  let pham = ($spec_data | get -o "x-ms-parameterized-host")
  if ($pham | is-empty) { return null }
  let tmpl = ($pham | get -o hostTemplate | default "")
  if ($tmpl | is-empty) { return null }
  let use_scheme = ($pham | get -o useSchemePrefix | default true)
  # Resolve each {var} placeholder by looking up its parameter in the
  # spec-level `parameters` table and reading the parameter's `default:`.
  # Parameters without defaults stay as `{var}` so `url parse` errors loudly.
  let params = ($pham | get -o parameters | default [])
  let spec_params = ($spec_data | get -o parameters | default {})
  let defaults = ($params | reduce -f {} {|p, acc|
    let resolved = if (($p | describe) | str starts-with "record") and ("$ref" in ($p | columns)) {
      let ref_path = ($p | get "$ref")
      let parts = ($ref_path | split row '/')
      let key = ($parts | last)
      ($spec_params | get -o $key | default {})
    } else { $p }
    let name = ($resolved.name? | default null)
    let def = ($resolved.default? | default null)
    if ($name != null) and ($def != null) { $acc | upsert $name ($def | into string) } else { $acc }
  })
  # Apply substitutions; placeholders not in `defaults` survive unchanged.
  let placeholders = ($tmpl | parse --regex '\{(?P<n>[A-Za-z0-9_]+)\}' | get n | uniq)
  let full = ($placeholders | reduce -f $defaults {|n, acc|
    if ($n in ($acc | columns)) { $acc } else { $acc | upsert $n $"{($n)}" }
  })
  let substituted = ($full | format pattern $tmpl)
  if $use_scheme {
    let raw_schemes = ($spec_data.schemes? | default [])
    let scheme = (if ($raw_schemes | is-empty) { "https" } else { $raw_schemes | first })
    $"($scheme)://($substituted)"
  } else {
    $substituted
  }
}

def get-base-url-impl [spec_data: record] {
  let parameterized = (resolve-parameterized-host $spec_data)
  if ($parameterized != null) {
    let base_path = (strip-base-path-template ($spec_data.basePath? | default ""))
    return ($"($parameterized)($base_path)" | str trim --right --char '/')
  }
  let host = ($spec_data.host? | default $spec.DEFAULT_HOST)
  let base_path = (strip-base-path-template ($spec_data.basePath? | default ""))
  let raw_schemes = ($spec_data.schemes? | default [])
  let scheme = (if ($raw_schemes | is-empty) { "https" } else { $raw_schemes | first })
  {scheme: $scheme, host: $host, path: $base_path} | url join | str trim --right --char '/'
}

def get-all-urls-impl [spec_data: record] {
  let parameterized = (resolve-parameterized-host $spec_data)
  if ($parameterized != null) {
    let base_path = (strip-base-path-template ($spec_data.basePath? | default ""))
    return [($"($parameterized)($base_path)" | str trim --right --char '/')]
  }
  let host = ($spec_data.host? | default $spec.DEFAULT_HOST)
  let base_path = (strip-base-path-template ($spec_data.basePath? | default ""))
  let raw_schemes = ($spec_data.schemes? | default [])
  let schemes = (if ($raw_schemes | is-empty) { ["https"] } else { $raw_schemes })
  $schemes | each {|s| {scheme: $s, host: $host, path: $base_path} | url join | str trim --right --char '/' }
}

# Issue 33.B: Swagger-2 `basePath` may contain `{name}` template variables
# (e.g. `/v2.0/{apikey}`) that are never declared as path parameters. Leaving
# them in the path means `url parse` percent-encodes the braces (`%7B…%7D`),
# producing guaranteed-404 URLs. Drop unresolved templates entirely; the user
# must override via `--base-url` to substitute the missing value.
def strip-base-path-template [base_path: string]: nothing -> string {
  if not ($base_path =~ '\{[^}]+\}') { return $base_path }
  let cleaned = ($base_path | str replace --all --regex '/\{[^}]+\}' '' | str replace --all --regex '\{[^}]+\}' '')
  log warn $"basePath contains undeclared template variable\(s\); stripped to '($cleaned)'. Pass --base-url at call time to substitute."
  $cleaned
}

def get-body-info-impl [op: record, schemas: record, spec_data: record] {
  # Resolve $ref-only param entries (e.g. Kubernetes spec shares body/query
  # params under #/parameters/...). Without this the body/form filter below
  # never finds them and the op is silently classified as no-body.
  let params = ($op.parameters? | default []) | each {|p| spec resolve-ref $p $schemas }
  let form_params = $params | where {|p| ($p.in? | default "") == "formData" }
  if ($form_params | is-not-empty) {
    let has_file = ($form_params | any {|p| ($p.type? | default "") == "file" })
    let ct = if $has_file { $spec.CT_MULTIPART } else { $spec.CT_FORM }
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
      {has_body: false, body_schema: {}, content_type: $spec.CT_JSON}
    } else {
      # Issue 28.A: honour Swagger-2 `consumes` (op-level, then doc-level).
      # Picker: prefer application/json (since `*/*` accepts it and most specs
      # list it explicitly), then application/merge-patch+json (safest k8s
      # PATCH default), then first non-wildcard. Wildcard `*/*` collapses to
      # application/json because `http patch` rejects `*/*` as a CT header.
      let consumes_global = ($spec_data.consumes? | default [])
      let consumes_op = ($op.consumes? | default $consumes_global)
      let picked_ct = (
        if ($consumes_op | is-empty) or ($spec.CT_JSON in $consumes_op) or ("*/*" in $consumes_op) {
          $spec.CT_JSON
        } else if ("application/merge-patch+json" in $consumes_op) {
          "application/merge-patch+json"
        } else {
          $consumes_op | where {|x| $x != "*/*" } | first | default $spec.CT_JSON
        }
      )
      let s = $body_param.schema?
      if ($s | is-not-empty) {
        {has_body: true, body_schema: (spec resolve-ref $s $schemas), content_type: $picked_ct}
      } else {
        {has_body: true, body_schema: {}, content_type: $picked_ct}
      }
    }
  }
}

def get-response-content-types-impl [op: record, spec_data: record] {
  let op_produces = ($op.produces? | default [])
  let global_produces = ($spec_data.produces? | default [])
  let types = if ($op_produces | is-not-empty) { $op_produces } else { $global_produces }
  if ($types | is-empty) { [$spec.CT_JSON] } else { $types | uniq }
}

def get-response-type-impl [op: record, spec_data: record, schemas: record] {
  let responses = ($op.responses? | default {})
  mut found_schema = null
  for code in $spec.RESPONSE_CODE_PRIORITY {
    if ($found_schema == null) {
      let resp = ($responses | get -o $code)
      if ($resp | is-not-empty) {
        let s = ($resp.schema? | default null)
        if ($s | is-not-empty) { $found_schema = $s }
      }
    }
  }
  if ($found_schema == null) { return "any" }
  spec schema-to-nu-type $found_schema $schemas
}

# Explicit success status codes (2xx/3xx numerics) declared by the operation.
# Ignores `default` and documented error codes — neither enumerates a concrete
# acceptable set, so those fall callers back to `< 400`.
def get-success-codes-impl [op: record]: nothing -> list<int> {
  $op.responses? | default {} | columns
    | where {|c| $c =~ '^[23][0-9][0-9]$' }
    | each {|c| $c | into int }
    | sort
}

def get-auth-schemes-impl [spec_data: record] {
  let schemes = ($spec_data.securityDefinitions? | default {})
  $schemes | items {|spec_name, d|
    if ($d.type? == "basic") {
      {spec_name: $spec_name, name: "basic", header_name: "Authorization", prefix: "Basic", in: "header"}
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
    get-schemas: {|spec|
      {
        definitions: ($spec.definitions? | default {})
        parameters: ($spec.parameters? | default {})
        responses: ($spec.responses? | default {})
      }
    }
    get-base-url: {|spec| get-base-url-impl $spec }
    get-all-urls: {|spec| get-all-urls-impl $spec }
    resolve-server-url: {|server| $server.url? | default null }
    get-param-type: {|param|
      $param.type? | default "string"
    }
    get-param-items-type: {|param|
      # Swagger 2 puts the items schema directly on the param, not under
      # `.schema`. Returns null for non-array params.
      let t = ($param.type? | default null)
      if $t != "array" { return null }
      $param.items?.type? | default null
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
    get-body-info: {|op, schemas, spec| get-body-info-impl $op $schemas $spec }
    get-response-content-types: {|op, spec| get-response-content-types-impl $op $spec }
    get-success-codes: {|op| get-success-codes-impl $op }
    get-response-type: {|op, spec, schemas| get-response-type-impl $op $spec $schemas }
    get-auth-schemes: {|spec| get-auth-schemes-impl $spec }
  }
}
