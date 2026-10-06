#if WIDGET_EXTENSION || DEBUG
import SwiftUI
import WidgetKit
import MapKit
import AppIntents
import UIKit

struct DashboardEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var mapLight: UIImage? = nil
    var mapDark: UIImage? = nil
    var mapPlaces: [WidgetPlace] = []
    var showsAll: Bool = false
}

struct DashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry { DashboardEntry(date: Date(), snapshot: WidgetSamples.snapshot) }
    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        completion(DashboardEntry(date: Date(), snapshot: context.isPreview ? WidgetSamples.snapshot : WidgetSharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        let entry = DashboardEntry(date: Date(), snapshot: WidgetSharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }
}

@available(iOS 17.0, *)
enum MapCoverage: String, AppEnum {
    case dense, all
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Enfoque del mapa"
    static var caseDisplayRepresentations: [MapCoverage: DisplayRepresentation] = [
        .dense: "Zona con más visitas", .all: "Todos los sitios pendientes"]
}
@available(iOS 17.0, *)
struct MapWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Mapa de visitas"
    static var description = IntentDescription("Elige entre la zona con más visitas pendientes y todos los sitios guardados para volver.")
    @Parameter(title: "Mostrar", default: .dense) var coverage: MapCoverage
}
@available(iOS 17.0, *)
struct PendingMapProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry { DashboardEntry(date: Date(), snapshot: WidgetSamples.snapshot) }
    func snapshot(for configuration: MapWidgetIntent, in context: Context) async -> DashboardEntry {
        await WidgetMapRenderer.entry(snapshot: context.isPreview ? WidgetSamples.snapshot : WidgetSharedStore.load(),
            all: configuration.coverage == .all, size: context.displaySize)
    }
    func timeline(for configuration: MapWidgetIntent, in context: Context) async -> Timeline<DashboardEntry> {
        let entry = await snapshot(for: configuration, in: context)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
    }
}

@available(iOS 17.0, *)
struct PendingMapWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ReviewNfcGoPendingMap", intent: MapWidgetIntent.self, provider: PendingMapProvider()) { entry in
            PendingMapWidgetView(entry: entry).dashboardBackground()
        }
        .configurationDisplayName("Mapa de visitas")
        .description("Todos los sitios pendientes o la zona donde más visitas has guardado.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
struct UpcomingVisitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReviewNfcGoUpcomingVisits", provider: DashboardProvider()) { entry in
            UpcomingVisitsWidgetView(entry: entry).dashboardBackground()
        }.configurationDisplayName("Próximas visitas").description("Negocios, día y hora a los que tienes que volver.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct EarningsSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReviewNfcGoEarnings", provider: DashboardProvider()) { entry in
            EarningsSummaryWidgetView(entry: entry).dashboardBackground()
        }.configurationDisplayName("Ganancias").description("Tus ganancias totales y las últimas operaciones.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension View {
    @ViewBuilder func dashboardBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        } else { self.padding(12).background(Color(uiColor: .systemBackground)) }
    }
}

struct PendingMapWidgetView: View {
    let entry: DashboardEntry
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = scheme == .dark ? entry.mapDark : entry.mapLight {
                GeometryReader { geometry in
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            } else {
                WidgetEmptyView(icon: "map.fill", title: !entry.mapPlaces.isEmpty ? "Mapa no disponible" : (entry.snapshot.isSignedIn ? "Sin visitas pendientes" : "Abre reviewNfcGo"),
                    subtitle: !entry.mapPlaces.isEmpty ? "Toca para abrir la ficha del negocio" : (entry.snapshot.isSignedIn ? "Guarda un sitio para volver más tarde" : "Inicia sesión para ver tus sitios"))
            }
            if !entry.mapPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label(entry.showsAll ? "Todos los sitios" : "Zona con más visitas", systemImage: "map.fill").font(.caption.bold())
                    Text("\(entry.mapPlaces.count) de \(entry.snapshot.validMapPlaces.count) sitios pendientes").font(.caption2)
                }.padding(9).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(10)
            }
        }
        .widgetURL(entry.mapPlaces.first.map { PortalLink.url(recordID: $0.id) } ?? WidgetSection.visits.url)
    }
}

struct UpcomingVisitsWidgetView: View {
    let entry: DashboardEntry
    @Environment(\.widgetFamily) private var widgetFamily
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Próximas visitas", systemImage: "calendar.badge.clock").font(.headline).foregroundStyle(.blue)
            if entry.snapshot.nextVisits.isEmpty {
                WidgetEmptyView(icon: "calendar", title: entry.snapshot.isSignedIn ? "Sin visitas programadas" : "Abre reviewNfcGo",
                    subtitle: "Tus recordatorios aparecerán aquí")
            } else {
                ForEach(Array(entry.snapshot.nextVisits.prefix(family == .systemLarge ? 5 : 2))) { place in
                    Link(destination: PortalLink.url(recordID: place.id)) {
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                if family == .systemLarge { Text(place.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer(minLength: 4)
                            if let date = place.visitDate {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(date, format: .dateTime.day().month(.abbreviated)).font(.caption.bold())
                                    Text(date, style: .time).font(.caption.monospacedDigit())
                                    if date < entry.date { Text("Pendiente").font(.caption2).foregroundStyle(.orange) }
                                }
                            }
                        }.foregroundStyle(.primary)
                    }
                    if place.id != entry.snapshot.nextVisits.prefix(family == .systemLarge ? 5 : 2).last?.id { Divider() }
                }
                Spacer(minLength: 0)
                Text("\(entry.snapshot.nextVisits.count) visitas · Toca un negocio para abrir su ficha").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }.widgetURL(WidgetSection.visits.url)
    }
}

