#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC="$(xcrun --find swiftc)"
PLUGIN="$(dirname "$SWIFTC")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$PLUGIN" ]]; then
  swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN"
else
  swift test --disable-xctest
fi
