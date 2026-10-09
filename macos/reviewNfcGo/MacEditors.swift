import SwiftUI

struct MacBusinessEditor: View {
    let original: VisitRecord?
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = MacPlaceSearch()
    @State private var draft: VisitRecord
    @State private var name: String
    @State private var address: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var unitAmount: String
    @State private var query = ""
    @State private var hasVisit: Bool
    @State private var visit: Date
    @State private var notice: Date
    @State private var error: String?
    @State private var owner: String?
    init(record: VisitRecord?) {
        original = record
        let value = record ?? VisitRecord(place: PlaceResult(id: "local-" + UUID().uuidString, name: "", address: "", latitude: 0, longitude: 0))
        _draft = State(initialValue: value); _name = State(initialValue: value.place.name); _address = State(initialValue: value.place.address)
        _latitude = State(initialValue: record.map { String($0.place.latitude) } ?? "")
        _longitude = State(initialValue: record.map { String($0.place.longitude) } ?? "")
        _unitAmount = State(initialValue: SaleAmountFormatting.text(for: value.earningsPerCard))
        _hasVisit = State(initialValue: value.reminderDate != nil && value.status != .completed)
        let date = value.reminderDate ?? Date().addingTimeInterval(86400)
        _visit = State(initialValue: date); _notice = State(initialValue: value.notificationDate ?? date.addingTimeInterval(-1800))
    }
    var body: some View {
        VStack(spacing: 0) {
            sheetTitle(original == nil ? "Nuevo negocio" : "Editar negocio")
            if original == nil {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Buscar negocio y ciudad", text: $query).textFieldStyle(.roundedBorder)
                    if search.isLoading { ProgressView().controlSize(.small) }
                    if let message = search.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                    if !search.results.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(search.results) { place in
                                    Button { choose(place) } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(place.name).font(.headline)
                                            Text(place.address).font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }.frame(maxHeight: 145)
                    }
                }.padding(.horizontal, 22).padding(.bottom, 12).task(id: query) { await search.search(query) }
            }
            Form {
                Section("Negocio") {
                    TextField("Nombre", text: $name)
                    TextField("Dirección", text: $address)
                    HStack { TextField("Latitud", text: $latitude); TextField("Longitud", text: $longitude) }
                    Text("Al elegir un resultado se rellenan su dirección y ubicación.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Seguimiento") {
                    Picker("Estado", selection: $draft.status) {
                        Text("Contactado").tag(VisitStatus.contacted)
                        Text("Volver").tag(VisitStatus.pending)
                        Text("Vendido").tag(VisitStatus.completed)
                    }.pickerStyle(.segmented)
                    TextField("Notas", text: $draft.notes, axis: .vertical).lineLimit(3...5)
                }
                Section(draft.hasQuickSales == true ? "Ventas anteriores de tarjetas" : "Venta de tarjetas") {
                    Stepper("Tarjetas vendidas: \(draft.cardsSold)", value: $draft.cardsSold, in: (draft.status == .completed && draft.hasQuickSales != true ? 1 : 0)...100_000)
                    TextField("Ganancia por tarjeta (€)", text: $unitAmount)
                    LabeledContent("Total", value: euro(MoneyLedger.cents(VisitRecord.totalEarnings(perCard: SaleAmountFormatting.parse(unitAmount) ?? 0, count: draft.cardsSold)) ?? 0))
                    Picker("Tarjeta / color", selection: $draft.inventoryProductID) {
                        Text("Sin asignar").tag(Optional<UUID>.none)
                        ForEach(store.money.products.filter { $0.kind == .nfcCard }) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Text("Hasta 50 € por tarjeta. La cantidad asignada se descuenta del inventario.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Próxima visita") {
                    Toggle("Volver otro día", isOn: $hasVisit).disabled(draft.status == .completed)
                    if hasVisit {
                        DatePicker("Fecha y hora de visita", selection: $visit)
                        DatePicker("Avisarme el", selection: $notice)
                    }
                }
            }.formStyle(.grouped)
            if let error { Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal, 22).padding(.bottom, 8) }
            sheetFooter { dismiss() } save: { save() }
        }.frame(width: 600, height: 700)
        .onAppear { owner = store.owner }
        .onChange(of: draft.status) { _, value in if value == .completed { draft.cardsSold = max(draft.hasQuickSales == true ? 0 : 1, draft.cardsSold); hasVisit = false } }
    }
    private func choose(_ place: PlaceResult) {
        if let existing = store.records.first(where: { $0.place.id == place.id }) {
            query = ""; dismiss(); navigation.selectedBusiness = existing.id; navigation.section = .businesses; return
        }
        draft.place = place; name = place.name; address = place.address
        latitude = String(place.latitude); longitude = String(place.longitude); query = ""
    }
    private func save() {
        do {
            guard owner == store.owner else { throw BackupError.wrongAccount }
            guard let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")), let lon = Double(longitude.replacingOccurrences(of: ",", with: ".")),
                  let amount = SaleAmountFormatting.parse(unitAmount), amount <= 50 else { throw DesktopError.invalidBusiness }
            var value = draft
            value.place = PlaceResult(id: draft.place.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), address: address, latitude: lat, longitude: lon)
            if original == nil || original!.cardsSold != value.cardsSold || unitAmount != SaleAmountFormatting.text(for: original!.earningsPerCard) {
                value.unitEarnings = amount
            }
            value.reminderDate = hasVisit ? visit : nil; value.notificationDate = hasVisit ? notice : nil
            if hasVisit && value.status == .contacted { value.status = .pending }
            try store.save(value); navigation.selectedBusiness = value.id; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct MacExpenseEditor: View {
    @EnvironmentObject private var store: MacStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var amount = ""
    @State private var quantity = 1
    @State private var choice = "expense"
    @State private var kind: ProductKind = .nfcCard
    @State private var productName = ""
    @State private var color = ""
    @State private var date = Date()
    @State private var merchant = ""
    @State private var method = "Tarjeta"
    @State private var url = ""
    @State private var notes = ""
    @State private var imageURL = ""
    @State private var error: String?
    @State private var metadataMessage: String?
    @State private var fetching = false
    @State private var fetchTask: Task<Void, Never>?
    @State private var owner: String?
    @State private var origin: InventoryAcquisition = .purchase
    var body: some View {
        VStack(spacing: 0) {
            sheetTitle("Registrar compra o entrada")
            Form {
                Section("Compra") {
                    TextField("Concepto", text: $title)
                    if choice != "expense" && origin != .purchase { LabeledContent("Coste total", value: "0,00 €") }
                    else { TextField("Coste total (€)", text: $amount) }
                    DatePicker("Fecha", selection: $date)
                    TextField("Proveedor o tienda", text: $merchant)
                    Picker("Forma de pago", selection: $method) { ForEach(["Tarjeta", "Efectivo", "Transferencia", "Otros"], id: \.self) { Text($0) } }
                }
                Section("Inventario") {
                    Picker("Producto", selection: $choice) {
                        Text("Gasto sin producto").tag("expense")
                        Text("Crear producto").tag("new")
                        ForEach(store.money.products) { Text($0.displayName).tag($0.id.uuidString) }
                    }
                    if choice != "expense" {
                        Picker("Origen", selection: $origin) { ForEach(InventoryAcquisition.allCases) { Text($0.title).tag($0) } }
                    }
                    if choice == "new" {
                        Picker("Categoría", selection: $kind) { ForEach(ProductKind.allCases) { Text($0.title).tag($0) } }
                        TextField("Nombre del producto", text: $productName)
                        if kind == .nfcCard { TextField("Color", text: $color) }
                    }
                    if choice != "expense" { Stepper("Unidades adquiridas: \(quantity)", value: $quantity, in: 1...100_000) }
                    Text(origin == .purchase || choice == "expense" ? "El coste total descuenta saldo y las unidades adquiridas aumentan las existencias." : "La entrada aumenta las existencias sin cambiar tu saldo. El origen se conserva en el historial.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Enlace de compra") {
                    TextField("https://tienda…", text: $url)
                    HStack {
                        Button("Importar datos del producto") { fetchMetadata() }.disabled(fetching || ProductMetadataService.purchaseURL(url) == nil)
                        if fetching { ProgressView().controlSize(.small) }
                    }
                    if let metadataMessage { Text(metadataMessage).font(.caption).foregroundStyle(.secondary) }
                    TextField("Notas", text: $notes, axis: .vertical).lineLimit(3...5)
                }
            }.formStyle(.grouped)
            if let error { Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal, 22).padding(.bottom, 8) }
            sheetFooter { dismiss() } save: { save() }
        }.frame(width: 580, height: 670).onAppear { owner = store.owner }.onDisappear { fetchTask?.cancel() }
    }
    private func fetchMetadata() {
        guard let address = ProductMetadataService.purchaseURL(url) else { return }
        fetching = true; metadataMessage = nil
        fetchTask = Task {
            do {
                let metadata = try await ProductMetadataService.fetch(address); try Task.checkCancellation()
                if !metadata.name.isEmpty { if title.isEmpty { title = metadata.name }; if productName.isEmpty { productName = metadata.name } }
                imageURL = metadata.imageURL
                if let price = metadata.euroPrice, amount.isEmpty {
                    amount = SaleAmountFormatting.text(for: price * Double(choice == "expense" ? 1 : quantity))
                    metadataMessage = "Datos importados. Revisa el coste total y las unidades antes de guardar."
                } else { metadataMessage = "Revisa los datos importados y añade manualmente los que falten." }
            } catch { if !Task.isCancelled { metadataMessage = error.localizedDescription } }
            fetching = false
        }
    }
    private func save() {
        do {
            guard owner == store.owner else { throw BackupError.wrongAccount }
            let noCost = choice != "expense" && origin != .purchase
            guard noCost || (SaleAmountFormatting.parse(amount) ?? 0) > 0 else { throw MoneyError.invalidAmount }
            guard url.isEmpty || ProductMetadataService.purchaseURL(url) != nil else { throw MoneyError.invalidProduct }
            var product: InventoryProduct?
            if choice == "new" { product = InventoryProduct(name: productName, kind: kind, color: kind == .nfcCard ? color : "", purchaseURL: url, imageURL: imageURL) }
            let id = product?.id ?? UUID(uuidString: choice)
            if noCost, let id {
                try store.receiveStock(title: title, quantity: quantity, productID: id, newProduct: product, origin: origin, date: date, notes: notes)
            } else {
                try store.addExpense(title: title, amount: SaleAmountFormatting.parse(amount) ?? 0, quantity: quantity, productID: id, newProduct: product,
                                     date: date, merchant: merchant, method: method, url: url, notes: notes)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct MacStockEditor: View {
    let product: InventoryProduct
    @EnvironmentObject private var store: MacStore
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var previous = 0
    @State private var reason = ""
    @State private var owner: String?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            sheetTitle("Ajustar existencias")
            Form {
                LabeledContent("Producto", value: product.displayName)
                LabeledContent("Existencias actuales", value: String(store.money.stock(product.id)))
                TextField("Nueva cantidad disponible", text: $quantity)
                TextField("Motivo", text: $reason, axis: .vertical).lineLimit(2...4)
                Text("Este ajuste registra el motivo en el historial y no cambia tu saldo.").font(.callout).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
            sheetFooter { dismiss() } save: {
                do {
                    guard owner == store.owner else { throw BackupError.wrongAccount }
                    guard let target = Int(quantity), target >= 0, previous == store.money.stock(product.id) else { throw MoneyError.invalidQuantity }
                    try store.adjustStock(product.id, quantity: target - previous, reason: reason); dismiss()
                } catch { self.error = error.localizedDescription }
            }
        }.frame(width: 480, height: 355)
        .onAppear { owner = store.owner; previous = store.money.stock(product.id); quantity = String(previous) }
    }
}

struct MacTransactionDetail: View {
    let item: MoneyTransaction
    @EnvironmentObject private var store: MacStore
    @EnvironmentObject private var navigation: MacNavigation
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            sheetTitle("Detalle de operación")
            Form {
                LabeledContent("Concepto", value: item.title)
                LabeledContent("Tipo", value: item.typeTitle)
                LabeledContent("Importe", value: euro(item.cents))
                LabeledContent("Fecha", value: item.date.formatted(date: .abbreviated, time: .shortened))
                if item.productID != nil { LabeledContent("Unidades", value: String(item.quantity)) }
                if !item.merchant.isEmpty { LabeledContent("Proveedor", value: item.merchant) }
                if !item.paymentMethod.isEmpty { LabeledContent("Pago", value: item.paymentMethod) }
                if !item.notes.isEmpty { Text(item.notes).textSelection(.enabled) }
                if let id = item.businessID, store.records.contains(where: { $0.id == id }) {
                    Button("Abrir ficha del negocio") { dismiss(); navigation.openBusiness(id, store: store) }
                }
                if let url = ProductMetadataService.purchaseURL(item.purchaseURL) { Link("Volver a comprar", destination: url) }
                if item.kind == .expense && !store.money.isReversed(item.id) { Button("Registrar devolución", role: .destructive) { confirmation = true } }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("Cerrar") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(18)
        }.frame(width: 510, height: 500)
        .confirmationDialog("¿Registrar la devolución?", isPresented: $confirmation, titleVisibility: .visible) {
            Button("Registrar devolución") {
                do { try store.reverseExpense(item.id); dismiss() } catch { self.error = error.localizedDescription }
            }
        } message: { Text("El gasto original se conserva. Se devuelve el importe y se retiran las unidades adquiridas; las unidades ya vendidas no se pueden devolver.") }
    }
}

private func sheetTitle(_ title: String) -> some View {
    HStack { Text(title).font(.title2.bold()); Spacer() }.padding(22)
}
private func sheetFooter(cancel: @escaping () -> Void, save: @escaping () -> Void) -> some View {
    VStack(spacing: 0) {
        Divider()
        HStack { Spacer(); Button("Cancelar", action: cancel).keyboardShortcut(.cancelAction); Button("Guardar", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }.padding(18)
    }
}
