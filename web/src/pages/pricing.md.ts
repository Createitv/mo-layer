import type { APIRoute } from 'astro';
import { aeoUpdatedAt, appStoreUrl, pricingPlans, productFacts } from '../lib/aeo';
import { siteBase } from '../lib/seo';

export const GET: APIRoute = ({ site }) => {
  const base = siteBase(site);
  const planSections = pricingPlans
    .map(
      (plan) => `## ${plan.name}

- Product ID: ${plan.productId}
- Price: ${plan.price}
- Billing: ${plan.cadence}
- Limits: ${plan.limits}
- Features:
${plan.features.map((feature) => `  - ${feature}`).join('\n')}`
    )
    .join('\n\n');

  return new Response(
    `# Pricing — ${productFacts.name}

Last updated: ${aeoUpdatedAt}

${productFacts.name} is an iPhone private photo vault and secure file organizer. Pricing is handled through Apple's App Store purchase sheet, and localized final prices may vary by country, currency, tax, promotion, trial availability, and App Store configuration.

Official site: ${base}/
App Store: ${appStoreUrl}
App Store app ID: ${productFacts.appStoreId}

${planSections}

## Privacy and subscription boundary

- The website is not a web vault and does not upload, store, or process user private files.
- Private content is local-first by default.
- Optional iCloud sync uses encrypted content for device changes and recovery.
- The developer does not hold the user's decryption key.
- Deleting the app does not automatically cancel an active Apple subscription; users manage subscriptions in Apple ID settings.
`,
    {
      headers: { 'Content-Type': 'text/markdown; charset=utf-8' }
    }
  );
};
