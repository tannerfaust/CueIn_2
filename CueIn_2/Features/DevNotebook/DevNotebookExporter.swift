import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Format

enum DevNotebookExportFormat: String, CaseIterable {
    case markdown
    case csv

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .csv: return "csv"
        }
    }
}

// MARK: - DevNotebookExporter

enum DevNotebookExporter {

    /// Writes UTF-8 text to a unique file under the temp directory (suitable for share / Save to Files).
    static func writeTempFile(
        entries: [DevNotebookEntry],
        format: DevNotebookExportFormat,
        fileNameSlug: String,
        documentScopeTitle: String
    ) throws -> URL {
        let text: String
        switch format {
        case .markdown:
            text = markdown(entries: entries, scopeLabel: documentScopeTitle)
        case .csv:
            text = csv(entries: entries)
        }

        let stamp = fileNameDateFormatter.string(from: Date())
        let scopeSlug = fileNameSlug
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let base = "CueIn-dev-notebook-\(scopeSlug)-\(stamp)"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(base)
            .appendingPathExtension(format.fileExtension)

        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func markdown(entries: [DevNotebookEntry], scopeLabel: String) -> String {
        let headerDate = exportHeaderFormatter.string(from: Date())
        var lines: [String] = [
            "# CueIn dev notebook export",
            "",
            "- **Exported:** \(headerDate)",
            "- **Notes:** \(entries.count)",
            "- **Scope:** \(scopeLabel)",
            "",
            "---",
            "",
        ]

        for (index, entry) in entries.enumerated() {
            let created = exportHeaderFormatter.string(from: entry.createdAt)
            lines.append("## \(index + 1). \(entry.kind.title)")
            lines.append("")
            lines.append("- **Created:** \(created)")
            lines.append("- **Module:** \(entry.moduleLabel)")
            if let aiModel = entry.aiModel {
                lines.append("- **Delegate to:** \(aiModel.title)")
            }
            lines.append("- **Context:** \(entry.contextLine)")
            lines.append("")
            lines.append("### Body")
            lines.append("")
            lines.append(entry.body)
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    static func csv(entries: [DevNotebookEntry]) -> String {
        var rows: [String] = [
            [csvField("id"), csvField("createdAt"), csvField("kind"), csvField("aiModel"), csvField("module"), csvField("context"), csvField("body")]
                .joined(separator: ",")
        ]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        for entry in entries {
            let created = iso.string(from: entry.createdAt)
            let line = [
                csvField(entry.id.uuidString),
                csvField(created),
                csvField(entry.kind.title),
                csvField(entry.aiModel?.title ?? ""),
                csvField(entry.moduleLabel),
                csvField(entry.contextLine),
                csvField(entry.body),
            ].joined(separator: ",")
            rows.append(line)
        }
        return rows.joined(separator: "\n")
    }

    private static func csvField(_ raw: String) -> String {
        let escaped = raw.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static let exportHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    private static let fileNameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()
}

// MARK: - Share (AirDrop, Files, Mail, …)

#if os(iOS)
struct DevNotebookActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
struct DevNotebookActivityView: View {
    let activityItems: [Any]

    var body: some View {
        VStack(spacing: CueInSpacing.md) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(CueInColors.accentFocus)
            Text("Export ready")
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
            Text("Open the exported file from Finder or share it using macOS.")
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textSecondary)
                .multilineTextAlignment(.center)
            if let url = activityItems.compactMap({ $0 as? URL }).first {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(minWidth: 360, minHeight: 260)
        .background(CueInColors.background)
    }
}
#endif
