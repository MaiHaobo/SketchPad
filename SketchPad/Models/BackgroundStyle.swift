import UIKit

/// 画纸背景样式：纯色 / 米黄 / 方格 / 横线
enum BackgroundStyle: String, CaseIterable, Identifiable {
    case white
    case black
    case cream
    case grid
    case ruled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: return "白纸"
        case .black: return "黑纸"
        case .cream: return "米黄"
        case .grid: return "方格"
        case .ruled: return "横线"
        }
    }

    /// 底色（不含线条）
    var baseColor: UIColor {
        switch self {
        case .white, .grid, .ruled:
            return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        case .black:
            return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .cream:
            return UIColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1)
        }
    }

    /// 可直接填充 / 设为 backgroundColor 的图案色。
    /// 显示与导出使用同一来源，保证所见即所得。
    var patternColor: UIColor {
        switch self {
        case .white, .black, .cream:
            return baseColor
        case .grid:
            return UIColor(patternImage: BackgroundStyle.gridTile())
        case .ruled:
            return UIColor(patternImage: BackgroundStyle.ruledTile())
        }
    }

    /// 菜单里的小色块预览
    var swatchImage: UIImage {
        let size = CGSize(width: 26, height: 18)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            path.addClip()
            patternColor.setFill()
            ctx.fill(rect)
            UIColor.separator.setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4)
            border.stroke()
        }
    }

    // MARK: - Pattern tiles

    /// 20pt 方格：tile 右、下边缘画浅灰线
    private static func gridTile() -> UIImage {
        let size = CGSize(width: 20, height: 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let line = UIColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
            line.setStroke()
            let vertical = UIBezierPath()
            vertical.move(to: CGPoint(x: size.width - 0.5, y: 0))
            vertical.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
            vertical.stroke()
            let horizontal = UIBezierPath()
            horizontal.move(to: CGPoint(x: 0, y: size.height - 0.5))
            horizontal.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            horizontal.stroke()
        }
    }

    /// 28pt 行高横线：tile 底边画浅蓝线
    private static func ruledTile() -> UIImage {
        let size = CGSize(width: 4, height: 28)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.78, green: 0.86, blue: 0.98, alpha: 1).setStroke()
            let line = UIBezierPath()
            line.move(to: CGPoint(x: 0, y: size.height - 0.5))
            line.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            line.stroke()
        }
    }
}
