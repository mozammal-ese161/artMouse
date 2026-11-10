import SwiftUI
import ArtMouseCore

struct ScrollBindingsTabView: View {
    let model: AppModel

    private var rows: [(label: String, axis: ScrollAxis, direction: ScrollDirection)] {
        [("Wheel Up", .vertical, .up), ("Wheel Down", .vertical, .down),
         ("Wheel Left", .horizontal, .left), ("Wheel Right", .horizontal, .right)]
    }

    var body: some View {
        List(rows, id: \.label) { row in
            ScrollBindingRowView(model: model, label: row.label,
                                 axis: row.axis, direction: row.direction)
        }
    }
}
