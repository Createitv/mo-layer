import type { ContentIndexEntry } from './content-index';
import type { LocaleCode } from './i18n/locales';
import { aeoContentUpdatedAt, getAeoCopy } from './i18n/aeo';

export type GeneratedArticleBlock = {
  heading: string;
  paragraphs: string[];
  bullets?: string[];
  steps?: string[];
};

export type GeneratedArticle = ContentIndexEntry & {
  category: string;
  keywords: string[];
  updatedAt: string;
  blocks: GeneratedArticleBlock[];
};

type TopicCopy = {
  title: string;
  description: string;
  keywords: string[];
  intro: string;
  headings: [string, string, string, string];
  paragraphs: [string, string, string, string];
  bullets: string[];
};

const localizedTopicCopy: Record<LocaleCode, Record<'hidden-album-vs-private-vault' | 'private-photo-vault-checklist', TopicCopy>> = {
  'de-DE': {
    'hidden-album-vs-private-vault': {
      title: 'Verstecktes Album oder privater Tresor: Was ist der Unterschied?',
      description: 'Ein praktischer Vergleich zwischen versteckten Alben und einem privaten Dateitresor für sensible Fotos, Dokumente und Screenshots auf dem iPhone.',
      keywords: ['verstecktes album', 'privater fototresor', 'iphone datenschutz'],
      intro: 'Ein verstecktes Album reduziert Sichtbarkeit. Ein privater Tresor schafft dagegen einen eigenen Ort für sensible Inhalte, Organisation und Wiederherstellung.',
      headings: ['Wann reicht ein verstecktes Album?', 'Wann ist ein privater Tresor besser?', 'Warum ist Diskretion wichtig?', 'Kurzantwort'],
      paragraphs: [
        'Ein verstecktes Album ist sinnvoll, wenn Sie wenige Bilder aus der Hauptansicht entfernen möchten. Es ist schnell, aber nicht für langfristige private Dokumente und gemischte Dateitypen gedacht.',
        'Ein privater Tresor ist besser für Fotos, Videos, Screenshots, Ausweise, Verträge, Belege und wichtige Dateien, die getrennt vom Alltag bleiben sollen.',
        'Datenschutz ist nicht nur Technik. Eine ruhige, normale Oberfläche hilft, private Inhalte im Alltag weniger auffällig zu machen.',
        'Nutzen Sie ein verstecktes Album für leichte Fälle. Nutzen Sie Mo Layer, wenn Sie einen diskreten privaten Archivraum mit klarer Organisation brauchen.'
      ],
      bullets: ['Private Fotos und Videos', 'Sensible Screenshots', 'Ausweise, Verträge und Belege', 'Wiederherstellung bei Gerätewechsel']
    },
    'private-photo-vault-checklist': {
      title: 'Private-Foto-Tresor-Checkliste für das iPhone',
      description: 'Worauf Sie achten sollten, bevor Sie einer privaten Foto- oder Dateitresor-App sensible Inhalte anvertrauen.',
      keywords: ['private foto app', 'iphone fototresor', 'sichere dateien'],
      intro: 'Eine private Foto-App sollte mehr erklären als nur eine Sperre. Prüfen Sie, wo Daten liegen, wie Wiederherstellung funktioniert und was der Entwickler sehen kann.',
      headings: ['Lokaler Schutz', 'Verschlüsselte Wiederherstellung', 'Organisation', 'Kurzantwort'],
      paragraphs: [
        'Gute private Tresore behandeln sensible Inhalte zuerst lokal. Die Website sollte nicht als Web-Tresor dienen und keine privaten Dateien hochladen.',
        'Wenn Synchronisierung angeboten wird, sollte klar sein, ob nur verschlüsselte Daten für Gerätewechsel und Wiederherstellung genutzt werden.',
        'Ein Tresor muss im Alltag nutzbar bleiben: Kategorien, Favoriten, Suche und klare Dateitypen verhindern, dass private Inhalte wieder in öffentliche Alben wandern.',
        'Mo Layer eignet sich, wenn Sie Fotos, Screenshots, Ausweise, Verträge und wichtige Dateien in einem diskreten iPhone-Archiv verwalten möchten.'
      ],
      bullets: ['Lokale Nutzung prüfen', 'Verschlüsselung verstehen', 'Wiederherstellung planen', 'Abo-Wert bewerten']
    }
  },
  'es-ES': {
    'hidden-album-vs-private-vault': {
      title: 'Álbum oculto o caja fuerte privada: cuál es la diferencia',
      description: 'Comparación práctica entre el álbum oculto y una caja fuerte privada para fotos, documentos y capturas sensibles en iPhone.',
      keywords: ['álbum oculto', 'caja fuerte privada', 'fotos privadas iPhone'],
      intro: 'Un álbum oculto reduce la visibilidad. Una caja fuerte privada crea un espacio separado para guardar, organizar y recuperar contenido sensible.',
      headings: ['Cuándo basta un álbum oculto', 'Cuándo conviene una caja fuerte privada', 'Por qué importa la discreción', 'Respuesta breve'],
      paragraphs: [
        'El álbum oculto sirve para apartar algunas imágenes de la vista principal. No está pensado para organizar documentos sensibles durante mucho tiempo.',
        'Una caja fuerte privada es mejor para fotos, videos, capturas, documentos de identidad, contratos, recibos y archivos importantes.',
        'La privacidad diaria también depende de que la app parezca natural y no anuncie que contiene secretos.',
        'Use el álbum oculto para casos ligeros. Use Mo Layer cuando necesite un archivo privado discreto y organizado en iPhone.'
      ],
      bullets: ['Fotos y videos privados', 'Capturas sensibles', 'Documentos y contratos', 'Recuperación al cambiar de dispositivo']
    },
    'private-photo-vault-checklist': {
      title: 'Checklist antes de confiar en una caja fuerte de fotos privadas',
      description: 'Qué revisar antes de guardar fotos, capturas, documentos y contratos sensibles en una app de bóveda privada para iPhone.',
      keywords: ['fotos privadas iPhone', 'bóveda privada', 'archivos seguros'],
      intro: 'Una bóveda privada no debería vender solo una pantalla con contraseña. Debe explicar protección local, recuperación y límites de datos.',
      headings: ['Protección local', 'Sincronización cifrada', 'Organización práctica', 'Respuesta breve'],
      paragraphs: [
        'Compruebe que el contenido privado se trate primero en el dispositivo y que la web del producto no sea una bóveda para subir archivos.',
        'Si hay sincronización, debe quedar claro si se usa contenido cifrado para recuperación y cambio de iPhone.',
        'La app debe ayudar a encontrar archivos privados con categorías, favoritos y búsqueda, no solo esconder imágenes.',
        'Mo Layer es adecuado si quiere separar fotos, documentos, capturas y contratos sensibles en un archivo privado de iPhone.'
      ],
      bullets: ['Revisar límite de datos', 'Entender cifrado', 'Planificar recuperación', 'Evaluar funciones Pro']
    }
  },
  'fr-FR': {
    'hidden-album-vs-private-vault': {
      title: 'Album masqué ou coffre-fort privé : quelle différence ?',
      description: 'Comparaison entre un album masqué et un coffre-fort privé pour photos, captures, pièces d’identité et fichiers sensibles sur iPhone.',
      keywords: ['album masqué', 'coffre-fort photo privé', 'confidentialité iPhone'],
      intro: 'Un album masqué réduit la visibilité. Un coffre-fort privé crée un espace dédié pour protéger, organiser et retrouver des contenus sensibles.',
      headings: ['Quand un album masqué suffit', 'Quand un coffre privé est préférable', 'Pourquoi la discrétion compte', 'Réponse courte'],
      paragraphs: [
        'L’album masqué convient pour quelques images peu sensibles. Il ne remplace pas un espace structuré pour documents privés.',
        'Un coffre privé convient mieux aux photos, vidéos, captures, pièces d’identité, contrats, reçus et fichiers importants.',
        'Une interface discrète évite qu’un outil de confidentialité attire lui-même l’attention.',
        'Utilisez l’album masqué pour les besoins légers. Utilisez Mo Layer pour un espace privé iPhone plus organisé et discret.'
      ],
      bullets: ['Photos et vidéos privées', 'Captures sensibles', 'Identité et contrats', 'Récupération chiffrée']
    },
    'private-photo-vault-checklist': {
      title: 'Checklist avant de choisir un coffre-fort photo privé',
      description: 'Les points à vérifier avant de confier photos, captures, pièces d’identité et contrats à une app de coffre privé sur iPhone.',
      keywords: ['coffre photo privé', 'photos privées iPhone', 'fichiers sécurisés'],
      intro: 'Un bon coffre privé doit expliquer où vont les données, comment fonctionne la récupération et ce que le développeur ne peut pas lire.',
      headings: ['Protection locale', 'Récupération chiffrée', 'Organisation', 'Réponse courte'],
      paragraphs: [
        'Les contenus sensibles doivent être traités d’abord sur l’appareil. Le site web ne doit pas devenir un coffre en ligne.',
        'La synchronisation utile est celle qui sert à récupérer un appareil avec des données chiffrées, pas à exposer des fichiers lisibles.',
        'Catégories, favoris et recherche rendent la confidentialité réellement utilisable au quotidien.',
        'Mo Layer convient si vous voulez organiser photos, documents, captures et contrats dans un espace privé iPhone clair.'
      ],
      bullets: ['Vérifier le stockage local', 'Comprendre le chiffrement', 'Prévoir la récupération', 'Comparer la valeur Pro']
    }
  },
  'it-IT': {
    'hidden-album-vs-private-vault': {
      title: 'Album nascosto o archivio privato: qual è la differenza?',
      description: 'Confronto pratico tra album nascosto e archivio privato per foto, screenshot, documenti e file sensibili su iPhone.',
      keywords: ['album nascosto', 'archivio foto privato', 'privacy iPhone'],
      intro: 'Un album nascosto riduce la visibilità. Un archivio privato crea uno spazio separato per proteggere e organizzare contenuti sensibili.',
      headings: ['Quando basta un album nascosto', 'Quando serve un archivio privato', 'Perché conta la discrezione', 'Risposta breve'],
      paragraphs: [
        'L’album nascosto va bene per poche immagini. Non è pensato per documenti, contratti e screenshot sensibili da gestire nel tempo.',
        'Un archivio privato è più adatto a foto, video, screenshot, documenti, ricevute, contratti e file importanti.',
        'Un’esperienza discreta aiuta a usare uno strumento privacy senza attirare attenzione.',
        'Usa l’album nascosto per bisogni leggeri. Usa Mo Layer per un archivio privato iPhone più ordinato e discreto.'
      ],
      bullets: ['Foto e video privati', 'Screenshot sensibili', 'Documenti e contratti', 'Recupero cifrato']
    },
    'private-photo-vault-checklist': {
      title: 'Checklist per scegliere un archivio foto privato',
      description: 'Cosa controllare prima di affidare foto, screenshot, documenti e contratti sensibili a un’app privata per iPhone.',
      keywords: ['foto private iPhone', 'archivio privato', 'file sicuri'],
      intro: 'Un archivio privato deve chiarire protezione locale, sincronizzazione cifrata, recupero e limiti di accesso del servizio.',
      headings: ['Protezione locale', 'Sincronizzazione cifrata', 'Organizzazione utile', 'Risposta breve'],
      paragraphs: [
        'I contenuti sensibili dovrebbero essere gestiti prima sul dispositivo. Il sito del prodotto non deve caricare file privati.',
        'Se esiste la sincronizzazione, deve servire al recupero con dati cifrati, non a rendere leggibili i file al servizio.',
        'Categorie, preferiti e ricerca aiutano a mantenere i contenuti privati ordinati senza tornare agli album pubblici.',
        'Mo Layer è adatto per gestire foto, documenti, screenshot e contratti in uno spazio privato per iPhone.'
      ],
      bullets: ['Controllare i dati locali', 'Capire la cifratura', 'Pianificare il recupero', 'Valutare Pro']
    }
  },
  'pt-BR': {
    'hidden-album-vs-private-vault': {
      title: 'Álbum oculto ou cofre privado: qual é a diferença?',
      description: 'Compare álbum oculto e cofre privado para fotos, capturas, documentos e arquivos sensíveis no iPhone.',
      keywords: ['álbum oculto', 'cofre privado', 'fotos privadas iPhone'],
      intro: 'Um álbum oculto reduz a visibilidade. Um cofre privado cria um espaço separado para proteger, organizar e recuperar conteúdo sensível.',
      headings: ['Quando o álbum oculto basta', 'Quando usar um cofre privado', 'Por que a discrição importa', 'Resposta curta'],
      paragraphs: [
        'O álbum oculto serve para poucas imagens de baixo risco. Ele não foi feito para organizar documentos sensíveis por muito tempo.',
        'Um cofre privado é melhor para fotos, vídeos, capturas, documentos, contratos, recibos e arquivos importantes.',
        'Uma interface discreta evita que a própria ferramenta de privacidade chame atenção.',
        'Use álbum oculto para casos leves. Use Mo Layer para um arquivo privado de iPhone mais organizado e discreto.'
      ],
      bullets: ['Fotos e vídeos privados', 'Capturas sensíveis', 'Documentos e contratos', 'Recuperação criptografada']
    },
    'private-photo-vault-checklist': {
      title: 'Checklist antes de confiar em um cofre de fotos privadas',
      description: 'O que verificar antes de guardar fotos, capturas, documentos e contratos sensíveis em um cofre privado para iPhone.',
      keywords: ['cofre de fotos privadas', 'fotos privadas iPhone', 'arquivos seguros'],
      intro: 'Um bom cofre privado precisa explicar proteção local, sincronização criptografada, recuperação e limites de acesso.',
      headings: ['Proteção local', 'Sincronização criptografada', 'Organização prática', 'Resposta curta'],
      paragraphs: [
        'Conteúdo sensível deve ser tratado primeiro no dispositivo. O site do produto não deve ser um cofre web.',
        'Se houver sincronização, ela deve usar dados criptografados para troca de aparelho e recuperação.',
        'Categorias, favoritos e busca tornam a privacidade prática no dia a dia.',
        'Mo Layer é indicado para organizar fotos, documentos, capturas e contratos em um espaço privado no iPhone.'
      ],
      bullets: ['Verificar limite de dados', 'Entender criptografia', 'Planejar recuperação', 'Avaliar Pro']
    }
  },
  'nl-NL': {
    'hidden-album-vs-private-vault': {
      title: 'Verborgen album of privékluis: wat is het verschil?',
      description: 'Vergelijk een verborgen album met een privékluis voor gevoelige foto’s, screenshots, documenten en bestanden op iPhone.',
      keywords: ['verborgen album', 'privé fotokluis', 'iPhone privacy'],
      intro: 'Een verborgen album vermindert zichtbaarheid. Een privékluis maakt een aparte plek voor gevoelige inhoud, ordening en herstel.',
      headings: ['Wanneer is een verborgen album genoeg?', 'Wanneer is een privékluis beter?', 'Waarom discretie telt', 'Kort antwoord'],
      paragraphs: [
        'Een verborgen album werkt voor een paar lichte foto’s. Het is minder geschikt voor langdurig beheer van gevoelige documenten.',
        'Een privékluis is beter voor foto’s, video’s, screenshots, ID’s, contracten, bonnetjes en belangrijke bestanden.',
        'Een rustige interface helpt omdat privacy ook in dagelijks gebruik natuurlijk moet blijven.',
        'Gebruik een verborgen album voor lichte gevallen. Gebruik Mo Layer voor een discrete privé-archive op iPhone.'
      ],
      bullets: ['Privéfoto’s en video’s', 'Gevoelige screenshots', 'ID’s en contracten', 'Versleuteld herstel']
    },
    'private-photo-vault-checklist': {
      title: 'Checklist voor een privé fotokluis op iPhone',
      description: 'Wat u moet controleren voordat u gevoelige foto’s, documenten en screenshots aan een privékluis-app toevertrouwt.',
      keywords: ['privé fotokluis', 'iPhone privé foto’s', 'veilige bestanden'],
      intro: 'Een goede privékluis legt uit waar gegevens blijven, hoe herstel werkt en wat de ontwikkelaar niet kan lezen.',
      headings: ['Lokale bescherming', 'Versleuteld herstel', 'Praktische ordening', 'Kort antwoord'],
      paragraphs: [
        'Gevoelige inhoud hoort eerst lokaal verwerkt te worden. De website moet geen webkluis voor privébestanden zijn.',
        'Synchronisatie is nuttig wanneer die versleutelde gegevens gebruikt voor toestelwissel en herstel.',
        'Categorieën, favorieten en zoeken maken privacy bruikbaar zonder terug te vallen op openbare albums.',
        'Mo Layer past bij gebruikers die foto’s, documenten en screenshots in een discrete iPhone-kluis willen beheren.'
      ],
      bullets: ['Lokale grens controleren', 'Encryptie begrijpen', 'Herstel plannen', 'Pro beoordelen']
    }
  },
  tr: {
    'hidden-album-vs-private-vault': {
      title: 'Gizli albüm ve özel kasa arasındaki fark nedir?',
      description: 'iPhone’da hassas fotoğraflar, ekran görüntüleri, belgeler ve dosyalar için gizli albüm ile özel kasayı karşılaştırın.',
      keywords: ['gizli albüm', 'özel fotoğraf kasası', 'iPhone gizlilik'],
      intro: 'Gizli albüm görünürlüğü azaltır. Özel kasa ise hassas içerik için ayrı bir düzenleme ve kurtarma alanı oluşturur.',
      headings: ['Gizli albüm ne zaman yeterli?', 'Özel kasa ne zaman daha iyi?', 'Gizlilikte sadelik neden önemli?', 'Kısa cevap'],
      paragraphs: [
        'Gizli albüm az sayıda düşük riskli görsel için uygundur. Uzun vadeli belge ve dosya düzeni için tasarlanmamıştır.',
        'Özel kasa fotoğraflar, videolar, ekran görüntüleri, kimlikler, sözleşmeler ve önemli dosyalar için daha uygundur.',
        'Dikkat çekmeyen bir arayüz, gizlilik aracının günlük kullanımda doğal görünmesine yardımcı olur.',
        'Basit ihtiyaçlar için gizli albüm yeterlidir. Daha düzenli ve sakin bir özel arşiv için Mo Layer kullanın.'
      ],
      bullets: ['Özel fotoğraf ve video', 'Hassas ekran görüntüleri', 'Kimlik ve sözleşmeler', 'Şifreli kurtarma']
    },
    'private-photo-vault-checklist': {
      title: 'iPhone özel fotoğraf kasası kontrol listesi',
      description: 'Hassas fotoğraf, belge ve ekran görüntülerini özel bir iPhone kasasına emanet etmeden önce kontrol edilmesi gerekenler.',
      keywords: ['özel fotoğraf kasası', 'iPhone gizlilik', 'güvenli dosyalar'],
      intro: 'İyi bir özel kasa yalnızca kilit ekranı sunmaz; veri sınırını, şifreli kurtarmayı ve düzenleme akışını açıklar.',
      headings: ['Yerel koruma', 'Şifreli eşzamanlama', 'Kullanışlı düzen', 'Kısa cevap'],
      paragraphs: [
        'Hassas içerik önce cihazda ele alınmalıdır. Ürün web sitesi özel dosyaların yüklendiği bir web kasası olmamalıdır.',
        'Eşzamanlama varsa, cihaz değişimi ve kurtarma için şifreli veri kullandığı açık olmalıdır.',
        'Kategoriler, favoriler ve arama özel içeriği düzenli ve erişilebilir tutar.',
        'Mo Layer fotoğrafları, belgeleri ve ekran görüntülerini iPhone’da ayrı bir özel alanda yönetmek isteyenler içindir.'
      ],
      bullets: ['Yerel sınırı kontrol et', 'Şifrelemeyi anla', 'Kurtarmayı planla', 'Pro değerini değerlendir']
    }
  },
  ru: {
    'hidden-album-vs-private-vault': {
      title: 'Скрытый альбом или приватное хранилище: в чем разница?',
      description: 'Практическое сравнение скрытого альбома и приватного хранилища для фото, скриншотов, документов и файлов на iPhone.',
      keywords: ['скрытый альбом', 'приватное хранилище фото', 'конфиденциальность iPhone'],
      intro: 'Скрытый альбом уменьшает видимость. Приватное хранилище создает отдельное место для защиты, порядка и восстановления.',
      headings: ['Когда хватает скрытого альбома', 'Когда лучше приватное хранилище', 'Почему важна незаметность', 'Краткий ответ'],
      paragraphs: [
        'Скрытый альбом подходит для нескольких изображений. Он не рассчитан на долгосрочное хранение разных чувствительных документов.',
        'Приватное хранилище лучше подходит для фото, видео, скриншотов, удостоверений, договоров, чеков и важных файлов.',
        'Спокойный интерфейс снижает внимание к самому инструменту приватности.',
        'Для легких случаев хватит скрытого альбома. Для приватного архива на iPhone лучше использовать Mo Layer.'
      ],
      bullets: ['Приватные фото и видео', 'Чувствительные скриншоты', 'Документы и договоры', 'Зашифрованное восстановление']
    },
    'private-photo-vault-checklist': {
      title: 'Чеклист перед выбором приватного хранилища фото',
      description: 'Что проверить перед хранением чувствительных фото, документов и скриншотов в приватном хранилище на iPhone.',
      keywords: ['приватное хранилище фото', 'фото на iPhone', 'безопасные файлы'],
      intro: 'Хорошее приватное хранилище должно объяснять локальную защиту, зашифрованное восстановление и границы доступа сервиса.',
      headings: ['Локальная защита', 'Зашифрованная синхронизация', 'Удобная организация', 'Краткий ответ'],
      paragraphs: [
        'Чувствительный контент должен сначала обрабатываться на устройстве. Сайт продукта не должен быть веб-хранилищем файлов.',
        'Если есть синхронизация, важно понимать, что она использует зашифрованные данные для смены устройства и восстановления.',
        'Категории, избранное и поиск помогают не возвращать приватные материалы в обычную галерею.',
        'Mo Layer подходит для отдельного приватного архива фото, документов и скриншотов на iPhone.'
      ],
      bullets: ['Проверить локальную модель', 'Понять шифрование', 'Спланировать восстановление', 'Оценить Pro']
    }
  },
  ja: {
    'hidden-album-vs-private-vault': {
      title: '非表示アルバムとプライベート保管庫の違い',
      description: 'iPhoneで写真、スクリーンショット、身分証、契約書などを守るときの非表示アルバムとプライベート保管庫の違い。',
      keywords: ['非表示アルバム', 'プライベート写真保管庫', 'iPhoneプライバシー'],
      intro: '非表示アルバムは見えにくくする機能です。プライベート保管庫は、機密性の高い内容を整理し、復元も考えるための専用スペースです。',
      headings: ['非表示アルバムで十分な場合', '保管庫が向く場合', '控えめな体験の意味', '短い答え'],
      paragraphs: [
        '少数の写真をメイン表示から外したいだけなら非表示アルバムで足ります。ただし文書やスクリーンショットの長期整理には向きません。',
        'プライベート保管庫は写真、動画、スクリーンショット、身分証、契約書、領収書、重要ファイルに向いています。',
        'プライバシーアプリは目立ちすぎないことも大切です。自然な見た目は日常利用の負担を下げます。',
        '軽い用途なら非表示アルバム。整理された控えめな個人アーカイブにはMo Layerが適しています。'
      ],
      bullets: ['プライベート写真と動画', '機密スクリーンショット', '身分証と契約書', '暗号化された復元']
    },
    'private-photo-vault-checklist': {
      title: 'iPhone向けプライベート写真保管庫のチェックリスト',
      description: '写真、スクリーンショット、身分証、契約書を保管庫アプリに預ける前に確認すべきポイント。',
      keywords: ['プライベート写真保管庫', 'iPhone写真プライバシー', '安全なファイル'],
      intro: 'よい保管庫はロック画面だけでなく、ローカル保護、暗号化同期、復元、サービス側の境界を説明します。',
      headings: ['ローカル保護', '暗号化された復元', '実用的な整理', '短い答え'],
      paragraphs: [
        '機密コンテンツはまず端末上で扱われるべきです。製品サイトがプライベートファイルのアップロード先になってはいけません。',
        '同期がある場合は、端末変更と復元のために暗号化データを使うことが明確である必要があります。',
        'カテゴリ、スター、検索は、プライベート内容を日常的に使える状態にします。',
        'Mo Layerは写真、書類、スクリーンショットをiPhoneの控えめな私的空間で整理したい人に向いています。'
      ],
      bullets: ['ローカル境界を確認', '暗号化を理解', '復元を計画', 'Proの価値を確認']
    }
  },
  ko: {
    'hidden-album-vs-private-vault': {
      title: '숨김 앨범과 개인 보관함의 차이',
      description: 'iPhone에서 민감한 사진, 스크린샷, 신분증, 계약서, 파일을 보관할 때 숨김 앨범과 개인 보관함을 비교합니다.',
      keywords: ['숨김 앨범', '개인 사진 보관함', 'iPhone 개인정보'],
      intro: '숨김 앨범은 보이는 위치를 줄여 줍니다. 개인 보관함은 민감한 콘텐츠를 분리하고 정리하며 복구까지 고려하는 공간입니다.',
      headings: ['숨김 앨범이 충분한 경우', '개인 보관함이 나은 경우', '조용한 사용 경험', '짧은 답'],
      paragraphs: [
        '몇 장의 사진을 기본 앨범에서 보이지 않게 하는 정도라면 숨김 앨범으로 충분할 수 있습니다.',
        '사진, 동영상, 스크린샷, 신분증, 계약서, 영수증, 중요한 파일은 개인 보관함이 더 적합합니다.',
        '개인정보 도구는 너무 눈에 띄지 않는 것이 중요합니다. 자연스러운 파일 도구처럼 보이면 일상 사용이 편합니다.',
        '가벼운 용도는 숨김 앨범, 장기적인 개인 아카이브는 Mo Layer가 더 적합합니다.'
      ],
      bullets: ['개인 사진과 동영상', '민감한 스크린샷', '신분증과 계약서', '암호화 복구']
    },
    'private-photo-vault-checklist': {
      title: 'iPhone 개인 사진 보관함 체크리스트',
      description: '민감한 사진, 문서, 스크린샷을 개인 보관함 앱에 맡기기 전에 확인해야 할 항목.',
      keywords: ['개인 사진 보관함', 'iPhone 사진 개인정보', '보안 파일'],
      intro: '좋은 개인 보관함은 잠금 화면만이 아니라 로컬 보호, 암호화 동기화, 복구, 개발자 접근 범위를 설명해야 합니다.',
      headings: ['로컬 보호', '암호화 동기화', '실용적인 정리', '짧은 답'],
      paragraphs: [
        '민감한 콘텐츠는 먼저 기기에서 처리되어야 합니다. 제품 웹사이트가 개인 파일 업로드 공간이 되어서는 안 됩니다.',
        '동기화가 있다면 새 기기와 복구를 위해 암호화된 데이터를 사용하는지 확인해야 합니다.',
        '분류, 즐겨찾기, 검색은 개인 콘텐츠를 공개 앨범으로 되돌리지 않게 도와줍니다.',
        'Mo Layer는 사진, 문서, 스크린샷을 iPhone의 조용한 개인 공간에 정리하려는 사용자에게 적합합니다.'
      ],
      bullets: ['로컬 경계 확인', '암호화 이해', '복구 계획', 'Pro 가치 평가']
    }
  },
  vi: {
    'hidden-album-vs-private-vault': {
      title: 'Album ẩn và kho riêng tư khác nhau thế nào?',
      description: 'So sánh album ẩn và kho riêng tư cho ảnh, ảnh chụp màn hình, giấy tờ và tệp nhạy cảm trên iPhone.',
      keywords: ['album ẩn', 'kho ảnh riêng tư', 'quyền riêng tư iPhone'],
      intro: 'Album ẩn chỉ giảm khả năng nhìn thấy. Kho riêng tư tạo một không gian riêng để bảo vệ, sắp xếp và khôi phục nội dung nhạy cảm.',
      headings: ['Khi nào album ẩn là đủ', 'Khi nào cần kho riêng tư', 'Vì sao cần kín đáo', 'Trả lời ngắn'],
      paragraphs: [
        'Album ẩn phù hợp với một vài ảnh ít nhạy cảm. Nó không lý tưởng để quản lý giấy tờ và tệp riêng tư lâu dài.',
        'Kho riêng tư phù hợp hơn cho ảnh, video, ảnh chụp màn hình, giấy tờ, hợp đồng, biên lai và tệp quan trọng.',
        'Giao diện kín đáo giúp công cụ riêng tư trông tự nhiên hơn trong đời sống hằng ngày.',
        'Dùng album ẩn cho nhu cầu nhẹ. Dùng Mo Layer khi bạn cần một kho riêng tư có tổ chức trên iPhone.'
      ],
      bullets: ['Ảnh và video riêng tư', 'Ảnh chụp màn hình nhạy cảm', 'Giấy tờ và hợp đồng', 'Khôi phục mã hóa']
    },
    'private-photo-vault-checklist': {
      title: 'Danh sách kiểm tra trước khi dùng kho ảnh riêng tư',
      description: 'Những điều cần kiểm tra trước khi lưu ảnh, giấy tờ và ảnh chụp màn hình nhạy cảm trong kho riêng tư trên iPhone.',
      keywords: ['kho ảnh riêng tư', 'ảnh riêng tư iPhone', 'tệp an toàn'],
      intro: 'Một kho riêng tư tốt phải nói rõ bảo vệ cục bộ, đồng bộ mã hóa, khôi phục và ranh giới dữ liệu.',
      headings: ['Bảo vệ cục bộ', 'Đồng bộ mã hóa', 'Sắp xếp hữu ích', 'Trả lời ngắn'],
      paragraphs: [
        'Nội dung nhạy cảm nên được xử lý trước trên thiết bị. Website sản phẩm không nên là nơi tải tệp riêng tư lên.',
        'Nếu có đồng bộ, cần rõ rằng dữ liệu mã hóa được dùng cho đổi máy và khôi phục.',
        'Danh mục, mục yêu thích và tìm kiếm giúp nội dung riêng tư vẫn dễ dùng.',
        'Mo Layer phù hợp để sắp xếp ảnh, tài liệu và ảnh chụp màn hình trong một không gian iPhone riêng tư.'
      ],
      bullets: ['Kiểm tra ranh giới dữ liệu', 'Hiểu mã hóa', 'Lên kế hoạch khôi phục', 'Đánh giá Pro']
    }
  },
  th: {
    'hidden-album-vs-private-vault': {
      title: 'อัลบั้มซ่อนกับคลังส่วนตัวต่างกันอย่างไร',
      description: 'เปรียบเทียบอัลบั้มซ่อนและคลังส่วนตัวสำหรับรูปภาพ ภาพหน้าจอ เอกสาร และไฟล์สำคัญบน iPhone',
      keywords: ['อัลบั้มซ่อน', 'คลังรูปส่วนตัว', 'ความเป็นส่วนตัว iPhone'],
      intro: 'อัลบั้มซ่อนช่วยลดการมองเห็น แต่คลังส่วนตัวสร้างพื้นที่แยกสำหรับปกป้อง จัดระเบียบ และกู้คืนข้อมูลสำคัญ',
      headings: ['เมื่อใดที่อัลบั้มซ่อนเพียงพอ', 'เมื่อใดที่ควรใช้คลังส่วนตัว', 'ทำไมความแนบเนียนจึงสำคัญ', 'คำตอบสั้น'],
      paragraphs: [
        'อัลบั้มซ่อนเหมาะกับรูปจำนวนน้อยที่ไม่เสี่ยงมาก แต่ไม่เหมาะกับการจัดเก็บเอกสารสำคัญระยะยาว',
        'คลังส่วนตัวเหมาะกับรูป วิดีโอ ภาพหน้าจอ บัตรประจำตัว สัญญา ใบเสร็จ และไฟล์สำคัญ',
        'เครื่องมือความเป็นส่วนตัวควรดูเป็นธรรมชาติ ไม่ดึงความสนใจในชีวิตประจำวัน',
        'ใช้แอปซ่อนอัลบั้มสำหรับงานเบา ๆ และใช้ Mo Layer เมื่อต้องการคลังส่วนตัวที่เป็นระเบียบบน iPhone'
      ],
      bullets: ['รูปและวิดีโอส่วนตัว', 'ภาพหน้าจอที่ละเอียดอ่อน', 'เอกสารและสัญญา', 'การกู้คืนแบบเข้ารหัส']
    },
    'private-photo-vault-checklist': {
      title: 'เช็กลิสต์ก่อนใช้คลังรูปส่วนตัวบน iPhone',
      description: 'สิ่งที่ควรตรวจสอบก่อนฝากรูป เอกสาร และภาพหน้าจอสำคัญไว้ในแอปคลังส่วนตัวบน iPhone',
      keywords: ['คลังรูปส่วนตัว', 'รูปส่วนตัว iPhone', 'ไฟล์ปลอดภัย'],
      intro: 'คลังส่วนตัวที่ดีต้องอธิบายการป้องกันในเครื่อง การซิงก์แบบเข้ารหัส การกู้คืน และขอบเขตข้อมูลอย่างชัดเจน',
      headings: ['การป้องกันในเครื่อง', 'การซิงก์แบบเข้ารหัส', 'การจัดระเบียบที่ใช้ได้จริง', 'คำตอบสั้น'],
      paragraphs: [
        'ข้อมูลสำคัญควรถูกจัดการบนอุปกรณ์ก่อน เว็บไซต์ของผลิตภัณฑ์ไม่ควรเป็นที่อัปโหลดไฟล์ส่วนตัว',
        'ถ้ามีการซิงก์ ควรชัดเจนว่าใช้ข้อมูลที่เข้ารหัสเพื่อเปลี่ยนเครื่องและกู้คืน',
        'หมวดหมู่ รายการโปรด และการค้นหาทำให้ความเป็นส่วนตัวใช้งานได้จริง',
        'Mo Layer เหมาะกับการจัดรูป เอกสาร และภาพหน้าจอไว้ในพื้นที่ส่วนตัวบน iPhone'
      ],
      bullets: ['ตรวจสอบขอบเขตข้อมูล', 'เข้าใจการเข้ารหัส', 'วางแผนกู้คืน', 'ประเมิน Pro']
    }
  },
  id: {
    'hidden-album-vs-private-vault': {
      title: 'Album tersembunyi vs brankas pribadi: apa bedanya?',
      description: 'Perbandingan album tersembunyi dan brankas pribadi untuk foto, tangkapan layar, dokumen, dan file sensitif di iPhone.',
      keywords: ['album tersembunyi', 'brankas foto pribadi', 'privasi iPhone'],
      intro: 'Album tersembunyi mengurangi visibilitas. Brankas pribadi membuat ruang terpisah untuk melindungi, mengatur, dan memulihkan konten sensitif.',
      headings: ['Kapan album tersembunyi cukup', 'Kapan brankas pribadi lebih baik', 'Mengapa tampilan tenang penting', 'Jawaban singkat'],
      paragraphs: [
        'Album tersembunyi cocok untuk beberapa foto berisiko rendah. Ia tidak dirancang untuk mengatur dokumen sensitif jangka panjang.',
        'Brankas pribadi lebih cocok untuk foto, video, tangkapan layar, identitas, kontrak, tanda terima, dan file penting.',
        'Antarmuka yang tidak mencolok membantu alat privasi terasa alami dalam penggunaan sehari-hari.',
        'Gunakan album tersembunyi untuk kebutuhan ringan. Gunakan Mo Layer untuk arsip pribadi iPhone yang rapi dan tenang.'
      ],
      bullets: ['Foto dan video pribadi', 'Tangkapan layar sensitif', 'Identitas dan kontrak', 'Pemulihan terenkripsi']
    },
    'private-photo-vault-checklist': {
      title: 'Checklist sebelum memakai brankas foto pribadi',
      description: 'Hal yang perlu diperiksa sebelum menyimpan foto, dokumen, dan tangkapan layar sensitif di brankas pribadi iPhone.',
      keywords: ['brankas foto pribadi', 'foto pribadi iPhone', 'file aman'],
      intro: 'Brankas pribadi yang baik harus menjelaskan perlindungan lokal, sinkronisasi terenkripsi, pemulihan, dan batas akses layanan.',
      headings: ['Perlindungan lokal', 'Sinkronisasi terenkripsi', 'Organisasi praktis', 'Jawaban singkat'],
      paragraphs: [
        'Konten sensitif sebaiknya diproses di perangkat terlebih dahulu. Situs produk tidak boleh menjadi brankas web untuk file pribadi.',
        'Jika ada sinkronisasi, harus jelas bahwa data terenkripsi dipakai untuk pemulihan dan pergantian perangkat.',
        'Kategori, favorit, dan pencarian membuat konten pribadi tetap mudah digunakan.',
        'Mo Layer cocok untuk mengatur foto, dokumen, dan tangkapan layar dalam ruang pribadi iPhone.'
      ],
      bullets: ['Periksa batas data', 'Pahami enkripsi', 'Rencanakan pemulihan', 'Nilai Pro']
    }
  },
  hi: {
    'hidden-album-vs-private-vault': {
      title: 'हिडन एल्बम और प्राइवेट वॉल्ट में क्या अंतर है?',
      description: 'iPhone पर संवेदनशील फोटो, स्क्रीनशॉट, दस्तावेज़ और फाइलों के लिए हिडन एल्बम और प्राइवेट वॉल्ट की तुलना।',
      keywords: ['हिडन एल्बम', 'प्राइवेट फोटो वॉल्ट', 'iPhone गोपनीयता'],
      intro: 'हिडन एल्बम दृश्यता कम करता है। प्राइवेट वॉल्ट संवेदनशील सामग्री को अलग रखने, व्यवस्थित करने और रिकवरी के लिए बेहतर जगह देता है।',
      headings: ['हिडन एल्बम कब पर्याप्त है', 'प्राइवेट वॉल्ट कब बेहतर है', 'सादा अनुभव क्यों जरूरी है', 'छोटा उत्तर'],
      paragraphs: [
        'कुछ कम जोखिम वाली तस्वीरों के लिए हिडन एल्बम ठीक है। यह लंबे समय तक दस्तावेज़ और फाइलें व्यवस्थित करने के लिए नहीं बना है।',
        'प्राइवेट वॉल्ट फोटो, वीडियो, स्क्रीनशॉट, पहचान पत्र, अनुबंध, रसीद और महत्वपूर्ण फाइलों के लिए बेहतर है।',
        'गोपनीयता टूल का सामान्य दिखना रोजमर्रा के उपयोग में ध्यान कम करता है।',
        'हल्की जरूरतों के लिए हिडन एल्बम ठीक है। व्यवस्थित निजी iPhone आर्काइव के लिए Mo Layer बेहतर है।'
      ],
      bullets: ['निजी फोटो और वीडियो', 'संवेदनशील स्क्रीनशॉट', 'पहचान और अनुबंध', 'एन्क्रिप्टेड रिकवरी']
    },
    'private-photo-vault-checklist': {
      title: 'iPhone प्राइवेट फोटो वॉल्ट चेकलिस्ट',
      description: 'संवेदनशील फोटो, दस्तावेज़ और स्क्रीनशॉट को प्राइवेट iPhone वॉल्ट में रखने से पहले क्या जांचें।',
      keywords: ['प्राइवेट फोटो वॉल्ट', 'iPhone निजी फोटो', 'सुरक्षित फाइलें'],
      intro: 'अच्छा प्राइवेट वॉल्ट केवल लॉक नहीं देता; वह स्थानीय सुरक्षा, एन्क्रिप्टेड सिंक, रिकवरी और डेटा सीमा स्पष्ट करता है।',
      headings: ['स्थानीय सुरक्षा', 'एन्क्रिप्टेड सिंक', 'उपयोगी संगठन', 'छोटा उत्तर'],
      paragraphs: [
        'संवेदनशील सामग्री पहले डिवाइस पर संभाली जानी चाहिए। उत्पाद वेबसाइट निजी फाइल अपलोड करने की जगह नहीं होनी चाहिए।',
        'अगर सिंक है, तो यह साफ होना चाहिए कि डिवाइस बदलने और रिकवरी के लिए एन्क्रिप्टेड डेटा उपयोग होता है।',
        'श्रेणियां, पसंदीदा और खोज निजी सामग्री को उपयोगी बनाए रखते हैं।',
        'Mo Layer फोटो, दस्तावेज़ और स्क्रीनशॉट को iPhone के निजी स्थान में व्यवस्थित करने के लिए उपयुक्त है।'
      ],
      bullets: ['डेटा सीमा जांचें', 'एन्क्रिप्शन समझें', 'रिकवरी योजना बनाएं', 'Pro मूल्य देखें']
    }
  },
  ar: {
    'hidden-album-vs-private-vault': {
      title: 'ما الفرق بين الألبوم المخفي والخزنة الخاصة؟',
      description: 'مقارنة عملية بين الألبوم المخفي والخزنة الخاصة للصور ولقطات الشاشة والوثائق والملفات الحساسة على iPhone.',
      keywords: ['الألبوم المخفي', 'خزنة صور خاصة', 'خصوصية iPhone'],
      intro: 'الألبوم المخفي يقلل الظهور فقط. الخزنة الخاصة تنشئ مساحة منفصلة لحماية المحتوى الحساس وتنظيمه واستعادته.',
      headings: ['متى يكفي الألبوم المخفي؟', 'متى تكون الخزنة الخاصة أفضل؟', 'لماذا تهم البساطة؟', 'إجابة مختصرة'],
      paragraphs: [
        'الألبوم المخفي مناسب لعدد قليل من الصور قليلة الحساسية. لكنه ليس مساحة طويلة الأمد للوثائق والملفات الخاصة.',
        'الخزنة الخاصة أفضل للصور والفيديو ولقطات الشاشة والهويات والعقود والإيصالات والملفات المهمة.',
        'واجهة هادئة وغير ملفتة تساعد أداة الخصوصية على الاندماج في الاستخدام اليومي.',
        'استخدم الألبوم المخفي للحالات البسيطة. استخدم Mo Layer عندما تحتاج إلى أرشيف خاص ومنظم على iPhone.'
      ],
      bullets: ['صور وفيديو خاص', 'لقطات شاشة حساسة', 'هويات وعقود', 'استعادة مشفرة']
    },
    'private-photo-vault-checklist': {
      title: 'قائمة فحص قبل استخدام خزنة صور خاصة',
      description: 'ما الذي يجب التحقق منه قبل حفظ الصور والوثائق ولقطات الشاشة الحساسة في خزنة خاصة على iPhone.',
      keywords: ['خزنة صور خاصة', 'صور خاصة iPhone', 'ملفات آمنة'],
      intro: 'الخزنة الجيدة لا تكتفي بكلمة مرور؛ يجب أن توضح الحماية المحلية والمزامنة المشفرة والاستعادة وحدود الوصول.',
      headings: ['حماية محلية', 'مزامنة مشفرة', 'تنظيم عملي', 'إجابة مختصرة'],
      paragraphs: [
        'يجب أن تعالج المحتويات الحساسة أولاً على الجهاز. لا ينبغي أن يكون موقع المنتج خزنة ويب للملفات الخاصة.',
        'إذا وُجدت مزامنة، فيجب أن يكون واضحاً أنها تستخدم بيانات مشفرة لتغيير الجهاز والاستعادة.',
        'التصنيفات والمفضلة والبحث تجعل الخصوصية قابلة للاستخدام يومياً.',
        'Mo Layer مناسب لتنظيم الصور والوثائق ولقطات الشاشة في مساحة خاصة على iPhone.'
      ],
      bullets: ['تحقق من حدود البيانات', 'افهم التشفير', 'خطط للاستعادة', 'قيّم Pro']
    }
  },
  'zh-Hant': {
    'hidden-album-vs-private-vault': {
      title: '隱藏相簿和私密保險箱有什麼差別？',
      description: '比較 iPhone 隱藏相簿與專門私密保險箱，說明哪些情境需要更完整的保護。',
      keywords: ['隱藏相簿', '私密相簿', '私密保險箱'],
      intro: '隱藏相簿可以降低可見性。私密保險箱則提供專門空間，用來整理、保護和恢復敏感內容。',
      headings: ['什麼時候隱藏相簿就夠用？', '什麼時候需要私密保險箱？', '為什麼低調體驗重要？', '簡短結論'],
      paragraphs: [
        '如果只是把少量照片從主要相簿移開，隱藏相簿通常足夠。但它不適合長期整理證件、合約、截圖和文件。',
        '私密保險箱更適合照片、影片、截圖、證件、合約、票據和重要文件。',
        '隱私工具不只需要安全，也需要在日常使用中自然低調。',
        '輕量需求可以使用隱藏相簿；需要完整私人檔案空間時，墨層更合適。'
      ],
      bullets: ['私密照片與影片', '敏感截圖', '證件與合約', '密文恢復']
    },
    'private-photo-vault-checklist': {
      title: '選擇 iPhone 私密相簿前應該檢查什麼？',
      description: '從本機保護、加密同步、恢復能力和隱私邊界檢查一款私密相簿是否值得信任。',
      keywords: ['iPhone 私密相簿', '私密保險箱', '加密相簿'],
      intro: '私密相簿不應只是一個密碼入口。它需要說清楚資料在哪裡、如何恢復，以及開發者是否能讀取。',
      headings: ['本機優先', '密文同步', '實用整理', '簡短結論'],
      paragraphs: [
        '敏感內容應優先在裝置上處理。產品官網不應成為上傳私人文件的網頁保險箱。',
        '如果提供同步，應清楚說明是為換機和恢復而同步密文。',
        '分類、收藏與搜尋能讓私密內容長期保持有序。',
        '墨層適合把照片、文件、截圖和合約放進低調的 iPhone 私人空間。'
      ],
      bullets: ['檢查資料邊界', '理解加密', '規劃恢復', '評估 Pro 價值']
    }
  }
};

