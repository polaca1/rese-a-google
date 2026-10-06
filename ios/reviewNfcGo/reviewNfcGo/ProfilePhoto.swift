import SwiftUI
import PhotosUI
import CryptoKit
import UIKit

@MainActor
final class ProfilePhotoStore: ObservableObject {
    @Published private(set) var image: UIImage?
    private(set) var email: String?
    private func key(_ email: String) -> String {
        let hash = SHA256.hash(data: Data(email.utf8)).map { String(format: "%02x", $0) }.joined()
        return "resenago.profilePhoto.\(hash)"
    }
    func switchUser(_ email: String?) {
        self.email = email
        image = email.flatMap { UserDefaults.standard.data(forKey: key($0)) }.flatMap(UIImage.init(data:))
    }
    func save(_ source: UIImage, for owner: String) throws {
        guard owner == email else { return }
        let size = source.size
        guard size.width > 0, size.height > 0 else { throw PhotoError.invalid }
        let ratio = min(1, 640 / max(size.width, size.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width * ratio, height: size.height * ratio), format: format)
        let normalized = renderer.image { context in
            UIColor.systemBackground.setFill(); context.fill(CGRect(origin: .zero, size: CGSize(width: size.width * ratio, height: size.height * ratio)))
            source.draw(in: CGRect(x: 0, y: 0, width: size.width * ratio, height: size.height * ratio))
        }
        guard let data = normalized.jpegData(compressionQuality: 0.85) else { throw PhotoError.invalid }
        UserDefaults.standard.set(data, forKey: key(owner)); image = UIImage(data: data)
    }
    func remove() { if let email { UserDefaults.standard.removeObject(forKey: key(email)) }; image = nil }
    enum PhotoError: LocalizedError { case invalid; var errorDescription: String? { "No se pudo abrir esa foto. Prueba con otra imagen." } }
}
struct ProfileAvatar: View {
    @EnvironmentObject private var photos: ProfilePhotoStore
    var size: CGFloat = 54
    var body: some View {
        Group {
            if let image = photos.image { Image(uiImage: image).resizable().scaledToFill() }
            else { ZStack { Circle().fill(Color.accentColor.opacity(0.12)); Image(systemName: "person.fill").font(.system(size: size * 0.44)).foregroundStyle(Color.accentColor) } }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityLabel("Foto de perfil")
    }
}
struct ProfilePhotoPicker: View {
    @EnvironmentObject private var photos: ProfilePhotoStore
    @State private var selected: PhotosPickerItem?
    @State private var loading = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: $selected, matching: .images) {
                HStack { Label(photos.image == nil ? "Añadir foto de perfil" : "Cambiar foto de perfil", systemImage: "photo"); if loading { Spacer(); ProgressView() } }
            }.disabled(loading)
            if photos.image != nil { Button("Quitar foto", role: .destructive) { task?.cancel(); selected = nil; photos.remove() } }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .onChange(of: selected) { item in
            task?.cancel()
            guard let item, let owner = photos.email else { return }
            loading = true; error = nil
            task = Task { @MainActor in
                defer { loading = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw ProfilePhotoStore.PhotoError.invalid }
                    guard !Task.isCancelled else { return }
                    try photos.save(image, for: owner)
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        }.onDisappear { task?.cancel() }
    }
}
