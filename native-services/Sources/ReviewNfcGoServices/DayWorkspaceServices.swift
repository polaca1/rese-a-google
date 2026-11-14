// SPDX-License-Identifier: MIT
// Existing workspace calculations and document services, with Day-owned screens.
import Foundation
import UIKit
import CoreLocation

@MainActor extension DayServices {
    func workspaceSnapshot() -> [String: Any] {
        let money = store.money, records = store.records, calendar = Calendar.current
        let weekly = WeeklyProgress(records: records, money: money, date: workspaceDay)
        let today = TodaySummary(records: records, money: money)
        let month = calendar.dateInterval(of: .month, for: workspaceDay)!
        let previous = calendar.dateInterval(of: .month, for: calendar.date(byAdding: .month, value: -1, to: workspaceDay)!)!
        func income(_ range: DateInterval) -> Int64 { money.transactions.filter { $0.date >= range.start && $0.date < range.end && $0.kind.isIncome }.reduce(0) { $0 + $1.cents } }
        func expense(_ range: DateInterval) -> Int64 { -money.transactions.filter { $0.date >= range.start && $0.date < range.end && ($0.kind == .expense || $0.kind == .refund) }.reduce(0) { $0 + $1.cents } }
        let origin = finder.userLocation.map { PlaceResult(id: "route-origin", name: "Mi ubicación", address: "", latitude: $0.latitude, longitude: $0.longitude) }
        let stops = DailyRoute.stops(records: records, day: routeDay, origin: routeUseLocation ? origin : nil)
        let routes: [[String: Any]] = stops.map { ["id": $0.id.uuidString, "name": $0.record.place.name, "address": $0.record.place.address,
            "time": $0.record.reminderDate?.formatted(date: .omitted, time: .shortened) ?? "Sin hora fijada",
            "distance": $0.distanceMeters.map { Measurement(value: $0, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)) } ?? ""] }
        let legs: [[String: Any]] = stride(from: 0, to: stops.count, by: 4).compactMap { start in
            let end = min(start + 4, stops.count)
            guard let url = DailyRoute.mapURL(stops: Array(stops[start..<end]), walking: routeWalking) else { return nil }
            return ["id": String(start), "start": start + 1, "end": end, "url": url.absoluteString]
        }
        let quotes: [[String: Any]] = (money.quotations ?? []).sorted { $0.createdAt > $1.createdAt }.map { quote in
            var object = encoded(quote) as? [String: Any] ?? [:]
            object["number"] = quote.number; object["totalCents"] = quote.totalCents
            object["discountCents"] = quote.discountCents; object["expiryLabel"] = quote.expiresAt.formatted(date: .abbreviated, time: .omitted)
            object["canConvert"] = quote.saleID == nil && quote.status != .declined && quote.expiresAt >= Date() && quote.totalCents > 0
            return object
        }
        let performance: [[String: Any]] = money.productPerformance.map { ["id": $0.id.uuidString, "name": $0.product.displayName, "quantity": $0.quantity, "revenue": $0.revenue, "profit": $0.profit.map { $0 as Any } ?? NSNull()] }
        let sales: [[String: Any]] = money.activeQuickSales.sorted { $0.date > $1.date }.map { sale in
            var object = encoded(sale) as? [String: Any] ?? [:]
            object["name"] = records.first { $0.id == sale.businessID }?.place.name ?? "Negocio eliminado"
            object["dateLabel"] = sale.date.formatted(date: .abbreviated, time: .shortened)
            object["incomeCents"] = sale.incomeCents; object["profitCents"] = sale.profitCents.map { $0 as Any } ?? NSNull()
            return object
        }
        return ["day": String(localDate(workspaceDay).prefix(10)), "routeDay": String(localDate(routeDay).prefix(10)), "routeWalking": routeWalking,
            "goals": encoded(money.weeklyGoals ?? WeeklyGoals()),
            "weekly": ["cards": weekly.cards, "visits": weekly.visits, "profit": weekly.profit, "unknownCosts": weekly.unknownCosts,
                "days": weekly.days.map { ["id": localDate($0.date), "day": $0.date.formatted(.dateTime.weekday(.abbreviated)), "income": $0.income, "profit": $0.profit] }],
            "today": ["salesCents": today.salesCents, "visits": today.visits.map { $0.id.uuidString }, "followUps": today.followUps.map { $0.id.uuidString }],
            "monthly": [["id": "previous", "month": previous.start.formatted(.dateTime.month(.abbreviated).year()), "income": income(previous), "expense": expense(previous)],
                        ["id": "current", "month": month.start.formatted(.dateTime.month(.abbreviated).year()), "income": income(month), "expense": expense(month)]],
            "routes": routes, "routeLegs": legs, "quotes": quotes, "performance": performance, "sales": sales]
    }

    func workspaceCommand(_ action: String, values: [String: String], rows: [[String: String]]) throws -> Bool {
        func value(_ key: String) -> String { values[key] ?? "" }
        func id(_ key: String) throws -> UUID { guard let result = UUID(uuidString: value(key)) else { throw BackupError.invalid }; return result }
        func integer(_ key: String) throws -> Int { guard let result = Int(value(key)) else { throw MoneyError.invalidAmount }; return result }
        func viewDate() throws -> Date {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let result = formatter.date(from: value("date")) else { throw BackupError.invalid }; return result
        }
        switch action {
        case "workspaceDate": workspaceDay = try viewDate()
        case "routeDate": routeDay = try viewDate(); routeWalking = value("walking") != "false"
        case "routeLocate": routeUseLocation = true; finder.start(); finder.focusOnUserLocation()
        case "goals":
            guard let price = SaleAmountFormatting.parse(value("profit")), let cents = MoneyLedger.cents(price) else { throw MoneyError.invalidAmount }
            try store.setWeeklyGoals(WeeklyGoals(cards: try integer("cards"), visits: try integer("visits"), profitCents: cents))
        case "quote":
            guard let record = store.records.first(where: { $0.id.uuidString == value("record") }) else { throw BackupError.invalid }
            let items = try rows.map { row -> QuoteLine in
                guard let productID = row["product"].flatMap(UUID.init(uuidString:)), let product = store.money.products.first(where: { $0.id == productID }),
                      let quantity = row["quantity"].flatMap(Int.init), let amount = row["price"].flatMap(SaleAmountFormatting.parse), let cents = MoneyLedger.cents(amount) else { throw MoneyError.invalidProduct }
                return QuoteLine(productID: productID, title: product.displayName, quantity: quantity, unitPriceCents: cents)
            }
            let validity = try integer("validity"); guard (1...365).contains(validity), let expiry = Calendar.current.date(byAdding: .day, value: validity, to: Date()) else { throw MoneyError.invalidAmount }
            let quote = BusinessQuote(businessID: record.id, businessName: record.place.name, expiresAt: expiry, items: items, discountPercent: try integer("discount"), notes: value("notes"))
            try store.saveQuote(quote)
        case "quoteStatus":
            let quoteID = try id("quote")
            guard var quote = store.money.quotations?.first(where: { $0.id == quoteID }), let status = QuoteStatus(rawValue: value("status")), status == .sent || status == .declined else { throw MoneyError.invalidProduct }
            quote.status = status; try store.saveQuote(quote)
        case "convertQuote": try store.convertQuote(try id("quote"), payment: value("payment"))
        case "externalURL":
            guard ReviewLinkAddress.validTarget(value("url")), let url = URL(string: value("url")) else { throw BackupError.invalid }
            UIApplication.shared.open(url)
        case "quotePDF":
            let quoteID = try id("quote")
            guard let quote = store.money.quotations?.first(where: { $0.id == quoteID }), let owner = store.loadedUserEmail else { throw BackupError.invalid }
            let url = try QuotePDF.create(quote, owner: owner)
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { throw BackupError.invalid }
            controller.popoverPresentationController?.sourceView = root.view; controller.popoverPresentationController?.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
            root.present(controller, animated: true)
        default: return false
        }
        return true
    }
}
