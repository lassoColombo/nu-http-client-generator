# Unit tests for the request runtime every generated client carries
# (`src/runtime.nu`). The goldens prove the text is emitted unchanged; these
# prove what the text DOES. The file is `source`d in a subprocess, after a
# `CLIENT` constant like the one a generated client declares, so its private
# defs are callable without generating a client.

use std/assert
use std/testing *

# The client constant the runtime reads; a test may pass its own.
const CLIENT = {
    base_url: "https://api.test/v1"
    token_env_var: "RT_TEST_TOKEN"
    timeout: 30sec
    default_headers: {}
    auth_schemes: [
        {name: bearer, in: header, header_name: Authorization, prefix: Bearer}
        {name: x-api-key, in: header, header_name: X-Api-Key, prefix: ""}
        {name: "query-api key", in: query, header_name: "api key", prefix: ""}
        {name: cookie-sid, in: cookie, header_name: sid, prefix: ""}
        {name: basic-credentials, in: header, header_name: Authorization, prefix: Basic, base64: true}
    ]
}

# The generator's own flags, as every command passes them to `http-request`.
const ARGS = {base_url: null, token: null, auth_scheme: null, insecure: false, max_time: null, raw: false, allow_errors: false, full: false, dry_run: true}

def run-rt [expr: string, client: any]: nothing -> record {
    ^nu --no-config-file -c $"const CLIENT = ($client | default $CLIENT | to nuon); source src/runtime.nu; ($expr) | to json -r" | complete
}

def rt [expr: string, --client: record]: nothing -> any {
    let r = (run-rt $expr $client)
    if $r.exit_code != 0 {
        error make --unspanned { msg: $"runtime expression failed: ($r.stderr)" }
    }
    $r.stdout | from json
}

# The error message a runtime expression fails with.
def rt-error [expr: string]: nothing -> string {
    let r = (run-rt $expr null)
    assert ($r.exit_code != 0) $"expected an error from: ($expr)"
    $r.stderr
}

# `build-request`'s {req, wire} for a descriptor, the spec args (merged over
# the generator's flags) and pipeline input.
def build [op: record, args: record = {}, input: any = null, --client: record]: nothing -> record {
    rt $"build-request ($op | to nuon) ($ARGS | merge $args | to nuon) ($input | to nuon)" --client=$client
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
    assert equal (rt 'build-url "https://h.test:8080/v1//" "//x"') "https://h.test:8080/v1/x" "the seam is one slash"
    assert equal (rt 'build-url "https://h.test:8080/v1/" "/x//y"') "https://h.test:8080/v1/x//y" "slashes inside the path are data"
}

@test
def "a greedy value with a doubled slash reaches the URL intact" [] {
    assert equal (rt 'build-url "https://s3.test" ({k: (encode-path-greedy "dir//a b.txt")} | format pattern "/b/{k}")') "https://s3.test/b/dir//a%20b.txt"
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
    assert (rt-error '{status: 404, headers: {}, body: "nf"} | handle-response false false []' | str contains "HTTP 404: nf")
}

@test
def "merge-body-input merges a piped record under the flags" [] {
    for mode in [record list scalar] {
        assert equal (rt $'merge-body-input {a: 1, b: 2} {b: 3} "($mode)"') {a: 1, b: 3}
        assert equal (rt $'merge-body-input {a: 1} null "($mode)"') {a: 1}
    }
}

@test
def "merge-body-input passes a piped list only for an array variant" [] {
    assert equal (rt 'merge-body-input [x y] null "list"') [x y]
    assert equal (rt 'merge-body-input [{a: 1}] null "list"') [{a: 1}]
    assert equal (rt 'merge-body-input [x y] {b: 1} "record"') {b: 1}
}

@test
def "merge-body-input takes a piped scalar only when the flags gave nothing" [] {
    assert equal (rt 'merge-body-input "text" null "scalar"') "text"
    assert equal (rt 'merge-body-input "text" "flag" "scalar"') "flag"
    assert equal (rt 'merge-body-input "text" null "record"') null
}

