import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ReviewNfcGoLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        ReviewNfcGoLiveActivity()
    }
}

struct ReviewNfcGoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "building.2.fill")
                    Text(context.attributes.placeName).font(.headline).lineLimit(1)
                    Spacer()
                }
                Text("Próxima visita").font(.caption).foregroundStyle(.secondary)
                Text(timerInterval: min(Date(), context.state.visitDate)...context.state.visitDate, countsDown: true)
                    .font(.title2.bold().monospacedDigit())
                Text(context.attributes.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(UUID(uuidString: context.attributes.recordID).map { PortalLink.url(recordID: $0) })
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "building.2.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: min(Date(), context.state.visitDate)...context.state.visitDate, countsDown: true)
                        .monospacedDigit().font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.placeName).font(.headline).lineLimit(1)
                        Text(context.attributes.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "building.2.fill")
            } compactTrailing: {
                Text(timerInterval: min(Date(), context.state.visitDate)...context.state.visitDate, countsDown: true)
                    .monospacedDigit().frame(width: 54)
            } minimal: {
                Image(systemName: "timer")
            }
            .widgetURL(UUID(uuidString: context.attributes.recordID).map { PortalLink.url(recordID: $0) })
        }
    }
}
