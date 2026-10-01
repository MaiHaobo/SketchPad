# 墨迹 SketchPad

一个用 **SwiftUI + PencilKit** 写的 iOS 绘画工具应用。iOS 原生风格界面，支持 Apple Pencil 压感。

## 功能

| 模块 | 说明 |
| --- | --- |
| **画笔** | 钢笔 / 铅笔 / 马克笔 / 橡皮擦，切换即时生效 |
| **颜色** | 20 色预设色板 + 系统取色器自定义颜色 |
| **笔刷粗细** | 5 档预设（3 / 6 / 10 / 16 / 24 pt） |
| **画纸** | 白纸 / 黑纸 / 米黄 / 方格 / 横线，显示与导出完全一致 |
| **撤销重做** | 对接系统 UndoManager，按钮实时反映可用状态 |
| **保存** | 存到本地画廊（可再次编辑）、存到系统相册 |
| **分享** | 导出 PNG 走系统分享面板 |
| **画廊** | 网格缩略图浏览，长按删除，点按继续编辑 |

## 运行方式

```bash
open SketchPad.xcodeproj
```

1. 用 Xcode 15 或更高版本打开 `SketchPad.xcodeproj`
2. 在 `TARGETS → SketchPad → Signing & Capabilities` 里选择你的开发者账号
   （模拟器运行可跳过；真机运行必须选，否则签名会失败）
3. 选择任意 iPhone 模拟器或真机，按 `⌘R` 运行

**环境要求**：Xcode 15+，iOS 16.0+，Swift 5

## 目录结构

```
SketchPad/
├── SketchPad.xcodeproj/          # Xcode 工程（含共享 scheme）
└── SketchPad/
    ├── SketchPadApp.swift        # App 入口
    ├── Info.plist                # 相册写入权限、横竖屏配置
    ├── Models/
    │   ├── BackgroundStyle.swift # 画纸样式与 pattern 绘制
    │   └── DrawingStore.swift    # 全局状态、导出、画廊持久化
    ├── Views/
    │   ├── CanvasView.swift      # PKCanvasView 的 SwiftUI 封装
    │   ├── DrawingScreen.swift   # 主界面（画布 + 顶栏 + 工具面板）
    │   ├── ToolPanel.swift       # 底部工具面板
    │   ├── GalleryView.swift     # 本地画廊
    │   └── Components.swift      # 颜色面板、分享面板、通用按钮
    └── Assets.xcassets/          # App 图标与强调色
```

## 实现要点

- **画布**：`PKCanvasView` 用 `UIViewRepresentable` 封装，`drawingPolicy = .anyInput` 让手指和 Pencil 都能画。画布单屏不滚动（`isScrollEnabled = false`），配合外层 `ignoresSafeArea` 实现全屏作画。
- **状态同步**：`DrawingStore` 是唯一的 `ObservableObject`。画布内容通过 delegate **单向**回写到 store（`updateDrawing` 不触发 `@Published`），避免绘画过程中高频刷新视图导致掉帧；工具/颜色/粗细变化才走 `@Published` 驱动画布更新。
- **撤销重做**：直接复用 `PKCanvasView.undoManager`，delegate 里刷新 `canUndo` / `canRedo`，且仅在值真正变化时赋值。
- **导出所见即所得**：`renderImage()` 用同一个 `UIGraphicsImageRenderer` 绘制背景 + 笔画，背景使用与屏幕显示相同的 `UIColor(patternImage:)`，因此方格/横线画纸导出后与屏幕一致（默认 2x，画廊缩略图用 1x）。
- **本地持久化**：`PKDrawing.dataRepresentation()` 存到 `Documents/Artworks/<uuid>.drawing`，同时导出 `<uuid>.png` 作缩略图；画廊按修改时间倒序排列。

## 可扩展方向

- 图层系统（多 `PKCanvasView` 叠加 + 混合模式）
- 画布缩放平移（把 `isScrollEnabled` 和 `zoomInteractionEnabled` 打开并加手势切换）
- iCloud 同步（把 `Documents/Artworks` 接入 `NSPersistentCloudKitContainer` 或 `ubiquityContainer`）
- 压感曲线自定义、导入图片作为底图描摹
- 导出 PDF / 视频回放笔迹过程

## 注意

该应用使用 CodeBuddy 生成，不一定能正确运行！