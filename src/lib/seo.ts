import { defaultLocale, localeCodes, type LocaleCode } from '../i18n/locales';

export const officialSite = 'https://molayer.tech';

export type HreflangLink = {
  hrefLang: string;
  href: string;
};

export function cleanBaseUrl(baseUrl: string) {
  return baseUrl.replace(/\/+$/, '');
}

export function siteBase(site?: URL | string | null) {
  return site ? cleanBaseUrl(site.toString()) : officialSite;
}

function normalizePath(path: string) {
  const bare = path.split('?')[0].split('#')[0] || '/';
  const withLeading = bare.startsWith('/') ? bare : `/${bare}`;
  return withLeading.endsWith('/') ? withLeading : `${withLeading}/`;
}

export function localizedPath(locale: LocaleCode, path: string) {
  const normalized = normalizePath(path);
  return `/${locale}${normalized}`;
}

export function canonicalUrl(baseUrl: string, locale: LocaleCode, path: string) {
  return `${cleanBaseUrl(baseUrl)}${localizedPath(locale, path)}`;
}

export function buildHreflangLinks(baseUrl: string, path: string, availableLocales: LocaleCode[] = [...localeCodes]): HreflangLink[] {
  const uniqueLocales = [...new Set(availableLocales)];
  const links = uniqueLocales.map((locale) => ({
    hrefLang: locale,
    href: canonicalUrl(baseUrl, locale, path)
  }));

  links.push({
    hrefLang: 'x-default',
    href: canonicalUrl(baseUrl, uniqueLocales.includes(defaultLocale) ? defaultLocale : uniqueLocales[0], path)
  });

  return links;
}

export function absoluteUrl(baseUrl: string, path: string) {
  return `${cleanBaseUrl(baseUrl)}${normalizePath(path)}`;
}