@test
def "merge-headers lets the right side win except for cookies" [] {
    assert equal (rt 'merge-headers {A: 1, B: 2} {B: 3}') {A: 1, B: 3}
    assert equal (rt 'merge-headers {Cookie: "s=1"} {Cookie: "l=it"}') {Cookie: "s=1; l=it"} "both cookie strings are kept"
    assert equal (rt 'merge-headers {Cookie: "s=1"} {A: 1}') {A: 1, Cookie: "s=1"}
    assert equal (rt 'merge-headers {A: 1} {Cookie: ""}') {A: 1} "an empty cookie adds no header"
}

@test
def "merge-body-input keeps the flags when nothing is piped" [] {
    for mode in [record list scalar] {
        assert equal (rt $'merge-body-input null {b: 1} "($mode)"') {b: 1}
    }
}

@test
def "build-auth places the token where its scheme says" [] {
    assert equal (rt 'build-auth t bearer') {scheme: bearer, headers: {Authorization: "Bearer t"}, query: "", location: header}
    assert equal (rt 'build-auth t x-api-key').headers {X-Api-Key: t}
    assert equal (rt 'build-auth "a b" "query-api key"') {scheme: "query-api key", headers: {}, query: "api%20key=a%20b", location: query}
    assert equal (rt 'build-auth t cookie-sid').headers {Cookie: "sid=t"}
    assert equal (rt 'build-auth "user:pass" basic-credentials').headers {Authorization: "Basic dXNlcjpwYXNz"}
    assert equal (rt 'build-auth t made-up').headers {Authorization: "Bearer t"} "an unknown scheme sends a bearer token"
}

@test
def "build-auth sends nothing without a token or with the none scheme" [] {
    assert equal (rt 'build-auth "" bearer').location none
    assert equal (rt 'build-auth t none') {scheme: none, headers: {}, query: "", location: none}
}

@test
def "build-auth falls back to the client token env var" [] {
    with-env {RT_TEST_TOKEN: e} {
        assert equal (rt 'build-auth').headers {Authorization: "Bearer e"}
    }
}

@test
def "build-request fills the path, the query and the url" [] {
    let op = {
        method: get, path: "/pets/{petId}/{tags}/{key}"
        path_params: [{name: petId, var: pet_id}, {name: tags, var: tags, encode: array}, {name: key, var: key, encode: greedy}]
        query: [{name: limit, var: limit}, {name: q, var: q, style: multi}, {name: unset, var: unset}]
        accept: [application/json], ok: [200], auth: bearer
    }
    let r = (build $op {pet_id: "a/b", tags: [x "y,z"], key: "d/e f", limit: 5, q: [1 2], unset: null})
    assert equal $r.req.url "https://api.test/v1/pets/a%2Fb/x,y%2Cz/d/e%20f?limit=5&q=1&q=2"
    assert equal $r.req.query {limit: 5, q: [1 2]} "the dry-run query is keyed by spec name, unset params left out"
    assert equal $r.req.headers {Accept: application/json}
    assert equal [$r.req.body $r.req.content_type $r.wire] [null null null]
    assert equal $r.req.auth {scheme: bearer, location: none}
}

@test
def "build-request refuses an empty path value" [] {
    let op = {method: get, path: "/p/{id}", path_params: [{name: id, var: id}], accept: [a/b], ok: [], auth: bearer}
    assert (rt-error $"build-request ($op | to nuon) ($ARGS | merge {id: ''} | to nuon) null" | str contains "path parameter 'id' must be non-empty")
}

@test
def "build-request applies a required default and refuses a missing value" [] {
    let op = {
        method: get, path: "/r"
        query: [{name: kind, var: kind, required: true, default: basic}]
        header: [{name: X-Id, var: x_id, required: true}, {name: Content-Type, var: content_type, required: true}]
        accept: [application/json], ok: [], auth: bearer
    }
    let r = (build $op {kind: null, x_id: 7, content_type: null})
    assert equal $r.req.url "https://api.test/v1/r?kind=basic"
    assert equal $r.req.query {kind: basic}
    assert equal $r.req.headers {Accept: application/json, X-Id: 7} "a Content-Type param is never missing"
    let args = ($ARGS | merge {kind: null, x_id: null, content_type: null} | to nuon)
    assert (rt-error $"build-request ($op | to nuon) ($args) null" | str contains "required header parameter 'X-Id' missing: pass --x-id")
}

