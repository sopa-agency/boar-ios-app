#!/bin/bash
# The whole engine test package in two steps: every suite but the timing ones (in parallel), then the timing ones alone,
# so the fuzz and combination suites don't slow the measuring thread (BOAR-66, Tests/BoarAnswerTests/LabTimingTests.swift).
# Usage: scripts/test.sh [extra swift test arguments, e.g. --scratch-path .build/<your-name>]
# Not for --filter: filters add up (OR), so the second step would run the filtered tests again. Use swift test directly.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test "$@" --skip LabTimingTests
swift test "$@" --filter LabTimingTests
