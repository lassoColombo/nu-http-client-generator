# Emitted only for clients with at least one AND-form operation: one security
# requirement naming several schemes, all sent together. `merge-auth` folds the
# per-scheme `build-auth` records into one: headers merged with `merge-headers`
# (runtime.nu, so cookie schemes are joined), query fragments joined with `&`,
# the distinct non-"none" locations joined with `+`. A scheme whose token is
# absent comes back as location "none" and contributes nothing.
#
# Spliced by render's `runtime-defs`: this header block holds no def and is dropped.

# Merge multiple auth records (AND-form security: every scheme must be sent).
def merge-auth [parts: list]: nothing -> record {
  let active = ($parts | where {|p| $p.location != "none" })
  let headers = ($parts | reduce --fold {} {|p, acc| merge-headers $acc $p.headers })
  let query = ($parts | each {|p| $p.query } | where {|q| $q | is-not-empty } | str join "&")
  let locs = ($active | each {|p| $p.location } | uniq)
  let location = if ($locs | is-empty) { "none" } else { $locs | str join "+" }
  {scheme: ($parts | each {|p| $p.scheme } | str join "+"), headers: $headers, query: $query, location: $location}
}
