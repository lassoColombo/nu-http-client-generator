# Behavioral tests for command naming and the --name-fn override hook.
#
# The operationId IS the name. Operations without a usable one fall back to a
# mechanical method+path slug. Whatever a --name-fn closure returns, the
# generator still guarantees a valid `def` name and global uniqueness — those
# two invariants are the generator's, not the user's.

use std/assert
use std/testing *

use ../mod.nu

const PETSTORE = "tests/fixtures/petstore-v3.yaml"
const OPID = "tests/inputs/openapi-v3/opid-naming-edge-cases.yaml"

# ── the default: operationId, sanitized ─────────────────────────────────

@test
def "name comes from the operation id" [] {
    let names = mod preview $PETSTORE | get name
    assert ("find-pets-by-status" in $names) "camelCase operationId must kebab to the command name"
    assert ("get-pet-by-id" in $names) "operationId wins over path and method"
}

@test
def "separators in an operation id collapse to dashes" [] {
    let names = mod preview $OPID | get name
    assert ("widgets-list-by-owner" in $names) "`_` separates"
    assert ("widgets-list-archived" in $names) "`/` separates"
    assert ("catalog-widgets-list-all" in $names) "`.` separates"
    assert ("widgets-batch-get" in $names) "`:` separates"
}

# ── the fallback: method + path slug ────────────────────────────────────

@test
def "missing operation id falls back to a method+path slug" [] {
    let names = mod preview $OPID | get name
    assert ("get-fallback-widget-id-parts" in $names) "slug is method + path, params kept as segments"
    assert ("delete-fallback-widget-id-parts" in $names) "the method prefix keeps sibling verbs apart"
}

@test
def "path params keep the slug unique" [] {
    let names = mod preview $OPID | get name
    # /siblings/{id} and /siblings/{name}/detail only differ by param name.
    assert ("get-siblings-id" in $names) "param name survives into the slug"
    assert ("get-siblings-name-detail" in $names) "…so no dedup pass is needed"
}

@test
def "an operation id nushell cannot define falls back to the slug" [] {
    let names = mod preview $OPID | get name
    # `export` and `match` are parser keywords; `main` and `commands` are
    # already defined by the generated module itself.
    assert ("post-keyword-export" in $names) "parser keyword `export` is rescued"
    assert ("post-keyword-match" in $names) "parser keyword `match` is rescued"
    assert ("get-keyword-main" in $names) "`main` would collide with the root command"
    assert ("get-keyword-commands" in $names) "`commands` would collide with introspection"
    assert ("get-empty-opid" in $names) "an operationId that sanitizes to nothing is rescued"
}

# ── the sweep: uniqueness ───────────────────────────────────────────────

@test
def "operation ids that kebab alike get a numeric suffix" [] {
    let names = mod preview $OPID | get name
    # getThingDetail / get_thing_detail / get-thing-detail all kebab the same.
    assert ("get-thing-detail" in $names) "the first one keeps the bare name"
    assert ("get-thing-detail-1" in $names) "the second gets -1"
    assert ("get-thing-detail-2" in $names) "the third gets -2"
}

@test
def "every generated name is unique" [] {
    for spec in [$PETSTORE $OPID] {
        let names = mod preview $spec | get name
        assert equal ($names | length) ($names | uniq | length) $"duplicate names in ($spec)"
    }
}

# ── light touch: the closure defers to the generator's default ──────────

@test
def "name-fn passthrough keeps defaults" [] {
    let base = mod preview $PETSTORE | get name
    let same = mod preview $PETSTORE --name-fn {|ctx| $ctx.derived.default_name } | get name
    assert equal $same $base "returning default_name must reproduce the default names"
}

@test
def "name-fn null keeps defaults" [] {
    let base = mod preview $PETSTORE | get name
    let same = mod preview $PETSTORE --name-fn {|ctx| null } | get name
    assert equal $same $base "returning null must fall back to the default"
}

@test
def "name-fn error keeps defaults" [] {
    let base = mod preview $PETSTORE | get name
    let same = mod preview $PETSTORE --name-fn {|ctx| error make {msg: "boom"} } | get name
    assert equal $same $base "a throwing closure must fall back to the default"
}

# ── full control: override from spec context ────────────────────────────

@test
def "name-fn overrides by operation id" [] {
    let names = mod preview $PETSTORE --name-fn {|ctx|
        if $ctx.raw.operation_id == "findPetsByStatus" { "pet search" } else { $ctx.derived.default_name }
    } | get name
    assert ("pet-search" in $names) "override should apply to the matched op (spaces kebab like any separator)"
    assert ("find-pets-by-status" not-in $names) "the default name should be replaced"
}

@test
def "name-fn exposes which rule produced the default" [] {
    # NB: `--` collapses to `-` like any other separator run.
    let rows = mod preview $OPID --name-fn {|ctx| $"from ($ctx.derived.source) ($ctx.derived.default_name)" } | get name
    assert ("from-operation-id-get-widget" in $rows) "an operationId-derived name reports source=operation-id"
    assert ("from-path-get-fallback-widget-id-parts" in $rows) "a slug reports source=path"
}

# ── invariants the generator keeps regardless of the closure ────────────

@test
def "name-fn collisions still deduped" [] {
    # Collapse every command to one name; the generator must still emit unique defs.
    let names = mod preview $PETSTORE --name-fn {|ctx| "same cmd" } | get name
    assert equal ($names | length) ($names | uniq | length) "names must stay globally unique"
    assert ("same-cmd" in $names) "the first colliding member keeps the bare name"
    assert ("same-cmd-1" in $names) "the rest get a numeric suffix"
}

@test
def "name-fn sanitizes def-breaking chars" [] {
    let names = mod preview $PETSTORE --name-fn {|ctx| '"bad(name)"' } | get name
    assert ($names | all {|n| not ($n | str contains '"') }) "quotes must be stripped"
    assert ($names | all {|n| not ($n | str contains '(') }) "parens must be stripped"
}

@test
def "name-fn cannot produce a name nushell refuses" [] {
    let names = mod preview $PETSTORE --name-fn {|ctx| "let" } | get name
    assert ("let" not-in $names) "a parser keyword must never reach the emitted module"
    assert equal ($names | length) ($names | uniq | length) "names must stay globally unique"
}
