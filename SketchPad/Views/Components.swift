import SwiftUI
import UIKit

// MARK: - 玻璃圆形按钮

struct FloatingIconButton: View {
    let systemImage: String
    var tint: Color = .primary
    var disabled: Bool = false
    /// 危险操作（如删除）用带色玻璃强调
    var destructive: Bool = false
    let action: () -> Void

    private var glassStyle: GlassStyle {
        if disabled { return .regular }
        return destructive ? .tinted(.red) : .interactive
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .adaptiveGlassCircle(glassStyle)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

// MARK: - 系统分享面板

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 颜色选择面板

struct ColorSheet: View {
    @EnvironmentObject private var store: DrawingStore
    @Environment(\.dismiss) private var dismiss

    @State private var customColor: Color = .black

    private let colors: [UIColor] = [
        // 第一排：黑白灰
        UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1),
        .darkGray, .lightGray, .white,
        .systemRed,
        // 第二排：暖色
        .systemOrange, .systemYellow, .systemGreen, .systemMint,
        .systemTeal,
        // 第三排：冷色
        .systemCyan, .systemBlue, .systemIndigo, .systemPurple,
        .systemPink,
        // 第四排:扩展色
        .systemBrown,
        UIColor(red: 0.56, green: 0.06, blue: 0.36, alpha: 1),   // 玫红
        UIColor(red: 0.42, green: 0.48, blue: 0.13, alpha: 1),   // 橄榄
        UIColor(red: 0.11, green: 0.20, blue: 0.38, alpha: 1),   // 藏蓝
        UIColor(red: 0.96, green: 0.89, blue: 0.82, alpha: 1),   // 米白
    ]

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 5
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                            colorCell(color)
                        }
                    }

                    Divider()

                    ColorPicker("自定义颜色", selection: $customColor, supportsOpacity: false)
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 4)
                        .onChange(of: customColor) { newValue in
                            store.inkColor = UIColor(newValue)
                        }
                }
                .padding(20)
            }
            .navigationTitle("选择颜色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            // iOS 26：让面板背景透明，透出后方画布的玻璃质感
            .adaptiveSheetGlassBackground()
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            customColor = Color(uiColor: store.inkColor)
        }
    }

    private func colorCell(_ color: UIColor) -> some View {
        let isSelected = store.inkColor.isEqual(color)
        return Button {
            store.inkColor = color
        } label: {
            ZStack {
                Circle()
                    .fill(Color(uiColor: color))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle().strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                            lineWidth: isSelected ? 3 : 1
                        )
                    )
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(contrastColor(for: color))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func contrastColor(for color: UIColor) -> Color {
        var white: CGFloat = 0
        color.getWhite(&white, alpha: nil)
        return white > 0.6 ? .black : .white
    }
}
