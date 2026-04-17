import AppKit
import CoreGraphics
import Foundation
import QuartzCore

public enum VisualCursorSupport {
    public static var isEnabled: Bool {
        visualCursorEnabled(environment: ProcessInfo.processInfo.environment)
    }

    static func performOnMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                body()
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                body()
            }
        }
    }
}

func visualCursorEnabled(environment: [String: String]) -> Bool {
    guard let rawValue = environment["OPEN_COMPUTER_USE_VISUAL_CURSOR"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        return true
    }

    return !["0", "false", "no", "off"].contains(rawValue)
}

struct CursorTargetWindow: Equatable, Sendable {
    let windowID: CGWindowID
    let layer: Int
}

struct CursorWindowGeometry {
    let windowSize: CGSize
    let tipAnchor: CGPoint

    func origin(forTipPosition tipPosition: CGPoint) -> CGPoint {
        CGPoint(
            x: tipPosition.x - tipAnchor.x,
            y: tipPosition.y - tipAnchor.y
        )
    }

    func tipPosition(forOrigin origin: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + tipAnchor.x,
            y: origin.y + tipAnchor.y
        )
    }
}

struct CursorMotionPath {
    let start: CGPoint
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint

    init(start: CGPoint, end: CGPoint) {
        let delta = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let distance = max(hypot(delta.dx, delta.dy), 1)
        let normal = normalized(CGVector(dx: -delta.dy, dy: delta.dx))
        let curveDirection: CGFloat = delta.dx >= 0 ? 1 : -1
        let curveAmount = min(max(distance * 0.22, 28), 110)
        let controlOffset = CGPoint(x: normal.dx * curveAmount * curveDirection, y: normal.dy * curveAmount * curveDirection)

        self.start = start
        self.end = end
        self.control1 = CGPoint(
            x: start.x + (delta.dx * 0.18) + controlOffset.x,
            y: start.y + (delta.dy * 0.10) + controlOffset.y
        )
        self.control2 = CGPoint(
            x: start.x + (delta.dx * 0.80) + (controlOffset.x * 0.48),
            y: start.y + (delta.dy * 0.96) + (controlOffset.y * 0.48)
        )
    }

    func point(at t: CGFloat) -> CGPoint {
        let omt = 1 - t
        let omt2 = omt * omt
        let t2 = t * t

        return CGPoint(
            x: (omt2 * omt * start.x)
                + (3 * omt2 * t * control1.x)
                + (3 * omt * t2 * control2.x)
                + (t2 * t * end.x),
            y: (omt2 * omt * start.y)
                + (3 * omt2 * t * control1.y)
                + (3 * omt * t2 * control2.y)
                + (t2 * t * end.y)
        )
    }

    func tangent(at t: CGFloat) -> CGVector {
        let omt = 1 - t
        return CGVector(
            dx: (3 * omt * omt * (control1.x - start.x))
                + (6 * omt * t * (control2.x - control1.x))
                + (3 * t * t * (end.x - control2.x)),
            dy: (3 * omt * omt * (control1.y - start.y))
                + (6 * omt * t * (control2.y - control1.y))
                + (3 * t * t * (end.y - control2.y))
        )
    }
}

private struct ProcessedCursorImage {
    let image: NSImage
    let tipAnchor: CGPoint
}

private struct CursorArtwork {
    let image: NSImage?
    let geometry: CursorWindowGeometry
    let drawRect: CGRect
    let shadowBlur: CGFloat
    let shadowOffset: CGSize
    let shadowColor: NSColor
    let vectorScale: CGFloat

    static let active: CursorArtwork = loadOfficialSoftwareCursor() ?? fallback

    private static let fallback = CursorArtwork(
        image: nil,
        geometry: CursorWindowGeometry(
            windowSize: CGSize(width: 56, height: 56),
            tipAnchor: CGPoint(x: 10, y: 43)
        ),
        drawRect: CGRect(x: 0, y: 0, width: 56, height: 56),
        shadowBlur: 12,
        shadowOffset: CGSize(width: 0, height: -2),
        shadowColor: NSColor.black.withAlphaComponent(0.24),
        vectorScale: 0.40
    )

