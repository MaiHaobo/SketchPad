import SwiftUI

/// 主绘画界面：全屏画布 + 顶部浮动栏 + 底部工具面板
struct DrawingScreen: View {
    @EnvironmentObject private var store: DrawingStore

    @State private var showGallery = false
    @State private var showColorPicker = false
    @State private var showShare = false
    @State private var showClearConfirm = false
    @State private var shareURL: URL?

    var body: some View {
        ZStack {
            // 兜底背景（画布未布局 / 尺寸变化时不出黑底）
            Rectangle()
                .fill(Color(uiColor: store.background.patternColor))
                .ignoresSafeArea()

            CanvasView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                ToolPanel(
                    showColorPicker: $showColorPicker,
                    showClearConfirm: $showClearConfirm
                )
            }

            toastOverlay
        }
        .sheet(isPresented: $showGallery) {
            GalleryView()
        }
        .sheet(isPresented: $showColorPicker) {
            ColorSheet()
        }
        .sheet(isPresented: $showShare) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .confirmationDialog(
            "清空画布",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) { store.clearCanvas() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移除画布上的所有笔画，此操作不可恢复。")
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack(spacing: 10) {
            FloatingIconButton(systemImage: "photo.stack") {
                showGallery = true
            }

            Spacer()

            overflowMenu
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                store.saveToGallery()
            } label: {
                Label("保存到画廊", systemImage: "square.and.arrow.down.on.square")
            }
            Button {
                store.saveToPhotoLibrary()
            } label: {
                Label("保存到相册", systemImage: "square.and.arrow.down")
            }
            Button {
                shareArtwork()
            } label: {
                Label("分享 PNG", systemImage: "square.and.arrow.up")
            }

            Divider()

            Menu {
                ForEach(BackgroundStyle.allCases) { style in
                    Button {
                        store.background = style
                    } label: {
                        HStack {
                            Image(uiImage: style.swatchImage)
                            Text(style.displayName)
                            if store.background == style {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("画纸样式", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清空画布", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - 分享

    private func shareArtwork() {
        if let url = store.exportPNGURL() {
            shareURL = url
            showShare = true
        } else {
            store.showToast("画布还是空的")
        }
    }

    // MARK: - Toast

    private var toastOverlay: some View {
        VStack {
            if let toast = store.toast {
                Text(toast)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 60)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }
}
