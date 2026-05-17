import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum CueInPasteboard {
    @MainActor
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = string
        #endif
    }
}
