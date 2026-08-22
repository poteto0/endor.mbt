# The documentation site

<https://endor.poteto-mahiro.com>, whose source is [`website/`](../website/).

Kept here rather than as `website/README.md` because astra renders every markdown
file it finds under the site root into a page, and its `exclude` list matches
directories only — a README in there would be published as `/README/`.

Rendered by [astra](https://mooncakes.io/docs/mizchi/astra), a static site
generator written in MoonBit, and deployed to Cloudflare Workers static assets as
the `endor-docs` worker.

## Layout

```
website/
  astra.config.json   nav, theme, footer, the islands directory
  page.json           the home page's front matter
  index.md            the home page
  00_guide/           install, design, errors, retries
  01_cookbook/        one page per task, each with a live demo
  02_reference/       what is wrapped, and what is not
  islands/            the demos — a MoonBit module (poteto0/endor-website-islands)
  public/             assets copied verbatim; islands/ under it is generated
  smoke.mjs           the check that the built demos hydrate

```

Numeric directory prefixes order the sidebar and are stripped from the URL:
`01_cookbook/02_send-eth.md` is served at `/cookbook/send-eth/`.

## The demos are MoonBit

`islands/` is a separate MoonBit module, for the same reason `examples/` is one:
the SDK's own `moon.mod` stays free of UI dependencies. Each package links as an
ES module exporting `hydrate`, which astra calls when the island comes on screen:

```
website/islands/connect/moon.pkg
  pkgtype(kind: "executable")
  options(link: { "js": { "exports": ["hydrate"], "format": "esm" } })
```

A page embeds one by naming it in its front matter and placing it in the body:

```markdown
---
islands:
  - connect
---

<Island name="connect" trigger="load" />
```

`moon.work` at the repository root lists this module, so the demos resolve
`poteto0/endor` from the working tree — what a reader clicks is the SDK as it is
now, not as the registry last published it.

`islands/ui` is shared UI and links no entry point, so it is not copied into
`public/islands/`.

### Two kinds of demo

The ones with a button drive the reader's wallet: `connect`, `send_eth`,
`token`, `switch_chain`, `sign`, `receipt`. They are placed at the top of the
page they belong to.

The ones that answer **as you type** — `address_tool`, `units`, `abi_tool` —
call functions that need no provider at all, so they need no wallet, no network
and no connection. They are built from `@ui.panel` and `@ui.computed`, which
recompute on every keystroke, and they are placed beside the paragraph they
illustrate rather than at the top: the point is that the description and the
behaviour are the same thing.

Prefer the second kind where the API allows it. It works for a reader who has no
wallet installed, which is most of them.

## Recipes

All of them live in the repository's `justfile` and run from its root:

```sh
just docs-dev      # build everything, serve website/dist-docs on localhost:7777
just docs-build    # build the demos, render the site into website/dist-docs
just docs-check    # compile every ```moonbit block on the site and in the README
just docs-smoke    # build, then check in a browser that the demos hydrate and answer
```

`docs-dev` serves the **built** tree rather than running `astra dev`. astra's dev
server renders pages but does not serve `public/`, so the stylesheet 404s and
every island 404s with it: the site comes up in astra's default colours with no
demos on it, which is a preview of nothing. The cost is a rebuild after each
edit.

`docs-check` runs as part of `just ci` and `just ci-check`, and out of
`just precommit` — the pre-commit hook — whenever a `.md` or a `.mbti` is
staged, those being the only two things that can move it. It needs only the
MoonBit toolchain. `docs-smoke` needs Node and a browser, so it runs in its own
CI job.

## Markup astra does not have

Two things look like they work and do not. `just docs-build` fails on both, but
it is quicker to know:

- **`:::` containers.** `::: warning … :::` is a VitePress convention; astra's
  markdown prints the fences as text. Raw HTML passes straight through, and
  astra's theme ships the classes — so a callout is:

  ```html
  <div class="alert alert--warning" role="note">
    <div class="alert__title">This one is real</div>
    <div class="alert__description">

  Blank lines around the body, so the markdown inside it is still markdown.

    </div>
  </div>
  ```

  The variants are `alert--warning`, `alert--error`, `alert--success` and
  `alert--status`.

- **HTML inside a config string.** `theme.footer.message` is escaped and comes
  out as its own source. Links belong in `theme.footer.links`.

## Adding a page

1. Write the markdown under the right numbered directory.
2. Tag MoonBit examples ` ```moonbit `. They will be compiled — a block that
   cannot compile on its own (a `fn main`, a fragment) is tagged
   ` ```moonbit no-check ` instead.
3. `just docs-check`.

The sidebar is `"sidebar": "auto"`, so nothing has to be registered.

## Adding a demo

1. `website/islands/<name>/` with a `moon.pkg` copied from an existing one and a
   `main.mbt` exporting `pub fn hydrate(el, _state)`.
2. Reference it from a page as above, using `<name>`.
3. Add the page to `CASES` in `smoke.mjs`. If the demo answers as you type, add
   an input and the answer it must give to `INTERACTIONS` as well — `CASES`
   only proves the widget rendered, and one wired to a signal nothing
   recomputes renders perfectly.
4. `just docs-smoke`.

Keep the SDK code in a demo shaped the way the page describes it — the demo is
the claim that the recipe works.

A widget with no button has nothing to say what it is, so `@ui.panel` takes a
title naming the call it makes and prints a `LIVE` chip beside it. Introduce it
in the prose with **Try it:** and one sentence on what to change and what will
happen — a box of inputs and values is not self-explanatory on a page of prose.

## Deploying

Pushes to `main` that touch `website/` (or the SDK packages the site is built
from) deploy through
[`.github/workflows/deploy-docs.yml`](../.github/workflows/deploy-docs.yml). It
needs two repository secrets:

| Secret                  | What                                                                   |
| ----------------------- | ---------------------------------------------------------------------- |
| `CLOUDFLARE_API_TOKEN`  | the "Edit Cloudflare Workers" template, scoped to the zone below        |
| `CLOUDFLARE_ACCOUNT_ID` | the account the worker lives in                                         |

By hand, from `website/`:

```sh
npx wrangler deploy --dry-run   # validate without publishing
npx wrangler deploy
```

### The custom domain

`wrangler.jsonc` declares `endor.poteto-mahiro.com` as a **custom domain** route.
Cloudflare provisions the DNS record and the certificate on the first deploy,
which means `poteto-mahiro.com` has to already be a zone on the same Cloudflare
account. Nothing has to be created in the dashboard first, and no CNAME has to be
added by hand — but a domain sitting at another registrar's nameservers will not
work.

The first deploy is therefore the one to watch: after it, `wrangler deployments
list` and a plain `curl -I https://endor.poteto-mahiro.com` are enough.
