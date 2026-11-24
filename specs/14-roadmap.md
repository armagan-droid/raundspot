# 14 — Uygulama Sırası (Claude Code görev listesi)

Her görev bir **ana spec**'e dayanır (görev satırında ilk yazılan) ve satırda listelenen kabul kriterleriyle (testlerle) biter; diğer spec'ler bağlam ve atıf içindir. Sıra bağımlılığa göredir. **Faz 0'daki spike (T0.2) Faz 1 ile paralel yürür** ve sonucu 03 (H1/H2) ile 04'ü (lean back) etkiler.

Bu proje salon reposundan bağımsızdır; salon reposuna hiçbir görevde yazılmaz. Tek temas T1.2'deki bir kerelik golden üretimidir.

## Faz 0 — Hazırlık ve spike
- [x] T0.1 Repo iskeleti: Xcode projesi (Debug/Beta/Release), `Packages/` altında `SoloEngine` (Linux'ta `swift test`), `SoloCalibrate`, `SoloPose`, `SoloCapture`, `SoloHealth`, `SoloRecording` boş paketleri; String Catalog TR/EN; CI (Linux `swift test` + `solo-calibrate validate`, macOS `xcodebuild test`) — 02 (AC-2.1, AC-2.3, AC-2.5)
- [ ] T0.2 **Spike:** Vision 2B/3B FPS ve gecikme, 3B eksenleri, `centerHead`↔`nose`, güven dağılımı, önden lean back derinliği, ses çıkış gecikmesi (hoparlör/Bluetooth), termal ve pil. Ölçüm uygulaması `Spike/` (Debug hedefi, üretime girmez). Sonuçları 02 tablosuna yaz; H1/H2 kararını 03'e, `lean_back_front`/`high_kick` kararını 04 ve 05'e işle — 02 (AC-2.4), 03

## Faz 1 — Kaynaktan devralma (bir kerelik)
- [x] T1.1 Kaynak kopyaları: salon reposunun `c2fe3fd` commit'inden şablonları `exercises/source/` altına aynen kopyala, sağlama toplamı listesini yaz; `docs/reference/b2b/` içeriğinin aynı commit'ten olduğunu doğrula — 04 (AC-4.2)
- [x] T1.2 `tools/golden-export`: geçici dizinde `c2fe3fd` kopyası üzerinde çalışan TS betiği; kaynak golden ve ifade golden'ını `fixtures/source-golden/` altına üret, iki kez çalıştırıp aynı çıktıyı doğrula — 03 (AC-3.1) *Durum (2026-11-24): 133 motor durumu (11 şablon) ve 180 ifade girdisi `fixtures/source-golden/` altında; iki çalıştırma bayt bayt aynı, `run.sh --check` taze dışa aktarmayla eşitliği doğrular. Biçim 03 "Üretilen golden".*

## Faz 2 — Swift motoru
- [x] T2.1 Şema ve yükleyici: rule pack (Codable, katı), ref 04 doğrulama kuralları, `LandmarkSequence` v1/v2 (`skeleton`, `null` noktalar), iskelet yetenek kontrolü `unsupported_landmark`; `solo-calibrate validate` — 03 (AC-3.4, AC-3.5), 04 (AC-4.1)
- [x] T2.2 İfade dili: tokenize, parse, üç değerli değerlendirme; ifade golden'ı — 03 (AC-3.3). *Durum (2026-11-24): ifade golden'ının 180 girdisi Swift'te aynı (`ExpressionGoldenTests`).*
- [x] T2.3 Metrikler (kaynak kapalı liste), One Euro, görünüm tespiti, yakın taraf — 03
- [x] T2.4 Tekrar sayıcı, hata değerlendirici, uyarı kuralları, güvenlik duraklatması, takip kaybı; zaman damgalı olaylar; ham metrik geçmişi — 03
- [x] T2.5 Kaynak uyumluluğu tüm kaynak golden'larda yeşil (Linux CI); anlık görüntü altyapısı (`UPDATE_SNAPSHOTS`) — 03 (AC-3.2, AC-3.7) *Durum (2026-11-24): Swift motoru 133 durumun tümünde olay, rep durumu ve metriklerde (≤ 1e-9) kaynakla aynı; gevşetme ya da `superseded` gerekmedi (`SoloEngineSourceConformanceTests`). Değişmezlik CI'da `scripts/ci/check-source-golden.sh` ile denetlenir.*
- [x] T2.6 Kurulum değerlendirmesi ve kişi seçimi (ref 08 A3, ref 07) — 03, 12
- [ ] T2.7 Yeni metrik fonksiyonları: `min`, `angle2d`, `lateralLean2d`, `chainHeight2d`, `sagittalLean`, `sagittalLean2d`; sentetik vücut aracı ve `toVision19` — 04 (AC-4.3) *Durum: fonksiyonlar, birim testleri, sentetik vücut (eskiv, dövüş duruşu) ve `toVision19` tamam; AC-4.3 anlık görüntüleri `fixtures/snapshots/snap_*` (test şablonları `fixtures/snapshots/packs/`). Önden duck için 04 açık soru 6 kararıyla `heightOverShoulders2d` eklendi (T2.8 ile).*
- [ ] T2.8 Bu projenin şablonları (draft): `exercises/` altında 2B eskivler, `bob_weave_left/right`, `lean_back` (yandan; `lean_back_front` yalnız H1 doğrulanırsa), `squat`/`pushup` (2B), `reverse_lunge`, `jumping_jack`; `fixtures/equivalence/` kopyaları, testleri ve anlık görüntüleri — 04 (AC-4.4, AC-4.5, AC-4.8) *Durum: 11 şablon `exercises/` altında (`draft`, metinler hoca onayı bekler), `fixtures/equivalence/` (`slip_left`, `duck`), şablon testleri ve `fixtures/snapshots/project_*` tamam. AC-4.4 sentetik `vision19` dizileriyle sağlanıyor. Golden kısmı (2026-11-24): 04 açık soru 7 kararıyla (kapsam: eşik sınırı ve duck'ta 0,003 üstü gürültü dışında) 17 golden durumunun hepsi aynı sonucu verir. `lean_back_front` H1 kararını bekler (oluşturulmadı). Bulgular 04'te: duck'ın gürültü riski, `forward_lean_start` çıkarıldı, lunge `knee_near`.*
- [x] T2.9 `solo-calibrate report` ve `--sweep` (ref 09 ölçüt tanımları) — 03, 09

## Faz 3 — Kamera, poz, teknik modu
- [x] T3.1 `SoloCapture`: kamera oturumu, kare kuyruğu, host saati; sahte kamera (dosyadan kare akışı) — 02 (AC-2.2) *Durum (2026-11-24):*
  - *Saat: `SoloClock` (`LiveClock`, `ManualClock`).*
  - *Kare kaynağı: uygulamada `FrameSource` (`CameraFrameSource`, `SequenceFrameSource`). Debug derlemesinde ana listeden bir landmark dizisi dosyası seçilir; antrenmanlar kamera yerine o diziyle, döngüde çalışır.*
  - *Test: `FakeCameraTests`, sahte saatle uçtan uca. Kareler, seans makinesi ve kayıtlar aynı saatte.*
  - *Açık kalanlar: AC-2.2'nin ses kısmı T3.3'teki planlı sesle; gerçek kamerada `synchronizationClock` eşlemesinin doğrulanması T0.2 cihaz ölçümüyle.*
- [ ] T3.2 `SoloPose`: Vision 2B (+3B, karara göre) → `Frame` dönüşümü, ön kamera aynalama kuralı — 03 (AC-3.6) *Durum (2026-11-25): Vision 2B → `Frame` dönüşümü, aday seçimi ve döndürme kodda; AC-3.6'nın sentetik birim testi `SoloPoseTests`'te (y ekseni, sol/sağ, ön kamerada sola kaçışta `lateralLean2d` > 0). Kalan: cihazda sabit pozlu görüntü testi ve 3B (H1/H2), ikisi de T0.2 spike'ına bağlı.*
- [ ] T3.3 Ses çıkışı: `AVAudioEngine` planlı çalma, çıkış gecikmesi, TTS yedeği, ses oturumu kuralları; ses dosyaları ve `cueOnsetMs` meta verisi — 02, 05
- Durum (2026-11-24, T3.3 kısmı):
  - *Yapıldı: `SoloCapture/CueOut`. İşaret sesi `AVAudioPlayerNode` ile host saatinde ileri bir zamana planlanır (`HostClock.hostTicks`). `t_cue` = çıkış gecikmesi + I/O tamponu + `cueOnsetMs` (`CueTiming`). Meta veri `cues.json` (05). Dosyası olmayan işaret TTS ile söylenir ve `rtApproximate` işaretlenir; Bluetooth'ta da öyle. Sonuç tonları `ToneOut`. Ses oturumu 02'ye uygun (`SpeechOut`).*
  - *Henüz yok: ses dosyalarının kendisi (05 açık soru 4: hocanın sesi) ve `cueOnsetMs` ölçümü. Bu yüzden şimdilik tüm işaretler TTS'tir. Dosyalar eklenince paket içindeki yolu (`audio/<dil>/`) bir testle doğrulanmalı.*
- [x] T3.4 Seans motoru (06 Bölüm 1) + hazır antrenman JSON'ları + SwiftData modeli ve göç altyapısı (11 Bölüm 1; seans kayıtları buradan itibaren yazılır) — 06 (AC-6.1–AC-6.5), 11 (AC-11.1, AC-11.2)
- Durum (2026-11-24, T3.4): seans motoru (`SoloEngine/Session`: `SessionMachine`, `Workout`), girdiler, komutlar ve kayıtlar (06 "Girdiler ve komutlar"), `serialize`/`restore`; hazır antrenmanlar `eskiv_temeli`, `refleks`, `kondisyon` (`exercises/workouts/`, `solo-calibrate validate` denetler). Kondisyon devresi formatı (06 "Devre") eklendi; `kondisyon` 3 turlu devredir. SwiftData modeli (`App/Data/SoloSchema.swift`: `SoloSchemaV1`, `SoloMigrationPlan`, `SessionRecorder`) uygulamada kayıtları yazar. Testler AC-6.1–AC-6.5, AC-11.1 ve AC-11.2'yi kapsar. "Hızlı karma" refleks moduna bağlıdır ve T4.4 ile gelir (06). Görev o dosya dışında tamamdır.
- [ ] T3.5 Ekranlar: S1–S3, T1–T3, Y1; eskiv çizimleri — 12 (AC-12.1, AC-12.2 T2 kısmı; AC-12.3, AC-12.4; AC-12.7 T2 kısmı)
- Durum (2026-11-24, T3.5 kısmı): uygulama seans motoruyla çalışır. Ana listede hazır antrenmanlar ve tek hareket var; tek hareket 1×10'luk tek bloklu antrenmandır. Akış: S2 → S1 (ilk kameralı bloğun şablonuyla `assessSetup`; refleks bloğunda eskiv şablonlarıyla, 06) → ısınma adımları (adım gösterimiyle, 04 "Adım gösterimleri") → T1 (set x/y, gösterim) → sesli 3-2-1 → T2 (x / hedef) → "Set bitti mi?" → T3 dinlenme → soğuma → Y1. Duraklatma, atla/geri al, arka plan, kamera ve ses kesintisi bağlı. Kayıtlar SwiftData deposuna yazılır (T3.4). **Geçici:** refleks blokları, deneme döngüsü (Faz 4) gelene kadar uygulamada kendiliğinden atlanır ve bu kullanıcıya söylenir. Görünümü farklı sonraki bloklarda görünüm ipucu `READY`'de verilir; motor her yeni sette o şablonun görünümüyle yeniden kurulur. Cihaz denemesinde bulunan iki hata (2026-11-22) bu kuralla giderildi: "Refleks" S1'de kalıyordu, "Kondisyon"da önden ve yandan şablonların görünüm kesişimi boş olduğu için kurulum bitmiyordu. Alt sekme çubuğu, O ekranları, H3 ve R ekranları sonradan geldi (T4.4, T7.1). Henüz yok: H1 kartları, S3 içeriğinin hoca onayı.
- [x] T3.6 Kademeli çalışma ve tanı paneli — 02 (AC-2.6) *Durum (2026-11-24): termal `serious` → 24 fps (kamera ve sahte kamera), seans kaydına `fps24`, kullanıcıya gösterilmez, antrenman sürer; `critical` → E4 "kısa bir mola" ve duraklatma. Tanı panelinde termal durum ve düşüşler. 3B adımı H2'de yoktur (2B çalışılıyor). `DegradationTests` sahte termal durumla.*
- Durum (2026-11-22, cihaz deneme dilimi): T3.1 ve T3.2'nin çekirdeği ile T3.3 (yalnız TTS yedeği), T3.5 (S2, S1, T1, T2 ve Y1 sade hâli; eskiv hedef dairesi, balonlar, kesikli çizgiler ve ok, geometrisi `SoloEngine` `HeadGuideTracker`; eğilme çizgisi o anki omuz genişliğiyle çizilir, böylece baş çizgiyi metrik eşiği geçtiğinde geçer; kondisyon şablonlarında hedef çizgisi `TargetLineTracker`; S1 ve T1'de gösterim animasyonu, `exercises/demos/`) ve T3.6 (yalnız tanı paneli) kısımları, telefonda bir şablonu baştan sona denemek için kuruldu. Ön kamera; H2, yani yalnız 2B; kişi seçimi ve `assessSetup` motordan. Henüz yok: sahte kamera, saat eşlemesinin testi, planlı ses ve ses dosyaları, seans motoru (T3.4), telefon eğimi (CoreMotion), arka kamera, kademeli çalışma. Görevler bu kısımlar bitene kadar `[ ]` kalır. Şablonlar uygulamaya `scripts/xcode/copy-exercises.sh` ile kopyalanır; derleme kum havuzu yalnız bildirilen girdileri okuttuğu için dosyalar `scripts/xcode/exercises.xcfilelist`'te sayılır ve bir test listeyi `exercises/*.json` ile eşit tutar.

## Faz 4 — Refleks modu
- [x] T4.1 Katalog şeması ve `muay_thai.json` taslağı; southpaw aynalaması — 05 (AC-5.3, AC-5.6, AC-5.8) *Durum (2026-11-24):*
  - *Katalog: `SoloEngine/Reflex/ReflexCatalog` (katı yükleyici, `resolved(for:)`, `templateIssues`, `isUsable(release:)`); biçimi 05 "Seviye kaydı ve doğrulama"da.*
  - *Veri: `exercises/reflex/muay_thai.json` (`draft`, 6 seviye, H1 doğrulanmadığı için `high_kick` yok). Uygulama paketine kopyalanır. Saldırı anahtarları TR/EN String Catalog'da.*
  - *Doğrulama: `solo-calibrate validate` katalogları, `comboGapMs` kuralını ve antrenmanlardaki `catalogId`'yi denetler.*
  - *AC-5.8'in ekran kısmı (TestFlight'ta "taslak eşleme" ibaresi) T4.4'te gelir.*
