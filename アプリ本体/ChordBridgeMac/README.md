# Chord Bridge

Cubase 15のコード進行をLogic Proへ送り、LogicのSession Player演奏をMIDIまたはオーディオとしてCubaseへ戻す双方向のMacアプリ。

現行版は0.9.1（build 11）。Cubase 15日本語UIの実プロジェクトで、8個のコードMIDIパートを並び順・位置・長さを維持した一つのパートへ自動結合できることを確認済み。

Dockで一目で判別できるよう、青地に大きな `C7`、音符の橋、カタカナの `コード` を配置した専用アイコンを使用する。デスクトップ版はDockへ固定済み。

## 使い方

### Cubase → Logic

1. CubaseでコードのMIDIパートが横に並んでいるトラック名を一回クリックする。
2. Chord Bridgeの「① 選んだトラックのコードを一つにまとめる」を押す。
3. 初回のみ、macOSの「プライバシーとセキュリティ → アクセシビリティ」でChord Bridgeを許可する。
4. Cubaseで一つに結合されたMIDIパートを、Chord Bridgeの青いカードへドラッグする。
5. 青いカードをLogic Proのトラック領域へドラッグする。
6. Logic 12のコードトラックにしたい場合は、Logicへ入ったMIDIリージョンをグローバルのコードトラックへドラッグする。

Cubase側では、`編集 → 選択 → 選択トラック上の全イベントを選択` の後に `編集 → のり` を実行する。新しいトラックは作らず、コードの時間位置・長さ・並び順を維持して一つへ結合する。

アプリを再ビルドするとmacOSのアクセシビリティ許可が古い署名を指すことがある。その場合は設定一覧の古いChord Bridgeを削除し、完成した `build/Chord Bridge.app` を追加し直す。

### Logic → Cubase

1. LogicでDrummer／Bass／Keyboard等のSession Playerリージョンを選択する。
2. 編集可能な演奏データなら「MIDIで受け取る」、Logicの音色とエフェクト込みなら「オーディオで受け取る（WAV／AIFF）」を選ぶ。
3. MIDIの場合、Session PlayerをControlクリックして `変換 → MIDIリージョンに変換`、続けて `選択範囲をMIDIファイルとして…` を実行する。
4. オーディオの場合、リージョンをControlクリックし、`書き出す → 1個のリージョンをオーディオファイルとして…` を実行する。
5. 保存したMIDI／オーディオを受渡カードへ入れ、Cubaseへドラッグする。

注意: Logic Pro 12.3の右クリックメニューは通常のアクセシビリティUI外に出るため、0.9の二つのボタンから保存画面を自動で開く処理は未解決。ファイル受渡部分は利用できる。

## 現在の対象

- Cubase 15 日本語UI
- Logic Pro 12 日本語UI
- `.mid` / `.midi` / `.wav` / `.aiff` / `.caf` など

CubaseとLogicのコードトラックには直接互換性がないため、MIDIノートを中間形式として使う。

Chord Bridgeのウインドウは常に手前に表示されるため、CubaseやLogicを操作中でも受渡カードへドラッグできる。

0.3からは、受け取ったMIDIをファイルURLと `public.midi-audio` データの両方でmacOSのクリップボードへコピーできる。
