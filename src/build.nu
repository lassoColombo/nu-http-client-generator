# build.nu — OpenAPI/Swagger command-model builder.
#
# Extracts operations from an OpenAPI 3.x / Swagger 2.0 spec and produces
# the command model consumed by render.nu.

use spec/spec.nu
use render.nu
use log.nu

# ─── Spec loading ──────────────────────────────────────────────────
#
# The URL path goes through `spec fetch-text` (raw fetch + UTF-8 decode)
# instead of `http get`'s auto-parser — see the helper for the rationale.

# Load an OpenAPI/Swagger spec from a local file or a URL.
# Returns {data: record, source: string}.
export def load-spec [source: string, headers: record = {}] {
  if ($source | str starts-with "http://") or ($source | str starts-with "https://") {
    let body = (spec fetch-text $source $headers)
    {data: (parse-spec-text $body $source), source: $source}
  } else {
    let expanded = ($source | path expand | into string)
    {data: (open $expanded), source: $expanded}
  }
}

# Parse a raw spec body, picking JSON or YAML based on the source URL's
# extension and falling back to "try JSON then YAML" when there's no hint.
def parse-spec-text [body: string, source: string]: nothing -> any {
  let parsed = if ($source | str ends-with ".json") {
    $body | from json
  } else if ($source | str ends-with ".yaml") or ($source | str ends-with ".yml") {
    $body | from yaml
  } else {
    try {
      $body | from json
    } catch {
      try {
        $body | from yaml
      } catch {
        # YAML accepts bare HTML/text as a scalar string, so a successful parse
        # here means we got real JSON or structured YAML — anything else is a
        # server returning an error page (HTML, plain text) with HTTP 200.
        error make --unspanned { msg: $"could not parse spec from ($source): not valid JSON or YAML" }
      }
    }
  }
  if not (($parsed | describe) | str starts-with "record") {
    let preview = ($body | str trim | str substring 0..120)
    error make --unspanned { msg: $"spec at ($source) did not parse to a record \(got ($parsed | describe)\); response begins: ($preview)" }
  }
  $parsed
}

# ── Private helpers ────────────────────────────────────────────────

# Process header or cookie params into a uniform record list.
def process-simple-params [params: list, location: string, h: record] {
  $params | where {|p| ($p.in? | default "") == $location } | each {|p|
    let example = ($p.schema?.example? | default ($p.example? | default null))
    let desc_base = ($p.description? | default "")
    let deprecated = ($p.deprecated? | default false)
    {
      name: $p.name
      type: (do $h.get-param-type $p)
      required: ($p.required? | default false)
      description: (spec build-description $desc_base [
        (if $deprecated { "DEPRECATED" } else { null })
        (if ($example != null) { $"e.g. ($example)" } else { null })
      ])
      enum: (spec clean-enum-values (do $h.get-param-enum $p))
      deprecated: $deprecated
    }
  }
}

# Normalize a discriminator into {propertyName, mapping}. OAS 3.x discriminators
# are records; Swagger 2.0 encodes them as bare strings (just the propertyName).
# Returns null when there is no discriminator.
def normalize-discriminator [disc: any] {
  let t = ($disc | describe)
  if ($t | str starts-with "record") {
    {propertyName: ($disc.propertyName? | default ""), mapping: ($disc.mapping? | default {})}
  } else if ($t == "string") {
    {propertyName: $disc, mapping: {}}
  } else {
    null
  }
}

# Merge properties from a body schema, handling allOf/oneOf/anyOf/discriminator.
# Returns {props: record, required: list<string>}.
def merge-body-props [schema: record, schemas: record] {
  mut merged_props = ($schema.properties? | default {})
  mut merged_required = ($schema.required? | default [])
  let all_of = ($schema.allOf? | default [])
  for sub in $all_of {
    let resolved_sub = (spec resolve-ref $sub $schemas)
    if (($resolved_sub | describe) | str starts-with "record") {
      let sub_props = ($resolved_sub.properties? | default {})
      let sub_req = ($resolved_sub.required? | default [])
      $merged_props = ($merged_props | merge $sub_props)
      $merged_required = ($merged_required | append $sub_req)
    }
  }

  let disc = (normalize-discriminator ($schema.discriminator? | default null))
  let disc_prop = if ($disc != null) { $disc.propertyName } else { null }
  let disc_mapping = if ($disc != null) { $disc.mapping } else { {} }
  let poly_variants = ($schema.oneOf? | default ($schema.anyOf? | default []))
  for variant in $poly_variants {
    let resolved_variant = (spec resolve-ref $variant $schemas)
    if (($resolved_variant | describe) | str starts-with "record") {
      let v_props = ($resolved_variant.properties? | default {})
      for col in ($v_props | columns) {
        if not ($col in ($merged_props | columns)) {
          $merged_props = ($merged_props | insert $col ($v_props | get $col))
        }
      }
    }
  }

  if ($disc_prop != null) and ($disc_prop in ($merged_props | columns)) {
    $merged_required = ($merged_required | append $disc_prop | uniq)
    if ($disc_mapping | columns | length) > 0 {
      $merged_props = ($merged_props | upsert $disc_prop ($merged_props | get $disc_prop | upsert enum ($disc_mapping | columns)))
    }
  }

  {props: $merged_props, required: $merged_required}
}

