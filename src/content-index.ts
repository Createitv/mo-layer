import type { LocaleCode } from './i18n/locales';

export type ContentIndexEntry = {
  locale: LocaleCode;
  slug: string;
  translationKey: string;
  title: string;
  description: string;
};

export const contentIndex: ContentIndexEntry[] = [
  {
    locale: 'en-US',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'What is a privacy-first file vault?',
    description: 'How Mo Layer protects photos, videos, screenshots, IDs, contracts, and private files.'
  },
  {
    locale: 'en-US',
    slug: 'hidden-album-vs-private-vault',
    translationKey: 'hidden-album-vs-private-vault',
    title: 'Hidden album vs private photo vault: what is the difference?',
    description: 'A practical comparison of hidden albums, locked albums, and private vault apps for iPhone.'
  },
  {
    locale: 'en-US',
    slug: 'encrypted-icloud-private-vault',
    translationKey: 'encrypted-icloud-private-vault',
    title: 'How encrypted iCloud sync works in a private vault',
    description: 'What encrypted iCloud recovery means, what Mo Layer uploads, and what stays unreadable.'
  },
  {
    locale: 'en-US',
    slug: 'decoy-vault-explained',
    translationKey: 'decoy-vault-explained',
    title: 'What is a decoy vault and when is it useful?',
    description: 'How a realistic decoy space helps a private vault stay discreet in everyday situations.'
  },
  {
    locale: 'en-US',
    slug: 'secure-file-organizer-iphone',
    translationKey: 'secure-file-organizer-iphone',
    title: 'Secure file organizer for iPhone: what to store and how to organize it',
    description: 'How to organize IDs, contracts, receipts, screenshots, videos, and sensitive files on iPhone.'
  },
  {
    locale: 'en-US',
    slug: 'private-photo-vault-checklist',
    translationKey: 'private-photo-vault-checklist',
    title: 'Private photo vault checklist before you trust an app',
    description: 'A checklist for local protection, encryption, recovery, decoy behavior, and subscription value.'
  },
  {
    locale: 'en-US',
    slug: 'is-private-photo-vault-safe',
    translationKey: 'is-private-photo-vault-safe',
    title: 'Is a private photo vault safe on iPhone?',
    description: 'A practical way to judge whether a private photo vault is safe enough for sensitive photos, videos, IDs, contracts, and screenshots.'
  },
  {
    locale: 'en-US',
    slug: 'private-vault-vs-cloud-drive',
    translationKey: 'private-vault-vs-cloud-drive',
    title: 'Private vault vs cloud drive: which should store sensitive files?',
    description: 'Compare private vault apps and cloud drives for storing sensitive photos, IDs, contracts, screenshots, receipts, and personal documents.'
  },
  {
    locale: 'en-US',
    slug: 'delete-photos-after-importing-vault',
    translationKey: 'delete-photos-after-importing-vault',
    title: 'Should you delete photos after importing them into a private vault?',
    description: 'How to think about deleting original photos after moving sensitive media into an iPhone private vault.'
  },
  {
    locale: 'en-US',
    slug: 'store-sensitive-documents-iphone',
    translationKey: 'store-sensitive-documents-iphone',
    title: 'How to store sensitive documents on iPhone',
    description: 'A practical guide for organizing IDs, contracts, receipts, screenshots, and private files on iPhone without mixing them into everyday albums.'
  },
  {
    locale: 'en-US',
    slug: 'private-screenshots-iphone',
    translationKey: 'private-screenshots-iphone',
    title: 'How to keep private screenshots safe on iPhone',
    description: 'Why screenshots often contain sensitive information and how to organize them in a private iPhone vault instead of leaving them in the camera roll.'
  },
  {
    locale: 'en-US',
    slug: 'id-photo-private-storage',
    translationKey: 'id-photo-private-storage',
    title: 'Where should you store ID photos on iPhone?',
    description: 'A privacy-focused guide to storing ID cards, passports, licenses, and document photos on iPhone without mixing them into everyday albums.'
  },
  {
    locale: 'en-US',
    slug: 'decoy-vault-use-cases',
    translationKey: 'decoy-vault-use-cases',
    title: 'When is a decoy vault useful?',
    description: 'Understand realistic decoy vault use cases and why discretion matters for private photo vault apps.'
  },
  {
    locale: 'en-US',
    slug: 'recover-private-vault-new-iphone',
    translationKey: 'recover-private-vault-new-iphone',
    title: 'How do you recover a private vault on a new iPhone?',
    description: 'What to check before relying on a private photo vault for device changes, encrypted iCloud recovery, and long-term private archives.'
  },
  {
    locale: 'de-DE',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Was ist ein datenschutzorientierter Dateitresor?',
    description: 'Wie Mo Layer Fotos, Videos, Screenshots, Ausweise, Verträge und private Dateien schützt.'
  },
  {
    locale: 'es-ES',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Qué es una caja fuerte privada de archivos',
    description: 'Cómo Mo Layer protege fotos, videos, capturas, documentos, contratos y archivos privados.'
  },
  {
    locale: 'fr-FR',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Qu’est-ce qu’un coffre-fort de fichiers privé ?',
    description: 'Comment Mo Layer protège photos, vidéos, captures, pièces d’identité, contrats et fichiers privés.'
  },
  {
    locale: 'it-IT',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Che cos’è un archivio privato per file?',
    description: 'Come Mo Layer protegge foto, video, screenshot, documenti, contratti e file privati.'
  },
  {
    locale: 'pt-BR',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'O que é um cofre de arquivos com foco em privacidade?',
    description: 'Como o Mo Layer protege fotos, vídeos, capturas, documentos, contratos e arquivos privados.'
  },
  {
    locale: 'nl-NL',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Wat is een privacygerichte bestandskluis?',
    description: 'Hoe Mo Layer foto’s, video’s, screenshots, ID’s, contracten en privébestanden beschermt.'
  },
  {
    locale: 'tr',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Gizlilik odaklı dosya kasası nedir?',
    description: 'Mo Layer fotoğrafları, videoları, ekran görüntülerini, kimlikleri, sözleşmeleri ve özel dosyaları nasıl korur.'
  },
  {
    locale: 'ru',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Что такое файловое хранилище с акцентом на приватность?',
    description: 'Как Mo Layer защищает фото, видео, скриншоты, документы, договоры и личные файлы.'
  },
  {
    locale: 'ja',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'プライバシー重視のファイル保管庫とは',
    description: 'Mo Layerが写真、動画、スクリーンショット、身分証、契約書、個人ファイルを保護する仕組み。'
  },
  {
    locale: 'ko',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: '개인정보 중심 파일 보관함이란?',
    description: 'Mo Layer가 사진, 동영상, 스크린샷, 신분증, 계약서, 개인 파일을 보호하는 방식.'
  },
  {
    locale: 'vi',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Kho tệp ưu tiên quyền riêng tư là gì?',
    description: 'Cách Mo Layer bảo vệ ảnh, video, ảnh chụp màn hình, giấy tờ, hợp đồng và tệp riêng tư.'
  },
  {
    locale: 'th',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'คลังไฟล์ที่ให้ความสำคัญกับความเป็นส่วนตัวคืออะไร',
    description: 'Mo Layer ปกป้องรูปภาพ วิดีโอ ภาพหน้าจอ เอกสาร สัญญา และไฟล์ส่วนตัวอย่างไร'
  },
  {
    locale: 'id',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'Apa itu brankas file yang mengutamakan privasi?',
    description: 'Cara Mo Layer melindungi foto, video, tangkapan layar, identitas, kontrak, dan file pribadi.'
  },
  {
    locale: 'hi',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'प्राइवेसी-फर्स्ट फाइल वॉल्ट क्या है?',
    description: 'Mo Layer फोटो, वीडियो, स्क्रीनशॉट, पहचान पत्र, अनुबंध और निजी फाइलों की सुरक्षा कैसे करता है।'
  },
  {
    locale: 'ar',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: 'ما خزنة الملفات التي تضع الخصوصية أولاً؟',
    description: 'كيف يحمي Mo Layer الصور والفيديو ولقطات الشاشة والوثائق والعقود والملفات الخاصة.'
  },
  {
    locale: 'zh-Hans',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: '什么是隐私优先的文件保险箱？',
    description: '墨层如何通过本地优先保护、可选 iCloud 密文同步和清晰分类来保护照片、视频、截图、证件、合同和私密文件。'
  },
  {
    locale: 'zh-Hans',
    slug: 'hidden-album-vs-private-vault',
    translationKey: 'hidden-album-vs-private-vault',
    title: '隐藏相册和私密保险箱有什么区别？',
    description: '对比 iPhone 隐藏相册、锁定相册和专门私密保险箱，说明哪些场景需要更完整的保护。'
  },
  {
    locale: 'zh-Hans',
    slug: 'private-photo-vault-checklist',
    translationKey: 'private-photo-vault-checklist',
    title: '选择 iPhone 私密相册前应该检查什么？',
    description: '从本地保护、加密同步、恢复能力、诱饵空间、订阅价值和隐私边界检查一款私密相册是否值得信任。'
  },
  {
    locale: 'zh-Hans',
    slug: 'iphone-private-photo-vault-safe',
    translationKey: 'is-private-photo-vault-safe',
    title: 'iPhone 私密相册安全吗？',
    description: '判断一款 iPhone 私密相册是否安全，应该看本地保护、密文同步、恢复能力、开发者边界和日常使用方式。'
  },
  {
    locale: 'zh-Hans',
    slug: 'encrypted-icloud-sync-explained',
    translationKey: 'encrypted-icloud-private-vault',
    title: 'iCloud 密文同步是什么意思？',
    description: '解释私密相册里的 iCloud 密文同步：它和普通云盘同步有什么不同，适合解决哪些换机和恢复问题。'
  },
  {
    locale: 'zh-Hans',
    slug: 'private-vault-vs-cloud-drive',
    translationKey: 'private-vault-vs-cloud-drive',
    title: '私密保险箱和云盘有什么区别？',
    description: '对比私密保险箱和普通云盘，说明照片、证件、合同、票据和敏感截图应该如何选择保存位置。'
  },
  {
    locale: 'zh-Hans',
    slug: 'delete-photos-after-importing-vault',
    translationKey: 'delete-photos-after-importing-vault',
    title: '导入私密相册后，要删除原相册里的照片吗？',
    description: '解释把照片导入私密保险箱后，是否应该删除公开相册里的原图，以及删除前应该检查什么。'
  },
  {
    locale: 'zh-Hans',
    slug: 'store-sensitive-documents-iphone',
    translationKey: 'store-sensitive-documents-iphone',
    title: '如何在 iPhone 上保存证件、合同和敏感文件？',
    description: '适合 iPhone 用户的敏感文件整理方法：把证件、合同、票据、截图和私密照片放进清晰的私人档案空间。'
  },
  {
    locale: 'zh-Hans',
    slug: 'private-screenshots-iphone',
    translationKey: 'private-screenshots-iphone',
    title: 'iPhone 上的敏感截图应该怎么保存？',
    description: '很多截图包含地址、验证码、合同、票据和私人聊天，应该从公开相册中分离出来，放进更清晰的私人空间。'
  },
  {
    locale: 'zh-Hans',
    slug: 'id-photo-private-storage',
    translationKey: 'id-photo-private-storage',
    title: '身份证、护照照片应该存在 iPhone 哪里？',
    description: '证件照、护照、驾照和文件扫描件不适合混在公开相册里，更适合放进专门的私密文件保险箱。'
  },
  {
    locale: 'zh-Hans',
    slug: 'decoy-vault-use-cases',
    translationKey: 'decoy-vault-use-cases',
    title: '诱饵空间有什么用？',
    description: '解释私密相册里的诱饵空间适合哪些日常场景，以及为什么低调体验也是隐私保护的一部分。'
  },
  {
    locale: 'zh-Hans',
    slug: 'recover-private-vault-new-iphone',
    translationKey: 'recover-private-vault-new-iphone',
    title: '换新 iPhone 后，私密保险箱怎么恢复？',
    description: '解释私密相册换机恢复前应该检查什么，包括密文同步、恢复路径、开发者边界和本地优先模式。'
  },
  {
    locale: 'zh-Hant',
    slug: 'privacy-first-file-vault',
    translationKey: 'privacy-first-file-vault',
    title: '什麼是隱私優先的檔案保險箱？',
    description: '墨層如何透過本機優先保護、可選 iCloud 密文同步與清晰分類來保護照片、影片、截圖、證件、合約與私密檔案。'
  }
];
