#!/usr/bin/env nu
# Regenerate golden reference files for tests.
# Auto-discovers all specs in tests/inputs/ and applies the full variant matrix.
# Run from project root.
#
# Usage:
#   nu tests/regenerate.nu                    # regenerate all
#   nu tests/regenerate.nu dumbo              # cases matching "dumbo"
#   nu tests/regenerate.nu graphql/           # all graphql cases
#   nu tests/regenerate.nu no-introspection   # a specific variant across all specs

use lib.nu

def main [filter?: string] {
    let all_cases = lib cases $filter

    if ($all_cases | is-empty) {
        print "No matching cases."
        return
    }

    # Show filter and discovered specs
    if $filter != null {
        print $"Filter: \"($filter)\""
    }

    let specs = $all_cases | get spec | uniq
    let variants_per_spec = ($all_cases | length) / ($specs | length)
    print $"Specs:  ($specs | length) specs × ($variants_per_spec) variants = ($all_cases | length) golden files"
    for s in $specs {
        print $"  - ($s)"
    }
    print ""

    # Ensure all output directories exist before parallel generation
    $all_cases | each {|case| $case.golden | path dirname } | uniq | each {|dir| mkdir $dir }

    print "Generating..."
    let results = $all_cases | par-each {|case|
        let tmp = mktemp --directory
        let out = $tmp | path join "out.nu"
        let result = try {
            do $case.gen $case.spec $out $case.base_url
            let content = open $out --raw | lib normalize
            let is_new = not ($case.golden | path exists)
            let changed = if $is_new {
                true
            } else {
                (open $case.golden --raw) != $content
            }
            $content | save --force $case.golden
            if $is_new {
                { label: $case.label, status: "new", msg: "" }
            } else if $changed {
                { label: $case.label, status: "upd", msg: "" }
            } else {
                { label: $case.label, status: "ok", msg: "" }
            }
        } catch {|err|
            { label: $case.label, status: "err", msg: $err.msg }
        }
        rm --recursive $tmp
        $result
    } | sort-by label

    for r in $results {
        match $r.status {
            "new" => { print $"  NEW  ($r.label)" }
            "upd" => { print $"  UPD  ($r.label)" }
            "ok"  => { print $"  ok   ($r.label)" }
            _     => { print $"  ERR  ($r.label): ($r.msg)" }
        }
    }

    let new_count = $results | where status == "new" | length
    let upd_count = $results | where status == "upd" | length
    let ok_count = $results | where status == "ok" | length
    let err_count = $results | where status == "err" | length
    print $"\nDone. ($new_count) new, ($upd_count) updated, ($ok_count) unchanged, ($err_count) errors."
}
