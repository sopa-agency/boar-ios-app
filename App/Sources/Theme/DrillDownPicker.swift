import SwiftUI

/// One choice of a `DrillDownPicker`.
struct DrillDownOption<Value: Hashable> {
    let value: Value
    let title: Text
    var symbol: String?
    /// A line under the title on the iPhone page (what an answer style does, as Android's StyleRow); the Mac menu shows
    /// the title only.
    var detail: Text?
    /// Shown but not selectable (Apple Intelligence on a device without it).
    var disabled = false
}

/// A picker that opens its own page of choices on iPhone and a pop-up menu on the Mac. The iPhone page is a `BoarForm`,
/// in the theme: the page SwiftUI pushes for `.pickerStyle(.navigationLink)` keeps the grouped system colors and
/// can't be styled from outside.
struct DrillDownPicker<Value: Hashable, Label: View, Current: View>: View {
    /// The page's title on iPhone.
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [DrillDownOption<Value>]
    @ViewBuilder let label: Label
    @ViewBuilder let current: Current

    var body: some View {
        #if os(iOS)
        NavigationLink {
            DrillDownPage(title: title, selection: $selection, options: options)
        } label: {
            HStack {
                label
                Spacer()
                current.foregroundStyle(.secondary)
            }
        }
        #else
        Picker(selection: $selection) {
            ForEach(options.indices, id: \.self) { i in
                DrillDownOptionLabel(option: options[i])
                    .tag(options[i].value)
                    .selectionDisabled(options[i].disabled)
            }
        } label: {
            label
        } currentValueLabel: {
            current
        }
        .pickerStyle(.menu)
        #endif
    }
}

private struct DrillDownOptionLabel<Value: Hashable>: View {
    let option: DrillDownOption<Value>
    var showsDetail = false

    var body: some View {
        if let symbol = option.symbol {
            // The icon in the tint, as on the system's picker page (a Mac menu draws its own), dim when disabled.
            Label { text } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(option.disabled ? AnyShapeStyle(.boar(.dim)) : AnyShapeStyle(.tint))
            }
        } else {
            text
        }
    }

    @ViewBuilder private var text: some View {
        if showsDetail, let detail = option.detail {
            // Android's StyleRow: the name in body textHeading semibold, what it does in subtext textSecondary.
            VStack(alignment: .leading, spacing: 2) {
                option.title
                    .fontWeight(.semibold)
                    .foregroundStyle(option.disabled ? AnyShapeStyle(.boar(.dim)) : AnyShapeStyle(.boar(.heading)))
                detail
                    .font(.boar("ui.subtext"))
                    .foregroundStyle(option.disabled ? AnyShapeStyle(.boar(.dim)) : AnyShapeStyle(.boar(.secondary)))
            }
        } else {
            option.title
                .foregroundStyle(option.disabled ? AnyShapeStyle(.boar(.dim)) : AnyShapeStyle(.boar(.primary)))
        }
    }
}

#if os(iOS)
/// The choices as rows (icon in the tint, a checkmark on the current one), like the system's picker page; choosing one
/// goes back, as there. The current row is marked as Android marks the chosen answer style: emeraldBgSubtle behind,
/// the check in textAccentEmerald.
private struct DrillDownPage<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [DrillDownOption<Value>]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    var body: some View {
        BoarForm {
            Section {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    let selected = option.value == selection
                    Button {
                        selection = option.value
                        dismiss()
                    } label: {
                        HStack {
                            DrillDownOptionLabel(option: option, showsDetail: true)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.boar(.success))
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                    }
                    // The system row button (it lights up on touch); the label sets its own colors.
                    .buttonStyle(.automatic)
                    .disabled(option.disabled)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .listRowBackground(Color(selected ? palette.emeraldBgSubtle : palette.bgCard))
                }
            }
        }
        .navigationTitle(Text(title))
        .inlineNavigationTitle()
    }
}
#endif
