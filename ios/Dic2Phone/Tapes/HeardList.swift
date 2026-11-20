import Foundation

/// Which deck tapes have been played (or shared) at least once; the rest are NEW.
struct HeardList {
    private static let key = "heard"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var ids: Set<TapeID> {
        Set((defaults.stringArray(forKey: Self.key) ?? []).compactMap(TapeID.init))
    }

    func markHeard(_ heard: some Sequence<TapeID>) {
        save(ids.union(heard))
    }

    func forget(_ forgotten: some Sequence<TapeID>) {
        save(ids.subtracting(forgotten))
    }

    private func save(_ ids: Set<TapeID>) {
        defaults.set(ids.map(\.fileName).sorted(), forKey: Self.key)
    }
}
