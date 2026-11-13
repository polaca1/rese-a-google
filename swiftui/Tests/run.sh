#!/bin/sh
set -eu
task_project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_test_dir=$(mktemp -d)
trap 'rm -rf "$task_test_dir"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitRecord.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/NearbyBusinesses.swift" \
    "$task_project_dir/Tests/NearbyBusinessTests.swift" \
    -o "$task_test_dir/nearby-business-tests"
"$task_test_dir/nearby-business-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitScheduling.swift" \
    "$task_project_dir/Tests/SchedulingTests.swift" \
    -o "$task_test_dir/scheduling-tests"
"$task_test_dir/scheduling-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/PortalLink.swift" \
    "$task_project_dir/Tests/PortalLinkTests.swift" \
    -o "$task_test_dir/portal-tests"
"$task_test_dir/portal-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitRecord.swift" \
    "$task_project_dir/Tests/SalesTests.swift" \
    -o "$task_test_dir/sales-tests"
"$task_test_dir/sales-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/AlertHistory.swift" \
    "$task_project_dir/Tests/AlertHistoryTests.swift" \
    -o "$task_test_dir/history-tests"
"$task_test_dir/history-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/MapFlightPlan.swift" \
    "$task_project_dir/Tests/MapFlightTests.swift" \
    -o "$task_test_dir/map-flight-tests"
"$task_test_dir/map-flight-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitRecord.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/WidgetData.swift" \
    "$task_project_dir/Tests/WidgetDataTests.swift" \
    -o "$task_test_dir/widget-tests"
"$task_test_dir/widget-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitRecord.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/WidgetData.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/WidgetSharedStore.swift" \
    "$task_project_dir/Tests/WidgetSharedStoreTests.swift" \
    -o "$task_test_dir/widget-shared-store-tests"
"$task_test_dir/widget-shared-store-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitRecord.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/MoneyLedger.swift" \
    "$task_project_dir/Tests/MoneyTests.swift" \
    -o "$task_test_dir/money-tests"
"$task_test_dir/money-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitRecord.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/MoneyLedger.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/ProductMetadataService.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/SearchSuggestions.swift" \
    "$task_project_dir/Tests/ProductAndSearchTests.swift" \
    -o "$task_test_dir/product-search-tests"
"$task_test_dir/product-search-tests"

xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitRecord.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/MoneyLedger.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/BusinessTools.swift" \
    "$task_project_dir/Tests/BusinessToolsTests.swift" \
    -o "$task_test_dir/business-tools-tests"
"$task_test_dir/business-tools-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/PlacesTransport.swift" \
    "$task_project_dir/Tests/PlacesTransportTests.swift" \
    -o "$task_test_dir/places-transport-tests"
"$task_test_dir/places-transport-tests"

xcrun swiftc -parse-as-library -swift-version 5 \
    -module-cache-path "$task_test_dir/ModuleCache" \
    "$task_project_dir/Sources/ReviewNfcGoViews/VisitRecord.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/MoneyLedger.swift" \
    "$task_project_dir/Sources/ReviewNfcGoViews/BusinessTools.swift" \
    "$task_project_dir/Tests/EasySalesTests.swift" \
    -o "$task_test_dir/easy-sales-tests"
"$task_test_dir/easy-sales-tests"
