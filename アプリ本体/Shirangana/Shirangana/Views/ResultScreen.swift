import SwiftUI

struct ResultScreen: View {
    let result: ReadingResult
    let retry: () -> Void
    @StateObject private var speaker = SpeechService()

    var body: some View {
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
                            Spacer()
                            Text("♪")
                                .font(PixelTheme.font(size: 27))
                        }
                        .foregroundStyle(PixelTheme.ink)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
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

                Text("意味は代表例です。文脈によって異なる場合があります。")
                    .font(PixelTheme.font(size: 9, weight: .medium))
                    .foregroundStyle(PixelTheme.ink.opacity(0.65))
                    .multilineTextAlignment(.center)

                Button("もう一度") {
                    retry()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            }
            .padding(24)
        }
    }
}
