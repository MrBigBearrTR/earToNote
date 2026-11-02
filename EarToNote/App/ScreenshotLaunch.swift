import Foundation

/// Opens a specific screen when launched with `SCREENSHOT=<name>` from the simulator.
/// Used only to capture App Store screenshots; ignored in Release builds.
enum ScreenshotLaunch {
    static var screen: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["SCREENSHOT"]
        #else
        nil
        #endif
    }
}
