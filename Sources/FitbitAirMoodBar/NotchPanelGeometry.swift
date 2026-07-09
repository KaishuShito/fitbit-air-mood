import AppKit

// Placement math shared by the notch-anchored panels (Quick Check-In, Tasks).
// The panel hugs the camera housing when one exists, otherwise it hangs from
// the top of the screen under the pointer.
@MainActor
enum NotchPanelGeometry {
    static let notchWingPadding: CGFloat = 220

    struct Placement {
        let frame: NSRect
        let topInset: CGFloat
        let width: CGFloat
    }

    static func placement(baseHeight: CGFloat, fallbackWidth: CGFloat) -> Placement {
        let screen = screenWithCameraHousing() ?? screenForCurrentPointer() ?? NSScreen.main
        let topInset = panelTopInset(on: screen)
        let width = panelWidth(on: screen, fallbackWidth: fallbackWidth)
        let size = NSSize(width: width, height: baseHeight + topInset)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let centerX = cameraHousingCenterX(on: screen) ?? visibleFrame.midX
        let topY = topInset > 0 ? (screen?.frame.maxY ?? visibleFrame.maxY) : visibleFrame.maxY
        let origin = NSPoint(
            x: clamped(centerX - (size.width / 2), min: visibleFrame.minX + 12, max: visibleFrame.maxX - size.width - 12),
            y: topY - size.height
        )
        return Placement(frame: NSRect(origin: origin, size: size), topInset: topInset, width: width)
    }

    private static func panelTopInset(on screen: NSScreen?) -> CGFloat {
        guard
            let screen,
            screen.safeAreaInsets.top > 0,
            cameraHousingCenterX(on: screen) != nil
        else {
            return 0
        }

        return screen.safeAreaInsets.top
    }

    private static func panelWidth(on screen: NSScreen?, fallbackWidth: CGFloat) -> CGFloat {
        guard
            let screen,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea,
            !left.isEmpty,
            !right.isEmpty,
            left.maxX < right.minX
        else {
            return fallbackWidth
        }

        return max(fallbackWidth, (right.minX - left.maxX) + notchWingPadding)
    }

    private static func screenWithCameraHousing() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard screen.safeAreaInsets.top > 0 else { return false }
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
                return false
            }
            return !left.isEmpty && !right.isEmpty && left.maxX < right.minX
        }
    }

    private static func cameraHousingCenterX(on screen: NSScreen?) -> CGFloat? {
        guard
            let screen,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea,
            !left.isEmpty,
            !right.isEmpty,
            left.maxX < right.minX
        else {
            return nil
        }

        return (left.maxX + right.minX) / 2
    }

    private static func screenForCurrentPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(location)
        }
    }

    private static func clamped(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}
