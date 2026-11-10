public enum RouterOutcome: Equatable {
    case passThrough
    case consume
    /// Scale the CGEvent delta fields by these factors (CursorController).
    case cursorTransform(dxFactor: Double, dyFactor: Double)
    /// Scale the scroll wheel's axis delta fields by these factors (ScrollController).
    case scrollTransform(verticalFactor: Double, horizontalFactor: Double)
}
