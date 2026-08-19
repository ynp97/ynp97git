import SwiftUI
import UIKit

struct ResultScreen: View {
    let result: ReadingResult
    let retry: () -> Void
    let chooseCandidate: (DictionaryCandidateDiagnostic) -> Void
    @StateObject private var speaker = SpeechService()

    var body: some View {
        VStack(spacing: 12) {
            Button("もう一度") {
                retry()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 20) {
                    Text(result.expression)
                        .font(.system(size: 66, weight: .black, design: .monospaced))
                        .foregroundStyle(PixelTheme.paper)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .padding(.top, 18)
                        .pixelPanel(fill: PixelTheme.ink, stroke: PixelTheme.gold)

                    ForEach(result.readings, id: \.self) { reading in
                        Button {
                            speaker.speak(reading)
                        } label: {
                            HStack {
                                Text(reading)
                                    .font(PixelTheme.font(size: 31))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.82)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 12)
                                Text("♪")
                                    .font(PixelTheme.font(size: 27))
                            }
                            .foregroundStyle(PixelTheme.ink)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 60)
                            .pixelPanel(fill: PixelTheme.paper, stroke: PixelTheme.blue)
                        }
                    }

                    if !result.meanings.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("▼ だいひょうてきな いみ")
                                .font(PixelTheme.font(size: 15))
                                .foregroundStyle(PixelTheme.red)

                            ForEach(result.meanings, id: \.self) { meaning in
                                Text(meaning)
                                    .font(PixelTheme.font(size: 16, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pixelPanel(fill: PixelTheme.paper)
                    }

                    if let diagnostic = result.diagnostic {
                        CandidateSelectionPanel(
                            diagnostic: diagnostic,
                            choose: chooseCandidate
                        )
                        #if DEBUG
                        DiagnosticPanel(diagnostic: diagnostic)
                        #endif
                    }

                    Text("意味は代表例です。文脈によって異なる場合があります。")
                        .font(PixelTheme.font(size: 9, weight: .medium))
                        .foregroundStyle(PixelTheme.ink.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

struct CandidateSelectionPanel: View {
    let diagnostic: RecognitionDiagnostic
    let choose: (DictionaryCandidateDiagnostic) -> Void

    private var choices: [DictionaryCandidateDiagnostic] {
        var seen = Set<String>()
        return diagnostic.dictionaryCandidates.filter { candidate in
            guard let expression = candidate.matchedExpression,
                  !candidate.readings.isEmpty,
                  !seen.contains(expression) else {
                return false
            }
            seen.insert(expression)
            return true
        }.prefix(5).map { $0 }
    }

    var body: some View {
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("▼ ほかの候補をえらぶ")
                    .font(PixelTheme.font(size: 14))
                    .foregroundStyle(PixelTheme.blue)
                Text("OCRの候補から、読みのある言葉を選べます")
                    .font(PixelTheme.font(size: 10, weight: .medium))
                    .foregroundStyle(PixelTheme.ink.opacity(0.68))
                ForEach(choices, id: \.matchedExpression) { candidate in
                    Button {
                        choose(candidate)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.matchedExpression ?? candidate.sourceText)
                                    .font(PixelTheme.font(size: 18))
                                Text(candidate.readings.joined(separator: " / "))
                                    .font(PixelTheme.font(size: 13))
                            }
                            Spacer()
                            Text("これ")
                                .font(PixelTheme.font(size: 12))
                        }
                        .foregroundStyle(PixelTheme.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pixelPanel(fill: PixelTheme.gold, stroke: PixelTheme.ink, shadowSize: 2)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelPanel(fill: PixelTheme.paper)
        }
    }
}

#if DEBUG
struct DiagnosticPanel: View {
    let diagnostic: RecognitionDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BUILD \(buildNumber) 診断")
                .font(PixelTheme.font(size: 15))
                .foregroundStyle(PixelTheme.red)

            VStack(alignment: .leading, spacing: 8) {
                Text("▼ 画像パターンとOCR候補")
                    .font(PixelTheme.font(size: 11))
                    .foregroundStyle(PixelTheme.blue)

                ForEach(diagnostic.variants, id: \.name) { variant in
                    DiagnosticVariantRow(variant: variant)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("▼ 辞書照合")
                    .font(PixelTheme.font(size: 11))
                    .foregroundStyle(PixelTheme.blue)

                if diagnostic.dictionaryCandidates.isEmpty {
                    Text("OCR候補がないため、辞書照合なし")
                        .font(PixelTheme.font(size: 11, weight: .medium))
                        .foregroundStyle(PixelTheme.ink.opacity(0.65))
                } else {
                    ForEach(Array(diagnostic.dictionaryCandidates.prefix(12).enumerated()), id: \.offset) { _, candidate in
                        DiagnosticDictionaryRow(candidate: candidate)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel(fill: PixelTheme.paper)
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "?"
    }
}

private struct DiagnosticVariantRow: View {
    let variant: RecognitionVariantDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                if let image = UIImage(data: variant.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 86, height: 70)
                        .background(PixelTheme.ink.opacity(0.08))
                        .overlay {
                            Rectangle().stroke(PixelTheme.ink.opacity(0.25), lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(variant.name)
                        .font(PixelTheme.font(size: 12))
                        .foregroundStyle(PixelTheme.ink)

                    if variant.candidates.isEmpty {
                        Text("OCR候補なし")
                            .font(PixelTheme.font(size: 10, weight: .medium))
                            .foregroundStyle(PixelTheme.red)
                    } else {
                        Text(variant.candidates.prefix(5).joined(separator: " / "))
                            .font(PixelTheme.font(size: 11, weight: .medium))
                            .foregroundStyle(PixelTheme.ink.opacity(0.78))
                            .lineLimit(3)
                    }
                }
            }
        }
        .padding(8)
        .background(PixelTheme.ink.opacity(0.04))
    }
}

private struct DiagnosticDictionaryRow: View {
    let candidate: DictionaryCandidateDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("OCR: \(candidate.sourceText)")
                .font(PixelTheme.font(size: 10, weight: .medium))
                .foregroundStyle(PixelTheme.ink.opacity(0.7))
                .lineLimit(2)

            if let expression = candidate.matchedExpression {
                Text("辞書: \(expression) → \(candidate.readings.joined(separator: " / "))")
                    .font(PixelTheme.font(size: 11))
                    .foregroundStyle(PixelTheme.ink)
                    .lineLimit(2)
            } else {
                Text("辞書ヒットなし")
                    .font(PixelTheme.font(size: 10, weight: .medium))
                    .foregroundStyle(PixelTheme.red)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(PixelTheme.ink.opacity(0.04))
    }
}
#endif
