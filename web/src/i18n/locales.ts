export const locales = [
  { code: 'en-US', lang: 'en', region: 'US', label: 'English', name: 'Mo Layer' },
  { code: 'de-DE', lang: 'de', region: 'DE', label: 'Deutsch', name: 'Mo Layer' },
  { code: 'es-ES', lang: 'es', region: 'ES', label: 'Español', name: 'Mo Layer' },
  { code: 'fr-FR', lang: 'fr', region: 'FR', label: 'Français', name: 'Mo Layer' },
  { code: 'it-IT', lang: 'it', region: 'IT', label: 'Italiano', name: 'Mo Layer' },
  { code: 'pt-BR', lang: 'pt', region: 'BR', label: 'Português', name: 'Mo Layer' },
  { code: 'nl-NL', lang: 'nl', region: 'NL', label: 'Nederlands', name: 'Mo Layer' },
  { code: 'tr', lang: 'tr', label: 'Türkçe', name: 'Mo Layer' },
  { code: 'ru', lang: 'ru', label: 'Русский', name: 'Mo Layer' },
  { code: 'ja', lang: 'ja', label: '日本語', name: 'Mo Layer' },
  { code: 'ko', lang: 'ko', label: '한국어', name: 'Mo Layer' },
  { code: 'vi', lang: 'vi', label: 'Tiếng Việt', name: 'Mo Layer' },
  { code: 'th', lang: 'th', label: 'ไทย', name: 'Mo Layer' },
  { code: 'id', lang: 'id', label: 'Bahasa Indonesia', name: 'Mo Layer' },
  { code: 'hi', lang: 'hi', label: 'हिन्दी', name: 'Mo Layer' },
  { code: 'ar', lang: 'ar', label: 'العربية', name: 'Mo Layer' },
  { code: 'zh-Hans', lang: 'zh-Hans', label: '简体中文', name: '墨层' },
  { code: 'zh-Hant', lang: 'zh-Hant', label: '繁體中文', name: '墨層' }
] as const;

export type LocaleCode = (typeof locales)[number]['code'];

export const defaultLocale: LocaleCode = 'en-US';

export const localeCodes = locales.map((locale) => locale.code);

export function isLocale(value: string | undefined): value is LocaleCode {
  return Boolean(value && localeCodes.includes(value as LocaleCode));
}

export function localeInfo(locale: LocaleCode) {
  return locales.find((item) => item.code === locale) ?? locales[0];
}
