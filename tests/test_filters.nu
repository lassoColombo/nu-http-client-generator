# Targeted tests for filtering and naming flags:
# --tags, --prefixes, --methods, --verb-map, --urls
#
# Uses the petstore-v3 OpenAPI schema with assertion-based checks
# rather than golden files.

use std/assert
use std/testing *

use ../mod.nu

const PETSTORE = "tests/fixtures/petstore-v3.yaml"

# ── --tags ───────────────────────────────────────────────────────────

@test
def "tags single" [] {
    let names = mod preview $PETSTORE --tags [pet] | get name
    assert equal ($names | length) 8 "expected 8 pet-tagged commands"
    assert ($names | all {|n| $n | str starts-with "pet"}) "all commands should start with 'pet'"
}

@test
def "tags multiple" [] {
    let names = mod preview $PETSTORE --tags [store user] | get name
    assert equal ($names | length) 11 "expected 11 store+user commands"
    let has_pet = $names | any {|n| ($n | str starts-with "pet-") or ($n == "pet")}
    assert (not $has_pet) "should not contain pet commands"
}

@test
def "tags empty match" [] {
    let result = mod preview $PETSTORE --tags [nonexistent]
    assert ($result | is-empty) "non-existent tag should yield zero commands"
}

# ── --prefixes ───────────────────────────────────────────────────────

@test
def "prefixes rest" [] {
    let names = mod preview $PETSTORE --prefixes ["/pet"] | get name
    assert equal ($names | length) 8 "expected 8 commands under /pet"
    assert ($names | all {|n| $n | str starts-with "pet"}) "all commands should start with 'pet'"
}

@test
def "prefixes rest narrow" [] {
    let names = mod preview $PETSTORE --prefixes ["/store/order"] | get name
    assert equal ($names | length) 3 "expected 3 commands under /store/order"
    let expected = ["store-order create-place", "store-order get", "store-order delete"]
    assert equal $names $expected
}

# ── --methods ────────────────────────────────────────────────────────

@test
def "methods get only" [] {
    let result = mod preview $PETSTORE --methods [get]
    assert ($result | all {|r| $r.method == "get"}) "all commands should be GET"
    assert equal ($result | length) 8 "expected 8 GET commands"
}

@test
def "methods get and delete" [] {
    let result = mod preview $PETSTORE --methods [get delete]
    assert ($result | all {|r| $r.method in [get delete]}) "all commands should be GET or DELETE"
    assert equal ($result | length) 11 "expected 11 GET+DELETE commands"
}

# ── --verb-map ───────────────────────────────────────────────────────

@test
def "verb-map renames action" [] {
    let baseline = mod preview $PETSTORE | get name
    let mapped = mod preview $PETSTORE --verb-map {findPetsByStatus: "search-by-status"} | get name
    let changed = $baseline | zip $mapped | where {|pair| $pair.0 != $pair.1 }
    assert equal ($changed | length) 1 "exactly one command should change"
    assert equal $changed.0.1 "pet-find-by-status search-by-status"
}

@test
def "verb-map multiple keys" [] {
    let mapped = mod preview $PETSTORE --verb-map {findPetsByStatus: "search-by-status", placeOrder: "create"} | get name
    assert ("pet-find-by-status search-by-status" in $mapped) "findPetsByStatus should be renamed"
    assert ("store-order create" in $mapped) "placeOrder should be renamed"
}

# ── --urls ───────────────────────────────────────────────────────────

@test
def "urls added to completer" [] {
    let tmp = mktemp --directory
    let out = $tmp | path join "out.nu"
    try {
        mod $PETSTORE -o $out --urls ["https://extra.example.com" "https://staging.example.com"]
        let content = open $out --raw
        assert ($content | str contains "https://extra.example.com") "should contain extra URL"
        assert ($content | str contains "https://staging.example.com") "should contain staging URL"
        assert ($content | str contains "http://localhost/api/v3") "should still contain spec URL"
    } catch {|err|
        rm --recursive $tmp
        assert false $err.msg
    }
    rm --recursive $tmp
}

# ── combined filters ─────────────────────────────────────────────────

@test
def "tags plus methods" [] {
    let result = mod preview $PETSTORE --tags [pet] --methods [get]
    assert ($result | all {|r| $r.method == "get"}) "all should be GET"
    assert equal ($result | length) 3 "expected 3 pet GET commands"
}

@test
def "prefixes plus methods" [] {
    let result = mod preview $PETSTORE --prefixes ["/user"] --methods [get put]
    assert ($result | all {|r| $r.method in [get put]}) "all should be GET or PUT"
    let names = $result | get name
    assert ($names | all {|n| $n | str starts-with "user"}) "all should be user commands"
}
