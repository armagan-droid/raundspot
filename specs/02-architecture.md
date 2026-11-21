# 02 — Mimari

## Karar özeti
| Konu | Karar | Gerekçe |
|---|---|---|
| Platform | Yalnız iOS (iPhone). iPad çalışır ama hedeflenmez. | Ürün kararı; tek cihaz türüyle test yükü düşük |
| Minimum sürüm | **iOS 26** | iPhone'da `HKWorkoutSession` + `HKLiveWorkoutBuilder` iOS 26 ile geldi (08); Vision'ın Swift API'si (iOS 18+) ve 3B poz (iOS 17+) bunu kapsar. Kasım 2026 itibarıyla son iki ana sürüm (26, 27). |
| Minimum cihaz | Spike (T0.2) sonucuyla belirlenir; varsayılan hedef A15 ve üstü (iPhone 13+) | Vision 3B ve 30 FPS bütçesi |
| Dil | Swift 6 (katı eşzamanlılık), SwiftUI | Ürün kararı |
| Kamera | AVFoundation: `AVCaptureSession` + `AVCaptureVideoDataOutput` | Kare zaman damgasına ve formatına tam kontrol |
| Poz | Apple Vision: `DetectHumanBodyPoseRequest` (2B, 19 eklem) + `DetectHumanBodyPose3DRequest` (3B, 17 eklem) | Cihaz üzerinde, ek model dosyası yok (03) |
| Kural motoru | **Swift'e çevrilmiş egzersiz katmanı** (`SoloEngine`), kaynak TS motorundan bir kez üretilen golden verisiyle sabitlenmiş (03'teki karşılaştırma ve öneri) | Performans, hata ayıklama, tip güvenliği |
| Ses | `AVAudioEngine` + `AVAudioPlayerNode` (önceden üretilmiş dosyalar), yedek `AVSpeechSynthesizer` | İşaret anını örnek doğruluğunda bilmek (05) |
| Yerel veri | SwiftData | iOS 17+ yerleşik; sunucu yok (11) |
| Satın alma | StoreKit 2 (v1.0), cihaz üzerinde doğrulama | Sunucu yok (11) |
| Sağlık | HealthKit (`HKWorkoutSession`, `HKLiveWorkoutBuilder`) | 08 |
| Yerelleştirme | String Catalog (`.xcstrings`), TR + EN | 00 kural 8 |
| Sunucu | **Yok** | 00 kural 2 |
| Dağıtım | TestFlight (MVP), App Store (v1.0) | 13 |

## Repo yerleşimi
```
README.md
CLAUDE.md                          # Claude Code kuralları (00 değişmez kurallarına atıf)
specs/                             # bu spec'ler (00–14)
docs/reference/b2b/                # salon ürününün spec'leri, commit c2fe3fd, salt okunur ("ref NN")
exercises/                         # hareket şablonları (04)
  source/                          # kaynak şablonların aynen kopyası (c2fe3fd), yalnız kaynak golden için; uygulamaya girmez
  reflex/  workouts/  programs/  energy/   # refleks katalogları, hazır antrenmanlar, program kalıpları, MET tablosu
fixtures/
  source-golden/                   # kaynak motordan bir kez üretilen golden (değiştirilmez, 03)
  snapshots/                       # Swift motorunun onaylı anlık görüntüleri (03)
  equivalence/                     # AC-4.4 eşdeğerlik testinin dondurulmuş şablon kopyaları (04)
  recordings/                      # kayıt modundan dışa aktarılan landmark dizileri (09)
tools/
  golden-export/                   # bir kerelik TS betiği: salon reposunun c2fe3fd kopyasında çalışır (03)
GymSpotSolo.xcodeproj              # uygulama hedefi + Debug/Beta/Release yapılandırmaları
Spike/                             # T0.2 ölçüm uygulaması (yalnız Debug hedefi, üretime girmez)
App/                               # SwiftUI uygulaması (ekranlar, akışlar)
  Resources/audio/{tr,en}/         # işaret ve uyarı sesleri
Packages/
  SoloEngine/                      # saf Swift: şema, ifade dili, metrikler, tekrar sayıcı, hata değerlendirici,
                                   # refleks değerlendirici, seans motoru, program üretici (UIKit/AVFoundation/Vision YOK)
  SoloCalibrate/                   # komut satırı aracı (macOS/Linux): şablon doğrulama, kalibrasyon raporu, eşik taraması (03, 09)
  SoloPose/                        # Vision → Frame adaptörü, kişi seçimi, koordinat dönüşümü
  SoloCapture/                     # AVFoundation kamera, ses çıkışı, saat eşleme
  SoloHealth/                      # HealthKit
  SoloRecording/                   # kayıt modu (yalnız Beta yapılandırmasında derlenir, 09)
```
- `exercises/` ve `fixtures/` uygulama paketine ve test hedeflerine derleme adımında kopyalanır; kaynakları tek yerdedir.
- `SoloEngine` Foundation dışında hiçbir şeye bağlı değildir ve **Linux'ta `swift test` ile çalışır**. Böylece motor ve uyumluluk testleri Mac olmadan (Claude Code bulut oturumu, Linux CI) koşar.
- Uygulama ve diğer paketler Xcode ve macOS ister.
- Node/TypeScript bu projenin derlemesinde ve CI'ında **yoktur**; yalnız `tools/golden-export` bir kez elle çalıştırılır (03).