# Extract body field info from a resolved request body schema
def extract-body-fields [schema: record, schemas: record] {
  let merged = (merge-body-props $schema $schemas)
  let props = $merged.props
  let required = $merged.required
  # Filter out malformed entries where a property value isn't a schema record
  # (e.g. meilisearch's open-api.yaml uses `$ref` as a property name, leaving
  # a bare string sibling that would crash subsequent cell-path accesses).
  $props | transpose name field_spec | each {|field|
    if (($field.field_spec | describe) | str starts-with "record") {
      $field | upsert field_spec (spec resolve-ref $field.field_spec $schemas)
    } else {
      $field
    }
  } | where {|field|
    ($field.field_spec | describe | str starts-with "record")
  } | where {|field|
    not ($field.field_spec.readOnly? | default false)
  } | each {|field|
    let field_type = (spec normalize-type ($field.field_spec.type? | default "any"))
    let enum_vals = (spec clean-enum-values ($field.field_spec.enum? | default []))
    let nullable = (spec is-nullable $field.field_spec)
    let desc_base = ($field.field_spec.description? | default "")
    let default_val = ($field.field_spec.default? | default null)
    let format = ($field.field_spec.format? | default null)
    let example = ($field.field_spec.example? | default null)
    let deprecated = ($field.field_spec.deprecated? | default false)
    let desc = (spec build-description $desc_base [
      (if $deprecated { "DEPRECATED" } else { null })
      (if $nullable { "nullable" } else { null })
      (if ($format != null) { $"format: ($format)" } else { null })
      (if ($default_val != null) { $"default: ($default_val)" } else { null })
      (if ($example != null) { $"e.g. ($example)" } else { null })
    ])
    {
      name: $field.name
      type: $field_type
      required: ($field.name in $required)
      nullable: $nullable
      enum: $enum_vals
      description: $desc
      deprecated: $deprecated
    }
  }
}

# Build shape documentation entries for complex-typed body fields (record/list).
# Returns list of {flag: string, shape: string, is_item: bool}.
def build-field-shapes [schema: record, schemas: record] {
  let merged = (merge-body-props $schema $schemas)
  $merged.props | transpose name field_spec | where {|field|
    ($field.field_spec | describe | str starts-with "record")
  } | each {|field|
    let fs = (spec resolve-ref $field.field_spec $schemas)
    let ft = (spec normalize-type ($fs.type? | default ""))
    if ($ft == "object") or (($ft == "" or $ft == "any") and ($fs.properties? | is-not-empty)) {
      let sub_fields = (extract-body-fields $fs $schemas)
      if ($sub_fields | is-empty) { null } else {
        {flag: $field.name, shape: (render build-shape-doc $sub_fields), is_item: false}
      }
    } else if $ft == "array" {
      let items = ($fs.items? | default {})
      let resolved_items = (spec resolve-ref $items $schemas)
      if ($resolved_items.properties? | is-not-empty) or ($resolved_items.allOf? | is-not-empty) {
        let sub_fields = (extract-body-fields $resolved_items $schemas)
        if ($sub_fields | is-empty) { null } else {
          {flag: $field.name, shape: (render build-shape-doc $sub_fields), is_item: true}
        }
      } else { null }
    } else { null }
  } | compact
}

# Map OpenAPI method actions to command verbs
def action-verb [action: string] {
  match $action {
    "retrieve" => "get"
    "destroy" => "delete"
    "partial_update" => "patch"
    _ => $action
  }
}

