import SwiftUI
import PencilKit
import UIKit

// MARK: - 墨水工具

enum InkTool: String, CaseIterable, Identifiable {
    case pen       // 钢笔
    case pencil    // 铅笔
    case marker    // 马克笔
    case eraser    // 橡皮擦

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    var name: String {
        switch self {
        case .pen: return "钢笔"
        case .pencil: return "铅笔"
        case .marker: return "马克笔"
        case .eraser: return "橡皮"
        }
    }

    func tool(color: UIColor, width: CGFloat) -> PKTool {
        switch self {
        case .pen:
            return PKInkingTool(.pen, tint: color, width: width)
        case .pencil:
            return PKInkingTool(.pencil, tint: color, width: width * 1.4)
        case .marker:
            return PKInkingTool(.marker, tint: color, width: width * 2.4)
        case .eraser:
            return PKEraserTool(.bitmap)
        }
    }
}

// MARK: - 画廊条目

struct Artwork: Identifiable, Codable {
    let id: UUID
    var savedAt: Date
}

// MARK: - 全局状态中心

@MainActor
final class DrawingStore: ObservableObject {

    // MARK: 画布

    weak var canvas: PKCanvasView?

    /// 当前画布内容（不触发视图刷新，由 delegate 单向同步，避免绘画过程中高频重绘）
    private(set) var drawing = PKDrawing()

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    // MARK: 工具

    @Published var ink: InkTool = .pen {
        didSet { applyTool() }
    }
    @Published var inkColor: UIColor = UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1) {
        didSet { applyTool() }
    }
    @Published var brushWidth: CGFloat = 8 {
        didSet { applyTool() }
    }

    @Published var background: BackgroundStyle = .white

    // MARK: 画廊

    @Published private(set) var gallery: [Artwork] = []
    @Published var editingArtworkID: UUID?

    // MARK: 提示

    @Published var toast: String?

    // MARK: - 路径

    private var artworksDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Artworks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        loadGallery()
    }

    // MARK: - 工具应用

    var currentTool: PKTool {
        ink.tool(color: inkColor, width: brushWidth)
    }

    private func applyTool() {
        canvas?.tool = currentTool
    }

    // MARK: - 撤销 / 重做 / 清空

    func refreshUndoState() {
        let canUndoNow = canvas?.undoManager?.canUndo ?? false
        let canRedoNow = canvas?.undoManager?.canRedo ?? false
        // 仅在状态真正变化时赋值，避免绘画过程中频繁触发对象刷新
        if canUndoNow != canUndo { canUndo = canUndoNow }
        if canRedoNow != canRedo { canRedo = canRedoNow }
    }

    func undo() {
        canvas?.undoManager?.undo()
    }

    func redo() {
        canvas?.undoManager?.redo()
    }

    func clearCanvas() {
        load(PKDrawing())
    }

    /// 程序化替换画布内容（打开画作 / 清空）
    func load(_ newDrawing: PKDrawing, artworkID: UUID? = nil) {
        editingArtworkID = artworkID
        drawing = newDrawing
        canvas?.drawing = newDrawing
        refreshUndoState()
    }

    /// 由画布 delegate 单向同步内容
    func updateDrawing(_ newDrawing: PKDrawing) {
        drawing = newDrawing
    }

    func startNewArtwork() {
        load(PKDrawing())
    }

    // MARK: - 导出

    /// 将当前画布渲染为完整图片（背景 + 笔画）
    func renderImage(scale: CGFloat = 2) -> UIImage? {
        guard let canvas else { return nil }
        let size = canvas.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            background.patternColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let bounds = canvas.drawing.bounds
            if !bounds.isEmpty, bounds.width > 0, bounds.height > 0 {
                let strokes = canvas.drawing.image(from: bounds, scale: scale)
                strokes.draw(in: bounds)
            }
        }
    }

    /// 导出 PNG 到临时目录（用于分享）
    func exportPNGURL() -> URL? {
        guard let image = renderImage() else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SketchPad-\(stamp).png")
        do {
            try image.pngData()?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    func saveToPhotoLibrary() {
        guard let image = renderImage() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showToast("已保存到相册")
    }

    // MARK: - 画廊存取

    func saveToGallery() {
        let id = editingArtworkID ?? UUID()
        let isNew = editingArtworkID == nil
        do {
            let drawingURL = artworksDir.appendingPathComponent("\(id.uuidString).drawing")
            try drawing.dataRepresentation().write(to: drawingURL)

            let thumbURL = artworksDir.appendingPathComponent("\(id.uuidString).png")
            if let image = renderImage(scale: 1) {
                try? image.pngData()?.write(to: thumbURL)
            }

            if isNew {
                gallery.insert(Artwork(id: id, savedAt: Date()), at: 0)
                editingArtworkID = id
            } else if let index = gallery.firstIndex(where: { $0.id == id }) {
                gallery[index].savedAt = Date()
            }
            showToast(isNew ? "已保存到画廊" : "画作已更新")
        } catch {
            showToast("保存失败，请重试")
        }
    }

    func loadGallery() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: artworksDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        var items: [Artwork] = []
        for url in files where url.pathExtension == "drawing" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name) else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            items.append(Artwork(id: id, savedAt: date))
        }
        gallery = items.sorted { $0.savedAt > $1.savedAt }
    }

    func openArtwork(_ artwork: Artwork) {
        let url = artworksDir.appendingPathComponent("\(artwork.id.uuidString).drawing")
        guard let data = try? Data(contentsOf: url),
              let saved = try? PKDrawing(data: data) else {
            showToast("无法打开画作")
            return
        }
        load(saved, artworkID: artwork.id)
    }

    func deleteArtwork(_ artwork: Artwork) {
        let fm = FileManager.default
        try? fm.removeItem(at: artworksDir.appendingPathComponent("\(artwork.id.uuidString).drawing"))
        try? fm.removeItem(at: artworksDir.appendingPathComponent("\(artwork.id.uuidString).png"))
        gallery.removeAll { $0.id == artwork.id }
        if editingArtworkID == artwork.id {
            editingArtworkID = nil
        }
    }

    func thumbnail(for artwork: Artwork) -> UIImage? {
        let url = artworksDir.appendingPathComponent("\(artwork.id.uuidString).png")
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: - Toast

    func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            toast = text
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.toast == text else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.toast = nil
            }
        }
    }
}
