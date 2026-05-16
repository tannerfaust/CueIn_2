import SwiftUI

// MARK: - CreateProjectSheet

struct CreateProjectSheet: View {

    enum Mode {
        case create(fieldID: UUID?)
        case edit(UUID)
    }

    let mode: Mode
    var store: TasksStore
    var onDismiss: () -> Void

    @State private var name: String
    @State private var summary: String
    @State private var iconName: String
    @State private var fieldID: UUID?
    @State private var status: Project.Status
    @State private var targetDate: Date?
    @State private var showingDelete = false
    @FocusState private var nameFocused: Bool

    init(mode: Mode, store: TasksStore, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.store = store
        self.onDismiss = onDismiss
        switch mode {
        case .create(let fid):
            _name = State(initialValue: "")
            _summary = State(initialValue: "")
            _iconName = State(initialValue: ProjectPalette.icons.first ?? "folder")
            _fieldID = State(initialValue: fid ?? store.fields.first?.id)
            _status = State(initialValue: .active)
            _targetDate = State(initialValue: nil)
        case .edit(let id):
            let p = store.projects.first { $0.id == id }
            _name = State(initialValue: p?.name ?? "")
            _summary = State(initialValue: p?.summary ?? "")
            _iconName = State(initialValue: p?.iconName ?? ProjectPalette.icons.first ?? "folder")
            _fieldID = State(initialValue: p?.fieldID)
            _status = State(initialValue: p?.status ?? .active)
            _targetDate = State(initialValue: p?.targetDate)
        }
    }

    private var resolvedField: Field? { store.field(fieldID) }
    private var accent: Color { resolvedField?.color ?? CueInColors.textTertiary }

    private var title: String {
        if case .create = mode { return "New Project" }
        return "Edit Project"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && fieldID != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CueInSpacing.lg) {
                    previewHeader
                    nameSection
                    iconSection
                    organizationSection
                    if case .edit = mode { deleteSection }
                }
                .padding(.top, CueInSpacing.base)
                .padding(.bottom, CueInSpacing.huge)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CueInColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(CueInColors.textSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? CueInColors.accentFocus : CueInColors.textTertiary)
                        .disabled(!canSave)
                }
            }
            .alert("Delete project?", isPresented: $showingDelete) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if case .edit(let id) = mode { store.deleteProject(id) }
                    onDismiss()
                }
            } message: {
                Text("Tasks will remain, unassigned.")
            }
        }
        .cueInPreferredColorScheme()
    }

    // MARK: Sections

    private var previewHeader: some View {
        VStack(spacing: CueInSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 60, height: 60)
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(name.isEmpty ? "Project name" : name)
                .font(CueInTypography.title)
                .foregroundStyle(name.isEmpty ? CueInColors.textTertiary : CueInColors.textPrimary)
            if let f = resolvedField {
                HStack(spacing: 5) {
                    Circle().fill(f.color).frame(width: 6, height: 6)
                    Text(f.name)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CueInSpacing.lg)
    }

    private var nameSection: some View {
        SheetSection("Name") {
            TextField("e.g. iOS App, Marathon Training", text: $name)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.accentFocus)
                .focused($nameFocused)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, 12)
            SheetRowDivider()
            TextField("Short description (optional)", text: $summary)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.accentFocus)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, 12)
        }
    }

    private var iconSection: some View {
        SheetSection("Icon") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                spacing: 10
            ) {
                ForEach(ProjectPalette.icons, id: \.self) { icon in
                    let selected = icon == iconName
                    Button { iconName = icon } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? accent.opacity(0.18) : CueInColors.surfaceSecondary)
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(selected ? accent : CueInColors.textSecondary)
                        }
                        .frame(height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? accent.opacity(0.4) : Color.clear,
                                              lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Project icon")
                    .accessibilityValue(icon)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(CueInSpacing.md)
        }
    }

    private var organizationSection: some View {
        SheetSection("Details") {
            PickerRow(icon: "square.grid.2x2.fill", label: "Initiative") {
                Menu {
                    ForEach(store.fields) { f in
                        Button {
                            fieldID = f.id
                        } label: { Label(f.name, systemImage: f.iconName) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let f = resolvedField {
                            Circle().fill(f.color).frame(width: 7, height: 7)
                            Text(f.name)
                        } else {
                            Text("Choose an initiative")
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textPrimary)
                }
            }
            SheetRowDivider()
            PickerRow(icon: status.icon, label: "Status", iconColor: status.tint) {
                Menu {
                    ForEach(Project.Status.allCases) { s in
                        Button { status = s } label: { Label(s.label, systemImage: s.icon) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(status.label)
                            .font(CueInTypography.body)
                            .foregroundStyle(CueInColors.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                }
            }
            SheetRowDivider()
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(width: 18)
                Text("Target date")
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer()
                if targetDate != nil {
                    Button {
                        withAnimation { targetDate = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                DatePicker("", selection: Binding(
                    get: { targetDate ?? Date() },
                    set: { targetDate = $0 }
                ), displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(accent)
                .opacity(targetDate == nil ? 0.4 : 1)
                .onTapGesture { if targetDate == nil { targetDate = Date() } }
            }
            .padding(.horizontal, CueInSpacing.base)
            .padding(.vertical, 10)
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            showingDelete = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "trash")
                Text("Delete project")
                    .fontWeight(.medium)
                Spacer()
            }
            .foregroundStyle(CueInColors.danger)
            .padding(.vertical, CueInSpacing.md)
            .background(CueInColors.danger.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func save() {
        guard let fid = fieldID else { return }
        switch mode {
        case .create:
            store.addProject(Project(
                name: name.trimmingCharacters(in: .whitespaces),
                summary: summary,
                iconName: iconName,
                fieldID: fid,
                status: status,
                targetDate: targetDate
            ))
        case .edit(let id):
            guard var existing = store.projects.first(where: { $0.id == id }) else { break }
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.summary = summary
            existing.iconName = iconName
            existing.fieldID = fid
            existing.status = status
            existing.targetDate = targetDate
            store.updateProject(existing)
        }
        onDismiss()
    }
}
