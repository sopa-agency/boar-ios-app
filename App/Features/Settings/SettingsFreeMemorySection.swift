#if !os(macOS)
import BoarCore
import SwiftUI

/// Free memory when I leave BOAR (android Settings → model section and Advanced tweaks → Free memory after): the model
/// is unloaded soon after BOAR leaves the screen, so iOS doesn't end BOAR to get its memory back.
struct SettingsFreeMemorySection: View {
    let bridge: SettingsBridge

    var body: some View {
        let on = bridge.binding({ $0.freeMemoryInBackground }, { $0.freeMemoryInBackground = $1 })
        Section {
            Toggle(isOn: on) {
                SettingsLabel("Free Memory When I Leave BOAR", symbol: "memorychip")
            }
            if on.wrappedValue {
                Picker(selection: bridge.binding({ $0.freeMemoryAfterMinutes }, { $0.freeMemoryAfterMinutes = $1 })) {
                    Text("Auto").tag(Int?.none)
                    Text("Immediately").tag(Int?.some(0))
                    ForEach(FreeMemory.choicesMinutes, id: \.self) { m in
                        Text("\(m) min").tag(Int?.some(m))
                    }
                } label: {
                    SettingsLabel("Free Memory After", symbol: "timer")
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("Memory")
        } footer: {
            BoarFooter {
                Text("Shortly after you leave, when nothing is being answered, BOAR unloads the model, so the phone doesn't close BOAR to get its memory back. The next answer takes a few seconds longer to start.")
            }
        }
    }
}
#endif
