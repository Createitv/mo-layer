export const siteUrl = "https://inklayer.app";
export const appStoreUrl = "https://apps.apple.com/app/id6772853639";

export const locales = ["en", "zh-cn", "zh-tw", "ja", "ko", "es", "fr", "de"] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = "en";

export const localeLabels: Record<Locale, string> = {
  en: "English",
  "zh-cn": "简体中文",
  "zh-tw": "繁體中文",
  ja: "日本語",
  ko: "한국어",
  es: "Español",
  fr: "Français",
  de: "Deutsch"
};

export const localeCodes: Record<Locale, string> = {
  en: "en",
  "zh-cn": "zh-CN",
  "zh-tw": "zh-TW",
  ja: "ja",
  ko: "ko",
  es: "es",
  fr: "fr",
  de: "de"
};

export const screenshots = [
  {
    src: "/assets/screenshots/vault-home.png",
    alt: "Encrypted photo and file organizer overview"
  },
  {
    src: "/assets/screenshots/import-flow.png",
    alt: "Secure import screen for photos, files, camera, and scans"
  },
  {
    src: "/assets/screenshots/import-options.png",
    alt: "Encrypted import options and original cleanup choices"
  },
  {
    src: "/assets/screenshots/photo-picker.png",
    alt: "Photo selection interface before secure import"
  }
] as const;

type Feature = {
  slug: string;
  eyebrow: string;
  title: string;
  short: string;
  detail: string;
};

type FaqItem = {
  question: string;
  answer: string;
};

export type PageCopy = {
  appName: string;
  nav: {
    features: string;
    security: string;
    faq: string;
    download: string;
  };
  seo: {
    title: string;
    description: string;
    keywords: string[];
  };
  hero: {
    eyebrow: string;
    title: string;
    lead: string;
    primary: string;
    secondary: string;
    note: string;
  };
  proof: string[];
  sections: {
    featuresTitle: string;
    featuresLead: string;
    securityTitle: string;
    securityLead: string;
    screenshotsTitle: string;
    downloadTitle: string;
    downloadLead: string;
    qrLabel: string;
    faqTitle: string;
  };
  features: Feature[];
  securityPoints: Feature[];
  faq: FaqItem[];
  footer: {
    tagline: string;
    privacy: string;
    terms: string;
  };
};

const featureSlugs = ["private-photo-organizer", "secure-file-organizer", "decoy-space", "icloud-encrypted-sync"] as const;

const enFeatures: Feature[] = [
  {
    slug: featureSlugs[0],
    eyebrow: "Photos and videos",
    title: "Organize private photos without making privacy obvious",
    short: "Import photos and videos into a quieter personal space with albums, recents, favorites, and recovery.",
    detail: "Aegis Vault Safe keeps the workflow practical: select from Photos, import from camera, review recent imports, and manage sensitive media without turning the app into a loud secret-album billboard."
  },
  {
    slug: featureSlugs[1],
    eyebrow: "Files and documents",
    title: "Keep IDs, contracts, scans, and files together",
    short: "Store screenshots, PDFs, contracts, documents, links, and local files in one secure organizer.",
    detail: "The product is designed for more than photos. It gives users a private place for the documents they actually need to keep close: identity photos, invoices, contracts, project files, and archived screenshots."
  },
  {
    slug: featureSlugs[2],
    eyebrow: "Low-profile access",
    title: "A believable front door and a realistic backup space",
    short: "The app can feel like a normal file cabinet first, with a separate decoy space for wrong input.",
    detail: "A privacy app should not announce itself every time it opens. The website presents this as a professional low-profile workspace instead of sensational disguise language."
  },
  {
    slug: featureSlugs[3],
    eyebrow: "Recovery",
    title: "Optional iCloud encrypted sync for device changes",
    short: "Sync encrypted content through iCloud when users want recovery and multi-device continuity.",
    detail: "The copy stays careful: iCloud sync is optional, content is encrypted before upload, and the developer does not hold the decryption key."
  }
];

