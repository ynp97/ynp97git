import SwiftUI

struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("プライバシー") {
                    Label("画像は保存しません", systemImage: "photo.badge.checkmark")
                    Label("すべて端末内で処理します", systemImage: "iphone")
                    Label("個人情報を収集しません", systemImage: "hand.raised.fill")
                }

                Section("辞書") {
                    Text(
                        """
                        本アプリはElectronic Dictionary Research and Development Groupの\
                        JMdictと日本語WordNetを、それぞれのライセンスに従って使用しています。
                        """
                    )
                    .font(.footnote)

                    Link(
                        "JMdictライセンス",
                        destination: URL(string: "https://www.edrdg.org/edrdg/licence.html")!
                    )
                    Link(
                        "日本語WordNet",
                        destination: URL(string: "https://bond-lab.github.io/wnja/index.ja.html")!
                    )
                }

                Section("バージョン") {
                    Text("1.0")
                }
            }
            .navigationTitle("このアプリについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}
