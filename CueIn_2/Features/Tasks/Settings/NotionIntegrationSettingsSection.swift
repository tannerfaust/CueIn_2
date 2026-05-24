import SwiftUI

// MARK: - NotionIntegrationSettingsSection

/// Connect, sync, and status for Notion — shared by Hub settings and Tasks module settings.
struct NotionIntegrationSettingsSection: View {
    @Bindable private var authStore = SupabaseAuthStore.shared
    @Bindable private var notionStore = NotionIntegrationStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            statusPanel

            HStack(spacing: CueInSpacing.sm) {
                switch notionStore.state {
                case .connected:
                    connectedActions
                    notionButton(title: "Disconnect", icon: "xmark.circle", isPrimary: false) {
                        Task { await notionStore.disconnect() }
                    }
                case .working:
                    notionButton(title: "Working...", icon: "hourglass", isPrimary: true, disabled: true) {}
                default:
                    notionButton(
                        title: "Connect Notion",
                        icon: "square.and.arrow.up.on.square",
                        isPrimary: true,
                        disabled: !authStore.isSignedIn
                    ) {
                        Task { await notionStore.connect() }
                    }
                }
            }

            if let result = notionStore.lastSyncResult {
                Text(syncSummary(result))
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("CueIn uses Notion OAuth and creates CueIn-managed Projects and Tasks databases in a page you grant access to. Tokens stay on the backend.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            await notionStore.refreshStatus()
        }
    }

    private var connectedActions: some View {
        VStack(spacing: CueInSpacing.xs) {
            notionButton(title: "Sync both", icon: "arrow.triangle.2.circlepath", isPrimary: true) {
                Task { await notionStore.syncNow(action: .full) }
            }

            HStack(spacing: CueInSpacing.xs) {
                notionButton(title: "Pull", icon: "arrow.down.to.line", isPrimary: false) {
                    Task { await notionStore.syncNow(action: .pull) }
                }
                notionButton(title: "Push", icon: "arrow.up.to.line", isPrimary: false) {
                    Task { await notionStore.syncNow(action: .push) }
                }
            }
        }
    }

    private var statusPanel: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            Image(systemName: statusIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 42, height: 42)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Notion")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text(statusText)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            if case let .failed(message) = notionStore.state {
                copyButton(message: message)
            }
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.surfaceSecondary.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusIcon: String {
        switch notionStore.state {
        case .connected: return "checkmark.circle.fill"
        case .working: return "arrow.triangle.2.circlepath.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .disconnected: return "square.grid.2x2"
        }
    }

    private var statusColor: Color {
        switch notionStore.state {
        case .connected: return CueInColors.success
        case .working: return CueInColors.accentFocus
        case .failed: return CueInColors.danger
        case .disconnected: return CueInColors.textSecondary
        }
    }

    private var statusText: String {
        guard authStore.isSignedIn else {
            return "Sign in to CueIn Cloud before connecting Notion."
        }
        switch notionStore.state {
        case .disconnected:
            return "Not connected — connect to import projects and tasks."
        case let .connected(connection):
            let name = connection.workspaceName ?? "Notion workspace"
            let taskTarget = connection.externalTasksDatabaseTitle.map { " Tasks sync with \($0)." } ?? ""
            if let lastSyncedAt = connection.lastSyncedAt {
                return "\(name).\(taskTarget) Last synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))."
            }
            return "\(name) connected.\(taskTarget)"
        case let .working(message):
            return message
        case let .failed(message):
            return message
        }
    }

    private func syncSummary(_ result: NotionSyncResult) -> String {
        let pulled = (result.projectsPulled ?? 0) + (result.tasksPulled ?? 0)
        let pushed = (result.projectsPushed ?? 0) + (result.tasksPushed ?? 0)
        return "Last sync: \(pulled) pulled, \(pushed) pushed."
    }

    private func notionButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(CueInTypography.captionMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CueInSpacing.sm)
                .padding(.horizontal, CueInSpacing.sm)
                .background(disabled ? CueInColors.surfaceSecondary : (isPrimary ? CueInColors.accentFocus : CueInColors.surfaceSecondary))
                .foregroundStyle(disabled ? CueInColors.textTertiary : (isPrimary ? Color.white : CueInColors.textPrimary))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func copyButton(message: String) -> some View {
        Button {
            CueInPasteboard.copy(message)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(CueInColors.surfaceSecondary.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy Notion error")
    }
}
