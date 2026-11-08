#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec scripts/swift-local.sh run AppsCoreChecks