# Canonical verb mapping for HTTP-verb-prefixed operationIds.
def canonical-verb [prefix: string] {
  match ($prefix | str downcase) {
    "get" => "get"
    "post" => "create"
    "put" => "update"
    "patch" => "update"
    "delete" => "delete"
    "list" => "list"
    "create" => "create"
    "update" => "update"
    "retrieve" => "retrieve"
    "fetch" => "get"
    "insert" => "create"
    "remove" => "delete"
    "destroy" => "delete"
    # Extended verb vocabulary — k8s, Docker, Notion, Azure batch, etc.
    "read" => "get"
    "replace" => "update"
    "watch" => "watch"
    "append" => "create"
    "query" => "list"
    "inspect" => "get"
    "attach" => "attach"
    "prune" => "prune"
    "exec" => "exec"
    "commit" => "commit"
    "build" => "build"
    "ping" => "ping"
    "cancel" => "cancel"
    "enable" => "enable"
    "disable" => "disable"
    "wait" => "wait"
    "restart" => "restart"
    "start" => "start"
    "stop" => "stop"
    "clone" => "clone"
    "copy" => "copy"
    "move" => "move"
    "add" => "create"
    # Round-3 expansion: pub/sub, registration, archive/import/export,
    # Docker (info/version/kill/pause/tag/push/pull/top/changes/stats/logs),
    # OAuth-ish (revoke/approve/reject), upload/download, send/receive,
    # sync/refresh/reload, upsert, validate/verify/check/test, lifecycle
    # (close/open/lock/unlock/finalize/abort), search/submit/trigger/reset.
    "publish" => "publish"
    "unpublish" => "delete"
    "subscribe" => "subscribe"
    "unsubscribe" => "unsubscribe"
    "register" => "create"
    "unregister" => "delete"
    "request" => "request"
    "archive" => "archive"
    "unarchive" => "unarchive"
    "export" => "export"
    "import" => "import"
    "info" => "get"
    "version" => "version"
    "kill" => "kill"
    "pause" => "pause"
    "unpause" => "unpause"
    "resize" => "resize"
    "rename" => "rename"
    "tag" => "tag"
    "untag" => "untag"
    "pull" => "pull"
    "push" => "push"
    "search" => "list"
    "top" => "top"
    "changes" => "changes"
    "stats" => "stats"
    "logs" => "logs"
    "unwatch" => "unwatch"
    "revoke" => "delete"
    "approve" => "approve"
    "reject" => "reject"
    "upload" => "upload"
    "download" => "download"
    "send" => "send"
    "receive" => "receive"
    "sync" => "sync"
    "refresh" => "refresh"
    "reload" => "reload"
    "upsert" => "update"
    "reset" => "reset"
    "validate" => "validate"
    "verify" => "verify"
    "check" => "check"
    "test" => "test"
    "submit" => "submit"
    "trigger" => "trigger"
    "close" => "close"
    "open" => "open"
    "lock" => "lock"
    "unlock" => "unlock"
    "finalize" => "finalize"
    "abort" => "abort"
    _ => $prefix
  }
}

# Regex alternation listing every verb canonical-verb knows about. Used by
# both the leading-verb and trailing-verb detectors.
#
# IMPORTANT — ordering: alternation in Rust's regex engine is leftmost-first,
# not longest-match. When one verb is a prefix of another (e.g. `update` is a
# prefix of `upsert`, `watch` of `unwatch`), the LONGER alternative MUST come
# first or the shorter one will eat its prefix and leave the rest as the
# "remainder" — producing nonsense like verb=`watch` + rest=`Unxxx`.
def known-verbs-regex [] {
  # un-prefixed pairs first (longer alternative leads)
  ('unsubscribe|subscribe|unregister|register|unarchive|archive|unpublish|publish|unpause|pause|unwatch|watch|unlock|lock|untag|tag|'
    + 'upsert|update|'
    + 'get|post|put|patch|delete|list|create|retrieve|fetch|insert|remove|destroy|'
    + 'read|replace|append|query|inspect|attach|prune|exec|commit|build|ping|cancel|enable|disable|wait|restart|start|stop|clone|copy|move|add|'
    + 'request|export|import|info|version|kill|resize|rename|pull|push|search|top|changes|stats|logs|revoke|approve|reject|'
    + 'upload|download|send|receive|sync|refresh|reload|reset|validate|verify|check|test|submit|trigger|close|open|finalize|abort')
}

# Naive singularization: strip trailing "s" if word ends in "s" but not "ss".
def naive-singular [word: string] {
  if ($word | str ends-with "ss") {
    $word
  } else if ($word | str ends-with "s") and (($word | str length) > 1) {
    $word | str substring 0..<(($word | str length) - 1)
  } else {
    $word
  }
}

# Convert a CamelCase / PascalCase / mixed token to kebab-case.
def to-kebab [s: string] {
  $s | str kebab-case
}

# Try to interpret an operationId as a HTTP-verb-prefixed name.
# Returns {matched: bool, verb: string, remainder: string} where remainder is
# the chunk after the verb (kebab-cased, with leading article stripped).
def parse-verb-prefix [action_raw: string] {
  let verbs = (known-verbs-regex)
  let pattern = ('(?i)^(?<verb>(' + $verbs + '))(?<rest>([A-Z_].*)?)$')
  let m = ($action_raw | parse --regex $pattern)
  if ($m | is-empty) {
    {matched: false, verb: "", remainder: ""}
  } else {
    let row = ($m | first)
    let rest_raw = ($row.rest | default "" | str trim --char '_')
    # Strip leading article (A / An / The) when followed by uppercase or end.
    let rest_no_article = ($rest_raw | str replace --regex '^(A|An|The)([A-Z_].*)?$' '$2')
    let remainder = (to-kebab $rest_no_article)
    {matched: true, verb: (canonical-verb $row.verb), remainder: $remainder}
  }
}

