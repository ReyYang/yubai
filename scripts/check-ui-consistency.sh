#!/usr/bin/env bash
# Enforced source and gallery contracts; no Xcode or third-party modules required.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
python3 scripts/ui_consistency.py "$@"
