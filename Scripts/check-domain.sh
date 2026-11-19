#!/bin/sh
set -eu

# Compile the actual wire/recovery sources and run a small executable check on
# machines that lack Xcode's SwiftData macros and XCTest framework.
recovery_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
recovery_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/recovery-domain.XXXXXX")
trap 'rm -rf "$recovery_check_dir"' EXIT

xcrun swiftc -module-cache-path "$recovery_check_dir/module-cache" \
    "$recovery_root/Sources/RecoveryCore/WireProtocol.swift" \
    "$recovery_root/Sources/RecoveryCore/Recovery.swift" \
    "$recovery_root/Validation/DomainCheck.swift" \
    -o "$recovery_check_dir/domain-check"
"$recovery_check_dir/domain-check"
