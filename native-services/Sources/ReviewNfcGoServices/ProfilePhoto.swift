import Foundation
import Combine
import PhotosUI
import CryptoKit
import UIKit
import ImageIO

@MainActor
final class ProfilePhotoStore: ObservableObject {
    @Published private(set) var image: UIImage?
    var didChange: (() -> Void)?
    private(set) var email: String?
    var backupData: Data? { email.flatMap { UserDefaults.standard.data(forKey: key($0)) } }
    static func validateBackupPhoto(_ data: Data?) throws {
        guard let data else { return }
        guard data.count <= 2_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...640).contains(width), (1...640).contains(height), UIImage(data: data) != nil else { throw PhotoError.invalid }
    }
    func restoreBackupData(_ data: Data?) throws {
        try Self.validateBackupPhoto(data)
        guard let email else { throw BackupError.wrongAccount }
        if let data { UserDefaults.standard.set(data, forKey: key(email)); image = UIImage(data: data) }
        else { remove() }
        didChange?()
    }
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
        didChange?()
    }
    func remove() { if let email { UserDefaults.standard.removeObject(forKey: key(email)) }; image = nil; didChange?() }
    enum PhotoError: LocalizedError { case invalid; var errorDescription: String? { "No se pudo abrir esa foto. Prueba con otra imagen." } }
}
