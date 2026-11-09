# Unit tests for the Swagger 2.0 to OpenAPI 3 conversion (`src/spec/swagger2.nu`).
# The goldens prove a converted spec generates the client it always did; these
# pin the converted document itself, the contract `spec.nu` reads.

use std/assert
use std/testing *

use ../src/spec/swagger2.nu

const V2 = "tests/inputs/openapi-v2"

def convert [stem: string]: nothing -> record {
    swagger2 to-openapi3 (open (glob $"($V2)/($stem).*" | first))
}

def op [doc: record, path: string, method: string]: nothing -> record {
    $doc.paths | get $path | get $method
}

def param [o: record, name: string]: nothing -> record {
    $o.parameters | where name == $name | first
}

@test
def "servers come from host, basePath and schemes" [] {
    let doc = (convert collection-format-edge-cases)
    assert equal $doc.servers [{url: "https://api.example.com/v2"}]
    assert equal $doc.openapi "3.0.3"
}

@test
def "a parameterized host is the single server" [] {
    let doc = (convert parameterized-host-edge-cases)
    assert equal $doc.servers [{url: "https://{searchServiceName}.search.windows.net"}]
}

@test
def "collectionFormat becomes style and explode" [] {
    let o = (op (convert collection-format-edge-cases) "/search" get)
    let style = {|n| param $o $n | select style explode }
    assert equal (do $style csvTags) {style: form, explode: false}
    assert equal (do $style ssvTags) {style: spaceDelimited, explode: false}
    assert equal (do $style tsvTags) {style: tabDelimited, explode: false}
    assert equal (do $style pipesTags) {style: pipeDelimited, explode: false}
    assert equal (do $style multiTags) {style: form, explode: true}
    assert equal (param $o csvTags).schema {type: array, items: {type: string}}
}

@test
def "formData params become a multipart requestBody" [] {
    let o = (op (convert form-data-edge-cases) "/analysis" post)
    let schema = $o.requestBody.content."multipart/form-data".schema
    assert equal ($schema.properties | columns) [picture storeResult tags]
    assert equal $schema.required [picture]
    assert equal $schema.properties.tags.collectionFormat csv
}

@test
def "formData is urlencoded when nothing asks for multipart" [] {
    let o = (op (convert form-data-edge-cases) "/marketstat" post)
    assert equal ($o.requestBody.content | columns) [application/x-www-form-urlencoded]
}

@test
def "path-level body params are inherited unless the operation has its own" [] {
    let doc = (convert path-level-body-edge-cases)
    let props = {|path, m| (op $doc $path $m).requestBody.content."application/json".schema.properties | columns }
    assert equal (do $props "/things" post) [name]
    assert equal (do $props "/things" put) [name color]
    assert equal (do $props "/things" patch) [size]
    let form = (op $doc "/forms" post).requestBody.content."application/x-www-form-urlencoded".schema
    assert equal ($form.properties | columns) [title note]
}

@test
def "basic auth becomes the http basic scheme" [] {
    let schemes = (convert auth-edge-cases).components.securitySchemes
    assert equal $schemes.basicAuth {type: http, scheme: basic}
    assert equal $schemes.apiKeyHeader.in header
}

@test
def "responses serve their schema as every produced type" [] {
    let doc = (convert header-override-edge-cases)
    let content = (op $doc "/widgets" get).responses."200".content
    assert equal ($content | columns) [application/json application/yaml]
    assert equal $content."application/yaml".schema {type: object}
}

@test
def "a response ref is inlined and given content" [] {
    let o = (op (convert form-data-edge-cases) "/analysis" post)
    assert equal ($o.responses."200".content."application/json".schema.properties | columns) [id faces]
}

@test
def "a response without a schema still lists the produced types" [] {
    let o = (op (convert form-data-edge-cases) "/marketstat" post)
    assert equal $o.responses."200".content {application/json: {}}
}

# Swagger 2's `produces` covers undocumented responses too; OpenAPI 3 says so
# with a `default` response. An op documenting only a 302 thus keeps its types.
@test
def "an operation without a default response gets one with the produced types" [] {
    let o = (op (convert header-override-edge-cases) "/widgets" get)
    assert equal $o.responses.default {description: "", content: {application/json: {}, application/yaml: {}}}
    let marketstat = (op (convert form-data-edge-cases) "/marketstat" post)
    assert equal $marketstat.responses.default.description error
}

# Specs point into operations (`#/paths/…/responses/200/schema/items/…`), so
# the conversion moves nothing: the Swagger 2 keys stay next to the new ones.
@test
def "converted responses and params keep their Swagger 2 keys" [] {
    let doc = (convert header-override-edge-cases)
    assert equal (op $doc "/widgets" get).responses."200".schema {type: object}
    let o = (op (convert collection-format-edge-cases) "/search" get)
    assert equal (param $o csvTags).collectionFormat csv
    assert equal (param $o csvTags).type array
}
