import SwiftUI

// MARK: - Root / Auth

struct RootView: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-blur-auth") {
                AuthView()
            } else if ProcessInfo.processInfo.arguments.contains("--verification-suite-sale") {
                NavigationStack { QuickSaleView() }
            } else if ProcessInfo.processInfo.arguments.contains("--verification-suite-clients") {
                NavigationStack { ClientFollowUpView() }
            } else if ProcessInfo.processInfo.arguments.contains("--verification-suite-goals") {
                NavigationStack { WeeklyGoalsView() }
            } else if ProcessInfo.processInfo.arguments.contains("--verification-suite-profit") {
                NavigationStack { SaleProfitView() }
            } else if ProcessInfo.processInfo.arguments.contains("--verification-suite-history") {
                NavigationStack { CloudHistoryView() }
            } else if ProcessInfo.processInfo.arguments.contains("--verification-v5-route") {
                NavigationStack { WorkspaceRouteView() }
            } else if ProcessInfo.processInfo.arguments.contains("--verification-v5-backup") {
                NavigationStack { BackupView() }
            } else if ProcessInfo.processInfo.arguments.contains("--verification-v5-profit") {
                NavigationStack { ProfitView() }
            } else if ProcessInfo.processInfo.arguments.contains("--verification-widgets") {
                WidgetVerificationView()
            } else if ProcessInfo.processInfo.arguments.contains("--verification-dates") || ProcessInfo.processInfo.arguments.contains("--verification-reminder-save") {
                QuickReminderView(place: PlaceResult(id: "date-verification", name: "Negocio de prueba", address: "Calle Mayor, Madrid", latitude: 40.4168, longitude: -3.7038))
            } else {
                authenticatedContent
            }
            #else
            authenticatedContent
            #endif
        }
    }
    @ViewBuilder private var authenticatedContent: some View {
            if auth.currentUser == nil {
                AuthView()
            } else {
                MainTabView()
            }
    }
}

// MARK: - Main tabs

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var portalRouter: PortalRouter
    @State private var selectedTab = 0
    @State private var businessPath: [UUID] = []
    @State private var showUnavailableBusiness = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $businessPath) {
                HistoryView()
                    .navigationDestination(for: UUID.self) { id in
                        RecordDetailView(recordID: id)
                    }
            }
                .tabItem { Label("Sitios", systemImage: "clock.fill") }.tag(1)
            NavigationStack { MoneyView() }
                .tabItem { Label("Dinero", systemImage: "eurosign.circle.fill") }.tag(2)
            NavigationStack { RemindersView() }
                .tabItem { Label("Avisos", systemImage: "bell.fill") }.tag(3)
            NavigationStack {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--verification-major-today") { TodayWorkspaceView() }
                else { HomeView() }
                #else
                HomeView()
                #endif
            }
                .tabItem { Label("Inicio", systemImage: "location.fill") }.tag(0)
            NavigationStack { ProfileView() }
                .tabItem { Label("Perfil", systemImage: "person.crop.circle.fill") }.tag(4)
        }
        .onAppear {
            openPendingBusiness()
            openPendingWidgetSection()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-profile") { selectedTab = 4 }
            if ProcessInfo.processInfo.arguments.contains("--verification-history") { selectedTab = 3 }
            if ProcessInfo.processInfo.arguments.contains("--verification-money") || ProcessInfo.processInfo.arguments.contains("--verification-inventory") || ProcessInfo.processInfo.arguments.contains("--verification-expense") { selectedTab = 2 }
            #endif
        }
        .onChange(of: portalRouter.pendingRecordID) { _ in openPendingBusiness() }
        .onChange(of: portalRouter.pendingWidgetSection) { _ in openPendingWidgetSection() }
        .onChange(of: store.hasLoadedRecords) { _ in openPendingBusiness(); openPendingWidgetSection() }
        .onChange(of: store.loadedUserEmail) { _ in openPendingBusiness(); openPendingWidgetSection() }
        .alert("Negocio no disponible", isPresented: $showUnavailableBusiness) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text("Este negocio se ha eliminado o pertenece a otra cuenta. Inicia sesión con la cuenta que lo guardó.")
        }
    }

    private func openPendingWidgetSection() {
        guard store.hasLoadedRecords, store.loadedUserEmail == auth.currentUser?.email,
              let section = portalRouter.pendingWidgetSection else { return }
        selectedTab = section == .visits ? 3 : 2
        portalRouter.consumeWidgetSection()
    }

    private func openPendingBusiness() {
        guard store.hasLoadedRecords, store.loadedUserEmail == auth.currentUser?.email,
              let id = portalRouter.pendingRecordID else { return }
        portalRouter.consume()
        guard store.records.contains(where: { $0.id == id }) else {
            showUnavailableBusiness = true
            return
        }
        selectedTab = 1
        // Replace a previous detail/editor with the requested business portal.
        businessPath = [id]
    }
}

// Compatibility alias: the old project expects ContentView to exist.
struct ContentView: View {
    var body: some View { RootView() }
}
