import type { LocaleCode } from './locales';
import { aeoUpdatedAt, productFacts } from '../lib/aeo';

type AeoText = {
  labels: [string, string, string, string, string, string, string, string];
  overview: string;
  comparison: [string, string];
  recovery: [string, string];
  steps: [string, string, string];
  plans: [string, string];
};

// The quota is inserted from the same facts used by pricing and JSON-LD.
const text: Record<LocaleCode, AeoText> = {
  'en-US': {
    labels: ['Product overview', 'Platform', 'Privacy', 'Free and Pro', 'Author', 'Updated', 'Related guides', 'Apple: hide photos and videos'],
    overview: 'What is Mo Layer?',
    comparison: ['Is Apple’s Hidden album enough?', 'Apple’s Hidden album can require authentication on supported systems and is suitable for hiding photos and videos. Mo Layer provides a separate archive for media and documents, with folders and a decoy space. Choose based on file types, organization and recovery needs; a separate app is not automatically more secure.'],
    recovery: ['How do I recover Mo Layer on a new iPhone?', 'Recovery requires an existing encrypted iCloud backup and access to the vault key through iCloud Keychain or your recovery key. Reinstalling the app or restoring a Pro purchase alone does not recover missing files or keys.'],
    steps: ['Before changing phones, check that iCloud backup has completed and keep your recovery key in a safe place outside the vault.', 'Sign in to the same Apple Account on the new iPhone. Open Mo Layer and follow the recovery prompts; use your recovery key if the vault key is unavailable.', 'Open important files to verify recovery before erasing the old device. Originals may download when opened; keep network access available.'],
    plans: ['What is free, and what does Pro change?', 'Free includes {storage} of vault capacity with no file-count limit, plus backup and restore. Pro removes the app’s {storage} limit; device storage and iCloud capacity still apply. Existing files remain accessible after Pro expires. Check the App Store purchase sheet for current local prices and billing terms.']
  },
  'zh-Hans': {
    labels: ['产品概览', '适用平台', '隐私保护', '免费版与 Pro', '作者', '更新日期', '相关指南', 'Apple：隐藏照片和视频'],
    overview: '墨层是什么？',
    comparison: ['系统隐藏相册够用吗？', '在支持的系统上，Apple 隐藏相册可以要求身份验证，适合隐藏照片和视频。墨层提供独立的媒体与文件档案空间，支持文件夹和诱饵空间。应根据文件类型、整理和恢复需求选择；独立 App 并不自动意味着更安全。'],
    recovery: ['换新 iPhone 后，墨层怎么恢复？', '恢复需要已有的 iCloud 加密备份，以及通过 iCloud 钥匙串或恢复密钥取得保险箱密钥。仅重新安装 App 或恢复 Pro 购买，不能找回缺失的文件或密钥。'],
    steps: ['换机前确认 iCloud 备份已完成，并把恢复密钥安全保存在保险箱之外。', '在新 iPhone 登录同一 Apple 账户，打开墨层并按照恢复提示操作；无法取得保险箱密钥时，使用恢复密钥。', '抹掉旧设备前，打开重要文件验证恢复结果。原始文件可能在打开时下载，请保持网络连接。'],
    plans: ['免费版包含什么，Pro 改变什么？', '免费版提供 {storage} 保险箱容量，不限文件数量，包含备份与恢复。Pro 移除 App 的 {storage} 容量限制，实际可用空间仍受设备和 iCloud 容量影响。Pro 到期后已有文件仍可访问。当地价格和计费条款以 App Store 购买页面为准。']
  },
  'zh-Hant': {
    labels: ['產品概覽', '適用平台', '隱私保護', '免費版與 Pro', '作者', '更新日期', '相關指南', 'Apple：隱藏照片與影片'],
    overview: '墨層是什麼？',
    comparison: ['系統隱藏相簿夠用嗎？', '在支援的系統上，Apple 隱藏相簿可以要求身分驗證，適合隱藏照片與影片。墨層提供獨立的媒體與檔案空間，支援資料夾與誘餌空間。應依檔案類型、整理與復原需求選擇；獨立 App 並不自動代表更安全。'],
    recovery: ['換新 iPhone 後，墨層如何復原？', '復原需要既有的 iCloud 加密備份，以及透過 iCloud 鑰匙圈或復原金鑰取得保險箱金鑰。僅重新安裝 App 或回復 Pro 購買，無法找回遺失的檔案或金鑰。'],
    steps: ['換機前確認 iCloud 備份已完成，並將復原金鑰安全保存在保險箱之外。', '在新 iPhone 登入同一 Apple 帳號，開啟墨層並依復原提示操作；無法取得保險箱金鑰時，使用復原金鑰。', '清除舊裝置前，開啟重要檔案驗證復原結果。原始檔案可能在開啟時下載，請保持網路連線。'],
    plans: ['免費版包含什麼，Pro 改變什麼？', '免費版提供 {storage} 保險箱容量，不限檔案數量，包含備份與復原。Pro 移除 App 的 {storage} 容量限制，實際可用空間仍受裝置與 iCloud 容量影響。Pro 到期後既有檔案仍可存取。當地價格與計費條款以 App Store 購買頁面為準。']
  },
  'de-DE': {
    labels: ['Produktübersicht', 'Plattform', 'Datenschutz', 'Kostenlos und Pro', 'Autor', 'Aktualisiert', 'Weitere Anleitungen', 'Apple: Fotos und Videos ausblenden'],
    overview: 'Was ist Mo Layer?',
    comparison: ['Reicht Apples Album „Ausgeblendet“ aus?', 'Apples Album „Ausgeblendet“ kann auf unterstützten Systemen eine Authentifizierung verlangen und eignet sich für Fotos und Videos. Mo Layer bietet ein separates Archiv für Medien und Dokumente mit Ordnern und einem Tarnbereich. Entscheidend sind Dateitypen, Organisation und Wiederherstellung; eine separate App ist nicht automatisch sicherer.'],
    recovery: ['Wie stelle ich Mo Layer auf einem neuen iPhone wieder her?', 'Sie benötigen ein vorhandenes verschlüsseltes iCloud-Backup und Zugriff auf den Tresorschlüssel über den iCloud-Schlüsselbund oder Ihren Wiederherstellungsschlüssel. Eine Neuinstallation oder das Wiederherstellen eines Pro-Kaufs allein bringt fehlende Dateien oder Schlüssel nicht zurück.'],
    steps: ['Prüfen Sie vor dem Gerätewechsel, ob das iCloud-Backup abgeschlossen ist, und bewahren Sie Ihren Wiederherstellungsschlüssel sicher außerhalb des Tresors auf.', 'Melden Sie sich auf dem neuen iPhone mit demselben Apple Account an. Öffnen Sie Mo Layer und folgen Sie den Wiederherstellungshinweisen; verwenden Sie bei fehlendem Tresorschlüssel Ihren Wiederherstellungsschlüssel.', 'Öffnen Sie wichtige Dateien zur Kontrolle, bevor Sie das alte Gerät löschen. Originale werden möglicherweise erst beim Öffnen geladen; halten Sie eine Netzwerkverbindung bereit.'],
    plans: ['Was ist kostenlos und was ändert Pro?', 'Kostenlos enthalten sind {storage} Tresorkapazität ohne Begrenzung der Dateianzahl sowie Backup und Wiederherstellung. Pro hebt die {storage}-Grenze der App auf; Geräte- und iCloud-Speicher bleiben begrenzt. Vorhandene Dateien bleiben nach Ablauf von Pro zugänglich. Aktuelle lokale Preise und Zahlungsbedingungen stehen im Kaufdialog des App Store.']
  },
  'es-ES': {
    labels: ['Resumen del producto', 'Plataforma', 'Privacidad', 'Gratis y Pro', 'Autor', 'Actualizado', 'Guías relacionadas', 'Apple: ocultar fotos y vídeos'],
    overview: '¿Qué es Mo Layer?',
    comparison: ['¿Es suficiente el álbum Oculto de Apple?', 'El álbum Oculto de Apple puede exigir autenticación en sistemas compatibles y sirve para ocultar fotos y vídeos. Mo Layer ofrece un archivo separado para contenido multimedia y documentos, con carpetas y un espacio señuelo. Elige según los tipos de archivo, la organización y la recuperación; una app independiente no es automáticamente más segura.'],
    recovery: ['¿Cómo recupero Mo Layer en un iPhone nuevo?', 'Necesitas una copia cifrada existente en iCloud y acceso a la clave de la caja fuerte mediante el Llavero de iCloud o tu clave de recuperación. Reinstalar la app o restaurar una compra de Pro no recupera por sí solo archivos o claves que falten.'],
    steps: ['Antes de cambiar de móvil, comprueba que la copia en iCloud haya terminado y guarda tu clave de recuperación en un lugar seguro fuera de la caja fuerte.', 'Inicia sesión con la misma Cuenta de Apple en el nuevo iPhone. Abre Mo Layer y sigue las indicaciones de recuperación; utiliza tu clave de recuperación si la clave de la caja fuerte no está disponible.', 'Abre los archivos importantes para verificar la recuperación antes de borrar el dispositivo anterior. Los originales pueden descargarse al abrirlos; mantén la conexión a Internet.'],
    plans: ['¿Qué incluye la versión gratuita y qué cambia Pro?', 'La versión gratuita incluye {storage} de capacidad, sin límite de archivos, además de copia de seguridad y recuperación. Pro elimina el límite de {storage} de la app; siguen aplicándose los límites del dispositivo y de iCloud. Los archivos existentes siguen accesibles al caducar Pro. Consulta los precios locales y las condiciones de cobro en la pantalla de compra del App Store.']
  },
  'fr-FR': {
    labels: ['Présentation du produit', 'Plateforme', 'Confidentialité', 'Gratuit et Pro', 'Auteur', 'Mis à jour', 'Guides associés', 'Apple : masquer des photos et vidéos'],
    overview: 'Qu’est-ce que Mo Layer ?',
    comparison: ['L’album Masquées d’Apple suffit-il ?', 'L’album Masquées d’Apple peut demander une authentification sur les systèmes compatibles et convient aux photos et vidéos. Mo Layer propose un espace séparé pour les médias et documents, avec dossiers et espace leurre. Choisissez selon les types de fichiers, le classement et la récupération ; une app distincte n’est pas automatiquement plus sûre.'],
    recovery: ['Comment récupérer Mo Layer sur un nouvel iPhone ?', 'Il faut une sauvegarde chiffrée existante dans iCloud et un accès à la clé du coffre via le trousseau iCloud ou votre clé de récupération. Réinstaller l’app ou restaurer un achat Pro ne suffit pas à retrouver des fichiers ou des clés manquants.'],
    steps: ['Avant de changer de téléphone, vérifiez que la sauvegarde iCloud est terminée et conservez votre clé de récupération en sécurité hors du coffre.', 'Connectez-vous au même compte Apple sur le nouvel iPhone. Ouvrez Mo Layer et suivez les instructions ; utilisez votre clé de récupération si la clé du coffre est indisponible.', 'Ouvrez les fichiers importants pour vérifier la récupération avant d’effacer l’ancien appareil. Les originaux peuvent se télécharger à l’ouverture ; gardez une connexion réseau.'],
    plans: ['Que comprend la version gratuite et que change Pro ?', 'La version gratuite comprend {storage} de capacité, sans limite du nombre de fichiers, avec sauvegarde et restauration. Pro supprime la limite de {storage} de l’app ; les capacités de l’appareil et d’iCloud restent applicables. Les fichiers existants restent accessibles après l’expiration de Pro. Consultez les prix locaux et les conditions de facturation sur l’écran d’achat de l’App Store.']
  },
  'it-IT': {
    labels: ['Panoramica del prodotto', 'Piattaforma', 'Privacy', 'Gratis e Pro', 'Autore', 'Aggiornato', 'Guide correlate', 'Apple: nascondere foto e video'],
    overview: 'Che cos’è Mo Layer?',
    comparison: ['Basta l’album Nascosti di Apple?', 'L’album Nascosti di Apple può richiedere l’autenticazione sui sistemi supportati ed è adatto a foto e video. Mo Layer offre un archivio separato per contenuti multimediali e documenti, con cartelle e uno spazio diversivo. Scegli in base ai tipi di file, all’organizzazione e al recupero: un’app separata non è automaticamente più sicura.'],
    recovery: ['Come recupero Mo Layer su un nuovo iPhone?', 'Servono un backup cifrato già presente su iCloud e l’accesso alla chiave della cassaforte tramite il Portachiavi iCloud o la chiave di recupero. Reinstallare l’app o ripristinare un acquisto Pro non recupera da solo file o chiavi mancanti.'],
    steps: ['Prima di cambiare telefono, verifica che il backup iCloud sia completo e conserva la chiave di recupero al sicuro fuori dalla cassaforte.', 'Accedi allo stesso Apple Account sul nuovo iPhone. Apri Mo Layer e segui le indicazioni di recupero; usa la chiave di recupero se quella della cassaforte non è disponibile.', 'Apri i file importanti per verificare il recupero prima di inizializzare il vecchio dispositivo. Gli originali potrebbero scaricarsi all’apertura: mantieni la connessione di rete.'],
    plans: ['Cosa include la versione gratuita e cosa cambia con Pro?', 'La versione gratuita include {storage} di capacità senza limite al numero di file, oltre a backup e ripristino. Pro elimina il limite di {storage} dell’app; restano i limiti del dispositivo e di iCloud. I file esistenti restano accessibili alla scadenza di Pro. Prezzi locali e condizioni di fatturazione sono indicati nella schermata di acquisto dell’App Store.']
  },
  'pt-BR': {
    labels: ['Visão geral do produto', 'Plataforma', 'Privacidade', 'Grátis e Pro', 'Autor', 'Atualizado', 'Guias relacionados', 'Apple: ocultar fotos e vídeos'],
    overview: 'O que é o Mo Layer?',
    comparison: ['O álbum Itens Ocultos da Apple é suficiente?', 'O álbum Itens Ocultos da Apple pode exigir autenticação em sistemas compatíveis e serve para fotos e vídeos. O Mo Layer oferece um arquivo separado para mídia e documentos, com pastas e espaço de disfarce. Escolha conforme os tipos de arquivo, a organização e a recuperação; um app separado não é automaticamente mais seguro.'],
    recovery: ['Como recupero o Mo Layer em um iPhone novo?', 'É necessário ter um backup criptografado no iCloud e acesso à chave do cofre pelas Chaves do iCloud ou pela sua chave de recuperação. Reinstalar o app ou restaurar uma compra Pro não recupera, por si só, arquivos ou chaves ausentes.'],
    steps: ['Antes de trocar de celular, confira se o backup do iCloud foi concluído e guarde sua chave de recuperação em local seguro fora do cofre.', 'Entre na mesma Conta Apple no novo iPhone. Abra o Mo Layer e siga as instruções de recuperação; use sua chave de recuperação se a chave do cofre não estiver disponível.', 'Abra os arquivos importantes para verificar a recuperação antes de apagar o aparelho antigo. Os originais podem ser baixados ao abrir; mantenha a conexão de rede.'],
    plans: ['O que é grátis e o que muda com o Pro?', 'O plano gratuito inclui {storage} de capacidade, sem limite de quantidade de arquivos, além de backup e restauração. O Pro remove o limite de {storage} do app; o armazenamento do aparelho e do iCloud continua sendo necessário. Os arquivos existentes permanecem acessíveis após o vencimento do Pro. Consulte os preços locais e os termos de cobrança na tela de compra da App Store.']
  },
  'nl-NL': {
    labels: ['Productoverzicht', 'Platform', 'Privacy', 'Gratis en Pro', 'Auteur', 'Bijgewerkt', 'Gerelateerde handleidingen', 'Apple: foto’s en video’s verbergen'],
    overview: 'Wat is Mo Layer?',
    comparison: ['Is Apples album Verborgen voldoende?', 'Apples album Verborgen kan op ondersteunde systemen authenticatie vereisen en is geschikt voor foto’s en video’s. Mo Layer biedt een apart archief voor media en documenten, met mappen en een afleidingsruimte. Kies op basis van bestandstypen, ordening en herstel; een aparte app is niet automatisch veiliger.'],
    recovery: ['Hoe herstel ik Mo Layer op een nieuwe iPhone?', 'Je hebt een bestaande versleutelde iCloud-reservekopie nodig en toegang tot de kluissleutel via iCloud-sleutelhanger of je herstelsleutel. Alleen de app opnieuw installeren of een Pro-aankoop herstellen brengt ontbrekende bestanden of sleutels niet terug.'],
    steps: ['Controleer vóór de overstap of de iCloud-reservekopie voltooid is en bewaar je herstelsleutel veilig buiten de kluis.', 'Log op de nieuwe iPhone in met hetzelfde Apple Account. Open Mo Layer en volg de herstelstappen; gebruik je herstelsleutel als de kluissleutel ontbreekt.', 'Open belangrijke bestanden om het herstel te controleren voordat je het oude apparaat wist. Originelen worden mogelijk bij het openen gedownload; zorg voor een netwerkverbinding.'],
    plans: ['Wat is gratis en wat verandert Pro?', 'Gratis omvat {storage} kluisruimte zonder limiet op het aantal bestanden, plus reservekopieën en herstel. Pro verwijdert de app-limiet van {storage}; de opslagruimte van je apparaat en iCloud blijft bepalend. Bestaande bestanden blijven toegankelijk na afloop van Pro. Actuele lokale prijzen en betalingsvoorwaarden staan in het aankoopscherm van de App Store.']
  },
  tr: {
    labels: ['Ürüne genel bakış', 'Platform', 'Gizlilik', 'Ücretsiz ve Pro', 'Yazar', 'Güncellendi', 'İlgili rehberler', 'Apple: fotoğraf ve videoları gizleme'],
    overview: 'Mo Layer nedir?',
    comparison: ['Apple’ın Gizli albümü yeterli mi?', 'Apple’ın Gizli albümü desteklenen sistemlerde kimlik doğrulama isteyebilir ve fotoğraf ile videoları gizlemek için uygundur. Mo Layer, klasörler ve yanıltıcı alan ile medya ve belgeler için ayrı bir arşiv sunar. Dosya türü, düzenleme ve kurtarma ihtiyaçlarına göre seçin; ayrı bir uygulama otomatik olarak daha güvenli değildir.'],
    recovery: ['Mo Layer’ı yeni iPhone’da nasıl kurtarırım?', 'Mevcut bir şifreli iCloud yedeği ve iCloud Anahtar Zinciri veya kurtarma anahtarınız üzerinden kasa anahtarına erişim gerekir. Uygulamayı yeniden yüklemek veya Pro satın alımını geri yüklemek tek başına eksik dosyaları ya da anahtarları geri getirmez.'],
    steps: ['Telefon değiştirmeden önce iCloud yedeklemesinin tamamlandığını kontrol edin ve kurtarma anahtarınızı kasa dışında güvenli bir yerde saklayın.', 'Yeni iPhone’da aynı Apple Hesabı ile giriş yapın. Mo Layer’ı açıp kurtarma yönergelerini izleyin; kasa anahtarı yoksa kurtarma anahtarınızı kullanın.', 'Eski cihazı silmeden önce önemli dosyaları açarak kurtarmayı doğrulayın. Orijinaller açılırken indirilebilir; ağ bağlantısını koruyun.'],
    plans: ['Ücretsiz sürüm neler içerir, Pro neyi değiştirir?', 'Ücretsiz sürüm, dosya sayısı sınırı olmadan {storage} kasa kapasitesi, yedekleme ve geri yükleme sunar. Pro, uygulamanın {storage} sınırını kaldırır; cihaz ve iCloud kapasitesi sınırları geçerliliğini korur. Pro sona erdiğinde mevcut dosyalara erişilebilir. Güncel yerel fiyatlar ve faturalandırma koşulları için App Store satın alma ekranına bakın.']
  },
  ru: {
    labels: ['Обзор продукта', 'Платформа', 'Конфиденциальность', 'Бесплатно и Pro', 'Автор', 'Обновлено', 'Другие руководства', 'Apple: как скрыть фото и видео'],
    overview: 'Что такое Mo Layer?',
    comparison: ['Достаточно ли альбома «Скрытые» от Apple?', 'Альбом «Скрытые» может требовать аутентификацию в поддерживаемых системах и подходит для фото и видео. Mo Layer предоставляет отдельный архив для медиа и документов с папками и отвлекающим пространством. Выбирайте по типам файлов, организации и восстановлению: отдельное приложение не обязательно безопаснее.'],
    recovery: ['Как восстановить Mo Layer на новом iPhone?', 'Нужны существующая зашифрованная резервная копия в iCloud и доступ к ключу хранилища через Связку ключей iCloud или ваш ключ восстановления. Одна лишь переустановка приложения или восстановление покупки Pro не вернёт отсутствующие файлы или ключи.'],
    steps: ['Перед сменой телефона убедитесь, что резервное копирование в iCloud завершено, и сохраните ключ восстановления в безопасном месте вне хранилища.', 'Войдите в тот же Аккаунт Apple на новом iPhone. Откройте Mo Layer и следуйте подсказкам; если ключ хранилища недоступен, используйте ключ восстановления.', 'Откройте важные файлы для проверки, прежде чем стирать старое устройство. Оригиналы могут загружаться при открытии; сохраняйте подключение к сети.'],
    plans: ['Что доступно бесплатно и что меняет Pro?', 'Бесплатно доступны {storage} ёмкости без ограничения числа файлов, резервное копирование и восстановление. Pro снимает ограничение приложения в {storage}; ограничения памяти устройства и iCloud сохраняются. После окончания Pro существующие файлы остаются доступными. Текущие местные цены и условия оплаты указаны на экране покупки App Store.']
  },
  ja: {
    labels: ['製品概要', '対応プラットフォーム', 'プライバシー', '無料版と Pro', '著者', '更新日', '関連ガイド', 'Apple：写真やビデオを非表示にする'],
    overview: 'Mo Layer とは？',
    comparison: ['Apple の「非表示」アルバムで十分ですか？', 'Apple の「非表示」アルバムは、対応システムでは認証を要求でき、写真やビデオを隠す用途に適しています。Mo Layer は、フォルダやおとりのスペースを備え、メディアと書類を別の保管庫で管理します。ファイル形式、整理、復元の必要性で選んでください。独立したアプリが必ずしも安全性で優れるとは限りません。'],
    recovery: ['新しい iPhone で Mo Layer を復元するには？', '既存の暗号化された iCloud バックアップと、iCloud キーチェーンまたは復元キーによる保管庫キーへのアクセスが必要です。アプリの再インストールや Pro の購入復元だけでは、失われたファイルやキーは戻りません。'],
    steps: ['機種変更前に iCloud バックアップの完了を確認し、復元キーを保管庫の外の安全な場所に保存します。', '新しい iPhone で同じ Apple Account にサインインします。Mo Layer を開き復元の案内に従います。保管庫キーが利用できない場合は復元キーを使います。', '旧端末を消去する前に重要なファイルを開いて復元を確認します。オリジナルは開くときにダウンロードされる場合があるため、ネットワーク接続を維持してください。'],
    plans: ['無料版の内容と Pro の違いは？', '無料版はファイル数の制限なしで {storage} の保管庫容量を利用でき、バックアップと復元も含まれます。Pro はアプリの {storage} 制限を解除しますが、端末と iCloud の空き容量は必要です。Pro の終了後も既存ファイルにアクセスできます。最新の地域別価格と請求条件は App Store の購入画面で確認してください。']
  },
  ko: {
    labels: ['제품 개요', '플랫폼', '개인정보 보호', '무료 및 Pro', '작성자', '업데이트', '관련 가이드', 'Apple: 사진 및 비디오 가리기'],
    overview: 'Mo Layer란 무엇인가요?',
    comparison: ['Apple의 가려진 항목 앨범으로 충분한가요?', 'Apple의 가려진 항목 앨범은 지원되는 시스템에서 인증을 요구할 수 있으며 사진과 비디오를 숨기는 데 적합합니다. Mo Layer는 폴더와 위장 공간을 갖춘 별도의 미디어 및 문서 보관함을 제공합니다. 파일 종류, 정리, 복구 필요에 따라 선택하세요. 별도 앱이 반드시 더 안전한 것은 아닙니다.'],
    recovery: ['새 iPhone에서 Mo Layer를 어떻게 복구하나요?', '기존의 암호화된 iCloud 백업과 iCloud 키체인 또는 복구 키를 통한 보관함 키 접근이 필요합니다. 앱을 다시 설치하거나 Pro 구매를 복원하는 것만으로 누락된 파일이나 키를 되찾을 수는 없습니다.'],
    steps: ['휴대폰을 바꾸기 전에 iCloud 백업 완료 여부를 확인하고 복구 키를 보관함 외부의 안전한 곳에 보관하세요.', '새 iPhone에서 동일한 Apple 계정으로 로그인하세요. Mo Layer를 열고 복구 안내를 따르세요. 보관함 키를 사용할 수 없으면 복구 키를 사용하세요.', '이전 기기를 지우기 전에 중요한 파일을 열어 복구를 확인하세요. 원본은 열 때 다운로드될 수 있으므로 네트워크 연결을 유지하세요.'],
    plans: ['무료 버전에는 무엇이 포함되며 Pro는 무엇을 바꾸나요?', '무료 버전은 파일 수 제한 없이 {storage} 보관함 용량과 백업 및 복구를 제공합니다. Pro는 앱의 {storage} 제한을 없애지만 기기와 iCloud 용량 제한은 여전히 적용됩니다. Pro가 만료되어도 기존 파일에 접근할 수 있습니다. 현재 지역별 가격과 결제 조건은 App Store 구매 화면에서 확인하세요.']
  },
  vi: {
    labels: ['Tổng quan sản phẩm', 'Nền tảng', 'Quyền riêng tư', 'Miễn phí và Pro', 'Tác giả', 'Cập nhật', 'Hướng dẫn liên quan', 'Apple: ẩn ảnh và video'],
    overview: 'Mo Layer là gì?',
    comparison: ['Album Bị ẩn của Apple có đủ không?', 'Album Bị ẩn của Apple có thể yêu cầu xác thực trên hệ thống được hỗ trợ và phù hợp để ẩn ảnh, video. Mo Layer cung cấp kho riêng cho nội dung đa phương tiện và tài liệu, với thư mục và không gian ngụy trang. Hãy chọn theo loại tệp, cách sắp xếp và nhu cầu khôi phục; ứng dụng riêng không mặc nhiên an toàn hơn.'],
    recovery: ['Làm sao khôi phục Mo Layer trên iPhone mới?', 'Cần có bản sao lưu iCloud đã mã hóa và quyền truy cập khóa kho qua Chuỗi khóa iCloud hoặc khóa khôi phục của bạn. Chỉ cài lại ứng dụng hoặc khôi phục giao dịch Pro không thể lấy lại tệp hay khóa bị thiếu.'],
    steps: ['Trước khi đổi máy, kiểm tra sao lưu iCloud đã hoàn tất và giữ khóa khôi phục ở nơi an toàn bên ngoài kho.', 'Đăng nhập cùng Tài khoản Apple trên iPhone mới. Mở Mo Layer và làm theo hướng dẫn khôi phục; dùng khóa khôi phục nếu không có khóa kho.', 'Mở các tệp quan trọng để kiểm tra trước khi xóa thiết bị cũ. Bản gốc có thể tải xuống khi mở; hãy duy trì kết nối mạng.'],
    plans: ['Bản miễn phí có gì và Pro thay đổi điều gì?', 'Bản miễn phí có {storage} dung lượng kho, không giới hạn số tệp, cùng sao lưu và khôi phục. Pro bỏ giới hạn {storage} của ứng dụng; dung lượng thiết bị và iCloud vẫn là giới hạn thực tế. Tệp hiện có vẫn truy cập được khi Pro hết hạn. Xem giá địa phương và điều khoản thanh toán hiện hành trên màn hình mua hàng App Store.']
  },
  th: {
    labels: ['ภาพรวมผลิตภัณฑ์', 'แพลตฟอร์ม', 'ความเป็นส่วนตัว', 'ฟรีและ Pro', 'ผู้เขียน', 'อัปเดต', 'คู่มือที่เกี่ยวข้อง', 'Apple: ซ่อนรูปภาพและวิดีโอ'],
    overview: 'Mo Layer คืออะไร?',
    comparison: ['อัลบั้มที่ซ่อนของ Apple เพียงพอหรือไม่?', 'อัลบั้มที่ซ่อนของ Apple สามารถกำหนดให้ยืนยันตัวตนในระบบที่รองรับ และเหมาะสำหรับซ่อนรูปภาพกับวิดีโอ Mo Layer มีคลังแยกสำหรับสื่อและเอกสาร พร้อมโฟลเดอร์และพื้นที่อำพราง เลือกตามประเภทไฟล์ การจัดระเบียบ และความต้องการกู้คืน แอปแยกไม่ได้ปลอดภัยกว่าโดยอัตโนมัติ'],
    recovery: ['จะกู้คืน Mo Layer บน iPhone เครื่องใหม่ได้อย่างไร?', 'ต้องมีข้อมูลสำรอง iCloud ที่เข้ารหัสไว้แล้ว และเข้าถึงกุญแจคลังผ่านพวงกุญแจ iCloud หรือกุญแจกู้คืนของคุณ การติดตั้งแอปใหม่หรือกู้คืนการซื้อ Pro เพียงอย่างเดียวไม่ทำให้ไฟล์หรือกุญแจที่หายไปกลับมา'],
    steps: ['ก่อนเปลี่ยนเครื่อง ตรวจสอบว่าการสำรองข้อมูล iCloud เสร็จสมบูรณ์ และเก็บกุญแจกู้คืนไว้อย่างปลอดภัยนอกคลัง', 'ลงชื่อเข้าบัญชี Apple เดิมบน iPhone เครื่องใหม่ เปิด Mo Layer และทำตามคำแนะนำการกู้คืน หากไม่มีกุญแจคลัง ให้ใช้กุญแจกู้คืน', 'เปิดไฟล์สำคัญเพื่อตรวจสอบการกู้คืนก่อนลบข้อมูลเครื่องเก่า ไฟล์ต้นฉบับอาจดาวน์โหลดเมื่อเปิด จึงควรเชื่อมต่อเครือข่ายไว้'],
    plans: ['เวอร์ชันฟรีมีอะไรบ้าง และ Pro เปลี่ยนอะไร?', 'เวอร์ชันฟรีมีความจุคลัง {storage} โดยไม่จำกัดจำนวนไฟล์ รวมการสำรองและกู้คืนข้อมูล Pro ยกเลิกขีดจำกัด {storage} ของแอป แต่ยังขึ้นอยู่กับพื้นที่อุปกรณ์และ iCloud ไฟล์เดิมยังเข้าถึงได้เมื่อ Pro หมดอายุ ตรวจสอบราคาในพื้นที่และเงื่อนไขเรียกเก็บเงินปัจจุบันที่หน้าซื้อของ App Store']
  },
  id: {
    labels: ['Ringkasan produk', 'Platform', 'Privasi', 'Gratis dan Pro', 'Penulis', 'Diperbarui', 'Panduan terkait', 'Apple: menyembunyikan foto dan video'],
    overview: 'Apa itu Mo Layer?',
    comparison: ['Apakah album Tersembunyi Apple sudah cukup?', 'Album Tersembunyi Apple dapat meminta autentikasi pada sistem yang didukung dan cocok untuk foto serta video. Mo Layer menyediakan arsip terpisah untuk media dan dokumen, dengan folder dan ruang penyamaran. Pilih berdasarkan jenis file, pengaturan, dan kebutuhan pemulihan; aplikasi terpisah tidak otomatis lebih aman.'],
    recovery: ['Bagaimana memulihkan Mo Layer di iPhone baru?', 'Anda memerlukan cadangan iCloud terenkripsi yang sudah ada dan akses ke kunci brankas melalui Rantai Kunci iCloud atau kunci pemulihan Anda. Menginstal ulang aplikasi atau memulihkan pembelian Pro saja tidak mengembalikan file atau kunci yang hilang.'],
    steps: ['Sebelum berganti ponsel, pastikan pencadangan iCloud selesai dan simpan kunci pemulihan dengan aman di luar brankas.', 'Masuk ke Akun Apple yang sama di iPhone baru. Buka Mo Layer dan ikuti petunjuk pemulihan; gunakan kunci pemulihan jika kunci brankas tidak tersedia.', 'Buka file penting untuk memverifikasi pemulihan sebelum menghapus perangkat lama. File asli mungkin diunduh saat dibuka; pertahankan koneksi jaringan.'],
    plans: ['Apa yang gratis dan apa yang diubah Pro?', 'Versi gratis mencakup kapasitas brankas {storage} tanpa batas jumlah file, serta pencadangan dan pemulihan. Pro menghapus batas {storage} aplikasi; kapasitas perangkat dan iCloud tetap berlaku. File yang ada tetap dapat diakses setelah Pro berakhir. Lihat harga lokal dan ketentuan penagihan terbaru di layar pembelian App Store.']
  },
  hi: {
    labels: ['उत्पाद का परिचय', 'प्लैटफ़ॉर्म', 'गोपनीयता', 'मुफ़्त और Pro', 'लेखक', 'अपडेट', 'संबंधित गाइड', 'Apple: फ़ोटो और वीडियो छिपाएँ'],
    overview: 'Mo Layer क्या है?',
    comparison: ['क्या Apple का Hidden ऐल्बम पर्याप्त है?', 'Apple का Hidden ऐल्बम समर्थित सिस्टम पर प्रमाणीकरण माँग सकता है और फ़ोटो व वीडियो छिपाने के लिए उपयोगी है। Mo Layer मीडिया और दस्तावेज़ों के लिए फ़ोल्डर तथा छद्म स्थान वाला अलग संग्रह देता है। फ़ाइल प्रकार, व्यवस्था और रिकवरी की ज़रूरत के अनुसार चुनें; अलग ऐप अपने आप अधिक सुरक्षित नहीं होता।'],
    recovery: ['नए iPhone पर Mo Layer कैसे रिकवर करें?', 'पहले से मौजूद एन्क्रिप्टेड iCloud बैकअप और iCloud Keychain या अपनी रिकवरी कुंजी से वॉल्ट कुंजी तक पहुँच ज़रूरी है। सिर्फ़ ऐप दोबारा इंस्टॉल करने या Pro खरीद बहाल करने से गायब फ़ाइलें या कुंजियाँ वापस नहीं आतीं।'],
    steps: ['फ़ोन बदलने से पहले जाँचें कि iCloud बैकअप पूरा हो गया है और रिकवरी कुंजी को वॉल्ट के बाहर सुरक्षित रखें।', 'नए iPhone पर उसी Apple खाते से साइन इन करें। Mo Layer खोलकर रिकवरी के निर्देशों का पालन करें; वॉल्ट कुंजी उपलब्ध न हो तो रिकवरी कुंजी इस्तेमाल करें।', 'पुराने डिवाइस को मिटाने से पहले ज़रूरी फ़ाइलें खोलकर रिकवरी जाँचें। मूल फ़ाइलें खोलते समय डाउनलोड हो सकती हैं; नेटवर्क कनेक्शन बनाए रखें।'],
    plans: ['मुफ़्त संस्करण में क्या है और Pro क्या बदलता है?', 'मुफ़्त संस्करण में फ़ाइलों की संख्या पर सीमा के बिना {storage} वॉल्ट क्षमता, बैकअप और रिकवरी मिलती है। Pro ऐप की {storage} सीमा हटाता है; डिवाइस और iCloud की क्षमता सीमाएँ बनी रहती हैं। Pro समाप्त होने पर भी मौजूदा फ़ाइलें उपलब्ध रहती हैं। वर्तमान स्थानीय कीमतें और बिलिंग शर्तें App Store की खरीद स्क्रीन पर देखें।']
  },
  ar: {
    labels: ['نظرة عامة على المنتج', 'المنصة', 'الخصوصية', 'المجاني وPro', 'الكاتب', 'آخر تحديث', 'أدلة ذات صلة', 'Apple: إخفاء الصور والفيديو'],
    overview: 'ما هو Mo Layer؟',
    comparison: ['هل يكفي ألبوم «مخفية» من Apple؟', 'يمكن لألبوم «مخفية» من Apple طلب المصادقة على الأنظمة المدعومة، وهو مناسب لإخفاء الصور والفيديو. يوفر Mo Layer أرشيفاً منفصلاً للوسائط والمستندات مع مجلدات ومساحة تمويه. اختر حسب أنواع الملفات والتنظيم والاسترداد؛ التطبيق المنفصل ليس أكثر أماناً تلقائياً.'],
    recovery: ['كيف أسترد Mo Layer على iPhone جديد؟', 'تحتاج إلى نسخة احتياطية مشفرة موجودة في iCloud وإمكانية الوصول إلى مفتاح الخزنة عبر سلسلة مفاتيح iCloud أو مفتاح الاسترداد الخاص بك. إعادة تثبيت التطبيق أو استعادة شراء Pro وحدها لا تعيد الملفات أو المفاتيح المفقودة.'],
    steps: ['قبل تغيير الهاتف، تحقق من اكتمال النسخ الاحتياطي على iCloud واحفظ مفتاح الاسترداد بأمان خارج الخزنة.', 'سجّل الدخول إلى حساب Apple نفسه على iPhone الجديد. افتح Mo Layer واتبع تعليمات الاسترداد؛ استخدم مفتاح الاسترداد إذا لم يتوفر مفتاح الخزنة.', 'افتح الملفات المهمة للتحقق من الاسترداد قبل مسح الجهاز القديم. قد تُنزّل الملفات الأصلية عند فتحها؛ أبقِ اتصال الشبكة متاحاً.'],
    plans: ['ما الذي تتضمنه النسخة المجانية وما الذي يغيّره Pro؟', 'تشمل النسخة المجانية سعة خزنة قدرها {storage} دون حد لعدد الملفات، مع النسخ الاحتياطي والاسترداد. يزيل Pro حد التطبيق البالغ {storage}؛ وتظل حدود سعة الجهاز وiCloud قائمة. تبقى الملفات الحالية متاحة بعد انتهاء Pro. راجع الأسعار المحلية وشروط الفوترة الحالية في شاشة الشراء في App Store.']
  }
};

