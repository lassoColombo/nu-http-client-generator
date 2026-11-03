# Every single-word builtin command and parser keyword of the RUNNING nushell,
# plus every def the generated module emits itself, used as an operationId.
# The module must parse, introspect, and dry-run every command: a module-level
# `export def "get"` shadows the builtin inside the module's own helpers, which
# is a parse error for most builtins and a silent wrong call for input-only
# ones like `is-not-empty`. The list in model.nu is static; this test is what
# keeps it honest when nushell adds a builtin or render starts calling a new one.

use std/assert
use std/testing *

use ../mod.nu
use ../src/names.nu [EMITTED_DEF_NAMES]

# The module's own defs plus one enum-completer name.
const EMITTED = ($EMITTED_DEF_NAMES ++ [status-completer])

@before-all
def setup []: nothing -> record {
    let temp = mktemp --directory
    let names = (
        help commands
        | where command_type in [built-in keyword]
        | get name
        | where ($it !~ " ")
        | append $EMITTED
        | uniq
        | sort
    )
    let paths = ($names | enumerate | reduce --fold {} {|it, acc|
        $acc | insert $"/p($it.index)" {
            get: {operationId: $it.item, responses: {"200": {description: ok}}}
        }
    })
    let spec = ($temp | path join "spec.json")
    {openapi: "3.0.0", info: {title: probe, version: "1"}, servers: [{url: "https://x.test"}], paths: $paths}
    | to json | save -f $spec
    let client = ($temp | path join "probe.nu")
    mod $spec -o $client
    { temp: $temp, client: $client, expected: ($names | length) }
}

@after-all
def cleanup [] {
    rm -rf $in.temp
}

@test
def "client parses and introspects every command" [] {
    let ctx = $in
    let r = (^nu --no-config-file -c $"use '($ctx.client)'; probe commands | length" | complete)
    assert equal $r.exit_code 0 $"client failed to load: ($r.stderr)"
    assert equal ($r.stdout | str trim | into int) $ctx.expected
}

@test
def "no exported command is named like a builtin, keyword or emitted def" [] {
    let ctx = $in
    let exported = (open --raw $ctx.client | lines | parse --regex '^export def "([^"]+)"' | get capture0)
    let reserved = (
        help commands | where command_type in [built-in keyword] | get name | append $EMITTED
    )
    let clashes = ($exported | where $it in $reserved | where $it != "commands")
    assert equal $clashes [] $"exported commands shadow builtins: ($clashes)"
}

@test
def "every command dry-runs" [] {
    let ctx = $in
    let failures = (
        ^nu --no-config-file -c $"use '($ctx.client)'; probe commands | get name | to json -r"
        | from json
        | par-each {|n|
            let r = (^nu --no-config-file -c $"use '($ctx.client)'; probe ($n) --dry-run | get url" | complete)
            if $r.exit_code != 0 { $"($n): ($r.stderr | lines | first)" } else { null }
        }
        | compact
    )
    assert equal $failures [] $"dry-run failures: ($failures)"
}

@test
def "every helper def a client emits is a reserved name" [] {
    # A def the module emits but EMITTED_DEF_NAMES misses is a name an
    # operationId could take, which is a duplicate_command_def. Every golden
    # together covers the optional helpers (merge-auth, multipart, all verbs).
    let emitted = (glob tests/expected/**/*.nu
        | each {|f| open --raw $f | parse --regex '(?m)^def (?<n>[^ ]+) ' | get n }
        | flatten | uniq)
    let missing = ($emitted | where {|n| ($n not-in $EMITTED_DEF_NAMES) and ($n !~ '-completer(-\d+)?$') })
    assert ($missing | is-empty) $"defs missing from EMITTED_DEF_NAMES: ($missing | str join ', ')"
}
