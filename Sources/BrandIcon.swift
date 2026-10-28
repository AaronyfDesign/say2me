import AppKit

/// say2me 品牌图形：圆角对话气泡 + 三条声波弧线。
/// 菜单栏使用模板图（黑色 + alpha），系统自动适配深浅色模式。
enum BrandIcon {

    enum State {
        case idle
        case recording
        case transcribing
    }

    /// 生成菜单栏图标（点尺寸 pointSize，含 @1x/@2x 表示）。
    static func menuIcon(for state: State, pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)

        func render(scale: CGFloat) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pointSize * scale),
                pixelsHigh: Int(pointSize * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )!
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            drawGlyph(in: NSRect(origin: .zero, size: size), state: state)
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }

        let img = NSImage(size: size)
        img.addRepresentation(render(scale: 1))
        img.addRepresentation(render(scale: 2))
        img.isTemplate = true
        return img
    }

    // MARK: - 绘制

    private static func drawGlyph(in rect: NSRect, state: State) {
        // 归一化到 18x18 设计网格
        let design: CGFloat = 18
        let s = rect.width / design

        // 气泡主体：圆角矩形 x[1..11.5] y[5.5..14.5]，左下小尾巴
        let bubbleRect = NSRect(x: 1 * s, y: 5.5 * s, width: 10.5 * s, height: 9 * s)
        let corner: CGFloat = 3.2 * s
        let bubble = NSBezierPath(roundedRect: bubbleRect,
                                  xRadius: corner, yRadius: corner)
        // 尾巴：从左下角伸出的三角形
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 2.6 * s, y: 5.5 * s))
        tail.line(to: NSPoint(x: 2.6 * s, y: 2.8 * s))
        tail.line(to: NSPoint(x: 5.8 * s, y: 5.5 * s))
        tail.close()

        let outline = NSBezierPath()
        outline.append(bubble)
        outline.append(tail)
        outline.lineJoinStyle = .round

        // 声波弧线：圆心在气泡右缘中点，向右辐射
        let center = NSPoint(x: 11.5 * s, y: 10 * s)
        let radii: [CGFloat] = [2.6, 4.6, 6.5]
        let lineWidth: CGFloat = 1.5 * s

        switch state {
        case .idle:
            // 描边气泡 + 实心弧线
            outline.lineWidth = 1.4 * s
            NSColor.black.setStroke()
            outline.stroke()
            drawArcs(center: center, radii: radii, lineWidth: lineWidth)
        case .recording:
            // 实心气泡 + 实心弧线
            NSColor.black.setFill()
            outline.fill()
            drawArcs(center: center, radii: radii, lineWidth: lineWidth)
        case .transcribing:
            // 实心气泡 + 气泡内三点（识别中），弧线收成短弧表示等待
            NSColor.black.setFill()
            outline.fill()
            // 挖出三个点（用白色/透明叠加：模板图中用 alpha 抠空）
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setBlendMode(.clear)
                let dotRadius: CGFloat = 0.85 * s
                let midY = bubbleRect.midY
                let xs: [CGFloat] = [4.0, 6.25, 8.5]
                for x in xs {
                    let dot = NSBezierPath(ovalIn: NSRect(x: x * s - dotRadius,
                                                          y: midY - dotRadius,
                                                          width: dotRadius * 2,
                                                          height: dotRadius * 2))
                    dot.fill()
                }
                ctx.setBlendMode(.normal)
            }
            drawArcs(center: center, radii: [2.6, 4.6], lineWidth: lineWidth)
        }
    }

    private static func drawArcs(center: NSPoint, radii: [CGFloat], lineWidth: CGFloat) {
        NSColor.black.setStroke()
        for r in radii {
            let path = NSBezierPath()
            // 以右缘中点为圆心，-38°..38° 的弧（0° 为正右方向）
            path.appendArc(withCenter: center,
                           radius: r,
                           startAngle: -38,
                           endAngle: 38,
                           clockwise: false)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.stroke()
        }
    }
}
