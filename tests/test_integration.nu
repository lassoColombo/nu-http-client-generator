# Integration tests: generate clients from specs and call real APIs.
# These tests hit live endpoints (httpbin.org, countries.trevorblades.com).
# They will fail if the APIs are unreachable.

use std/assert
use std/testing *

use ../mod.nu

const COUNTRIES_URL = "https://countries.trevorblades.com/graphql"

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

    mod openapi ./tests/inputs/openapi-v2/httpbin.json -o ($temp | path join "httpbin.nu")
    mod graphql ./tests/inputs/graphql/countries.json -o ($temp | path join "countries.nu") --default-base-url $COUNTRIES_URL

    {
        temp: $temp
        httpbin: ($temp | path join "httpbin.nu")
        countries: ($temp | path join "countries.nu")
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
    let resp = run-cmd $in.httpbin "httpbin anything post --max-time 15sec"
    assert equal $resp.method "POST"
}

# --- countries GraphQL tests ---

@test
def "graphql country by code returns Italy" [] {
    let resp = run-cmd $in.countries $"countries query country IT --base-url ($COUNTRIES_URL) --max-time 15sec --fields [name capital emoji]"
    assert equal $resp.name "Italy"
    assert equal $resp.capital "Rome"
}

@test
def "graphql continents returns 7 items" [] {
    let resp = run-cmd $in.countries $"countries query continents --base-url ($COUNTRIES_URL) --max-time 15sec --fields [code name]"
    assert equal ($resp | length) 7
    assert (($resp | get code) | any { $in == "EU" }) "should contain Europe"
}

@test
def "graphql language returns Italian" [] {
    let resp = run-cmd $in.countries $"countries query language it --base-url ($COUNTRIES_URL) --max-time 15sec --fields [name native]"
    assert equal $resp.name "Italian"
    assert equal $resp.native "Italiano"
}

@test
def "graphql countries filtered by code" [] {
    let resp = run-cmd $in.countries $"countries query countries --base-url ($COUNTRIES_URL) --max-time 15sec --filter-code {eq: US} --fields [name code]"
    assert equal ($resp | length) 1
    assert equal ($resp | first | get name) "United States"
}
