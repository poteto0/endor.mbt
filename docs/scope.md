# Scope

**Moved to <https://endor.poteto-mahiro.com/reference/>.**

What `poteto0/endor` wraps used to be maintained here as one long file. It is now
the reference section of the documentation site, split by area — and, more to the
point, its examples are compiled by CI (`just docs-check`) rather than being prose
nobody checks. Two examples in this file were wrong by the time it was split.

| Was here                        | Is now                                                    |
| ------------------------------- | --------------------------------------------------------- |
| the whole wrapped surface       | <https://endor.poteto-mahiro.com/reference/>               |
| reads, calls, gas estimation    | <https://endor.poteto-mahiro.com/reference/reads/>         |
| `send_transaction`, fees, waits | <https://endor.poteto-mahiro.com/reference/writes/>        |
| chain switching                 | <https://endor.poteto-mahiro.com/reference/chains/>        |
| message and typed-data signing  | <https://endor.poteto-mahiro.com/reference/signing/>       |
| provider events                 | <https://endor.poteto-mahiro.com/reference/events/>        |
| ABI, `Contract`, `Erc20`        | <https://endor.poteto-mahiro.com/reference/abi/>           |
| `Provider::request`             | <https://endor.poteto-mahiro.com/reference/escape-hatch/>  |
| "planned, not implemented yet"  | <https://endor.poteto-mahiro.com/reference/not-wrapped/>   |
| the error types                 | <https://endor.poteto-mahiro.com/guide/errors/>            |

The site's source is [`website/`](../website/) and how to work on it is
[`website.md`](website.md). `just docs-dev` serves it locally.

The files here that are notes rather than documentation stay:
[`roadmap.md`](roadmap.md), [`e2e.md`](e2e.md) and [`website.md`](website.md).
