#!/usr/bin/env bash
# Chooses which checkout owns native GPS binaries during a local PR check.
# Dependencies: pure shell policy only; callers perform the selected build/reuse action.
set -euo pipefail

select_native_gps_source() {
  local scope="${1:-}" reusable="${2:-}"
  case "${scope}:${reusable}" in
    required:yes|required:no)
      printf 'pr\n'
      ;;
    skip:yes)
      printf 'reuse\n'
      ;;
    skip:no)
      printf 'main\n'
      ;;
    *)
      printf 'invalid native GPS source decision: scope=%s reusable=%s\n' "$scope" "$reusable" >&2
      return 64
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ "$#" -eq 2 ]] || { printf 'usage: %s <required|skip> <yes|no>\n' "$0" >&2; exit 64; }
  select_native_gps_source "$1" "$2"
fi
