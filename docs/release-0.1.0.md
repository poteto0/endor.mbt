# v0.1.0 公開までのタスク整理

対象: `poteto0/endor` を mooncakes.io に `moon publish` して、GitHub リポジトリ
(`github.com/poteto0/endor.mbt`) を SDK として人に見せられる状態にすること。

方針: **v0.1.0 は読み取り専用の SDK として公開する** (下記 F の判断)。

状況 (2026-07-25):

- `just ci-check` は全部通る (fmt / check / build / 51 tests / info-check)。
- `moon publish --dry-run` → サーバは 202 Accepted。名前とバージョンは確保済み。
- A / B / C / F は完了。残っているのは **E (パッケージング)** と、
  公開前に潰しておきたい README の壊れた画像リンク。

---

## A. リポジトリを公開状態にする — 完了

`moon.mod` が commit されておらず、clone してもビルドできない状態だった
(`origin/main` はルートのファイルを 1 つも持っていなかった)。

- [x] A-1. 未追跡の必須ファイルを commit
      (`moon.mod` / `moon.pkg` / `moon.work` / `endor.mbt` / `pkg.generated.mbti` /
      `README.mbt.md` / `README.md` / `LICENSE` / `AGENTS.md` / `.gitignore`)
- [x] A-2. `types/pkg.generated.mbti` の package 名 `username/endor/types` →
      `poteto0/endor/types`。これで `just info-check` が緑。
- [x] A-3. `.githooks/pre-commit` を `just ci` → `just ci-check` に変更
      (コミット中にファイルを書き換えるのではなく落ちるように)。
      `copilot-setup-steps.yml` の削除は PR #1 で済んでいた。
- [x] A-4. `ci/github-actions` → `main` のマージは PR #1 で完了済み。
- [ ] A-5. **`main` を push する** (ローカルにコミット済み、リモートは未反映)。

## B. moon.mod のメタデータ — 完了

- [x] B-1. `repository = "https://github.com/poteto0/endor.mbt"`
- [x] B-2. `description` を記入
- [x] B-3. `keywords = ["ethereum", "metamask", "wallet", "eip-1193", "dapp", "web3"]`

## C. ドキュメントを実際の API に合わせる — 完了

root package の階層は維持し (案 1)、doc 側を `@provider.*` に直す方針を採った。
root と `types` がバックエンド非依存のままなので、`ffi/js` だけが js 限定という
分離が保たれる。

- [x] C-1. README のサンプルを実際の API に修正。
      `@ffi.require()` → `@provider.BrowserProvider::require()`、
      `@endor.request_accounts` → `@provider.request_accounts`、
      `@ffi.spawn` → `@js.spawn`。import すべき package も明記。
      **一時パッケージを作って実際にコンパイルを通して検証した**
      (escape hatch の例も同様に検証済み)。
- [x] C-2. README の Layout 表を修正 (`endor/ffi` → `endor/ffi/js`、
      provider の面は root ではなく `endor/provider`、root は型の re-export のみ)。
- [x] C-3. すべての `///` doc comment を修正
      (`provider/error.mbt` `eth.mbt` `mock.mbt` `provider.mbt`)。
- [x] C-4. 存在しない `@ffi.MetaMaskProvider` への言及を `BrowserProvider` に修正。
- [x] C-5. `AGENTS.md` の Layout も実態に合わせた (`cmd/main` は存在しない、
      `ffi/` は `ffi/js/`、`provider/` の記載が無かった)。

## D. doc の例がテストされていない

- 51 テスト = 手書き `test` ブロックの数と完全一致 (types 32 + provider 19)。
- 検証済み: doc comment の ` ```moonbit ` ブロックにわざと落ちる `inspect` を
  入れても 51 passed のまま。`README.mbt.md` に壊れたブロックを足しても同じ。
  `moon test README.mbt.md` は `no test entry found`。
- つまり C の間違いは CI では永久に検出されない。今回は一時パッケージを作って
  手で照合した。

- [x] D-1. C の修正を実物と照合 (コンパイルさせて確認)。
- [ ] D-2. markdown テスト / doc テストを CI で走らせる方法を調べて有効化する。
      `moon test` に `--doc-index` があるので機構自体は存在するが、この構成では
      拾われていない。有効化できれば README の例が二度と腐らない。

## E. パッケージング — 未着手 (公開前にやるべき)

- [ ] E-1. `supported_targets = "js"` の宣言が無い。`moon check --target wasm-gc`
      は `ffi/js` 由来で 4 errors。`ffi/js/moon.pkg` と `provider/moon.pkg` に
      package 単位で宣言する (`mizchi/js_browser` が同じやり方)。
      module 全体に付けると root/types のバックエンド非依存が無駄になるので付けない。
- [ ] E-2. 配布 zip に余計なものが入っている (計 50 ファイル)。
      `examples/` (独自 `moon.mod` 付き、`mizchi/luna` 等を要求する入れ子モジュール)、
      `moon.work`、`justfile`、`AGENTS.md`、空の `docs/movie/` まで同梱。
      `moon.mod` の `exclude` で除外する。

## F. 公開範囲 — 決定: 読み取り専用として公開

- [x] F-1. 0.1.0 は読み取り専用として出す。README に「v0.1.0 is read-only」の
      注意書き、対応済みメソッドの表、未実装 (送金 / 署名 / チェーン切替 /
      イベント) の一覧、および未対応メソッドへの逃げ道として
      `Provider::request` の使い方を記載。`AGENTS.md` の説明も現状に合わせた。

## G. 設計ドキュメントが消えている

- [ ] G-1. `logic.md` (レイヤ構成・FFI 方針・エラーマッピング・v0.1〜v0.5 の
      マイルストーン) が **どのブランチのどのコミットにも無く**、作業ツリーにも
      無い。復元するか、無いものとして扱うかを決める。
      なお `AGENTS.md` から `logic.md` への参照は今回の修正で外した。

## H. 残り

- [ ] H-1. **README が `./docs/movie/demo.gif` を参照しているがファイルが無い。**
      `docs/movie/` は空。このままだと GitHub と mooncakes で画像が壊れて見える。
      デモを録るか、リンクを外す。
- [ ] H-2. リリース自動化: tag push → Actions で `moon publish`。
      認証は `~/.moon/credentials.json` (`{"token", "username"}`) を secret から書き出す。
- [ ] H-3. `CHANGELOG.md`、README のバッジ。
- [ ] H-4. 最終ゲートとして `moon publish --dry-run` をもう一度通す。

---

## 残りの進め方

1. H-1 (デモ画像) — 公開の顔なので最優先
2. E-1 / E-2 (配布物を綺麗にする)
3. A-5 push → H-4 dry-run → `moon publish`
4. 余力で D-2, G, H-2, H-3
