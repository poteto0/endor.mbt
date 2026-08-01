/*
 * Screenshots of the built site, for looking at the design without deploying it.
 *
 *   node shot.mjs dist-docs /cookbook/connect/ out.png [dark]
 *
 * Not part of any check — `smoke.mjs` is what CI runs. This is a viewer.
 */
import { chromium } from 'playwright'
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'

const [root = 'dist-docs', url = '/', out = 'shot.png', mode = 'light'] =
  process.argv.slice(2)
const TYPES = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
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
await new Promise((done) => server.listen(8098, done))

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } })
await page.goto(`http://localhost:8098${url}`, { waitUntil: 'networkidle' })
if (mode === 'dark') {
  await page.evaluate(() => document.documentElement.classList.add('dark'))
  await page.waitForTimeout(200)
}
await page.screenshot({ path: out, fullPage: false })
await browser.close()
server.close()
console.log(`wrote ${out}`)
