import SwiftUI

// MARK: - MeasureAddTrackerSheet

struct MeasureAddTrackerSheet: View {
    @Bindable private var store = MeasureStore.shared
    let onDismiss: () -> Void

    @State private var mode: Mode = .templates
    @State private var customTitle = ""
    @State private var customKind: MeasureKind = .count
    @State private var customScaleMax = 5

    private enum Mode: String, CaseIterable {
        case templates = "Templates"
        case custom = "Custom"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.md)

                ScrollView {
                    VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                        switch mode {
                        case .templates:
                            templateGrid
                        case .custom:
                            customForm
                        }
                    }
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
                    .padding(.vertical, CueInSpacing.lg)
                }
            }
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("New tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .foregroundStyle(CueInColors.accentFocus)
                }
            }
        }
    }

    private var templateGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: CueInSpacing.md),
                GridItem(.flexible(), spacing: CueInSpacing.md),
            ],
            spacing: CueInSpacing.md
        ) {
            ForEach(MeasureTemplate.catalog) { template in
                Button {
                    add(template: template)
                } label: {
                    CueInCard {
                        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                            Image(systemName: template.iconSystemName)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(CueInColors.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                            Text(template.title)
                                .font(CueInTypography.bodyMedium)
                                .foregroundStyle(CueInColors.textPrimary)
                                .multilineTextAlignment(.leading)

                            Text(template.kind.pickerLabel)
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customForm: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text("Name it, pick how you log, and you can refine links later.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)

            TextField("Title", text: $customTitle)
                .textFieldStyle(.plain)
                .padding(CueInSpacing.md)
                .background(CueInColors.surfaceSecondary.opacity(0.6), in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

            VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                Text("Log type")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                Picker("Kind", selection: $customKind) {
                    ForEach(MeasureKind.allCases) { k in
                        Text(k.pickerLabel).tag(k)
                    }
                }
                .pickerStyle(.menu)
            }

            if customKind == .scale {
                Stepper("Top of scale: \(customScaleMax)", value: $customScaleMax, in: 3...10)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
            }

            Button {
                addCustom()
            } label: {
                Text("Create tracker")
                    .font(CueInTypography.bodyMedium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CueInColors.accentFocus)
            .disabled(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func add(template: MeasureTemplate) {
        let def = MeasureDefinition(
            title: template.title,
            iconSystemName: template.iconSystemName,
            kind: template.kind,
            scaleMin: template.scaleMin,
            scaleMax: template.kind == .scale ? template.scaleMax : 5,
            dailyTarget: template.dailyTarget
        )
        store.addDefinition(def)
        onDismiss()
    }

    private func addCustom() {
        let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let maxScale = customKind == .scale ? customScaleMax : 5
        let def = MeasureDefinition(
            title: title,
            iconSystemName: iconForCustom(kind: customKind),
            kind: customKind,
            scaleMin: 1,
            scaleMax: maxScale,
            dailyTarget: customKind == .count ? nil : nil
        )
        store.addDefinition(def)
        onDismiss()
    }

    private func iconForCustom(kind: MeasureKind) -> String {
        switch kind {
        case .count: return "number"
        case .scale: return "slider.horizontal.3"
        case .flag: return "checkmark.circle"
        case .duration: return "clock"
        }
    }
}
