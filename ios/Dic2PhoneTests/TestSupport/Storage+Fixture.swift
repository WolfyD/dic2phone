import Foundation
@testable import Dic2Phone

extension Storage {
    /// The app's folders, made fresh under `root`.
    static func fixture(in root: URL) throws -> Storage {
        let storage = Storage(
            support: root.appending(path: "support"),
            documents: root.appending(path: "documents"),
            temporary: root.appending(path: "tmp"),
            caches: root.appending(path: "caches")
        )
        try storage.prepare()
        return storage
    }
}
