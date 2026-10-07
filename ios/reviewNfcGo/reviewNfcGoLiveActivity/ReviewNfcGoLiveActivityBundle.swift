import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ReviewNfcGoLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 17.0, *) { PendingMapWidget() }
        UpcomingVisitsWidget()
        EarningsSummaryWidget()
        if #available(iOS 18.0, *) { ReviewNfcGoMirroredLiveActivity() }
        if #unavailable(iOS 18.0) { ReviewNfcGoLiveActivity() }
    }
}

struct ReviewNfcGoLiveActivity: Widget {
    var body: some WidgetConfiguration { configuration }
    fileprivate var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: ReminderActivityAttributes.self) { context in
            Group {
                if #available(iOS 18.0, *) { AdaptiveVisitActivity(context: context) }
                else { VisitActivityCard(context: context) }
            }
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

private struct VisitActivityCard: View {
    let context: ActivityViewContext<ReminderActivityAttributes>
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            Label(context.attributes.placeName, systemImage: "building.2.fill").font(.headline).lineLimit(compact ? 2 : 1)
            Text("Próxima visita").font(.caption).foregroundStyle(.secondary)
            Text(timerInterval: min(Date(), context.state.visitDate)...context.state.visitDate, countsDown: true)
                .font(compact ? .headline.monospacedDigit() : .title2.bold().monospacedDigit())
            if !compact { Text(context.attributes.address).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }.padding(compact ? 4 : 16).privacySensitive()
    }
}
@available(iOS 18.0, *)
private struct AdaptiveVisitActivity: View {
    let context: ActivityViewContext<ReminderActivityAttributes>
    @Environment(\.activityFamily) private var family
    var body: some View { VisitActivityCard(context: context, compact: family == .small) }
}

@available(iOS 18.0, *)
private struct ReviewNfcGoMirroredLiveActivity: Widget {
    var body: some WidgetConfiguration { ReviewNfcGoLiveActivity().configuration.supplementalActivityFamilies([.small, .medium]) }
}
