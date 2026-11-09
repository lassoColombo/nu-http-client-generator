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
