import Foundation
import CryptoKit
import Security
import AuthenticationServices
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Each attempt owns its PKCE verifier and callback. Neither is persisted or logged.
struct GoogleOAuthRequest {
    let verifier: String
    let callback: URL
    let authorizeURL: URL

    init(origin: String) throws {
        func random() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw RemoteAuthError.unavailable
            }
            return Self.base64URL(Data(bytes))
        }
        verifier = try random()
        let state = try random()
        callback = URL(string: "reviewnfcgo://auth/callback/" + state)!
        guard var components = URLComponents(string: origin + "/auth/v1/authorize"), components.scheme == "https" else {
            throw RemoteAuthError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: callback.absoluteString),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = components.url else { throw RemoteAuthError.invalidURL }
        authorizeURL = url
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func code(from url: URL) throws -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == callback.scheme, parts.host == callback.host, parts.path == callback.path,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else {
            throw RemoteAuthError.rejected("El acceso no corresponde a esta solicitud. Vuelve a intentarlo.")
        }
        let items = parts.queryItems ?? []
        if items.contains(where: { $0.name == "error" }) {
            if items.contains(where: { $0.name == "error" && $0.value == "access_denied" }) { throw CancellationError() }
            throw RemoteAuthError.rejected("Google no pudo completar el acceso. Inténtalo de nuevo.")
        }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value, !code.isEmpty, code.utf8.count <= 4096,
              !items.contains(where: { ["access_token", "refresh_token"].contains($0.name) }) else {
            throw RemoteAuthError.rejected("El acceso no se ha completado. Vuelve a intentarlo.")
        }
        return code
    }
}

@MainActor final class NativeGoogleBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?

    func open(_ url: URL) async throws -> URL {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "reviewnfcgo") { [weak self] url, error in
                    Task { @MainActor in
                        if let url { self?.finish(.success(url)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self?.finish(.failure(CancellationError()))
                        } else { self?.finish(.failure(RemoteAuthError.unavailable)) }
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                if !session.start() { finish(.failure(RemoteAuthError.unavailable)) }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func cancel() {
        session?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil; session = nil
        continuation.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? ASPresentationAnchor()
        #else
        return NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
        #endif
    }
}

struct GoogleSignInLabel: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("GoogleLogo").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
            Text("Continuar con Google").foregroundStyle(.primary)
        }
    }
}
