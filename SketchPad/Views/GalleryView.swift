import SwiftUI

/// 本地画廊：浏览 / 打开 / 删除已保存的画作
struct GalleryView: View {
    @EnvironmentObject private var store: DrawingStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 105, maximum: 160), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.gallery.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(store.gallery) { artwork in
                                ArtworkCell(
                                    artwork: artwork,
                                    onOpen: {
                                        store.openArtwork(artwork)
                                        dismiss()
                                    },
                                    onDelete: {
                                        store.deleteArtwork(artwork)
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("画廊")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                cloudStatusBar
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.startNewArtwork()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    // MARK: - iCloud 状态条

    private var cloudStatusBar: some View {
        Button {
            store.refreshCloud()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.cloudStatus.symbolName)
                    .font(.caption)
                    .symbolEffect(.pulse, isActive: store.cloudStatus == .syncing)

                Text(store.cloudStatus.isCloudActive
                     ? "iCloud 同步 · \(store.cloudStatus.displayName)"
                     : "iCloud 未开启 · 画作仅保存在本机")
                    .font(.caption)

                Spacer()

                if store.cloudStatus.isCloudActive {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
            }
            .foregroundStyle(store.cloudStatus.isCloudActive ? Color.accentColor : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .adaptiveGlass(.regular, in: .rect(cornerRadius: 0))
        }
        .buttonStyle(.plain)
        .disabled(!store.cloudStatus.isCloudActive)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("还没有保存的画作")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("回到画布，点击右上角菜单即可把作品保存到这里")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 画作单元格

private struct ArtworkCell: View {
    let artwork: Artwork
    let onOpen: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var store: DrawingStore
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                        .aspectRatio(3 / 4, contentMode: .fit)

                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06))
                )
                .frame(maxWidth: .infinity)

                Text(artwork.savedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("删除画作", systemImage: "trash")
            }
        }
        .task {
            thumbnail = store.thumbnail(for: artwork)
        }
    }
}
