export const defaultContentUpdatedAt = '2026-06-05';

export function contentUpdateKey(locale: string, slug: string) {
  return `${locale}/${slug}`;
}

export function resolveContentLastmod(locale: string, slug: string, updatesByKey: Map<string, string>) {
  return updatesByKey.get(contentUpdateKey(locale, slug)) ?? defaultContentUpdatedAt;
}
