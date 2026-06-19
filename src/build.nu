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
      items_type: (do $h.get-param-items-type $p)
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
  let all_of_resolved = (($schema.allOf? | default [])
    | each {|sub| spec resolve-ref $sub $schemas }
    | where {($in | describe) | str starts-with "record"})

  let props_after_allof = ($all_of_resolved | reduce -f ($schema.properties? | default {}) {|s, acc|
    $acc | merge ($s.properties? | default {})
  })
  let required_after_allof = ($all_of_resolved | reduce -f ($schema.required? | default []) {|s, acc|
    $acc | append ($s.required? | default [])
  })

  let disc = (normalize-discriminator ($schema.discriminator? | default null))
  let disc_prop = if ($disc != null) { $disc.propertyName } else { null }
  let disc_mapping = if ($disc != null) { $disc.mapping } else { {} }

  let poly_resolved = (($schema.oneOf? | default ($schema.anyOf? | default []))
    | each {|v| spec resolve-ref $v $schemas }
    | where {($in | describe) | str starts-with "record"})

  let merged_props_pre_disc = ($poly_resolved | reduce -f $props_after_allof {|v, acc|
    let v_props = ($v.properties? | default {})
    $v_props | items {|col, val|
      if $col in ($acc | columns) { null } else { {col: $col, val: $val} }
    } | compact | reduce -f $acc {|kv, a| $a | insert $kv.col $kv.val }
  })
  let merged_required_pre_disc = $required_after_allof

  let merged_required = if ($disc_prop != null) and ($disc_prop in ($merged_props_pre_disc | columns)) {
    $merged_required_pre_disc | append $disc_prop | uniq
  } else {
    $merged_required_pre_disc
  }
  let merged_props = if ($disc_prop != null) and ($disc_prop in ($merged_props_pre_disc | columns)) and ($disc_mapping | is-not-empty) {
    $merged_props_pre_disc | upsert $disc_prop ($merged_props_pre_disc | get $disc_prop | upsert enum ($disc_mapping | columns))
  } else {
    $merged_props_pre_disc
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
  $props | items {|name, field_spec|
    if (($field_spec | describe) | str starts-with "record") {
      {name: $name, field_spec: (spec resolve-ref $field_spec $schemas)}
    } else {
      {name: $name, field_spec: $field_spec}
    }
  } | where {|field|
    ($field.field_spec | describe | str starts-with "record")
  } | where {|field|
    not ($field.field_spec.readOnly? | default false)
  } | each {|field|
    # Defensive guard: a malformed spec may leave `.type` as a record (e.g.
    # codat.io/accounting nests `definitions.itemType` one level too deep, so
    # the JSON-Pointer resolves to `{type: {description, enum, type}}` instead
    # of the inner schema). Records can't be coerced to a render-time type
    # string, so fall back to "any". OAS 3.1 list-typed unions (e.g.
    # `[string, null]`) are still handled by `normalize-type`. Logged as a
    # warning so a legitimate generator regression doesn't degrade silently.
    # Issue 13.A.
    let raw_type = ($field.field_spec.type? | default "any")
    let raw_type_desc = ($raw_type | describe)
    let field_type = if ($raw_type_desc | str starts-with "record") {
      log warn $"field ($field.name): record-typed `.type` \(malformed spec\) → coerced to any"
      "any"
    } else {
      spec normalize-type $raw_type
    }
    let items_type = if $field_type == "array" {
      let items = (spec resolve-ref ($field.field_spec.items? | default {}) $schemas)
      spec normalize-type ($items.type? | default null)
    } else { null }
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
      items_type: $items_type
      required: ($field.name in $required)
      nullable: $nullable
      enum: $enum_vals
      description: $desc
      deprecated: $deprecated
      format: $format
    }
  }
}

