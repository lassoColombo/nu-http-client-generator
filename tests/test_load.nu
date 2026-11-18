# Unit tests for spec loading in `src/spec/spec.nu` (`load-spec`): integers
# nushell's `from yaml` refuses are read as digit strings instead of failing
# the spec, and a body that parses as neither JSON nor YAML says why.

use std/assert
use std/testing *

use ../src/spec/spec.nu

# Load `text` from a file named `name` in a fresh directory.
def load-text [name: string, text: string] {
    let dir = (mktemp --directory)
    let file = ($dir | path join $name)
    $text | save $file
    let result = (try { {ok: (spec load-spec $file).data} } catch {|e| {err: $e.msg} })
    rm --recursive $dir
    $result
}

const BIG_INTS = "openapi: 3.0.3
info: {title: t, version: '1'}
paths: {}
min: -9223372036854775808
max: 9223372036854775807
seq:
  - 18446744073709551615 # uint64
flow: [0, 99999999999999999999, -9223372036854775807]
quoted: '18446744073709551615'
"

@test
def "integers outside i64 are read as their digits" [] {
    let doc = (load-text "spec" $BIG_INTS).ok
    assert equal $doc.min "-9223372036854775808" "i64::MIN, which from yaml refuses"
    assert equal $doc.max 9223372036854775807 "i64::MAX parses as is and stays an int"
    assert equal $doc.seq ["18446744073709551615"] "a sequence item, before a comment"
    assert equal $doc.flow [0, "99999999999999999999", -9223372036854775807] "only the out-of-range flow item changes"
    assert equal $doc.quoted "18446744073709551615" "an already quoted scalar is left alone"
}

@test
def "a yaml extension takes the same retry" [] {
    assert equal (load-text "spec.yaml" $BIG_INTS).ok.min "-9223372036854775808"
}

@test
def "a broken yaml spec names the defect and where it is" [] {
    let err = (load-text "spec" "openapi: 3.0.3\nmin: -9223372036854775808\npaths: [\n").err
    assert str contains $err "invalid YAML: unclosed bracket '['"
    assert str contains $err "line 3"
}

@test
def "an html page is not reported as a yaml defect" [] {
    let err = (load-text "spec" "<html>\n<p>Error: 502 Bad Gateway</p>\n</html>\n").err
    assert str contains $err "not valid JSON or YAML"
}
