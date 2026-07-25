## D. doc の例がテストされていない

- 51 テスト = 手書き `test` ブロックの数と完全一致 (types 32 + provider 19)。
- 検証済み: doc comment の ` ```moonbit ` ブロックにわざと落ちる `inspect` を
  入れても 51 passed のまま。`README.mbt.md` に壊れたブロックを足しても同じ。
  `moon test README.mbt.md` は `no test entry found`。
- つまり C の間違いは CI では永久に検出されない。今回は一時パッケージを作って
  手で照合した。

- [ ] D-2. markdown テスト / doc テストを CI で走らせる方法を調べて有効化する。
      `moon test` に `--doc-index` があるので機構自体は存在するが、この構成では
      拾われていない。有効化できれば README の例が二度と腐らない。

## E. パッケージング — 完了

- [x] E-1. `ffi/js/moon.pkg` と `provider/moon.pkg` に `supported_targets = "js"`
      を宣言。`moon check --target wasm-gc` が通るようになった (js 限定パッケージは
      スキップされ、root と `types` だけがビルドされる)。module 全体には付けて
      いないので root/types のバックエンド非依存は保たれている。
- [x] E-2. `moon.mod` の `options(exclude: [...])` で
      `examples` / `moon.work` / `justfile` / `AGENTS.md` / `docs` を除外。
      配布 zip は 50 → 33 ファイル。`moon publish --dry-run` の
      「展開したパッケージに対する moon check」も通る。
      構文は `exclude = [...]` ではなく `options(exclude: [...])`
      (`moonbitlang/async` の moon.mod が実例)。
- [x] E-3. E-2 の副作用対応。`examples/` と `docs/` を除外したため README の
      相対リンクが配布物側で切れるので、デモ画像・example へのリンクを
      GitHub の絶対 URL に変更した。`justfile` も同梱されないため
      Development セクションにその旨を明記。

## H. 残り

- [ ] H-1. **README が参照するデモ画像がまだ存在しない。**
      リンク先は
      `https://raw.githubusercontent.com/poteto0/endor.mbt/main/docs/movie/demo.gif`
      で、`docs/movie/` は空。撮って push すれば表示される (docs/ は配布物からは
      除外済みなので、絶対 URL 経由で参照している)。

- [ ] H-2. リリース自動化: tag push → Actions で `moon publish`。
      認証は `~/.moon/credentials.json` (`{"token", "username"}`) を secret から書き出す。
- [ ] H-3. `CHANGELOG.md`、README のバッジ。
- [ ] H-4. 最終ゲートとして `moon publish --dry-run` をもう一度通す。

---

## 残りの進め方

1. H-1 (デモ画像) — 公開の顔なので最優先
2. push → H-4 dry-run → `moon publish`
3. 余力で D-2, H-2, H-3
