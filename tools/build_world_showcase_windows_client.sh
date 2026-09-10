#!/usr/bin/env bash
# Compatibility alias for the repository-owned exact-revision Windows build entrypoint.
# Dependencies: tools/windows_build.sh; accepts the same PR/ref selector arguments.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$ROOT/tools/windows_build.sh" "$@"
