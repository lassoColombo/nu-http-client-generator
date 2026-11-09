# Every golden client must parse as a module. The golden diff only proves the
# text did not change; a spec string that leaks a newline out of a `#` comment
# (a YAML block-scalar title) changes no existing golden and still produces a
# module nushell refuses to load. `nu-check` runs sequentially: it is not
# reliable under `par-each`.

use std/assert
use std/testing *

@test
def "every golden client parses as a module" [] {
    let broken = (glob tests/expected/**/*.nu | where {|f| not (nu-check --as-module $f) } | each { path relative-to $env.PWD })
    assert ($broken | is-empty) $"goldens that do not parse:\n($broken | str join (char nl))"
}

@test
def "every runtime file parses" [] {
    let broken = (glob src/runtime*.nu | where {|f| not (nu-check $f) } | each { path relative-to $env.PWD })
    assert ($broken | is-empty) $"runtime files that do not parse: ($broken | str join ', ')"
}

# render's `runtime-defs` splits these files on blank lines and keeps the
# blocks holding a wanted def. A blank line inside a def would cut it in two,
# and two defs in one block would always travel together.
@test
def "spliced runtime files hold one def per blank-line block" [] {
    for f in [src/runtime-send.nu src/runtime-send-socket.nu src/runtime-auth-and.nu] {
        let blocks = (open --raw $f | split row "\n\n")
        let defs = ($blocks | each {|b| $b | parse --regex '(?m)^def (?<n>[^ ]+) ' | length })
        assert ($defs | all {|n| $n <= 1 }) $"($f): a block holds more than one def"
        let total = (open --raw $f | parse --regex '(?m)^def (?<n>[^ ]+) ' | length)
        assert equal ($defs | math sum) $total $"($f): a def is split across blocks"
        let unclosed = ($blocks | where {|b| ($b =~ '(?m)^def ') and not ($b | str trim --right | str ends-with "\n}") })
        assert ($unclosed | is-empty) $"($f): a def block does not end with its closing brace"
    }
}
