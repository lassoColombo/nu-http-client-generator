# Unit tests for the static runtime helpers every generated client carries
# (`src/runtime.nu`). The goldens only prove the text is emitted unchanged;
# these prove what the text DOES. The file is `source`d in a subprocess so its
# private defs are callable without generating a client.

use std/assert
use std/testing *

def rt [expr: string]: nothing -> any {
    let r = (^nu --no-config-file -c $"source src/runtime.nu; ($expr) | to json -r" | complete)
    if $r.exit_code != 0 {
        error make --unspanned { msg: $"runtime expression failed: ($r.stderr)" }
    }
    $r.stdout | from json
}

@test
def "serialize-qp percent-encodes scalars and keys" [] {
    assert equal (rt 'serialize-qp "a b" "x y" "scalar"') ["a%20b=x%20y"]
}

@test
def "serialize-qp joins lists by style or repeats the key" [] {
    assert equal (rt 'serialize-qp "n" [1 2] "csv"') ["n=1,2"]
    assert equal (rt 'serialize-qp "n" [a b] "ssv"') ["n=a%20b"]
    assert equal (rt 'serialize-qp "n" [a b] "pipes"') ["n=a|b"]
    assert equal (rt 'serialize-qp "n" [a b] "multi"') ["n=a" "n=b"]
    assert equal (rt 'serialize-qp "n" [a b] "deepObject"') ["n[]=a" "n[]=b"]
}

@test
def "serialize-qp serializes records per OpenAPI object styles" [] {
    assert equal (rt 'serialize-qp "n" {k: v, j: null} "multi"') ["k=v"] "exploded pairs, null member skipped"
    assert equal (rt 'serialize-qp "n" {k: v, j: w} "csv"') ["n=k,v,j,w"]
    assert equal (rt 'serialize-qp "n" {k: v} "deepObject"') ["n[k]=v"]
}

@test
def "serialize-qp treats a list of records as a list, each element as JSON" [] {
    assert equal (rt 'serialize-qp "n" [{a: 1} {a: 2}] "multi"') ["n=%7B%22a%22%3A1%7D" "n=%7B%22a%22%3A2%7D"]
    assert equal (rt 'serialize-qp "n" [{a: 1}] "csv"') ["n=%7B%22a%22%3A1%7D"]
}

@test
def "serialize-qp drops null and empty-list values" [] {
    assert equal (rt 'serialize-qp "n" null "csv"') []
    assert equal (rt 'serialize-qp "n" [] "multi"') []
}

@test
def "encode-path-segment keeps RFC 3986 unreserved chars literal" [] {
    assert equal (rt 'encode-path-segment "feature/auth-fix a-b.c_d~e"') "feature%2Fauth-fix%20a-b.c_d~e"
    assert equal (rt 'encode-path-segment 42') "42"
}

@test
def "encode-path-array comma-joins elements encoded individually" [] {
    assert equal (rt 'encode-path-array ["a,b" c]') "a%2Cb,c"
    assert equal (rt 'encode-path-array "x"') "x" "a scalar falls through to the segment encoder"
}

@test
def "list elements that are null are dropped, not crashed on" [] {
    assert equal (rt 'serialize-qp "n" [1 null 2] "multi"') ["n=1" "n=2"]
    assert equal (rt 'serialize-qp "n" [null] "csv"') [] "a list of only nulls sends nothing"
    assert equal (rt 'encode-path-array [a null b]') "a,b"
    assert equal (rt 'encode-path-segment null') ""
}

@test
def "encode-path-greedy keeps slashes between encoded segments" [] {
    assert equal (rt 'encode-path-greedy "dir/a b/c%.txt"') "dir/a%20b/c%25.txt"
    assert equal (rt 'encode-path-greedy "single"') "single"
}

@test
def "encode-path-greedy encodes structured and empty values like a segment" [] {
    assert equal (rt 'encode-path-greedy [a b]') (rt 'encode-path-segment [a b]') "a list is compact JSON, not debug text"
    assert equal (rt 'encode-path-greedy {k: "x/y"}') (rt 'encode-path-segment {k: "x/y"}') "a record is never split on its slashes"
    assert equal (rt 'encode-path-greedy null') ""
    assert equal (rt 'encode-path-greedy 42') "42"
}

@test
def "build-url joins base path, template path and query fragments" [] {
    assert equal (rt 'build-url "https://h.test/v1" "/pets" "a=1" "" "b=2"') "https://h.test/v1/pets?a=1&b=2" "empty fragments are dropped"
    assert equal (rt 'build-url "https://h.test/?k=v" "/pets" "a=1"') "https://h.test/pets?k=v&a=1" "a query on the base URL is kept first"
    assert equal (rt 'build-url "https://h.test" ""') "https://h.test/"
    assert equal (rt 'build-url "https://h.test:8080/v1/" "/x//y"') "https://h.test:8080/v1/x/y" "slash runs collapse"
}

@test
def "status-ok falls back to < 400 only when the spec declared no codes" [] {
    assert equal (rt 'status-ok 399 []') true
    assert equal (rt 'status-ok 400 []') false
    assert equal (rt 'status-ok 302 [201 302]') true
    assert equal (rt 'status-ok 303 [201 302]') false
    assert equal (rt 'status-ok 200 [302]') true "any 2xx is always a success"
}

@test
def "handle-response unwraps by flag" [] {
    let ok = '{status: 200, headers: {}, body: {a: 1}}'
    assert equal (rt $"($ok) | handle-response false false []") {a: 1}
    assert equal (rt $"($ok) | handle-response false true []") {status: 200, headers: {}, body: {a: 1}} "--full keeps the envelope"
    assert equal (rt '{status: 204, headers: {}, body: ""} | handle-response false false []') null "204 is nothing"
    assert equal (rt '{status: 500, headers: {}, body: "x"} | handle-response true false []') {status: 500, headers: {}, body: "x"} "--allow-errors returns the raw response"
}

@test
def "handle-response raises on a failed status" [] {
    let r = (^nu --no-config-file -c 'source src/runtime.nu; {status: 404, headers: {}, body: "nf"} | handle-response false false []' | complete)
    assert equal $r.exit_code 1
    assert ($r.stderr | str contains "HTTP 404: nf")
}