# Try to interpret an operationId as a PascalCase resource followed by a
# trailing verb token (Docker style: ContainerDelete, ConfigList, ImageBuild).
# Returns {matched: bool, verb: string, remainder: string} where remainder is
# the kebab-cased resource part (which is usually discarded since the path
# already carries the resource).
def parse-trailing-verb [action_raw: string] {
  let verbs = (known-verbs-regex)
  # Require the resource prefix to start uppercase and the trailing verb to
  # start uppercase too — keeps clean camelCase (findPetsByStatus) untouched
  # while catching PascalCase ContainerDelete / ConfigList.
  let pattern = ('^(?<rest>[A-Z][a-z][A-Za-z0-9]*?)(?<verb>(?:' + (
    $verbs | split row '|' | each {|v| ($v | str substring 0..0 | str upcase) + ($v | str substring 1..) } | str join '|'
  ) + '))$')
  let m = ($action_raw | parse --regex $pattern)
  if ($m | is-empty) {
    {matched: false, verb: "", remainder: ""}
  } else {
    let row = ($m | first)
    {matched: true, verb: (canonical-verb $row.verb), remainder: (to-kebab $row.rest)}
  }
}

# Detect a single-word PascalCase verb (Azure batch: Add, Get, List, Delete).
# Returns {matched: bool, verb: string}.
def parse-single-verb [action_raw: string] {
  let verbs = (known-verbs-regex)
  let pattern = ('(?i)^(?<verb>(' + $verbs + '))$')
  let m = ($action_raw | parse --regex $pattern)
  if ($m | is-empty) {
    {matched: false, verb: ""}
  } else {
    {matched: true, verb: (canonical-verb ($m | first | get verb))}
  }
}

# Resolve PathItem-level $ref. Returns the methods record.
def resolve-path-item [path_entry: record, schemas: record] {
  if ($path_entry.methods | columns | any {|c| $c == "$ref"}) {
    let resolved = (spec resolve-ref $path_entry.methods $schemas)
    if ($resolved | columns | any {|c| $c == "$ref"}) {
      log warn $"unresolved PathItem $ref for path '($path_entry.path)', skipping referenced operations"
      $path_entry.methods
    } else {
      $resolved
    }
  } else {
    $path_entry.methods
  }
}

# Extract operation-level metadata: description, auth, server override, etc.
def extract-op-metadata [op: record, auth_schemes: list, root_default_auth: string, methods: record] {
  let operation_id = ($op.operationId? | default "")
  let summary = ($op.summary? | default "")
  let description_text = ($op.description? | default "")
  let description = if ($summary | is-not-empty) { $summary } else { $description_text }
  let deprecated = ($op.deprecated? | default false)
  let external_docs = ($op.externalDocs? | default null)

  # per-operation security override
  let op_security = ($op.security?)
  let default_auth = if ($op_security | is-not-empty) {
    if ($op_security | length) == 0 {
      "none"
    } else {
      let first_req = ($op_security | first)
      if (($first_req | describe) | str starts-with "record") and (($first_req | columns | length) > 0) {
        let ref_name = ($first_req | columns | first)
        let matched = $auth_schemes | where {|s| $s.spec_name == $ref_name }
        if ($matched | length) > 0 { $matched | first | get name } else { $root_default_auth }
      } else {
        $root_default_auth
      }
    }
  } else {
    $root_default_auth
  }

  # per-operation/path server overrides
  let base_url = ($op.servers?.0?.url? | default ($methods.servers?.0?.url? | default null))

  {
    description: $description
    operation_id: $operation_id
    deprecated: $deprecated
    external_docs: $external_docs
    default_auth: $default_auth
    base_url: $base_url
  }
}

