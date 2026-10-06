#!/bin/sh
set -eu
task_project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_test_dir=$(mktemp -d)
trap 'rm -rf "$task_test_dir"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/reviewNfcGo/VisitScheduling.swift" \
    "$task_project_dir/Tests/SchedulingTests.swift" \
    -o "$task_test_dir/scheduling-tests"
"$task_test_dir/scheduling-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/reviewNfcGo/PortalLink.swift" \
    "$task_project_dir/Tests/PortalLinkTests.swift" \
    -o "$task_test_dir/portal-tests"
"$task_test_dir/portal-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/reviewNfcGo/VisitRecord.swift" \
    "$task_project_dir/Tests/SalesTests.swift" \
    -o "$task_test_dir/sales-tests"
"$task_test_dir/sales-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/reviewNfcGo/AlertHistory.swift" \
    "$task_project_dir/Tests/AlertHistoryTests.swift" \
    -o "$task_test_dir/history-tests"
"$task_test_dir/history-tests"
