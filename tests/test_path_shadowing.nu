# Behavioral tests for path-param shadowing.
#
# OpenAPI keys a parameter by name AND location, so a path `{id}` next to a
# query `id` is legal (Django REST Framework emits it for every detail route
# with an `id` filter). In a generated `def` both would bind `$id`: the flag is
# declared after the positional, so it wins, and the path value is lost — the
# command fails with "path parameter 'id' must be non-empty" whatever the
# caller passes. The path positional keeps the name; the query/header/cookie
# flag takes its group prefix (`--qp-id`, `--hdr-id`, `--ck-id`), the same rule
# reserved names already follow. All checks are offline, via --dry-run.

use std/assert
use std/testing *

use ../mod.nu

const SPEC = "tests/inputs/openapi-v3/path-shadowing-edge-cases.yaml"
const BODY_SPEC = "tests/inputs/openapi-v3/body-field-collision-edge-cases.yaml"
const RESERVED_SPEC = "tests/inputs/openapi-v3/reserved-name-edge-cases.yaml"
const GREEDY_SPEC = "tests/inputs/openapi-v3/greedy-path-edge-cases.yaml"

def run-cmd [client: string, cmd: string]: nothing -> any {
    let result = ^nu --no-config-file -c $"use '($client)' *; ($cmd) | to json -r" | complete
    if $result.exit_code != 0 {
        error make --unspanned { msg: $"nu -c failed: ($result.stderr)" }
    }
    $result.stdout | from json
}

@before-all
def setup []: nothing -> record {
    let temp = mktemp --directory
    let client = ($temp | path join "shadowing.nu")
    mod $SPEC -o $client
    let body_client = ($temp | path join "collision.nu")
    mod $BODY_SPEC -o $body_client
    let reserved_client = ($temp | path join "reserved.nu")
    mod $RESERVED_SPEC -o $reserved_client
    let greedy_client = ($temp | path join "greedy.nu")
    mod $GREEDY_SPEC -o $greedy_client
    { temp: $temp, client: $client, body_client: $body_client, reserved_client: $reserved_client, greedy_client: $greedy_client }
}

@after-all
def cleanup [] {
    rm --recursive $in.temp
}

@test
def "a query param named like a path param no longer swallows it" [] {
    let r = (run-cmd $in.client 'list-group-members 42 --dry-run')
    assert equal $r.url "https://example.com/api/groups/42/members"
}

@test
def "the clashing query param is reachable under its prefixed flag" [] {
    let r = (run-cmd $in.client 'list-group-members 42 --qp-id 7 --status OPE --dry-run')
    assert equal $r.url "https://example.com/api/groups/42/members?id=7&status=OPE" "the wire name stays `id`"
    assert equal $r.query.id 7
}

@test
def "header and cookie params take their own prefix" [] {
    let r = (run-cmd $in.client 'list-tenant-things acme --qp-tenant q --hdr-tenant h --ck-tenant c --dry-run')
    assert equal $r.url "https://example.com/api/tenants/acme/things?tenant=q"
    assert equal $r.headers.tenant "h" "header keeps its spec name"
    assert ($r.headers.Cookie | str contains "tenant=c") "cookie keeps its spec name"
}

@test
def "names that only clash once sanitized are separated too" [] {
    let r = (run-cmd $in.client 'list-user-sessions u1 --qp-user-id x --dry-run')
    assert equal $r.url "https://example.com/api/users/u1/sessions?user_id=x"
}

@test
def "path, query and body can all carry the same name" [] {
    let r = (run-cmd $in.client 'create-group-note 42 hello --qp-id 7 --body-id 9 --dry-run')
    assert equal $r.url "https://example.com/api/groups/42/notes?id=7"
    assert equal $r.body {id: 9, text: "hello"}
}

@test
def "two body fields that sanitize alike bind two variables" [] {
    let r = (run-cmd $in.body_client 'mixed-case A --user-id-body B --dry-run')
    assert equal $r.body {user_id: "A", userId: "B"}
    let r = (run-cmd $in.body_client 'both-required A --user-id-body B --dry-run')
    assert equal $r.body {user_id: "A", userId: "B"}
}

@test
def "a third spelling and a second reserved name get the numeric sweep" [] {
    let r = (run-cmd $in.body_client 'triple-spelling --user-id A --user-id-body B --user-id-body-2 C --dry-run')
    assert equal $r.body {user_id: "A", userId: "B", "user-id": "C"}
    let r = (run-cmd $in.body_client 'reserved-twice --body-input A --body-input-2 B --dry-run')
    assert equal $r.body {input: "A", Input: "B"}
}

@test
def "path params named like body-code internals are not shadowed" [] {
    let r = (run-cmd $in.reserved_client 'run-job IN BASE --sort s --dry-run')
    assert equal $r.url "https://example.com/api/jobs/IN/BASE"
    assert equal $r.body {sort: "s"}
}

# The invariant itself, over every golden input: no generated command binds
# the same variable twice, whether through two positionals, two flags, or a
# positional and a flag.
@test
def "a greedy label declared with its plus is one greedy positional" [] {
    let r = (run-cmd $in.greedy_client 'proxy-get "a/b c" --dry-run')
    assert equal $r.url "https://s3.example.com/proxy/a/b%20c" "the slash survives, the space is encoded"
}

@test
def "no golden command binds a variable twice" [] {
    let clashes = (glob tests/expected/**/baseline.nu | each {|f|
        open --raw $f | lines | split list --regex '^export def ' | skip 1 | each {|blk|
            let sig = ($blk | take while {|l| not ($l | str starts-with ']') })
            let positionals = ($sig | parse --regex '^  (?<n>[a-z_][a-z0-9_]*): ' | get n)
            let flags = ($sig | parse --regex '^  --(?<n>[a-z0-9-]+)' | get n | str replace --all '-' '_')
            $positionals | append $flags | uniq --count | where count > 1 | each {|v| $"($f | path relative-to $env.PWD): `$($v.value)`" }
        } | flatten
    } | flatten)
    assert ($clashes | is-empty) $"commands binding a variable twice:\n($clashes | str join (char nl))"
}