export const aeoContentUpdatedAt = aeoUpdatedAt;
export const appleHiddenAlbumUrl = 'https://support.apple.com/guide/personal-safety/hide-photos-and-videos-ipsb4de8251c/web';

export function getAeoCopy(locale: LocaleCode) {
  const copy = text[locale];
  const [overview, platform, privacy, plans, author, updated, related, source] = copy.labels;
  const toAnswer = ([question, answer]: [string, string]) => ({ question, answer });
  const plan = toAnswer([copy.plans[0], copy.plans[1].replaceAll('{storage}', `${productFacts.freeStorageGB} GB`)]);
  return {
    labels: { overview, platform, privacy, plans, author, updated, related, source },
    overview: copy.overview,
    comparison: toAnswer(copy.comparison),
    recovery: toAnswer(copy.recovery),
    steps: copy.steps,
    plan,
    faq: [toAnswer(copy.comparison), toAnswer(copy.recovery), plan]
  };
}

export function articleAnswers(locale: LocaleCode, translationKey: string) {
  const copy = getAeoCopy(locale);
  switch (translationKey) {
    case 'privacy-first-file-vault':
      return [copy.comparison, copy.recovery];
    case 'private-photo-vault-checklist':
      return copy.faq;
    case 'hidden-album-vs-private-vault':
      return [];
    case 'is-private-photo-vault-safe':
    case 'encrypted-icloud-private-vault':
      return [copy.recovery, copy.plan];
    default:
      return [];
  }
}

export function articleUpdatedAt(locale: LocaleCode, translationKey: string, original: string) {
  return articleAnswers(locale, translationKey).length ? [original, aeoContentUpdatedAt].sort().at(-1)! : original;
}
