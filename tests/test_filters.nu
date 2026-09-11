# Targeted tests for filtering and naming flags:
# --tags, --prefixes, --methods, --autocompletion-base-urls
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
    let result = mod preview $PETSTORE --tags [pet]
    assert equal ($result | length) 8 "expected 8 pet-tagged commands"
    # Names come from operationIds, so assert on what the filter actually
    # selects on: every pet-tagged petstore op lives under /pet.
    assert ($result | all {|r| $r.path_template | str starts-with "/pet"}) "all commands should be /pet operations"
}

@test
def "tags multiple" [] {
    let result = mod preview $PETSTORE --tags [store user]
    assert equal ($result | length) 11 "expected 11 store+user commands"
    let has_pet = $result | any {|r| $r.path_template | str starts-with "/pet"}
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
    let result = mod preview $PETSTORE --prefixes ["/pet"]
    assert equal ($result | length) 8 "expected 8 commands under /pet"
    assert ($result | all {|r| $r.path_template | str starts-with "/pet"}) "all commands should be /pet operations"
}

@test
def "prefixes rest narrow" [] {
    let names = mod preview $PETSTORE --prefixes ["/store/order"] | get name
    assert equal ($names | length) 3 "expected 3 commands under /store/order"
    let expected = ["place-order", "get-order-by-id", "delete-order"]
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

# ── --autocompletion-base-urls ────────────────────────────────────────

@test
def "urls added to completer" [] {
    let tmp = mktemp --directory
    let out = $tmp | path join "out.nu"
    try {
        mod $PETSTORE -o $out --autocompletion-base-urls ["https://extra.example.com" "https://staging.example.com"]
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
    assert ($result | all {|r| $r.path_template | str starts-with "/user"}) "all should be user operations"
}
