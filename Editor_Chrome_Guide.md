# Editor Chrome Guide

This app's editor top blur is the native iOS sheet/navigation-bar Liquid Glass blur. It is not a custom `LinearGradient`, not a masked `Rectangle`, and not a `safeAreaInset(edge: .top)` background.

Use this rule for task, block, and editor-style settings sheets:

```swift
NavigationStack {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        // Editor content here.
    }
    .navigationTitle("Task")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbar {
        CueInEditorToolbar(
            saveEnabled: canSave,
            onClose: onDismiss,
            onSave: save
        ) {
            CueInEditorPrincipalChip(
                icon: "folder.fill",
                title: "iOS App",
                tint: CueInColors.accentFocus
            )
        }
    }
}
```

## Rules for Agents

- Use `CueInEditorToolbar` for editor close/save/principal controls.
- Use `CueInEditorPrincipalChip` for the center project, field, or context chip.
- Let `NavigationStack` and the system navigation bar create the top blur.
- Do not draw a top `LinearGradient`, masked material rectangle, or custom blur slab.
- Do not hide the navigation bar for editors just to recreate controls manually.
- Do not wrap the top controls in `safeAreaInset(edge: .top)`.
- Do not style editor X/check controls independently; update `CueInLiquidGlassToolbarIconButton` if the shared shape needs tuning.

## Button Rules

`CueInEditorToolbar` uses `CueInLiquidGlassToolbarIconButton` for the X and blue check controls. That component:

- keeps toolbar controls circular with a fixed size;
- uses native iOS 26 `glassEffect` for the button glass;
- hides the shared toolbar item glass background to avoid doubled or squeezed shapes;
- uses a blue-tinted checkmark inside the blue save button.

For editor-style settings that intentionally need a plain white check, pass:

```swift
saveButtonStyle: .plainIcon
```

That is the To-do settings case. Normal task/block editors should keep the default blue circular save button.
