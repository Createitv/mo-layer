import type { LocaleCode } from './locales';

type LandingCopy = {
  nav: { features: string; privacy: string; content: string; feedback: string; download: string };
  hero: { eyebrow: string; title: string; subtitle: string; primary: string; secondary: string };
  trust: string[];
  sections: Array<{ title: string; body: string }>;
  privacy: { title: string; body: string; steps: string[] };
  pro: { title: string; body: string; features: string[] };
  faq: Array<{ question: string; answer: string }>;
  feedback: { title: string; body: string };
  seo: { title: string; description: string };
  labels: {
    featureTitle: string;
    featureBody: string;
    contentTitle: string;
    contentBody: string;
    faqTitle: string;
    readContent: string;
    qrTitle: string;
    qrBody: string;
    galleryTitle: string;
    galleryBody: string;
  };
};

type CopyText = {
  nav: [string, string, string, string, string];
  hero: [string, string, string, string, string];
  trust: [string, string, string, string];
  sections: [[string, string], [string, string], [string, string]];
  privacy: [string, string, [string, string, string, string]];
  pro: [string, string, [string, string, string, string]];
  faq: [[string, string], [string, string], [string, string]];
  feedback: [string, string];
  seo: [string, string];
  labels: [string, string, string, string, string, string, string, string, string, string];
};

function copyFrom(text: CopyText): LandingCopy {
  return {
    nav: {
      features: text.nav[0],
      privacy: text.nav[1],
      content: text.nav[2],
      feedback: text.nav[3],
      download: text.nav[4]
    },
    hero: {
      eyebrow: text.hero[0],
      title: text.hero[1],
      subtitle: text.hero[2],
      primary: text.hero[3],
      secondary: text.hero[4]
    },
    trust: text.trust,
    sections: text.sections.map(([title, body]) => ({ title, body })),
    privacy: { title: text.privacy[0], body: text.privacy[1], steps: text.privacy[2] },
    pro: { title: text.pro[0], body: text.pro[1], features: text.pro[2] },
    faq: text.faq.map(([question, answer]) => ({ question, answer })),
    feedback: { title: text.feedback[0], body: text.feedback[1] },
    seo: { title: text.seo[0], description: text.seo[1] },
    labels: {
      featureTitle: text.labels[0],
      featureBody: text.labels[1],
      contentTitle: text.labels[2],
      contentBody: text.labels[3],
      faqTitle: text.labels[4],
      readContent: text.labels[5],
      qrTitle: text.labels[6],
      qrBody: text.labels[7],
      galleryTitle: text.labels[8],
      galleryBody: text.labels[9]
    }
  };
}

