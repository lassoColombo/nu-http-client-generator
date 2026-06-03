# log.nu — Severity-based log helpers for http-gen.
# Colors represent gravity: green = info, yellow = warning, red = error.

# Informational: something happened automatically, no action needed.
export def info [msg: string] { print -e $"(ansi green)info(ansi reset): ($msg)" }

# Warning: something degraded but generation continues.
export def warn [msg: string] { print -e $"(ansi yellow)warn(ansi reset): ($msg)" }

# Error: user action is likely required.
export def error [msg: string] { print -e $"(ansi red_bold)error(ansi reset): ($msg)" }