## Akış (canlı antrenman)
```
AVCaptureSession (30 FPS, 1280×720, ön veya arka kamera)
   │ CMSampleBuffer (PTS, host saati)
   ▼
SoloPose: Vision 2B (her kare) + Vision 3B (03'teki karara göre)
   │ PoseObservation[] → kişi seçimi → Frame (vision19, world dönüştürülmüş)
   ▼
SoloEngine.ExerciseEngine (her aday şablon için bir örnek)
   │ EngineEvent[] (zaman damgalı)
   ▼
SoloEngine.ReflexEvaluator (refleks modu) / SessionMachine
   │ komutlar: SPEAK, SHOW, PLAY_CUE(at:), PERSIST, HAPTIC
   ▼
SwiftUI (ana aktör) + SoloCapture.AudioOut + SwiftData
```
- Görüntü işleme ana iş parçacığında yapılmaz. Kare kuyruğu: en fazla 1 kare bekler; yeni kare gelince işlenmeyen eski kare atılır (`alwaysDiscardsLateVideoFrames = true`) ve atılan kare sayısı tanı panelinde görünür.
- Motor durum makineleri saf (girdi → durum + komut) ve deterministiktir; zaman yalnızca kare zamanı ve `TICK` ile ilerler (ref 03 ilkesi).

## Saat tabanı
Tüm zamanlar **tek saatte**: `CMClockGetHostTimeClock()` (mach host time), milisaniyeye çevrilir.
- Kamera karesi: `CMSampleBufferGetPresentationTimeStamp` (capture session saati host saatine eşlenir; eşleme `AVCaptureSession.synchronizationClock` ile yapılır ve testte doğrulanır).
- Ses: işaret `AVAudioPlayerNode.scheduleBuffer(at: AVAudioTime(hostTime:))` ile **ileri bir zamana planlanır**; gerçek çıkış anı = planlanan host zamanı + `AVAudioSession.outputLatency` + `ioBufferDuration` (05 "İşaret anı").
- Motor olayları, olayı tetikleyen karenin zamanını taşır.

