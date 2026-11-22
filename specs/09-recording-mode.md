# 09 — Kayıt Modu (Geliştirici Aracı)

Prototipi salonda hoca ve arkadaşlarla denemek, hocanın yorumlarını hareketin tam anına bağlamak, eşikleri Vision verisiyle kalibre etmek ve motor için gerçek test verisi üretmek için. 00 değişmez kural 1'in **tek ve dar istisnası**dır.

## Erişim
- Yalnız **Beta** yapılandırmasında derlenir (`RECORDING_MODE`, 02). App Store derlemesinde kod yoktur (AC-2.3).
- Beta'da bile öntanımlı kapalıdır: Ayarlar → Geliştirici → "Kayıt modu"nu açmak bir onay ekranı gerektirir ("Bu mod video kaydeder. Yalnız açık rıza veren kişileri kaydet.").
- Kayıt sürerken ekranın üstünde sürekli kırmızı "● KAYIT" bandı ve geçen süre görünür; kamera önizlemesinin çevresi kırmızıdır.
- Kayıt modu, normal kullanıcı antrenmanlarında **asla** kendiliğinden açılmaz; her kayıt elle başlatılır.

## Rıza (KVKK)
Kaydedilecek her kişi için, **o kişiden**, kayıttan önce:
1. **Aydınlatma ve açık rıza ekranı** (TR/EN, sürümlü `recordingConsentVersion`): ne kaydedilir (video, eklem koordinatları, motor çıktısı, notlar), amaç (uygulama geliştirme ve kalibrasyon), nerede saklanır (yalnız bu telefonda), ne paylaşılır (yalnız takma adlı eklem verisi, video asla), ne kadar süre (en çok 12 ay), nasıl geri çekilir (operatöre söyleyerek; tüm kayıtları silinir), veri sorumlusu ve iletişim.
2. Kişi "18 yaşından büyüğüm" kutusunu ve "Okudum, kabul ediyorum" düğmesini **kendisi** işaretler. 18 yaş altı kayıt yapılamaz.
3. **Takma ad:** operatör bir katılımcı kodu verir (ör. `P07`); gerçek isim uygulamaya girilmez. Kod ile kişi arasındaki eşleme uygulama dışında (operatörün kendi notunda) tutulur.
4. Rıza kaydı: `RecordingConsent { id, participantRef, consentVersion, consentedAt, withdrawnAt? }`. Rıza sürümü değişince aynı katılımcıdan yeniden rıza istenir.
5. **Geri çekme:** Kayıt modu → Katılımcılar → `P07` → "Rızayı geri çek": bu katılımcının tüm kayıtları (video, poz, notlar, dışa aktarım geçmişi) cihazdan silinir. Daha önce dışa aktarılmış landmark dosyalarının da silinmesi gerektiği operatöre hatırlatılır (repoya girmişse kaldırılır, 10).

## Ne kaydedilir
Bir kayıt, kamera akışının tek bir kesintisiz parçasıdır (bir set, bir refleks seti ya da serbest kayıt).

| Akış | İçerik | Biçim |
|---|---|---|
| Video | Kamera kareleri, **sessiz** (mikrofon yok), 1280×720, 30 FPS, HEVC | `video.mov` (`AVAssetWriter`) |
| Poz | Her kare: PTS, Vision 2B 19 eklem (x, y, güven), Vision 3B 17 eklem (varsa), seçilen kişi kimliği, aday kişi sayısı | `poses.jsonl` |
| Motor | Her kare: aktif şablonların ham ve yumuşatılmış metrikleri, rep sayıcı durumu, görünüm, yakın taraf; olaylar (`REP_STARTED`, `REP_COMPLETED`, `FAULT_DETECTED`, `SAFETY_PAUSE`, `TRACKING_*`, `READY_POSE_HELD`) | `engine.jsonl` |
| Uygulama | Seans/refleks olayları: işaret planlama ve çıkış zamanları (`t_cue`), deneme sonuçları, kullanıcı eylemleri, kademeli çalışma değişiklikleri | `app.jsonl` |
| Meta | Kayıt kimliği, katılımcı kodu, rıza kimliği, cihaz modeli, iOS sürümü, uygulama sürümü, şablonlar ve sürümleri (tam JSON kopyaları), gard yönü, kamera (ön/arka), mod, 03 H1/H2 durumu | `meta.json` |
| Notlar | Oynatma ekranında eklenen notlar (aşağıda) | `notes.json` |

