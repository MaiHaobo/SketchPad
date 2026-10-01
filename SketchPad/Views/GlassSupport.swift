import SwiftUI

// MARK: - 液态玻璃双路径封装
//
// iOS 26 引入 Liquid Glass 设计语言，SwiftUI 通过 .glassEffect(_:in:) 暴露。
// 本 App 部署目标是 iOS 17，所以这里把「版本判断」收敛到一处：
//   - iOS 26+  → 原生液态玻璃（折射、高光、可交互形变）
//   - iOS 17~25 → 回退到原有的 Material 毛玻璃
//
// 使用约定（很重要）：
//   1. adaptiveGlass 必须写在 .frame()/.padding()/.font() 等「影响外观的修饰符之后」，
//      因为 glassEffect 采样的是它下方（最终形态）的内容。
//   2. 任何祖先视图上的 .clipped() / .mask() 都会让玻璃静默退化成平材质。
//   3. 不要在已经带玻璃的表面上再叠玻璃（glass-on-glass），视觉会发脏。
//   4. 多个玻璃元素相邻时，用 GlassEffectContainer 包起来共享采样，避免接缝。

/// 玻璃样式：把「设计意图」与「系统版本判断」解耦
enum GlassStyle {
    /// 标准玻璃，用于面板、工具栏底色
    case regular
    /// 可交互玻璃：会跟随触摸实时形变（A17 Pro 及以上）
    case interactive
    /// 纯折射（不做磨砂），适合压在图片/画布上
    case clear
    /// 带语义色的玻璃，用于强调
    case tinted(Color)
}

/// 自适应玻璃修饰符：iOS 26 走原生 glassEffect，旧系统走 Material
struct AdaptiveGlass<S: Shape>: ViewModifier {
    var style: GlassStyle = .regular
    var shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glassValue, in: shape)
        } else {
            content.background(legacyMaterial, in: shape)
        }
    }

    @available(iOS 26.0, *)
    private var glassValue: Glass {
        switch style {
        case .regular:
            return .regular
        case .interactive:
            return .regular.interactive()
        case .clear:
            return .clear
        case .tinted(let color):
            return .regular.tint(color)
        }
    }

    private var legacyMaterial: Material {
        switch style {
        case .clear:
            return .ultraThinMaterial
        default:
            return .regularMaterial
        }
    }
}

extension View {
    /// 给任意形状的视图加自适应玻璃底
    func adaptiveGlass<S: Shape>(
        _ style: GlassStyle = .regular,
        in shape: S
    ) -> some View {
        modifier(AdaptiveGlass(style: style, shape: shape))
    }

    /// 圆形浮动控件的玻璃底（图标按钮、菜单按钮等）
    func adaptiveGlassCircle(_ style: GlassStyle = .interactive) -> some View {
        adaptiveGlass(style, in: Circle())
    }

    /// sheet 的透明背景：iOS 26 让面板透出后方画布，旧系统保持系统默认背景
    @ViewBuilder
    func adaptiveSheetGlassBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
                .presentationBackground(.clear)
                .containerBackground(.clear, for: .navigation)
        } else {
            self
        }
    }
}

// MARK: - 容器降级包装

/// 玻璃容器：iOS 26 用 GlassEffectContainer 共享背景采样（避免相邻玻璃出现接缝），
/// 旧系统下等价于普通容器，不影响布局。
struct AdaptiveGlassContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
