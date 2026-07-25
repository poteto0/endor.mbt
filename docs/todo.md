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

## H. 残り

- [ ] H-2. リリース自動化: tag push → Actions で `moon publish`。
      認証は `~/.moon/credentials.json` (`{"token", "username"}`) を secret から書き出す。
- [ ] H-3. `CHANGELOG.md`、README のバッジ。
- [ ] H-4. 最終ゲートとして `moon publish --dry-run` をもう一度通す。

---

## 残りの進め方

1. H-1 (デモ画像) — 公開の顔なので最優先
2. push → H-4 dry-run → `moon publish`
3. 余力で D-2, H-2, H-3
