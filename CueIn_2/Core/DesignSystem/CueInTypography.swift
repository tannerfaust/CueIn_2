import SwiftUI

// MARK: - CueIn Typography System
/// Tight, readable type scale using system font.

enum CueInTypography {

    /// 28pt bold — key screen headers
    static let largeTitle = Font.system(size: 28, weight: .bold, design: .default)

    /// 22pt semibold — section headers
    static let title = Font.system(size: 22, weight: .semibold, design: .default)

    /// 17pt semibold — card titles / emphasis
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)

    /// 15pt regular — default reading text
    static let body = Font.system(size: 15, weight: .regular, design: .default)

    /// 15pt medium — body emphasis
    static let bodyMedium = Font.system(size: 15, weight: .medium, design: .default)

    /// 13pt regular — metadata, labels, timestamps
    static let caption = Font.system(size: 13, weight: .regular, design: .default)

    /// 13pt medium — emphasized captions
    static let captionMedium = Font.system(size: 13, weight: .medium, design: .default)

    /// 11pt medium — micro labels, chip text
    static let micro = Font.system(size: 11, weight: .medium, design: .default)

    /// 10pt regular — tab bar labels
    static let tabLabel = Font.system(size: 10, weight: .medium, design: .default)
}
