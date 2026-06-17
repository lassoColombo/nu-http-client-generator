# Round-9 response: regressions A and B + surface-area inventory

Both regressions fixed and verified locally. Inventory found **no other shared
renderers** and **one structural duplication** that didn't cause either bug.
Recommendation: spot-fix is the right call; the higher-leverage improvement is
a **parse-load step in the test runner** (now landed), which catches the entire
class both regressions belong to without any refactor.

---

## Regression A — root and fix

**Root.** Not actually a "shared renderer" problem. Two functions exist:

- `build-shape-doc` (`src/render.nu`) feeds **only** `# shape: ...` comments.
- `build-record-fields` (`src/spec/spec.nu`) — used by `schema-to-nu-type` —
  feeds **only** `record<...>` type signatures.

When implementing round-8 issue #3, I added width capping to `build-shape-doc`
(correctly, for the comment context) and then **copy-pasted the same capping
into `build-record-fields`** without re-thinking the syntactic constraint of
the target. The two functions look similar; their outputs go to different
syntactic positions. The cap produced `... (N more fields)` which is invalid
inside `record<>`.

**Fix.** `build-record-fields` (`spec.nu:308`) had the cap removed. Depth
limiting (already there via `max_depth = 3`) bounds catastrophic recursion;
wide records produce long-but-valid type signatures, which is the correct
tradeoff (terminals can wrap, parsers can't fix bad syntax). `build-shape-doc`
keeps its cap — it still feeds comments only.

**Verified.** Test golden `tests/expected/openapi-v3/vinny/baseline.nu`
previously failed `use` with `expected operator`; now parses cleanly. Zero
remaining `... (N more fields)` markers in any regenerated golden.

---

## Regression B — root and fix

**Root.** A `let req_body = ...` initial line is emitted in the per-field
branch but **not** in the collapsed branch (when `body_threshold` collapses to
a single `--body: record` flag, or when there are zero body fields). The merge
line was emitted unconditionally afterwards and assumed `$req_body` already
existed. Pre-rename it read `$body` (the user's flag), which was always in
scope. Post-rename, `$req_body` is referenced where nothing has defined it.

**Fix.** Restructured `build-body-code` (`src/render.nu`) so the collapsed
branch explicitly emits `let req_body = $body` before the merge line. Now both
branches share the same merge line and both have `$req_body` defined:

```nu
# per-field branch:
  let req_body = {"field1": $field1, ...} | compact
  let req_body = if ($input | ...) { $input | merge deep ($req_body | default {}) } else { $req_body }

# collapsed branch:
  let req_body = $body
  let req_body = if ($input | ...) { $input | merge deep ($req_body | default {}) } else { $req_body }
```

The shape of the merge line is now invariant across branches. Future renames
touch one line, not two.

**Verified.** `petstore-v3/body-threshold.nu` previously failed `use` with
`variable not found`; now parses cleanly. Every regenerated golden (231 files)
parses via `nu --no-config-file -c "use <file>"`.

---

## Inventory: shared renderers (Regression A's class)

Walked every string-producing helper in `src/render.nu`, `src/build.nu`,
`src/spec/spec.nu`. For each, traced where its output lands.

| Renderer | Target | Multiple targets? |
|---|---|---|
| `build-shape-doc` | `# shape: …` comments | No |
| `build-record-fields` / `schema-to-nu-type` | `record<…>` type signatures | No |
| `normalize-description` / `build-description` | `# …` comments | No |
| `openapi-to-nu-type` / `nu-type-for` | type signatures (flags + outputs) | One syntactic class (type) |
| `to-flag-name` / `to-var-name` / `to-flag-var` / `effective-positional-var` | identifier strings | One syntactic class (ident) |
| `clean-enum-values` | enum value strings | Two consumers (completers + shape comments) but **same syntactic class** (string literals with escape rules) |
| `lookup-shape` | `# shape: …` comments | No |
| `render-param-sig` / `render-param-group` | full def-signature flag lines | One target |

**Finding.** No renderer feeds two syntactically different audiences. Regression A
came from **near-duplicated logic** in two separate functions (the
copy-pasted cap), not from a single function with two consumers. Adding a
"--as-type" switch wouldn't help — `build-record-fields` was never the same
function as `build-shape-doc`.

---

## Inventory: identifier contracts (Regression B's class)

Mapped every place where a flag name or variable name must agree across
emission sites.

| Identifier contract | Sites | Computed via | Drift risk |
|---|---|---|---|
| Universal flags (`--token` → `$token`, etc.) | signature, body-code, `do-request` call | hardcoded literals | low — names are stable |
| Path param positional vs body-code ref | signature, body-code, path-template substitution | `effective-positional-var` helper | low — one source |
| Query param flag vs body-code var (`--name` → `$qp_name`) | signature, body-code | `effective-flag-var $name "qp"` helper | low — one source |
| Header / cookie param flag vs var (`hdr_*`, `ck_*`) | signature, body-code | helpers | low — one source |
| **Body field flag vs body-code var (incl. `body-` prefix on collision)** | **3 sites**: signature (`render.nu:322-339`), body-code per-field (`render.nu:495-505`), body-code multipart (`render.nu:547-554`) | inline duplicates of `to-var-name`/`to-flag-var` + collision check | **medium** — three near-identical copies; any divergence produces "variable not found" or unbound flag |
| `req_body` LHS vs RHS in merge line | the merge line itself | string template | **was** medium, now low — single canonical merge line shared by both branches |

**Finding.** One real duplication exists (body-field collision rule across 3
sites). It did **not** cause Regression B — that was a missing initial line in
the collapsed branch, not a name-mismatch. The duplication is a known smell;
not urgent.

---

## Judgment

The two regressions are **isolated** and the inventory is **small** — exactly
the case the agent flagged as "spot-fix and stop". The two structural smells
I found (copy-pasted truncation cap, three-way body-field collision rule) are
real but neither is currently broken and a refactor for either would be larger
than the regression-fix surface itself.

The **highest-leverage improvement** turned out to be neither a refactor nor a
spot-fix: it's a **parse-load step in the test runner**. Both regressions
slipped past golden tests because string-diff doesn't exercise the parser.
That gap let bad output through to mass-load. With the new step, the test
runner now invokes `nu --no-config-file -c "use <out>.nu"` after each
generation; any non-zero exit becomes a test failure with the parser error
attached. Both regressions reproduce locally if reintroduced — they no longer
need to wait for registry-wide mass-load to surface.

---

## Files changed

- `src/spec/spec.nu` — `build-record-fields`: removed width cap (regression A).
- `src/render.nu` — `build-body-code`: collapsed branch now emits
  `let req_body = $body` initial line; merge line shared (regression B).
- `tests/test_golden.nu` — parse-load step before string-diff (verification).
- 94 golden files regenerated.

## Acceptance

| Check | Expected | Got |
|---|---|---|
| `... (N more fields)` inside type signatures (231 goldens) | 0 | **0** |
| `nu use` parse failures across all 231 goldens | 0 | **0** |
| nutest run | 29/31 (2 flaky integration: petstore 500, httpbin timeout) | 29/31 |

## What I am NOT doing

- Not refactoring the body-field collision rule into a helper. It works; doing
  it now is speculation. Would be appropriate when adding the next body-field
  feature, not earlier.
- Not splitting `build-shape-doc` / `build-record-fields` further. They're
  already separate functions and the documentation now states their targets.
  The next person to touch either should be unsurprised about which is which.
- Not adding `--shape-depth` config (suggested in round-8 issue #3). Only the
  width cap was the relevant lever for the original DocuSign case, and that's
  applied in `build-shape-doc` already; `build-record-fields` was the wrong
  place. If wide return types become a problem in their own right, the right
  fix is in `schema-to-nu-type` (depth already exists).
