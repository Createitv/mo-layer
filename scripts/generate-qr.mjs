import { mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import QRCode from "qrcode";

const appStoreUrl = "https://apps.apple.com/app/id6772853639";
const outDir = new URL("../public/images/", import.meta.url);
const outFile = new URL("app-store-qr.svg", outDir);

await mkdir(outDir, { recursive: true });
await QRCode.toFile(fileURLToPath(outFile), appStoreUrl, {
  type: "svg",
  margin: 1,
  width: 300,
  color: {
    dark: "#111111",
    light: "#ffffff"
  }
});