@test
def "build-request comma-joins array headers and joins every cookie" [] {
    let op = {
        method: get, path: "/c"
        header: [{name: X-Tags, var: x_tags, array: true}]
        cookie: [{name: theme, var: theme}, {name: ids, var: ids, array: true}, {name: gone, var: gone}]
        accept: [application/json], ok: [], auth: cookie-sid
    }
    let r = (build $op {x_tags: [a null b], theme: dark, ids: [1 2], gone: null, token: t})
    assert equal $r.req.headers {Accept: application/json, X-Tags: "a,b", Cookie: "sid=t; theme=dark; ids=1,2"}
    assert equal $r.req.auth {scheme: cookie-sid, location: cookie}
}

@test
def "build-request assembles a JSON body from its fields and pipeline input" [] {
    let op = {
        method: post, path: "/b", content_type: application/json
        body: {kind: json, fields: [{name: name, var: name}, {name: tag, var: tag}, {name: id, var: id, required: true}]}
        accept: [application/json], ok: [201], auth: bearer
    }
    let r = (build $op {name: n, tag: null, id: 3} {extra: 1, name: piped})
    assert equal $r.req.body {extra: 1, name: n, id: 3} "a flag wins over the piped record"
    assert equal $r.wire '{"extra":1,"name":"n","id":3}'
    assert equal $r.req.content_type application/json
    assert equal (build $op {name: null, tag: null, id: null} {id: 9}).req.body {id: 9} "a piped record satisfies a required field"
    let args = ($ARGS | merge {name: null, tag: null, id: null} | to nuon)
    assert (rt-error $"build-request ($op | to nuon) ($args) null" | str contains "required body field 'id' missing: pass --id or pipe a record")
}

@test
def "build-request encodes every JSON value, empty and scalar ones included" [] {
    let op = {
        method: put, path: "/j", content_type: application/json
        body: {kind: json, accepts: scalar}
        accept: [application/json], ok: [], auth: bearer
    }
    assert equal (build $op {body: []}).wire "[]"
    assert equal (build $op {body: {}}).wire "{}"
    assert equal (build $op {body: 5}).wire "5"
    assert equal (build $op {body: false}).wire "false"
    assert equal (build $op {body: '{"pre":1}'}).wire '{"pre":1}' "a string is already JSON text"
    assert equal (build $op {body: null}).wire null "no body sends nothing"
    let patch = ($op | merge {content_type: application/merge-patch+json, body: {kind: json, fields: [{name: a, var: a}]}})
    assert equal (build $patch {a: 1}).wire '{"a":1}' "a +json type is JSON"
}

@test
def "a per-field body without flags or input is no body, a piped empty record is one" [] {
    let op = {
        method: post, path: "/p", content_type: application/json
        body: {kind: json, fields: [{name: a, var: a}]}
        accept: [application/json], ok: [], auth: bearer
    }
    let r = (build $op {a: null})
    assert equal [$r.req.body $r.wire] [null null]
    assert equal (build $op {a: null} {}).wire "{}"
}

@test
def "build-request encodes form and opaque bodies for the wire" [] {
    let form = {
        method: post, path: "/f", content_type: application/x-www-form-urlencoded
        body: {kind: form, fields: [{name: tags, var: tags, join: ","}, {name: n, var: n}]}
        accept: [application/json], ok: [], auth: bearer
    }
    let r = (build $form {tags: [a b], n: "x y"})
    assert equal $r.req.body {tags: "a,b", n: "x y"} "a csv form array is one joined value"
    assert equal $r.wire ({tags: "a,b", n: "x y"} | url build-query)
    let opaque = ($form | merge {content_type: text/plain, body: {kind: opaque, accepts: scalar}})
    let r = (build $opaque {body: null} "raw text")
    assert equal [$r.req.body $r.wire] ["raw text" "raw text"] "a piped scalar is the body"
    assert equal (build $opaque {body: 42}).wire "42"
    let args = ($ARGS | merge {body: {a: 1}} | to nuon)
    assert (rt-error $"build-request ($opaque | to nuon) ($args) null" | str contains "a text/plain body must be a string or binary")
}

