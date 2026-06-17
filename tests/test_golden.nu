use std/assert
use std/testing *
use lib.nu

# Run a single variant across all discovered specs in parallel.
# Returns a list of {spec, status, msg} records.
def run-variant [name: string] {
    let variant = lib variants | where {|v| $v.name == $name } | first
    let specs = lib discover

    $specs | par-each {|spec|
        let golden = lib golden-path $spec.format $spec.stem $name
        let label = $"($spec.format)/($spec.stem)"

        if not ($golden | path exists) {
            return { spec: $label, status: "miss", msg: $"golden file not found: ($golden)" }
        }

        let tmp = mktemp --directory
        let out = $tmp | path join "out.nu"
        let result = try {
            do $variant.gen $spec.path $out

            # Parse-load check. Golden string-diff doesn't exercise the
            # parser, so codegen changes that emit invalid Nushell syntax
            # (e.g. `... (N more fields)` inside `record<>`, or a `$var`
            # reference to a never-defined identifier) sail past it. A
            # subprocess `use` catches the entire class of bugs that round-9
            # filed two regressions for.
            let parse = (^nu --no-config-file -c $"use \"($out)\"" | complete)
            if $parse.exit_code != 0 {
                let fail_dir = $"tests/failures/($spec.format)/($spec.stem)"
                mkdir $fail_dir
                let fail_path = $"($fail_dir)/($name).nu"
                cp $out $fail_path
                rm --recursive $tmp
                let err = ($parse.stderr | lines | take 10 | str join "\n  ")
                return {
                    spec: $label
                    status: "fail"
                    msg: $"parse error in generated client \(($fail_path)\):\n  ($err)"
                }
            }

            let actual = open $out --raw | lib normalize
            let expected = open $golden --raw
            if $actual == $expected {
                rm --recursive $tmp
                { spec: $label, status: "pass", msg: "" }
            } else {
                # Save actual output for inspection
                let fail_dir = $"tests/failures/($spec.format)/($spec.stem)"
                mkdir $fail_dir
                let fail_path = $"($fail_dir)/($name).nu"
                $actual | save --force $fail_path
                # Compute diff (diff exits 1 when files differ, use complete to capture)
                let diff = (^diff --unified $golden $fail_path | complete | get stdout)
                    | lines
                    | skip 2          # drop --- / +++ header
                    | take 40         # cap length
                    | str join "\n"
                rm --recursive $tmp
                {
                    spec: $label
                    status: "fail"
                    msg: $"golden: ($golden)\n  actual: ($fail_path)\n  diff:\n($diff)"
                }
            }
        } catch {|err|
            rm --recursive $tmp
            { spec: $label, status: "err", msg: $err.msg }
        }
        $result
    }
}

def assert-all-pass []: list -> nothing {
    let failures = $in | where status != "pass"
    if not ($failures | is-empty) {
        let msgs = $failures | each {|f|
            if ($f.msg | is-empty) { $"($f.spec): ($f.status)" } else { $"($f.spec): ($f.status) - ($f.msg)" }
        } | str join "\n  "
        assert false $"golden test failures:\n  ($msgs)"
    }
}

@test
def "baseline" [] { run-variant "baseline" | assert-all-pass }

@test
def "no-introspection" [] { run-variant "no-introspection" | assert-all-pass }

@test
def "no-descriptions" [] { run-variant "no-descriptions" | assert-all-pass }

@test
def "no-intro-no-desc" [] { run-variant "no-intro-no-desc" | assert-all-pass }

@test
def "name-override" [] { run-variant "name-override" | assert-all-pass }

@test
def "token-env-var" [] { run-variant "token-env-var" | assert-all-pass }

@test
def "default-timeout" [] { run-variant "default-timeout" | assert-all-pass }

@test
def "default-headers" [] { run-variant "default-headers" | assert-all-pass }

@test
def "default-base-url" [] { run-variant "default-base-url" | assert-all-pass }

@test
def "body-threshold" [] { run-variant "body-threshold" | assert-all-pass }

@test
def "exclude-deprecated" [] { run-variant "exclude-deprecated" | assert-all-pass }
