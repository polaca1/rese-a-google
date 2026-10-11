import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import UIKit
import ActivityKit

// MARK: - Theme

enum AppTheme {
    static let blue = Color(red: 0.05, green: 0.42, blue: 0.95)
    static let softBlue = blue.opacity(0.12)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: - Reusable UI

struct LogoMark: View {
    let size: CGFloat
    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct TopScrollBlurVerification: View {
    let screen: String
    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verification-blur-\(screen)") {
            ScrollBlurProbe(screen: screen)
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
}

struct HomeHeaderScrollMarker: View {
    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--verification-blur-home") {
            HomeHeaderMarkerProbe()
        }
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG
private struct HomeHeaderMarkerProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> HomeHeaderMarkerView { HomeHeaderMarkerView() }
    func updateUIView(_ view: HomeHeaderMarkerView, context: Context) {}
}

private final class HomeHeaderMarkerView: UIView {}

private struct ScrollBlurProbe: UIViewRepresentable {
    let screen: String
    func makeUIView(context: Context) -> ProbeView { ProbeView(screen: screen) }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        let screen: String
        private var scheduled = false
        init(screen: String) { self.screen = screen; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !scheduled else { return }
            scheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, #available(iOS 26.0, *) else { return }
                var ancestor = self.superview
                while ancestor != nil && !(ancestor is UIScrollView) { ancestor = ancestor?.superview }
                guard let scroll = ancestor as? UIScrollView else {
                    self.report(["passed": false, "error": "No native scroll view"]); return
                }
                func findHeader(in view: UIView) -> HomeHeaderMarkerView? {
                    if let header = view as? HomeHeaderMarkerView { return header }
                    for child in view.subviews {
                        if let header = findHeader(in: child) { return header }
                    }
                    return nil
                }
                let header = findHeader(in: scroll)
                let originalHeaderFrame = header?.convert(header?.bounds ?? .zero, to: self.window)
                let originalOffset = scroll.contentOffset.y
                let maxOffset = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let target = min(150, maxOffset)
                scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let currentHeaderFrame = header?.convert(header?.bounds ?? .zero, to: self.window)
                    let actualScroll = scroll.contentOffset.y - originalOffset
                    let headerMovement = (originalHeaderFrame?.minY ?? 0) - (currentHeaderFrame?.minY ?? 0)
                    let headerScrolls = header != nil && actualScroll > 50 && abs(headerMovement - actualScroll) < 2
                    let softEffect = scroll.topEdgeEffect.style == .soft && !scroll.topEdgeEffect.isHidden
                    self.report(["passed": softEffect && (self.screen != "home" || headerScrolls),
                        "screen": self.screen, "nativeSoftEffect": scroll.topEdgeEffect.style == .soft,
                        "effectHidden": scroll.topEdgeEffect.isHidden,
                        "scrollOffset": scroll.contentOffset.y, "maximumOffset": maxOffset,
                        "headerInScrollContent": header != nil, "headerScrollsWithContent": headerScrolls,
                        "headerMovement": headerMovement, "actualScrollDistance": actualScroll])
                }
            }
        }
        private func report(_ result: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) else { return }
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("blur-\(screen)-verification.json")
            try? data.write(to: file)
        }
    }
}
#endif

extension View {
    /// The actual header content registers the blur region with iOS. A clear
    /// spacer has no visible elements for the system to protect with an effect.
    @ViewBuilder
    func appTopScrollBlur<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: .top, spacing: 0, content: content)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectHidden(false, for: .top)
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) { content().background(.ultraThinMaterial) }
        }
    }

    @ViewBuilder
    func appGlassSearch() -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .capsule) }
        else { self.background(.ultraThinMaterial, in: Capsule()) }
    }
    @ViewBuilder
    func appGlassField() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 14))
        } else {
            self.background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    func appGlassOverlay() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Use Apple's actual interactive button styles, including system accessibility.
    @ViewBuilder
    func appConfirmationButton() -> some View {
        if #available(iOS 26.0, *) {
            self.bold().buttonBorderShape(.capsule).buttonStyle(.glassProminent).tint(AppTheme.blue)
        } else {
            self.bold()
        }
    }

    @ViewBuilder
    func appPrimaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.font(.headline)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .buttonStyle(.glassProminent)
                .tint(AppTheme.blue)
        } else {
            self.font(.headline)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.blue)
        }
    }

    @ViewBuilder
    func appSecondaryButton() -> some View {
        if #available(iOS 26.0, *) {
            self.font(.headline)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .buttonStyle(.glass)
                .tint(AppTheme.blue)
        } else {
            self.font(.headline)
                .controlSize(.large)
                .buttonStyle(.bordered)
                .tint(AppTheme.blue)
        }
    }
}
