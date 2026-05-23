import Foundation
import OSLog

/// A thread-safe logger that outputs structured messages to Apple's Unified Logging System
/// and maintains a memory-only rolling list of "breadcrumbs" (recent user activities).
/// When an error is logged, the breadcrumbs are printed alongside the error context.
public final class AppLogger {
    /// The shared logger instance
    public static let shared = AppLogger()
    
    /// Categories representing different sub-systems or layers of the application
    public enum Category: String {
        case ui = "UI"
        case database = "Database"
        case network = "Network"
        case system = "System"
        case audio = "Audio"
        case error = "Error"
        
        /// Emojis to make logs instantly readable and scannable in the console
        public var emoji: String {
            switch self {
            case .ui: return "📱"
            case .database: return "💾"
            case .network: return "🌐"
            case .system: return "⚙️"
            case .audio: return "🔊"
            case .error: return "🚨"
            }
        }
    }
    
    /// A single logged event or user action representing a step in the application flow
    public struct Breadcrumb {
        public let timestamp: Date
        public let category: Category
        public let message: String
    }
    
    private let queue = DispatchQueue(label: "com.cuein.logger.queue", attributes: .concurrent)
    private var _breadcrumbs: [Breadcrumb] = []
    private let maxBreadcrumbs = 30
    
    private init() {}
    
    /// Retrieves the rolling log of recent user activities
    public var breadcrumbs: [Breadcrumb] {
        var result: [Breadcrumb] = []
        queue.sync {
            result = _breadcrumbs
        }
        return result
    }
    
    /// Logs a standard message or user activity and stores it in the breadcrumb trail.
    /// - Parameters:
    ///   - message: The message detailing what was done or happened.
    ///   - category: The subsystem category (default: `.system`).
    public func log(
        _ message: String,
        category: Category = .system,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let systemLogger = Logger(subsystem: "TannerFaust.CueIn-2", category: category.rawValue)
        let formattedMessage = "\(category.emoji) [\(category.rawValue)] \(message)"
        
        // Output to Apple's OSLog
        systemLogger.log("\(formattedMessage, privacy: .public)")
        
        // Store in the thread-safe breadcrumb history
        let breadcrumb = Breadcrumb(timestamp: Date(), category: category, message: message)
        queue.async(flags: .barrier) {
            self._breadcrumbs.append(breadcrumb)
            if self._breadcrumbs.count > self.maxBreadcrumbs {
                self._breadcrumbs.removeFirst()
            }
        }
    }
    
    /// Logs an error with location context and dumps the rolling list of recent user activities (breadcrumbs).
    /// - Parameters:
    ///   - error: The Error that was thrown.
    ///   - message: An optional custom message clarifying what action failed.
    public func error(
        _ error: Error,
        message: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let filename = (file as NSString).lastPathComponent
        let errorMessage = message ?? "An unexpected operation failed"
        
        let errorSystemLogger = Logger(subsystem: "TannerFaust.CueIn-2", category: Category.error.rawValue)
        
        // Retrieve and format the breadcrumb dump
        let currentBreadcrumbs = self.breadcrumbs
        var breadcrumbDump = "\n--- 🐾 RECENT USER ACTIVITY / BREADCRUMBS ---"
        if currentBreadcrumbs.isEmpty {
            breadcrumbDump += "\n  (No recent activity recorded)"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss.SSS"
            for (index, crumb) in currentBreadcrumbs.enumerated() {
                let countStr = String(format: "%02d", index + 1)
                breadcrumbDump += "\n  [\(countStr)] \(dateFormatter.string(from: crumb.timestamp)) \(crumb.category.emoji) \(crumb.message)"
            }
        }
        breadcrumbDump += "\n---------------------------------------------\n"
        
        let finalLogMessage = """
        
        🚨 ERROR OCCURRED: \(errorMessage)
        📍 Location: \(filename):\(line) in \(function)
        📝 Error Details: \(error.localizedDescription) (Error: \(error))
        \(breadcrumbDump)
        """
        
        // Write the error dump to console
        errorSystemLogger.error("\(finalLogMessage, privacy: .public)")
    }
}
