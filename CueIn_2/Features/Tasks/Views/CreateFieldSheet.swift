import SwiftUI

// MARK: - CreateFieldSheet
/// Create or edit a `Field`. Simple flow: name, summary, icon, color.

struct CreateFieldSheet: View {

    enum Mode {
        case create
        case edit(UUID)
    }

    let mode: Mode
    var store: TasksStore
    var onDismiss: () -> Void

    @State private var name: String
    @State private var summary: String
    @State private var iconName: String
    @State private var colorHex: UInt
    @State private var showingDelete = false
    @FocusState private var nameFocused: Bool

    init(mode: Mode, store: TasksStore, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.store = store
        self.onDismiss = onDismiss
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _summary = State(initialValue: "")
            _iconName = State(initialValue: FieldPalette.icons.first ?? "folder.fill")
            _colorHex = State(initialValue: FieldPalette.colors.first ?? 0x34C759)
        case .edit(let id):
            let f = store.fields.first { $0.id == id }
            _name = State(initialValue: f?.name ?? "")
            _summary = State(initialValue: f?.summary ?? "")
            _iconName = State(initialValue: f?.iconName ?? FieldPalette.icons.first ?? "folder.fill")
            _colorHex = State(initialValue: f?.colorHex ?? FieldPalette.colors.first ?? 0x34C759)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CueInSpacing.lg) {
                    previewHeader
                    nameSection
                    iconSection
                    colorSection
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
                        .foregroundStyle(canSave
                                         ? CueInColors.accentFocus
                                         : CueInColors.textTertiary)
                        .disabled(!canSave)
                }
            }
            .alert("Delete initiative?", isPresented: $showingDelete) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) { deleteField() }
            } message: {
                Text("Projects inside will also be deleted. Tasks will remain, unassigned.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: UI blocks

    private var title: String {
        if case .create = mode { return "New Initiative" }
        return "Edit Initiative"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var previewColor: Color { Color(hex: colorHex) }

    private var previewHeader: some View {
        VStack(spacing: CueInSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(previewColor.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(previewColor)
            }
            Text(name.isEmpty ? "Initiative name" : name)
                .font(CueInTypography.title)
                .foregroundStyle(name.isEmpty ? CueInColors.textTertiary : CueInColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CueInSpacing.lg)
    }

    private var nameSection: some View {
        SheetSection("Name") {
            TextField("e.g. Health, Career, Home", text: $name)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.accentFocus)
                .focused($nameFocused)
                .padding(.horizontal, CueInSpacing.base)
                .padding(.vertical, 12)
            SheetRowDivider()
            TextField("A short description (optional)", text: $summary)
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
                ForEach(FieldPalette.icons, id: \.self) { icon in
                    iconTile(icon)
                }
            }
            .padding(CueInSpacing.md)
        }
    }

    @ViewBuilder
    private func iconTile(_ icon: String) -> some View {
        let selected = icon == iconName
        Button { iconName = icon } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? previewColor.opacity(0.18) : CueInColors.surfaceSecondary)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? previewColor : CueInColors.textSecondary)
            }
            .frame(height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? previewColor.opacity(0.4) : Color.clear,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var colorSection: some View {
        SheetSection("Color") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                spacing: 10
            ) {
                ForEach(FieldPalette.colors, id: \.self) { hex in
                    colorTile(hex)
                }
            }
            .padding(CueInSpacing.md)
        }
    }

    @ViewBuilder
    private func colorTile(_ hex: UInt) -> some View {
        let selected = hex == colorHex
        Button { colorHex = hex } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 34, height: 34)
                if selected {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                        .frame(width: 40, height: 40)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            showingDelete = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "trash")
                Text("Delete initiative")
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
        switch mode {
        case .create:
            store.addField(Field(
                name: name.trimmingCharacters(in: .whitespaces),
                summary: summary,
                iconName: iconName,
                colorHex: colorHex
            ))
        case .edit(let id):
            guard var existing = store.fields.first(where: { $0.id == id }) else { break }
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.summary = summary
            existing.iconName = iconName
            existing.colorHex = colorHex
            store.updateField(existing)
        }
        onDismiss()
    }

    private func deleteField() {
        if case .edit(let id) = mode { store.deleteField(id) }
        onDismiss()
    }
}
