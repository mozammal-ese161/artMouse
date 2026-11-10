import SwiftUI
import ArtMouseCore

struct ButtonsTabView: View {
    let model: AppModel

    private var buttons: [ButtonID] {
        let standard: [ButtonID] = [.left, .right, .middle, .fourth, .fifth]
        let extendedNumbers = model.settings.buttonBindings.compactMap { binding -> Int? in
            if case .extended(let n) = binding.button { return n }
            return nil
        }
        return standard + extendedNumbers.sorted().map { ButtonID.extended($0) }
    }

    var body: some View {
        List {
            Section {
                ForEach(buttons, id: \.self) { button in
                    BindingRowView(model: model, button: button)
                }
            } header: {
                HStack {
                    Text("Buttons")
                    Spacer()
                    Menu("Add…") {
                        ForEach(5...31, id: \.self) { number in
                            Button("Button \(number + 1)") {
                                model.ensureBinding(for: .extended(number))
                            }
                        }
                    }
                }
            }
        }
    }
}
