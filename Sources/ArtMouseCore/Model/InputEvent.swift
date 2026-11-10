public enum ScrollAxis: Equatable, Codable {
    case vertical, horizontal
}

/// Normalized input event fed to EventRouter. Produced from CGEvents by
/// CGEventTranslation, and (phase 4) from raw HID reports by HIDObserver.
public enum InputEvent: Equatable {
    case buttonDown(ButtonID)
    case buttonUp(ButtonID)
    case moved(dx: Double, dy: Double)
    case dragged(dx: Double, dy: Double)
    case scrolled(axis: ScrollAxis, ticks: Double)
    case other
}
