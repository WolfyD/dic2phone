import Foundation
import Observation

/// A tape list's state and what its keys do: the selection, a question or share sheet waiting
/// to open, and the short note left after an action.
@MainActor
@Observable
final class TapeListModel {
    let mode: TapeListMode
    private(set) var selected: Set<TapeID> = []
    var confirming: ConfirmRequest?
    private(set) var sharing: ShareRequest?
    /// Stands in for Android's toasts.
    var notice: String?
    /// What a long job is doing, shown in place of the keys until it's done.
    private(set) var busy: String?

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let library: TapeLibrary
    @ObservationIgnored private let player: Player
    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private let navigate: (Screen) -> Void

    init(
        mode: TapeListMode,
        settings: Settings,
        library: TapeLibrary,
        player: Player,
        vault: Vault,
        navigate: @escaping (Screen) -> Void
    ) {
        self.mode = mode
        self.settings = settings
        self.library = library
        self.player = player
        self.vault = vault
        self.navigate = navigate
    }

    var isLocked: Bool {
        mode.rack == .vault && !vault.isOpen
    }

    var vaultIsOpen: Bool {
        vault.isOpen
    }

    var vaultCount: Int {
        library.vault.count
    }

    var isKeyLost: Bool {
        vault.isKeyLost
    }

    var passcodeIsSet: Bool {
        vault.passcodeIsSet
    }

    var sort: TapeSort {
        settings.sort(for: mode.rack)
    }

    var tapes: [Tape] {
        library.tapes(in: mode.rack, sortedBy: sort)
    }

    var selection: [Tape] {
        tapes.filter { selected.contains($0.id) }
    }

    func cycleSort() {
        settings.cycleSort(for: mode.rack)
    }

    func goBack() {
        navigate(mode.back)
    }

    func openVaultScreen() {
        navigate(.vault)
    }

    /// Leaving the list stops its tape, as on Android.
    func leave() {
        player.stop()
    }

    func tap(_ tape: Tape) {
        if !selected.isEmpty {
            toggleSelection(of: tape)
        } else if mode == .load {
            putInDeck(tape)
        } else {
            player.toggle(tape)
        }
    }

    func toggleSelection(of tape: Tape) {
        if selected.contains(tape.id) {
            selected.remove(tape.id)
        } else {
            selected.insert(tape.id)
        }
    }

    func selectAll() {
        selected = Set(tapes.map(\.id))
    }

    func clearSelection() {
        selected = []
    }

    func putInDeck(_ tape: Tape) {
        player.load(tape)
        selected = []
        navigate(.deck)
    }

    func send(_ tapes: [Tape]) {
        Task {
            let files = await library.filesToSend(tapes)
            guard !files.isEmpty else {
                notice = String(localized: "Couldn't unseal the tapes")
                return
            }
            sharing = ShareRequest(tapes: tapes, files: files)
        }
    }

    /// Called both when the share sheet reports back and when it's swiped away.
    func finishSharing(sent: Bool) {
        guard let sharing else { return }
        if sent, mode.rack == .deck {
            library.markHeard(sharing.tapes)
        }
        if mode.rack == .vault {
            Task { await library.clearSendingCopies() }
        }
        self.sharing = nil
        selected = []
    }

    func shelve(_ tapes: [Tape]) {
        stopIfPlaying(tapes)
        Task {
            let moved = await library.shelve(tapes)
            selected = []
            notice = moved == tapes.count
                ? String(localized: "Moved to shelf")
                : String(localized: "Moved \(moved) of \(tapes.count) to the shelf")
        }
    }

    func confirmErase(_ tapes: [Tape]) {
        confirming = ConfirmRequest(
            title: String(localized: "Erase \(tapes.count) tapes?"),
            message: String(localized: "This can't be undone."),
            button: String(localized: "ERASE")
        ) { [weak self] in self?.erase(tapes) }
    }

    func confirmEraseAll(_ tapes: [Tape]) {
        confirming = ConfirmRequest(
            title: String(localized: "Erase the whole deck?"),
            message: String(localized: "All \(tapes.count) tapes on the deck will be deleted. Tapes on the shelf are kept."),
            button: String(localized: "ERASE ALL")
        ) { [weak self] in self?.erase(tapes) }
    }

    /// Seals tapes into the vault, opening it first if need be.
    func lockAway(_ tapes: [Tape]) {
        Task {
            guard await openVault() else { return }
            busy = String(localized: "LOCKING \(tapes.count) TAPES…")
            // Out of the deck too, or the deck would remember a vault tape's name.
            player.letGo(of: tapes)
            let result = await library.lockAway(tapes)
            busy = nil
            selected = []
            notice = lockAwayNotice(result, of: tapes.count)
        }
    }

    func confirmTakeOut(_ tapes: [Tape]) {
        confirming = ConfirmRequest(
            title: String(localized: "Take \(tapes.count) tapes out?"),
            message: String(localized: "They go back on the shelf, unencrypted, where the Files app and other apps can open them."),
            button: String(localized: "TAKE OUT")
        ) { [weak self] in self?.takeOut(tapes) }
    }

    func unlock() {
        Task { _ = await openVault() }
    }

    func lock() {
        Task { await vault.lock() }
    }

    func confirmReset() {
        confirming = ConfirmRequest(
            title: String(localized: "Reset the vault?"),
            message: String(localized: "The vault's key is gone, so the tapes inside can never be played again. Resetting deletes them and makes a new, empty vault."),
            button: String(localized: "RESET")
        ) { [weak self] in self?.reset() }
    }

    private func erase(_ tapes: [Tape]) {
        stopIfPlaying(tapes)
        Task {
            let failures = await library.delete(tapes)
            selected = []
            if failures > 0 {
                notice = String(localized: "Couldn't erase \(failures) tapes")
            }
        }
    }

    private func takeOut(_ tapes: [Tape]) {
        stopIfPlaying(tapes)
        Task {
            let takenOut = await library.takeOut(tapes)
            selected = []
            if takenOut < tapes.count {
                notice = String(localized: "Took out \(takenOut) of \(tapes.count)")
            }
        }
    }

    private func reset() {
        Task {
            await vault.reset()
            notice = String(localized: "Vault reset")
        }
    }

    private func stopIfPlaying(_ tapes: [Tape]) {
        if tapes.contains(where: { $0.id == player.playingID }) {
            player.stop()
        }
    }

    /// - Returns: whether the vault is open now. If it can't be, the vault's door says why.
    private func openVault() async -> Bool {
        switch await vault.unlock() {
        case .opened:
            return true
        case .cancelled:
            return false
        case .noPasscode, .keyLost:
            if mode.rack != .vault { navigate(.vault) }
            return false
        case .failed:
            notice = String(localized: "Couldn't open the vault")
            return false
        }
    }

    private func lockAwayNotice(_ result: LockAwayResult, of count: Int) -> String {
        if result.locked.count < count {
            String(localized: "Locked \(result.locked.count) of \(count) tapes")
        } else if result.leftBehind > 0 {
            String(localized: "Locked away, but \(result.leftBehind) originals couldn't be removed. Erase them by hand.")
        } else {
            String(localized: "Locked in the vault")
        }
    }
}