    private static func loadOfficialSoftwareCursor() -> CursorArtwork? {
        for bundle in officialCursorBundles() {
            guard let image = bundle.image(forResource: NSImage.Name("SoftwareCursor")),
                  let processed = processOfficialCursor(image)
            else {
                continue
            }

            let targetHeight: CGFloat = 26
            let scale = targetHeight / processed.image.size.height
            let imageSize = CGSize(
                width: processed.image.size.width * scale,
                height: processed.image.size.height * scale
            )
            let margin = NSEdgeInsets(top: 4, left: 3, bottom: 7, right: 5)
            let tipAnchor = CGPoint(
                x: margin.left + (processed.tipAnchor.x * scale),
                y: margin.bottom + (processed.tipAnchor.y * scale)
            )

            return CursorArtwork(
                image: processed.image,
                geometry: CursorWindowGeometry(
                    windowSize: CGSize(
                        width: imageSize.width + margin.left + margin.right,
                        height: imageSize.height + margin.top + margin.bottom
                    ),
                    tipAnchor: tipAnchor
                ),
                drawRect: CGRect(x: margin.left, y: margin.bottom, width: imageSize.width, height: imageSize.height),
                shadowBlur: 17,
                shadowOffset: CGSize(width: 0, height: -3),
                shadowColor: NSColor.black.withAlphaComponent(0.26),
                vectorScale: 0
            )
        }

        return nil
    }

    private static func officialCursorBundles() -> [Bundle] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/plugins/cache/openai-bundled/computer-use", isDirectory: true)

        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sortedVersions = versions.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }

        let bundlePaths = sortedVersions.flatMap { versionURL in
            [
                versionURL.appendingPathComponent("Codex Computer Use.app/Contents/Resources/Package_ComputerUse.bundle", isDirectory: true),
                versionURL.appendingPathComponent("Codex Computer Use.app/Contents/Resources/Package_SlimCore.bundle", isDirectory: true),
            ]
        }

        return bundlePaths.compactMap { Bundle(path: $0.path) }
    }

    private static func processOfficialCursor(_ image: NSImage) -> ProcessedCursorImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else {
            return nil
        }

        let highlightThreshold: CGFloat = 0.83
        let tint = NSColor(calibratedWhite: 0.92, alpha: 1).usingColorSpace(.deviceRGB) ?? NSColor.white
        let tintRed = UInt8(tint.redComponent * 255)
        let tintGreen = UInt8(tint.greenComponent * 255)
        let tintBlue = UInt8(tint.blueComponent * 255)

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var tipPixel = CGPoint.zero
        var tipScore = -CGFloat.greatestFiniteMagnitude

        for y in 0..<height {
            for x in 0..<width {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let alpha = color.alphaComponent
                let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
                guard alpha > 0.08, brightness > highlightThreshold else {
                    continue
                }

                minX = Swift.min(minX, x)
                maxX = Swift.max(maxX, x)
                minY = Swift.min(minY, y)
                maxY = Swift.max(maxY, y)

                let score = (CGFloat(y) * 3) - CGFloat(x)
                if score > tipScore {
                    tipScore = score
                    tipPixel = CGPoint(x: x, y: y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        let padding = 3
        minX = Swift.max(0, minX - padding)
        minY = Swift.max(0, minY - padding)
        maxX = Swift.min(width - 1, maxX + padding)
        maxY = Swift.min(height - 1, maxY + padding)

        let croppedWidth = maxX - minX + 1
        let croppedHeight = maxY - minY + 1

        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: croppedWidth,
            pixelsHigh: croppedHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let bitmapData = output.bitmapData else {
            return nil
        }

        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let alpha = color.alphaComponent
                let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
                let whiteness = CGFloat.clamped((brightness - highlightThreshold) / (1 - highlightThreshold), lower: 0, upper: 1)
                let resultAlpha = UInt8((alpha * whiteness) * 255)

                let localX = x - minX
                let localY = y - minY
                let offset = (localY * output.bytesPerRow) + (localX * 4)
                bitmapData[offset] = tintRed
                bitmapData[offset + 1] = tintGreen
                bitmapData[offset + 2] = tintBlue
                bitmapData[offset + 3] = resultAlpha
            }
        }

        let processed = NSImage(size: CGSize(width: croppedWidth, height: croppedHeight))
        processed.addRepresentation(output)

        return ProcessedCursorImage(
            image: processed,
            tipAnchor: CGPoint(
                x: tipPixel.x - CGFloat(minX),
                y: tipPixel.y - CGFloat(minY)
            )
        )
    }
}