const generatedLocales = Object.keys(localizedTopicCopy) as LocaleCode[];

const existingGeneratedArticles: GeneratedArticle[] = generatedLocales.flatMap((locale) =>
  (Object.keys(localizedTopicCopy[locale]) as Array<keyof (typeof localizedTopicCopy)[typeof locale]>).map((translationKey) => {
    const copy = localizedTopicCopy[locale][translationKey];
    return {
      locale,
      slug: translationKey,
      translationKey,
      title: copy.title,
      description: copy.description,
      category: 'privacy',
      keywords: copy.keywords,
      updatedAt: '2026-06-05',
      blocks: [
        { heading: copy.title, paragraphs: [copy.intro] },
        { heading: copy.headings[0], paragraphs: [copy.paragraphs[0]] },
        { heading: copy.headings[1], paragraphs: [copy.paragraphs[1]], bullets: copy.bullets },
        { heading: copy.headings[2], paragraphs: [copy.paragraphs[2]] },
        { heading: copy.headings[3], paragraphs: [copy.paragraphs[3]] }
      ]
    };
  })
);

export const generatedArticles: GeneratedArticle[] = [
  ...existingGeneratedArticles.map((article) => {
    if (article.translationKey !== 'hidden-album-vs-private-vault') return article;
    const copy = getAeoCopy(article.locale);
    return {
      ...article,
      updatedAt: aeoContentUpdatedAt,
      blocks: [
        { heading: article.title, paragraphs: [copy.comparison.answer] },
        { heading: copy.recovery.question, paragraphs: [copy.recovery.answer], steps: copy.steps },
        { heading: copy.plan.question, paragraphs: [copy.plan.answer] }
      ]
    };
  }),
  ...generatedLocales.map((locale) => {
    const copy = getAeoCopy(locale);
    return {
      locale,
      slug: 'recover-private-vault-new-iphone',
      translationKey: 'recover-private-vault-new-iphone',
      title: copy.recovery.question,
      description: copy.recovery.answer,
      category: 'privacy',
      keywords: ['Mo Layer', 'iPhone', 'iCloud'],
      updatedAt: aeoContentUpdatedAt,
      blocks: [
        { heading: copy.recovery.question, paragraphs: [copy.recovery.answer], steps: copy.steps },
        { heading: copy.plan.question, paragraphs: [copy.plan.answer] }
      ]
    };
  })
];

export const generatedContentIndex: ContentIndexEntry[] = generatedArticles.map(({ blocks, category, keywords, ...entry }) => entry);

export function generatedArticleFor(locale: LocaleCode, slug: string) {
  return generatedArticles.find((article) => article.locale === locale && article.slug === slug);
}
