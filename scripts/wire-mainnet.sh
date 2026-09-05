#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOYMENT_ENV=mainnet "$SCRIPT_DIR/wire.sh"