# Merge path+op params, resolve refs, split into path/query/header/cookie categories.
def classify-params [op: record, methods: record, schemas: record, h: record] {
  # merge path-level params with operation params (op overrides path-level)
  let path_level_params = ($methods.parameters? | default [])
  let op_params = ($op.parameters? | default [])
  let op_param_keys = $op_params | each {|p| $"($p.name? | default ''):($p.in? | default '')" }
  let parameters = ($path_level_params | where {|p|
    let key = $"($p.name? | default ''):($p.in? | default '')"
    not ($key in $op_param_keys)
  } | append $op_params)

  # resolve $ref in params, filter out body params
  # resolve-ref is shallow, so we also resolve the nested .schema if it's a ref
  let resolved_params = $parameters | each {|p|
    let resolved = if ($p | columns | any {|c| $c == "$ref"}) {
      spec resolve-ref $p $schemas
    } else { $p }
    let s = ($resolved.schema? | default null)
    if ($s != null) and (($s | describe) | str starts-with "record") and ($s | columns | any {|c| $c == "$ref"}) {
      $resolved | upsert schema (spec resolve-ref $s $schemas)
    } else {
      $resolved
    }
  } | where {|p| ($p.in? | default "") in ["path" "query" "header" "cookie"] }

  # classify params
  let path_params = $resolved_params | where {|p| ($p.in? | default "") == "path" } | each {|p|
    {
      name: ($p.name | str replace --all '-' '_')
      original_name: $p.name
      type: (do $h.get-param-type $p)
      required: ($p.required? | default true)
    }
  }

  let query_params = $resolved_params | where {|p| ($p.in? | default "") == "query" } | each {|p|
    let default_val = ($p.schema?.default? | default ($p.default? | default null))
    let format = ($p.schema?.format? | default ($p.format? | default null))
    let example = ($p.schema?.example? | default ($p.example? | default ($p | get -o "x-example" | default null)))
    let param_type = (do $h.get-param-type $p)
    let collection_style = (do $h.get-param-collection-style $p)
    let deprecated = ($p.deprecated? | default false)
    let nullable = ($p.schema?.nullable? | default false)
    let allow_empty = ($p.allowEmptyValue? | default false)
    let desc_base = ($p.description? | default "")
    let description = (spec build-description $desc_base [
      (if $deprecated { "DEPRECATED" } else { null })
      (if $nullable { "nullable" } else { null })
      (if ($format != null) { $"format: ($format)" } else { null })
      (if ($default_val != null) { $"default: ($default_val)" } else { null })
      (if ($example != null) { $"e.g. ($example)" } else { null })
      (if $allow_empty { "allows empty value" } else { null })
    ])
    {
      name: $p.name
      type: $param_type
      required: ($p.required? | default false)
      description: $description
      enum: (spec clean-enum-values (do $h.get-param-enum $p))
      collection_style: $collection_style
      deprecated: $deprecated
    }
  }

  let header_params = (process-simple-params $resolved_params "header" $h)
  let cookie_params = (process-simple-params $resolved_params "cookie" $h)

  {path_params: $path_params, query_params: $query_params, header_params: $header_params, cookie_params: $cookie_params}
}

# Extract body info: has_body, content_type, body_fields, discriminator.
def extract-body-info [op: record, schemas: record, h: record] {
  let body_info = (do $h.get-body-info $op $schemas)
  let has_body = $body_info.has_body
  let body_schema = $body_info.body_schema
  let content_type = ($body_info.content_type? | default $spec.CT_JSON)

  let has_schema = ($body_schema | is-not-empty) and (($body_schema | describe) | str starts-with "record") and (($body_schema | columns | length) > 0)
  let body_fields = if $has_schema {
    extract-body-fields $body_schema $schemas
  } else {
    []
  }
  let field_shapes = if $has_schema {
    build-field-shapes $body_schema $schemas
  } else {
    []
  }

  # discriminator info
  let body_disc = (normalize-discriminator (if (($body_schema | describe) | str starts-with "record") { $body_schema.discriminator? | default null } else { null }))
  let responses = ($op.responses? | default {})
  let resp_discs = $responses | transpose code resp | where {|r|
    ($r.code | str starts-with "2") or ($r.code == "default") or ($r.code =~ '^[12][xX]{2}$')
  } | each {|r|
    let content = ($r.resp.content? | default {})
    let json_schema = ($content | get -o "application/json" | default {} | get -o schema | default {})
    let resolved = (spec resolve-ref $json_schema $schemas)
    if (($resolved | describe) | str starts-with "record") {
      normalize-discriminator ($resolved.discriminator? | default null)
    } else {
      null
    }
  } | where { $in != null }
  let resp_disc = if ($resp_discs | length) > 0 { $resp_discs | first } else { null }
  let discriminator = if ($body_disc != null) {
    {context: "request", propertyName: $body_disc.propertyName, mapping: $body_disc.mapping}
  } else if ($resp_disc != null) {
    {context: "response", propertyName: $resp_disc.propertyName, mapping: $resp_disc.mapping}
  } else {
    null
  }

  {has_body: $has_body, content_type: $content_type, body_fields: $body_fields, field_shapes: $field_shapes, discriminator: $discriminator}
}

# Extract response info: accept_types, return_type, returns_body.
def extract-response-info [method: string, op: record, spec_data: record, schemas: record, h: record] {
  let accept_types = (do $h.get-response-content-types $op $spec_data)

  let return_type = if ($method in ["head" "options"]) {
    "record"
  } else {
    do $h.get-response-type $op $spec_data $schemas
  }

  let responses = ($op.responses? | default {})
  let returns_body = if ($method == "delete") {
    let resp_204 = ($responses | get -o "204")
    ($resp_204 | is-empty)
  } else if ($method in ["head" "options"]) {
    false
  } else {
    true
  }

  {accept_types: $accept_types, return_type: $return_type, returns_body: $returns_body}
}