# Build shape documentation entries for complex-typed body fields (record/list).
# Returns list of {flag: string, shape: string, is_item: bool}.
def build-field-shapes [schema: record, schemas: record] {
  let merged = (merge-body-props $schema $schemas)
  $merged.props | items {|name, field_spec|
    if (not (($field_spec | describe) | str starts-with "record")) {
      null
    } else {
      let fs = (spec resolve-ref $field_spec $schemas)
      let ft = (spec normalize-type ($fs.type? | default ""))
      if ($ft == "object") or (($ft == "" or $ft == "any") and ($fs.properties? | is-not-empty)) {
        let sub_fields = (extract-body-fields $fs $schemas)
        if ($sub_fields | is-empty) { null } else {
          {flag: $name, shape: (render build-shape-doc $sub_fields), is_item: false}
        }
      } else if $ft == "array" {
        let items = ($fs.items? | default {})
        let resolved_items = (spec resolve-ref $items $schemas)
        if ($resolved_items.properties? | is-not-empty) or ($resolved_items.allOf? | is-not-empty) {
          let sub_fields = (extract-body-fields $resolved_items $schemas)
          if ($sub_fields | is-empty) { null } else {
            {flag: $name, shape: (render build-shape-doc $sub_fields), is_item: true}
          }
        } else { null }
      } else { null }
    }
  } | compact
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
    "retrieve" => "get"
    "fetch" => "get"
    "insert" => "create"
    "remove" => "delete"
    "destroy" => "delete"
    "head" => "head"
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
    # Round-4 additions
    "find" => "find"
    "confirm" => "confirm"
    "set" => "update"
    "all" => "list"
    "current" => "get"
    # Round-5 additions (data-driven: see CLASSIFIER-DESIGN.md analysis)
    "describe" => "get"
    "del" => "delete"
    "notify" => "notify"
    "generate" => "generate"
    "assign" => "assign"
    "complete" => "complete"
    "resend" => "resend"
    _ => $prefix
  }
}

# Naive singularization: strip trailing "s" if word ends in "s" but not "ss".
def naive-singular [word: string] {
  if ($word | str ends-with "ss") {
    $word
  } else if ($word | str ends-with "s") and (($word | str length) > 1) {
    $word | str substring 0..-2
  } else {
    $word
  }
}

# Convert a CamelCase / PascalCase / mixed token to kebab-case.
def to-kebab [s: string] {
  $s | str kebab-case
}

# ── Tokenize-and-classify pipeline ─────────────────────────────────
#
# Verb extraction reformulated as: split the operationId into tokens once,
# label each token by its role, then pick the verb wherever it lands.
# Replaces the multi-matcher chain (parse-verb-prefix / parse-trailing-verb /
# parse-single-verb / normalized_opid splitter / leading-non-alpha strip /
# recursive un-/bulk- handlers / trailing-token dedup).
#
# See CLASSIFIER-DESIGN.md for the data analysis backing this design.

# Membership list of canonical verbs. Mirrors `canonical-verb`'s match arms.
# Used by the classifier for O(1) verb-token detection.
const KNOWN_VERBS = [
  get post put patch delete list create update retrieve fetch insert remove destroy head
  read replace watch append query inspect attach prune exec commit build ping cancel
  enable disable wait restart start stop clone copy move add
  unsubscribe subscribe unregister register unarchive archive unpublish publish
  unpause pause unwatch unlock lock untag tag upsert
  request export import info version kill resize rename pull push search top
  changes stats logs revoke approve reject upload download send receive sync
  refresh reload reset validate verify check test submit trigger close open
  finalize abort find confirm current all set
  describe del notify generate assign complete resend
]

# Tokens treated as namespace/version noise inside operationIds.
# `collection` is intentionally NOT here — it carries real meaning for k8s
# (`delete-collection` ≠ `delete`) so it falls through as OTHER and naturally
# becomes part of the discriminator suffix.
const STRUCTURAL_TOKENS = [api apis namespaced cluster scoped core]

# Prepositions kept in the discriminator only when followed by a kept token.
const PREPOSITIONS = [by for as using from with in on of to]

# Articles dropped wherever they appear.
const ARTICLES = [a an the]

