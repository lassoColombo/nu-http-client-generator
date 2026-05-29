# Shared test infrastructure for http-gen golden-file tests.
# Provides spec discovery, variant matrix, normalization, and path helpers.

use ../mod.nu

const GQL_BASE = "https://example.com/graphql"

export def gql-base-url []: nothing -> string { $GQL_BASE }

# Normalize generated output by replacing the machine-specific source path
export def normalize []: string -> string {
    str replace --regex '# Source: .+' '# Source: <spec>'
}

# Auto-discover all spec files under tests/inputs/
export def discover []: nothing -> list<record<path: string, format: string, stem: string>> {
    glob tests/inputs/*/*
    | sort
    | each {|path|
        let format = $path | path dirname | path basename
        let stem = $path | path parse | get stem
        { path: $path, format: $format, stem: $stem }
    }
}

# Compute golden file path
export def golden-path [format: string, stem: string, variant: string]: nothing -> string {
    $"tests/expected/($format)/($stem)/($variant).nu"
}

# Build a flat list of all (spec, variant) test cases, optionally filtered.
export def cases [filter?: string] {
    let specs = discover
    let all_variants = variants
    let gql_base = $GQL_BASE

    $specs | each {|spec|
        let is_gql = $spec.format == "graphql"
        let base_url = if $is_gql { $gql_base } else { null }
        let applicable = $all_variants | where { not ($in.rest_only and $is_gql) }

        $applicable | each {|variant|
            let label = $"($spec.format)/($spec.stem)/($variant.name)"
            {
                label: $label
                spec: $spec.path
                gen: $variant.gen
                base_url: $base_url
                golden: (golden-path $spec.format $spec.stem $variant.name)
            }
        }
    } | flatten | where {|case|
        ($filter == null) or ($case.label =~ $filter)
    }
}

# Variant test matrix.
# Each variant: {name: string, rest_only: bool, gen: closure(spec, out, base_url)}
# base_url is null for REST specs, a URL string for GraphQL specs.
export def variants [] {
    [
        {
            name: "baseline"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url
                } else {
                    mod openapi $spec -o $out
                }
            }
        }
        {
            name: "no-introspection"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url --no-introspection
                } else {
                    mod openapi $spec -o $out --no-introspection
                }
            }
        }
        {
            name: "no-descriptions"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url --no-descriptions
                } else {
                    mod openapi $spec -o $out --no-descriptions
                }
            }
        }
        {
            name: "no-intro-no-desc"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url --no-introspection --no-descriptions
                } else {
                    mod openapi $spec -o $out --no-introspection --no-descriptions
                }
            }
        }
        {
            name: "name-override"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url --name "test-client"
                } else {
                    mod openapi $spec -o $out --name "test-client"
                }
            }
        }
        {
            name: "token-env-var"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url --token-env-var "TEST_TOKEN"
                } else {
                    mod openapi $spec -o $out --token-env-var "TEST_TOKEN"
                }
            }
        }
        {
            name: "default-timeout"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url --default-timeout "5min"
                } else {
                    mod openapi $spec -o $out --default-timeout "5min"
                }
            }
        }
        {
            name: "default-headers"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url --default-headers {"X-Test": "value"}
                } else {
                    mod openapi $spec -o $out --default-headers {"X-Test": "value"}
                }
            }
        }
        {
            name: "default-base-url"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url "https://custom.example.com"
                } else {
                    mod openapi $spec -o $out --default-base-url "https://custom.example.com"
                }
            }
        }
        {
            name: "body-threshold"
            rest_only: false
            gen: {|spec, out, base_url|
                if $base_url != null {
                    mod graphql $spec -o $out --default-base-url $base_url --body-threshold 3
                } else {
                    mod openapi $spec -o $out --body-threshold 3
                }
            }
        }
        {
            name: "exclude-deprecated"
            rest_only: true
            gen: {|spec, out, _base_url|
                mod openapi $spec -o $out --exclude-deprecated
            }
        }
    ]
}