const enSecurity: Feature[] = [
  {
    slug: "local-first",
    eyebrow: "Local first",
    title: "Private content starts on the device",
    short: "Imported content is protected locally by default.",
    detail: "The site makes the storage model understandable without overpromising absolute security."
  },
  {
    slug: "encrypted-sync",
    eyebrow: "Encrypted sync",
    title: "iCloud sync uses encrypted content",
    short: "When enabled, sync moves ciphertext rather than readable personal files.",
    detail: "This is central for trust, especially for a privacy-focused app."
  },
  {
    slug: "no-ad-tracking",
    eyebrow: "No ad posture",
    title: "Built for private utility, not attention capture",
    short: "The marketing avoids ad-tech language and keeps the privacy story calm.",
    detail: "The site should feel like a serious product, not a fear-based landing page."
  }
];

const enFaq: FaqItem[] = [
  {
    question: "What can I store in the app?",
    answer: "Photos, videos, screenshots, IDs, contracts, PDFs, scanned files, links, and other important personal documents."
  },
  {
    question: "Does the app upload my files to your server?",
    answer: "Personal content stays on your device by default. If iCloud sync is enabled, encrypted content is synced through iCloud."
  },
  {
    question: "Is this only a photo vault?",
    answer: "No. It is positioned as a private photo and file organizer for the personal material people actually need to manage."
  },
  {
    question: "Can I download it with a QR code?",
    answer: "Yes. Scan the QR code on the website or use the App Store button to open the App Store page directly."
  }
];

