import Foundation

enum Constants {
    /// Minimum supported DPI for PDF rendering to avoid unusable raster output.
    static let minPDFRenderDPI = 72
    /// Maximum supported DPI to prevent excessive memory usage in rendering.
    static let maxPDFRenderDPI = 600
    /// Supported column count range for fixed column detection.
    static let minColumnCount = 1
    /// Supported column count range for fixed column detection.
    static let maxColumnCount = 3
    /// Default graceful timeout for signal handling cleanup.
    static let defaultGracefulTimeoutSeconds = 2.0
    /// Width of the terminal progress bar for status output.
    static let progressBarWidth = 30
}
