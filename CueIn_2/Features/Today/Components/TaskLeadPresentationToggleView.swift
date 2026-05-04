import SwiftUI

// MARK: - TaskLeadPresentationToggleView

struct TaskLeadPresentationToggleView: View {
    let selectedPresentation: TaskLeadPresentation
    let onSelect: (TaskLeadPresentation) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TaskLeadPresentation.allCases) { presentation in
                Button {
                    onSelect(presentation)
                } label: {
                    Text(presentation.label)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(
                            selectedPresentation == presentation ? CueInColors.textPrimary : CueInColors.textSecondary
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(selectedPresentation == presentation ? CueInColors.surfaceSecondary : CueInColors.surfacePrimary)
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }
}