# Tokenize an operationId. Splits on common separators AND camelCase
# boundaries, lowercases, and discards empties.
#   "compute.firewallPolicies.list" → [compute, firewall, policies, list]
#   "readCoreV1NamespacedConfigMap" → [read, core, v1, namespaced, config, map]
#   ".GetAvailableLocales"          → [get, available, locales]
def tokenize-opid [s: string] {
  let raw = (
    $s
    | split row --regex '[._/\-\s:]+'
    | where {|p| $p | is-not-empty }
    | each {|p|
        $p
        | str replace --all --regex '([a-z0-9])([A-Z])' '$1 $2'
        | str replace --all --regex '([A-Z]+)([A-Z][a-z])' '$1 $2'
        | split row ' '
      }
    | flatten
    | where {|t| $t | is-not-empty }
    | each {|t| $t | str downcase }
    # Issue 36.A: split lowercase-glued verb-prefix tokens like `getairlines`
    # -> [`get`, `airlines`]. Only applies to tokens that survived the case-
    # boundary sweeps unchanged (i.e. all-lowercase, separator-less). Uses
    # a small fixed set of HTTP-method-shaped verbs (not the full KNOWN_VERBS
    # list) to avoid mis-splitting common nouns like `findings`, `deliveries`,
    # `startup*`. Guard: remainder must be alphabetic and >= 5 chars so
    # `listings` (`list`+`ings`, 4), `getable` (`get`+`able`, 4), `headers`
    # (`head`+`ers`, 3), `gets` (1), `lister` (2) all stay unsplit while
    # `getairlines` (8), `gethotels` (6) split correctly.
    | each {|t|
        let pref = ([get post put patch delete list create update retrieve fetch insert remove destroy head]
          | where {|v| ($t | str starts-with $v) and (($t | str length) - ($v | str length) >= 5) and (($t | str substring (($v | str length)..)) =~ '^[a-z]+$') }
          | sort-by {|v| 0 - ($v | str length) }
          | first
          | default null)
        if $pref == null { [$t] } else {
          [$pref ($t | str substring (($pref | str length)..))]
        }
      }
    | flatten
  )
  # Collapse Django REST framework's `partial_update` compound verb to `patch`.
  # Tokens are scanned pairwise; the rest of the list passes through.
  mut out = []
  let n = ($raw | length)
  mut i = 0
  while $i < $n {
    let t = ($raw | get $i)
    let next = if ($i + 1) < $n { ($raw | get ($i + 1)) } else { "" }
    if ($t == "partial") and ($next == "update") {
      $out = ($out | append "patch")
      $i = ($i + 2)
    } else {
      $out = ($out | append $t)
      $i = ($i + 1)
    }
  }
  $out
}

# Tokenize a path-derived resource (or any string) into atomic tokens for
# cross-checking with opId tokens. Uses the SAME alphabet as `tokenize-opid`
# so `storage.k8s.io` in a path symmetrically matches `storage` in an opId —
# without this, the path-side tokens are glued together and opId tokens that
# visually appear in the path stay misclassified as OTHER (issue #6.1).
def tokenize-resource [resource: string] {
  tokenize-opid $resource
  | each {|t| naive-singular $t }
  | where {|t| $t | is-not-empty }
}

# Classify each tokenized opId token. Returns a list of
# {token: string, label: string} records preserving order.
def classify-tokens [
  tokens: list,
  resource_tokens: list,   # singularized path resource tokens
  param_tokens: list,      # singularized path-param name tokens (incl. "id")
] {
  $tokens | each {|t|
    let sing = (naive-singular $t)
    # Priority: RESOURCE / PARAM / STRUCTURAL beat VERB. Tokens that appear
    # in the path resource take precedence so `createAccessRequest` on
    # `/access_requests` classifies `request` as RESOURCE (load-bearing for
    # the resource name) rather than as a secondary VERB.
    let label = if ($t in $STRUCTURAL_TOKENS) or ($t =~ '^v\d+$') {
      "STRUCTURAL"
    } else if ($sing in $param_tokens) or ($t in $param_tokens) {
      "PARAM"
    } else if ($sing in $resource_tokens) or ($t in $resource_tokens) {
      "RESOURCE"
    } else if ($t in $KNOWN_VERBS) {
      "VERB"
    } else if ($t in $ARTICLES) {
      "ARTICLE"
    } else if ($t in $PREPOSITIONS) {
      "PREPOSITION"
    } else {
      "OTHER"
    }
    {token: $t, label: $label}
  }
}

