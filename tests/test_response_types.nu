# Response typing: a client is strict about what it sends and lenient about
# what it receives. nushell checks a command's declared output type when its
# result is bound with `let` (never when it is piped), so a documented
# `record<id: int, …>` made `let r = (cmd)` fail on a real API's null or
# missing field, and on every --dry-run/--full record. The signature
# therefore declares only the shape — `oneof<record, string, nothing>` for an
# object, `oneof<list<any>, record, string, nothing>` for an array, `any`
# otherwise (`string` is --raw, `record` --dry-run/--full, `nothing` a 204) —
# and the documented type lives in the `Returns:` help line and the
# `commands` table. All offline via --dry-run.

use std/assert
use std/testing *

use ../mod.nu

const SPEC = "tests/inputs/openapi-v3/response-type-edge-cases.yaml"

const SHAPES = ["any" "oneof<record, string, nothing>" "oneof<list<any>, record, string, nothing>"]

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
    let client = ($temp | path join "responses.nu")
    mod $SPEC -o $client
    { temp: $temp, client: $client }
}

@after-all
def cleanup [] {
    rm --recursive $in.temp
}

@test
def "every golden command declares only a response shape" [] {
    let typed = (glob tests/expected/**/*.nu | each {|f|
        open --raw $f | lines | parse --regex '^\]: \S+ -> (?<out>.+) \{$' | get out
        | where {|t| $t not-in $SHAPES } | each {|t| $"($f | path relative-to $env.PWD): ($t)" }
    } | flatten)
    assert ($typed | is-empty) $"output types that name fields or scalars:\n($typed | first 10 | str join (char nl))"
}

@test
def "a dry-run result binds with let for every response kind" [] {
    let client = $in.client
    for cmd in [get-profile list-profiles get-count get-etag get-ping] {
        let m = (run-cmd $client $"let r = \(($cmd) --dry-run\); $r.method")
        assert equal $m "get" $"let-bound dry-run of ($cmd)"
    }
}

@test
def "a dry-run result pipes into get" [] {
    assert equal (run-cmd $in.client 'get-count --dry-run | get method') "get"
    assert equal (run-cmd $in.client 'list-profiles --dry-run | get method') "get"
}

@test
def "the commands table reports the documented response type" [] {
    let types = (run-cmd $in.client 'commands | select name return_type' | transpose -r -d)
    assert equal $types.get-profile "record<id: int, name: string>"
    assert equal $types.list-profiles "table<id: int, name: string>"
    assert equal $types.get-count "int"
    assert equal $types.get-healthy "bool"
    assert equal $types.get-etag "string" "a text/plain scalar is documented through the non-JSON media fallback"
    assert equal $types.get-ping "any" "no schema, no documented type"
}

@test
def "the documented type is what the client hands back" [] {
    let types = (run-cmd $in.client 'commands | select name return_type' | transpose -r -d)
    assert equal $types.authorize "any" "a redirect-only operation is not typed by its default error schema"
    assert equal $types.get-report "any" "an XML body is nushell's own tree, not the schema's record"
    assert equal $types.download "binary" "format: binary"
    assert equal $types.get-azure-file "binary" "Azure's type: object, format: file"
    assert equal $types.get-swagger-file "binary" "Swagger 2's type: file"
}

@test
def "help names the documented response type" [] {
    let extra = (run-cmd $in.client 'commands | where name == "get-profile" | get extra_description.0')
    assert ($extra | str contains "Returns: record<id: int, name: string>") $"help must document the response, got: ($extra)"
    let none = (run-cmd $in.client 'commands | where name == "get-ping" | get extra_description.0')
    assert not ($none | str contains "Returns:") "a schemaless response has no Returns line"
}

@test
def "record response command parses when --raw output is piped into from json" [] {
    # Port 1 refuses the connection, so the call fails at runtime — the point
    # is that it gets that far instead of failing to parse.
    let r = (^nu --no-config-file -c $"use '($in.client)' *; get-profile --raw --base-url http://127.0.0.1:1 | from json" | complete)
    assert not ($r.stderr | str contains "input_type_mismatch") $"--raw | from json must parse, got: ($r.stderr)"
    assert not ($r.stderr | str contains "parser") $"no parse error expected, got: ($r.stderr)"
}
