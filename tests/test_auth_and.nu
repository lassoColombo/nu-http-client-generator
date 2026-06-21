# Behavioral tests for AND-form (multi-scheme) security requirements — D-7 / issue 51.
#
# When an operation's `security` is the AND-form (ONE requirement object listing
# MULTIPLE schemes, e.g. `[{apiKeyA: [], apiKeyB: []}]`), the generated client
# must send ALL required credentials together — one `--token-<scheme>` flag per
# scheme, merged into a single request. The golden files lock the emitted text;
# these tests lock the RUNTIME behavior via `--dry-run` (both headers actually
# present, header+query merge, partial creds, and that single/OR-form ops are
# untouched). All checks are offline — `--dry-run` never hits the network.

use std/assert
use std/testing *

use ../mod.nu

const AUTH_SPEC = "tests/inputs/openapi-v3/auth-edge-cases.yaml"
const GLOBAL_AND_SPEC = "tests/inputs/openapi-v3/auth-global-and-edge-cases.yaml"

# Run a generated command and return its parsed output. Shells out to a clean
# nu process so the test environment stays clean (no env-var leakage into the
# per-scheme token fallbacks).
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
    let client = ($temp | path join "auth.nu")
    let global_client = ($temp | path join "global.nu")
    mod $AUTH_SPEC -o $client
    mod $GLOBAL_AND_SPEC -o $global_client
    { temp: $temp, client: $client, global_client: $global_client }
}

@after-all
def cleanup [] {
    rm --recursive $in.temp
}

# ── AND-form: both required headers are sent ─────────────────────────────

@test
def "and-form sends both header credentials" [] {
    let r = (run-cmd $in.client 'and-header get --token-apikeya K1 --token-apikeyb C1 --dry-run')
    assert equal ($r.headers | get "X-Api-Key-A") "K1" "first scheme header must be sent"
    assert equal ($r.headers | get "X-Api-Key-B") "C1" "second scheme header must be sent"
    # The bug was that only one header (or a bearer fallback) was ever sent.
    assert ("Authorization" not-in ($r.headers | columns)) "must not fall back to bearer Authorization"
    assert equal $r.auth.location "header"
}

# ── AND-form mixing header + query merges both locations ─────────────────

@test
def "and-form merges header and query schemes" [] {
    let r = (run-cmd $in.client 'and-mixed get --token-apikeya K1 --token-querykey Q1 --dry-run')
    assert equal ($r.headers | get "X-Api-Key-A") "K1" "header scheme must be sent"
    assert ($r.url | str contains "api_key=Q1") "query scheme must be appended to the URL"
    assert equal $r.auth.location "header+query" "merged location reflects both schemes"
}

# ── Partial credentials: only the supplied scheme contributes ────────────

@test
def "and-form with partial credentials sends only what is provided" [] {
    let r = (run-cmd $in.client 'and-header get --token-apikeya K1 --dry-run')
    assert equal ($r.headers | get "X-Api-Key-A") "K1" "provided scheme is sent"
    assert ("X-Api-Key-B" not-in ($r.headers | columns)) "absent scheme contributes no header"
}

# ── Regression guard: single-scheme / OR-form ops are unchanged ──────────

@test
def "single-scheme op still uses the shared token flag" [] {
    let r = (run-cmd $in.client 'basic get --token TOK --dry-run')
    assert equal ($r.headers | get "Authorization") "Basic TOK" "single-scheme path is unaffected"
}

# ── The AND-form signature drops --auth-scheme and adds per-scheme flags ──
# Checked against the raw signature block: the introspection `commands` view
# filters `token`/`auth-scheme` via its static builtin-flags list, so it cannot
# prove their ABSENCE — the source text can.

@test
def "and-form signature exposes per-scheme token flags and drops auth-scheme" [] {
    let content = (open $in.client --raw)
    # Isolate the `and-header get` signature block (def line .. closing `]`).
    let sig = ($content
        | lines
        | skip until {|l| $l | str contains 'export def "and-header get"' }
        | take until {|l| $l =~ '^\]' })
    assert ($sig | any {|l| $l | str contains "--token-apikeya" }) "must expose --token-apikeya"
    assert ($sig | any {|l| $l | str contains "--token-apikeyb" }) "must expose --token-apikeyb"
    assert ($sig | all {|l| not ($l | str contains "--auth-scheme") }) "AND-form op must not expose --auth-scheme"
    assert ($sig | all {|l| not ($l | str contains "--token(-t)") }) "AND-form op must not expose the shared --token"
}

# ── GLOBAL AND-form (VTEX shape): ops inherit the top-level requirement ───

@test
def "global and-form is inherited by non-overriding ops" [] {
    let r = (run-cmd $in.global_client 'widgets list --token-appkey AK --token-apptoken AT --dry-run')
    assert equal ($r.headers | get "X-App-Key") "AK" "inherited first scheme header must be sent"
    assert equal ($r.headers | get "X-App-Token") "AT" "inherited second scheme header must be sent"
}

@test
def "global and-form public override drops all auth" [] {
    let r = (run-cmd $in.global_client 'public get --dry-run')
    assert equal $r.auth.location "none" "security: [] override must yield no auth"
    assert (("X-App-Key" not-in ($r.headers | columns)) and ("X-App-Token" not-in ($r.headers | columns))) "public op must send no auth headers"
}