const localeCopy: Record<Locale, Partial<PageCopy>> = {
  en: {},
  "zh-cn": {
    appName: "墨层",
    nav: { features: "功能", security: "安全", faq: "常见问题", download: "下载" },
    seo: {
      title: "墨层 - 私人资料管理与照片文件安全整理",
      description: "墨层是一款面向 iPhone 的私人资料管理 App，用于安全整理照片、视频、证件、合同、截图和重要文件，支持低调入口、备用空间与 iCloud 密文同步。",
      keywords: ["私人资料管理", "私密照片整理", "文件安全整理", "隐藏相册", "照片保险箱", "iPhone 文件管理"]
    },
    hero: {
      eyebrow: "私人资料管理 · iPhone App",
      title: "把照片、证件、合同和重要文件，放进更低调的个人空间。",
      lead: "墨层不是吵闹的“秘密相册”。它更像一个克制的文件整理工具，用于保存照片、视频、证件、合同、截图和重要文件，并在需要时提供低调入口与备用空间。",
      primary: "在 App Store 下载",
      secondary: "查看核心功能",
      note: "扫码或点击按钮即可打开 App Store"
    },
    proof: ["照片与视频安全整理", "证件合同集中保存", "可选 iCloud 密文同步", "低调入口与备用空间"],
    sections: {
      featuresTitle: "适合长期使用的私人资料管理",
      featuresLead: "重点不是制造紧张感，而是让敏感内容有一个稳定、清晰、可恢复的地方。",
      securityTitle: "把安全说清楚，而不是说过头",
      securityLead: "官网文案会突出本地优先、密文同步、开发者不持有解密密钥这些用户能理解的安全边界。",
      screenshotsTitle: "真实 App 界面",
      downloadTitle: "扫码下载墨层",
      downloadLead: "用 iPhone 扫描二维码，或点击 App Store 按钮打开下载页。",
      qrLabel: "App Store 二维码",
      faqTitle: "常见问题"
    },
    features: [
      { slug: featureSlugs[0], eyebrow: "照片与视频", title: "整理私密照片，但不把隐私写在脸上", short: "导入照片和视频后，通过相册、最近导入、收藏和回收站进行管理。", detail: "墨层的重点是长期可用的整理流程，而不是只做一个锁屏。用户可以从系统相册、相机和分享入口导入内容，再在 App 内安全管理。" },
      { slug: featureSlugs[1], eyebrow: "文件与证件", title: "证件、合同、扫描件和截图放在一起", short: "把身份证件、发票、合同、PDF、链接和重要截图整理到同一个空间。", detail: "很多隐私内容不是照片，而是文件。官网会明确覆盖证件、合同、扫描件和项目文件这些高意图搜索场景。" },
      { slug: featureSlugs[2], eyebrow: "低调入口", title: "表面像文件柜，内部是私人空间", short: "默认呈现更低调的文件整理语义，并支持备用空间应对误输入场景。", detail: "页面不使用低质的“防查岗”表达，而是用专业方式说明低调入口和备用空间的价值。" },
      { slug: featureSlugs[3], eyebrow: "恢复与同步", title: "可选 iCloud 密文同步", short: "需要换机和恢复时，可启用 iCloud 密文同步。", detail: "同步内容会先加密后再上传，开发者不持有解密密钥。这个点会在安全页和结构化数据中反复强化。" }
    ],
    securityPoints: [
      { slug: "local-first", eyebrow: "本地优先", title: "个人内容默认保存在设备中", short: "导入内容先在本机保护，不默认上传到自建服务器。", detail: "这有利于建立用户信任，也能降低隐私产品常见的疑虑。" },
      { slug: "encrypted-sync", eyebrow: "密文同步", title: "开启 iCloud 时同步的是密文", short: "用于换机恢复和多设备连续使用。", detail: "文案保持准确，不承诺无法验证的绝对安全。" },
      { slug: "calm-privacy", eyebrow: "克制表达", title: "隐私产品不需要恐吓式营销", short: "网站会用专业、安静、可信的方式说明功能。", detail: "这会让页面更像成熟 App，而不是灰产工具。" }
    ],
    faq: [
      { question: "墨层可以保存什么？", answer: "可以保存照片、视频、截图、证件、合同、PDF、扫描件、链接和其他重要文件。" },
      { question: "我的文件会上传到开发者服务器吗？", answer: "个人内容默认保存在设备中。启用 iCloud 同步时，同步的是加密后的内容。" },
      { question: "它只是私密相册吗？", answer: "不是。定位是私人资料管理，既包含照片视频，也包含证件、合同和文件。" },
      { question: "可以扫码下载吗？", answer: "可以。页面上的二维码会直接打开 App Store 下载页。" }
    ],
    footer: { tagline: "低调、清晰、可恢复的私人资料管理。", privacy: "隐私政策", terms: "使用条款" }
  },
  "zh-tw": {
    appName: "墨層",
    nav: { features: "功能", security: "安全", faq: "常見問題", download: "下載" },
    seo: {
      title: "墨層 - 私人資料管理與照片檔案安全整理",
      description: "墨層是一款 iPhone 私人資料管理 App，用於整理照片、影片、證件、合約、截圖與重要檔案，支援低調入口、備用空間與 iCloud 密文同步。",
      keywords: ["私人資料管理", "私密照片整理", "檔案安全整理", "隱藏相簿", "照片保險箱", "iPhone 檔案管理"]
    },
    hero: {
      eyebrow: "私人資料管理 · iPhone App",
      title: "把照片、證件、合約與重要檔案，放進更低調的個人空間。",
      lead: "墨層更像一個克制的檔案整理工具，用於保存照片、影片、證件、合約、截圖與重要檔案，並在需要時提供低調入口與備用空間。",
      primary: "在 App Store 下載",
      secondary: "查看核心功能",
      note: "掃碼或點擊按鈕即可打開 App Store"
    },
    sections: {
      featuresTitle: "適合長期使用的私人資料管理",
      featuresLead: "讓敏感內容有一個穩定、清晰、可恢復的地方。",
      securityTitle: "把安全說清楚，而不是說過頭",
      securityLead: "突出本機優先、密文同步、開發者不持有解密金鑰。",
      screenshotsTitle: "真實 App 介面",
      downloadTitle: "掃碼下載墨層",
      downloadLead: "用 iPhone 掃描 QR code，或點擊 App Store 按鈕。",
      qrLabel: "App Store QR code",
      faqTitle: "常見問題"
    }
  },
  ja: {
    appName: "Aegis保管庫",
    seo: {
      title: "Aegis保管庫 - 写真と書類を安全に整理するiPhoneアプリ",
      description: "Aegis保管庫は、写真、動画、身分証、契約書、スクリーンショット、重要ファイルを静かに整理するためのiPhone向けプライベートオーガナイザーです。",
      keywords: ["写真非表示", "秘密アルバム", "写真ロック", "書類保管", "iCloud同期"]
    },
    hero: {
      eyebrow: "Private organizer for iPhone",
      title: "写真、書類、契約書を静かに整理できる個人スペース。",
      lead: "Aegis保管庫は、写真とファイルを目立たず管理するためのアプリです。重要な内容を実用的な整理画面で扱えます。",
      primary: "App Storeで見る",
      secondary: "機能を見る",
      note: "QRコードからApp Storeを開けます"
    }
  },
  ko: {
    appName: "Aegis 보관함",
    seo: {
      title: "Aegis 보관함 - 사진과 파일을 안전하게 정리하는 iPhone 앱",
      description: "Aegis 보관함은 사진, 동영상, 신분증, 계약서, 스크린샷, 중요한 파일을 조용하고 안전하게 정리하는 iPhone용 개인 자료 관리 앱입니다.",
      keywords: ["사진숨기기", "비밀앨범", "사진잠금", "문서보관", "iCloud동기화"]
    },
    hero: {
      eyebrow: "Private organizer for iPhone",
      title: "사진, 문서, 계약서를 조용하게 정리하는 개인 공간.",
      lead: "Aegis 보관함은 민감한 사진과 파일을 더 전문적인 방식으로 정리하도록 설계된 iPhone 앱입니다.",
      primary: "App Store에서 보기",
      secondary: "기능 보기",
      note: "QR 코드를 스캔해 App Store를 열 수 있습니다"
    }
  },
  es: {
    appName: "Archivo Aegis",
    seo: {
      title: "Archivo Aegis - Organizador privado de fotos y archivos para iPhone",
      description: "Archivo Aegis ayuda a organizar fotos, videos, documentos, contratos, capturas y archivos importantes en un espacio personal discreto para iPhone.",
      keywords: ["ocultar fotos", "album secreto", "archivos privados", "documentos seguros", "iCloud"]
    },
    hero: {
      eyebrow: "Organizador privado para iPhone",
      title: "Fotos, documentos y contratos en un espacio personal más discreto.",
      lead: "Archivo Aegis organiza fotos, videos y archivos importantes con una experiencia profesional, clara y preparada para recuperación.",
      primary: "Ver en App Store",
      secondary: "Explorar funciones",
      note: "Escanee el código QR para abrir App Store"
    }
  },
  fr: {
    appName: "Coffre Aegis",
    seo: {
      title: "Coffre Aegis - Organiseur privé de photos et fichiers pour iPhone",
      description: "Coffre Aegis organise photos, vidéos, pièces d'identité, contrats, captures et fichiers importants dans un espace personnel discret sur iPhone.",
      keywords: ["album caché", "photos secrètes", "fichiers privés", "documents sécurisés", "iCloud"]
    },
    hero: {
      eyebrow: "Organiseur privé pour iPhone",
      title: "Photos, documents et contrats dans un espace personnel plus discret.",
      lead: "Coffre Aegis aide à organiser les contenus importants avec une interface calme, professionnelle et adaptée à la récupération.",
      primary: "Voir sur l'App Store",
      secondary: "Découvrir les fonctions",
      note: "Scannez le QR code pour ouvrir l'App Store"
    }
  },
  de: {
    appName: "Aegis Tresor",
    seo: {
      title: "Aegis Tresor - Privater Foto- und Datei-Organizer für iPhone",
      description: "Aegis Tresor organisiert Fotos, Videos, Ausweise, Verträge, Screenshots und wichtige Dateien in einem diskreten persönlichen Bereich auf dem iPhone.",
      keywords: ["fotos verstecken", "geheime fotos", "private dateien", "dokumente sichern", "iCloud"]
    },
    hero: {
      eyebrow: "Privater Organizer für iPhone",
      title: "Fotos, Dokumente und Verträge in einem diskreten persönlichen Bereich.",
      lead: "Aegis Tresor organisiert wichtige Inhalte mit einer ruhigen, professionellen Oberfläche und optionaler verschlüsselter iCloud-Synchronisierung.",
      primary: "Im App Store ansehen",
      secondary: "Funktionen ansehen",
      note: "Scannen Sie den QR-Code, um den App Store zu öffnen"
    }
  }
};

