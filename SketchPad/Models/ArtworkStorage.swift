import Foundation
import UIKit

/// iCloud 同步状态
enum CloudStatus: Equatable {
    case unknown            // 尚未检查
    case unavailable        // 未登录 iCloud 或未开启权限，降级为本地存储
    case available          // iCloud 可用，正在同步
    case syncing            // 正在同步
    case synced(Date?)      // 已同步

    var displayName: String {
        switch self {
        case .unknown: return "检查中…"
        case .unavailable: return "仅本地"
        case .available: return "iCloud 已连接"
        case .syncing: return "同步中…"
        case .synced: return "已同步"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown: return "icloud"
        case .unavailable: return "icloud.slash"
        case .available, .syncing, .synced: return "icloud.fill"
        }
    }

    var isCloudActive: Bool {
        switch self {
        case .available, .syncing, .synced: return true
        default: return false
        }
    }
}

/// 画作存储层：优先使用 iCloud 容器，不可用时自动降级为本地沙盒。
///
/// 目录结构（两种模式一致）：
/// ```
/// <root>/Artworks/<uuid>.drawing   ← PKDrawing 原始数据
/// <root>/Artworks/<uuid>.png       ← 缩略图
/// ```
///
/// - iCloud 模式：`<iCloud 容器>/Documents/Artworks/`
/// - 本地模式：`<App 沙盒>/Documents/Artworks/`
final class ArtworkStorage {

    // MARK: - 常量

    /// iCloud 容器标识符。需与项目 entitlements 中的
    /// `com.apple.developer.ubiquity-container-identifiers` 保持一致。
    static let containerIdentifier = "iCloud.com.sketchpad.ink"

    static let folderName = "Artworks"

    // MARK: - 状态

    /// 当前是否在用 iCloud 存储
    private(set) var isUsingCloud = false

    /// 解析后的根目录（iCloud 容器根 或 本地 Documents）
    private(set) var rootURL: URL

    /// 画作目录
    var artworksDir: URL {
        rootURL.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    // MARK: - 初始化

    init() {
        // 默认先指向本地，随后 checkCloudAvailability() 可能切换到 iCloud
        rootURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        ensureDirectory()
    }

    // MARK: - iCloud 可用性

    /// 检查 iCloud 是否可用。可用则把根目录切到 iCloud 容器，并迁移本地存量数据。
    /// - Returns: 是否成功启用 iCloud
    @discardableResult
    func checkCloudAvailability() -> Bool {
        let fm = FileManager.default

        // 未登录 iCloud 账号时，url(forUbiquityContainerIdentifier:) 返回 nil
        guard let containerURL = fm.url(forUbiquityContainerIdentifier: Self.containerIdentifier) else {
            isUsingCloud = false
            rootURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            ensureDirectory()
            return false
        }

        let cloudRoot = containerURL.appendingPathComponent("Documents", isDirectory: true)

        // iCloud 目录可能尚未创建，需要手动建
        if !fm.fileExists(atPath: cloudRoot.path) {
            do {
                try fm.createDirectory(at: cloudRoot, withIntermediateDirectories: true)
            } catch {
                // 创建失败说明权限或容器有问题，降级本地
                isUsingCloud = false
                rootURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                ensureDirectory()
                return false
            }
        }

        isUsingCloud = true
        rootURL = cloudRoot
        ensureDirectory()
        return true
    }

    /// 确保画作目录存在
    private func ensureDirectory() {
        let dir = artworksDir
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - 本地目录

    /// 本地沙盒的画作目录（用于迁移源）
    var localArtworksDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    // MARK: - 首次迁移

    /// 启用 iCloud 后，把本地已有的画作搬到 iCloud 目录（仅搬运 iCloud 中不存在的文件）。
    /// - Returns: 迁移的文件数量
    @discardableResult
    func migrateLocalArtworksToCloud() -> Int {
        guard isUsingCloud else { return 0 }

        let fm = FileManager.default
        let localDir = localArtworksDir
        guard localDir.path != artworksDir.path,
              fm.fileExists(atPath: localDir.path),
              let files = try? fm.contentsOfDirectory(at: localDir, includingPropertiesForKeys: nil)
        else { return 0 }

        var moved = 0
        for src in files {
            let dst = artworksDir.appendingPathComponent(src.lastPathComponent)
            // 已存在则跳过，避免覆盖云端较新的版本
            guard !fm.fileExists(atPath: dst.path) else { continue }
            do {
                try fm.copyItem(at: src, to: dst)
                try? fm.removeItem(at: src)
                moved += 1
            } catch {
                continue
            }
        }
        return moved
    }

    // MARK: - 文件路径

    func drawingURL(for id: UUID) -> URL {
        artworksDir.appendingPathComponent("\(id.uuidString).drawing")
    }

    func thumbnailURL(for id: UUID) -> URL {
        artworksDir.appendingPathComponent("\(id.uuidString).png")
    }

    // MARK: - iCloud 下载触发

    /// 若文件是 iCloud 占位符（尚未下载到本地），触发下载并等待。
    /// 非 iCloud 模式直接返回 true。
    func ensureDownloaded(_ url: URL) async -> Bool {
        guard isUsingCloud else { return true }

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }

        // 判断是否为未下载的占位符
        let keys: Set<URLResourceKey> = [
            .ubiquitousItemDownloadingStatusKey,
            .isUbiquitousItemKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return true }

        // 非 iCloud 项（本地已存在实体文件）
        if values.isUbiquitousItem != true { return true }

        if values.ubiquitousItemDownloadingStatus == .current {
            return true
        }

        // 触发下载并轮询等待
        try? fm.startDownloadingUbiquitousItem(at: url)

        for _ in 0..<40 {   // 最多等 20 秒
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let check = try? url.resourceValues(forKeys: keys) else { break }
            if check.ubiquitousItemDownloadingStatus == .current {
                return true
            }
        }
        return false
    }

    // MARK: - 读写

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func read(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 枚举

    /// 列出目录下所有 `.drawing` 文件及其修改时间
    func listDrawings() -> [(id: UUID, savedAt: Date)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: artworksDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        return files.compactMap { url -> (UUID, Date)? in
            guard url.pathExtension == "drawing" else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            return (id, date)
        }
    }
}
