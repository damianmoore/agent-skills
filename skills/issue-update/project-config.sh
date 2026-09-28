#!/usr/bin/env bash
# Compatibility shim — the config reader moved to scripts/project-config.sh.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/project-config.sh" "$@"
