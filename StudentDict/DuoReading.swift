import SwiftUI
import UIKit

enum DuoHingePhase: Equatable {
    case unavailable
    case closed
    case partiallyOpen
    case fullyOpen
}

struct DuoHingeSnapshot: Equatable {
    var phase: DuoHingePhase
    var radians: Double

    static let unavailable = DuoHingeSnapshot(phase: .unavailable, radians: .pi)
}

/// 一般 iPhone 維持直向。iPhone Duo 展開或半開時才允許橫向，讓內螢幕可以攤成書頁。
enum DuoOrientation {
    static var unfolded = false

    static func setUnfolded(_ unfolded: Bool) {
        guard self.unfolded != unfolded else { return }
        self.unfolded = unfolded
        let mask: UIInterfaceOrientationMask = unfolded ? .allButUpsideDown : .portrait
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

extension View {
    /// 鉸鏈角度只負責開書效果。版面改由尺寸與 ArrangementView 決定。
    @ViewBuilder
    func observingDuoHinge(_ onChange: @escaping (DuoHingeSnapshot) -> Void) -> some View {
        if #available(iOS 27.1, *) {
            self.onHingeChange { _, context in
                guard let hinge = context.hinge else {
                    onChange(.unavailable)
                    return
                }
                let phase: DuoHingePhase
                if hinge.status == .closed {
                    phase = .closed
                } else if hinge.status == .partiallyOpen {
                    phase = .partiallyOpen
                } else if hinge.status == .fullyOpen {
                    phase = .fullyOpen
                } else {
                    phase = .unavailable
                }
                onChange(DuoHingeSnapshot(phase: phase, radians: hinge.angle.radians))
            }
        } else {
            self
        }
    }

    func bookOpenFrost(_ frost: Double, horizontalFold: Bool) -> some View {
        modifier(BookOpenFrostModifier(frost: frost, horizontalFold: horizontalFold))
    }
}

private struct BookOpenFrostModifier: ViewModifier {
    var frost: Double
    var horizontalFold: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: frost * 7)
            .overlay {
                if frost > 0.02 {
                    BookOpenShade(frost: frost, horizontalFold: horizontalFold)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// 書脊保持透，外緣隨掀開角度變暗。攤平時漸層退乾淨。
private struct BookOpenShade: View {
    var frost: Double
    var horizontalFold: Bool

    var body: some View {
        let edge = Color.black.opacity(0.72 * frost)
        if horizontalFold {
            VStack(spacing: 0) {
                LinearGradient(colors: [edge, .clear], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.clear, edge], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        } else {
            HStack(spacing: 0) {
                LinearGradient(colors: [edge, .clear], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, edge], startPoint: .leading, endPoint: .trailing)
            }
            .ignoresSafeArea()
        }
    }
}

/// 避開內螢幕角落的狀態圖示。讀得到遮擋區域時用它的高度，否則用備用上緣間距。
struct DisplayOcclusionPadding: ViewModifier {
    var fallbackTop: CGFloat = 0
    @State private var top: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.top, max(top, fallbackTop))
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { top = Self.measuredTop(in: proxy) }
                        .onChange(of: proxy.size) { _, _ in
                            top = Self.measuredTop(in: proxy)
                        }
                }
            }
    }

    private static func measuredTop(in proxy: GeometryProxy) -> CGFloat {
        guard #available(iOS 27.1, *) else { return 0 }
        let obstruction = proxy.reservedRegions(kind: .occlusion)
            .filter { $0.isActive && $0.frame.minY < 180 }
            .map { $0.frame.maxY + $0.margins.bottom }
            .max() ?? 0
        return min(obstruction, 120)
    }
}

struct OpenDictionaryPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("典")
                .font(.system(size: 108, weight: .regular))
                .foregroundStyle(.primary)
            Text("選擇詞條")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