## Kamera kurulumu
- Varsayılan **ön kamera** (kullanıcı ekranı görebilir), ayarlardan arka kamera seçilebilir (daha geniş açı, daha iyi görüntü; ekran görünmez, ses yeterli).
- Telefon yere ya da bir standa, göğüs–bel hizasına, **yatay** konur (eskiv önden: geniş kadraj, kişi 2–3 m'de baştan ayağa sığar). Dikey kullanım desteklenir ama kurulumda yatay önerilir.
- Kare aynalanmaz (ref 04: aynalanmış görüntüde sola kaçış sağa görünür). Ön kamera önizlemesi kullanıcıya **aynalı gösterilir** (ayna gibi doğal), motora aynasız gider. Çizimler önizlemeyle aynı dönüşümü alır.
- Kurulum kontrolleri ref 08 "A3 kurulum kontrolleri" ile aynıdır; ek olarak mesafe tahmini ve alan onayı (12 S2).

## Performans bütçesi
| Ölçüt | Hedef | Alt sınır |
|---|---|---|
| İşlenen kare hızı (2B) | 30 FPS | 24 FPS |
| Kare → motor olayı gecikmesi (p95) | ≤ 60 ms | ≤ 100 ms |
| Kare → form uyarısı sesi (p95) | ≤ 200 ms | ≤ 250 ms (ref 05) |
| Ses planlama belirsizliği | ≤ 5 ms | ≤ 10 ms |
| 20 dk antrenmanda pil tüketimi | ≤ %10 | ≤ %15 |
| Termal durum | 20 dk sonunda `serious` değil | — |
- Termal durum `serious` olursa 3B istek kapatılır ya da kare hızı 24'e indirilir (kademeli düşüş, 03 "Kademeli çalışma"); kullanıcıya gösterilmez, tanı paneline yazılır.
- Ekran antrenman boyunca açık kalır (`isIdleTimerDisabled`).

## Ses oturumu
- `AVAudioSession` kategorisi `.playback`, mod `.default`, seçenek `.duckOthers` + `.mixWithOthers`: kullanıcının müziği çalarken işaretler duyulur, müzik kısılır.
- Mikrofon **hiç istenmez** (kayıt modu dahil, 09).
- Bluetooth kulaklık çıkış gecikmesi yüksektir (100–300 ms). `outputLatency` raporlanana göre düzeltilir; ancak bu değerin Bluetooth'ta güvenilirliği spike'ta ölçülür. Güvenilmezse refleks modunda Bluetooth çıkışta "tepki süresi yaklaşık" etiketi gösterilir (05).

## Kademeli çalışma (degradation)
Sıra: (1) 3B kapalı, 2B metrik yedekleri (03); (2) kare hızı 24; (3) refleks modunda aynı anda çalışan şablon sayısını aday tepkilerle sınırla (zaten öyle, 05). Her seviye düşüşü tanı paneline ve oturum kaydının meta verisine yazılır.

## Tanı paneli
ref 08 A5 tanı panelinin karşılığı: FPS (2B/3B ayrı), atılan kare, kare→olay gecikmesi, termal durum, ses çıkış yolu ve gecikmesi, kişi seçimi durumu, eklem görünürlükleri, aktif şablonlar ve durumları. Öntanımlı kapalı; Beta yapılandırmasında ayarlardan, App Store sürümünde 5 kez dokunmayla açılır. Hiçbir değer cihazdan çıkmaz.

## Derleme yapılandırmaları
| Yapılandırma | Kullanım | Fark |
|---|---|---|
| Debug | Geliştirme | Tanı paneli açık, sahte saat ve sahte kamera (dosyadan kare akışı) seçilebilir |
| Beta | TestFlight | `RECORDING_MODE` derleme bayrağı açık: `SoloRecording` paketi bağlanır (09) |
| Release | App Store | `SoloRecording` **derlenmez**; kayıt modu kodu ikili dosyada yoktur |

**Uygulama biçimi:** Xcode'da paket bağımlılığı yapılandırmaya göre değil hedefe göre bağlanır. Bu yüzden iki uygulama hedefi aynı kaynakları (`App/`) paylaşır:
- `GymSpotSolo`: Debug ve Release ile derlenir; `SoloRecording`'e bağlı **değildir**. App Store arşivi bu hedeften alınır.
- `GymSpotSoloBeta`: Beta ile arşivlenir (TestFlight); `SoloRecording`'e bağlıdır ve `RECORDING_MODE` bayrağını tanımlar. Geliştirme için Debug ile de çalıştırılabilir; Release ile derlenmeye çalışılırsa derleme hatası verir (`#error`).
- Kayıt moduna dokunan uygulama kodu `#if RECORDING_MODE` içindedir. İki hedefin bundle kimliği aynıdır (aynı App Store kaydı).

## CI
- Linux (GitHub Actions): `swift test --package-path Packages/SoloEngine` (kaynak uyumluluğu ve anlık görüntüler dahil) + `swift run --package-path Packages/SoloCalibrate solo-calibrate validate exercises/` (tüm şablon ve katalogların doğrulanması) + `exercises/source/SHA256SUMS` sağlama toplamı kontrolü (AC-4.2).
- macOS runner: `xcodebuild test` (uygulama ve diğer paketler), PR'larda. Maliyet yüksekse yalnız `main` ve etiketlerde. Aynı işte AC-2.3 (`GymSpotSolo` Release ikilisinde `SoloRecording` sembolü yok; karşı kontrol olarak `GymSpotSoloBeta` ikilisinde var) ve AC-2.5 (`Info.plist`'te mikrofon anahtarı yok) kontrol edilir.

