# warn.nu — Colored warning helpers for http-gen.
# Each category has its own color so warnings are visually distinct.

# Missing or problematic configuration requiring user action.
export def config [msg: string] { print -e $"(ansi yellow_bold)($msg)(ansi reset)" }

# Name deduplication occurred (informational, auto-resolved).
export def dedup [msg: string] { print -e $"(ansi cyan)($msg)(ansi reset)" }

# Falling back to a default because the expected value is absent.
export def fallback [msg: string] { print -e $"(ansi yellow)($msg)(ansi reset)" }

# Data quality / schema issues (truncated types, unresolved refs).
export def data [msg: string] { print -e $"(ansi purple)($msg)(ansi reset)" }
