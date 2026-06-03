# Integration tests: generate clients from specs and call real APIs.
# These tests hit live endpoints (httpbin.org, countries.trevorblades.com, petstore3.swagger.io).
# They will fail if the APIs are unreachable.
# Clients are generated from both local files and remote URLs to cover both load paths.

use std/assert
use std/testing *

use ../mod.nu

const COUNTRIES_URL = "https://countries.trevorblades.com/graphql"
const PETSTORE_SPEC_URL = "https://petstore3.swagger.io/api/v3/openapi.json"
const PETSTORE_BASE_URL = "https://petstore3.swagger.io/api/v3"
const POKEAPI_URL = "https://beta.pokeapi.co/graphql/v1beta"

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
    mod openapi ./tests/inputs/openapi-v2/httpbin.json -o ($temp | path join "httpbin.nu")
    mod graphql ./tests/inputs/graphql/countries.json -o ($temp | path join "countries.nu") --default-base-url $COUNTRIES_URL

    # url inputs
    mod openapi $PETSTORE_SPEC_URL -o ($temp | path join "petstore.nu") --default-base-url $PETSTORE_BASE_URL
    mod graphql $POKEAPI_URL -o ($temp | path join "pokeapi.nu") --default-base-url $POKEAPI_URL --name pokeapi

    {
        temp: $temp
        httpbin: ($temp | path join "httpbin.nu")
        countries: ($temp | path join "countries.nu")
        petstore: ($temp | path join "petstore.nu")
        pokeapi: ($temp | path join "pokeapi.nu")
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

# --- petstore REST tests (loaded from URL) ---

@test
def "petstore find pets by status" [] {
    let resp = run-cmd $in.petstore "petstore pet-find-by-status findPetsByStatus --status available --max-time 15sec"
    assert (($resp | length) > 0) "should return at least one pet"
}

@test
def "petstore get pet by id" [] {
    let resp = run-cmd $in.petstore "petstore pet get 987654321 --max-time 15sec"
    assert ($resp.id != null) "pet should have an id"
    assert ($resp.name | is-not-empty) "pet should have a name"
}

# --- pokeapi GraphQL tests (loaded from URL) ---

@test
def "pokeapi query abilities" [] {
    let resp = run-cmd $in.pokeapi $"pokeapi query pokemon-v2-ability --base-url ($POKEAPI_URL) --max-time 15sec --limit 3 --fields [id name]"
    assert equal ($resp | length) 3
    assert equal ($resp | first | get name) "stench"
}

@test
def "pokeapi query ability by pk" [] {
    let resp = run-cmd $in.pokeapi $"pokeapi query pokemon-v2-ability-by-pk 1 --base-url ($POKEAPI_URL) --max-time 15sec --fields [id name is_main_series]"
    assert equal $resp.id 1
    assert equal $resp.name "stench"
}
