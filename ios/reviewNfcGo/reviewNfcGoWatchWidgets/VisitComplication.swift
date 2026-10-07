import SwiftUI
import WidgetKit

struct VisitEntry: TimelineEntry { var date: Date; var visit: WatchBusiness? }
struct VisitProvider: TimelineProvider {
    func placeholder(in context: Context) -> VisitEntry { VisitEntry(date: Date(), visit: nil) }
    func getSnapshot(in context: Context, completion: @escaping (VisitEntry) -> Void) { completion(VisitEntry(date: Date(), visit: WatchSharedStore.load().nextVisit(at: Date()))) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VisitEntry>) -> Void) {
        let value = WatchSharedStore.load(), now = Date()
        var entries = [VisitEntry(date: now, visit: value.nextVisit(at: now))]
        for business in value.businesses.filter({ !$0.completed && $0.arrivedAt == nil && $0.visitDate.map { $0 > now } == true }).sorted(by: { $0.visitDate! < $1.visitDate! }).prefix(20) {
            let date = business.visitDate!.addingTimeInterval(1)
            entries.append(VisitEntry(date: date, visit: value.nextVisit(at: date)))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
    }
}
struct VisitComplicationView: View {
    var entry: VisitEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if let visit = entry.visit, let date = visit.visitDate {
                switch family {
                case .accessoryCircular:
                    ZStack { AccessoryWidgetBackground(); VStack(spacing: 0) { Image(systemName: "building.2.fill"); Text(timerInterval: min(entry.date, date)...date, countsDown: true).font(.caption2).monospacedDigit().minimumScaleFactor(0.5) } }.accessibilityLabel("Próxima visita: " + visit.name)
                case .accessoryInline:
                    Label { Text(date, format: .dateTime.hour().minute()) + Text(" · " + visit.name) } icon: { Image(systemName: "building.2") }
                default:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(visit.name).font(.headline).lineLimit(1)
                        HStack { Image(systemName: "timer"); Text(timerInterval: min(entry.date, date)...date, countsDown: true).monospacedDigit(); Spacer(); Text(date, format: .dateTime.hour().minute()).font(.caption) }
                    }
                }
            } else { Label("Sin visitas", systemImage: "calendar").font(.caption) }
        }.privacySensitive()
            .containerBackground(.clear, for: .widget)
            .widgetURL(entry.visit.flatMap { URL(string: "reviewnfcgo-watch://business/" + $0.id.uuidString) })
    }
}
@main struct ReviewNfcGoWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReviewNfcGoVisit", provider: VisitProvider()) { entry in VisitComplicationView(entry: entry) }
            .configurationDisplayName("Próxima visita")
            .description("Tu próximo negocio y el tiempo que queda para volver.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
