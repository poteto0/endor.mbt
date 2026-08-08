/*
 * Does every live demo still come up?
 *
 * `just docs-check` proves the code blocks on the pages compile and
 * `just docs-islands` proves the demos compile, but neither proves the built
 * artifact is one the browser can hydrate: a wrong `link` format, an island
 * renamed out from under its `<Island name=…>`, a missing asset. Those fail
 * silently — the page renders, and the demo is simply not there.
 *
 * So: serve `dist-docs`, open each page that carries a demo, and require the
 * island to have replaced itself with real markup, styled, with nothing 404ing.
 * It drives no wallet — there is none in a headless browser, and every demo is
 * written to say so rather than to break.
 *
 *   node smoke.mjs dist-docs
 */
import { chromium } from 'playwright'
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'

const root = process.argv[2] ?? 'dist-docs'
const PORT = 8099

// Every page that embeds a demo, the island it embeds, and a string only the
// hydrated markup contains.
const CASES = [
  ['/', 'connect', 'Connect wallet'],
  ['/cookbook/connect/', 'connect', 'Connect wallet'],
  ['/cookbook/connect/', 'address_tool', 'to_checksum_string'],
  ['/cookbook/events/', 'connect', 'Connect wallet'],
  ['/cookbook/send-eth/', 'send_eth', 'Send'],
  ['/cookbook/send-eth/', 'units', 'smallest units'],
  ['/cookbook/erc20/', 'token', 'Read the token'],
  ['/cookbook/switch-chain/', 'switch_chain', 'Sepolia'],
  ['/cookbook/receipts/', 'receipt', 'Read the receipt'],
  ['/cookbook/sign/', 'sign', 'Sign it'],
  ['/cookbook/contract/', 'abi_tool', '@abi.selector'],
  ['/guide/errors/', 'address_tool', 'to_checksum_string'],
]

// The widgets that answer as you type. Each case is an input to put in the
// first box and the substring the first computed field must then contain — so
// this checks the demo is *reacting*, not merely present. A widget wired to a
// signal that nothing recomputes still renders perfectly.
const INTERACTIONS = [
  // one character of the checksum changed: EIP-55 catches it
  [
    '/cookbook/connect/',
    'address_tool',
    '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96046',
    'InvalidChecksum',
  ],
  // the all-lowercase form carries no checksum to fail
  [
    '/cookbook/connect/',
    'address_tool',
    '0xd8da6bf26964af9d7eed9e03e53415d37aa96045',
    'accepted',
  ],
  ['/cookbook/send-eth/', 'units', '1', '1000000000000000000'],
  // finer than a wei: refused rather than rounded
  ['/cookbook/send-eth/', 'units', '0.0000000000000000001', 'refused'],
]

const TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
}

const server = http.createServer((req, res) => {
  let file = path.join(root, decodeURIComponent(req.url.split('?')[0]))
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) {
    file = path.join(file, 'index.html')
  }
  if (!fs.existsSync(file)) {
    res.writeHead(404)
    res.end('not found')
    return
  }
  res.writeHead(200, {
    'content-type': TYPES[path.extname(file)] ?? 'application/octet-stream',
  })
  res.end(fs.readFileSync(file))
})
await new Promise((done) => server.listen(PORT, done))

const browser = await chromium.launch()
const page = await browser.newPage()
const problems = []
page.on('pageerror', (e) => problems.push(`uncaught: ${e}`))
page.on('response', (r) => {
  if (r.status() >= 400) problems.push(`${r.status()} ${r.url()}`)
})

let failed = 0
for (const [url, island, marker] of CASES) {
  problems.length = 0
  await page.goto(`http://localhost:${PORT}${url}`, {
    waitUntil: 'networkidle',
  })
  // half the demos hydrate on `visible`, and a headless viewport shows only the
  // top of the page — scroll the island into view before waiting for it
  await page
    .locator(island)
    .first()
    .scrollIntoViewIfNeeded()
    .catch(() => {})

  const reasons = []
  try {
    await page.waitForSelector(`${island} .endor-demo`, { timeout: 15_000 })
  } catch {
    reasons.push(`<${island}> never hydrated`)
  }
  if (reasons.length === 0) {
    const text = await page.textContent(`${island} .endor-demo`)
    if (!text.includes(marker)) reasons.push(`hydrated without "${marker}"`)
    // the demo's stylesheet is a separate asset from the island; a demo that
    // renders unstyled is a demo nobody can read
    const border = await page.evaluate(
      (sel) => getComputedStyle(document.querySelector(sel)).borderTopWidth,
      `${island} .endor-demo`,
    )
    if (border === '0px') reasons.push('rendered unstyled (endor.css missing?)')
  }
  reasons.push(...problems)

  if (reasons.length === 0) {
    console.log(`ok    ${url} (${island})`)
  } else {
    console.log(`FAIL  ${url} (${island})`)
    for (const reason of reasons) console.log(`        ${reason}`)
    failed++
  }
}

for (const [url, island, typed, expected] of INTERACTIONS) {
  await page.goto(`http://localhost:${PORT}${url}`, {
    waitUntil: 'networkidle',
  })
  const root = page.locator(island).first()
  await root.scrollIntoViewIfNeeded()
  await page.waitForSelector(`${island} .endor-demo`, { timeout: 15_000 })
  await root.locator('input').first().fill(typed)
  const field = root.locator('.endor-demo-value').first()
  let answer = ''
  try {
    await field.filter({ hasText: expected }).waitFor({ timeout: 5_000 })
  } catch {
    // fall through and report whatever it does say
  }
  answer = await field.textContent().catch(() => '(no field)')
  if (answer.includes(expected)) {
    console.log(`ok    ${island} "${typed.slice(0, 24)}" -> ${expected}`)
  } else {
    console.log(`FAIL  ${island} "${typed.slice(0, 24)}"`)
    console.log(`        expected "${expected}", answered "${answer.trim()}"`)
    failed++
  }
}

await browser.close()
server.close()
const total = CASES.length + INTERACTIONS.length
if (failed > 0) {
  console.log(`\n${failed} of ${total} check(s) failed`)
  process.exit(1)
}
console.log(
  `\nok: ${CASES.length} demo pages hydrate, ${INTERACTIONS.length} widgets answer`,
)
