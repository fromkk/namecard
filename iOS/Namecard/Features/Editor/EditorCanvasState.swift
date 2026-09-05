import Observation
import SwiftUI
import UIKit

/// One editable layer on the 296x128 card. Coordinates are in paper units.
struct EditorLayer: Identifiable, Equatable {
    let id: UUID
    var text: String?
    var image: UIImage?      // already desaturated to grayscale
    var center: CGPoint
    var width: CGFloat = 0   // image width in paper units
    var height: CGFloat = 0
    var fontSize: CGFloat = 0
    var rotationDegrees: CGFloat = 0

    static func text(_ value: String, at center: CGPoint) -> EditorLayer {
        EditorLayer(id: UUID(), text: value, image: nil, center: center, fontSize: 24)
    }

    static func image(_ image: UIImage, at center: CGPoint, width: CGFloat, height: CGFloat) -> EditorLayer {
        EditorLayer(id: UUID(), text: nil, image: image, center: center, width: width, height: height)
    }

    static func == (lhs: EditorLayer, rhs: EditorLayer) -> Bool { lhs.id == rhs.id }
}

/// Holds the editable layers and renders them to the native 1-bit format.
/// Ported from the Android `EditorCanvasState`, adapted to SwiftUI/UIKit.
@MainActor
@Observable
final class EditorCanvasState {
    static let paperWidth: CGFloat = 296
    static let paperHeight: CGFloat = 128
    private static let maxHistory = 50

    private(set) var layers: [EditorLayer] = []
    private(set) var selectedID: UUID?
    private(set) var previewImage: UIImage?
    var gridEnabled = false
    private(set) var canUndo = false
    private(set) var canRedo = false

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var transformSnapshot: Snapshot?

    var hasSelection: Bool { selectedID != nil }

    init() { render() }

    // MARK: - Adding / replacing

    func addText(_ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pushUndo()
        var layer = EditorLayer.text(text, at: center())
        layer.fontSize = 24
        layers.append(layer)
        selectedID = layer.id
        changed()
    }

    func addImage(_ image: UIImage) {
        let gray = image.grayscale() ?? image
        let fit = min(1, (Self.paperWidth * 0.55) / image.size.width, (Self.paperHeight * 0.70) / image.size.height)
        pushUndo()
        let layer = EditorLayer.image(
            gray, at: center(),
            width: image.size.width * fit, height: image.size.height * fit
        )
        layers.append(layer)
        selectedID = layer.id
        changed()
    }

    /// Replaces all layers with a single full-canvas image (editing a library card).
    func replaceWithImage(_ image: UIImage) {
        let gray = image.grayscale() ?? image
        pushUndo()
        layers = [EditorLayer.image(gray, at: center(), width: Self.paperWidth, height: Self.paperHeight)]
        selectedID = layers.first?.id
        changed()
    }

    // MARK: - Selection & ordering

    func selectLayer(at paperPoint: CGPoint) {
        for layer in layers.reversed() where hitTest(layer, paperPoint) {
            if selectedID != layer.id { selectedID = layer.id }
            return
        }
        if selectedID != nil { selectedID = nil }
    }

    func selectedLayer() -> EditorLayer? {
        guard let selectedID else { return nil }
        return layers.first { $0.id == selectedID }
    }

    func deleteSelection() {
        guard let index = selectedIndex() else { return }
        pushUndo()
        layers.remove(at: index)
        selectedID = layers.isEmpty ? nil : layers[min(index, layers.count - 1)].id
        changed()
    }

    func bringForward() {
        guard let index = selectedIndex(), index < layers.count - 1 else { return }
        pushUndo()
        layers.swapAt(index, index + 1)
        changed()
    }

    func sendBackward() {
        guard let index = selectedIndex(), index > 0 else { return }
        pushUndo()
        layers.swapAt(index, index - 1)
        changed()
    }

    func clearAll() {
        guard !layers.isEmpty else { return }
        pushUndo()
        layers.removeAll()
        selectedID = nil
        changed()
    }

    func toggleGrid() {
        gridEnabled.toggle()
        render()
    }

    // MARK: - Transforms (interactive gestures)

    /// Call once at gesture start to snapshot for a single undo step.
    func beginTransform() {
        transformSnapshot = snapshot()
    }

    func endTransform() {
        transformSnapshot = nil
    }

    func transformSelection(translation: CGSize, scale: CGFloat, rotation: Angle) {
        guard let index = selectedIndex() else { return }
        commitTransformSnapshotIfNeeded()
        var layer = layers[index]
        layer.center.x = (layer.center.x + translation.width).clamped(0, Self.paperWidth)
        layer.center.y = (layer.center.y + translation.height).clamped(0, Self.paperHeight)
        if abs(scale - 1) > 0.001 { apply(scale: scale, to: &layer) }
        let degrees = rotation.degrees
        if abs(degrees) > 0.01 { layer.rotationDegrees = normalize(layer.rotationDegrees + degrees) }
        layers[index] = layer
        changed()
    }