# Given classified tokens + the HTTP method, pick the primary verb and build
# the discriminator suffix. Returns the joined action string (e.g. "get",
# "get-by-status", "delete-collection", "create-or-update").
def pick-action [classified: list, method: string] {
  let verb_idxs = ($classified | enumerate | where {|e| $e.item.label == "VERB" } | each {|e| $e.index })
  # Leftmost wins: data shows it matches the HTTP method 2.4× more often than
  # rightmost (38.9% vs 16.3%) when there are multiple verb tokens.
  # When no token classifies as VERB, fall back to any token whose word is
  # in the verb vocabulary even if it classified as RESOURCE — this rescues
  # cases like `findPetsByStatus` on path `/pet/findByStatus` where the
  # verb-word is itself embedded in a path segment.
  let chosen_idx = if ($verb_idxs | is-not-empty) {
    $verb_idxs | first
  } else {
    # Fallback: no token classified as VERB, but the opId may still contain
    # a vocab verb that classified as RESOURCE (e.g. `approveAccessRequest`
    # on `/.../approve`, where every token also appears in the path).
    # Leftmost wins — matches the dominant verb-at-0 position in the data.
    let fallback_idxs = ($classified | enumerate | where {|e| $e.item.token in $KNOWN_VERBS } | each {|e| $e.index })
    if ($fallback_idxs | is-empty) { -1 } else { $fallback_idxs | first }
  }
  let primary_verb = if $chosen_idx >= 0 {
    canonical-verb ($classified | get $chosen_idx | get token)
  } else {
    # No verb token anywhere → fall back to HTTP method (71.5% agree with
    # opId-verb when one exists, so method is a defensible default).
    canonical-verb $method
  }

  # Build discriminator: walk tokens, keeping OTHER and secondary VERBs and
  # PREPOSITIONS (when followed by a kept token).
  let parts = ($classified | enumerate | each {|e|
    let i = $e.index
    let entry = $e.item
    let label = $entry.label
    let tok = $entry.token
    let keep = if $i == $chosen_idx {
      false
    } else if $label in ["STRUCTURAL" "PARAM" "RESOURCE" "ARTICLE"] {
      false
    } else if $label == "PREPOSITION" {
      # Keep if the NEXT non-dropped token is OTHER or VERB.
      let upcoming = ($classified | skip ($i + 1) | where {|p| $p.label not-in ["STRUCTURAL" "PARAM" "RESOURCE" "ARTICLE"] })
      ($upcoming | is-not-empty) and (($upcoming | first | get label) in ["OTHER" "VERB" "PREPOSITION"])
    } else if $label == "VERB" {
      # Issue 33.A: drop a secondary VERB whose canonical form equals the
      # primary verb. Suppresses verb-verb stutter like `create-create-tags`
      # (POST + Create), `get-get-bundle-info` (GET + Info→get),
      # `list-list-of-unsubscribed-addresses` (GET + Query→list).
      (canonical-verb $tok) != $primary_verb
    } else {
      # OTHER. Issue 41.A: when the primary verb came from method-fallback
      # (no token classified as VERB), also drop OTHER tokens whose word
      # matches the fallback method verb itself. Suppresses
      # `options-options` stutter on OPTIONS opIds like `options_events`,
      # `optionsProxy` (where `options` stays out of KNOWN_VERBS so that
      # `<X>Options_Verb` opIds don't mis-classify their trailing real verb).
      # Mirrors 33.A's secondary-VERB drop for the no-real-VERB-token case.
      #
      # Issue 43.A: extend the drop to glued-suffix forms like `deleteall`
      # (= delete + all) on `deleteAll` opIds where the 36.A tokenizer's
      # `>= 5` remainder guard rejects the split. Only fires when the
      # primary verb came from method-fallback AND the remainder is in a
      # small allow-list of common short noun-stems. Suppresses
      # `delete-deleteall`, `get-getall`, `delete-deletebulk` etc.
      if ($chosen_idx == -1) and ($tok == $primary_verb) {
        false
      } else if ($chosen_idx == -1) and ($tok | str starts-with $primary_verb) and (($tok | str length) > ($primary_verb | str length)) {
        let rem = ($tok | str substring (($primary_verb | str length)..))
        if $rem in ["all" "bulk" "byid" "byname" "many" "one"] { false } else { true }
      } else {
        true
      }
    }
    if $keep {
      if $label == "VERB" { canonical-verb $tok } else { $tok }
    } else {
      null
    }
  } | compact)

  if ($parts | is-empty) {
    $primary_verb
  } else {
    $"($primary_verb)-($parts | str join '-')"
  }
}

