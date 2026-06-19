# Integration tests: generate clients from specs and call real APIs.
# These tests hit live endpoints (httpbin.org, petstore3.swagger.io).
# They will fail if the APIs are unreachable.
# Clients are generated from both local files and remote URLs to cover both load paths.

use std/assert
use std/testing *

use ../mod.nu

const PETSTORE_SPEC_URL = "https://petstore3.swagger.io/api/v3/openapi.json"
const PETSTORE_BASE_URL = "https://petstore3.swagger.io/api/v3"

# Run a command using a generated client module and return parsed output.
# Shells out to a clean nu process to avoid polluting the test environment.
def run-cmd [client: string, cmd: string]: nothing -> any {
    let result = ^nu -c $"use '($client)'; ($cmd) | to json -r" | complete
    if $result.exit_code != 0 {
        error make --unspanned { msg: $"nu -c failed: ($result.stderr)" }
    }
    $result.stdout | from json
}

@before-all
def setup []: nothing -> record {
    let temp = mktemp --directory

    # file inputs
    mod ./tests/inputs/openapi-v2/httpbin.json -o ($temp | path join "httpbin.nu")

    # url inputs
    mod $PETSTORE_SPEC_URL -o ($temp | path join "petstore.nu") --default-base-url $PETSTORE_BASE_URL

    {
        temp: $temp
        httpbin: ($temp | path join "httpbin.nu")
        petstore: ($temp | path join "petstore.nu")
    }
}

@after-all
def cleanup [] {
    rm --recursive $in.temp
}

# --- httpbin REST tests ---

@test
def "httpbin ip returns origin" [] {
    let resp = run-cmd $in.httpbin "httpbin ip get --max-time 15sec"
    assert ($resp.origin | is-not-empty) "origin should not be empty"
}

@test
def "httpbin get returns request url" [] {
    let resp = run-cmd $in.httpbin "httpbin get get --max-time 15sec"
    assert equal $resp.url "https://httpbin.org/get"
}

@test
def "httpbin headers returns headers record" [] {
    let resp = run-cmd $in.httpbin "httpbin headers get --max-time 15sec"
    assert ($resp.headers | describe | str starts-with "record") "headers should be a record"
}

@test
def "httpbin user-agent returns user-agent" [] {
    let resp = run-cmd $in.httpbin "httpbin user-agent get --max-time 15sec"
    let ua = $resp | get "user-agent"
    assert ($ua | is-not-empty) "user-agent should not be empty"
}

@test
def "httpbin uuid returns valid uuid" [] {
    let resp = run-cmd $in.httpbin "httpbin uuid get --max-time 15sec"
    assert ($resp.uuid =~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') "should be a valid UUID"
}

@test
def "httpbin anything post echoes method" [] {
    let resp = run-cmd $in.httpbin "httpbin anything create --max-time 15sec"
    assert equal $resp.method "POST"
}

# --- petstore REST tests (loaded from URL) ---

@test
def "petstore find pets by status" [] {
    let resp = run-cmd $in.petstore "petstore pet-find-by-status find --status available --max-time 15sec"
    assert (($resp | length) > 0) "should return at least one pet"
}

@test
def "petstore get pet by id" [] {
    # First find an existing pet, then fetch it by ID
    let pets = run-cmd $in.petstore "petstore pet-find-by-status find --status available --max-time 15sec"
    assert (($pets | length) > 0) "should find at least one pet to test with"
    let pet_id = ($pets | first | get id)
    let resp = run-cmd $in.petstore $"petstore pet get ($pet_id) --max-time 15sec"
    assert ($resp.id != null) "pet should have an id"
    assert ($resp.name | is-not-empty) "pet should have a name"
}

# --- dry-run shape tests ---
# These don't hit the network; they only check the record shape returned by
# --dry-run. Verifies the redesigned shape (issue 32): dry_run marker, query
# record by spec name, structured auth metadata, logical body across content-types.

@test
def "dry-run record has dry_run marker" [] {
    let r = run-cmd $in.httpbin "httpbin get get --dry-run"
    assert equal $r.dry_run true
    assert equal $r.method "get"
}

@test
def "dry-run query record carries user-passed params by spec name" [] {
    let r = run-cmd $in.petstore "petstore pet-find-by-status find --status available --dry-run"
    assert equal $r.query.status "available"
    # The wire URL should also contain the param (so $r.url and $r.query agree)
    assert ($r.url | str contains "status=available")
}

@test
def "dry-run query record is empty for no-query ops" [] {
    let r = run-cmd $in.httpbin "httpbin get get --dry-run"
    assert equal ($r.query | columns | length) 0
}

@test
def "dry-run auth metadata surfaces scheme and location" [] {
    let r = run-cmd $in.httpbin "httpbin get get --dry-run"
    # httpbin needs no token → scheme falls back, location is "none"
    assert equal $r.auth.location "none"
    # When a token IS supplied (bearer default), location should be "header"
    let r2 = run-cmd $in.httpbin "httpbin get get --token T --dry-run"
    assert equal $r2.auth.location "header"
    assert equal $r2.auth.scheme "bearer"
}

@test
def "dry-run body is logical record for json body" [] {
    let r = run-cmd $in.petstore "petstore pet create fluffy [\"http://x.jpg\"] --id 42 --status sold --dry-run"
    assert equal ($r.body | describe | str starts-with "record") true
    assert equal $r.body.name "fluffy"
    assert equal $r.body.id 42
    assert equal $r.body.status "sold"
}

@test
def "dry-run record has no query_string field" [] {
    # Breaking change: cycle-29's misnamed field is gone. Anything reading
    # $r.query_string should fail loudly so callers migrate to $r.query.
    let r = run-cmd $in.httpbin "httpbin get get --dry-run"
    assert equal ($r.query_string? == null) true
}