- [x] T4.2 Deneme döngüsü, sınıflandırma, tepki süresi (ham metrik interpolasyonu), kombinasyon, aldatma, seviye önerisi — 05 (AC-5.1, AC-5.2, AC-5.4, AC-5.5) *Durum (2026-11-24): `SoloEngine/Reflex/ReflexSet` (deneme döngüsü, `classifyReflexTrial`, `ReflexSetSummary`, `ReflexLevelAdvice`, tohumlu `ReflexRandom`); motora ham eşik geçişi (`rawConfirmCrossing`), dönüş ilerlemesi ve hazır duruş süresi eklendi. Uygulama ayrıntıları 05'te. Sentetik boksörle testler: RT bir kare içinde, aynı tohum aynı set. Ses önceliği ve sonuç tonları T4.3'te.*
- [x] T4.3 Refleks geri bildirimi ve ses önceliği (konuşma–işaret çakışmaması) — 05 (AC-5.7) *Durum (2026-11-24): `ReflexSet` sonuç tonları, form uyarısı, yön ipucu, set özeti ve konuşma–işaret arbitrajı; güvenlik duraklatması `cancelCues` ile planlı işareti iptal eder. Sahte ses çıkışıyla zaman çizelgesi testi (`ReflexFeedbackTests`). Metinler TR/EN String Catalog'da; `DataKeysTests` motorun söyleyebildiği anahtarları denetler.*
- [ ] T4.4 Ekranlar R1–R3, H3; "Hızlı karma" antrenmanı ve seçim gösterimi (06) — 12 (AC-12.1, AC-12.2 R2 kısmı; AC-12.7 R2 kısmı), 06
- Durum (2026-11-24, T4.4):
  - *Refleks blokları uygulamada çalışır. Seviye ve işaret sayısı antrenman başında sabitlenir. Kayıtlar `ReflexTrial`'a setiyle yazılır.*
  - *Ekranlar: R1 (gard al, seviye, işaret sayısı, "yaklaşık" notu, taslak ibaresi), R2 (saldırı adı ekran yüksekliğinin %22'si, sonuç ikonu ve tepki süresi, sayaç, hedef balonu yok), R3 (dinlenmede set özeti ve seviye önerisi), H3 (eskiv seçimi, sonra seviye kartları).*
  - *İşaret sesi şimdilik TTS ile planlanır, bu yüzden tepki süresi "yaklaşık" işaretlenir. Planlı ses dosyaları T3.3'te gelir.*
  - *AC-5.8: Release derlemesi taslak katalogla refleks bloğunu atlar.*
  - *"Hızlı karma" (06 \"Seçim\") eklendi.*
  - *Test: `ReflexFlowTests` (sahte kamerayla uçtan uca).*
  - *Henüz yok: AC-12.1/AC-12.2 ekran anlık görüntü testleri (anlık görüntü altyapısı uygulamada yok, T3.5'in T2 kısmıyla birlikte gelecek), R1'de başın etrafındaki nötr daire.*
- [ ] T4.5 Cihazda RT doğrulaması (ağır çekim yöntemi) — 05 (AC-5.9)

## Faz 5 — Kayıt modu (Beta)
- [ ] T5.1 Rıza, katılımcılar, kayıt paketi yazımı (video + poz + motor + uygulama akışları, PTS eşleme), depolama güvenliği — 09 (AC-9.1–AC-9.3, AC-9.7–AC-9.9)
- [ ] T5.2 Oynatma ekranı ve notlar — 09 (AC-9.4)
- [ ] T5.3 Yeniden oynatma ve değer taraması — 09 (AC-9.5)
- [ ] T5.4 Landmark dışa aktarma; örnek dosyanın `solo-calibrate` ile okunması (CI) — 09 (AC-9.6)

## Faz 6 — HealthKit ve kalori
- [ ] T6.1 MET tablosunu Compendium 2024'ten doğrula (kodlarıyla), Keytel denklemlerini kaynağından doğrula; enerji hesabı — 08 (AC-8.1, AC-8.3, AC-8.7)
- Durum (2026-11-25, T6.1 kısmı):
  - *Yapıldı: enerji hesabı `SoloEngine/Energy` (segment zaman çizelgesi, duraklatma sayılmaz, net kcal, nabız kapsamı ve yöntem seçimi, kilo önceliği, 5'e yuvarlama); AC-8.1 ve AC-8.3 testli. `exercises/energy/met.json` Compendium 2024 kodlarıyla: kalistenik 02020 7,5 (spec'teki 8,0 2011 değeriydi), ısınma 02024 2,8, soğuma 02101 2,3. `solo-calibrate validate` enerji dosyalarını denetler.*
  - *Kalan:*
    - *dinlenme MET'i (1,5) için 2024 karşılığı bulunamadı;*
    - *Keytel katsayıları makalenin tam metniyle doğrulanmalı. `keytel.json` `verified: false` olduğu sürece nabız yöntemi kapalı, MET kullanılır;*
    - *AC-8.7 "tahmin" ibaresi Y1 ve T6.2 ile gelir.*
- [ ] T6.2 `SoloHealth`: izinler, `HKWorkoutSession`/`HKLiveWorkoutBuilder`, blok etkinlikleri, enerji örnekleri, iptal/silme — 08 (AC-8.2, AC-8.4–AC-8.6)
- Durum (2026-11-25, T6.2 kısmı):
  - *Yapıldı: `SoloHealth` `HealthWorkout` (blok başına etkinlik ve net enerji örneği, ana tür en uzun blok, 3 dk'dan kısa iptal atılır, kilo yoksa enerji örneği yok; AC-8.2 ve AC-8.5 sahte depoyla testli). `LiveHealthStore` (`HKWorkoutSession` ve canlı builder, builder'ın enerji toplaması kapalı, kapalı alan) derleniyor.*
  - *Kalan:*
    - *uygulamaya bağlama: HealthKit yetkisi (entitlement), `NSHealthShareUsageDescription` ve `NSHealthUpdateUsageDescription` TR/EN, O6 ve Ayarlar'da izin, Y1'de kalori ve "tahmin" ibaresi;*
    - *silmede "Sağlık'taki kaydı da sil?" sorusu;*
    - *oturum türünün en uzun bloğa göre seçilmesi (oturum türü başta sabitlenir; antrenman planından önceden hesaplanmalı);*
    - *cihaz testi (AC-8.4) ve AC-8.6.*

## Faz 7 — MVP tamamlama ve pilot
- [ ] T7.1 İlk açılış O1–O7, O9; Ayarlar; dışa aktarma ve silme — 12, 10 (AC-10.3, AC-10.4, AC-10.6, AC-10.7)
- Durum (2026-11-24, T7.1):
  - *Yapıldı: ilk açılış O1–O7 ve O9 (`App/Home/OnboardingView`; sağlık yanıtları saklanmaz), alt sekme çubuğu (Antrenman · İlerleme · Ayarlar), Ayarlar (A).*
  - *Profil ayarları antrenmana uygulanır: kamera, form uyarısı sesi, sonuç tonları, yavaş tempo (`minDurationMs` × 2 ve "Daha yavaş"; 05 öntanımlısı `slow`).*
  - *Dışa aktarma `exportVersion: 1` ve silme `DataPortability`'de. Testler AC-10.3, AC-10.4 ve AC-10.7'yi kapsar.*
  - *Henüz yok:*
    - *O5'te "Sağlık'tan al" ve O6'da "İzin ver" (T6.2);*
    - *AC-10.6 anlık görüntü testi (uygulamada anlık görüntü altyapısı yok);*
    - *gizlilik politikası ile kullanım koşullarının hukuki metni (10 açık soru 1; uygulamadakiler taslak);*
    - *tema seçimi (sistem teması izlenir).*
- [x] T7.2 İlerleme G1–G3 — 12 *Durum (2026-11-24): `App/Home/ProgressHome` (G1 Swift Charts: 8 haftalık antrenman sayısı, seviyeye göre medyan RT, isabet; G2 geçmiş, detay ve silme; G3 son 30 günde eskiv bazında temiz tekrar oranı ve en sık hatalar). Hesaplar `ProgressStats`'ta, testli. Silmede Sağlık sorusu T6.2 ile gelir.*
- [x] T7.3 Gizlilik: ağ isteği testi, bağımlılık listesi, `PrivacyInfo.xcprivacy` — 10 (AC-10.1, AC-10.2, AC-10.5) *Durum (2026-11-24):*
  - *`App/Resources/PrivacyInfo.xcprivacy`: izleme yok, toplanan veri yok, `SystemBootTime` (35F9.1, `HostClock`).*
  - *`scripts/ci/check-privacy.sh` (Linux CI) gerekçe isteyen API'leri bildirime karşı tarar; uzak paket ve ağ API'si kullanılırsa kırılır.*
  - *`PrivacyTests`: bir antrenman boyunca `URLProtocol` sayacı 0, bildirim paket içinde.*
  - *AC-10.1'in "Release UI test akışları" kısmı UI test hedefi gelince (T7.4) aynı sayaçla genişletilir.*
- [ ] T7.4 TR/EN gözden geçirme, erişilebilirlik — 12 (AC-12.5, AC-12.6)
- Durum (2026-11-25, T7.4 kısmı): kural 6'nın yasaklı ifade testi tüm String Catalog'da (TR/EN, kök eşleşmesi; `ForbiddenPhraseTests`). İki metin değişti ("heart condition" → "heart problem", "Diagnostics" → "Developer panel"). Kalan: metinlerin insan gözüyle gözden geçirilmesi, VoiceOver ile O1–O7, O9 ve A akışları (AC-12.6), koyu/açık tema kontrolü.
- [ ] T7.5 TestFlight dağıtımı, pilot (hafta 0 kalibrasyon kayıtları → eşik taraması → şablon ve katalog güncellemesi) — 13, 11 (AC-11.6)
- [ ] T7.6 Pilot değerlendirmesi, geri bildirim listesi, v1.0 kapsam güncellemesi — 13

## Faz 8 — v1.0
Her biri önce ilgili spec'teki "v1.0" bölümünün kesinleştirilmesini gerektirir.
- [ ] T8.1 `sequence:` hata konumu (Swift + anlık görüntü) ve teep'in yeni sürümü — 04 (AC-4.6)
- [ ] T8.2 `lead_`/`rear_` sanal noktaları — 04 (AC-4.7)
- [ ] T8.3 `check` şablonu, `low_kick` işareti — 04, 05
- [ ] T8.4 `hold` tipi, `plank`, `single_leg_balance`, `guard_hold` (önce 04'te `guard_hold` tanımı) — 04, 06
- [ ] T8.10 v1.0 kondisyon şablonları: 04'teki "tanım bekliyor" satırlarının tanımları (`glute_bridge`, `superman`, `burpee`, `standing_rotation`), hoca onayı, şablon dosyaları ve testleri; T8.6'dan önce — 04, 06
- [ ] T8.5 Raunt modu — 05 (AC-5.10), 12 R4
- [ ] T8.6 Haftalık program motoru ve H4 — 06 (AC-6.6, AC-6.7)
- [ ] T8.7 Postür değerlendirmesi P1–P3, O8 — 07 (AC-7.1–AC-7.6)
- [ ] T8.8 StoreKit 2, kilitler, satın alma ekranı — 11 (AC-11.3–AC-11.5)
- [ ] T8.9 Ürün adı, mağaza metni (07 yasaklı ifade kontrolü), gizlilik politikası, ekran görüntüleri; App Store incelemesi — 00, 10

## Sonrası (sıra belirlenmedi)
- Apple Watch uygulaması: canlı nabız (antrenman yansıtma) ve bilekte titreşimli işaret — 08
- Kickboks ve boks spor paketleri (şablonlar, kataloglar, programlar) — 00, 11
- iCloud eşitlemesi (CloudKit) — 10
- Hocanın sesiyle işaret paketi — 05
- Görsel işaret modu — 05
- Uzaktan şablon güncellemesi (imzalı paket; 00 kural 2 değişikliği gerektirir) — 10

## Claude Code'a görev verme şablonu
> "specs/<NN-…>.md içindeki <AC-x.y> kabul kriterlerini karşılayan <Tx.y> görevini yap. Önce testleri yaz, sonra uygula. Kaynak golden testleri yeşil kalmalı. Spec dışı davranış ekleme; eksik veya çelişen nokta varsa dur ve belirt."

## Açık sorular
1. Faz sırası: kayıt modu (Faz 5) refleks modundan (Faz 4) önce mi gelmeli? Pilot hafta 0'daki kalibrasyon kayıtları için kayıt modu gerekir, ama refleks kayıtları için refleks modu da gerekir. Öneri: T5.1–T5.2'yi teknik modundan hemen sonra (Faz 3'ten sonra) yapıp eskiv kalibrasyonunu erken başlatmak; refleks kayıtları Faz 4'ten sonra.
2. Mac erişimi: Faz 3'ten itibaren görevler Xcode ve gerçek cihaz ister; Claude Code bulut oturumunda yalnız `SoloEngine` (Linux) görevleri tam yapılabilir. Diğer görevlerin yerel Mac'te Claude Code ile yürütülmesi planlanmalı.
