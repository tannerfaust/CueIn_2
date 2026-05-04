import SwiftUI

// MARK: - FieldGridCard
/// Square-ish card for the Fields grid. Icon, progress ring, name, project count.

struct FieldGridCard: View {

    let field: Field
    let store: TasksStore

    private var progress: Double {
        let p = store.progress(field: field)
        return p.total > 0 ? Double(p.done) / Double(p.total) : 0
    }

    private var stats: (done: Int, total: Int) { store.progress(field: field) }
    private var projectCount: Int { store.projects(in: field.id).count }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(field.color.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: field.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(field.color)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(CueInColors.surfaceTertiary, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(field.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
                .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(field.name)
                    .font(CueInTypography.headline)
                    .foregroundStyle(CueInColors.textPrimary)

                Text("\(stats.done) of \(stats.total) done")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
            }

            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(CueInColors.textTertiary)
                Text("\(projectCount) projects")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
            }
        }
        .padding(CueInSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CueInColors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                .strokeBorder(field.color.opacity(0.18), lineWidth: 0.5)
        )
    }
}
