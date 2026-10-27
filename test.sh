#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source scripts/swift-env.sh
swift run "${SWIFT_OPTIONS[@]}" ClimateCoreTests
