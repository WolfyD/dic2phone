/// One line of what the deck knows about a tape: "LENGTH  4:05".
struct TapeFact: Equatable, Identifiable {
    let name: String
    let value: String

    var id: String { name }
}
