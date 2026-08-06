# Behavioral tests for the --name-fn override hook.
#
# Default naming is mechanical (path -> namespace, method -> verb). --name-fn
# lets the user override per-operation. Whatever the closure returns, the
# generator still guarantees a valid `def` name and global uniqueness — those
# two invariants are the generator's, not the user's.

use std/assert
use std/testing *

use ../mod.nu

const PETSTORE = "tests/fixtures/petstore-v3.yaml"

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
    assert ("pet search" in $names) "override should apply to the matched op"
    assert ("pet-find-by-status get" not-in $names) "the default name should be replaced"
}

@test
def "name-fn exposes derived resource and action" [] {
    let names = mod preview $PETSTORE --name-fn {|ctx| $"($ctx.derived.resource) x-($ctx.derived.action)" } | get name
    assert ("pet x-get" in $names) "derived.resource + derived.action must be populated"
}

# ── invariants the generator keeps regardless of the closure ────────────

@test
def "name-fn collisions still deduped" [] {
    # Collapse every command to one name; the generator must still emit unique defs.
    let names = mod preview $PETSTORE --name-fn {|ctx| "same cmd" } | get name
    assert equal ($names | length) ($names | uniq | length) "names must stay globally unique"
    assert ("same cmd" in $names) "the first colliding member keeps the bare name"
}

@test
def "name-fn sanitizes def-breaking chars" [] {
    let names = mod preview $PETSTORE --name-fn {|ctx| '"bad(name)"' } | get name
    assert ($names | all {|n| not ($n | str contains '"') }) "quotes must be stripped"
    assert ($names | all {|n| not ($n | str contains '(') }) "parens must be stripped"
}