struct EarningsSummaryWidgetView: View {
    let entry: DashboardEntry
    @Environment(\.widgetFamily) private var widgetFamily
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Ganancias", systemImage: "eurosign.circle.fill").font(.headline).foregroundStyle(.green)
            Text(entry.snapshot.totalEarnings, format: .currency(code: "EUR"))
                .font(family == .systemSmall ? .title.bold() : .title2.bold()).minimumScaleFactor(0.6).lineLimit(1)
            Text("\(entry.snapshot.totalCards) tarjetas vendidas").font(.caption).foregroundStyle(.secondary)
            if family != .systemSmall {
                if entry.snapshot.operations.isEmpty {
                    Text(entry.snapshot.isSignedIn ? "Todavía no hay operaciones" : "Abre la app e inicia sesión").font(.caption).foregroundStyle(.secondary)
                } else {
                    Divider()
                    ForEach(Array(entry.snapshot.operations.prefix(family == .systemLarge ? 5 : 1))) { place in
                        Link(destination: PortalLink.url(recordID: place.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).font(.caption.weight(.semibold)).lineLimit(1)
                                    Text("\(place.cardsSold) tarjetas · \(place.createdAt.formatted(.dateTime.day().month(.abbreviated)))").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Text(place.earnings, format: .currency(code: "EUR")).font(.caption.bold()).foregroundStyle(.green)
                            }.foregroundStyle(.primary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }.widgetURL(WidgetSection.earnings.url)
    }
}

struct WidgetEmptyView: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.title2).foregroundStyle(.blue)
            Text(title).font(.subheadline.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(10)
    }
}

// Rendering a genuine MapKit snapshot is supported by WidgetKit; interactive MKMapViews are not.
enum WidgetMapRenderer {
    static func entry(snapshot: WidgetSnapshot, all: Bool, size: CGSize) async -> DashboardEntry {
        let places = all ? snapshot.validMapPlaces : snapshot.densePlaces
        var entry = DashboardEntry(date: Date(), snapshot: snapshot, mapPlaces: places, showsAll: all)
        guard !places.isEmpty else { return entry }
        entry.mapLight = await render(places: places, size: size, style: .light)
        entry.mapDark = await render(places: places, size: size, style: .dark)
        return entry
    }
    static func region(for places: [WidgetPlace]) -> MKCoordinateRegion {
        guard let anchor = places.first else { return MKCoordinateRegion() }
        let lats = places.map(\.latitude)
        let lons = places.map { place -> Double in
            var delta = place.longitude - anchor.longitude
            if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
            return anchor.longitude + delta
        }
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        var lon = (minLon + maxLon) / 2
        if lon > 180 { lon -= 360 }; if lon < -180 { lon += 360 }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: max(0.018, (maxLat - minLat) * 1.8), longitudeDelta: max(0.024, (maxLon - minLon) * 1.6)))
    }
    static func render(places: [WidgetPlace], size: CGSize, style: UIUserInterfaceStyle) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        var visibleRegion = region(for: places)
        if size.height < 250 {
            // Reserve space above the pins for the floating title on medium widgets.
            visibleRegion.center.latitude = min(85, visibleRegion.center.latitude + visibleRegion.span.latitudeDelta * 0.12)
            visibleRegion.span.latitudeDelta *= 1.17
        }
        options.region = visibleRegion
        options.size = CGSize(width: max(1, size.width), height: max(1, size.height))
        options.scale = 2
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)
        let snapshotter = MKMapSnapshotter(options: options)
        let timeout = Task {
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            snapshotter.cancel()
        }
        defer { timeout.cancel() }
        guard let snapshot = try? await snapshotter.start() else { return nil }
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)
            for place in places {
                let point = snapshot.point(for: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { continue }
                let rect = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
                context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
                context.cgContext.fillEllipse(in: rect)
                context.cgContext.setStrokeColor(UIColor.white.cgColor)
                context.cgContext.setLineWidth(2.5)
                context.cgContext.strokeEllipse(in: rect)
            }
        }
    }
}

