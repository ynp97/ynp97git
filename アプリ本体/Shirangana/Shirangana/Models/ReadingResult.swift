import Foundation

struct ReadingResult: Equatable, Sendable {
    let expression: String
    let readings: [String]
    let meanings: [String]
}