const base: PageCopy = {
  appName: "Aegis Vault Safe",
  nav: { features: "Features", security: "Security", faq: "FAQ", download: "Download" },
  seo: {
    title: "Aegis Vault Safe - Private Photo and File Organizer for iPhone",
    description: "Aegis Vault Safe is a discreet iPhone app for organizing private photos, videos, IDs, contracts, screenshots, and important files with optional encrypted iCloud sync.",
    keywords: ["private photo organizer", "secure file organizer", "secret album", "photo vault", "hidden files", "iCloud encrypted sync"]
  },
  hero: {
    eyebrow: "Private organizer for iPhone",
    title: "A calmer place for private photos, documents, contracts, and files.",
    lead: "Aegis Vault Safe presents sensitive material as a refined personal archive: import photos, videos, IDs, contracts, screenshots, and files into a low-profile workspace built for everyday use.",
    primary: "Download on the App Store",
    secondary: "Explore features",
    note: "Scan the QR code or open the App Store page."
  },
  proof: ["Private photos and videos", "IDs, contracts, and scans", "Optional encrypted iCloud sync", "Low-profile workspace"],
  sections: {
    featuresTitle: "Built like a serious personal archive",
    featuresLead: "The site positions the app as a durable private organizer, not a noisy secret-album gimmick.",
    securityTitle: "Security language that users can trust",
    securityLead: "The website explains local-first storage, encrypted sync, and recovery without making absolute claims.",
    screenshotsTitle: "Real app screens",
    downloadTitle: "Scan to download",
    downloadLead: "Open the App Store page with your iPhone camera or use the direct download button.",
    qrLabel: "App Store QR code",
    faqTitle: "Questions"
  },
  features: enFeatures,
  securityPoints: enSecurity,
  faq: enFaq,
  footer: {
    tagline: "Private photo and file organization, designed to stay calm.",
    privacy: "Privacy Policy",
    terms: "Terms"
  }
};

