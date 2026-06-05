import { defineConfig } from 'astro/config';

const site = process.env.PUBLIC_SITE_URL || 'https://molayer.tech';

export default defineConfig({
  site,
  output: 'static'
});