- **Eş zaman:** video yazıcısı ve poz akışı **aynı `CMSampleBuffer`'ları** kullanır; her kayıt satırı karenin PTS'sini taşır. Videodaki kare ile poz satırı PTS ile birebir eşlenir. Vision'ın atladığı kare (kuyrukta atılan) videoda vardır, pozda `"skipped": true` satırı olarak yer alır.
- Kayıt paketi: `Recordings/<recordingId>.gsrec/` (yukarıdaki dosyalar). `recordingId` UUID.
- Boyut: dakikada yaklaşık 4–6 MB video + 1 MB poz/motor. Boş alan < 2 GB ise kayıt başlamadan uyarı; < 500 MB ise kayıt başlatılmaz.

## Depolama ve güvenlik
- Uygulama kapsayıcısında, `NSFileProtectionComplete` (cihaz kilitliyken okunamaz).
- iCloud/iTunes yedeğinden hariç (`isExcludedFromBackup`). Fotoğraflar'a yazılmaz. `UIFileSharingEnabled` ve "Dosyalar'da göster" kapalı: video Dosyalar uygulamasından görünmez.
- 11 aydan eski kayıtlar uygulama açılışında listelenir ve silinmesi önerilir. 12 ayı dolduran kayıt (rıza metnindeki en uzun süre) uygulama açılışında ya da arka plan görevinde (`BGAppRefreshTask`) otomatik silinir; süre hiçbir durumda bilerek aşılmaz.

## Oynatma ekranı
- Video (`AVPlayer`) ve üstünde PTS'ye göre eşlenmiş çizim katmanı: iskelet (2B), seçilen şablonun hedef dairesi/çizgileri, metrik paneli (seçilen metriklerin anlık değeri ve start/target bölgeleri), rep sayıcı durumu.
- **Zaman çizelgesi:** altta olay işaretleri: işaret (`t_cue`), `REP_STARTED`, `REP_COMPLETED` (sonuç rengiyle), form uyarısı, güvenlik duraklatması, takip kaybı, not.
- Kontroller: oynat/durdur, kare kare ileri–geri, 0,25×/0,5×/1× hız, işaretten işarete atlama, sürükleyerek sarma.
- **Not ekleme:** o anki zamana not. Alanlar: metin (TR/EN serbest), isteğe bağlı **etiket**: deneme sonucu (`valid`/`faulty`/`incomplete`; refleks denemesinde doğru tepki şablonu) ve hata kimlikleri (o kaydın şablonlarındaki hatalardan seçilir). Not, zamanına en yakın denemeye bağlanır (deneme aralığındaysa). Notlar düzenlenip silinebilir.
- Hoca telefonu eline alıp not ekleyebilir; notun yazarı için "hoca / geliştirici" seçimi tutulur (isim değil).