const localized: Record<LocaleCode, LandingCopy> = {
  'en-US': copyFrom({
    nav: ['Features', 'Privacy', 'Content', 'Feedback', 'Download'],
    hero: [
      'Quiet Secure Archive',
      'A private vault for photos, videos, and important files.',
      'Mo Layer keeps sensitive memories, IDs, contracts, screenshots, and files organized in a discreet encrypted space for iPhone.',
      'Download on the App Store',
      'How privacy works'
    ],
    trust: ['Local-first protection', 'Encrypted iCloud sync', 'No developer-held decryption key', 'No ads or tracking'],
    sections: [
      ['Organize sensitive media without mixing it into your public camera roll', 'Import photos, videos, screenshots, IDs, contracts, receipts, and files into a dedicated private archive.'],
      ['Find what matters quickly', 'Albums, recent imports, favorites, file categories, and clean visual grids keep private content usable.'],
      ['Stay discreet in everyday situations', 'A restrained file-tool experience, private gestures, and realistic decoy space help the app feel calm and practical.']
    ],
    privacy: ['Privacy explained in plain language', 'Your private content stays on your device by default. If you enable iCloud sync, Mo Layer uploads encrypted content for recovery and device changes.', ['Choose files', 'Encrypt locally', 'Sync ciphertext optionally', 'Recover with your own trusted Apple environment']],
    pro: ['Pro is for capacity, recovery, and control', 'Basic local protection stays available. Pro adds more space, batch organization, encrypted sync, decoy controls, intrusion records, and advanced recovery.', ['Unlimited imports', 'Batch organization', 'Encrypted iCloud sync', 'Advanced decoy controls']],
    faq: [
      ['Does Mo Layer upload readable private files?', 'No. The product is designed around local-first protection. Optional iCloud sync stores encrypted content, and the developer does not hold your decryption key.'],
      ['Is this only for photos?', 'No. Mo Layer is designed for photos, videos, screenshots, IDs, contracts, receipts, links, and important files.'],
      ['What is Pro for?', 'Pro unlocks capacity, batch workflows, encrypted sync, recovery tools, advanced disguise, and decoy controls. Basic local protection remains part of the app.']
    ],
    feedback: ['Tell us what to improve next', 'Request features, report issues, or explain what would make Mo Layer more useful for your private archive workflow.'],
    seo: ['Mo Layer - Private Photo Vault and Secure File Organizer', 'Mo Layer is a private photo vault and secure file organizer for iPhone, built for sensitive photos, videos, IDs, contracts, screenshots, and encrypted iCloud recovery.'],
    labels: ['Private content, kept orderly.', 'Mo Layer is designed for daily use: secure enough for sensitive files, calm enough to open without drama.', 'Content that explains the product clearly.', 'Markdown pages give search engines and AI answer engines direct, factual explanations of Mo Layer.', 'Questions people ask before trusting a private vault.', 'Read content', 'Scan to download', 'Open the App Store page directly on iPhone.', 'Real App Store screens, displayed at readable size.', 'These are full promotional screenshots from the real app folder, shown as product posters instead of squeezed phone mockups.']
  }),
  'zh-Hans': copyFrom({
    nav: ['功能', '隐私', '内容', '反馈', '下载'],
    hero: ['安静可信的私人档案室', '照片、视频和重要文件的私人保险箱', '墨层帮助你把照片、证件、合同、截图和文件整理到低调加密的 iPhone 私人空间。', '前往 App Store', '了解隐私保护'],
    trust: ['本地优先保护', 'iCloud 密文同步', '开发者不持有解密密钥', '无广告、无追踪'],
    sections: [['把敏感内容从公开相册中分离出来', '导入照片、视频、截图、证件、合同、票据和文件，建立专门的私人档案空间。'], ['重要内容更快找到', '通过相册、最近导入、收藏、文件分类和清晰网格，让私密内容仍然好用。'], ['日常场景保持低调', '克制的文件工具体验、私密手势和拟真的备用空间，让产品更自然、更可信。']],
    privacy: ['用普通语言解释隐私保护', '你的私人内容默认保存在设备中。启用 iCloud 同步时，墨层同步的是加密后的密文，用于换机和恢复。', ['选择文件', '本地加密', '可选同步密文', '通过你的 Apple 环境恢复']],
    pro: ['Pro 购买的是容量、恢复和管理能力', '基础本地保护保持可用。Pro 增加更多容量、批量整理、密文同步、诱饵控制、入侵记录和高级恢复。', ['无限导入', '批量整理', 'iCloud 密文同步', '高级诱饵控制']],
    faq: [['墨层会上传可读的私人文件吗？', '不会。产品以本地优先保护为核心。可选 iCloud 同步保存的是加密内容，开发者不持有解密密钥。'], ['它只适合照片吗？', '不是。墨层适合照片、视频、截图、证件、合同、票据、链接和重要文件。'], ['Pro 主要解锁什么？', 'Pro 解锁容量、批量流程、密文同步、恢复工具、高级伪装和诱饵控制。基础本地保护仍然保留。']],
    feedback: ['告诉我们下一步该改进什么', '提交功能建议、问题反馈，或说明你希望墨层怎样更适合你的私人档案流程。'],
    seo: ['墨层 - 私密相册与安全文件保险箱', '墨层是一款 iPhone 私密相册与安全文件整理工具，适合保护照片、视频、证件、合同、截图，并支持 iCloud 密文恢复。'],
    labels: ['私密内容，也应该清晰有序。', '墨层面向日常使用而设计：足够安全，可以保存敏感文件；足够克制，打开时不制造压力。', '用内容页把产品讲清楚。', 'Markdown 页面为搜索引擎和 AI 搜索提供直接、具体、可引用的产品说明。', '用户在信任私密保险箱前会问的问题。', '阅读内容', '扫码下载', '用 iPhone 扫描后直接打开 App Store 页面。', '真实审核截图，按可读尺寸展示。', '这些是来自真实 App 文件夹的完整宣传截图，现在作为产品海报展示，不再被压进小手机框里。']
  }),
  'zh-Hant': copyFrom({
    nav: ['功能', '隱私', '內容', '回饋', '下載'],
    hero: ['安靜可信的私人檔案室', '照片、影片與重要檔案的私人保險箱', '墨層幫助您將照片、證件、合約、截圖與檔案整理到低調加密的 iPhone 私人空間。', '前往 App Store', '了解隱私保護'],
    trust: ['本機優先保護', 'iCloud 密文同步', '開發者不持有解密金鑰', '無廣告、無追蹤'],
    sections: [['把敏感內容從公開相簿中分離出來', '匯入照片、影片、截圖、證件、合約、票據與檔案，建立專門的私人檔案空間。'], ['重要內容更快找到', '透過相簿、最近匯入、收藏、檔案分類與清晰網格，讓私密內容仍然好用。'], ['日常場景保持低調', '克制的檔案工具體驗、私密手勢與擬真的備用空間，讓產品更自然、更可信。']],
    privacy: ['用普通語言解釋隱私保護', '您的私人內容預設保存在裝置中。啟用 iCloud 同步時，墨層同步的是加密後的密文，用於換機與恢復。', ['選擇檔案', '本機加密', '可選同步密文', '透過您的 Apple 環境恢復']],
    pro: ['Pro 購買的是容量、恢復與管理能力', '基礎本機保護保持可用。Pro 增加更多容量、批次整理、密文同步、誘餌控制、入侵記錄與進階恢復。', ['無限匯入', '批次整理', 'iCloud 密文同步', '高級誘餌控制']],
    faq: [['墨層會上傳可讀的私人檔案嗎？', '不會。產品以本機優先保護為核心。可選 iCloud 同步保存的是加密內容，開發者不持有解密金鑰。'], ['它只適合照片嗎？', '不是。墨層適合照片、影片、截圖、證件、合約、票據、連結與重要檔案。'], ['Pro 主要解鎖什麼？', 'Pro 解鎖容量、批次流程、密文同步、恢復工具、高級偽裝與誘餌控制。基礎本機保護仍然保留。']],
    feedback: ['告訴我們下一步該改進什麼', '提交功能建議、問題回饋，或說明您希望墨層怎樣更適合您的私人檔案流程。'],
    seo: ['墨層 - 私密相簿與安全檔案保險箱', '墨層是一款 iPhone 私密相簿與安全檔案整理工具，適合保護照片、影片、證件、合約、截圖，並支援 iCloud 密文恢復。'],
    labels: ['私密內容，也應該清晰有序。', '墨層面向日常使用而設計：足夠安全，可以保存敏感檔案；足夠克制，開啟時不製造壓力。', '用內容頁把產品講清楚。', 'Markdown 頁面為搜尋引擎和 AI 搜尋提供直接、具體、可引用的產品說明。', '使用者在信任私密保險箱前會問的問題。', '閱讀內容', '掃碼下載', '用 iPhone 掃描後直接開啟 App Store 頁面。', '真實審核截圖，按可讀尺寸展示。', '這些是來自真實 App 資料夾的完整宣傳截圖，現在作為產品海報展示，不再被壓進小手機框裡。']
  }),
  'ko': copyFrom({
    nav: ['기능', '개인정보', '콘텐츠', '피드백', '다운로드'],
    hero: ['조용하고 안전한 개인 보관함', '사진, 동영상, 중요한 파일을 위한 개인 금고.', 'Mo Layer는 추억, 신분증, 계약서, 스크린샷, 파일을 iPhone의 은밀한 암호화 공간에 정리합니다.', 'App Store에서 다운로드', '개인정보 보호 방식'],
    trust: ['로컬 우선 보호', '암호화된 iCloud 동기화', '개발자가 복호화 키를 보유하지 않음', '광고와 추적 없음'],
    sections: [['민감한 미디어를 공개 사진 보관함과 분리', '사진, 동영상, 스크린샷, 신분증, 계약서, 영수증, 파일을 전용 개인 보관함으로 가져옵니다.'], ['중요한 항목을 빠르게 찾기', '앨범, 최근 가져오기, 즐겨찾기, 파일 카테고리, 깔끔한 그리드가 개인 콘텐츠를 사용하기 쉽게 유지합니다.'], ['일상에서 조용하게 사용', '절제된 파일 도구 경험, 개인 제스처, 현실적인 미끼 공간이 앱을 자연스럽고 실용적으로 만듭니다.']],
    privacy: ['쉬운 말로 설명하는 개인정보 보호', '개인 콘텐츠는 기본적으로 기기에 남아 있습니다. iCloud 동기화를 켜면 복구와 기기 변경을 위해 암호화된 콘텐츠만 업로드됩니다.', ['파일 선택', '기기에서 암호화', '필요할 때만 암호문 동기화', '신뢰하는 Apple 환경에서 복구']],
    pro: ['Pro는 용량, 복구, 제어를 위한 기능', '기본 로컬 보호는 계속 제공됩니다. Pro는 더 많은 공간, 일괄 정리, 암호화 동기화, 미끼 제어, 침입 기록, 고급 복구를 추가합니다.', ['무제한 가져오기', '일괄 정리', '암호화된 iCloud 동기화', '고급 미끼 제어']],
    faq: [['Mo Layer가 읽을 수 있는 개인 파일을 업로드하나요?', '아니요. 제품은 로컬 우선 보호를 중심으로 설계되었습니다. 선택적 iCloud 동기화는 암호화된 콘텐츠를 저장하며 개발자는 복호화 키를 보유하지 않습니다.'], ['사진 전용 앱인가요?', '아니요. 사진, 동영상, 스크린샷, 신분증, 계약서, 영수증, 링크, 중요한 파일에 맞게 설계되었습니다.'], ['Pro는 무엇을 위한 것인가요?', 'Pro는 용량, 일괄 작업, 암호화 동기화, 복구 도구, 고급 위장, 미끼 제어를 해제합니다. 기본 로컬 보호는 유지됩니다.']],
    feedback: ['다음 개선점을 알려주세요', '기능 요청, 문제 보고, 개인 보관 워크플로에 필요한 개선점을 알려주세요.'],
    seo: ['Mo Layer - 개인 사진 금고와 보안 파일 정리 도구', 'Mo Layer는 iPhone에서 민감한 사진, 동영상, 신분증, 계약서, 스크린샷과 암호화된 iCloud 복구를 위한 개인 사진 금고 및 보안 파일 정리 도구입니다.'],
    labels: ['개인 콘텐츠도 질서 있게.', 'Mo Layer는 일상 사용을 위해 설계되었습니다. 민감한 파일에는 충분히 안전하고, 열 때는 부담스럽지 않습니다.', '제품을 명확히 설명하는 콘텐츠.', 'Markdown 페이지는 검색 엔진과 AI 답변 엔진에 직접적이고 사실적인 설명을 제공합니다.', '개인 금고를 신뢰하기 전에 사람들이 묻는 질문.', '콘텐츠 읽기', '스캔하여 다운로드', 'iPhone에서 App Store 페이지를 바로 엽니다.', '읽기 좋은 크기의 실제 App Store 화면.', '실제 앱 폴더의 전체 홍보 스크린샷을 작은 휴대폰 프레임 대신 제품 포스터처럼 보여줍니다.']
  }),
  'ja': copyFrom({
    nav: ['機能', 'プライバシー', 'コンテンツ', 'フィードバック', 'ダウンロード'],
    hero: ['静かな安全アーカイブ', '写真、動画、大切なファイルのためのプライベート保管庫。', 'Mo Layerは思い出、身分証、契約書、スクリーンショット、ファイルをiPhone上の控えめな暗号化スペースに整理します。', 'App Storeでダウンロード', 'プライバシーの仕組み'],
    trust: ['ローカル優先の保護', '暗号化されたiCloud同期', '開発者は復号キーを保持しません', '広告や追跡なし'],
    sections: [['機密性の高いメディアを公開カメラロールから分離', '写真、動画、スクリーンショット、身分証、契約書、領収書、ファイルを専用のプライベートアーカイブに取り込めます。'], ['大切なものをすばやく見つける', 'アルバム、最近の読み込み、お気に入り、ファイル分類、見やすいグリッドで個人コンテンツを扱いやすく保ちます。'], ['日常でも目立たず使える', '控えめなファイルツール体験、プライベートジェスチャー、現実的なデコイスペースにより自然に使えます。']],
    privacy: ['わかりやすい言葉で説明するプライバシー', '個人コンテンツは標準でデバイスに保存されます。iCloud同期を有効にすると、復元や機種変更のために暗号化済みコンテンツだけをアップロードします。', ['ファイルを選ぶ', 'ローカルで暗号化', '必要に応じて暗号文を同期', '自分のApple環境で復元']],
    pro: ['Proは容量、復元、制御のために', '基本的なローカル保護は利用できます。Proでは容量、まとめ整理、暗号化同期、デコイ制御、侵入記録、高度な復元が追加されます。', ['無制限の読み込み', 'まとめ整理', '暗号化iCloud同期', '高度なデコイ制御']],
    faq: [['Mo Layerは読める状態の個人ファイルをアップロードしますか？', 'いいえ。ローカル優先の保護を中心に設計されています。任意のiCloud同期では暗号化済みコンテンツを保存し、開発者は復号キーを保持しません。'], ['写真専用ですか？', 'いいえ。写真、動画、スクリーンショット、身分証、契約書、領収書、リンク、重要なファイル向けです。'], ['Proは何のためですか？', 'Proは容量、まとめ作業、暗号化同期、復元ツール、高度な偽装、デコイ制御を解放します。基本的なローカル保護は残ります。']],
    feedback: ['次に改善すべきことを教えてください', '機能要望、不具合報告、またはプライベートアーカイブに必要な改善点を送ってください。'],
    seo: ['Mo Layer - 写真とファイルのプライベート保管庫', 'Mo LayerはiPhoneで写真、動画、身分証、契約書、スクリーンショット、個人ファイルを安全に整理し、暗号化されたiCloud復元を提供します。'],
    labels: ['個人コンテンツを整然と保管。', 'Mo Layerは日常利用のために設計されています。機密ファイルには十分安全で、開くときは静かです。', '製品を明確に説明するコンテンツ。', 'Markdownページは検索エンジンとAI回答エンジンに直接的で事実に基づく説明を提供します。', 'プライベート保管庫を信頼する前によくある質問。', 'コンテンツを読む', 'スキャンしてダウンロード', 'iPhoneでApp Storeページを直接開きます。', '読みやすいサイズで表示した実際のApp Store画面。', '実際のアプリフォルダのプロモーションスクリーンを、小さな端末枠ではなく製品ポスターとして表示します。']
  }),
  'de-DE': copyFrom({
    nav: ['Funktionen', 'Datenschutz', 'Inhalte', 'Feedback', 'Download'],
    hero: ['Ruhiges sicheres Archiv', 'Ein privater Tresor für Fotos, Videos und wichtige Dateien.', 'Mo Layer ordnet sensible Erinnerungen, Ausweise, Verträge, Screenshots und Dateien in einem diskreten verschlüsselten Bereich auf dem iPhone.', 'Im App Store laden', 'So funktioniert Datenschutz'],
    trust: ['Lokaler Schutz zuerst', 'Verschlüsselte iCloud-Synchronisierung', 'Kein Entwicklerschlüssel zur Entschlüsselung', 'Keine Werbung oder Nachverfolgung'],
    sections: [['Sensible Medien vom öffentlichen Kameraroll trennen', 'Importieren Sie Fotos, Videos, Screenshots, Ausweise, Verträge, Belege und Dateien in ein privates Archiv.'], ['Wichtiges schneller finden', 'Alben, letzte Importe, Favoriten, Dateikategorien und klare Raster halten private Inhalte nutzbar.'], ['Im Alltag diskret bleiben', 'Eine zurückhaltende Dateiwerkzeug-Oberfläche, private Gesten und ein realistischer Ersatzbereich sorgen für Ruhe und Alltagstauglichkeit.']],
    privacy: ['Datenschutz verständlich erklärt', 'Private Inhalte bleiben standardmäßig auf Ihrem Gerät. Bei aktivierter iCloud-Synchronisierung lädt Mo Layer verschlüsselte Inhalte für Wiederherstellung und Gerätewechsel hoch.', ['Dateien wählen', 'Lokal verschlüsseln', 'Optional Chiffretext synchronisieren', 'Mit Ihrer Apple-Umgebung wiederherstellen']],
    pro: ['Pro ist für Kapazität, Wiederherstellung und Kontrolle', 'Basisschutz lokal bleibt verfügbar. Pro ergänzt mehr Speicher, Stapelorganisation, verschlüsselte Synchronisierung, Ersatzbereich-Steuerung, Eindringlingsprotokolle und erweiterte Wiederherstellung.', ['Unbegrenzte Importe', 'Stapelorganisation', 'Verschlüsselte iCloud-Synchronisierung', 'Erweiterte Ersatzbereich-Steuerung']],
    faq: [['Lädt Mo Layer lesbare private Dateien hoch?', 'Nein. Das Produkt ist lokal ausgerichtet. Optionale iCloud-Synchronisierung speichert verschlüsselte Inhalte, und der Entwickler besitzt Ihren Entschlüsselungsschlüssel nicht.'], ['Ist es nur für Fotos?', 'Nein. Mo Layer ist für Fotos, Videos, Screenshots, Ausweise, Verträge, Belege, Links und wichtige Dateien gedacht.'], ['Wofür ist Pro?', 'Pro schaltet Kapazität, Stapelabläufe, verschlüsselte Synchronisierung, Wiederherstellung, erweiterte Tarnung und Ersatzbereich-Steuerung frei. Der lokale Basisschutz bleibt erhalten.']],
    feedback: ['Sagen Sie uns, was wir verbessern sollen', 'Senden Sie Funktionswünsche, melden Sie Probleme oder erklären Sie, was Mo Layer für Ihren privaten Archivablauf nützlicher macht.'],
    seo: ['Mo Layer - Privater Fototresor und sicherer Datei-Organizer', 'Mo Layer schützt Fotos, Videos, Ausweise, Verträge, Screenshots und Dateien auf dem iPhone mit lokaler Sicherheit und verschlüsselter iCloud-Wiederherstellung.'],
    labels: ['Private Inhalte, ordentlich aufbewahrt.', 'Mo Layer ist für den Alltag konzipiert: sicher genug für sensible Dateien und ruhig genug, um ohne Aufsehen geöffnet zu werden.', 'Inhalte, die das Produkt klar erklären.', 'Markdown-Seiten liefern Suchmaschinen und KI-Antwortsystemen direkte, sachliche Erklärungen zu Mo Layer.', 'Fragen vor dem Vertrauen in einen privaten Tresor.', 'Inhalt lesen', 'Zum Download scannen', 'Öffnet die App-Store-Seite direkt auf dem iPhone.', 'Echte App-Store-Bildschirme in lesbarer Größe.', 'Vollständige Werbescreens aus dem echten App-Ordner werden als Produktposter statt als kleine Telefonrahmen gezeigt.']
  }),
  'es-ES': copyFrom({
    nav: ['Funciones', 'Privacidad', 'Contenido', 'Comentarios', 'Descargar'],
    hero: ['Archivo seguro y discreto', 'Una caja fuerte privada para fotos, vídeos y archivos importantes.', 'Mo Layer organiza recuerdos sensibles, documentos, contratos, capturas y archivos en un espacio cifrado y discreto para iPhone.', 'Descargar en App Store', 'Cómo funciona la privacidad'],
    trust: ['Protección local primero', 'Sincronización iCloud cifrada', 'Sin clave de descifrado en manos del desarrollador', 'Sin anuncios ni seguimiento'],
    sections: [['Separe medios sensibles del carrete público', 'Importe fotos, vídeos, capturas, documentos, contratos, recibos y archivos en un archivo privado dedicado.'], ['Encuentre lo importante rápido', 'Álbumes, importaciones recientes, favoritos, categorías y cuadrículas limpias mantienen útil el contenido privado.'], ['Manténgase discreto en el día a día', 'Una experiencia sobria de herramienta de archivos, gestos privados y un espacio señuelo realista hacen que la app sea práctica y natural.']],
    privacy: ['Privacidad explicada con claridad', 'Su contenido privado permanece en el dispositivo de forma predeterminada. Si activa iCloud, Mo Layer sube contenido cifrado para recuperación y cambios de dispositivo.', ['Elegir archivos', 'Cifrar localmente', 'Sincronizar texto cifrado opcionalmente', 'Recuperar con su entorno Apple de confianza']],
    pro: ['Pro es capacidad, recuperación y control', 'La protección local básica sigue disponible. Pro añade más espacio, organización por lotes, sincronización cifrada, controles señuelo, registros de intrusión y recuperación avanzada.', ['Importaciones ilimitadas', 'Organización por lotes', 'Sincronización iCloud cifrada', 'Controles señuelo avanzados']],
    faq: [['¿Mo Layer sube archivos privados legibles?', 'No. El producto está diseñado con protección local primero. La sincronización iCloud opcional guarda contenido cifrado y el desarrollador no posee su clave de descifrado.'], ['¿Es solo para fotos?', 'No. Mo Layer sirve para fotos, vídeos, capturas, documentos, contratos, recibos, enlaces y archivos importantes.'], ['¿Para qué sirve Pro?', 'Pro desbloquea capacidad, flujos por lotes, sincronización cifrada, recuperación, disfraz avanzado y controles señuelo. La protección local básica continúa incluida.']],
    feedback: ['Díganos qué mejorar', 'Solicite funciones, informe problemas o explique qué haría Mo Layer más útil para su archivo privado.'],
    seo: ['Mo Layer - Caja fuerte privada de fotos y archivos', 'Mo Layer protege fotos, vídeos, documentos, contratos, capturas y archivos privados en iPhone con organización segura y recuperación cifrada.'],
    labels: ['Contenido privado, siempre ordenado.', 'Mo Layer está diseñado para el uso diario: seguro para archivos sensibles y discreto al abrirlo.', 'Contenido que explica claramente el producto.', 'Las páginas Markdown ofrecen explicaciones directas y objetivas para buscadores y motores de respuesta con IA.', 'Preguntas antes de confiar en una caja fuerte privada.', 'Leer contenido', 'Escanear para descargar', 'Abra la página de App Store directamente en iPhone.', 'Pantallas reales de App Store a tamaño legible.', 'Capturas promocionales completas de la carpeta real de la app, mostradas como pósteres de producto.']
  }),
  'fr-FR': copyFrom({
    nav: ['Fonctions', 'Confidentialité', 'Contenu', 'Retour', 'Télécharger'],
    hero: ['Archive sûre et discrète', 'Un coffre privé pour photos, vidéos et fichiers importants.', 'Mo Layer range souvenirs sensibles, pièces d’identité, contrats, captures et fichiers dans un espace chiffré discret sur iPhone.', 'Télécharger sur l’App Store', 'Comment la confidentialité fonctionne'],
    trust: ['Protection locale d’abord', 'Synchronisation iCloud chiffrée', 'Aucune clé de déchiffrement détenue par le développeur', 'Sans publicité ni suivi'],
    sections: [['Séparer les médias sensibles de la pellicule publique', 'Importez photos, vidéos, captures, pièces d’identité, contrats, reçus et fichiers dans une archive privée dédiée.'], ['Retrouver vite ce qui compte', 'Albums, imports récents, favoris, catégories et grilles claires gardent vos contenus privés faciles à utiliser.'], ['Rester discret au quotidien', 'Une interface sobre de gestion de fichiers, des gestes privés et un espace leurre réaliste rendent l’app calme et pratique.']],
    privacy: ['La confidentialité en mots simples', 'Vos contenus privés restent par défaut sur votre appareil. Si vous activez iCloud, Mo Layer téléverse des contenus chiffrés pour la récupération et les changements d’appareil.', ['Choisir les fichiers', 'Chiffrer localement', 'Synchroniser le texte chiffré si besoin', 'Récupérer avec votre environnement Apple de confiance']],
    pro: ['Pro apporte capacité, récupération et contrôle', 'La protection locale de base reste disponible. Pro ajoute plus d’espace, l’organisation par lots, la synchronisation chiffrée, les contrôles leurres, les journaux d’intrusion et la récupération avancée.', ['Imports illimités', 'Organisation par lots', 'Synchronisation iCloud chiffrée', 'Contrôles leurres avancés']],
    faq: [['Mo Layer téléverse-t-il des fichiers privés lisibles ?', 'Non. Le produit est conçu autour d’une protection locale. La synchronisation iCloud facultative stocke des contenus chiffrés, et le développeur ne détient pas votre clé de déchiffrement.'], ['Est-ce seulement pour les photos ?', 'Non. Mo Layer est conçu pour photos, vidéos, captures, pièces d’identité, contrats, reçus, liens et fichiers importants.'], ['À quoi sert Pro ?', 'Pro débloque la capacité, les actions par lots, la synchronisation chiffrée, les outils de récupération, le déguisement avancé et les contrôles leurres. La protection locale de base reste incluse.']],
    feedback: ['Dites-nous quoi améliorer', 'Demandez des fonctions, signalez des problèmes ou expliquez ce qui rendrait Mo Layer plus utile à votre archive privée.'],
    seo: ['Mo Layer - Coffre privé pour photos et fichiers', 'Mo Layer protège photos, vidéos, pièces d’identité, contrats, captures et fichiers privés sur iPhone avec récupération iCloud chiffrée.'],
    labels: ['Contenu privé, bien organisé.', 'Mo Layer est pensé pour le quotidien : assez sûr pour les fichiers sensibles, assez calme pour s’ouvrir sans attirer l’attention.', 'Un contenu qui explique clairement le produit.', 'Les pages Markdown donnent aux moteurs de recherche et aux réponses IA des explications directes et factuelles.', 'Questions avant de faire confiance à un coffre privé.', 'Lire le contenu', 'Scanner pour télécharger', 'Ouvrez directement la page App Store sur iPhone.', 'Vrais écrans App Store en taille lisible.', 'Captures promotionnelles complètes du dossier réel de l’app, affichées comme des affiches produit.']
  }),
  'it-IT': copyFrom({
    nav: ['Funzioni', 'Privacy', 'Contenuti', 'Feedback', 'Scarica'],
    hero: ['Archivio sicuro e discreto', 'Una cassaforte privata per foto, video e file importanti.', 'Mo Layer organizza ricordi sensibili, documenti, contratti, screenshot e file in uno spazio cifrato e discreto per iPhone.', 'Scarica da App Store', 'Come funziona la privacy'],
    trust: ['Protezione prima locale', 'Sincronizzazione iCloud cifrata', 'Nessuna chiave di decifratura al developer', 'Niente annunci o tracciamento'],
    sections: [['Separare i contenuti sensibili dal rullino pubblico', 'Importa foto, video, screenshot, documenti, contratti, ricevute e file in un archivio privato dedicato.'], ['Trovare subito ciò che conta', 'Album, import recenti, preferiti, categorie e griglie pulite mantengono utilizzabili i contenuti privati.'], ['Restare discreti ogni giorno', 'Un’esperienza sobria da strumento file, gesti privati e uno spazio esca realistico rendono l’app naturale.']],
    privacy: ['Privacy spiegata in modo semplice', 'I contenuti privati restano sul dispositivo per impostazione predefinita. Con iCloud attivo, Mo Layer carica contenuti cifrati per recupero e cambio dispositivo.', ['Scegli file', 'Cifra localmente', 'Sincronizza facoltativamente il cifrato', 'Recupera nel tuo ambiente Apple']],
    pro: ['Pro è capacità, recupero e controllo', 'La protezione locale di base resta disponibile. Pro aggiunge spazio, organizzazione in batch, sync cifrata, controlli esca, registri intrusioni e recupero avanzato.', ['Import illimitati', 'Organizzazione in batch', 'Sync iCloud cifrata', 'Controlli esca avanzati']],
    faq: [['Mo Layer carica file privati leggibili?', 'No. Il prodotto è progettato con protezione locale. La sync iCloud opzionale salva contenuti cifrati e il developer non possiede la chiave di decifratura.'], ['È solo per foto?', 'No. Mo Layer è per foto, video, screenshot, documenti, contratti, ricevute, link e file importanti.'], ['A cosa serve Pro?', 'Pro sblocca capacità, workflow batch, sync cifrata, recupero, travestimento avanzato e controlli esca. La protezione locale di base resta inclusa.']],
    feedback: ['Dicci cosa migliorare', 'Richiedi funzioni, segnala problemi o spiega cosa renderebbe Mo Layer più utile per il tuo archivio privato.'],
    seo: ['Mo Layer - Cassaforte privata per foto e file', 'Mo Layer protegge foto, video, documenti, contratti, screenshot e file privati su iPhone con sicurezza locale e recupero iCloud cifrato.'],
    labels: ['Contenuti privati, tenuti in ordine.', 'Mo Layer è progettato per l’uso quotidiano: sicuro per file sensibili, discreto quando lo apri.', 'Contenuti che spiegano chiaramente il prodotto.', 'Le pagine Markdown offrono spiegazioni dirette e fattuali a motori di ricerca e risposte AI.', 'Domande prima di fidarsi di una cassaforte privata.', 'Leggi contenuto', 'Scansiona per scaricare', 'Apri direttamente la pagina App Store su iPhone.', 'Schermate App Store reali in formato leggibile.', 'Screenshot promozionali completi dalla cartella reale dell’app, mostrati come poster prodotto.']
  }),
  'pt-BR': copyFrom({
    nav: ['Recursos', 'Privacidade', 'Conteúdo', 'Feedback', 'Baixar'],
    hero: ['Arquivo seguro e discreto', 'Um cofre privado para fotos, vídeos e arquivos importantes.', 'Mo Layer organiza memórias sensíveis, documentos, contratos, capturas e arquivos em um espaço criptografado discreto no iPhone.', 'Baixar na App Store', 'Como a privacidade funciona'],
    trust: ['Proteção local primeiro', 'Sincronização iCloud criptografada', 'Sem chave de descriptografia com o desenvolvedor', 'Sem anúncios ou rastreamento'],
    sections: [['Separe mídias sensíveis do rolo público', 'Importe fotos, vídeos, capturas, documentos, contratos, recibos e arquivos para um arquivo privado dedicado.'], ['Encontre o que importa rapidamente', 'Álbuns, importações recentes, favoritos, categorias e grades limpas mantêm o conteúdo privado utilizável.'], ['Mantenha discrição no dia a dia', 'Uma experiência contida de ferramenta de arquivos, gestos privados e espaço isca realista tornam o app natural e prático.']],
    privacy: ['Privacidade explicada de forma simples', 'Seu conteúdo privado fica no dispositivo por padrão. Ao ativar iCloud, o Mo Layer envia conteúdo criptografado para recuperação e troca de aparelho.', ['Escolher arquivos', 'Criptografar localmente', 'Sincronizar cifra opcionalmente', 'Recuperar no seu ambiente Apple confiável']],
    pro: ['Pro é capacidade, recuperação e controle', 'A proteção local básica continua disponível. Pro adiciona mais espaço, organização em lote, sync criptografada, controles isca, registros de intrusão e recuperação avançada.', ['Importações ilimitadas', 'Organização em lote', 'Sync iCloud criptografada', 'Controles isca avançados']],
    faq: [['O Mo Layer envia arquivos privados legíveis?', 'Não. O produto é local-first. A sincronização iCloud opcional armazena conteúdo criptografado e o desenvolvedor não possui sua chave.'], ['É só para fotos?', 'Não. Mo Layer foi criado para fotos, vídeos, capturas, documentos, contratos, recibos, links e arquivos importantes.'], ['Para que serve o Pro?', 'Pro desbloqueia capacidade, fluxos em lote, sync criptografada, recuperação, disfarce avançado e controles isca. A proteção local básica permanece.']],
    feedback: ['Conte o que devemos melhorar', 'Peça recursos, relate problemas ou explique como o Mo Layer pode ajudar melhor seu arquivo privado.'],
    seo: ['Mo Layer - Cofre privado de fotos e arquivos', 'Mo Layer protege fotos, vídeos, documentos, contratos, capturas e arquivos privados no iPhone com organização segura e recuperação iCloud criptografada.'],
    labels: ['Conteúdo privado, bem organizado.', 'Mo Layer foi criado para uso diário: seguro para arquivos sensíveis e discreto ao abrir.', 'Conteúdo que explica o produto com clareza.', 'Páginas Markdown dão a buscadores e respostas de IA explicações diretas e factuais.', 'Perguntas antes de confiar em um cofre privado.', 'Ler conteúdo', 'Escanear para baixar', 'Abra a página da App Store diretamente no iPhone.', 'Telas reais da App Store em tamanho legível.', 'Screenshots promocionais completos da pasta real do app, exibidos como pôsteres do produto.']
  }),
  'nl-NL': copyFrom({
    nav: ['Functies', 'Privacy', 'Content', 'Feedback', 'Download'],
    hero: ['Rustig veilig archief', 'Een privékluis voor foto’s, video’s en belangrijke bestanden.', 'Mo Layer bewaart gevoelige herinneringen, ID’s, contracten, screenshots en bestanden in een discrete versleutelde ruimte op iPhone.', 'Download in de App Store', 'Hoe privacy werkt'],
    trust: ['Lokale bescherming eerst', 'Versleutelde iCloud-sync', 'Geen ontsleutelsleutel bij de ontwikkelaar', 'Geen advertenties of tracking'],
    sections: [['Scheid gevoelige media van je openbare filmrol', 'Importeer foto’s, video’s, screenshots, ID’s, contracten, bonnetjes en bestanden in een privéarchief.'], ['Vind snel wat belangrijk is', 'Albums, recente imports, favorieten, bestandscategorieën en duidelijke rasters houden privé-inhoud bruikbaar.'], ['Blijf discreet in dagelijkse situaties', 'Een ingetogen bestandsinterface, privégebaren en een realistische decoyruimte maken de app rustig en praktisch.']],
    privacy: ['Privacy in gewone taal', 'Privé-inhoud blijft standaard op je apparaat. Met iCloud-sync uploadt Mo Layer versleutelde inhoud voor herstel en apparaatwissels.', ['Bestanden kiezen', 'Lokaal versleutelen', 'Versleutelde data optioneel synchroniseren', 'Herstellen via je Apple-omgeving']],
    pro: ['Pro is voor capaciteit, herstel en controle', 'Basis lokale bescherming blijft beschikbaar. Pro voegt ruimte, batchorganisatie, versleutelde sync, decoybediening, inbraaklogboeken en geavanceerd herstel toe.', ['Onbeperkt importeren', 'Batchorganisatie', 'Versleutelde iCloud-sync', 'Geavanceerde decoybediening']],
    faq: [['Uploadt Mo Layer leesbare privébestanden?', 'Nee. Het product is lokaal-first. Optionele iCloud-sync bewaart versleutelde inhoud en de ontwikkelaar heeft je ontsleutelsleutel niet.'], ['Is dit alleen voor foto’s?', 'Nee. Mo Layer is voor foto’s, video’s, screenshots, ID’s, contracten, bonnetjes, links en belangrijke bestanden.'], ['Waarvoor is Pro?', 'Pro ontgrendelt capaciteit, batchflows, versleutelde sync, hersteltools, geavanceerde vermomming en decoybediening. Basisbescherming blijft inbegrepen.']],
    feedback: ['Vertel wat beter kan', 'Vraag functies aan, meld problemen of leg uit wat Mo Layer nuttiger maakt voor je privéarchief.'],
    seo: ['Mo Layer - Privé fotokluis en veilige bestandsorganizer', 'Mo Layer beschermt foto’s, video’s, ID’s, contracten, screenshots en privébestanden op iPhone met lokale veiligheid en versleuteld iCloud-herstel.'],
    labels: ['Privé-inhoud, netjes bewaard.', 'Mo Layer is ontworpen voor dagelijks gebruik: veilig genoeg voor gevoelige bestanden, rustig genoeg om zonder gedoe te openen.', 'Content die het product duidelijk uitlegt.', 'Markdown-pagina’s geven zoekmachines en AI-antwoorden directe, feitelijke uitleg over Mo Layer.', 'Vragen voordat mensen een privékluis vertrouwen.', 'Content lezen', 'Scan om te downloaden', 'Open de App Store-pagina direct op iPhone.', 'Echte App Store-schermen op leesbare grootte.', 'Volledige promotionele screenshots uit de echte app-map, getoond als productposters.']
  }),
  'tr': copyFrom({
    nav: ['Özellikler', 'Gizlilik', 'İçerik', 'Geri bildirim', 'İndir'],
    hero: ['Sessiz güvenli arşiv', 'Fotoğraflar, videolar ve önemli dosyalar için özel kasa.', 'Mo Layer hassas anıları, kimlikleri, sözleşmeleri, ekran görüntülerini ve dosyaları iPhone’da gizli şifreli bir alanda düzenler.', 'App Store’dan indir', 'Gizlilik nasıl çalışır'],
    trust: ['Önce yerel koruma', 'Şifreli iCloud senkronizasyonu', 'Geliştiricide şifre çözme anahtarı yok', 'Reklam veya takip yok'],
    sections: [['Hassas medyayı herkese açık film rulonuzdan ayırın', 'Fotoğrafları, videoları, ekran görüntülerini, kimlikleri, sözleşmeleri, makbuzları ve dosyaları özel arşive aktarın.'], ['Önemli olanı hızlı bulun', 'Albümler, son aktarımlar, favoriler, dosya kategorileri ve temiz ızgaralar özel içeriği kullanılabilir tutar.'], ['Günlük durumlarda dikkat çekmeyin', 'Sade dosya aracı deneyimi, özel hareketler ve gerçekçi aldatma alanı uygulamayı doğal kılar.']],
    privacy: ['Gizlilik sade dille', 'Özel içeriğiniz varsayılan olarak cihazınızda kalır. iCloud’u açarsanız Mo Layer kurtarma ve cihaz değişimi için şifreli içerik yükler.', ['Dosyaları seç', 'Yerelde şifrele', 'İsteğe bağlı şifreli senkronizasyon', 'Güvenilir Apple ortamında kurtar']],
    pro: ['Pro kapasite, kurtarma ve kontrol içindir', 'Temel yerel koruma kalır. Pro daha fazla alan, toplu düzenleme, şifreli senkronizasyon, aldatma kontrolleri, giriş kayıtları ve gelişmiş kurtarma ekler.', ['Sınırsız içe aktarma', 'Toplu düzenleme', 'Şifreli iCloud senkronizasyonu', 'Gelişmiş aldatma kontrolleri']],
    faq: [['Mo Layer okunabilir özel dosyaları yükler mi?', 'Hayır. Ürün yerel öncelikli koruma üzerine tasarlanmıştır. İsteğe bağlı iCloud senkronizasyonu şifreli içerik saklar ve geliştirici şifre çözme anahtarınızı tutmaz.'], ['Sadece fotoğraflar için mi?', 'Hayır. Mo Layer fotoğraflar, videolar, ekran görüntüleri, kimlikler, sözleşmeler, makbuzlar, bağlantılar ve önemli dosyalar için tasarlanmıştır.'], ['Pro ne işe yarar?', 'Pro kapasiteyi, toplu iş akışlarını, şifreli senkronizasyonu, kurtarma araçlarını, gelişmiş gizlemeyi ve aldatma kontrollerini açar. Temel yerel koruma kalır.']],
    feedback: ['Neyi geliştirelim?', 'Özellik isteyin, sorun bildirin veya Mo Layer’ın özel arşiv iş akışınız için nasıl daha yararlı olacağını anlatın.'],
    seo: ['Mo Layer - Özel fotoğraf kasası ve güvenli dosya düzenleyici', 'Mo Layer iPhone’da hassas fotoğrafları, videoları, kimlikleri, sözleşmeleri, ekran görüntülerini ve şifreli iCloud kurtarmayı korur.'],
    labels: ['Özel içerik, düzenli tutulur.', 'Mo Layer günlük kullanım için tasarlanmıştır: hassas dosyalar için güvenli, açarken sakin.', 'Ürünü açıkça anlatan içerik.', 'Markdown sayfaları arama motorlarına ve yapay zeka yanıtlarına doğrudan, gerçek açıklamalar sunar.', 'Özel kasaya güvenmeden önce sorulan sorular.', 'İçeriği oku', 'İndirmek için tara', 'iPhone’da App Store sayfasını doğrudan açar.', 'Okunabilir boyutta gerçek App Store ekranları.', 'Gerçek uygulama klasöründen tam tanıtım ekran görüntüleri ürün posteri olarak gösterilir.']
  }),
  'ru': copyFrom({
    nav: ['Функции', 'Приватность', 'Контент', 'Обратная связь', 'Скачать'],
    hero: ['Тихий защищенный архив', 'Личное хранилище для фото, видео и важных файлов.', 'Mo Layer упорядочивает важные воспоминания, документы, договоры, скриншоты и файлы в незаметном зашифрованном пространстве iPhone.', 'Скачать в App Store', 'Как работает приватность'],
    trust: ['Сначала локальная защита', 'Зашифрованная синхронизация iCloud', 'Разработчик не хранит ключ расшифровки', 'Без рекламы и трекинга'],
    sections: [['Отделите чувствительные медиа от общей фотопленки', 'Импортируйте фото, видео, скриншоты, документы, договоры, чеки и файлы в отдельный личный архив.'], ['Быстро находите важное', 'Альбомы, недавние импорты, избранное, категории файлов и чистые сетки делают личный контент удобным.'], ['Оставайтесь незаметны в обычных ситуациях', 'Сдержанный интерфейс файлового инструмента, приватные жесты и реалистичное пространство-приманка делают приложение спокойным.']],
    privacy: ['Приватность простыми словами', 'Личный контент по умолчанию остается на устройстве. При включении iCloud Mo Layer загружает зашифрованный контент для восстановления и смены устройства.', ['Выберите файлы', 'Зашифруйте локально', 'При желании синхронизируйте шифртекст', 'Восстановите в своей Apple-среде']],
    pro: ['Pro — это емкость, восстановление и контроль', 'Базовая локальная защита остается. Pro добавляет больше места, пакетную организацию, шифрованную синхронизацию, приманки, журналы доступа и расширенное восстановление.', ['Неограниченный импорт', 'Пакетная организация', 'Шифрованная iCloud-синхронизация', 'Расширенные приманки']],
    faq: [['Mo Layer загружает читаемые личные файлы?', 'Нет. Продукт построен вокруг локальной защиты. Опциональная iCloud-синхронизация хранит зашифрованный контент, а разработчик не владеет вашим ключом.'], ['Это только для фото?', 'Нет. Mo Layer предназначен для фото, видео, скриншотов, документов, договоров, чеков, ссылок и важных файлов.'], ['Для чего нужен Pro?', 'Pro открывает емкость, пакетные процессы, шифрованную синхронизацию, восстановление, расширенную маскировку и приманки. Базовая защита остается.']],
    feedback: ['Расскажите, что улучшить', 'Запросите функции, сообщите о проблемах или объясните, как сделать Mo Layer полезнее для вашего личного архива.'],
    seo: ['Mo Layer - Личное хранилище фото и защищенный файловый органайзер', 'Mo Layer защищает фото, видео, документы, договоры, скриншоты и личные файлы на iPhone с локальной безопасностью и шифрованным восстановлением iCloud.'],
    labels: ['Личный контент в порядке.', 'Mo Layer создан для ежедневного использования: достаточно безопасен для чувствительных файлов и спокоен при открытии.', 'Контент, который ясно объясняет продукт.', 'Markdown-страницы дают поиску и AI-ответам прямые фактические объяснения Mo Layer.', 'Вопросы перед доверием личному хранилищу.', 'Читать', 'Сканировать для скачивания', 'Открывает страницу App Store прямо на iPhone.', 'Настоящие экраны App Store в читаемом размере.', 'Полные промо-скриншоты из реальной папки приложения показаны как продуктовые постеры.']
  }),
  'vi': copyFrom({
    nav: ['Tính năng', 'Quyền riêng tư', 'Nội dung', 'Góp ý', 'Tải về'],
    hero: ['Kho lưu trữ an toàn kín đáo', 'Kho riêng cho ảnh, video và tệp quan trọng.', 'Mo Layer sắp xếp kỷ niệm nhạy cảm, giấy tờ, hợp đồng, ảnh chụp màn hình và tệp trong không gian mã hóa kín đáo trên iPhone.', 'Tải trên App Store', 'Cách quyền riêng tư hoạt động'],
    trust: ['Bảo vệ ưu tiên cục bộ', 'Đồng bộ iCloud mã hóa', 'Nhà phát triển không giữ khóa giải mã', 'Không quảng cáo hoặc theo dõi'],
    sections: [['Tách nội dung nhạy cảm khỏi thư viện công khai', 'Nhập ảnh, video, ảnh chụp màn hình, giấy tờ, hợp đồng, biên lai và tệp vào kho riêng.'], ['Tìm nhanh thứ quan trọng', 'Album, mục mới nhập, yêu thích, danh mục tệp và lưới rõ ràng giúp nội dung riêng dễ dùng.'], ['Kín đáo trong tình huống hằng ngày', 'Trải nghiệm công cụ tệp tối giản, cử chỉ riêng và không gian mồi thực tế giúp ứng dụng tự nhiên.']],
    privacy: ['Giải thích quyền riêng tư dễ hiểu', 'Nội dung riêng mặc định ở trên thiết bị. Khi bật iCloud, Mo Layer tải lên nội dung đã mã hóa để phục hồi và đổi thiết bị.', ['Chọn tệp', 'Mã hóa cục bộ', 'Tùy chọn đồng bộ bản mã', 'Phục hồi bằng môi trường Apple tin cậy']],
    pro: ['Pro dành cho dung lượng, phục hồi và kiểm soát', 'Bảo vệ cục bộ cơ bản vẫn có. Pro thêm dung lượng, sắp xếp hàng loạt, đồng bộ mã hóa, kiểm soát mồi, nhật ký xâm nhập và phục hồi nâng cao.', ['Nhập không giới hạn', 'Sắp xếp hàng loạt', 'Đồng bộ iCloud mã hóa', 'Kiểm soát mồi nâng cao']],
    faq: [['Mo Layer có tải lên tệp riêng ở dạng đọc được không?', 'Không. Sản phẩm ưu tiên bảo vệ cục bộ. Đồng bộ iCloud tùy chọn lưu nội dung mã hóa và nhà phát triển không giữ khóa giải mã.'], ['Chỉ dùng cho ảnh thôi sao?', 'Không. Mo Layer dành cho ảnh, video, ảnh chụp màn hình, giấy tờ, hợp đồng, biên lai, liên kết và tệp quan trọng.'], ['Pro dùng để làm gì?', 'Pro mở khóa dung lượng, thao tác hàng loạt, đồng bộ mã hóa, công cụ phục hồi, ngụy trang nâng cao và kiểm soát mồi. Bảo vệ cục bộ cơ bản vẫn được giữ.']],
    feedback: ['Cho chúng tôi biết cần cải thiện gì', 'Yêu cầu tính năng, báo lỗi hoặc giải thích điều gì giúp Mo Layer hữu ích hơn cho kho riêng của bạn.'],
    seo: ['Mo Layer - Kho ảnh riêng và trình sắp xếp tệp an toàn', 'Mo Layer bảo vệ ảnh, video, giấy tờ, hợp đồng, ảnh chụp màn hình và tệp riêng trên iPhone với bảo mật cục bộ và phục hồi iCloud mã hóa.'],
    labels: ['Nội dung riêng, luôn có trật tự.', 'Mo Layer được thiết kế cho hằng ngày: đủ an toàn cho tệp nhạy cảm và đủ kín đáo khi mở.', 'Nội dung giải thích sản phẩm rõ ràng.', 'Trang Markdown cung cấp giải thích trực tiếp, thực tế cho công cụ tìm kiếm và AI.', 'Câu hỏi trước khi tin một kho riêng.', 'Đọc nội dung', 'Quét để tải', 'Mở trực tiếp trang App Store trên iPhone.', 'Màn hình App Store thật ở kích thước dễ đọc.', 'Ảnh quảng bá đầy đủ từ thư mục ứng dụng thật, hiển thị như poster sản phẩm.']
  }),
  'th': copyFrom({
    nav: ['ฟีเจอร์', 'ความเป็นส่วนตัว', 'เนื้อหา', 'ความคิดเห็น', 'ดาวน์โหลด'],
    hero: ['คลังเก็บที่ปลอดภัยและเงียบ', 'ตู้เซฟส่วนตัวสำหรับรูป วิดีโอ และไฟล์สำคัญ', 'Mo Layer จัดเก็บความทรงจำ เอกสาร สัญญา ภาพหน้าจอ และไฟล์สำคัญในพื้นที่เข้ารหัสที่ไม่สะดุดตาบน iPhone', 'ดาวน์โหลดบน App Store', 'การปกป้องความเป็นส่วนตัว'],
    trust: ['ปกป้องบนเครื่องก่อน', 'ซิงค์ iCloud แบบเข้ารหัส', 'ผู้พัฒนาไม่มีคีย์ถอดรหัส', 'ไม่มีโฆษณาหรือการติดตาม'],
    sections: [['แยกสื่อสำคัญออกจากม้วนรูปสาธารณะ', 'นำเข้ารูป วิดีโอ ภาพหน้าจอ เอกสาร สัญญา ใบเสร็จ และไฟล์เข้าสู่คลังส่วนตัว'], ['ค้นหาสิ่งสำคัญได้เร็ว', 'อัลบั้ม รายการนำเข้าล่าสุด รายการโปรด หมวดไฟล์ และกริดที่ชัดเจนช่วยให้ใช้งานเนื้อหาส่วนตัวได้ง่าย'], ['ใช้งานอย่างแนบเนียนในชีวิตประจำวัน', 'ประสบการณ์เครื่องมือไฟล์ที่เรียบง่าย ท่าทางส่วนตัว และพื้นที่หลอกที่สมจริงทำให้แอปใช้งานได้เป็นธรรมชาติ']],
    privacy: ['อธิบายความเป็นส่วนตัวแบบเข้าใจง่าย', 'เนื้อหาส่วนตัวจะอยู่บนอุปกรณ์โดยค่าเริ่มต้น หากเปิด iCloud Mo Layer จะอัปโหลดเฉพาะข้อมูลที่เข้ารหัสเพื่อการกู้คืนและเปลี่ยนอุปกรณ์', ['เลือกไฟล์', 'เข้ารหัสบนเครื่อง', 'ซิงค์ข้อความเข้ารหัสเมื่อเลือก', 'กู้คืนด้วยสภาพแวดล้อม Apple ของคุณ']],
    pro: ['Pro สำหรับพื้นที่ การกู้คืน และการควบคุม', 'การปกป้องพื้นฐานยังมีอยู่ Pro เพิ่มพื้นที่ การจัดการเป็นชุด การซิงค์เข้ารหัส การควบคุมพื้นที่หลอก บันทึกการบุกรุก และการกู้คืนขั้นสูง', ['นำเข้าไม่จำกัด', 'จัดการเป็นชุด', 'ซิงค์ iCloud แบบเข้ารหัส', 'ควบคุมพื้นที่หลอกขั้นสูง']],
    faq: [['Mo Layer อัปโหลดไฟล์ส่วนตัวแบบอ่านได้หรือไม่?', 'ไม่ แอปออกแบบโดยให้การปกป้องบนเครื่องมาก่อน การซิงค์ iCloud ที่เลือกได้จะเก็บข้อมูลที่เข้ารหัส และผู้พัฒนาไม่มีคีย์ถอดรหัส'], ['ใช้ได้เฉพาะรูปภาพหรือไม่?', 'ไม่ Mo Layer เหมาะกับรูป วิดีโอ ภาพหน้าจอ เอกสาร สัญญา ใบเสร็จ ลิงก์ และไฟล์สำคัญ'], ['Pro มีไว้เพื่ออะไร?', 'Pro ปลดล็อกพื้นที่ งานเป็นชุด การซิงค์เข้ารหัส เครื่องมือกู้คืน การพรางตัวขั้นสูง และการควบคุมพื้นที่หลอก การปกป้องบนเครื่องพื้นฐานยังคงอยู่']],
    feedback: ['บอกเราว่าควรปรับปรุงอะไร', 'ขอฟีเจอร์ แจ้งปัญหา หรืออธิบายสิ่งที่จะทำให้ Mo Layer เหมาะกับคลังส่วนตัวของคุณมากขึ้น'],
    seo: ['Mo Layer - ตู้เซฟรูปส่วนตัวและตัวจัดการไฟล์ปลอดภัย', 'Mo Layer ปกป้องรูป วิดีโอ เอกสาร สัญญา ภาพหน้าจอ และไฟล์ส่วนตัวบน iPhone ด้วยความปลอดภัยบนเครื่องและการกู้คืน iCloud แบบเข้ารหัส'],
    labels: ['เนื้อหาส่วนตัวที่เป็นระเบียบ', 'Mo Layer ออกแบบเพื่อใช้งานประจำวัน: ปลอดภัยพอสำหรับไฟล์สำคัญ และเปิดใช้งานได้อย่างเงียบ', 'เนื้อหาที่อธิบายผลิตภัณฑ์ชัดเจน', 'หน้า Markdown ให้คำอธิบายที่ตรงและเป็นข้อเท็จจริงแก่เสิร์ชเอนจินและ AI', 'คำถามก่อนเชื่อใจตู้เซฟส่วนตัว', 'อ่านเนื้อหา', 'สแกนเพื่อดาวน์โหลด', 'เปิดหน้า App Store บน iPhone โดยตรง', 'หน้าจอ App Store จริงในขนาดอ่านง่าย', 'ภาพโปรโมตเต็มจากโฟลเดอร์แอปจริง แสดงเป็นโปสเตอร์ผลิตภัณฑ์']
  }),
  'id': copyFrom({
    nav: ['Fitur', 'Privasi', 'Konten', 'Masukan', 'Unduh'],
    hero: ['Arsip aman yang tenang', 'Brankas pribadi untuk foto, video, dan file penting.', 'Mo Layer menyusun kenangan sensitif, identitas, kontrak, tangkapan layar, dan file di ruang terenkripsi yang diskret untuk iPhone.', 'Unduh di App Store', 'Cara kerja privasi'],
    trust: ['Perlindungan lokal dulu', 'Sinkronisasi iCloud terenkripsi', 'Pengembang tidak memegang kunci dekripsi', 'Tanpa iklan atau pelacakan'],
    sections: [['Pisahkan media sensitif dari rol kamera publik', 'Impor foto, video, tangkapan layar, identitas, kontrak, tanda terima, dan file ke arsip pribadi khusus.'], ['Temukan yang penting dengan cepat', 'Album, impor terbaru, favorit, kategori file, dan kisi bersih membuat konten pribadi tetap mudah digunakan.'], ['Tetap diskret dalam situasi sehari-hari', 'Pengalaman alat file yang sederhana, gestur pribadi, dan ruang umpan realistis membuat aplikasi terasa natural.']],
    privacy: ['Privasi dijelaskan dengan sederhana', 'Konten pribadi tetap di perangkat secara default. Jika iCloud diaktifkan, Mo Layer mengunggah konten terenkripsi untuk pemulihan dan pergantian perangkat.', ['Pilih file', 'Enkripsi lokal', 'Sinkronkan ciphertext bila perlu', 'Pulihkan dengan lingkungan Apple tepercaya']],
    pro: ['Pro untuk kapasitas, pemulihan, dan kontrol', 'Perlindungan lokal dasar tetap tersedia. Pro menambah ruang, organisasi massal, sinkronisasi terenkripsi, kontrol umpan, catatan intrusi, dan pemulihan lanjutan.', ['Impor tanpa batas', 'Organisasi massal', 'Sinkronisasi iCloud terenkripsi', 'Kontrol umpan lanjutan']],
    faq: [['Apakah Mo Layer mengunggah file pribadi yang dapat dibaca?', 'Tidak. Produk dirancang dengan perlindungan lokal terlebih dahulu. Sinkronisasi iCloud opsional menyimpan konten terenkripsi dan pengembang tidak memegang kunci dekripsi Anda.'], ['Apakah hanya untuk foto?', 'Tidak. Mo Layer dirancang untuk foto, video, tangkapan layar, identitas, kontrak, tanda terima, tautan, dan file penting.'], ['Untuk apa Pro?', 'Pro membuka kapasitas, alur massal, sinkronisasi terenkripsi, alat pemulihan, penyamaran lanjutan, dan kontrol umpan. Perlindungan lokal dasar tetap ada.']],
    feedback: ['Beri tahu kami yang perlu ditingkatkan', 'Minta fitur, laporkan masalah, atau jelaskan apa yang membuat Mo Layer lebih berguna untuk arsip pribadi Anda.'],
    seo: ['Mo Layer - Brankas foto pribadi dan pengelola file aman', 'Mo Layer melindungi foto, video, identitas, kontrak, tangkapan layar, dan file pribadi di iPhone dengan keamanan lokal dan pemulihan iCloud terenkripsi.'],
    labels: ['Konten pribadi tetap rapi.', 'Mo Layer dirancang untuk penggunaan sehari-hari: aman untuk file sensitif dan tenang saat dibuka.', 'Konten yang menjelaskan produk dengan jelas.', 'Halaman Markdown memberi mesin pencari dan jawaban AI penjelasan langsung dan faktual tentang Mo Layer.', 'Pertanyaan sebelum mempercayai brankas pribadi.', 'Baca konten', 'Pindai untuk mengunduh', 'Buka halaman App Store langsung di iPhone.', 'Layar App Store nyata dalam ukuran mudah dibaca.', 'Screenshot promosi lengkap dari folder aplikasi asli, ditampilkan sebagai poster produk.']
  }),
  'hi': copyFrom({
    nav: ['विशेषताएँ', 'गोपनीयता', 'सामग्री', 'प्रतिक्रिया', 'डाउनलोड'],
    hero: ['शांत सुरक्षित आर्काइव', 'फोटो, वीडियो और जरूरी फाइलों के लिए निजी वॉल्ट।', 'Mo Layer संवेदनशील यादें, पहचान पत्र, अनुबंध, स्क्रीनशॉट और फाइलों को iPhone पर एक शांत एन्क्रिप्टेड जगह में व्यवस्थित करता है।', 'App Store से डाउनलोड करें', 'गोपनीयता कैसे काम करती है'],
    trust: ['लोकल-फर्स्ट सुरक्षा', 'एन्क्रिप्टेड iCloud सिंक', 'डेवलपर के पास डिक्रिप्शन कुंजी नहीं', 'कोई विज्ञापन या ट्रैकिंग नहीं'],
    sections: [['संवेदनशील मीडिया को सार्वजनिक कैमरा रोल से अलग रखें', 'फोटो, वीडियो, स्क्रीनशॉट, पहचान पत्र, अनुबंध, रसीदें और फाइलें एक निजी आर्काइव में आयात करें।'], ['जरूरी चीजें जल्दी खोजें', 'एल्बम, हाल के आयात, पसंदीदा, फाइल श्रेणियाँ और साफ ग्रिड निजी सामग्री को उपयोगी रखते हैं।'], ['रोजमर्रा की स्थितियों में शांत रहें', 'संयमित फाइल-टूल अनुभव, निजी जेस्चर और वास्तविक डिकॉय स्पेस ऐप को व्यावहारिक बनाते हैं।']],
    privacy: ['गोपनीयता सरल भाषा में', 'आपकी निजी सामग्री डिफ़ॉल्ट रूप से डिवाइस पर रहती है। iCloud चालू करने पर Mo Layer रिकवरी और डिवाइस बदलने के लिए एन्क्रिप्टेड सामग्री अपलोड करता है।', ['फाइलें चुनें', 'लोकल एन्क्रिप्ट करें', 'वैकल्पिक रूप से ciphertext सिंक करें', 'अपने विश्वसनीय Apple वातावरण से रिकवर करें']],
    pro: ['Pro क्षमता, रिकवरी और नियंत्रण के लिए है', 'मूल लोकल सुरक्षा उपलब्ध रहती है। Pro अधिक जगह, बैच संगठन, एन्क्रिप्टेड सिंक, डिकॉय नियंत्रण, घुसपैठ रिकॉर्ड और उन्नत रिकवरी जोड़ता है।', ['अनलिमिटेड आयात', 'बैच संगठन', 'एन्क्रिप्टेड iCloud सिंक', 'उन्नत डिकॉय नियंत्रण']],
    faq: [['क्या Mo Layer पढ़ी जा सकने वाली निजी फाइलें अपलोड करता है?', 'नहीं। उत्पाद लोकल-फर्स्ट सुरक्षा पर आधारित है। वैकल्पिक iCloud सिंक एन्क्रिप्टेड सामग्री रखता है और डेवलपर आपकी डिक्रिप्शन कुंजी नहीं रखता।'], ['क्या यह सिर्फ फोटो के लिए है?', 'नहीं। Mo Layer फोटो, वीडियो, स्क्रीनशॉट, पहचान पत्र, अनुबंध, रसीदें, लिंक और जरूरी फाइलों के लिए है।'], ['Pro किसलिए है?', 'Pro क्षमता, बैच वर्कफ़्लो, एन्क्रिप्टेड सिंक, रिकवरी टूल, उन्नत disguise और डिकॉय नियंत्रण खोलता है। बेसिक लोकल सुरक्षा बनी रहती है।']],
    feedback: ['बताएँ हमें क्या सुधारना चाहिए', 'फीचर मांगें, समस्या बताएं या समझाएं कि Mo Layer आपके निजी आर्काइव के लिए कैसे अधिक उपयोगी होगा।'],
    seo: ['Mo Layer - निजी फोटो वॉल्ट और सुरक्षित फाइल ऑर्गनाइज़र', 'Mo Layer iPhone पर संवेदनशील फोटो, वीडियो, पहचान पत्र, अनुबंध, स्क्रीनशॉट और एन्क्रिप्टेड iCloud रिकवरी के लिए निजी फोटो वॉल्ट और सुरक्षित फाइल ऑर्गनाइज़र है।'],
    labels: ['निजी सामग्री, व्यवस्थित रखी गई।', 'Mo Layer रोजमर्रा के उपयोग के लिए बनाया गया है: संवेदनशील फाइलों के लिए सुरक्षित और खोलते समय शांत।', 'सामग्री जो उत्पाद को साफ समझाती है।', 'Markdown पेज सर्च इंजन और AI उत्तरों को Mo Layer की सीधी, तथ्यात्मक व्याख्या देते हैं।', 'निजी वॉल्ट पर भरोसा करने से पहले पूछे जाने वाले सवाल।', 'सामग्री पढ़ें', 'डाउनलोड के लिए स्कैन करें', 'iPhone पर App Store पेज सीधे खोलें।', 'पढ़ने योग्य आकार में वास्तविक App Store स्क्रीन।', 'वास्तविक ऐप फ़ोल्डर से पूर्ण प्रचार स्क्रीनशॉट, उत्पाद पोस्टर की तरह दिखाए गए।']
  }),
  'ar': copyFrom({
    nav: ['الميزات', 'الخصوصية', 'المحتوى', 'الملاحظات', 'تنزيل'],
    hero: ['أرشيف آمن وهادئ', 'خزنة خاصة للصور والفيديو والملفات المهمة.', 'ينظم Mo Layer الذكريات الحساسة والوثائق والعقود ولقطات الشاشة والملفات في مساحة مشفرة وهادئة على iPhone.', 'تنزيل من App Store', 'كيف تعمل الخصوصية'],
    trust: ['حماية محلية أولاً', 'مزامنة iCloud مشفرة', 'لا يحتفظ المطور بمفتاح فك التشفير', 'لا إعلانات ولا تتبع'],
    sections: [['افصل الوسائط الحساسة عن ألبوم الكاميرا العام', 'استورد الصور والفيديو ولقطات الشاشة والوثائق والعقود والإيصالات والملفات إلى أرشيف خاص.'], ['اعثر على المهم بسرعة', 'الألبومات والواردات الأخيرة والمفضلات وفئات الملفات والشبكات الواضحة تجعل المحتوى الخاص سهل الاستخدام.'], ['ابق هادئاً في المواقف اليومية', 'تجربة أداة ملفات بسيطة وإيماءات خاصة ومساحة تمويه واقعية تجعل التطبيق طبيعياً وعملياً.']],
    privacy: ['الخصوصية بلغة واضحة', 'يبقى محتواك الخاص على جهازك افتراضياً. عند تفعيل iCloud يرفع Mo Layer محتوى مشفراً للاسترداد وتغيير الجهاز.', ['اختر الملفات', 'شفّر محلياً', 'زامن النص المشفر اختيارياً', 'استعد عبر بيئة Apple الموثوقة']],
    pro: ['Pro للسعة والاسترداد والتحكم', 'تبقى الحماية المحلية الأساسية متاحة. يضيف Pro مساحة أكبر وتنظيماً دفعيًا ومزامنة مشفرة وتحكم التمويه وسجلات التطفل والاسترداد المتقدم.', ['استيراد غير محدود', 'تنظيم دفعي', 'مزامنة iCloud مشفرة', 'تحكم تمويه متقدم']],
    faq: [['هل يرفع Mo Layer ملفات خاصة قابلة للقراءة؟', 'لا. صُمم المنتج حول الحماية المحلية أولاً. تحفظ مزامنة iCloud الاختيارية محتوى مشفراً ولا يحتفظ المطور بمفتاح فك التشفير.'], ['هل هو للصور فقط؟', 'لا. Mo Layer مصمم للصور والفيديو ولقطات الشاشة والوثائق والعقود والإيصالات والروابط والملفات المهمة.'], ['ما فائدة Pro؟', 'يفتح Pro السعة وسير العمل الدفعي والمزامنة المشفرة وأدوات الاسترداد والتمويه المتقدم والتحكم في المساحات البديلة. تبقى الحماية المحلية الأساسية.']],
    feedback: ['أخبرنا بما يجب تحسينه', 'اطلب ميزات أو أبلغ عن مشكلات أو اشرح ما يجعل Mo Layer أكثر فائدة لأرشيفك الخاص.'],
    seo: ['Mo Layer - خزنة صور خاصة ومنظم ملفات آمن', 'Mo Layer خزنة صور خاصة ومنظم ملفات آمن على iPhone للصور والفيديو والوثائق والعقود ولقطات الشاشة واسترداد iCloud المشفر.'],
    labels: ['محتوى خاص ومنظم.', 'صُمم Mo Layer للاستخدام اليومي: آمن للملفات الحساسة وهادئ عند الفتح.', 'محتوى يشرح المنتج بوضوح.', 'توفر صفحات Markdown لمحركات البحث وإجابات الذكاء الاصطناعي شرحاً مباشراً وواقعياً عن Mo Layer.', 'أسئلة قبل الثقة بخزنة خاصة.', 'قراءة المحتوى', 'امسح للتنزيل', 'افتح صفحة App Store مباشرة على iPhone.', 'شاشات App Store حقيقية بحجم مقروء.', 'لقطات ترويجية كاملة من مجلد التطبيق الحقيقي معروضة كملصقات منتج.']
  })
};

export function getCopy(locale: LocaleCode): LandingCopy {
  return localized[locale];
}
