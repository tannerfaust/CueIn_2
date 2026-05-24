import SwiftUI

// MARK: - LinearIntegrationSettingsSection

/// Connect, sync, and status for Linear — shared by Hub settings and Tasks module settings.
struct LinearIntegrationSettingsSection: View {
    @Bindable private var authStore = SupabaseAuthStore.shared
    @Bindable private var linearStore = LinearIntegrationStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            statusPanel

            HStack(spacing: CueInSpacing.sm) {
                switch linearStore.state {
                case .connected:
                    connectedActions
                    linearButton(title: "Disconnect", icon: "xmark.circle", isPrimary: false) {
                        Task { await linearStore.disconnect() }
                    }
                case .working:
                    linearButton(title: "Working...", icon: "hourglass", isPrimary: true, disabled: true) {}
                default:
                    linearButton(
                        title: "Connect Linear",
                        icon: "square.and.arrow.up.on.square",
                        isPrimary: true,
                        disabled: !authStore.isSignedIn
                    ) {
                        Task { await linearStore.connect() }
                    }
                }
            }

            if let result = linearStore.lastSyncResult {
                Text(syncSummary(result))
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("CueIn uses Linear OAuth to sync issues and projects from your workspace. Tokens stay secure on the backend.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            await linearStore.refreshStatus()
        }
    }

    private var connectedActions: some View {
        VStack(spacing: CueInSpacing.xs) {
            linearButton(title: "Sync both", icon: "arrow.triangle.2.circlepath", isPrimary: true) {
                Task { await linearStore.syncNow(action: .full) }
            }

            HStack(spacing: CueInSpacing.xs) {
                linearButton(title: "Pull", icon: "arrow.down.to.line", isPrimary: false) {
                    Task { await linearStore.syncNow(action: .pull) }
                }
                linearButton(title: "Push", icon: "arrow.up.to.line", isPrimary: false) {
                    Task { await linearStore.syncNow(action: .push) }
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
                Text("Linear")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text(statusText)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            if case let .failed(message) = linearStore.state {
                copyButton(message: message)
            }
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.surfaceSecondary.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusIcon: String {
        switch linearStore.state {
        case .connected: return "checkmark.circle.fill"
        case .working: return "arrow.triangle.2.circlepath.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .disconnected: return "app.fill"
        }
    }

    private var statusColor: Color {
        switch linearStore.state {
        case .connected: return CueInColors.success
        case .working: return CueInColors.accentFocus
        case .failed: return CueInColors.danger
        case .disconnected: return CueInColors.textSecondary
        }
    }

    private var statusText: String {
        guard authStore.isSignedIn else {
            return "Sign in to CueIn Cloud before connecting Linear."
        }
        switch linearStore.state {
        case .disconnected:
            return "Not connected — connect to import projects and issues."
        case let .connected(connection):
            let name = connection.workspaceName ?? "Linear workspace"
            if let lastSyncedAt = connection.lastSyncedAt {
                return "\(name) connected. Last synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))."
            }
            return "\(name) connected."
        case let .working(message):
            return message
        case let .failed(message):
            return message
        }
    }

    private func syncSummary(_ result: LinearSyncResult) -> String {
        let pulled = (result.projectsPulled ?? 0) + (result.tasksPulled ?? 0)
        let pushed = (result.projectsPushed ?? 0) + (result.tasksPushed ?? 0)
        return "Last sync: \(pulled) pulled, \(pushed) pushed."
    }

    private func linearButton(
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
        .accessibilityLabel("Copy Linear error")
    }
}
