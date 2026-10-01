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

    // MARK: iCloud

    @Published private(set) var cloudStatus: CloudStatus = .unknown

    /// 存储层：iCloud 优先，不可用时自动降级本地
    private let storage = ArtworkStorage()

    /// iCloud 目录变更监听
    private var metadataQuery: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    // MARK: - 路径

    private var artworksDir: URL {
        storage.artworksDir
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        metadataQuery?.disableUpdates()
        metadataQuery?.stop()
    }

    init() {
        loadGallery()
        setupCloud()
    }

    // MARK: - iCloud 初始化

    private func setupCloud() {
        // 先看当前是否有 iCloud 账号（同步调用，很快）
        let hasAccount = FileManager.default
            .ubiquityIdentityToken != nil

        guard hasAccount else {
            cloudStatus = .unavailable
            return
        }

        cloudStatus = .available

        // 容器 URL 解析可能耗时，放后台线程
        Task { @MainActor [weak self] in
            guard let self else { return }

            let enabled = await Task.detached(priority: .userInitiated) { [storage] in
                storage.checkCloudAvailability()
            }.value

            guard enabled else {
                self.cloudStatus = .unavailable
                return
            }

            // 迁移本地存量画作
            let moved = await Task.detached(priority: .utility) { [storage] in
                storage.migrateLocalArtworksToCloud()
            }.value

            self.cloudStatus = .syncing
            self.loadGallery()
            if moved > 0 {
                self.showToast("已将 \(moved) 幅画作移到 iCloud")
            }

            self.startMetadataQuery()
            self.observeCloudAccountChanges()
        }
    }

    /// 监听 iCloud 账号登录/登出
    private func observeCloudAccountChanges() {
        let token = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleCloudAccountChange()
            }
        }
        observers.append(token)
    }

    private func handleCloudAccountChange() {
        let storage = self.storage
        Task { @MainActor in
            let enabled = await Task.detached(priority: .userInitiated) {
                storage.checkCloudAvailability()
            }.value

            if enabled {
                self.cloudStatus = .syncing
                self.loadGallery()
                self.startMetadataQuery()
            } else {
                self.cloudStatus = .unavailable
                self.loadGallery()
                self.stopMetadataQuery()
            }
        }
    }

    // MARK: - iCloud 变更监听

    /// 监听 iCloud 目录变化（其他设备新增/删除画作时自动刷新画廊）
    private func startMetadataQuery() {
        guard storage.isUsingCloud, metadataQuery == nil else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K LIKE '*.drawing'",
            NSMetadataItemFSNameKey
        )

        let token = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cloudStatus = .synced(Date())
                self?.loadGallery()
            }
        }
        observers.append(token)

        let updateToken = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cloudStatus = .synced(Date())
                self?.loadGallery()
            }
        }
        observers.append(updateToken)

        metadataQuery = query
        query.start()
    }

    private func stopMetadataQuery() {
        metadataQuery?.disableUpdates()
        metadataQuery?.stop()
        metadataQuery = nil
    }

    /// 手动触发一次同步刷新
    func refreshCloud() {
        guard cloudStatus.isCloudActive else {
            showToast("iCloud 不可用，当前仅保存在本机")
            return
        }
        cloudStatus = .syncing
        loadGallery()
        cloudStatus = .synced(Date())
        showToast("已刷新")
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
            let drawingURL = storage.drawingURL(for: id)
            try storage.write(drawing.dataRepresentation(), to: drawingURL)

            if let image = renderImage(scale: 1) {
                try? storage.write(image.pngData() ?? Data(), to: storage.thumbnailURL(for: id))
            }

            if isNew {
                gallery.insert(Artwork(id: id, savedAt: Date()), at: 0)
                editingArtworkID = id
            } else if let index = gallery.firstIndex(where: { $0.id == id }) {
                gallery[index].savedAt = Date()
            }

            if storage.isUsingCloud {
                cloudStatus = .synced(Date())
                showToast(isNew ? "已保存并同步到 iCloud" : "已更新并同步")
            } else {
                showToast(isNew ? "已保存到画廊" : "画作已更新")
            }
        } catch {
            showToast("保存失败，请重试")
        }
    }

    func loadGallery() {
        gallery = storage.listDrawings()
            .map { Artwork(id: $0.id, savedAt: $0.savedAt) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    func openArtwork(_ artwork: Artwork) {
        let url = storage.drawingURL(for: artwork.id)

        Task { @MainActor in
            // iCloud 文件可能还没下载到本地，先确保就绪
            let ready = await storage.ensureDownloaded(url)

            guard ready, let data = storage.read(at: url),
                  let saved = try? PKDrawing(data: data) else {
                showToast(storage.isUsingCloud ? "画作下载失败，请检查网络" : "无法打开画作")
                return
            }
            load(saved, artworkID: artwork.id)
        }
    }

    func deleteArtwork(_ artwork: Artwork) {
        storage.remove(storage.drawingURL(for: artwork.id))
        storage.remove(storage.thumbnailURL(for: artwork.id))
        gallery.removeAll { $0.id == artwork.id }
        if editingArtworkID == artwork.id {
            editingArtworkID = nil
        }
        if storage.isUsingCloud {
            cloudStatus = .synced(Date())
        }
    }

    func thumbnail(for artwork: Artwork) -> UIImage? {
        let url = storage.thumbnailURL(for: artwork.id)

        // iCloud 缩略图未下载时，尝试从已下载的 drawing 现场渲染一张
        if let image = UIImage(contentsOfFile: url.path) {
            return image
        }

        guard storage.isUsingCloud,
              let data = storage.read(at: storage.drawingURL(for: artwork.id)),
              let drawing = try? PKDrawing(data: data) else {
            return nil
        }

        let scale: CGFloat = 1
        guard let image = Self.renderThumbnail(from: drawing, scale: scale) else { return nil }
        return image
    }

    /// 从 PKDrawing 渲染缩略图（背景 + 笔画）
    static func renderThumbnail(from drawing: PKDrawing, scale: CGFloat) -> UIImage? {
        let bounds = drawing.bounds
        guard !bounds.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            drawing.image(from: bounds, scale: scale).draw(in: CGRect(origin: .zero, size: bounds.size))
        }
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
