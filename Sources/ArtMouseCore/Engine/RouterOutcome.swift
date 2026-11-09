public enum RouterOutcome: Equatable {
    case passThrough
    case consume
    /// Scale the CGEvent delta fields by these factors (CursorController).
    case cursorTransform(dxFactor: Double, dyFactor: Double)
}
