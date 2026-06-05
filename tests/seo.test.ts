import { describe, expect, it } from 'vitest';
import { defaultLocale, locales } from '../src/i18n/locales';
import { buildHreflangLinks, canonicalUrl, localizedPath, officialSite, siteBase } from '../src/lib/seo';
import { feedbackStatuses } from '../src/lib/feedback';
import { contentIndex } from '../src/content-index';
import { screenshotsForLocale } from '../src/i18n/screenshots';

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
