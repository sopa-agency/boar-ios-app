import SwiftUI

/// One choice of a `DrillDownPicker`.
struct DrillDownOption<Value: Hashable> {
    let value: Value
    let title: Text
    var symbol: String?
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

    var body: some View {
        if let symbol = option.symbol {
            // The icon in the tint, as on the system's picker page (a Mac menu draws its own).
            Label { option.title } icon: { Image(systemName: symbol).foregroundStyle(.tint) }
        } else {
            option.title
        }
    }
}

#if os(iOS)
/// The choices as rows (icon in the tint, a checkmark on the current one), like the system's picker page; choosing one
/// goes back, as there.
private struct DrillDownPage<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [DrillDownOption<Value>]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BoarForm {
            Section {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    Button {
                        selection = option.value
                        dismiss()
                    } label: {
                        HStack {
                            DrillDownOptionLabel(option: option)
                                .foregroundStyle(option.disabled ? AnyShapeStyle(.boar(.dim)) : AnyShapeStyle(.primary))
                            Spacer()
                            if option.value == selection {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(option.disabled)
                    .accessibilityAddTraits(option.value == selection ? .isSelected : [])
                }
            }
        }
        .navigationTitle(Text(title))
        .inlineNavigationTitle()
    }
}
#endif
