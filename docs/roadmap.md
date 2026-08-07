# Roadmap

`poteto0/endor` がどこへ向かうかと、次に何をやるか。個々の作業は
[GitHub issues](https://github.com/poteto0/endor.mbt/issues) 側で追う。
このファイルはその上位の枠組み — なぜその順番なのか — を書いておく場所。

何が実装済みで何がそうでないかの正確な一覧はドキュメントサイトの
[Reference](https://endor.poteto-mahiro.com/reference/) にある。未実装のものは
[Not wrapped yet](https://endor.poteto-mahiro.com/reference/not-wrapped/)。

## 長期: v1.0 — 「MoonBit で dapp が書ける」

|         | 目標                                                                                                                                                                                         | issue                                                 |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **L1**  | コントラクト層 — ABI encode/decode、型付き contract call、ERC-20 プリセット、ログのデコード（済）／残りは ERC-721                                                                            | [#18](https://github.com/poteto0/endor.mbt/issues/18) |
| **L1'** | ABI からのプリセット生成 — `abi/codegen` と `endor-cli abi`。**実験的、進行中**: 安全に型付けできるものだけを生成し、それ以外は「生成しない」と名指しでスキップする。安定 API とは見なさない | [#48](https://github.com/poteto0/endor.mbt/issues/48) |
| **L2**  | トランスポート抽象 — HTTP JSON-RPC を `Provider` の別実装として追加し、ブラウザ非依存にする                                                                                                  | [#19](https://github.com/poteto0/endor.mbt/issues/19) |
| **L3**  | ドキュメント / クックブック、semver ポリシー確立                                                                                                                                             | [#20](https://github.com/poteto0/endor.mbt/issues/20) |

L1 が SDK の価値の中心で、L2 は「何がコアか」を決める。この2つは独立に見えて、
どちらも同じ問いに触る: **`Provider` trait はどこまで背負うのか**。
ブラウザ injection を「トランスポートの一実装」に降格できれば、typed helper と
`types/` が真のコアになる。

UI ライブラリへの統合は長期目標に**含めない**。`mizchi/luna` は
`examples/demo/` という独立モジュール内だけの依存であり、SDK 本体は
`moonbitlang/async` 以外に依存しない（`moon.mod` の `exclude` コメント参照）。
リアクティブに使いたい要求は、イベント API をプレーンなコールバック +
unsubscribe ハンドルとして公開することで満たす — 購読側でラップできる形にする、
という [#16](https://github.com/poteto0/endor.mbt/issues/16) の設計制約に落ちる。

## 中期: v0.2〜v0.4 — 「実際に使える」

読み取り専用では「繋いで残高を見る」までしかできない。ここを埋めるのが中期。

|        | 目標                                                                         | issue                                                 |
| ------ | ---------------------------------------------------------------------------- | ----------------------------------------------------- |
| **M1** | `eth_call` / `eth_estimateGas`                                               | [#9](https://github.com/poteto0/endor.mbt/issues/9)   |
| **M2** | `eth_sendTransaction` + `TransactionRequest` / `TxHash` 型                   | [#10](https://github.com/poteto0/endor.mbt/issues/10) |
| **M3** | ブロック / レシート + `wait_for_receipt`（済）                               | [#11](https://github.com/poteto0/endor.mbt/issues/11) |
| **M4** | メッセージ署名 — `personal_sign`、`eth_signTypedData_v4`（済）               | [#14](https://github.com/poteto0/endor.mbt/issues/14) |
| **M5** | チェーン切替 — 4902 → `addEthereumChain` フォールバックまで含めて包む        | [#15](https://github.com/poteto0/endor.mbt/issues/15) |
| **M6** | プロバイダイベント — `accountsChanged` / `chainChanged` / `disconnect`（済） | [#16](https://github.com/poteto0/endor.mbt/issues/16) |
| **M7** | EIP-6963 — 複数の injected provider を列挙する                               | [#17](https://github.com/poteto0/endor.mbt/issues/17) |

M1 を M2 より先に置いてあるのは意図的。`eth_call` は署名も承認 UI も要らないので
`MockProvider` だけで完結して検証でき、かつ L1 への足場になる。

## 短期: v0.1.0 を出し切る

|        | 目標                                                       | issue                                               |
| ------ | ---------------------------------------------------------- | --------------------------------------------------- |
| **S1** | `provider/` を backend-agnostic に戻す（publish 前に判断） | [#4](https://github.com/poteto0/endor.mbt/issues/4) |
| **S2** | `v0.1.0` タグを貼り直して mooncakes に publish             | [#5](https://github.com/poteto0/endor.mbt/issues/5) |
| **S3** | `CHANGELOG.md` と README バッジ                            | [#6](https://github.com/poteto0/endor.mbt/issues/6) |
| **S4** | リリース自動化: tag push → Actions で `moon publish`       | [#7](https://github.com/poteto0/endor.mbt/issues/7) |
| **S5** | doc / README の例を CI でテストする                        | [#8](https://github.com/poteto0/endor.mbt/issues/8) |

## 順番が効く課題

上の表に散っているが、**着手順そのものが重要**な4件を明示しておく。

**`provider/` の js ロック（[#4](https://github.com/poteto0/endor.mbt/issues/4)）** —
`provider/` 全体に `supported_targets = "js"` が付いているが、実際に `ffi/js` へ
触っているのは `browser_provider.mbt` 1ファイルだけ。typed helper も
`ProviderError` も、負う必要のない制約を負っている。publish 後にやると import パスの
破壊的変更になるので、**L2 を目標に入れるなら v0.1.0 を出す前に判断する**。

**keccak256（[#13](https://github.com/poteto0/endor.mbt/issues/13)）** —
決着済み: `crypto/` に MoonBit で自前実装（[#28](https://github.com/poteto0/endor.mbt/issues/28)）。
JS への FFI は選ばず、leaf パッケージに置いたので backend-agnostic のまま上の層から
使える。これに乗って EIP-55 チェックサム付きアドレスは
[#29](https://github.com/poteto0/endor.mbt/issues/29) で、関数セレクタとイベント
topic は L1 の `abi/` で入った。残りは EIP-712 の typed data hashing。

**イベントの FFI 設計（[#16](https://github.com/poteto0/endor.mbt/issues/16)）** —
JS コールバックの寿命と MoonBit async の橋渡しに加えて、「SDK が現在の account /
chain を保持するのか」まで決まってしまう論点だった。決着済み: **SDK はステートレス**
— account も chain もキャッシュせず、値はコールバックにだけ流す。API はプレーンな
コールバック + `Subscription` ハンドルで、UI ライブラリには依存しない。`Provider`
とは別の `EventSource` trait に切り、`ffi/js` は `eth.on` が返したラッパ関数を
`Listener` ハンドルとして持ち回って `removeListener` に同一参照を渡す。

**書き込みパスの検証手段（[#12](https://github.com/poteto0/endor.mbt/issues/12)）** —
決着済み: Anvil + 手動 QA の二段構え（[`docs/e2e.md`](./e2e.md)）。Anvil の dev
account はロック解除済み = ノード自身がウォレットなので、`globalThis.ethereum` を
Anvil へ転送する shim を挟めば `BrowserProvider` をそのまま e2e にかけられる
（`e2e/`、`just e2e`）。ヘッドレスウォレット（synpress 相当）は入れない —
承認 UI だけのために拡張機能ごと CI に載せる割に合わない。そこは
`docs/e2e.md` のリリース前チェックリストで人が踏む。M2 / M4 で書き込みを
足すときは、`e2e/` 側にも同じ操作を追加する。

## 推奨する着手順

```
S1 の判断 (#4)  — L2 をやるなら publish 前にリファクタ
 → S2 タグ貼り直し + publish (#5)
 → S3 CHANGELOG / バッジ、S4 リリース自動化
 → S5 doc テスト (#8)      — API を増やす前に腐り止めを入れる
 → M1 eth_call (#9)
 → 検証手段の決定 (#12) → M2 送金 (#10) + M3 receipt (#11)
 → keccak256 の方針決定 (#13) → M4 署名 (#14) → M5 チェーン切替 (#15)
 → イベント設計 (#16) → M7 EIP-6963 (#17)
 → L1 コントラクト層 (#18) — ABI と Contract / Erc20 まで入った
```

L2（[#19](https://github.com/poteto0/endor.mbt/issues/19)）と
L3（[#20](https://github.com/poteto0/endor.mbt/issues/20)）はこの直線には乗らない。
L2 は S1 の判断次第でいつでも始められ、L3 は公開 API が固まってから。