function mergeCopy(locale: Locale): PageCopy {
  const override = localeCopy[locale] || {};
  return {
    ...base,
    ...override,
    nav: { ...base.nav, ...override.nav },
    seo: { ...base.seo, ...override.seo },
    hero: { ...base.hero, ...override.hero },
    sections: { ...base.sections, ...override.sections },
    footer: { ...base.footer, ...override.footer },
    proof: override.proof || base.proof,
    features: override.features || base.features,
    securityPoints: override.securityPoints || base.securityPoints,
    faq: override.faq || base.faq
  };
}

export const pages: Record<Locale, PageCopy> = Object.fromEntries(
  locales.map((locale) => [locale, mergeCopy(locale)])
) as Record<Locale, PageCopy>;

export function localePath(locale: Locale, path = "") {
  const clean = path.replace(/^\/+/, "");
  return `/${locale}/${clean}`.replace(/\/?$/, "/");
}

export function getAlternates(path = "") {
  return Object.fromEntries(locales.map((locale) => [localeCodes[locale], `${siteUrl}${localePath(locale, path)}`]));
}

export function getFeature(locale: Locale, slug: string) {
  return pages[locale].features.find((feature) => feature.slug === slug);
}

export const legalUrls = {
  privacy: "https://lesuire.notion.site/35aa4ace94c780d4a86adfb45664c87f",
  terms: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
};
