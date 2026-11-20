/// The app's screens. LOAD lists the deck's tapes to put one in the cassette well; the vault
/// is reached through the shelf, and search from any tape list.
indirect enum Screen {
    case deck
    case tapes
    case load
    case shelf
    case vault
    case setup(SetupTab)
    case search(returningTo: Screen)
}
