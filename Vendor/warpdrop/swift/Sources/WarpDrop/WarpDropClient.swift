import Foundation

public enum WarpDropError: Error, LocalizedError {
    case stubImplementation

    public var errorDescription: String? {
        "WarpDrop is unavailable in local dev builds (upstream uses a private package)."
    }
}

public struct WarpDropClient: Sendable {
    public init() {}

    public func send(
        files: [URL],
        keep: Bool,
        onRoomCreated: @escaping @Sendable (String) -> Void,
        onDownloadCompleted: @escaping @Sendable (Int) -> Void
    ) async throws -> String {
        throw WarpDropError.stubImplementation
    }
}
