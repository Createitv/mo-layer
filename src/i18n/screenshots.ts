import type { LocaleCode } from './locales';

export type LocalizedScreenshot = {
  src: string;
  alt: string;
};

const enScreens: LocalizedScreenshot[] = [
  {
    src: '/app-screens/en-US/01-photos.png',
    alt: 'Mo Layer English App Store screenshot showing organized private photos'
  },
  {
    src: '/app-screens/en-US/02-videos.png',
    alt: 'Mo Layer English App Store screenshot showing private video vault'
  },
  {
    src: '/app-screens/en-US/03-private-space.png',
    alt: 'Mo Layer English App Store screenshot showing private space and decoy controls'
  }
];

const screenshots: Partial<Record<LocaleCode, LocalizedScreenshot[]>> = {
  'en-US': enScreens,
  'zh-Hans': [
    {
      src: '/app-screens/zh-Hans/01-photos.png',
      alt: '墨层简体中文 App Store 截图，展示私密照片管理'
    },
    {
      src: '/app-screens/zh-Hans/02-videos.png',
      alt: '墨层简体中文 App Store 截图，展示私密视频管理'
    },
    {
      src: '/app-screens/zh-Hans/03-audio.png',
      alt: '墨层简体中文 App Store 截图，展示私密音频管理'
    },
    {
      src: '/app-screens/zh-Hans/04-files.png',
      alt: '墨层简体中文 App Store 截图，展示私密文件管理'
    }
  ]
};

export function screenshotsForLocale(locale: LocaleCode): LocalizedScreenshot[] {
  return screenshots[locale] ?? enScreens;
}
