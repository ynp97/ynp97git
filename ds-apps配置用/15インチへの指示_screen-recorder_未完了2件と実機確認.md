# 15インチMac（DS実装機）への指示 — screen-recorder 未完了2件 ＋ .app実機確認

作成日: 2026-07-31
前の指示: `15インチへの指示_screen-recorder移設.md`（7/30に再指示済み。**うち可視性変更が未実行であることを7/31に確認**）
※ 下の「DSへ渡す本文」を**そのまま**コピーして渡す。

---

## 確認済みの現状（2026-07-31、こちら側で実地確認）

- `https://github.com/ynp97apps15/screen-recorder` を未ログイン状態で取得できた。ページ上の表示は **Public**、公開メタデータも `repository_public: true`。
  → **Private化は実行されていない。** 7/30の再指示は額面通りに実行されなかった。
- `docs/作業票/screen-recorder-移設.md` の有無は、`ds-apps` が非公開のため外部からは確認できない。**未確認**として扱う。

---

## DSへ渡す本文（ここから）

```
screen-recorder について、未完了の作業がある。着手前に必ず ds-apps を pull し、root の AGENTS.md を読み直すこと。

前提として伝える。7月30日に同じ内容を指示したが、実行されていなかった。今回は「やった」という報告ではなく、
やった証拠だけを受け取る。証拠が貼られていない項目は未実施として扱う。

---

■ 作業1: 作業票を作る

ファイル: ds-apps の docs/作業票/screen-recorder-移設.md
テンプレート: docs/作業票テンプレート.md に沿うこと。

このファイルが存在しない場合は新規に作る。既にある場合も、下の内容が入っているか確認して足す。

「ビルド結果」の欄には、次を実際に実行し、コマンド行と出力を1文字も編集せずそのまま貼ること。

  cd apps/screen-recorder
  swift build 2>&1 | tail -40
  ls -la .build/*/ScreenRecorder 2>&1

「未ビルド」「未実施」「（省略）」「〜のはず」と書いてpushしない。
ビルドが通らなかった場合はエラー全文を貼る。それは正しい報告であり、失敗として扱わない。

■ 作業2: 旧リポジトリを Private にする

ynp97apps15/screen-recorder を、アーカイブではなく Private にする。
  Settings → General → 一番下 Danger Zone → Change repository visibility → Make private

アーカイブ（Archive）は公開状態が続くので不可。7月30日はここを取り違えている。
削除はしない。Privateにするだけ。削除の判断は本人が行う。

実行後、次を実行してこの出力を作業票の末尾に貼ること。

  curl -s -o /dev/null -w "%{http_code}\n" https://github.com/ynp97apps15/screen-recorder

  ※ このMacはログイン済みなので 200 が返る場合がある。必ず
    curl -s -o /dev/null -w "%{http_code}\n" -H "Cache-Control: no-cache" \
      "https://api.github.com/repos/ynp97apps15/screen-recorder"
    を、認証情報を付けずに（-u や Authorization ヘッダを付けずに）実行し、404 が返ることを貼る。
    200 が返るならまだ公開のままである。

■ 作業3: .app として実機確認する

ds-apps の apps/screen-recorder/ のコードから .app をビルドし、実際に起動して次を通すこと。
アプリ本体/ 側の古いコピーではなく、必ず ds-apps 側のコードを使う。

  1) build.sh を実行して .app を作る（コマンドと出力を貼る）
  2) .app を起動する
  3) 録画を開始し、10秒以上録る
  4) 停止する
  5) ~/Desktop/ScreenRecordings/ に出来たファイルについて、次を実行して出力を貼る
       ls -la ~/Desktop/ScreenRecordings/
       # 直近のファイルに対して
       ffprobe -hide_banner <ファイルパス> 2>&1 | tail -20
     ffprobe が無ければ  mdls -name kMDItemDurations -name kMDItemPixelHeight <ファイルパス>  でよい
  6) そのファイルをQuickTimeで再生し、映像が映り音が出るかを確認する

  ※ 過去に「0バイトのファイルを Saved と表示した」事故がある。
    ファイルサイズが 0 でないこと、再生時間が 0 秒でないことを、上の出力で示すこと。

権限について:
  画面収録の許可（システム設定 → プライバシーとセキュリティ → 画面収録）が必要になる。
  この許可はGUI操作が要るため、DS側で取得できない場合がある。
  取得できない場合は、そこまでの出力を貼ったうえで
  「画面収録権限が取得できないため 3)〜6) は未実施」と作業票に明記して停止すること。
  推測や想定で「動作確認できた」と書いてはならない。

■ 作業4: C層 相互チェック

実装したセッションで自己検品しない。新しいセッションを立て、渡すのは差分（git diff main...HEAD）と
完成条件だけ。台帳・リポジトリ全文は渡さない。
聞くこと: 仕様外の機能を足していないか／実データ・APIキー・証明書の混入／エラー処理の抜けと失敗時の挙動。
指摘と対応を作業票の「懸念・相談」へ残す。省略した場合は「急ぎ指示により省略」ではなく理由を書く。

■ push

  cd ~/ds-apps
  git add .
  git commit -m "screen-recorder 作業票の追加と実機確認結果"
  git push origin ds/screen-recorder

main へは push しない。

---

■ 完成条件（すべて証拠つきで）

  [ ] docs/作業票/screen-recorder-移設.md が ds/screen-recorder ブランチに存在する
  [ ] 作業票に swift build の実出力が貼られている
  [ ] 作業票に build.sh の実出力が貼られている
  [ ] 作業票に ls -la ~/Desktop/ScreenRecordings/ の実出力が貼られ、サイズが0でないファイルがある
      （権限が取れなかった場合は、その旨と取得を試みた記録）
  [ ] 認証なしの api.github.com への curl が 404 を返す（＝Privateになっている）
  [ ] C層レビューの結果、または省略した理由が書かれている

■ 報告の形式

作業票へのリンクと、上の6項目それぞれについて「証拠を貼った箇所」を1行ずつ返す。
「完了しました」だけの報告は受け取らない。
```