# Derive command name from path, method, operationId, tags, and path params.
def derive-command-name [url_path: string, method: string, operation_id: string, tags: list, path_params: list, verb_map: record] {
  let path_segments = ($url_path | split row '/' | where {|s|
    ($s | is-not-empty) and ($s != "api") and (not ($s | str starts-with "{")) and (not ($s =~ '^v\d+$'))
  })
  let resource = if ($path_segments | length) > 0 {
    $path_segments | where {|s| $s != "-" and $s != "--" }
    # Strip OData function-call suffixes from path segments —
    # `certificates(thumbprintAlgorithm={a},thumbprint={t})` → `certificates`.
    # The {placeholders} inside add no useful naming signal and turn the
    # resource into a mangled string when joined back together.
    | each {|s| $s | str replace --regex '^([^()]+)\(.*\)$' '$1' }
    | each {|s| $s | str replace --all --regex '[\\$()*\[\]=\x27",.$#!@%^&+~`]' '' }
    | where {|s| $s | is-not-empty }
    | str join '-' | str kebab-case
  } else if ($tags | length) > 0 {
    $tags.0 | str kebab-case
  } else {
    "api"
  }

  # Normalize slash-bearing operationIds (e.g. "repos/list-for-user").
  # If the trailing segment is verb-like, drop the leading namespace; otherwise
  # join with hyphens so the rest of the pipeline can deal with it.
  let normalized_opid = if ($operation_id | is-not-empty) and ($operation_id =~ '/') {
    let segs = ($operation_id | split row '/' | where {|s| $s | is-not-empty })
    let last = ($segs | last)
    if ($last =~ ('(?i)^(' + (known-verbs-regex) + ')')) {
      $last
    } else {
      $segs | str join '-'
    }
  } else {
    $operation_id
  }

  let action_raw = if ($normalized_opid | is-not-empty) {
    let parts = ($normalized_opid | split row '_')
    let last_part = ($parts | last)
    if ($last_part =~ '^\d+$') and ($parts | length) >= 2 {
      let action_part = ($parts | get (($parts | length) - 2))
      $action_part
    } else if ($parts | length) >= 2 and ($parts | last 2 | str join '_') == "partial_update" {
      "partial_update"
    } else {
      $last_part
    }
  } else {
    $method
  }

  # Resource-token containment check used by both leading- and trailing-verb
  # detectors. Lowercases + singularizes, ignores trivial id/path-param tokens.
  # Returns the cleaned remainder string (with resource-overlapping tokens
  # removed). If the remainder reduces to nothing, the verb alone suffices.
  let resource_lower = ($resource | str downcase)
  let resource_tokens = ($resource_lower | split row '-' | each {|t| naive-singular $t })
  let path_param_names = ($path_params | each {|p| $p.name | str downcase })
  let ignorable_tokens = ($path_param_names | append ["id"] | uniq)

  # Apply custom verb map override, then verb-prefix / trailing-verb / single-word
  # detectors, then default mapping.
  let action_mapped = ($verb_map | get -o $action_raw | default null)
  let action_picked = if ($action_mapped != null) {
    $action_mapped
  } else {
    # Detect single-word PascalCase verb FIRST (Azure batch: Add, Get, List).
    # The check is intentionally restricted to PascalCase to avoid clobbering
    # lowercase `_`-style suffixes like `op_retrieve` which need the legacy
    # `action-verb` mapping (retrieve→get) inside parse-verb-prefix's empty-
    # remainder branch.
    let is_pascal_single = ($action_raw =~ '^[A-Z][a-z]+$')
    let parsed_single_first = if $is_pascal_single { (parse-single-verb $action_raw) } else { {matched: false, verb: ""} }
    let parsed = if $parsed_single_first.matched { {matched: false, verb: "", remainder: ""} } else { (parse-verb-prefix $action_raw) }
    let parsed_trail = if $parsed_single_first.matched or $parsed.matched { {matched: false, verb: "", remainder: ""} } else { (parse-trailing-verb $action_raw) }
    if $parsed_single_first.matched {
      $parsed_single_first.verb
    } else if $parsed.matched {
      if ($parsed.remainder | is-empty) {
        # No suffix → preserve legacy single-word verb mapping (retrieve→get etc).
        action-verb $action_raw
      } else {
        # If the remainder (lowercased + naively singularized) is contained in the
        # resource segments, the verb alone is enough — avoids stutters like
        # `accounts get-accounts`. The "-by-X" tail (e.g. `getUserByName`) is
        # treated as discriminator metadata, not signal — strip it for the
        # containment check.
        let remainder_lower = ($parsed.remainder | str downcase)
        # Split off any "-by-..." suffix.
        let by_split = ($remainder_lower | split row --regex '-by-')
        let prefix_part = ($by_split | first)
        # Two parallel lists: the original token strings (preserved verbatim
        # for output) and their singularized form (used only for the dedup
        # comparison against the resource tokens).
        let remainder_raw = (
          $prefix_part
          | split row '-'
          | where {|t| not ((naive-singular $t) in $ignorable_tokens) }
        )
        let remainder_tokens = ($remainder_raw | each {|t| naive-singular $t })
        # Drop any tokens that overlap the path-derived resource. This is the
        # "Resource+Method+Resource+Suffix" dedup case — k8s
        # `readCoreV1NamespacedConfigMap` on `/configmaps/...` →
        # remainder tokens `core`, `v1`, `namespaced`, `config`, `map`;
        # `config-map` (joined) matches resource token `configmap` (singular
        # of `configmaps`) so drop both `config` and `map`, keep
        # `core-v1-namespaced`.
        # Preserve the old behavior when ALL remainder tokens are in the
        # resource — drop everything, return bare verb (this is the
        # `accounts get-accounts` stutter case).
        let all_contained = ($remainder_tokens | is-empty) or ($remainder_tokens | all {|t| $t in $resource_tokens })
        let kept_tokens = if $all_contained {
          []
        } else {
          # Trailing-token dedup: walk from the END, dropping tokens that
          # match the resource (singular or joined with predecessor).
          # Stop at the first non-match. This handles the k8s
          # `CoreV1NamespacedConfigMap` case (trailing `ConfigMap` matches
          # `configmaps`) without nuking head tokens that overlap.
          let n = ($remainder_tokens | length)
          mut drop_from = $n
          mut i = ($n - 1)
          while $i >= 0 {
            let t = ($remainder_tokens | get $i)
            let prev = if $i > 0 { ($remainder_tokens | get ($i - 1)) } else { "" }
            let joined = ($prev + $t)
            let joined_sing = (naive-singular $joined)
            let single_match = ($t in $resource_tokens)
            let joined_match = ($i > 0) and (($joined in $resource_tokens) or ($joined_sing in $resource_tokens))
            if $joined_match {
              $drop_from = ($i - 1)
              $i = ($i - 2)
            } else if $single_match {
              $drop_from = $i
              $i = ($i - 1)
            } else {
              break
            }
          }
          if $drop_from >= $n {
            $remainder_raw
          } else if $drop_from <= 0 {
            []
          } else {
            $remainder_raw | take $drop_from
          }
        }
        if ($kept_tokens | is-empty) {
          $parsed.verb
        } else {
          $"($parsed.verb)-($kept_tokens | str join '-')"
        }
      }
    } else if $parsed_trail.matched {
      # Trailing-verb (Docker: ContainerDelete). The resource part is already
      # carried by the URL path; verify it actually overlaps the path-derived
      # resource so we don't strip a legitimate camelCase name like
      # `findPetsByStatus` (which doesn't match anyway since `status` is the
      # verb and `findPetsBy` is the prefix — rejected below). If the prefix
      # doesn't overlap, keep the original action_raw to be safe.
      let trail_tokens = (
        $parsed_trail.remainder
        | split row '-'
        | each {|t| naive-singular $t }
        | where {|t| not ($t in $ignorable_tokens) }
      )
      let overlaps = ($trail_tokens | any {|t| $t in $resource_tokens })
      if $overlaps or ($trail_tokens | is-empty) {
        $parsed_trail.verb
      } else {
        # Prefix didn't overlap the resource — fall through to default.
        action-verb $action_raw
      }
    } else {
      action-verb $action_raw
    }
  }

  # No-operationId fallback: if the picked action ended up empty, trivially
  # equal to the resource (sendgrid: `alerts alerts`), or still looks like
  # a PascalCase blob (Default / IsAlive / Batch / ContainerAttachWebsocket),
  # fall back to the HTTP method as the verb.
  let action_picked = if (
    ($action_picked | is-empty) or
    (($action_picked | str downcase) == $resource_lower) or
    ($action_picked =~ '^[A-Z]')
  ) {
    $method
  } else {
    $action_picked
  }

  # Strip chars that break `def "..." [...]` names. Some specs (e.g. Sentry)
  # use free-text operationIds like "Retrieve Statuses (Alpha)" — without
  # this, the parens/spaces flow straight into the generated def name.
  # Only kicks in when the action has unsafe chars — leaves clean camelCase
  # action names (findPetsByStatus, etc.) untouched.
  let action = if ($action_picked =~ '[\s\\$()*\[\]=\x27",.#!@%^&+~`]') {
    let cleaned = (
      $action_picked
      | str replace --all --regex '[\\$()*\[\]=\x27",.$#!@%^&+~`]' ''
      | str trim
      | str replace --all --regex '\s+' '-'
    )
    if ($cleaned | is-empty) { $method } else { $cleaned }
  } else {
    $action_picked
  }

  # detect _2 deduplication pattern
  let is_duplicate = if ($normalized_opid | is-not-empty) {
    let parts = ($normalized_opid | split row '_')
    let last_part = ($parts | last)
    ($last_part =~ '^\d+$') and ($parts | length) >= 2
  } else {
    false
  }

  if $is_duplicate {
    let param_suffix = $path_params | each {|p| $p.name } | str join '-'
    $"($resource) ($action)-by-($param_suffix)"
  } else {
    $"($resource) ($action)"
  }
}

