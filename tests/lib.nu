# Shared test infrastructure for http-gen golden-file tests.
# Provides spec discovery, variant matrix, normalization, and path helpers.

use ../mod.nu

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

    $specs | each {|spec|
        $all_variants | each {|variant|
            let label = $"($spec.format)/($spec.stem)/($variant.name)"
            {
                label: $label
                spec: $spec.path
                gen: $variant.gen
                golden: (golden-path $spec.format $spec.stem $variant.name)
            }
        }
    } | flatten | where {|case|
        ($filter == null) or ($case.label =~ $filter)
    }
}

# Variant test matrix.
# Each variant: {name: string, gen: closure(spec, out)}
export def variants [] {
    [
        {
            name: "baseline"
            gen: {|spec, out|
                mod $spec -o $out
            }
        }
        {
            name: "no-introspection"
            gen: {|spec, out|
                mod $spec -o $out --no-introspection
            }
        }
        {
            name: "no-descriptions"
            gen: {|spec, out|
                mod $spec -o $out --no-descriptions
            }
        }
        {
            name: "no-intro-no-desc"
            gen: {|spec, out|
                mod $spec -o $out --no-introspection --no-descriptions
            }
        }
        {
            name: "name-override"
            gen: {|spec, out|
                mod $spec -o $out --name "test-client"
            }
        }
        {
            name: "token-env-var"
            gen: {|spec, out|
                mod $spec -o $out --token-env-var "TEST_TOKEN"
            }
        }
        {
            name: "default-timeout"
            gen: {|spec, out|
                mod $spec -o $out --default-timeout "5min"
            }
        }
        {
            name: "default-headers"
            gen: {|spec, out|
                mod $spec -o $out --default-headers {"X-Test": "value"}
            }
        }
        {
            name: "default-base-url"
            gen: {|spec, out|
                mod $spec -o $out --default-base-url "https://custom.example.com"
            }
        }
        {
            name: "body-threshold"
            gen: {|spec, out|
                mod $spec -o $out --body-threshold 3
            }
        }
        {
            name: "exclude-deprecated"
            gen: {|spec, out|
                mod $spec -o $out --exclude-deprecated
            }
        }
    ]
}
