#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/build/ModuleCache"
mkdir -p build
xcrun clang -O2 -Wall -Wextra -c Sources/Hardware/Hardware.c -o build/Hardware-test.o
xcrun swiftc -parse-as-library -sdk "$(xcrun --show-sdk-path)" \
    -import-objc-header Sources/Hardware/Hardware.h build/Hardware-test.o \
    Sources/PCHealthRemote/Protocol.swift Sources/PCHealthRemote/MetricsCollector.swift \
    Sources/PCHealthRemote/USBLink.swift Tests/Tests.swift -framework IOKit -o build/tests
./build/tests
xcrun clang Tests/Reference/protocol.c Tests/Reference/verify.c -o build/verify-flipper
./build/verify-flipper
