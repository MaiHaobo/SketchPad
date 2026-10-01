import SwiftUI

/// 底部工具面板：工具选择 + 撤销/重做/清空 + 颜色 + 笔刷粗细
struct ToolPanel: View {
    @EnvironmentObject private var store: DrawingStore

    @Binding var showColorPicker: Bool
    @Binding var showClearConfirm: Bool

    private let widths: [CGFloat] = [3, 6, 10, 16, 24]

    var body: some View {
        VStack(spacing: 12) {
            // 工具选择
            HStack(spacing: 0) {
                ForEach(InkTool.allCases) { tool in
                    toolButton(tool)
                }
            }

            // 动作 + 颜色 + 粗细
            HStack(spacing: 8) {
                FloatingIconButton(
                    systemImage: "arrow.uturn.backward",
                    disabled: !store.canUndo
                ) {
                    store.undo()
                }
                FloatingIconButton(
                    systemImage: "arrow.uturn.forward",
                    disabled: !store.canRedo
                ) {
                    store.redo()
                }
                FloatingIconButton(systemImage: "trash", tint: .red) {
                    showClearConfirm = true
                }

                Spacer(minLength: 12)

                colorButton
                widthButton
            }
            .frame(height: 40)
        }
        .padding(14)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - 工具按钮

    private func toolButton(_ tool: InkTool) -> some View {
        let isSelected = store.ink == tool
        return Button {
            store.ink = tool
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 18, weight: .medium))
                Text(tool.name)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 颜色按钮

    private var colorButton: some View {
        Button {
            showColorPicker = true
        } label: {
            Circle()
                .fill(Color(uiColor: store.inkColor))
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        .padding(2)
                )
        }
        .frame(width: 40, height: 40)
        .background(Color.primary.opacity(0.08), in: Circle())
        .disabled(store.ink == .eraser)
        .opacity(store.ink == .eraser ? 0.35 : 1)
    }

    // MARK: - 粗细按钮

    private var dotSize: CGFloat {
        min(max(store.brushWidth, 4), 24)
    }

    private var widthButton: some View {
        Menu {
            ForEach(widths, id: \.self) { width in
                Button {
                    store.brushWidth = width
                } label: {
                    if store.brushWidth == width {
                        Label("笔尖 \(Int(width)) pt", systemImage: "checkmark")
                    } else {
                        Text("笔尖 \(Int(width)) pt")
                    }
                }
            }
        } label: {
            Circle()
                .fill(Color.primary)
                .frame(width: dotSize, height: dotSize)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .disabled(store.ink == .eraser)
        .opacity(store.ink == .eraser ? 0.35 : 1)
    }
}
