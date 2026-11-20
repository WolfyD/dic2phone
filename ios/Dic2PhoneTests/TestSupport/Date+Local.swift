import Foundation

extension Date {
    /// A wall-clock time in the test machine's time zone, the way tapes are stamped.
    static func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