## Yeniden oynatma (yeni eşiklerle)
- Bir kayıt ya da kayıt grubu seçilir, bir şablon parametresi değiştirilir (ref 09'daki `--sweep` yol sözdizimi: `rep.target.enter`, `faults.<id>.threshold`) ya da şablonun başka bir sürümü seçilir.
- Swift motoru `poses.jsonl` üzerinden yeniden koşar (03 kalibrasyon katmanının Swift karşılığı). Çıktı:
  - Olay farkı: eklenen/kaybolan tekrarlar ve uyarılar, zaman çizelgesinde iki şerit (eski/yeni).
  - Etiketli kayıtlarda: ref 09 tanımlarıyla sayım doğruluğu, yanlış alarm oranı, hata bazında isabet/kaçırma; refleks kayıtlarında tepki sınıflandırma doğruluğu.
  - Değer taraması: aynı parametre için 3–7 aday değer, sonuç tablosu.
- Sonuçlar kayda ek dosya olarak saklanmaz (her seferinde yeniden hesaplanır); "Kopyala (JSON)" ile alınabilir.

## Dışa aktarma
- **Yalnız landmark verisi** dışa aktarılır: `LandmarkSequence` `formatVersion: 2`, `skeleton: "vision19"`, `source: "team"` (03), notlardaki etiketler `labels.reps` olarak, `meta` (şablon kimlikleri/sürümleri, cihaz, katılımcı kodu, rıza sürümü). Ek olarak refleks kayıtlarında `app.jsonl`'ın işaret ve deneme satırları.
- Paylaşım sayfası (Dosyalar, AirDrop) ile tek `.json` dosyası (gzip'li). **Video ve kare görüntüsü dışa aktarılamaz** (paylaşım sayfasına hiç verilmez).
- Her dışa aktarım meta veriye yazılır (ne zaman, hangi dosya adı); rıza geri çekilince operatöre bu liste gösterilir.
- `meta` alanının katı şeması (yalnız yukarıdaki alanlar; isim ya da serbest metin yok) T5.4'te 03'teki dizi şemasına eklenir; o zamana kadar `solo-calibrate` `meta`sız v2 dizilerini okur.
- Repo kullanımı: dışa aktarılan diziler `fixtures/recordings/<şablon>/` altına **açılmış** (gzip'siz) `.json` olarak girer; anlık görüntülere (03) ve kalibrasyon raporuna (`solo-calibrate report --files`) kaynak olur. Repoya girmeden önce dosyada isim, yüz ya da görüntü olmadığı şema ile doğrulanır (katı şema, ref 07 ilkesi).

## Salon pilotu akışı
1. Operatör (geliştirici) katılımcı kodu oluşturur, katılımcı rızayı verir.
2. Her eskiv için: teknik modunda 2 set (biri bilinçli hatalı: gard düşük, boyunla kaçma), refleks modunda seviye 1–3 birer set.
3. Hoca oynatmada denemeleri etiketler ve yorum ekler.
4. Kayıtlar dışa aktarılır, kalibrasyon raporu çalıştırılır, eşikler ve spec (04, 05) güncellenir.
5. Notlardaki ürün geri bildirimleri (ekran, ses, akış) 13'teki pilot geri bildirim listesine aktarılır.

## Kabul kriterleri
- AC-9.1: Release derlemesinde kayıt modu yoktur (AC-2.3); Beta'da ayardan açılmadan kayıt başlatılamaz.
- AC-9.2: Rıza kaydı olmayan ya da rızası geri çekilmiş katılımcıyla kayıt başlatılamaz; 18 yaş kutusu işaretlenmeden rıza tamamlanamaz (UI testi).
- AC-9.3: Videonun her karesi için `poses.jsonl`'da aynı PTS'li bir satır vardır (atlanmış kare satırları dahil); 10 dk kayıtta eşleşme %100 (cihaz testi + birim testi sahte kamerayla).
- AC-9.4: Oynatmada iskelet katmanı ile video arasındaki kayma 0 karedir (kare kare ilerletmede doğrulanır).
- AC-9.5: Yeniden oynatma, değiştirilmemiş eşiklerle kayıttaki olayların aynısını üretir (deterministiklik).
- AC-9.6: Dışa aktarılan dosya `LandmarkSequenceSchema` v2'ye uyar; görüntü/video alanı içeremez; `solo-calibrate` tarafından okunur (CI'da örnek dosyayla).
- AC-9.7: Rıza geri çekilince o katılımcının tüm kayıt paketleri silinir; dosya sisteminde kalıntı yoktur (test).
- AC-9.8: Kayıt dosyaları yedekten hariçtir ve `NSFileProtectionComplete` sınıfındadır (test).
- AC-9.9: Mikrofon izni istenmez; video dosyasında ses izi yoktur.

## Açık sorular
1. **Hukuki metin:** KVKK aydınlatma ve açık rıza metni bir hukukçuya okutulmalı. Bireysel geliştirici olarak veri sorumlusu kimdir, VERBİS kaydı gerekir mi?
2. Hoca videoyu kendi telefonunda/bilgisayarında izlemek isterse? Şu anki karar: video telefondan çıkmaz; hoca oynatmayı aynı telefonda yapar. Gerekirse ikinci bir rıza maddesiyle "videoyu hocayla AirDrop ile paylaşma" eklenebilir.
3. Notları sesle eklemek (dikte) için klavyenin sistem diktesi yeterli mi? Uygulama mikrofonu kendisi kullanmaz.
4. 12 aylık saklama süresi uygun mu, yoksa pilot bitince (3 ay) tüm videolar silinmeli mi?
