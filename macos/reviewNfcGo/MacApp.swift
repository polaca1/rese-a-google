import SwiftUI
import AppKit

@main struct ReviewNfcGoMacApp: App {
    @StateObject private var cloud = CloudBackupController()
    @StateObject private var store: MacStore
    @StateObject private var navigation = MacNavigation.shared
    @StateObject private var notifications = MacNotifications.shared
    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--verify-desktop"), args.indices.contains(index + 1) {
            _store = StateObject(wrappedValue: MacStore(fileURL: URL(fileURLWithPath: args[index + 1]).appendingPathComponent("Workspace.json")))
            return
        }
        #endif
        _store = StateObject(wrappedValue: MacStore())
    }
    var body: some Scene {
        WindowGroup("reviewNfcGo") {
            MacRootView().environmentObject(store).environmentObject(navigation).environmentObject(notifications).environmentObject(cloud)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1220, height: 800)
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Nuevo negocio") { navigation.sheet = .business(nil) }.keyboardShortcut("n").disabled(store.owner == nil)
                Button("Registrar gasto") { navigation.sheet = .expense }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(store.owner == nil)
                Divider()
                Button("Importar copia de seguridad…") { MacFiles.chooseImport(store: store, navigation: navigation) }.keyboardShortcut("o")
                Button("Exportar copia…") { MacFiles.export(store: store) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(store.owner == nil)
                Button("Exportar operaciones CSV…") { MacFiles.export(store: store, csv: true) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(store.owner == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(store.undoTitle.map { "Deshacer \($0.lowercased())" } ?? "Deshacer") { store.run { try store.undo() } }
                    .keyboardShortcut("z").disabled(store.undoTitle == nil)
            }
            CommandMenu("Ir a") {
                ForEach(Array(MacSection.allCases.enumerated()), id: \.element.id) { index, section in
                    Button(section.rawValue) { navigation.section = section }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
        }
        Settings {
            MacSettingsView().environmentObject(store).environmentObject(navigation).environmentObject(notifications).environmentObject(cloud)
        }
    }
}

struct MacRootView: View {
    @ObservedObject private var auth = RemoteAuthClient.shared
    @EnvironmentObject private var cloud: CloudBackupController
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @EnvironmentObject private var notifications: MacNotifications
    private var showsWorkspace: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verify-desktop") { return store.owner != nil }
        #endif
        return store.owner != nil && auth.signedIn
    }
    var body: some View {
        Group {
            if !showsWorkspace { MacWelcomeView() }
            else {
        NavigationSplitView {
            List(selection: $navigation.section) {
                Section("reviewNfcGo") {
                    ForEach(MacSection.allCases) { section in Label(section.rawValue, systemImage: section.symbol).tag(section) }
                }
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 170, ideal: 195, max: 240)
        } detail: {
            Group {
                if !showsWorkspace { MacWelcomeView() }
                else {
                    switch navigation.section ?? .dashboard {
                    case .workspace: NavigationStack { BusinessHubView() }
                    case .dashboard: NavigationStack { MacDashboardView() }
                    case .businesses: NavigationStack { MacBusinessesView() }
                    case .visits: MacVisitsView()
                    case .money: MacMoneyView()
                    case .analytics: MacAnalyticsView()
                    case .inventory: MacInventoryView()
                    case .map: MacMapView()
                    }
                }
            }
            .navigationTitle(navigation.section?.rawValue ?? "Resumen")
            .toolbar {
                ToolbarItemGroup {
                    Button { MacFiles.chooseImport(store: store, navigation: navigation) } label: { Label("Importar copia", systemImage: "square.and.arrow.down") }
                        .help("Importar copia del iPhone (⌘O)")
                    Button { MacFiles.export(store: store) } label: { Label("Exportar copia", systemImage: "square.and.arrow.up") }
                        .disabled(store.owner == nil).help("Exportar copia (⇧⌘S)")
                    Menu {
                        Button("Nuevo negocio", systemImage: "building.2") { navigation.sheet = .business(nil) }
                        Button("Registrar gasto", systemImage: "eurosign.circle") { navigation.sheet = .expense }
                    } label: { Label("Añadir", systemImage: "plus") }.disabled(store.owner == nil).help("Añadir negocio o gasto")
                }
            }
        }
            }
        }
        .onAppear { configureCloud() }
        .onChange(of: auth.session?.user.email) { _, _ in configureCloud() }
        .onChange(of: scenePhase) { _, _ in cloud.requestSync(immediate: true) }
        .sheet(item: $navigation.sheet) { sheet in
            switch sheet {
            case .business(let id): MacBusinessEditor(record: id.flatMap { id in store.records.first { $0.id == id } })
            case .expense: MacExpenseEditor()
            case .transaction(let id): if let item = store.money.transactions.first(where: { $0.id == id }) { MacTransactionDetail(item: item) }
            case .stock(let id): if let product = store.money.products.first(where: { $0.id == id }) { MacStockEditor(product: product) }
            }
        }
        .alert("No se ha podido completar", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("Cerrar", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("Importar copia", isPresented: Binding(get: { navigation.importCandidate != nil }, set: { if !$0 { navigation.importCandidate = nil } }), titleVisibility: .visible) {
            Button("Importar y sustituir datos") {
                if let value = navigation.importCandidate { store.run { try store.importBackup(value) } }
                navigation.importCandidate = nil; navigation.selectedBusiness = nil
            }
            Button("Cancelar", role: .cancel) { navigation.importCandidate = nil }
        } message: {
            if let value = navigation.importCandidate {
                Text("Cuenta: \(value.owner)\n\(value.records.count) negocios y \(value.money.transactions.count) operaciones. Sustituirá los datos actuales del Mac; se conservará una copia anterior para recuperarlos.")
            }
        }
        .onAppear { notifications.didOpen = { id in navigation.openBusiness(id, store: store) } }
        .onReceive(store.$backup) { value in notifications.replace(value?.records ?? []) }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--verify-desktop"), args.indices.contains(index + 1) {
                await MacVerification.run(store: store, navigation: navigation, output: URL(fileURLWithPath: args[index + 1]))
            }
            #endif
        }
    }
    private func configureCloud() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verify-desktop") { return }
        #endif
        cloud.connect(owner: nil, transport: auth, read: { guard let value = store.backup else { throw BackupError.invalid }; return value }, apply: { _ in })
        guard let email = auth.session?.user.email else { store.run { try store.deactivateAccount() }; return }
        do { try store.activateAccount(email) } catch { store.errorMessage = error.localizedDescription; return }
        store.didChange = { [weak cloud] in cloud?.localChanged() }
        cloud.connect(owner: email, transport: auth, read: {
            guard let value = store.backup else { throw BackupError.invalid }; return value
        }, apply: { value in try store.importBackup(value) })
    }

}