@MainActor
enum SoftwareCursorOverlay {
    private static let artwork = CursorArtwork.active
    private static let baseHeading = 3 * CGFloat.pi / 4
    private static var panel: CursorPanel?
    private static var cursorView: SoftwareCursorView?
    private static var restingTipPosition: CGPoint?
    private static var displayedTipPosition: CGPoint?
    private static var activeTargetWindow: CursorTargetWindow?
    private static var idleTimer: Timer?
    private static var hideTimer: Timer?
    private static var idlePhase: CGFloat = 0

    static func moveCursor(to targetPoint: CGPoint, in targetWindow: CursorTargetWindow?) {
        guard VisualCursorSupport.isEnabled, canPresentOverlay else {
            return
        }

        prepareWindowIfNeeded()
        stopIdleAnimation()
        cancelPendingHide()
        configureOrdering(relativeTo: targetWindow)

        let constrainedTarget = clampTipPosition(targetPoint)
        let startPoint = displayedTipPosition ?? defaultAppearancePoint(for: constrainedTarget)

        panel?.alphaValue = 1
        placeCursor(at: startPoint, rotation: 0, clickProgress: 0)

        if distanceBetween(startPoint, constrainedTarget) > 2 {
            animateMove(from: startPoint, to: constrainedTarget)
        }
    }

    static func pulseClick(at targetPoint: CGPoint, clickCount: Int, mouseButton: MouseButtonKind, in targetWindow: CursorTargetWindow?) {
        guard VisualCursorSupport.isEnabled, canPresentOverlay else {
            return
        }

        configureOrdering(relativeTo: targetWindow)
        let constrainedTarget = clampTipPosition(targetPoint)
        animateClickPulse(at: constrainedTarget, clickCount: max(clickCount, 1), mouseButton: mouseButton)
        restingTipPosition = constrainedTarget
        displayedTipPosition = constrainedTarget
        startIdleAnimation()
        scheduleHide(after: 0.55)
    }

    static func settle(at targetPoint: CGPoint, in targetWindow: CursorTargetWindow?) {
        guard VisualCursorSupport.isEnabled, canPresentOverlay else {
            return
        }

        configureOrdering(relativeTo: targetWindow)
        let constrainedTarget = clampTipPosition(targetPoint)
        restingTipPosition = constrainedTarget
        displayedTipPosition = constrainedTarget
        placeCursor(at: constrainedTarget, rotation: 0, clickProgress: 0)
        startIdleAnimation()
        scheduleHide(after: 0.45)
    }

    static func reset() {
        stopIdleAnimation()
        cancelPendingHide()
        displayedTipPosition = nil
        restingTipPosition = nil
        activeTargetWindow = nil
        panel?.orderOut(nil)
    }

    private static var canPresentOverlay: Bool {
        !NSScreen.screens.isEmpty
    }

