# Unit tests for server URL resolution in `src/spec/spec.nu`: a relative
# server URL is relative to where the document was fetched from
# (`anchor-servers`), and a document read from a file falls back to
# `http://localhost` (`base-url`, `all-urls`).

use std/assert
use std/testing *

use ../src/spec/spec.nu

const ORIGIN = "https://api.test:8443"

@test
def "relative root servers are anchored on the origin" [] {
    let doc = {openapi: "3.0.0", servers: [{url: "/v1"}, {url: "https://abs.test"}, {url: "//cdn.test"}], paths: {}}
    let anchored = (spec anchor-servers $doc $ORIGIN)
    assert equal $anchored.servers [{url: "https://api.test:8443/v1"}, {url: "https://abs.test"}, {url: "//cdn.test"}] "absolute and scheme-relative URLs are left alone"
    assert equal (spec base-url $anchored) "https://api.test:8443/v1"
}

@test
def "a document without servers is served from the origin" [] {
    let doc = {openapi: "3.0.0", paths: {}}
    assert equal (spec base-url (spec anchor-servers $doc $ORIGIN)) $ORIGIN
    assert equal (spec base-url $doc) "http://localhost" "a file keeps the localhost fallback"
}

@test
def "path-level and operation-level servers are anchored too" [] {
    let doc = {
        openapi: "3.0.0"
        servers: [{url: "https://root.test"}]
        paths: {
            "/a/{id}": {
                servers: [{url: "/path"}]
                get: {servers: [{url: "/op"}], responses: {}}
                post: {responses: {}}
            }
            "/b": {}
        }
    }
    let anchored = (spec anchor-servers $doc $ORIGIN)
    let item = ($anchored.paths | get "/a/{id}")
    assert equal $item.servers [{url: "https://api.test:8443/path"}]
    assert equal $item.get.servers [{url: "https://api.test:8443/op"}]
    assert equal $item.post {responses: {}}
    assert equal ($anchored.paths | get "/b") {}
    assert equal (spec all-urls $anchored) ["https://root.test" "https://api.test:8443/path" "https://api.test:8443/op"]
}
