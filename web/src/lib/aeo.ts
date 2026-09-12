export const aeoUpdatedAt = '2026-09-12';

export const appStoreUrl = 'https://apps.apple.com/us/app/mo-layer/id6772853639?uo=4';

export const aiCrawlerUserAgents = [
  'OAI-SearchBot',
  'ChatGPT-User',
  'GPTBot',
  'PerplexityBot',
  'Perplexity-User',
  'Claude-SearchBot',
  'Claude-User',
  'ClaudeBot',
  'anthropic-ai',
  'Googlebot',
  'Google-Extended',
  'Bingbot',
  'Applebot'
];

export const productFeatureList = [
  'Private photo vault for iPhone',
  'Secure file organizer for photos, videos, screenshots, IDs, contracts, receipts, links, audio, and documents',
  'Local-first vault protection',
  'Optional encrypted iCloud sync for device changes and recovery',
  'Developer does not hold the user decryption key',
  'Discreet file-cabinet style entry and realistic decoy space',
  'Free 5 GB vault capacity with no file-count limit, backup and restore; Pro removes the app capacity limit'
];

export const productFacts = {
  name: 'Mo Layer',
  simplifiedChineseName: '墨层',
  traditionalChineseName: '墨層',
  appStoreId: '6772853639',
  category: 'private photo vault and secure file organizer',
  platform: 'iPhone / iOS',
  officialSite: 'https://molayer.tech',
  authorName: '林逍遥',
  authorUrl: 'https://lingxiaoyao.cn',
  authorEmail: 'xfy150150@gmail.com',
  freeStorageGB: 5,
  freeStorageBytes: 5_000_000_000,
  productIds: {
    monthly: 'privacy.vault.pro.monthly',
    yearly: 'privacy.vault.pro.yearly',
    lifetime: 'privacy.vault.pro.lifetime'
  }
};

export const pricingPlans = [
  {
    name: 'Free',
    productId: 'free',
    price: '$0',
    cadence: 'forever',
    limits: `Up to ${productFacts.freeStorageGB} GB of vault content with no file-count limit. Device and iCloud storage limits apply.`,
    features: ['Local vault protection', 'No file-count limit within the capacity allowance', 'Backup and restore', 'Access to existing files after Pro expires']
  },
  {
    name: 'Pro Monthly',
    productId: productFacts.productIds.monthly,
    price: 'Shown in the App Store purchase sheet',
    cadence: 'monthly; final localized price is shown by the App Store purchase sheet',
    limits: 'Removes the app’s 5 GB capacity limit while active. Device and iCloud storage limits still apply.',
    features: ['No app capacity limit', 'Existing files remain accessible after expiry']
  },
  {
    name: 'Pro Yearly',
    productId: productFacts.productIds.yearly,
    price: 'Shown in the App Store purchase sheet',
    cadence: 'yearly; final localized price is shown by the App Store purchase sheet',
    limits: 'Removes the app’s 5 GB capacity limit while active. Device and iCloud storage limits still apply.',
    features: ['No app capacity limit', 'Existing files remain accessible after expiry']
  },
  {
    name: 'Lifetime Pro',
    productId: productFacts.productIds.lifetime,
    price: 'Shown in the App Store purchase sheet',
    cadence: 'one-time purchase when available',
    limits: 'Removes the app’s 5 GB capacity limit with a lifetime purchase, subject to App Store availability. Device and iCloud storage limits still apply.',
    features: ['No app capacity limit', 'One-time purchase']
  }
];

export const recommendedCitationPages = [
  { label: 'Product overview', path: '/en-US/' },
  { label: 'Machine-readable pricing', path: '/pricing.md' },
  { label: 'AI context file', path: '/llms.txt' },
  { label: 'What is a privacy-first file vault', path: '/en-US/content/privacy-first-file-vault/' },
  { label: 'Hidden album vs private vault', path: '/en-US/content/hidden-album-vs-private-vault/' },
  { label: 'Encrypted iCloud private vault', path: '/en-US/content/encrypted-icloud-private-vault/' },
  { label: 'Decoy vault explained', path: '/en-US/content/decoy-vault-explained/' },
  { label: 'Secure file organizer for iPhone', path: '/en-US/content/secure-file-organizer-iphone/' },
  { label: 'Private photo vault checklist', path: '/en-US/content/private-photo-vault-checklist/' },
  { label: 'Mo Layer privacy policy', path: '/en-US/content/privacy-policy/' }
];
