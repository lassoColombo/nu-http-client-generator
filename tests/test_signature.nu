# The `commands` introspection hides the generator's own flags from each
# command's param list using a hand-maintained name list (`SIGNATURE_FLAGS` in
# src/render.nu plus the per-client additions), while `build-signature` writes
# the flags themselves. These checks keep the two in step: a flag the
# signature gains without the list leaks into `commands` as if it were an API
# parameter, and a stale list entry would hide a real one.

use std/assert
use std/testing *

use ../mod.nu

# One single-auth op and one AND-form op (two schemes in one requirement), each
# with no spec params and two response media types, so every generator flag
# that can appear does: --token/--auth-scheme, --token-<scheme>, --accept and,
# under the socket flags below, --unix-socket.
const SPEC = {
    openapi: "3.0.3"
    info: {title: "Signature flags", version: "1.0"}
    servers: [{url: "https://example.com"}]
    components: {securitySchemes: {
        appKey: {type: apiKey, in: header, name: X-App-Key}
        appToken: {type: apiKey, in: header, name: X-App-Token}
    }}
    paths: {
        /single: {get: {
            operationId: single
            security: [{appKey: []}]
            responses: {"200": {description: ok, content: {application/json: {schema: {type: object}}, text/csv: {schema: {type: string}}}}}
        }}
        /both: {get: {
            operationId: both
            security: [{appKey: [], appToken: []}]
            responses: {"200": {description: ok, content: {application/json: {schema: {type: object}}, text/csv: {schema: {type: string}}}}}
        }}
    }
}

@before-all
def setup []: nothing -> record {
    let temp = mktemp --directory
    let spec = ($temp | path join "sig.json")
    $SPEC | to json | save $spec
    let client = ($temp | path join "sig.nu")
    mod $spec -o $client --default-unix-socket /tmp/x.sock
    { temp: $temp, client: $client }
}

@after-all
def cleanup [] {
    rm --recursive $in.temp
}

# Flag names each command declares, as nushell sees them.
def declared-flags [client: string]: nothing -> record {
    let r = (^nu --no-config-file -c $"use '($client)'; scope commands | where name =~ '^sig ' | each {|c| {name: \($c.name | str replace 'sig ' ''\), flags: \($c.signatures | values | first | where parameter_type in [named switch] | get parameter_name\)} } | to json -r" | complete)
    if $r.exit_code != 0 { error make --unspanned { msg: $r.stderr } }
    $r.stdout | from json | reduce --fold {} {|c, acc| $acc | insert $c.name $c.flags }
}

@test
def "no generator flag leaks into the commands param list" [] {
    let r = (^nu --no-config-file -c $"use '($in.client)'; sig commands | select name params | to json -r" | complete)
    assert equal $r.exit_code 0 $r.stderr
    for c in ($r.stdout | from json) {
        assert equal ($c.params | length) 0 $"($c.name) lists generator flags as params: ($c.params | get parameter_name? | default [] | str join ', ')"
    }
}

@test
def "every hidden flag is one some command actually declares" [] {
    let src = (open --raw $in.client)
    let hidden = ($src | parse --regex 'let builtin_flags = (?<l>\[.*\])' | get l.0 | from nuon)
    let flags = (declared-flags $in.client)
    let declared = ($flags | values | flatten | uniq)
    # `help` is nushell's own flag; 0.116's `scope` does not report it for
    # custom commands, and the generator hides it defensively.
    let stale = ($hidden | where {|f| ($f not-in $declared) and ($f != "help") })
    assert ($stale | is-empty) $"hidden-flag list names flags no command declares: ($stale | str join ', ')"
}
