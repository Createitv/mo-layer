import { localePath, locales, pages, siteUrl } from "@/data/site";

const staticPaths = ["", "security", "faq"];

function urlEntry(path: string) {
  return `  <url>
    <loc>${siteUrl}${path}</loc>
    <changefreq>weekly</changefreq>
    <priority>${path.split("/").length <= 3 ? "0.9" : "0.7"}</priority>
  </url>`;
}

export function GET() {
  const urls = locales.flatMap((locale) => [
    ...staticPaths.map((path) => localePath(locale, path)),
    ...pages[locale].features.map((feature) => localePath(locale, `features/${feature.slug}`))
  ]);

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map(urlEntry).join("\n")}
</urlset>`;

  return new Response(xml, {
    headers: {
      "Content-Type": "application/xml; charset=utf-8"
    }
  });
}
