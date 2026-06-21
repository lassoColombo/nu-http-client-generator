# Behavioral tests for scalar-response output typing — issue 52 (resolves D-10).
#
# A command whose spec response is a scalar leaf (string/int/bool) is polymorphic
# over its flags: record under --dry-run/--full, string under --raw, nothing on
# 204, the scalar on a normal call. The generator annotates it
# `oneof<scalar, string, record, nothing>` so that (a) structured piping
# (`cmd --dry-run | get …`) PARSES — the bug 47.A first hit — and (b) the
# response type stays visible in `help`/`commands` (the D-10 doc loss `-> any`
# caused). These checks lock both halves; all offline via --dry-run.

use std/assert
use std/testing *

use ../mod.nu

const SCALAR_SPEC = "tests/inputs/openapi-v3/scalar-response-edge-cases.yaml"

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
    let client = ($temp | path join "scalar.nu")
    mod $SCALAR_SPEC -o $client
    { temp: $temp, client: $client }
}

@after-all
def cleanup [] {
    rm --recursive $in.temp
}

# ── The original 47.A bug: structured piping on a scalar-response command ──
# Under a bare `-> string`/`-> int` annotation this is a PARSE error. The
# `record` member of the oneof makes it parse; run-cmd would raise on failure.

@test
def "scalar-response command pipes into get under dry-run" [] {
    let r = (run-cmd $in.client 'count get --dry-run | select method url')
    assert equal $r.method "get" "dry-run record must be gettable (oneof record member)"
    assert ($r.url | str ends-with "/count") "url field reachable via structured op"
}

@test
def "scalar-response command pipes into get for string and bool responses too" [] {
    let t = (run-cmd $in.client 'token get --dry-run | get method')
    assert equal $t "get" "string-response command pipes into get"
    let h = (run-cmd $in.client 'healthy get --dry-run | get method')
    assert equal $h "get" "bool-response command pipes into get"
}

# A text/plain (non-JSON) scalar response must ALSO derive the typed oneof,
# via the non-JSON media fallback — not collapse to `any`.
@test
def "text-plain scalar response is typed, not any" [] {
    let rt = (run-cmd $in.client 'commands | where name == "etag get" | get return_type.0')
    assert ($rt | str starts-with "oneof<string") $"text/plain string response must be oneof<string,…>, got: ($rt)"
    let m = (run-cmd $in.client 'etag get --dry-run | get method')
    assert equal $m "get" "text/plain-response command still pipes into get"
}

# ── D-10: the response type is preserved in introspection (not erased to any) ──

@test
def "scalar response type is preserved in the commands table" [] {
    let rt = (run-cmd $in.client 'commands | where name == "count get" | get return_type.0')
    assert ($rt | str starts-with "oneof<int") $"return_type should preserve the int response, got: ($rt)"
    assert ($rt | str contains "record") "oneof must include record (dry-run/full)"
    assert ($rt | str contains "nothing") "oneof must include nothing (204)"
}

# ── Negative controls: non-scalar responses keep their existing annotation ──

@test
def "record response keeps its rich annotation, not a oneof" [] {
    let rt = (run-cmd $in.client 'commands | where name == "profile get" | get return_type.0')
    assert ($rt | str starts-with "record<") $"record response must keep record<…>, got: ($rt)"
}

@test
def "schemaless response stays any" [] {
    let rt = (run-cmd $in.client 'commands | where name == "ping get" | get return_type.0')
    assert equal $rt "any" "no-schema response is genuinely any"
}
