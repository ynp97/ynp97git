# 🎹 Cubase 15・nanoKEY Studio Bluetooth MIDI Remote設定

## 結論

- USB接続とBluetooth接続は、Cubaseでは別のMIDIポートとして扱われる。
- USB用MIDI Remoteは削除せず、Bluetooth用サーフェスを別に作って併存させてよい。
- nanoKEY StudioのX-Yモードは、現在のScene 1では次の設定。
  - X軸（横）＝CC16、Left 0、Right 127
  - Y軸（縦）＝CC17、Lower 0、Upper 127
- Cubase側は専用の「X/Yパッド」を使い、X＝CC16、Y＝CC17を直接入力する。
- 方向を逆にしたいだけなら、Cubaseのマッピング範囲を反転できる。Cubase側でできない場合はKORG KONTROL Editorで0と127を入れ替える。

## Bluetooth接続

1. 以前つながっていた別のMac・iPhone・iPadからnanoKEY Studioを切断する。
2. nanoKEY Studioを一度Standbyにし、再びバッテリー／ワイヤレス側へ入れる。
3. Macの `Bluetooth MIDI Connect` で `nanoKEY Studio` を接続する。
4. 接続完了後にCubaseを起動する。
5. Cubaseの `スタジオ設定 → MIDIポートの設定` で `nanoKEY Studio Bluetooth` がアクティブか確認する。

## Bluetooth用MIDI Remote

1. USB用サーフェスは残す。
2. `MIDI Remoteマネージャー → サーフェスを追加` でBluetooth用を作る。
3. 入力・出力ポートを両方 `nanoKEY Studio Bluetooth` にする。
4. ノブ8個を登録し、必要に応じてQC1〜QC8へ割り当てる。
5. USB用とBluetooth用は2つあって問題ない。同時接続しなければ通常は二重操作にならない。

## XYパッド

1. nanoKEY Studio本体の `X-Y` ボタンを点灯させる。
2. Cubaseのコントローラーサーフェス編集で、フェーダー2本ではなく専用の `X/Yパッド` を配置する。
3. MIDI Learnは使わず、プロパティへ直接入力する。
   - X軸：Control Change、チャンネル1、CC16、絶対、0〜127
   - Y軸：Control Change、チャンネル1、CC17、絶対、0〜127
4. マッピングアシスタントで、例としてX→QC1、Y→QC2へ割り当てる。

## 方向を反転する

### Cubase側

マッピング設定の最小・最大を逆にできる場合は、反転したい軸だけ `最小100%／最大0%` にする。

### KORG側

- 横を反転：X-axis Left Value 127／Right Value 0
- 縦を反転：Y-axis Lower Value 127／Upper Value 0

変更後は `転送 → シーンデータを書き込み` を実行する。

## 今回つまずいた点

- nanoKEY Studioが15インチMacへつながったままで、新しいMacではスキャンが終わらなかった。
- USB用MIDI RemoteはUSB固有ポートに結びついており、Bluetooth接続では「切断」になる。マッピング消失ではない。
- USB用サーフェスのポートは簡単にBluetoothへ差し替えられなかったため、Bluetooth用を別作成した。
- Touch Scaleモードでは横になぞると音程を演奏する。QC操作にはX-Yモードを使う。
- CubaseのXY操作はフェーダー2本ではなく、専用X/Yパッドを使う。
- KORG KONTROL Editorの中央図だけではCC番号の所属を誤読しやすい。必ず左の `X-Y` を選択し、詳細欄を下へスクロールして確認する。
- CC1はPitch/ModのMod、CC19はTouch ScaleのY軸であり、X-Yモードの番号ではなかった。
- 確定したX-Yモードの番号はX＝CC16、Y＝CC17。

## 次回の検索語

`nanoKEY Bluetooth` / `Cubase MIDI Remote` / `XYパッド` / `CC16 CC17` / `USBとBluetooth切替`
