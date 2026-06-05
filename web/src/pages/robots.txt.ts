import type { APIRoute } from 'astro';
import { siteBase } from '../lib/seo';

export const GET: APIRoute = ({ site }) => {
  const base = siteBase(site);
  return new Response(`User-agent: OAI-SearchBot
Allow: /

User-agent: ChatGPT-User
Allow: /

User-agent: PerplexityBot
Allow: /

User-agent: Perplexity-User
Allow: /

User-agent: Claude-SearchBot
Allow: /

User-agent: Claude-User
Allow: /

User-agent: Googlebot
Allow: /

User-agent: *
Allow: /

Sitemap: ${base}/sitemap.xml
`, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' }
  });
};
