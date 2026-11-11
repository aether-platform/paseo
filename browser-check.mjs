import { createRequire } from "node:module";
const require = createRequire("/home/kaz/work/cc-paseo-basepath/paseo/package.json");
const { chromium } = require("playwright");
const [url, shot] = process.argv.slice(2);
const browser = await chromium.launch({ executablePath: process.env.CHROME_BIN, args: process.env.HOST_RULES ? [`--host-resolver-rules=${process.env.HOST_RULES}`] : [] });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
const failed = [];
const sockets = [];
page.on("response", (r) => { if (r.status() >= 400) failed.push(`${r.status()} ${r.url()}`); });
page.on("requestfailed", (r) => failed.push(`FAILED ${r.url()} ${r.failure()?.errorText}`));
page.on("websocket", (ws) => {
  const entry = { url: ws.url(), framesReceived: 0, closed: false };
  sockets.push(entry);
  ws.on("framereceived", () => entry.framesReceived++);
  ws.on("close", () => (entry.closed = true));
});
const consoleErrors = [];
page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text().slice(0, 200)); });
await page.goto(url, { waitUntil: "load" });
await page.waitForTimeout(12000);
await page.screenshot({ path: shot });
console.log(JSON.stringify({
  finalUrl: page.url(),
  title: await page.title(),
  sockets,
  failed,
  consoleErrors: consoleErrors.slice(0, 10),
  bodyText: (await page.locator("body").innerText()).slice(0, 400),
}, null, 2));
await browser.close();
