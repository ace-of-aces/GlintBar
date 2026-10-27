#!/usr/bin/env bash
# Formats the Swift sources with swift format (rules in .swift-format).
# Pass --check to only lint instead, failing on anything CI would reject.
set -euo pipefail
cd "$(dirname "$0")/.."

PATHS=(Sources Tests Package.swift)

if [[ "${1:-}" == "--check" ]]; then
    swift format lint --recursive --parallel --strict "${PATHS[@]}"
    echo "Formatting is clean"
else
    swift format format --in-place --recursive --parallel "${PATHS[@]}"
    echo "Formatted ${PATHS[*]}"
fi
