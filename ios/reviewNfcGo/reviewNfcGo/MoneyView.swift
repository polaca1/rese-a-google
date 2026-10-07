import SwiftUI

struct MoneyView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var balanceFontSize = 42.0
    @State private var showExpense = false
    @State private var filter = "Todos"
    @State private var detail: MoneyTransaction?
    #if DEBUG
    @State private var verificationInventory = false
    #endif
    private var history: [MoneyTransaction] {
        store.money.history.filter { filter == "Todos" || (filter == "Ingresos" ? $0.kind.isIncome : !$0.kind.isIncome) }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SALDO DISPONIBLE").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(Double(store.money.balanceCents) / 100, format: .currency(code: "EUR"))
                        .font(.system(size: balanceFontSize, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundStyle(store.money.balanceCents < 0 ? Color.red : Color.primary)
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 24))) {
                        summary("Ingresos", cents: store.money.incomeCents, color: .green)
                        summary("Gastos", cents: store.money.expenseCents, color: .orange)
                    }
                    Text("Ingresos de negocios menos gastos. El saldo puede ser negativo.").font(.footnote).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            Section {
                Button { showExpense = true } label: { Label("Registrar compra o gasto", systemImage: "plus.circle.fill") }
                NavigationLink { ProfitView() } label: { Label("Beneficio por negocio", systemImage: "chart.line.uptrend.xyaxis") }
                if let title = store.undoTitle { Button { store.undoLastChange() } label: { Label("Deshacer: " + title, systemImage: "arrow.uturn.backward") } }
                NavigationLink { InventoryView() } label: {
                    HStack {
                        Label("Tarjetas NFC y productos", systemImage: "shippingbox")
                        Spacer()
                        Text("\(store.money.products.count)").foregroundStyle(.secondary)
                    }
                }
            }
            if !store.money.lowStockProducts.isEmpty {
                Section("Reponer tarjetas") {
                    ForEach(store.money.lowStockProducts) { product in
                        NavigationLink { ProductDetailView(productID: product.id) } label: {
                            Label("\(product.displayName): \(store.money.stock(product.id)) disponibles", systemImage: "exclamationmark.circle")
                        }
                    }
                }
            }
            Section {
                historyFilter
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            } header: { Text("Historial detallado") }
            Section {
                if history.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tu dinero, en un mismo lugar").font(.headline)
                        Text("Las ganancias guardadas en los negocios aparecerán aquí. Registra tus compras de tarjetas, stands u otros gastos para conocer tu saldo.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }
                ForEach(history) { transaction in
                    if transaction.kind.isIncome, let id = transaction.businessID, store.records.contains(where: { $0.id == id }) {
                        NavigationLink { RecordDetailView(recordID: id) } label: { MoneyRow(transaction: transaction) }
                            .contextMenu { Button("Detalle del movimiento") { detail = transaction } }
                    } else {
                        NavigationLink { MoneyTransactionView(transactionID: transaction.id) } label: { MoneyRow(transaction: transaction) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dinero")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showExpense = true } label: { Image(systemName: "plus") }.accessibilityLabel("Añadir gasto") } }
        .sheet(isPresented: $showExpense) { ExpenseForm() }
        .sheet(item: $detail) { item in NavigationStack { MoneyTransactionView(transactionID: item.id).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { detail = nil } } } } }
        #if DEBUG
        .navigationDestination(isPresented: $verificationInventory) { InventoryView() }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--verification-inventory") { verificationInventory = true }
            if ProcessInfo.processInfo.arguments.contains("--verification-expense") { showExpense = true }
        }
        #endif
    }
    @ViewBuilder private var historyFilter: some View {
        if typeSize.isAccessibilitySize {
            Picker("Movimientos", selection: $filter) {
                ForEach(["Todos", "Ingresos", "Gastos"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu)
        } else {
            Picker("Movimientos", selection: $filter) {
                ForEach(["Todos", "Ingresos", "Gastos"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
        }
    }
    private func summary(_ label: String, cents: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: label == "Ingresos" ? "arrow.down.left" : "arrow.up.right").font(.caption).foregroundStyle(.secondary)
            Text(Double(cents) / 100, format: .currency(code: "EUR")).font(.headline).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct MoneyRow: View {
    let transaction: MoneyTransaction
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
            Image(systemName: transaction.kind.isIncome ? "arrow.down.left.circle.fill" : transaction.kind == .stockAdjustment ? "shippingbox.fill" : "arrow.up.right.circle.fill")
                .foregroundStyle(transaction.kind.isIncome ? Color.green : Color.orange).font(.title3).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title).font(.body.weight(.semibold))
                Text(transaction.typeTitle + (transaction.quantity != 0 ? " · \(transaction.quantity) uds." : "")).font(.caption).foregroundStyle(.secondary)
                if !transaction.merchant.isEmpty { Text(transaction.merchant).font(.caption).foregroundStyle(.secondary) }
                Text(transaction.date, format: .dateTime.day().month(.abbreviated).year().hour().minute()).font(.caption2).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 6) }
            Text(transaction.amount, format: .currency(code: "EUR")).font(.subheadline.bold())
                .foregroundStyle(transaction.cents < 0 ? Color.primary : Color.green).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(.vertical, 4)
    }
}
struct InventoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showPurchase = false
    var body: some View {
        List {
            Section {
                Button { showPurchase = true } label: { Label("Comprar / añadir producto", systemImage: "plus.circle") }
                Text("Cada color tiene sus propias existencias. Asigna las tarjetas al editar una venta para descontarlas del inventario.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(ProductKind.allCases) { kind in
                let products = store.money.products.filter { $0.kind == kind }
                if !products.isEmpty {
                    Section(kind.title) {
                        ForEach(products) { product in
                            NavigationLink { ProductDetailView(productID: product.id) } label: {
                                HStack(spacing: 12) {
                                    ProductThumbnail(product: product)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.displayName).font(.headline)
                                        Text("\(store.money.stock(product.id)) disponibles · \(store.money.purchased(product.id)) comprados").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            if store.money.products.isEmpty {
                Section {
                    Text("Registra una compra de tarjetas de cualquier color, un stand o un producto personalizado. Se guardarán la cantidad, el coste y el enlace para comprarlo de nuevo.").foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Inventario")
            .sheet(isPresented: $showPurchase) { ExpenseForm(initialCategory: ProductKind.nfcCard.rawValue) }
    }
}
struct ProductThumbnail: View {
    let product: InventoryProduct
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.1))
            if let url = ProductMetadataService.purchaseURL(product.imageURL) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: product.kind.icon).foregroundStyle(Color.accentColor) }
            } else { Image(systemName: product.kind.icon).foregroundStyle(Color.accentColor).font(.title2) }
        }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
struct ProductDetailView: View {
    let productID: UUID
    @EnvironmentObject private var store: AppStore
    @State private var showPurchase = false
    @State private var showAdjustment = false
    var body: some View {
        if let product = store.money.products.first(where: { $0.id == productID }) {
            List {
                Section {
                    HStack(spacing: 14) { ProductThumbnail(product: product); Text(product.displayName).font(.title3.bold()) }
                    LabeledContent("Disponibles", value: "\(store.money.stock(productID))")
                    LabeledContent("Adquiridos", value: "\(store.money.purchased(productID))")
                    if product.kind == .nfcCard { LabeledContent("Vendidos a negocios", value: "\(store.money.sold(productID))") }
                    LabeledContent("Dinero gastado", value: store.money.spent(productID).formatted(.currency(code: "EUR")))
                }
                Section {
                    Button("Registrar nueva compra") { showPurchase = true }
                    if let url = ProductMetadataService.purchaseURL(product.purchaseURL) { Link("Volver a comprar", destination: url) }
                    Button("Ajustar existencias") { showAdjustment = true }
                }
                Section("Movimientos de este producto") {
                    ForEach(store.money.history.filter { $0.productID == productID }) { transaction in
                        NavigationLink { MoneyTransactionView(transactionID: transaction.id) } label: { MoneyRow(transaction: transaction) }
                    }
                }
            }.navigationTitle(product.kind.title).navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showPurchase) { ExpenseForm(initialProductID: productID, initialCategory: product.kind.rawValue) }
                .sheet(isPresented: $showAdjustment) { StockAdjustmentForm(productID: productID) }
        } else { Text("Producto no disponible") }
    }
}
struct MoneyTransactionView: View {
    let transactionID: UUID
    @EnvironmentObject private var store: AppStore
    @State private var showReverse = false
    @State private var showCorrection = false
    @State private var error: String?
    var body: some View {
        if let item = store.money.transactions.first(where: { $0.id == transactionID }) {
            List {
                Section {
                    Text(item.title).font(.title2.bold())
                    Text(item.amount, format: .currency(code: "EUR")).font(.largeTitle.bold())
                    LabeledContent("Tipo", value: item.typeTitle)
                    LabeledContent("Fecha", value: item.date.formatted(date: .abbreviated, time: .shortened))
                    if item.quantity != 0 { LabeledContent("Unidades", value: "\(item.quantity)") }
                    if let id = item.productID, let product = store.money.products.first(where: { $0.id == id }) {
                        NavigationLink(product.displayName) { ProductDetailView(productID: id) }
                    }
                    if !item.merchant.isEmpty { LabeledContent("Dónde", value: item.merchant) }
                    if !item.paymentMethod.isEmpty { LabeledContent("Cómo pagaste", value: item.paymentMethod) }
                    if !item.notes.isEmpty { Text(item.notes).foregroundStyle(.secondary) }
                }
                if let id = item.businessID {
                    Section {
                        if store.records.contains(where: { $0.id == id }) { NavigationLink("Abrir ficha del negocio") { RecordDetailView(recordID: id) } }
                        else { Text("La ficha se ha eliminado. El ingreso se conserva en tu historial.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                if let url = ProductMetadataService.purchaseURL(item.purchaseURL) {
                    Section("Compra") { Link("Abrir enlace / volver a comprar", destination: url); Text(item.purchaseURL).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                if item.kind == .expense {
                    Section {
                        if store.money.isReversed(item.id) { Label("Gasto anulado; original conservado", systemImage: "arrow.uturn.backward").foregroundStyle(.secondary) }
                        else {
                            Button("Corregir gasto") { showCorrection = true }
                            Button("Anular gasto / devolver compra", role: .destructive) { showReverse = true }
                        }
                    } footer: { Text("Las correcciones y devoluciones se registran sin borrar el historial. Una devolución también retira las unidades adquiridas del inventario.") }
                }
            }.navigationTitle("Movimiento").navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("¿Anular este gasto?", isPresented: $showReverse, titleVisibility: .visible) {
                    Button("Registrar devolución", role: .destructive) { do { try store.reverseExpense(item.id) } catch { self.error = error.localizedDescription } }
                }
                .sheet(isPresented: $showCorrection) { ExpenseForm(initialProductID: item.productID, initialCategory: item.productID.flatMap { id in store.money.products.first(where: { $0.id == id })?.kind.rawValue } ?? "expense", correction: item) }
                .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
        } else { Text("Movimiento no disponible") }
    }
}
struct ExpenseForm: View {
    var initialProductID: UUID? = nil
    var initialCategory = "expense"
    var correction: MoneyTransaction? = nil
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var category = "expense"
    @State private var selectedProductID: UUID?
    @State private var name = ""
    @State private var color = "Negro"
    @State private var quantity = 1
    @State private var amount = ""
    @State private var merchant = ""
    @State private var method = ""
    @State private var link = ""
    @State private var imageURL = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var importing = false
    @State private var importMessage: String?
    @State private var error: String?
    @State private var initialized = false
    @State private var importTask: Task<Void, Never>?
    @State private var origin: InventoryAcquisition = .purchase
    init(initialProductID: UUID? = nil, initialCategory: String = "expense", correction: MoneyTransaction? = nil) {
        self.initialProductID = initialProductID; self.initialCategory = initialCategory; self.correction = correction
        _category = State(initialValue: initialCategory)
        _selectedProductID = State(initialValue: initialProductID)
    }
    private var kind: ProductKind? { ProductKind(rawValue: category) }
    private var selectedProduct: InventoryProduct? { store.money.products.first { $0.id == selectedProductID } }
    private var withoutCost: Bool { kind != nil && origin != .purchase && correction == nil }
    private var canSave: Bool { (withoutCost || (SaleAmountFormatting.parse(amount) ?? 0) > 0) && (selectedProduct != nil || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (kind != .nfcCard || selectedProduct != nil || !color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (kind == nil || (1...100_000).contains(quantity)) && !importing }
    var body: some View {
        NavigationStack {
            Form {
                Section("Compra o gasto") {
                    Picker("Categoría", selection: $category) {
                        Text("Gasto del negocio").tag("expense")
                        ForEach(ProductKind.allCases) { Text($0.title).tag($0.rawValue) }
                    }.onChange(of: category) { _ in selectedProductID = nil }
                    if let kind {
                        if correction == nil {
                            Picker("Origen", selection: $origin) {
                                ForEach(InventoryAcquisition.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        Picker("Producto", selection: $selectedProductID) {
                            Text("Crear producto nuevo").tag(UUID?.none)
                            ForEach(store.money.products.filter { $0.kind == kind }) { Text($0.displayName).tag(Optional($0.id)) }
                        }.onChange(of: selectedProductID) { _ in
                            if let product = selectedProduct { link = product.purchaseURL; imageURL = product.imageURL }
                        }
                    }
                    if selectedProduct == nil {
                        TextField(kind == nil ? "Concepto del gasto" : "Nombre del producto", text: $name)
                        if kind == .nfcCard { TextField("Color (negro, blanco, personalizado…)", text: $color) }
                    }
                    if kind != nil {
                        HStack {
                            Text("Cantidad")
                            Spacer()
                            TextField("1", value: $quantity, format: .number.grouping(.never)).keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).frame(width: 70).accessibilityLabel("Unidades adquiridas")
                            Stepper("Cantidad", value: $quantity, in: 1...100_000).labelsHidden().fixedSize()
                        }
                    }
                    HStack {
                        Text("Coste total")
                        if withoutCost { Spacer(); Text("0,00 €").foregroundStyle(.secondary) }
                        else { TextField("0,00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        if !withoutCost { Text("€").foregroundStyle(.secondary) }
                    }
                    if !withoutCost, kind != nil, quantity > 0, let value = SaleAmountFormatting.parse(amount), value > 0 {
                        LabeledContent("Coste por unidad", value: (value / Double(quantity)).formatted(.currency(code: "EUR")))
                    }
                    DatePicker(withoutCost ? "Fecha de entrada" : "Fecha del gasto", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    TextField("Enlace de compra (opcional)", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button { importProduct() } label: {
                        HStack { Label("Importar datos del producto", systemImage: "arrow.down.doc"); if importing { Spacer(); ProgressView() } }
                    }.disabled(ProductMetadataService.purchaseURL(link) == nil || importing)
                    if let importMessage { Text(importMessage).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Volver a comprar") } footer: { Text("La importación intenta obtener el nombre, la imagen y el precio. Revisa el coste total; si la tienda no facilita datos, rellénalos manualmente.") }
                Section("Detalles") {
                    TextField("Tienda / proveedor", text: $merchant)
                    TextField("Cómo pagaste (tarjeta, efectivo…)", text: $method)
                    TextField("Notas", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section { Text(withoutCost ? "La entrada aumenta el inventario, conserva su origen en el historial y no cambia el saldo." : "Este gasto se descontará de tu saldo aunque quede negativo.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle(correction == nil ? "Registrar entrada" : "Corregir gasto").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.appConfirmationButton().disabled(!canSave) }
                }
                .onAppear { initialize() }
                .onDisappear { importTask?.cancel() }
                .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func initialize() {
        guard !initialized else { return }; initialized = true
        if let product = selectedProduct { link = product.purchaseURL; imageURL = product.imageURL }
        if let correction {
            name = correction.title; amount = SaleAmountFormatting.text(for: -correction.amount)
            quantity = max(1, correction.quantity); merchant = correction.merchant; method = correction.paymentMethod
            link = correction.purchaseURL; notes = correction.notes; date = min(correction.date, Date())
        }
    }
    private func importProduct() {
        guard let url = ProductMetadataService.purchaseURL(link) else { return }
        let requestedLink = link, owner = store.loadedUserEmail
        importing = true; importMessage = nil
        importTask = Task { @MainActor in
            defer { importing = false }
            do {
                let result = try await ProductMetadataService.fetch(url)
                guard !Task.isCancelled, link == requestedLink, store.loadedUserEmail == owner else { return }
                if name.isEmpty { name = result.name }
                if imageURL.isEmpty { imageURL = result.imageURL }
                if amount.isEmpty, let price = result.euroPrice { amount = SaleAmountFormatting.text(for: price * Double(quantity)) }
                if merchant.isEmpty { merchant = url.host ?? "" }
                importMessage = result.name.isEmpty && result.euroPrice == nil ? "No hay datos de producto disponibles. Puedes rellenarlos manualmente." : result.currency.isEmpty || result.currency.uppercased() == "EUR" ? "Datos importados. Comprueba la cantidad y el coste total antes de guardar." : "Datos importados. El precio está en \(result.currency); introduce manualmente el coste en euros."
            } catch { if !Task.isCancelled { importMessage = "No se pudieron importar los datos. Puedes rellenarlos manualmente." } }
        }
    }
    private func save() {
        guard let value = withoutCost ? 0 : SaleAmountFormatting.parse(amount) else { return }
        if !link.isEmpty && ProductMetadataService.purchaseURL(link) == nil { error = "Introduce un enlace completo que empiece por https:// o deja el campo vacío."; return }
        let title = selectedProduct?.displayName ?? name.trimmingCharacters(in: .whitespacesAndNewlines)
        let product: InventoryProduct? = selectedProduct == nil ? kind.map { InventoryProduct(name: title, kind: $0, color: $0 == .nfcCard ? color.trimmingCharacters(in: .whitespacesAndNewlines) : "", purchaseURL: link, imageURL: imageURL) } : nil
        do {
            if withoutCost, let id = selectedProductID ?? product?.id {
                try store.receiveStock(title: product?.displayName ?? title, quantity: quantity, productID: id, newProduct: product, origin: origin, date: date, notes: notes)
            } else {
                try store.addExpense(title: product?.displayName ?? title, amount: value, quantity: quantity,
                    productID: selectedProductID ?? product?.id, newProduct: product, date: date,
                    merchant: merchant, method: method, url: link, notes: notes, replacing: correction?.id)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
struct StockAdjustmentForm: View {
    let productID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var stock = ""
    @State private var reason = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Existencias actuales", value: "\(store.money.stock(productID))")
                    TextField("Existencias reales", text: $stock).keyboardType(.numberPad)
                    TextField("Motivo (recuento, regalo, rotura…)", text: $reason, axis: .vertical)
                } footer: { Text("Este ajuste se guarda en el historial y cambia las existencias. Para registrar dinero gastado utiliza una compra.") }
            }.navigationTitle("Ajustar existencias").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Guardar") {
                        guard let total = Int(stock), total >= 0 else { return }
                        do { try store.adjustStock(productID, quantity: total - store.money.stock(productID), reason: reason); dismiss() } catch { self.error = error.localizedDescription }
                    }.appConfirmationButton().disabled(Int(stock) == nil || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Int(stock) == store.money.stock(productID)) }
                }
                .onAppear { stock = String(store.money.stock(productID)) }
                .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
        }
    }
}
