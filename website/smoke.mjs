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
  ['/cookbook/events/', 'connect', 'Connect wallet'],
  ['/cookbook/send-eth/', 'send_eth', 'Send'],
  ['/cookbook/erc20/', 'token', 'Read the token'],
  ['/cookbook/switch-chain/', 'switch_chain', 'Sepolia'],
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
  res.writeHead(200, { 'content-type': TYPES[path.extname(file)] ?? 'application/octet-stream' })
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
  await page.goto(`http://localhost:${PORT}${url}`, { waitUntil: 'networkidle' })

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
    if (border === '0px') reasons.push('rendered unstyled (endor-demo.css missing?)')
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

await browser.close()
server.close()
if (failed > 0) {
  console.log(`\n${failed} of ${CASES.length} demo page(s) failed`)
  process.exit(1)
}
console.log(`\nok: ${CASES.length} demo pages hydrate`)
