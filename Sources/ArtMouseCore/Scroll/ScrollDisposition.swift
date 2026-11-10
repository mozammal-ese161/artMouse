public enum ScrollDisposition: Equatable {
    case passThrough
    case scale(vertical: Double, horizontal: Double)
    case intercept
}

public protocol ScrollControlling: AnyObject {
    func disposition(forScroll axis: ScrollAxis, ticks: Double) -> ScrollDisposition
}
