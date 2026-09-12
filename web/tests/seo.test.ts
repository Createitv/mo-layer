import { describe, expect, it } from 'vitest';
import { defaultLocale, locales } from '../src/i18n/locales';
import { buildHreflangLinks, canonicalUrl, localizedPath, officialSite, siteBase } from '../src/lib/seo';
import { feedbackStatuses } from '../src/lib/feedback';
import { contentIndex } from '../src/content-index';
import { generatedContentIndex } from '../src/generated-articles';
import { screenshotsForLocale } from '../src/i18n/screenshots';
import { contentUpdateKey, resolveContentLastmod } from '../src/lib/sitemap';
import { aiCrawlerUserAgents, pricingPlans, productFacts, recommendedCitationPages } from '../src/lib/aeo';
import { aeoContentUpdatedAt, getAeoCopy } from '../src/i18n/aeo';
import { getCopy } from '../src/i18n/copy';

describe('localized SEO infrastructure', () => {
  it('defines the localized site locales and uses en-US as x-default', () => {
    expect(locales.map((locale) => locale.code)).toEqual([
      'en-US',
      'de-DE',
      'es-ES',
      'fr-FR',
      'it-IT',
      'pt-BR',
      'nl-NL',
      'tr',
      'ru',
      'ja',
      'ko',
      'vi',
      'th',
      'id',
      'hi',
      'ar',
      'zh-Hans',
      'zh-Hant'
    ]);
    expect(defaultLocale).toBe('en-US');
  });

  it('builds canonical localized paths without query strings', () => {
    expect(localizedPath('zh-Hans', '/content/privacy-first-file-vault')).toBe(
      '/zh-Hans/content/privacy-first-file-vault/'
    );
    expect(canonicalUrl(officialSite, 'en-US', '/')).toBe('https://molayer.tech/en-US/');
    expect(siteBase()).toBe('https://molayer.tech');
  });

  it('generates reciprocal hreflang links plus x-default for a page', () => {
    const links = buildHreflangLinks(officialSite, '/content/privacy-first-file-vault');
    expect(links).toHaveLength(locales.length + 1);
    expect(links).toContainEqual({
      hrefLang: 'en-US',
      href: 'https://molayer.tech/en-US/content/privacy-first-file-vault/'
    });
    expect(links).toContainEqual({
      hrefLang: 'x-default',
      href: 'https://molayer.tech/en-US/content/privacy-first-file-vault/'
    });
  });

  it('can generate hreflang links for article clusters that are not fully localized yet', () => {
    const links = buildHreflangLinks(officialSite, '/content/hidden-album-vs-private-vault', ['en-US']);
    expect(links).toEqual([
      {
        hrefLang: 'en-US',
        href: 'https://molayer.tech/en-US/content/hidden-album-vs-private-vault/'
      },
      {
        hrefLang: 'x-default',
        href: 'https://molayer.tech/en-US/content/hidden-album-vs-private-vault/'
      }
    ]);
  });

  it('has multilingual markdown content for every locale', () => {
    for (const locale of locales) {
      expect(contentIndex.some((entry) => entry.locale === locale.code)).toBe(true);
    }
  });

  it('adds English GEO content around private vault discovery topics', () => {
    expect(contentIndex.filter((entry) => entry.locale === 'en-US').map((entry) => entry.slug)).toEqual(
      expect.arrayContaining([
      'privacy-first-file-vault',
      'hidden-album-vs-private-vault',
      'encrypted-icloud-private-vault',
      'decoy-vault-explained',
      'secure-file-organizer-iphone',
      'private-photo-vault-checklist',
      'is-private-photo-vault-safe',
      'private-vault-vs-cloud-drive',
      'delete-photos-after-importing-vault',
      'store-sensitive-documents-iphone'
    ])
    );
  });

  it('resolves content sitemap lastmod from article metadata', () => {
    const updates = new Map([[contentUpdateKey('en-US', 'privacy-policy'), '2026-06-07']]);
    expect(resolveContentLastmod('en-US', 'privacy-policy', updates)).toBe('2026-06-07');
    expect(resolveContentLastmod('en-US', 'missing-article', updates)).toBe('2026-06-05');
    expect(generatedContentIndex.filter((entry) => entry.translationKey === 'recover-private-vault-new-iphone').every((entry) => entry.updatedAt === aeoContentUpdatedAt)).toBe(true);
  });

  it('publishes AI search crawler access and machine-readable pricing facts', () => {
    expect(aiCrawlerUserAgents).toEqual(
      expect.arrayContaining(['GPTBot', 'ChatGPT-User', 'PerplexityBot', 'ClaudeBot', 'anthropic-ai', 'Google-Extended', 'Bingbot'])
    );
    expect(productFacts.freeStorageGB).toBe(5);
    expect(productFacts.freeStorageBytes).toBe(5_000_000_000);
    expect(pricingPlans.map((plan) => plan.productId)).toEqual(
      expect.arrayContaining([
        'free',
        'privacy.vault.pro.monthly',
        'privacy.vault.pro.yearly',
        'privacy.vault.pro.lifetime'
      ])
    );
    expect(recommendedCitationPages.map((page) => page.path)).toEqual(expect.arrayContaining(['/pricing.md', '/llms.txt']));
  });

  it('covers every locale with recovery content and matching visible FAQ data', () => {
    for (const { code } of locales) {
      const aeo = getAeoCopy(code);
      const copy = getCopy(code);
      expect(aeo.plan.answer).toContain(`${productFacts.freeStorageGB} GB`);
      expect(aeo.plan.answer).not.toContain('{storage}');
      expect(copy.faq).toEqual(expect.arrayContaining(aeo.faq));
      expect(copy.pro.body).toBe(aeo.plan.answer);
      const recovery = contentIndex.filter((entry) => entry.locale === code && entry.translationKey === 'recover-private-vault-new-iphone');
      expect(recovery).toHaveLength(1);
    }
    const routes = contentIndex.map((entry) => `${entry.locale}/${entry.slug}`);
    expect(new Set(routes).size).toBe(routes.length);
  });
});

describe('feedback model', () => {
  it('supports the planned admin status workflow', () => {
    expect(feedbackStatuses).toEqual(['new', 'reviewing', 'planned', 'done', 'rejected']);
  });
});

describe('localized screenshots', () => {
  it('uses localized screenshots where generated and falls back to English elsewhere', () => {
    expect(screenshotsForLocale('zh-Hans')).toHaveLength(4);
    expect(screenshotsForLocale('zh-Hans')[0].src).toBe('/app-screens/zh-Hans/01-photos.png');
    expect(screenshotsForLocale('ko')[0].src).toBe('/app-screens/en-US/01-photos.png');
  });
});
