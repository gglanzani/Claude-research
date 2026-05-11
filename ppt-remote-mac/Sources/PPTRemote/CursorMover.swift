import CoreGraphics

final class CursorMover {
    func move(dx: Double, dy: Double) -> CGPoint {
        let current = CGEvent(source: nil)?.location ?? .zero
        let target = CGPoint(x: current.x + dx, y: current.y + dy)
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                               mouseCursorPosition: target, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
        return target
    }
}