struct MacWelcomeView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    var body: some View {
        ScrollView { VStack(spacing: 20) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 92, height: 92).accessibilityHidden(true)
            Text("Inicia sesión en reviewNfcGo").font(.largeTitle.bold())
            Text("Organiza tus visitas, tarjetas NFC e ingresos desde una sola ventana.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Form { MacAccountSection() }.formStyle(.grouped).frame(maxWidth: 480).fixedSize(horizontal: false, vertical: true)
            Text("Inicia sesión con la misma cuenta del iPhone para recuperar tus datos automáticamente.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)

        }.padding(36).frame(maxWidth: .infinity) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @EnvironmentObject private var notifications: MacNotifications
    var body: some View {
        Form {
            MacAccountSection()
            Section("Datos en la nube") { CloudBackupStatusView() }
            Section("Cuenta y datos") {
                LabeledContent("Cuenta", value: store.owner ?? "Sin configurar")
                Text("Tus datos se sincronizan entre iPhone y Mac. También puedes exportar una copia adicional. Importar sustituye los datos de la cuenta.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Importar copia…") { MacFiles.chooseImport(store: store, navigation: navigation) }
                Button("Exportar copia…") { MacFiles.export(store: store) }.disabled(store.owner == nil)
                Button("Recuperar copia anterior…") {
                    store.run { navigation.importCandidate = try MacStore.readBackup(Data(contentsOf: store.recoveryURL)) }
                }.disabled(!FileManager.default.fileExists(atPath: store.recoveryURL.path))
            }
            Section("Avisos en este Mac") {
                Toggle("Recordatorios de visitas", isOn: Binding(get: { notifications.enabled }, set: { value in Task { await notifications.setEnabled(value, records: store.records) } }))
                if let message = notifications.message { Text(message).foregroundStyle(.secondary) }
            }
            Section {
                LabeledContent("Versión", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4")
                LabeledContent("Desarrollado por", value: "Pablo Cancho Flores")
            }
        }.formStyle(.grouped).padding().frame(width: 560, height: 680)
    }
}

struct MacAccountSection: View {
    @EnvironmentObject private var store: MacStore
    @ObservedObject private var auth = RemoteAuthClient.shared
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var registering = false
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        Section("Cuenta") {
            if let session = auth.session, auth.signedIn {
                LabeledContent("Sesión", value: session.user.email)
                Button("Cerrar sesión") { auth.logout() }.disabled(busy)
            } else {
                Toggle("Crear cuenta", isOn: $registering).disabled(busy)
                if registering { TextField("Nombre", text: $name) }
                TextField("Correo", text: $email)
                SecureField("Contraseña", text: $password)
                Button(registering ? "Crear cuenta" : "Iniciar sesión") {
                    busy = true; message = nil
                    Task {
                        defer { busy = false; password = "" }
                        do {
                            let user = try await auth.authenticate(email: email, password: password, name: registering ? name : nil)
                            try store.activateAccount(user.email)

                        } catch { message = error.localizedDescription }
                    }
                }.disabled(busy || email.isEmpty || password.isEmpty)
            }
            Button {
                let expectedEmail = auth.signedIn ? auth.session?.user.email : nil
                busy = true; message = nil
                Task {
                    defer { busy = false }
                    do {
                        let user = try await auth.authenticateWithGoogle(expectedEmail: expectedEmail)
                        try store.activateAccount(user.email)

                    } catch is CancellationError { }
                    catch { message = error.localizedDescription }
                }
            } label: { GoogleSignInLabel() }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(busy)
            if busy { ProgressView().controlSize(.small) }
            if let message { Text(message).foregroundStyle(.secondary) }
            Text("Tus negocios, visitas, inventario y dinero se sincronizan con tu cuenta. Comprueba el estado del guardado antes de cerrar la app.")
                .font(.callout).foregroundStyle(.secondary)
        }.onAppear { email = store.owner ?? "" }
    }
}

func euro(_ cents: Int64) -> String { (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "es_ES"))) }
func reviewAvailable(_ place: PlaceResult) -> Bool { !place.id.hasPrefix("local-") }

struct MacCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
}
struct MacEmptyView: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(detail)) }
}
