import type { APIRoute } from 'astro';
import { aiCrawlerUserAgents } from '../lib/aeo';
import { siteBase } from '../lib/seo';

export const GET: APIRoute = ({ site }) => {
  const base = siteBase(site);
  const allowBlocks = aiCrawlerUserAgents.map((agent) => `User-agent: ${agent}\nAllow: /`).join('\n\n');

  return new Response(`${allowBlocks}

User-agent: *
Allow: /

Sitemap: ${base}/sitemap.xml
`, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' }
  });
};