## Spike T0.2 — Vision ve zamanlama ölçümü
**Amaç:** projenin en büyük teknik riskini kodun geri kalanı yazılmadan ölçmek.

**Ölçülenler** (en az: minimum hedef cihaz + güncel bir cihaz):
1. Vision 2B FPS ve gecikme (p50/p95), 1280×720 ve 1920×1080.
2. Vision 3B: kare başına süre; 2B ile birlikte her karede çalışabiliyor mu; çalışamıyorsa her N karede bir.
3. 3B eksen yönleri ve birimi (03 "Koordinat dönüşümü"'ndeki varsayımların doğrulanması).
4. 3B `centerHead` ile 2B `nose` arasındaki ilişki: önden slip ve duck sırasında `lateralLean(nose,…)` ile `lateralLean(centerHead,…)` farkı.
5. 2B güven (confidence) değerlerinin dağılımı: kadraj dışı, kısmen kapalı, bulanık karelerde (`minVisibility` eşiğinin karşılığı).
6. Önden lean back: 3B derinlikte (z) baş–kalça farkının değişimi ölçülebilir mi?
7. Ses: planlanan işaret anı ile gerçek çıkış arasındaki fark (hoparlör ve Bluetooth), ölçüm yöntemi 05 "Doğrulama".
8. 20 dk sürekli çalışmada termal durum ve pil.

**Sonuçlar:** bu bölüme cihaz başına bir satırlık tablo olarak yazılır.

| Cihaz | iOS | 2B FPS | 2B p95 (ms) | 3B ms/kare | 3B her kare? | Eksenler doğrulandı | centerHead↔nose | Termal 20 dk | Ses gecikmesi (hoparlör / BT) |
|---|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | — | — |

**Spike sonrası karar verilecekler:** minimum cihaz; 3B kullanım biçimi (her kare / seyrek / yok); eskiv metriklerinin 3B mi 2B mi hesaplanacağı (03); önden lean back şablonunun (`lean_back_front`) ve `high_kick` işaretinin refleks modunda yer alıp almayacağı (04, 05).

## Kabul kriterleri
- AC-2.1: `SoloEngine` paketi yalnız Foundation'a bağlıdır; Linux'ta `swift test` geçer (CI).
- AC-2.2: Kamera karesi, ses planlama zamanı ve motor olayları aynı host saatinde ifade edilir; sahte saatle uçtan uca test vardır.
- AC-2.3: Release yapılandırmasında `SoloRecording` sembolleri ikili dosyada bulunmaz (derleme sonrası `nm` kontrolü, CI).
- AC-2.4: Performans bütçesi spike cihazlarında ölçülür ve tabloya yazılır; alt sınırın altındaki cihaz desteklenmez.
- AC-2.5: Uygulama mikrofon izni istemez; `Info.plist`'te `NSMicrophoneUsageDescription` yoktur.
- AC-2.6: Termal `serious` durumunda kademeli çalışmaya geçilir ve antrenman kesilmez (sahte termal durumla test).

## Açık sorular
1. Minimum cihaz: spike'tan önce A15 varsayıldı; Türkiye'deki öğrencilerde eski iPhone oranı yüksekse (iPhone 11/12) 2B-yalnız modla destek genişletilebilir.
2. iPad desteği: kadraj ve yerleşim çalışır; mağazada "iPhone only" mi yoksa iPad uyumlu mu yayınlanacak?
3. macOS CI maliyeti: GitHub'ın ücretli macOS dakikaları yerine yerel Mac'te elle test yeterli mi?
