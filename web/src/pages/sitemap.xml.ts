import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { contentIndex } from '../content-index';
import { generatedArticles } from '../generated-articles';
import { defaultLocale, localeCodes, type LocaleCode } from '../i18n/locales';
import { aeoUpdatedAt } from '../lib/aeo';
import { articleUpdatedAt } from '../i18n/aeo';
import { buildHreflangLinks, canonicalUrl, siteBase, type HreflangLink } from '../lib/seo';
import { contentUpdateKey, resolveContentLastmod } from '../lib/sitemap';

const staticPages = [
  { path: '/', updatedAt: aeoUpdatedAt },
  { path: '/content', updatedAt: aeoUpdatedAt }
];
const machineReadablePages = [
  { loc: '/llms.txt', updatedAt: aeoUpdatedAt },
  { loc: '/pricing.md', updatedAt: aeoUpdatedAt }
];
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

export const GET: APIRoute = async ({ site }) => {
  const base = siteBase(site);
  const entries: string[] = [];
  const markdownArticles = await getCollection('articles');
  const updatesByKey = new Map<string, string>();

  for (const article of markdownArticles) {
    updatesByKey.set(contentUpdateKey(article.data.locale, article.data.pageSlug), article.data.updatedAt);
  }
  for (const article of generatedArticles) {
    updatesByKey.set(contentUpdateKey(article.locale, article.slug), article.updatedAt);
  }

  for (const locale of localeCodes) {
    for (const page of staticPages) {
      entries.push(urlEntry(base, locale, page.path, page.updatedAt));
    }
  }

  for (const page of machineReadablePages) {
    entries.push(renderUrlEntry(`${base}${page.loc}`, page.updatedAt, []));
  }

  for (const item of contentIndex) {
    entries.push(
      renderUrlEntry(
        canonicalUrl(base, item.locale, `/content/${item.slug}`),
        articleUpdatedAt(item.locale, item.translationKey, item.updatedAt ?? resolveContentLastmod(item.locale, item.slug, updatesByKey)),
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
