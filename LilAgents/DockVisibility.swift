import CoreGraphics

enum DockVisibility {
    static func screenHasVisibleDockReservedArea(
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> Bool {
        visibleFrame.minX > screenFrame.minX ||
        visibleFrame.minY > screenFrame.minY ||
        visibleFrame.maxX < screenFrame.maxX
    }

    /// Returns true when a full-screen app is occupying this screen
    /// (both the menu bar and dock reserved areas have collapsed).
    static func isFullScreenMode(
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> Bool {
        let menuBarHidden = visibleFrame.maxY >= screenFrame.maxY
        let dockHidden = visibleFrame.minY <= screenFrame.minY
        return menuBarHidden && dockHidden
    }

    static func shouldShowCharacters(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        isMainScreen: Bool,
        dockAutohideEnabled: Bool
    ) -> Bool {
        // Dock has a reserved area on this screen — always show
        if screenHasVisibleDockReservedArea(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        ) {
            return true
        }

        // Full-screen app: menu bar AND dock are both hidden.
        // visibleFrame == screenFrame in this case.
        // Still show characters so calendar alerts remain visible.
        let menuBarHidden = visibleFrame.maxY >= screenFrame.maxY
        let dockHidden = visibleFrame.minY <= screenFrame.minY
        if menuBarHidden && dockHidden {
            return true  // full-screen space — keep showing
        }

        // Dock auto-hidden (but not full-screen): show only on main screen
        let menuBarVisible = visibleFrame.maxY < screenFrame.maxY
        return dockAutohideEnabled && isMainScreen && menuBarVisible
    }
}