    private static func prepareWindowIfNeeded() {
        guard panel == nil else {
            return
        }

        let panel = CursorPanel(
            contentRect: CGRect(origin: .zero, size: artwork.geometry.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .normal
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none

        let view = SoftwareCursorView(frame: CGRect(origin: .zero, size: artwork.geometry.windowSize), artwork: artwork)
        panel.contentView = view

        self.panel = panel
        self.cursorView = view
    }

    private static func configureOrdering(relativeTo targetWindow: CursorTargetWindow?) {
        guard let panel else {
            return
        }

        let desiredLevel = NSWindow.Level(rawValue: targetWindow?.layer ?? 0)
        if panel.level != desiredLevel {
            panel.level = desiredLevel
        }

        if activeTargetWindow != targetWindow || panel.isVisible == false {
            if let targetWindow {
                panel.order(.above, relativeTo: Int(targetWindow.windowID))
            } else {
                panel.orderFront(nil)
            }
            activeTargetWindow = targetWindow
        }
    }

    private static func animateMove(from start: CGPoint, to end: CGPoint) {
        let path = CursorMotionPath(start: start, end: end)
        let duration = min(max(TimeInterval(distanceBetween(start, end) / 1050), 0.24), 0.56)
        let startTime = CACurrentMediaTime()

        while true {
            let elapsed = CACurrentMediaTime() - startTime
            let rawProgress = min(max(elapsed / duration, 0), 1)
            let eased = easeInOut(rawProgress)
            let point = path.point(at: eased)
            let tangent = path.tangent(at: max(min(eased, 0.999), 0.001))
            let rotation = rotationOffset(for: tangent)

            placeCursor(at: point, rotation: rotation, clickProgress: 0)

            if rawProgress >= 1 {
                break
            }

            pumpFrame()
        }
    }

    private static func animateClickPulse(at point: CGPoint, clickCount: Int, mouseButton: MouseButtonKind) {
        let pulseBias: CGFloat = mouseButton == .right ? 0.82 : 1

        for pulse in 0..<clickCount {
            let duration = 0.16
            let startTime = CACurrentMediaTime()

            while true {
                let elapsed = CACurrentMediaTime() - startTime
                let rawProgress = min(max(elapsed / duration, 0), 1)
                let clickProgress = sin(rawProgress * .pi) * pulseBias

                placeCursor(at: point, rotation: 0, clickProgress: clickProgress)

                if rawProgress >= 1 {
                    break
                }

                pumpFrame()
            }

            if pulse < clickCount - 1 {
                pause(for: 0.05)
            }
        }

        placeCursor(at: point, rotation: 0, clickProgress: 0)
    }

    private static func startIdleAnimation() {
        guard canPresentOverlay, let restingTipPosition else {
            return
        }

        idlePhase = 0
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let cursorView, let panel else {
                    return
                }

                idlePhase += 0.05
                let offset = CGPoint(
                    x: sin(idlePhase) * 1.6,
                    y: cos(idlePhase * 0.47) * 0.7
                )
                let tipPosition = CGPoint(
                    x: restingTipPosition.x + offset.x,
                    y: restingTipPosition.y + offset.y
                )

                cursorView.rotation = sin(idlePhase * 0.8) * 0.02
                cursorView.clickProgress = 0
                cursorView.needsDisplay = true

                panel.setFrameOrigin(artwork.geometry.origin(forTipPosition: tipPosition))
                displayedTipPosition = tipPosition
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer

        placeCursor(at: restingTipPosition, rotation: 0, clickProgress: 0)
    }

    private static func stopIdleAnimation() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private static func scheduleHide(after delay: TimeInterval) {
        cancelPendingHide()
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                hideOverlay()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private static func cancelPendingHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private static func hideOverlay() {
        guard let panel else {
            return
        }

        stopIdleAnimation()
        cancelPendingHide()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.alphaValue = 1
                displayedTipPosition = nil
                restingTipPosition = nil
                activeTargetWindow = nil
            }
        }
    }

    private static func defaultAppearancePoint(for targetPoint: CGPoint) -> CGPoint {
        clampTipPosition(
            CGPoint(
                x: targetPoint.x + 72,
                y: targetPoint.y - 54
            )
        )
    }

    private static func placeCursor(at tipPosition: CGPoint, rotation: CGFloat, clickProgress: CGFloat) {
        guard let panel, let cursorView else {
            return
        }

        panel.setFrameOrigin(artwork.geometry.origin(forTipPosition: tipPosition))
        cursorView.rotation = rotation
        cursorView.clickProgress = clickProgress
        cursorView.needsDisplay = true
        displayedTipPosition = tipPosition
    }

    private static func clampTipPosition(_ tipPosition: CGPoint) -> CGPoint {
        guard let screen = screen(containing: tipPosition) ?? NSScreen.main ?? NSScreen.screens.first else {
            return tipPosition
        }

        let visibleFrame = screen.visibleFrame
        let minX = visibleFrame.minX + artwork.geometry.tipAnchor.x
        let maxX = visibleFrame.maxX - (artwork.geometry.windowSize.width - artwork.geometry.tipAnchor.x)
        let minY = visibleFrame.minY + artwork.geometry.tipAnchor.y
        let maxY = visibleFrame.maxY - (artwork.geometry.windowSize.height - artwork.geometry.tipAnchor.y)

        return CGPoint(
            x: tipPosition.x.clamped(to: minX...maxX),
            y: tipPosition.y.clamped(to: minY...maxY)
        )
    }

    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private static func rotationOffset(for tangent: CGVector) -> CGFloat {
        guard tangent.dx != 0 || tangent.dy != 0 else {
            return 0
        }

        let heading = atan2(tangent.dy, tangent.dx)
        let delta = normalize(angle: heading - baseHeading)
        return delta.clamped(to: -0.22...0.22)
    }

    private static func normalize(angle: CGFloat) -> CGFloat {
        var value = angle
        while value > .pi {
            value -= 2 * .pi
        }
        while value < -.pi {
            value += 2 * .pi
        }
        return value
    }

    private static func easeInOut(_ value: CGFloat) -> CGFloat {
        value < 0.5
            ? 4 * value * value * value
            : 1 - pow(-2 * value + 2, 3) / 2
    }

    private static func pumpFrame() {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(1 / 120))
    }

