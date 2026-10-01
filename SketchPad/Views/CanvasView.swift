import SwiftUI
import PencilKit

/// PKCanvasView 的 SwiftUI 封装
struct CanvasView: UIViewRepresentable {
    @EnvironmentObject private var store: DrawingStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput          // 手指和 Apple Pencil 均可绘制
        canvas.isOpaque = false
        canvas.backgroundColor = store.background.patternColor
        canvas.isScrollEnabled = false            // 单屏画布
        canvas.isZoomEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.drawing = store.drawing
        canvas.tool = store.currentTool
        store.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // 背景仅在画纸样式真正切换时更新（pattern 色每次生成实例不同，不能靠 isEqual 判断）
        if context.coordinator.lastBackground != store.background {
            canvas.backgroundColor = store.background.patternColor
            context.coordinator.lastBackground = store.background
        }
        // 工具 / 颜色 / 粗细变化时同步
        canvas.tool = store.currentTool
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let store: DrawingStore
        var lastBackground: BackgroundStyle?

        init(store: DrawingStore) {
            self.store = store
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            store.updateDrawing(canvasView.drawing)
            store.refreshUndoState()
        }
    }
}
