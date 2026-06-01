import { defineConfig } from "astro/config";

const site = process.env.SITE_URL || "https://inklayer.app";

export default defineConfig({
  site,
  output: "static",
  trailingSlash: "always"
});