    private static func pause(for duration: TimeInterval) {
        let start = CACurrentMediaTime()
        while CACurrentMediaTime() - start < duration {
            pumpFrame()
        }
    }

    private static func distanceBetween(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(rhs.x - lhs.x, rhs.y - lhs.y)
    }
}

private final class CursorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SoftwareCursorView: NSView {
    private let artwork: CursorArtwork

    var rotation: CGFloat = 0
    var clickProgress: CGFloat = 0

    init(frame frameRect: NSRect, artwork: CursorArtwork) {
        self.artwork = artwork
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        let compression = clickProgress * 0.05
        let scaleX = 1 - compression
        let scaleY = 1 + (compression * 0.24)

        let anchor = artwork.geometry.tipAnchor
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.translateBy(x: anchor.x, y: anchor.y)
        context?.rotate(by: rotation)
        context?.scaleBy(x: scaleX, y: scaleY)
        context?.translateBy(x: -anchor.x, y: -anchor.y)

        let shadowOval = NSBezierPath(ovalIn: CGRect(x: anchor.x - 7, y: anchor.y - 49, width: 22, height: 7))
        NSGraphicsContext.saveGraphicsState()
        let ovalShadow = NSShadow()
        ovalShadow.shadowBlurRadius = 10 + (clickProgress * 2)
        ovalShadow.shadowOffset = CGSize(width: 0, height: -1)
        ovalShadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
        ovalShadow.set()
        NSColor.black.withAlphaComponent(0.09).setFill()
        shadowOval.fill()
        NSGraphicsContext.restoreGraphicsState()

        if let image = artwork.image {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = artwork.shadowBlur + (clickProgress * 4)
            shadow.shadowOffset = artwork.shadowOffset
            shadow.shadowColor = artwork.shadowColor
            shadow.set()
            image.draw(in: artwork.drawRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let shadowPath = cursorPath(anchor: anchor, scale: artwork.vectorScale, xOffset: 2, yOffset: -2)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = artwork.shadowBlur + (clickProgress * 5)
            shadow.shadowOffset = artwork.shadowOffset
            shadow.shadowColor = artwork.shadowColor
            shadow.set()
            NSColor.black.withAlphaComponent(0.22).setFill()
            shadowPath.fill()
            NSGraphicsContext.restoreGraphicsState()

            let path = cursorPath(anchor: anchor, scale: artwork.vectorScale, xOffset: 0, yOffset: 0)
            let gradient = NSGradient(colors: [
                NSColor(calibratedWhite: 0.97, alpha: 0.92),
                NSColor(calibratedWhite: 0.84, alpha: 0.90),
            ])!
            gradient.draw(in: path, angle: -78)

            NSColor(calibratedWhite: 1, alpha: 0.85).setStroke()
            path.lineWidth = 1.0
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
        }

        if clickProgress > 0.01 {
            let ringRadius = 4 + (clickProgress * 7)
            let ringRect = CGRect(
                x: anchor.x - ringRadius,
                y: anchor.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            let ring = NSBezierPath(ovalIn: ringRect)
            NSColor.white.withAlphaComponent(0.22 * (1 - clickProgress * 0.45)).setStroke()
            ring.lineWidth = 1.0
            ring.stroke()
        }

        context?.restoreGState()
    }

    private func cursorPath(anchor: CGPoint, scale: CGFloat, xOffset: CGFloat, yOffset: CGFloat) -> NSBezierPath {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: -79 * scale),
            CGPoint(x: 20 * scale, y: -60 * scale),
            CGPoint(x: 32 * scale, y: -91 * scale),
            CGPoint(x: 47 * scale, y: -84 * scale),
            CGPoint(x: 35 * scale, y: -55 * scale),
            CGPoint(x: 63 * scale, y: -50 * scale),
        ]

        let translated = points.map {
            CGPoint(
                x: anchor.x + $0.x + xOffset,
                y: anchor.y + $0.y + yOffset
            )
        }

        let path = NSBezierPath()
        path.move(to: translated[0])
        for point in translated.dropFirst() {
            path.line(to: point)
        }
        path.close()
        return path
    }
}

private func normalized(_ vector: CGVector) -> CGVector {
    let length = max(hypot(vector.dx, vector.dy), 0.001)
    return CGVector(dx: vector.dx / length, dy: vector.dy / length)
}

private extension CGFloat {
    static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }

    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
