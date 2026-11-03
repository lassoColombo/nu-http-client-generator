# names.nu — Names the emitted client claims for itself.
#
# A leaf data module: model reads these to keep spec-derived command names off
# them, render reads them to emit the module and hide its own flags from the
# `commands` introspection. Living here keeps model from knowing render's
# output through render itself.

# Every `def` the module emits besides the API commands: `main`/`commands`,
# the auth helpers, the runtime library (`src/runtime*.nu`), the per-verb
# senders, and the fixed completers. A command with one of these names is a
# `nu::parser::duplicate_command_def`. Enum completers (`<flag>-completer`,
# `<flag>-completer-<n>`) are reserved by pattern in model's `name-unusable`.
# `tests/test_reserved_names.nu` checks the runtime defs are all listed.
export const EMITTED_DEF_NAMES = [
  main commands
  build-auth merge-auth serialize-qp encode-path-segment encode-path-array encode-path-greedy build-url status-ok
  handle-response build-multipart-body
  send-get send-post send-put send-patch send-delete send-head send-options
  base-url-completer auth-scheme-completer unix-socket-completer
]

# The flags `build-signature` gives every command besides its spec params.
# Two per-client additions are not listed: the gated `--unix-socket` and the
# AND-form `--token-<scheme>` flags. The `commands` introspection hides these
# (plus nushell's own `--help` and the per-client ones) from the param list,
# and render's RESERVED_VARS keeps spec params off their variables, so a flag
# added to the signature must be added here. `tests/test_signature.nu` checks it.
export const SIGNATURE_FLAGS = [base-url token auth-scheme insecure max-time raw allow-errors full dry-run accept]