## DSへ渡す本文（ここまで）

---

## こちら側での確かめ方（DSの報告を受け取ったあと、南雲さんの手で）

1. `https://github.com/ynp97/ds-apps/tree/ds/screen-recorder/docs/作業票` を開き、`screen-recorder-移設.md` が実在するか見る。**DSの報告ではなくブラウザで見る。**
2. その中に `swift build` の生出力が貼ってあるか見る。「未ビルド」「省略」があれば未完了。
3. **ログアウト状態（またはプライベートウィンドウ）**で `https://github.com/ynp97apps15/screen-recorder` を開く。404なら Private 化できている。ログイン状態で見ると Private でも見えてしまうので、必ずプライベートウィンドウで確認する。
4. 録画ファイルの証拠（`ls -la` の出力）で、サイズが 0 でないことを見る。

---

## 2026-07-31 進行状況 — 一件ずつ渡す方式に切替

一括で渡さず、**1件渡す → 出力を検算する → 次を渡す**に変えた。作業1は通り、作業2で偽の完了報告を検出できたので、この方式を継続する。

- **作業1（Private化）: 完了。** 未認証で `api.github.com/repos/ynp97apps15/screen-recorder` を叩き、公開時のJSONが返らないことを確認した。
- **作業2（作業票）: 差し戻し中。** DSが `Build complete! (0.11s)` を返してきたが、`[0/3]` で止まっておりコンパイルしていない（キャッシュ判定のみ）。7/30と同じ罠で**2回目**。

### 再開時にDSへ貼る（作業2の差し戻し）

```
その出力はビルドの証拠にならない。[0/3] で止まっていて、Swiftファイルを1つもコンパイルしていない。
0.11秒は .build のキャッシュを見て「変更なし」と判断しただけの時間で、7月30日にも同じものを受け取っている。

キャッシュを消してゼロから通すこと。次をそのまま実行し、出力を全部返す。

  cd ~/ds-apps/apps/screen-recorder
  rm -rf .build
  swift build 2>&1 | tail -40
  echo "---- 成果物 ----"
  ls -la .build/debug/ScreenRecorder

Compiling / Emitting といった行が出るはずで、時間も数秒以上かかる。
また 0.1 秒台で Build complete と出たら、それは何かおかしいのでそのまま報告すること。

作業票にも、この新しい出力へ差し替えて push すること。

あわせて、次の出力も返す。作業票が本当に push できているかの確認。

  cd ~/ds-apps
  git log --oneline -3 origin/ds/screen-recorder
  git ls-tree -r --name-only origin/ds/screen-recorder | grep 作業票
```

## この指示で塞いだ抜け道（次回も使う）

- 「やった」という自己申告を受け取らず、**外から検証できる出力**（`curl` の HTTP ステータス、`ls -la` のバイト数）を要求した。
- **アーカイブとPrivateの取り違え**を明示的に否定した（7/30の実際の失敗）。
- ログイン状態だと Private でも 200 が返る点を先回りして書き、**認証なしのAPI叩き**を指定した。
- 「権限が取れないときは停止して未実施と書け」と逃げ道を用意した。逃げ道が無いと、DSは実施したことにする。
- 0バイト事故の履歴を明記し、**サイズと再生時間**を証拠に指定した。
