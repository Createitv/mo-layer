import type { APIRoute } from 'astro';
import { contentIndex } from '../content-index';
import { defaultLocale, localeCodes, type LocaleCode } from '../i18n/locales';
import { buildHreflangLinks, canonicalUrl, siteBase, type HreflangLink } from '../lib/seo';

const staticPages = [
  { path: '/', updatedAt: '2026-06-05' },
  { path: '/content', updatedAt: '2026-06-05' }
];
const defaultContentUpdatedAt = '2026-06-05';

function renderUrlEntry(loc: string, updatedAt: string, hreflangLinks: HreflangLink[]) {
  const alternates = hreflangLinks
    .map((link) => `    <xhtml:link rel="alternate" hreflang="${link.hrefLang}" href="${link.href}" />`)
    .join('\n');

  return `  <url>
    <loc>${loc}</loc>
    <lastmod>${updatedAt}</lastmod>
${alternates}
  </url>`;
}

function urlEntry(base: string, locale: LocaleCode, path: string, updatedAt: string, availableLocales?: LocaleCode[]) {
  return renderUrlEntry(canonicalUrl(base, locale, path), updatedAt, buildHreflangLinks(base, path, availableLocales));
}

function articleHreflangLinks(base: string, translationKey: string) {
  const translatedArticles = contentIndex.filter((entry) => entry.translationKey === translationKey);
  const links = translatedArticles.map((entry) => ({
    hrefLang: entry.locale,
    href: canonicalUrl(base, entry.locale, `/content/${entry.slug}`)
  }));
  const defaultArticle = translatedArticles.find((entry) => entry.locale === defaultLocale) ?? translatedArticles[0];
  if (defaultArticle) {
    links.push({
      hrefLang: 'x-default',
      href: canonicalUrl(base, defaultArticle.locale, `/content/${defaultArticle.slug}`)
    });
  }
  return links;
}

export const GET: APIRoute = ({ site }) => {
  const base = siteBase(site);
  const entries: string[] = [];

  for (const locale of localeCodes) {
    for (const page of staticPages) {
      entries.push(urlEntry(base, locale, page.path, page.updatedAt));
    }
  }

  for (const item of contentIndex) {
    entries.push(
      renderUrlEntry(
        canonicalUrl(base, item.locale, `/content/${item.slug}`),
        defaultContentUpdatedAt,
        articleHreflangLinks(base, item.translationKey)
      )
    );
  }

  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${entries.join('\n')}
</urlset>
`,
    {
      headers: { 'Content-Type': 'application/xml; charset=utf-8' }
    }
  );
};