enum WidgetSamples {
    static var snapshot: WidgetSnapshot {
        let now = Date()
        func item(_ name: String, _ lat: Double, _ lon: Double, _ hours: Double, _ earnings: Double, _ cards: Int) -> WidgetPlace {
            WidgetPlace(id: UUID(), name: name, address: "Badajoz", latitude: lat, longitude: lon,
                visitDate: now.addingTimeInterval(hours * 3600), createdAt: now.addingTimeInterval(-hours * 3600), cardsSold: cards, earnings: earnings)
        }
        let visits = [item("No Ni Ná Gastrobar", 38.8782, -6.9721, 4, 0, 0),
            item("Café de la Plaza", 38.8794, -6.9708, 24, 0, 0), item("Panadería del Centro", 38.8775, -6.9699, 28, 0, 0), item("Visita en Madrid", 40.4168, -3.7038, 48, 0, 0)]
        let sales = [item("Tienda de Ana", 38.878, -6.97, 1, 60, 3), item("Restaurante Mayor", 38.878, -6.97, 20, 50, 2)]
        return WidgetSnapshot(isSignedIn: true, updatedAt: now, pending: visits, operations: sales, totalEarnings: 110, totalCards: 5)
    }
}

#if DEBUG
struct WidgetVerificationView: View {
    var body: some View {
        VStack { ProgressView(); Text("Comprobando widgets…") }
            .task { await WidgetScreenshotVerification.run() }
    }
}
@MainActor
enum WidgetScreenshotVerification {
    static func run() async {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var checks: [String] = []
        do {
            for _ in 0..<40 {
                if WidgetSharedStore.load().isSignedIn { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            let stored = WidgetSharedStore.load()
            guard stored.isSignedIn && stored.totalEarnings == 100 && stored.totalCards == 2 else {
                throw NSError(domain: "WidgetGroup", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se comparten los datos reales mediante App Group"])
            }
            checks.append("Datos reales de app publicados y leídos del App Group")
            guard WidgetSharedStore.publish(.empty), !WidgetSharedStore.load().isSignedIn,
                  WidgetSharedStore.load().operations.isEmpty else { throw NSError(domain: "WidgetLogout", code: 2) }
            WidgetSharedStore.publish(stored)
            checks.append("Cerrar sesión elimina los datos del widget")
            let dense = await WidgetMapRenderer.entry(snapshot: WidgetSamples.snapshot, all: false, size: CGSize(width: 360, height: 170))
            let all = await WidgetMapRenderer.entry(snapshot: WidgetSamples.snapshot, all: true, size: CGSize(width: 360, height: 370))
            guard dense.mapLight != nil, dense.mapDark != nil, all.mapLight != nil else { throw NSError(domain: "WidgetMap", code: 3) }
            checks.append("Mapas MapKit de zona densa y todos los sitios, claros y oscuros")
            try save(PendingMapWidgetView(entry: dense), name: "widget-map-dense-light", size: CGSize(width: 360, height: 170), scheme: .light, folder: folder)
            let allMedium = await WidgetMapRenderer.entry(snapshot: WidgetSamples.snapshot, all: true, size: CGSize(width: 360, height: 170))
            try save(PendingMapWidgetView(entry: allMedium), name: "widget-map-all-medium-light", size: CGSize(width: 360, height: 170), scheme: .light, folder: folder)
            try save(PendingMapWidgetView(entry: all), name: "widget-map-all-dark", size: CGSize(width: 360, height: 370), scheme: .dark, folder: folder)
            let entry = DashboardEntry(date: Date(), snapshot: WidgetSamples.snapshot)
            try save(UpcomingVisitsWidgetView(entry: entry, familyOverride: .systemMedium), name: "widget-visits-medium-light", size: CGSize(width: 360, height: 170), scheme: .light, folder: folder)
            try save(UpcomingVisitsWidgetView(entry: entry, familyOverride: .systemLarge), name: "widget-visits-large-dark", size: CGSize(width: 360, height: 370), scheme: .dark, folder: folder)
            try save(EarningsSummaryWidgetView(entry: entry, familyOverride: .systemMedium), name: "widget-earnings-medium-light", size: CGSize(width: 360, height: 170), scheme: .light, folder: folder)
            try save(EarningsSummaryWidgetView(entry: entry, familyOverride: .systemLarge), name: "widget-earnings-large-dark", size: CGSize(width: 360, height: 370), scheme: .dark, folder: folder)
            checks.append("Vistas de los tres widgets renderizadas en claro y oscuro")
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: .prettyPrinted).write(to: folder.appendingPathComponent("widgets-verification.json"))
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": String(describing: error)], options: .prettyPrinted).write(to: folder.appendingPathComponent("widgets-verification.json"))
        }
    }
    private static func save<V: View>(_ view: V, name: String, size: CGSize, scheme: ColorScheme, folder: URL) throws {
        let padded = name.contains("widget-map") ? 0.0 : 14.0
        let renderer = ImageRenderer(content: view.padding(padded).frame(width: size.width, height: size.height)
            .background(scheme == .dark ? Color.black : Color.white).environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let image = renderer.uiImage, let png = image.pngData() else { throw NSError(domain: "WidgetImage", code: 4) }
        try png.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
#endif
#endif
