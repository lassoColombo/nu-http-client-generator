# Integration tests: generate clients from specs and call real APIs.
# These tests hit live endpoints (httpbingo.org, api.apis.guru).
# They will fail if the APIs are unreachable.
# Clients are generated from both local files (httpbin) and remote URLs
# (apis.guru) to cover both spec-load paths.
#
# Both targets are no-auth public APIs chosen for reliability: httpbingo.org is
# an HTTP echo service, and api.apis.guru hosts the entire client collection
# (if it were down, nothing in this project would work anyway).
# We deliberately avoid petstore3.swagger.io — its demo backend intermittently
# returns HTTP 500 on real calls, which made these tests flaky. We also moved
# off the original httpbin.org: its hosted instance grew chronically unreliable
# (503/504), so we target httpbingo.org (the maintained go-httpbin port), which
# is API-compatible across every endpoint these tests touch.

use std/assert
use std/testing *

use ../mod.nu

# apis.guru: no-auth, server baked into the spec (https://api.apis.guru/v2).
const APISGURU_SPEC_URL = "https://api.apis.guru/v2/specs/apis.guru/2.2.0/openapi.json"

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

    # local-file load path
    mod ./tests/fixtures/httpbin.json -o ($temp | path join "httpbin.nu")

    # remote-URL load path
    mod $APISGURU_SPEC_URL -o ($temp | path join "apisguru.nu")

    {
        temp: $temp
        httpbin: ($temp | path join "httpbin.nu")
        apisguru: ($temp | path join "apisguru.nu")
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
    assert equal $resp.url "https://httpbingo.org/get"
}

@test
def "httpbin headers returns headers record" [] {
    let resp = run-cmd $in.httpbin "httpbin headers get --max-time 15sec"
    assert ($resp.headers | describe | str starts-with "record") "headers should be a record"
}

@test
def "httpbin user-agent returns user-agent" [] {
    let resp = run-cmd $in.httpbin "httpbin user-agent get --max-time 15sec"
    # return "skip"
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

# --- apis.guru REST tests (loaded from URL) ---

@test
def "apisguru metrics returns counts" [] {
    # No-param GET returning a flat record of integers.
    let resp = run-cmd $in.apisguru "apisguru metrics-json get --max-time 15sec"
    assert (($resp.numAPIs | into int) > 0) "numAPIs should be positive"
    assert (($resp.numEndpoints | into int) > 0) "numEndpoints should be positive"
}

@test
def "apisguru providers returns list" [] {
    # No-param GET returning a collection ({data: [provider strings]}).
    let resp = run-cmd $in.apisguru "apisguru providers-json get --max-time 15sec"
    assert (($resp.data | length) > 0) "should return at least one provider"
    assert ($resp.data | all {|p| ($p | describe) == "string" }) "providers should be strings"
}

@test
def "apisguru provider lookup by path param" [] {
    # GET with a single path param returning an object (the provider's APIs).
    let resp = run-cmd $in.apisguru "apisguru ap-is get 'apis.guru' --max-time 15sec"
    assert ($resp.apis | is-not-empty) "provider should expose at least one API"
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
    let r = run-cmd $in.httpbin "httpbin redirect-to get --url 'http://x.test' --dry-run"
    assert equal $r.query.url "http://x.test"
    # The wire URL should also contain the param, percent-encoded (so $r.url and
    # $r.query agree).
    assert ($r.url | str contains "url=http%3A%2F%2Fx.test")
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
def "dry-run body is logical record" [] {
    # POST with a body: the logical (pre-serialization) body is a record keyed by
    # spec field name, regardless of the wire content-type.
    let r = run-cmd $in.httpbin "httpbin redirect-to create 'http://b.test' --status-code 302 --dry-run"
    assert equal ($r.body | describe | str starts-with "record") true
    assert equal $r.body.url "http://b.test"
    assert equal $r.body.status_code 302
}

@test
def "dry-run record has no query_string field" [] {
    # Breaking change: cycle-29's misnamed field is gone. Anything reading
    # $r.query_string should fail loudly so callers migrate to $r.query.
    let r = run-cmd $in.httpbin "httpbin get get --dry-run"
    assert equal ($r.query_string? == null) true
}
