public struct TidyError: Error, CustomStringConvertible {
    public let description: String
    /// The longer story for the log, when `description` is a short version of it.
    public let detail: String?

    public init(_ description: String, detail: String? = nil) {
        self.description = description
        self.detail = detail
    }
}