    // MARK: - Undo / redo

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        if undoStack.count > Self.maxHistory { undoStack.removeFirst() }
        restore(next)
    }

    // MARK: - Rendering

    /// Renders the layers to native 1-bit bytes for NFC transfer.
    func renderNativeImage() throws -> [UInt8] {
        let image = renderImage(showSelection: false)
        guard let cgImage = image.cgImage, let pixels = CanvasRenderer.pixels(from: cgImage) else {
            throw NativeImageFormatError.invalidPixelCount
        }
        return try NativeImageFormat.encode(pixels)
    }

    // MARK: - Private

    private func center() -> CGPoint { CGPoint(x: Self.paperWidth / 2, y: Self.paperHeight / 2) }

    private func selectedIndex() -> Int? {
        guard let selectedID else { return nil }
        return layers.firstIndex { $0.id == selectedID }
    }

    private func apply(scale: CGFloat, to layer: inout EditorLayer) {
        let factor = scale.clamped(0.5, 2)
        if layer.image != nil {
            let minFactor = 2 / max(layer.width, layer.height)
            let maxFactor = min(Self.paperWidth * 2 / layer.width, Self.paperHeight * 2 / layer.height)
            let applied = factor.clamped(minFactor, maxFactor)
            layer.width *= applied
            layer.height *= applied
        } else {
            layer.fontSize = (layer.fontSize * factor).clamped(6, 96)
        }
    }

    private func normalize(_ degrees: CGFloat) -> CGFloat {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private func hitTest(_ layer: EditorLayer, _ point: CGPoint) -> Bool {
        let radians = -layer.rotationDegrees * .pi / 180
        let dx = point.x - layer.center.x
        let dy = point.y - layer.center.y
        let localX = layer.center.x + dx * cos(radians) - dy * sin(radians)
        let localY = layer.center.y + dx * sin(radians) + dy * cos(radians)
        return bounds(of: layer).insetBy(dx: -5, dy: -5).contains(CGPoint(x: localX, y: localY))
    }

    private func bounds(of layer: EditorLayer) -> CGRect {
        if layer.image != nil {
            return CGRect(
                x: layer.center.x - layer.width / 2, y: layer.center.y - layer.height / 2,
                width: layer.width, height: layer.height
            )
        }
        let size = Self.measureText(layer.text ?? "", fontSize: layer.fontSize)
        return CGRect(
            x: layer.center.x - size.width / 2 - 2, y: layer.center.y - size.height / 2 - 2,
            width: size.width + 4, height: size.height + 4
        )
    }

    static func measureText(_ text: String, fontSize: CGFloat) -> CGSize {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        return (text as NSString).size(withAttributes: [.font: font])
    }

    /// Selection-aware bounds in paper coords, for the on-screen handle overlay.
    func selectionBounds() -> (rect: CGRect, rotation: CGFloat)? {
        guard let layer = selectedLayer() else { return nil }
        return (bounds(of: layer), layer.rotationDegrees)
    }

    private func renderImage(showSelection: Bool) -> UIImage {
        let size = CGSize(width: Self.paperWidth, height: Self.paperHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            if gridEnabled { drawGrid(cg) }
            for layer in layers {
                cg.saveGState()
                cg.translateBy(x: layer.center.x, y: layer.center.y)
                cg.rotate(by: layer.rotationDegrees * .pi / 180)
                cg.translateBy(x: -layer.center.x, y: -layer.center.y)
                draw(layer, in: cg)
                cg.restoreGState()
            }
        }
    }

    private func draw(_ layer: EditorLayer, in cg: CGContext) {
        if let image = layer.image, let cgImage = image.cgImage {
            let rect = CGRect(
                x: layer.center.x - layer.width / 2, y: layer.center.y - layer.height / 2,
                width: layer.width, height: layer.height
            )
            UIGraphicsPushContext(cg)
            image.draw(in: rect)
            UIGraphicsPopContext()
            _ = cgImage
            return
        }
        guard let text = layer.text else { return }
        let font = UIFont.systemFont(ofSize: layer.fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: layer.center.x - size.width / 2, y: layer.center.y - size.height / 2)
        UIGraphicsPushContext(cg)
        (text as NSString).draw(at: origin, withAttributes: attributes)
        UIGraphicsPopContext()
    }

    private func drawGrid(_ cg: CGContext) {
        cg.setStrokeColor(UIColor(white: 0.6, alpha: 0.6).cgColor)
        cg.setLineWidth(0.3)
        var x: CGFloat = 8
        while x < Self.paperWidth { cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x, y: Self.paperHeight)); x += 8 }
        var y: CGFloat = 8
        while y < Self.paperHeight { cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: Self.paperWidth, y: y)); y += 8 }
        cg.strokePath()
    }

    private func changed() {
        render()
    }

    private func render() {
        previewImage = renderImage(showSelection: false)
    }

    // MARK: - History helpers

    private struct Snapshot { var layers: [EditorLayer]; var selectedID: UUID? }

    private func snapshot() -> Snapshot { Snapshot(layers: layers, selectedID: selectedID) }

    private func pushUndo() {
        undoStack.append(snapshot())
        if undoStack.count > Self.maxHistory { undoStack.removeFirst() }
        redoStack.removeAll()
        updateHistoryFlags()
    }

    private func commitTransformSnapshotIfNeeded() {
        guard let snapshot = transformSnapshot else { return }
        transformSnapshot = nil
        undoStack.append(snapshot)
        if undoStack.count > Self.maxHistory { undoStack.removeFirst() }
        redoStack.removeAll()
        updateHistoryFlags()
    }

    private func restore(_ snapshot: Snapshot) {
        layers = snapshot.layers
        selectedID = snapshot.selectedID.flatMap { id in layers.contains { $0.id == id } ? id : nil }
        updateHistoryFlags()
        changed()
    }

    private func updateHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}

private extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        let hi = Swift.max(lower, upper)
        return Swift.min(Swift.max(self, lower), hi)
    }
}

extension UIImage {
    /// Returns a desaturated copy, matching the editor's grayscale preview.
    func grayscale() -> UIImage? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let filter = CIFilter(name: "CIPhotoEffectMono")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        guard let output = filter?.outputImage else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}
