#!/usr/bin/env sh
# Portable truthy/falsy checks for settings string values (sh-safe).

# Return 0 if VALUE is a recognized false-ish token.
waybar_is_false() {
  case "${1:-}" in
    false | False | FALSE | 0 | no | No | NO | null | off | Off | OFF) return 0 ;;
    *) return 1 ;;
  esac
}

# Return 0 if VALUE is not false-ish (including empty / unknown → truthy).
waybar_is_truthy() {
  if waybar_is_false "${1:-}"; then
    return 1
  fi
  return 0
}
