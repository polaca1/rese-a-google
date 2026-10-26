import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

// MARK: - Home

struct HomeView: View {
    var showsNavigation = false
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: AppStore
    @StateObject private var finder = PlaceFinder()
    @State private var searchText = ""
    @State private var showSearchResults = false
    @FocusState private var searchFocused: Bool
    @State private var showSavedToast = false
    @State private var reminderPlace: PlaceResult?
    @State private var writingRecord: VisitRecord?
    @EnvironmentObject private var portalRouter: PortalRouter

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header.background(HomeHeaderScrollMarker())
                if showSearchResults && searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 { searchSuggestions }
                NativeMapView(selectedPlace: finder.selectedPlace, focusRequest: finder.mapFocus) { coordinate in
                    showSearchResults = false; searchFocused = false
                    Task { await finder.searchNearest(to: coordinate) }
                }
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                statusRow

                if !finder.nearbyChoices.isEmpty {
                    nearbyChoicesCard
                } else if let place = finder.selectedPlace {
                    placeCard(place)
                } else if finder.isLoading {
                    ProgressView("Buscando locales cercanos…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                }

                if let error = finder.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .background(TopScrollBlurVerification(screen: "home"))
        }
        .appTopScrollBlur {
            searchBar.padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(AppTheme.background)
        .navigationBarHidden(!showsNavigation)
        .navigationTitle(showsNavigation ? "Buscar negocio" : "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-nearby") {
                Task { await NearbyPlaceVerification.run(finder: finder) }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--verification-blur-home") || ProcessInfo.processInfo.arguments.contains("--verification-home-top") {
                finder.prepareMapVerification()
                finder.chooseSearchResult(MajorUpdateVerification.searchPlaces[0])
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--verification-map") {
                Task { await MapCameraVerification.run(finder: finder) }
                return
            }
            #endif
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-search") {
                finder.prepareMapVerification(); searchText = "Café"; searchFocused = false
                return
            }
            #endif
            finder.start()
        }
        .onChange(of: searchText) { query in
            showSearchResults = true
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-search") {
                finder.beginNameSearch(query, saved: MajorUpdateVerification.searchPlaces); return
            }
            #endif
            finder.beginNameSearch(query, saved: store.records.map(\.place))
        }
        .task(id: searchText) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verification-search") { return }
            #endif
            let query = searchText
            guard showSearchResults, query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
            do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
            guard !Task.isCancelled, showSearchResults, query == searchText else { return }
            await finder.searchByName(query, saved: store.records.map(\.place))
        }
        .overlay(alignment: .top) {
            if showSavedToast {
                Text("Enlace copiado y sitio guardado")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: portalRouter.pendingRecordID) { id in
            if id != nil { reminderPlace = nil }
        }
        .sheet(item: $writingRecord) { record in
            NavigationStack { NFCCardWriteView(recordID: record.id) }
        }
        .sheet(item: $reminderPlace) { place in
            QuickReminderView(place: place)
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hola, \(auth.currentUser?.name.components(separatedBy: " ").first ?? "")")
                    .font(.title2.bold())
                Text("Obtén el enlace de reseña en segundos")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            ProfileAvatar(size: 42)
        }
        .padding(.top, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar negocio por nombre", text: $searchText)
                .submitLabel(.search).focused($searchFocused).autocorrectionDisabled()
                .onSubmit { searchFocused = false; showSearchResults = true; Task { await finder.searchByName(searchText, saved: store.records.map(\.place)) } }
            if finder.isLoading { ProgressView().controlSize(.small) }
            if !searchText.isEmpty {
                Button { searchText = ""; showSearchResults = false; finder.beginNameSearch("", saved: []) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Borrar búsqueda")
            }
        }.padding(.horizontal, 18).padding(.vertical, 16).appGlassSearch()
    }
    private var searchSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Coincidencias y recomendaciones").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showSearchResults = false; searchFocused = false } label: { Image(systemName: "chevron.up") }.accessibilityLabel("Ocultar resultados")
            }.padding(.horizontal, 16).padding(.vertical, 12)
            if finder.searchResults.isEmpty {
                Text(finder.isLoading ? "Buscando coincidencias…" : "Escribe el nombre y la ciudad para afinar la búsqueda.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(finder.searchResults) { place in
                            Button {
                                showSearchResults = false; searchFocused = false
                                finder.chooseSearchResult(place)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(AppTheme.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                        Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
                                }.padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if place.id != finder.searchResults.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                }.frame(maxHeight: min(280, CGFloat(finder.searchResults.count) * 82))
            }
        }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: finder.isLoading ? "location.circle" : "location.fill")
                .foregroundStyle(AppTheme.blue)
            Text(finder.status).font(.footnote.weight(.medium))
            Spacer()
            if finder.userLocation != nil {
                Button("Mi ubicación") {
                    showSearchResults = false; searchFocused = false
                    Task { await finder.useMyLocation() }
                }
                .font(.footnote.weight(.semibold))
                .appSecondaryButton()
                .controlSize(.small)
                .disabled(finder.isFindingNearby)
                .accessibilityHint("Vuelve a pulsar para seleccionar otro local cercano")
            }
        }
        .padding(.horizontal, 4)
    }

    private var nearbyChoicesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("¿En qué local estás?").font(.title3.bold())
            Text("Hay dos opciones muy cerca.").font(.subheadline).foregroundStyle(.secondary)
                .padding(.bottom, 10)
            ForEach(finder.nearbyChoices) { place in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { finder.chooseNearbyPlace(place) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title3).foregroundStyle(AppTheme.blue)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.softBlue, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            if !place.address.isEmpty { Text(place.address).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Seleccionar este negocio")
                if place.id != finder.nearbyChoices.last?.id { Divider().padding(.leading, 56) }
            }
        }
        .padding(20)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func placeCard(_ place: PlaceResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(finder.nearbyPosition > 0 ? "LOCAL CERCANO · \(finder.nearbyPosition) DE \(finder.nearbyCount)" : "NEGOCIO SELECCIONADO")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(place.name).font(.title3.bold())
                    if !place.address.isEmpty {
                        Text(place.address).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(.green)
            }

            if finder.nearbyCount > 1 {
                Text("Vuelve a pulsar «Mi ubicación» para ver otro local cercano.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Divider()

            Button {
                store.addOrUpdatePlace(place)
                writingRecord = store.records.first { $0.place.id == place.id }
            } label: {
                Label("Escribir NFC", systemImage: "wave.3.right")
                    .frame(maxWidth: .infinity)
            }
            .appPrimaryButton()

            Button {
                UIPasteboard.general.string = place.reviewURL
                store.addOrUpdatePlace(place)
                withAnimation { showSavedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                    withAnimation { showSavedToast = false }
                }
            } label: {
                Label("Copiar enlace de reseña", systemImage: "doc.on.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .appSecondaryButton()

            Button {
                store.addOrUpdatePlace(place)
                reminderPlace = place
            } label: {
                Label("Volver más tarde", systemImage: "calendar.badge.clock")
                    .frame(maxWidth: .infinity)
            }
            .appSecondaryButton()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("UBICACIÓN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                ZStack {
                    PlaceMiniMap(place: place)
                        .allowsHitTesting(false)
                    Button {
                        MapLauncher.openAppleMaps(place: place)
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cómo llegar con Apple Maps")
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label("Cómo llegar", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .appGlassOverlay()
                        .padding(10)
                        .allowsHitTesting(false)
                }

                HStack(spacing: 10) {
                    Button { MapLauncher.openAppleMaps(place: place) } label: {
                        Label("Apple Maps", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .appSecondaryButton()

                    Button { MapLauncher.openGoogleMaps(place: place) } label: {
                        Label("Google Maps", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .appSecondaryButton()
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// Keep the two native compact controls on the same row as their label.