# Build the command model list from a parsed+resolved REST spec.
export def build-command-list [spec_data: record, schemas: record, h: record, auth_schemes: list, root_default_auth: string, config: record] {
  ($spec_data.paths | spec drop-vendor-extensions) | transpose path methods | each {|path_entry|
    # PATH PREFIX FILTER
    if ($config.filter_prefixes | length) > 0 {
      let matches = ($config.filter_prefixes | any {|prefix| $path_entry.path | str starts-with $prefix })
      if not $matches { return null }
    }

    let methods = (resolve-path-item $path_entry $schemas)

    $methods | transpose method op | where {|m|
      ($m.method in [get post put patch delete head options]) and (
        ($config.filter_methods | length) == 0 or ($m.method in $config.filter_methods)
      )
    } | each {|method_entry|
      let method = $method_entry.method
      let op = $method_entry.op

      # skip if op is not a record (e.g. "parameters", "servers", "$ref" at path level)
      if not (($op | describe) | str starts-with "record") {
        return null
      }

      # TAG FILTER
      if ($config.filter_tags | length) > 0 {
        let op_tags = ($op.tags? | default [])
        let has_match = ($config.filter_tags | any {|t| $t in $op_tags })
        if not $has_match { return null }
      }

      let meta = (extract-op-metadata $op $auth_schemes $root_default_auth $methods)

      # DEPRECATED FILTER
      if $config.exclude_deprecated and $meta.deprecated {
        return null
      }

      let params = (classify-params $op $methods $schemas $h)
      # Synthesize path params for undeclared URL template placeholders
      let declared_originals = ($params.path_params | each {|p| $p.original_name? | default $p.name })
      let template_placeholders = ($path_entry.path | split row '{' | skip 1 | each {|s| $s | split row '}' | first } | where {|s| $s =~ '^\w+$' })
      let extra_path_params = $template_placeholders | where {|ph| not ($ph in $declared_originals) } | each {|ph|
        {name: ($ph | str replace --all '-' '_'), original_name: $ph, type: "any", required: true}
      }
      let params = if ($extra_path_params | is-empty) { $params } else {
        $params | update path_params ($params.path_params | append $extra_path_params)
      }
      # Reorder path_params to match URL template order. Path-param emission and
      # positional-flag order are taken straight from this list, so a spec that
      # declares params in a different order (e.g. alphabetical) than the URL
      # template would route calls to the wrong endpoint (e.g. `{namespace}/{name}`
      # called as `(name, namespace)` would swap them).
      let path_str = $path_entry.path
      let params = $params | update path_params ($params.path_params | sort-by {|p|
        let token = $"{($p.original_name? | default $p.name)}"
        let idx = ($path_str | str index-of $token)
        if $idx < 0 { 999999 } else { $idx }
      })
      let body = (extract-body-info $op $schemas $h)
      let resp = (extract-response-info $method $op $spec_data $schemas $h)
      let cmd_name = (derive-command-name $path_entry.path $method $meta.operation_id ($op.tags? | default []) $params.path_params $config.verb_map)

      # Build unified field_shapes: collapsed body shape + per-field shapes
      let body_collapsed = ($config.body_threshold > 0) and (($body.body_fields | length) > $config.body_threshold)
      let field_shapes = if $body_collapsed {
        [{flag: "body", shape: (render build-shape-doc $body.body_fields), is_item: false}]
      } else {
        $body.field_shapes
      }

      let endpoint_line = $"($method | str upcase) ($path_entry.path)"

      {
        name: $cmd_name
        method: $method
        path_template: $path_entry.path
        path_params: $params.path_params
        query_params: $params.query_params
        header_params: $params.header_params
        cookie_params: $params.cookie_params
        has_body: $body.has_body
        content_type: $body.content_type
        body_fields: $body.body_fields
        field_shapes: $field_shapes
        returns_body: $resp.returns_body
        description: $meta.description
        extra_doc_lines: (if ($meta.description | is-not-empty) { [$"# ($endpoint_line)"] } else { [] })
        operation_id: $meta.operation_id
        deprecated: $meta.deprecated
        deprecation_reason: null
        external_docs: $meta.external_docs
        default_auth: $meta.default_auth
        base_url: $meta.base_url
        accept_types: $resp.accept_types
        discriminator: $body.discriminator
        return_type: $resp.return_type
        tags: ($op.tags? | default [])
      }
    }
  } | flatten | compact
}