@test
def "a Content-Type header param picks the body encoding at call time" [] {
    let op = {
        method: post, path: "/t", content_type: application/json
        header: [{name: Content-Type, var: content_type, required: true}]
        body: {kind: json, fields: [{name: a, var: a}]}
        accept: [application/json], ok: [], auth: bearer
    }
    let r = (build $op {content_type: application/x-www-form-urlencoded, a: "1 2"})
    assert equal $r.wire ({a: "1 2"} | url build-query)
    assert equal $r.req.content_type application/x-www-form-urlencoded
    assert equal $r.req.headers.Content-Type application/x-www-form-urlencoded
    let r = (build $op {content_type: null, a: 1})
    assert equal [$r.wire $r.req.content_type] ['{"a":1}' application/json]
    let r = (build $op {content_type: "application/vnd.api+json; charset=utf-8", a: 1})
    assert equal $r.wire '{"a":1}' "a +json type with parameters is JSON"
}

@test
def "build-request builds a multipart envelope without reading files under dry-run" [] {
    let op = {
        method: post, path: "/u", content_type: multipart/form-data
        body: {kind: multipart, fields: [{name: file, var: file}, {name: note, var: note}], files: [file]}
        accept: [application/json], ok: [], auth: bearer
    }
    let args = ($ARGS | merge {file: "/does/not/exist", note: hi} | to nuon)
    let envelope = (rt $"build-request ($op | to nuon) ($args) null | get wire | decode utf-8")
    assert ($envelope | str contains 'name="file"; filename="exist"')
    assert ($envelope | str contains "name=\"note\"\r\n\r\nhi\r\n")
    let r = (build $op {file: "/does/not/exist", note: hi})
    assert ($r.req.content_type | str starts-with "multipart/form-data; boundary=----nu-")
    assert equal $r.req.body {file: "/does/not/exist", note: hi}
    let verbatim = (build ($op | update body {kind: multipart, accepts: scalar}) {body: "pre-encoded"})
    assert equal [$verbatim.wire $verbatim.req.content_type] ["pre-encoded" multipart/form-data] "a non-record body is sent as is"
}

@test
def "the client default headers sit under the request own" [] {
    let client = ($CLIENT | update default_headers {X-Test: v, Accept: "*/*", Cookie: "pref=1"})
    let op = {method: get, path: "/d", accept: [application/json], ok: [], auth: cookie-sid}
    let r = (build $op {token: t} --client $client)
    assert equal $r.req.headers {X-Test: v, Accept: application/json, Cookie: "pref=1; sid=t"}
}

@test
def "an AND-form requirement sends every scheme" [] {
    let op = {
        method: get, path: "/and", accept: [application/json], ok: []
        auth_all: [{scheme: x-api-key, var: token_a, env: RT_A_TOKEN}, {scheme: "query-api key", var: token_b, env: RT_B_TOKEN}]
    }
    with-env {RT_B_TOKEN: B} {
        let r = (build $op {token_a: A, token_b: null})
        assert equal $r.req.headers {X-Api-Key: A, Accept: application/json}
        assert equal $r.req.url "https://api.test/v1/and?api%20key=B" "a scheme token falls back to its own env var"
        assert equal $r.req.auth {scheme: "x-api-key+query-api key", location: "header+query"}
    }
}

@test
def "the Unix socket is recorded only for a socket client" [] {
    let op = {method: get, path: "/s", accept: [application/json], ok: [], auth: bearer}
    assert ("unix_socket" not-in (build $op).req)
    let client = ($CLIENT | insert unix_socket /run/s.sock)
    assert equal (build $op --client $client).req.unix_socket /run/s.sock
    assert equal (build $op {unix_socket: ""} --client $client).req.unix_socket "" "an empty --unix-socket means TCP"
}

@test
def "http-request returns the request under dry-run" [] {
    let op = {method: delete, path: "/x/{id}", path_params: [{name: id, var: id}], content_type: application/json, accept: [application/json], ok: [204], auth: bearer}
    let r = (rt $"http-request ($op | to nuon) ($ARGS | merge {id: 5, token: t, max_time: 1sec} | to nuon)")
    assert equal $r {
        dry_run: true, method: delete, url: "https://api.test/v1/x/5", query: {}
        headers: {Authorization: "Bearer t", Accept: application/json}, body: null, content_type: application/json
        timeout: 1000000000, auth: {scheme: bearer, location: header}
    }
}
