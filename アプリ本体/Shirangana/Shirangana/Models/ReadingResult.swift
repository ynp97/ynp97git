import Foundation

struct ReadingResult: Equatable, Sendable {
    let expression: String
    let readings: [String]
    let meanings: [String]
    let diagnostic: RecognitionDiagnostic?

    init(
        expression: String,
        readings: [String],
        meanings: [String],
        diagnostic: RecognitionDiagnostic? = nil
    ) {
        self.expression = expression
        self.readings = readings
        self.meanings = meanings
        self.diagnostic = diagnostic
    }
}

struct RecognitionDiagnostic: Equatable, Sendable {
    var variants: [RecognitionVariantDiagnostic]
    var dictionaryCandidates: [DictionaryCandidateDiagnostic]

    var allOCRCandidates: [String] {
        variants.reduce(into: [String]()) { combined, variant in
            for candidate in variant.candidates where !combined.contains(candidate) {
                combined.append(candidate)
            }
        }
    }
}

struct RecognitionVariantDiagnostic: Equatable, Sendable {
    let name: String
    let imageData: Data
    let candidates: [String]
}

struct DictionaryCandidateDiagnostic: Equatable, Sendable {
    let sourceText: String
    let matchedExpression: String?
    let readings: [String]
    let meanings: [String]
}