# Resolve PathItem-level $ref. Returns the methods record.
def resolve-path-item [path_entry: record, schemas: record] {
  if ("$ref" in ($path_entry.methods | columns)) {
    let resolved = (spec resolve-ref $path_entry.methods $schemas)
    if ("$ref" in ($resolved | columns)) {
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
def extract-op-metadata [op: record, auth_schemes: list, root_default_auth: string, methods: record, h: record] {
  let operation_id = ($op.operationId? | default "")
  let summary = ($op.summary? | default "")
  let description_text = ($op.description? | default "")
  let description = (spec normalize-description (if ($summary | is-not-empty) { $summary } else { $description_text }))
  let deprecated = ($op.deprecated? | default false)
  let external_docs = ($op.externalDocs? | default null)

  # per-operation security override.
  # OAS3 §4.8.30: `security: []` (empty array) removes the top-level security
  # declaration for this operation. Use `!= null` (not `is-not-empty`) so
  # an empty array enters the override branch and yields "none". The legacy
  # `[{}]` form (one empty record meaning "no auth required") also yields
  # "none". 42.A.
  let op_security = ($op.security?)
  let default_auth = if ($op_security != null) {
    if ($op_security | is-empty) {
      "none"
    } else {
      let first_req = ($op_security | first)
      if (($first_req | describe) | str starts-with "record") and ($first_req | is-not-empty) {
        let ref_name = ($first_req | columns | first)
        let matched = $auth_schemes | where {|s| $s.spec_name == $ref_name }
        if ($matched | is-not-empty) { $matched | first | get name } else { $root_default_auth }
      } else {
        "none"
      }
    }
  } else {
    $root_default_auth
  }

  # per-operation/path server overrides — resolve {var} placeholders via dispatch helper
  let chosen_server = ($op.servers?.0? | default ($methods.servers?.0? | default null))
  let base_url = if ($chosen_server == null) { null } else { do $h.resolve-server-url $chosen_server }

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
    let resolved = if ("$ref" in ($p | columns)) {
      spec resolve-ref $p $schemas
    } else { $p }
    let s = ($resolved.schema? | default null)
    if ($s != null) and (($s | describe) | str starts-with "record") and ("$ref" in ($s | columns)) {
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
      items_type: (do $h.get-param-items-type $p)
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
def extract-body-info [op: record, schemas: record, h: record, spec_data: record] {
  let body_info = (do $h.get-body-info $op $schemas $spec_data)
  let has_body = $body_info.has_body
  let content_type = ($body_info.content_type? | default $spec.CT_JSON)

  # Issue 25.A: when the body content-type is non-priority (e.g. text/plain,
  # text/xml, application/vnd.X+json), `get-body-info` records the
  # content_type but returns an empty `body_schema` because it only resolves
  # schemas for application/json / multipart / form-urlencoded. To surface
  # `body_scalar_type` for those endpoints, bridge here by re-reading the
  # schema directly from op.requestBody.content.{content_type}.schema (OA3
  # shape only — Swagger 2 always uses application/json so its body_schema
  # is already populated by get-body-info).
  let body_schema = if ($body_info.body_schema | is-empty) and $has_body and (($op.requestBody? | describe) | str starts-with "record") {
    let rb = (spec resolve-ref ($op.requestBody) $schemas)
    let content = ($rb.content? | default {})
    let s = ($content | get -o $content_type | default {} | get -o schema)
    if ($s | is-not-empty) {
      spec resolve-ref $s $schemas
    } else {
      {}
    }
  } else {
    $body_info.body_schema
  }

  # For non-JSON content-types (text/xml, application/vnd.X+json, …) we do
  # NOT expand record schemas into per-field flags: there is no canonical
  # Nushell-record-to-XML codec, no canonical record-to-octet-stream codec,
  # etc. Callers pre-serialize and either pass a string via --body or pipe
  # one into the operation. Per-field flags would be misleading. JSON-family
  # content-types still expand because `http post --content-type application/json
  # <record>` auto-encodes correctly. Multipart and form-urlencoded also
  # expand — the renderer has dedicated `build-multipart-body` and
  # `url build-query` codecs for them.
  let priority_ct = ($content_type | str starts-with "application/json") or ($content_type == "multipart/form-data") or ($content_type == "application/x-www-form-urlencoded")
  let has_schema = ($body_schema | is-not-empty) and (($body_schema | describe) | str starts-with "record") and ($body_schema | is-not-empty)
  let expand_fields = $has_schema and ($priority_ct or (not $has_body))
  let body_fields = if $expand_fields {
    extract-body-fields $body_schema $schemas
  } else {
    []
  }
  let field_shapes = if $expand_fields {
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
  let resp_disc = if ($resp_discs | is-not-empty) { $resp_discs | first } else { null }
  let discriminator = if ($body_disc != null) {
    {context: "request", propertyName: $body_disc.propertyName, mapping: $body_disc.mapping}
  } else if ($resp_disc != null) {
    {context: "response", propertyName: $resp_disc.propertyName, mapping: $resp_disc.mapping}
  } else {
    null
  }

  # Detect polymorphic body schemas where one oneOf/anyOf variant is a bare
  # array. The per-field signature only covers object variants; the array
  # variant is unreachable through any flag. We flag the command so the
  # renderer can accept a list pipeline input and pass it straight through as
  # the request body (e.g. GitHub branch-protection contexts). Issue 13.B.
  let body_polymorphic_array = if (($body_schema | describe) | str starts-with "record") {
    let variants = ($body_schema.oneOf? | default ($body_schema.anyOf? | default []))
    $variants | any {|v|
      let resolved = (spec resolve-ref $v $schemas)
      if (($resolved | describe) | str starts-with "record") {
        let t = ($resolved.type? | default null)
        # Plain "array" or OAS 3.1 list-typed union containing "array".
        ($t == "array") or ((($t | describe) | str starts-with "list") and ("array" in ($t | default [])))
      } else {
        false
      }
    }
  } else {
    false
  }

  # Determine the body schema's scalar type so the renderer can emit a typed
  # `--body: <type>` flag (and accept matching pipeline input) when the body
  # has no enumerable fields. "any" covers record-shaped, missing, and
  # unresolvable schemas — those keep the existing `--body: record` path.
  # Issue 25.A: non-record schemas (`type: string`/`integer`/etc.) and
  # non-JSON content-types like text/xml were unreachable because the
  # generator hardcoded `--body: record` and the pipeline-merge dropped
  # non-record input.
  let body_scalar_type = if (not $has_schema) {
    "any"
  } else {
    let raw = ($body_schema.type? | default null)
    let normalized = (spec normalize-type $raw)
    if ($normalized == null) or ($normalized == "object") {
      "any"
    } else if (($normalized | describe) | str starts-with "record") {
      "any"
    } else {
      $normalized
    }
  }

  {has_body: $has_body, content_type: $content_type, body_fields: $body_fields, field_shapes: $field_shapes, discriminator: $discriminator, body_polymorphic_array: $body_polymorphic_array, body_scalar_type: $body_scalar_type}
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
  let resource = if ($path_segments | is-not-empty) {
    $path_segments | where {|s| $s != "-" and $s != "--" }
    # Strip OData function-call suffixes from path segments —
    # `certificates(thumbprintAlgorithm={a},thumbprint={t})` → `certificates`.
    # The {placeholders} inside add no useful naming signal and turn the
    # resource into a mangled string when joined back together.
    | each {|s| $s | str replace --regex '^([^()]+)\(.*\)$' '$1' }
    # Strip garbage chars but PRESERVE separators (`.`, `_`, `:`, space) so
    # the tokenizer can split on them. Without this, `account.cart.add.json`
    # would have `.` stripped first and collapse to `accountcartaddjson`.
    # See issue #7 — the resource-name string must share the alphabet with
    # the matching token set so users see readable names like
    # `account-cart-add-json` instead of glued strings.
    | each {|s| $s | str replace --all --regex '[\\$()*\[\]=\x27",$#!@%^&+~`]' '' }
    | each {|s| tokenize-opid $s }
    | flatten
    | where {|s| $s | is-not-empty }
    | str join '-' | str kebab-case
  } else if ($tags | is-not-empty) {
    $tags.0 | str kebab-case
  } else {
    "api"
  }

  # `normalized_opid` retained ONLY for the `_2` numeric-suffix dedup below.
  # The verb-extraction itself no longer uses it — see the tokenize-classify
  # pipeline below.
  let normalized_opid = if ($operation_id | is-not-empty) and ($operation_id =~ '[/.]') {
    let segs = ($operation_id | split row --regex '[/.]' | where {|s| $s | is-not-empty })
    $segs | str join '-'
  } else {
    $operation_id
  }

  # ── Tokenize → classify → pick ─────────────────────────────────
  # Splits the operationId on every common separator + camelCase boundary,
  # labels each token by its role (VERB / STRUCTURAL / PARAM / RESOURCE /
  # PREPOSITION / ARTICLE / OTHER), then picks the leftmost VERB as the
  # action and joins remaining tokens into the discriminator. Replaces the
  # old chain of parse-verb-prefix / parse-trailing-verb / parse-single-verb
  # / normalized_opid splitter / leading-non-alpha strip / recursive un-/bulk-
  # handlers / trailing-token dedup. See CLASSIFIER-DESIGN.md.
  let resource_lower = ($resource | str downcase)
  # Build resource_token_set from RAW path segments (pre-cleaning, pre-join),
  # tokenized through the same alphabet as opIds. Without this, segments like
  # `storage.k8s.io` or `account.cart.add.json` get glued into one token and
  # opId tokens that visually appear in the path stay as discriminator noise.
  # See issue #6.1.
  let resource_token_set = if ($path_segments | is-not-empty) {
    $path_segments
    | each {|s| $s | str replace --regex '^([^()]+)\(.*\)$' '$1' }
    | each {|s| tokenize-resource $s }
    | flatten
    | uniq
  } else {
    # Path had no usable segments (e.g. `/` or only `{name}`): the final
    # resource comes from tags or the "api" fallback. Tokenize it so opId
    # tokens that overlap with the tag still classify as RESOURCE.
    tokenize-resource $resource
  }
  let path_param_token_set = (
    $path_params | each {|p|
      let n = ($p.name | str downcase)
      [(naive-singular $n)] | append (tokenize-resource $n)
    } | flatten | append ["id"] | uniq
  )

  # For namespaced operationIds, only the LAST namespace-segment carries
  # verb info — earlier segments are namespace. Without this, every
  # namespace token survives as discriminator and produces 12-token verbs.
  # See issue #6.2.
  #   `.` separator: Google `cloudkms.projects...macSign`, Flickr
  #     `flickr.favorites.getList`, Yandex, etc.
  #   `#` separator: Rails-style `controller#action`
  #     (`Api::V1::Models#search`), AWS-style `path#subresource`
  #     (`get_files_id#get_shared_link`). Cycle 32.
  let opid_for_verb = if ($operation_id | is-not-empty) and ($operation_id =~ '[.#]') {
    $operation_id | split row --regex '[.#]' | last
  } else if ($operation_id | is-not-empty) {
    $operation_id
  } else if $method == "options" {
    # Issue 35.B: avoid `options-options` stutter when method-fallback
    # re-tokenizes. `options` stays out of KNOWN_VERBS (3 leftmost-noun
    # `<X>Options_Verb` opIds rely on its OTHER classification), so the
    # empty-opid case needs a separate bypass.
    ""
  } else {
    $method
  }
  # Strip trailing `_<digit>+` before tokenizing — auto-generated dedup
  # markers, not part of the action name. The numeric-suffix dedup branch
  # downstream still uses `normalized_opid` to detect and re-attach the marker.
  let opid_for_tokens = ($opid_for_verb | str replace --regex '_\d+$' '')
  let tokens = (tokenize-opid $opid_for_tokens)
  let classified = (classify-tokens $tokens $resource_token_set $path_param_token_set)
  let picked = (pick-action $classified $method)

  # Apply --verb-map. The override key is matched against (a) the full
  # operationId, then (b) the last `_`-segment of the opId (legacy contract),
  # then (c) the picked verb head. A match REPLACES the entire action.
  let verb_map_keys = [
    $operation_id
    ($operation_id | split row '_' | last)
    ($picked | split row '-' | first)
  ]
  let matches = ($verb_map_keys | each {|k| $verb_map | get -o $k } | where {|v| $v != null })
  let action_picked = if ($matches | is-not-empty) { $matches | first } else { $picked }

  # Stutter case: if the picked verb is literally the resource word
  # (sendgrid: `alerts alerts`), fall back to canonical method.
  let action_picked = if (($action_picked | str downcase) == $resource_lower) {
    canonical-verb $method
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
    # Issue 34.B: kebab-case each path-param name so the suffix stays
    # internally consistent with the rest of the command (no surviving
    # camelCase or underscore from the spec).
    let param_suffix = $path_params | each {|p| $p.name | str kebab-case } | str join '-'
    # Issue 34.A: when there are no path params, the `-by-` marker would
    # collapse to a hanging hyphen. Skip it and let pass-2 numeric-suffix
    # dedup handle the collision (matches same-resource same-verb path).
    if ($param_suffix | is-empty) {
      $"($resource) ($action)"
    } else {
      $"($resource) ($action)-by-($param_suffix)"
    }
  } else {
    $"($resource) ($action)"
  }
}

# Build the command model list from a parsed+resolved REST spec.
export def build-command-list [spec_data: record, schemas: record, h: record, auth_schemes: list, root_default_auth: string, config: record] {
  ($spec_data.paths | spec drop-vendor-extensions) | transpose path methods | each {|path_entry|
    # PATH PREFIX FILTER
    if ($config.filter_prefixes | is-not-empty) {
      let matches = ($config.filter_prefixes | any {|prefix| $path_entry.path | str starts-with $prefix })
      if not $matches { return null }
    }

    let methods = (resolve-path-item $path_entry $schemas)

    $methods | transpose method op | where {|m|
      ($m.method in [get post put patch delete head options]) and (
        ($config.filter_methods | is-empty) or ($m.method in $config.filter_methods)
      )
    } | each {|method_entry|
      let method = $method_entry.method
      let op = $method_entry.op

      # skip if op is not a record (e.g. "parameters", "servers", "$ref" at path level)
      if not (($op | describe) | str starts-with "record") {
        return null
      }

      # TAG FILTER
      if ($config.filter_tags | is-not-empty) {
        let op_tags = ($op.tags? | default [])
        let has_match = ($config.filter_tags | any {|t| $t in $op_tags })
        if not $has_match { return null }
      }

      let meta = (extract-op-metadata $op $auth_schemes $root_default_auth $methods $h)

      # DEPRECATED FILTER
      if $config.exclude_deprecated and $meta.deprecated {
        return null
      }

      # Strip OpenAPI path-key fragment (e.g. AWS `#tagKeys`, `#Content-Type`)
      # used to disambiguate ops sharing method+path. Servers treat `#…` as a
      # client-side fragment, so it must not leak into the runtime URL, command
      # name, or doc comment.
      let clean_path = ($path_entry.path | str replace --regex '#.*$' '')

      let params = (classify-params $op $methods $schemas $h)
      # Synthesize path params for undeclared URL template placeholders
      let declared_originals = ($params.path_params | each {|p| $p.original_name? | default $p.name })
      let template_placeholders = ($clean_path | split row '{' | skip 1 | each {|s| $s | split row '}' | first } | where {|s| $s =~ '^\w+$' })
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
      let params = $params | update path_params ($params.path_params | sort-by {|p|
        let token = $"{($p.original_name? | default $p.name)}"
        let idx = ($clean_path | str index-of $token)
        if $idx < 0 { 999999 } else { $idx }
      })
      let body = (extract-body-info $op $schemas $h $spec_data)
      let resp = (extract-response-info $method $op $spec_data $schemas $h)
      let cmd_name = (derive-command-name $clean_path $method $meta.operation_id ($op.tags? | default []) $params.path_params $config.verb_map)

      # Build unified field_shapes: collapsed body shape + per-field shapes
      let body_collapsed = ($config.body_threshold > 0) and (($body.body_fields | length) > $config.body_threshold)
      let field_shapes = if $body_collapsed {
        [{flag: "body", shape: (render build-shape-doc $body.body_fields), is_item: false}]
      } else {
        $body.field_shapes
      }

      let endpoint_line = $"($method | str upcase) ($clean_path)"

      {
        name: $cmd_name
        method: $method
        path_template: $clean_path
        path_params: $params.path_params
        query_params: $params.query_params
        header_params: $params.header_params
        cookie_params: $params.cookie_params
        has_body: $body.has_body
        content_type: $body.content_type
        body_fields: $body.body_fields
        body_polymorphic_array: $body.body_polymorphic_array
        body_scalar_type: $body.body_scalar_type
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
