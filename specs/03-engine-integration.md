# 03 — Motor ve Vision Entegrasyonu

Bu dosya üç soruyu karara bağlar: (1) salon ürününden çatallanan kural motoru bu projede nasıl yaşayacak, (2) Apple Vision'ın eklem seti mevcut şablonlarla nasıl eşleşecek, (3) MediaPipe'la ayarlanmış eşikler nasıl yeniden kalibre edilecek.

## Kaynak: salon ürününün motoru (commit `c2fe3fd`)
GymSpot salon reposundaki `packages/engine` (TypeScript) iki katmandan oluşur:

| Katman | Dosyalar | Boyut (yaklaşık) | Bu projede |
|---|---|---|---|
| **Egzersiz katmanı** | `expr/*` (ifade dili), `metrics/*` (metrikler, One Euro, görünüm), `reps/rep-counter.ts`, `exercise/exercise-engine.ts`, `exercise/summary.ts`, `rules/load-rule-pack.ts`, `setup/*` | ~1.100 satır | **Swift'e çevrilir** (`SoloEngine`) |
| Program katmanı | `program/program.ts` | ~660 satır | **Alınmaz.** İstasyon, devir, QR, tenant kavramları salon ürününe özgü; bu proje kendi seans motorunu kullanır (06) |
| Kalibrasyon | `calibration/evaluate.ts` | ~140 satır | Swift'e çevrilir: kayıt modunda yeniden oynatma (09) ve `SoloCalibrate` aracı |
| Test araçları | `testing/*` (sentetik vücut, oynatıcı) | ~630 satır | Yalnız bir kerelik golden üretiminde kullanılır; Swift'te sentetik vücut ihtiyaç oldukça yazılır |

Şema (`packages/shared/src/rule-pack.ts`, Zod, katı: bilinmeyen alan hata) bu projede Swift `Codable` + doğrulayıcı olarak yeniden yazılır; davranışı ref 04 ve 04'teki eklemelerdir.

## Seçenekler
### (a) TypeScript motorunu JavaScriptCore ile çalıştırmak
Kaynak motor esbuild ile tek bir JS dosyasına paketlenir, uygulamaya gömülür ve `JSContext` içinde çalıştırılır. Her karede Swift `Frame`'i JS'e verilir, olaylar geri alınır. Bu, ayrı projede TS kodunu da bu repoya taşımak ve bakımını üstlenmek demektir.

### (b) Motoru Swift'e çevirmek
Egzersiz katmanı ve kalibrasyonun yeniden oynatma kısmı Swift'e çevrilir (`SoloEngine`). Aynı JSON formatını okur. Çatallanma anındaki davranış, kaynak motordan **bir kez** üretilen golden verisiyle sabitlenir.

### Karşılaştırma
| Ölçüt | (a) JavaScriptCore | (b) Swift + kaynak golden |
|---|---|---|
| Kaynak davranışa eşitlik | Kendiliğinden (aynı kod) | Testle sağlanır; golden kapsamı kadar güvenli |
| Kare başı maliyet | Her karede Swift↔JS dönüşümü; uygulama içi `JSContext` JIT'siz yorumlayıcıyla çalışır; refleks modunda 4–6 motor örneği aynı anda koşar | Doğrudan, ayırmasız; 6 örnek sorun değil |
| Hata ayıklama | JS yığın izi Xcode'da zayıf | Xcode, Instruments, Swift Testing |
| Tip güvenliği | Sınırda elle eşleme; şema değişince sessiz kırılma riski | Swift tipleri; şema değişikliği derleme hatası |
| Swift 6 eşzamanlılık | `JSContext` iş parçacığına bağlı | Doğal (`Sendable` değer tipleri) |
| Derleme zinciri | Node + pnpm + esbuild + TS kaynak kodu bu repoda | Yalnız Swift |
| Projeye özgü genişleme | Yeni metrikler (2B fonksiyonlar), refleks, seans: iki dil karışır | Hepsi Swift |
| Linux'ta test | JS ayrı, köprü test edilmez | `swift test` Linux'ta (02) |
| Bakım | İki dil, tek motor | Tek dil, tek motor |

### Karar: (b) Swift motoru
Gerekçe:
1. **Proje ayrıldı:** TS motorunu taşımak, bu projeye bir Node araç zinciri ve ikinci bir dil eklerdi. Swift motoru projenin tek motorudur; senkron tutulacak ikinci bir motor yoktur.
2. **Refleks modu birden çok motoru aynı anda koşturur** (05); (a)'da her kare 4–6 kez JS sınırını geçer.
3. **Çevrilecek kısım küçük ve kararlı:** ~1.100 satır saf fonksiyon; en karmaşık kısım (program katmanı) zaten alınmıyor.
4. **Çeviri hatası mekanik olarak yakalanır:** kaynak golden (aşağıda).
5. Davranış zaten spec'te yazılı (ref 04, ref 05); çeviri spec'in ikinci uygulamasıdır.

(a) yedek plan olarak kalır: Swift çevirisi kaynak uyumluluğunda tıkanırsa egzersiz katmanı JSC'de çalıştırılabilir.

## Kaynak uyumluluğu (bir kerelik golden)
### Üretim
- `tools/golden-export/` (bu repoda, TypeScript, ~200 satır): salon reposunun **`c2fe3fd`** commit'inin bir kopyasında çalıştırılır (`git clone` + `git checkout c2fe3fd` + `pnpm install`, geçici dizinde). Kaynak motoru ve `@gymspot/engine/testing` sentetik üreticilerini kullanır. Çıktı `fixtures/source-golden/` altına yazılır ve repoya girer. Bir kez çalıştırılır; yeniden çalıştırmak aynı dosyaları bayt bayt üretmelidir (deterministik).
- Bu betik ve Node yalnız bu adım içindir; CI'da ve derlemede yoktur (02).
- Her golden dosyası bir **durum**dur:
```jsonc
{
  "goldenVersion": 1,
  "source": { "repo": "armagan-droid/gymspot", "commit": "c2fe3fd" },
  "rulePack": "slip_left", "rulePackVersion": 1,          // exercises/ altındaki kaynak kopya
  "setup": { "view": "front", "nearSide": "left" },
  "options": { "safetyPause": true },
  "cuesEnabled": [ { "fromT": 0, "enabled": true } ],
  "sequence": "sequences/slip_left/noisy_seed7.json",      // LandmarkSequence formatVersion 1 (mediapipe33)
  "expected": {
    "events": [ { "frame": 41, "t": 1366.7, "type": "REP_STARTED" },
                { "frame": 58, "t": 1933.3, "type": "REP_COMPLETED", "outcome": "valid", "faults": [], "durationMs": 667 } ],
    "metrics": { "every": 10, "values": [ /* her 10. karede yumuşatılmış metrikler */ ] },
    "repStates": [ /* her karede WAITING | AT_START | IN_REP */ ]
  }
}
```
- Alan biçimleri (golden ve anlık görüntü ortak): `events[]` olayın tüm alanlarını taşır (`type` + kaynak alanları) ve `frame` (dizideki 0 tabanlı kare indeksi) ile `t` (o karenin zamanı) eklenir. `metrics.values[]` her `every`'inci karede (0, 10, 20 …) bir eleman: `{ "frame": i, "values": { "<metrik>": sayı | null } }`; anahtarlar motorun değerlendirme sırasındadır, `NaN` `null` yazılır (JSON `NaN` taşımaz). `cuesEnabled` adımları, `t ≥ fromT` olan ilk kareden önce uygulanır. Sayılar JavaScript `JSON.stringify` biçimindedir (Swift yazıcısı aynı biçimi üretir).
- Kapsam: kaynaktaki 11 şablonun tümü (`slip`, `slip_left`, `slip_right`, `duck`, `squat`, `pushup`, `teep`, `knee_strike`, `straight_punch`, `mae_geri`, `shoulder_press`; uygulamaya girmeyenler dahil, çünkü golden sonradan yeniden üretilmez) için en az 3 temiz, 3 hatalı, 1 eşik salınımı (ref AC-4.4), 1 takip kaybı, 1 düşük görünürlük, 1 `ambiguous` görünüm durumu; farklı tohum, gürültü, aynalama. Ayrıca ifade dili golden'ı: ifade + metrik değerleri → `true` / `false` / `unknown` ya da ayrıştırma hatası kodu.
- Kaynak şablonlar `exercises/source/` altına aynen kopyalanır (golden onlara bağlıdır); bu projenin kendi şablonları `exercises/` altındadır (04).

### Doğrulama
- `SoloEngineSourceConformanceTests` tüm kaynak golden dosyalarını okur, aynı diziyi Swift motorundan geçirir.
- **Eşitlik kuralları:** olaylar (tür, sıra, kare indeksi, alanlar) birebir; metrikler mutlak ya da göreli fark ≤ 1e-9 (gerekçeli gevşetme 1e-7'ye kadar, bu bölüme yazılır); `NaN` = `NaN`; rep durumları birebir.
- Kaynak golden **değiştirilmez ve silinmez.** Bu projede kaynak davranış bilerek değiştirilirse (ör. bir varsayılan değer), etkilenen dosyalar `fixtures/source-golden/superseded.json` listesine spec bölümü ve gerekçeyle yazılır; test o dosyaları atlar.

### Yeni davranış: anlık görüntüler
Kaynakta olmayan her şey (2B metrik fonksiyonları, `vision19`, `sequence:`, `hold`, refleks sınıflandırması …) Swift'te birim testleriyle (elle hesaplanmış beklenen değerler) geliştirilir. Uçtan uca davranış, Swift motorunun ürettiği ve gözden geçirilip onaylanan **anlık görüntülerle** (`fixtures/snapshots/`) korunur: aynı biçim, `source` yerine `"generatedBy": "SoloEngine <sürüm>"`. Anlık görüntü ayrıca şablon dosyasının repo köküne göre yolunu (`"rulePackFile"`) taşır; girdi dizisi `fixtures/snapshots/sequences/` altında saklanır ve test motoru **saklanan** diziyle çalıştırır (sentetik üreticideki bir değişiklik anlık görüntüyü kırmaz; dizi yalnız `UPDATE_SNAPSHOTS=1` ile yeniden yazılır). Dosya ya da dizi yoksa test başarısız olur ve ne yapılacağını yazar. Anlık görüntü yalnız ilgili spec değişikliğiyle güncellenir (`swift test` ile `UPDATE_SNAPSHOTS=1`, PR'da fark gözden geçirilir).

### Zaman damgalı olaylar
Kaynak `EngineEvent` olayları zaman taşımaz. Swift motoru her olaya karenin `t`'sini ekler (`TimedEvent { t, event }`); kaynak golden'daki `frame`/`t` alanları golden-export betiği tarafından eklenir.

### Çatallanma sonrası salon değişiklikleri
Salon reposunda `c2fe3fd` sonrası motor değişiklikleri buraya kendiliğinden gelmez. Faydalı bir değişiklik alınacaksa: önce ilgili spec (04/05) güncellenir, Swift'te uygulanır, testleri yazılır. Kaynak golden yeniden üretilmez.

## Apple Vision eklem setleri
### 2B — `DetectHumanBodyPoseRequest` (19 eklem)
`nose, leftEye, rightEye, leftEar, rightEar, neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle`. Her nokta normalize görüntü koordinatı ve güven (0–1) taşır.

### 3B — `DetectHumanBodyPose3DRequest` (17 eklem)
`topHead, centerHead, centerShoulder, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, spine, root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle`. Metre cinsinden; `root` kalça ortasıdır. **Burun, göz ve kulak yoktur.** Eklem başına güven değeri yoktur (spike'ta doğrulanır); görünürlük 2B güveninden alınır.

### Eşleme tablosu (MediaPipe 33 → Vision)
| MediaPipe | Vision 2B | Vision 3B | Not |
|---|---|---|---|
| `nose` | `nose` | — | 3B'de yok → **`centerHead` vekil** (aşağıda) |
| `left_eye_inner`, `left_eye_outer`, `right_eye_inner`, `right_eye_outer` | — | — | Eksik |
| `left_eye`, `right_eye` | `leftEye`, `rightEye` | — | Yalnız 2B |
| `left_ear`, `right_ear` | `leftEar`, `rightEar` | — | Yalnız 2B |
| `mouth_left`, `mouth_right` | — | — | Eksik |
| `left/right_shoulder` | ✓ | ✓ | |
| `left/right_elbow` | ✓ | ✓ | |
| `left/right_wrist` | ✓ | ✓ | |
| `left/right_pinky`, `left/right_index`, `left/right_thumb` | — | — | Eksik (el pozu ayrı istektir, kullanılmaz) |
| `left/right_hip` | ✓ | ✓ | |
| `left/right_knee` | ✓ | ✓ | |
| `left/right_ankle` | ✓ | ✓ | |
| `left/right_heel`, `left/right_foot_index` | — | — | Eksik |
| — | `neck` | `centerShoulder` | Vision'a özgü; şablonlarda kullanılmaz |
| — | `root` | `root` | Kalça ortası; dönüşümde merkez |
| — | — | `spine`, `topHead` | Yalnız 3B |

**Eksik eklemler (16):** göz iç/dış (4), ağız (2), el parmakları (6), topuk (2), ayak ucu (2). 2B'de olup 3B'de olmayanlar: burun, gözler, kulaklar (5).

### `vision19` iskeleti ve şema
- Şablonlar landmark adlarını **MediaPipe adlarıyla** yazmaya devam eder (kaynak format korunur). Swift motoru bu adları Vision eklemlerine çözer.
- `SoloEngine` yükleyicisi, şablonun kullandığı (metrik, `minVisibleLandmarks`, `readyPose`, hata ifadeleri; `near_`/`far_` çözümünden sonra) her landmark'ın iskelette bulunduğunu doğrular. Eksik landmark kullanan şablon **reddedilir** (`unsupported_landmark`), uygulama onu listede göstermez.
- Landmark dizisi formatı (ref 04 "fixture formatı") genişler: `formatVersion: 2`'de `skeleton: "mediapipe33" | "vision19"` alanı zorunludur ve `vision19`'da eksik eklemler `null` olarak tutulur (`Landmark | null`). `formatVersion: 1` dosyaları (kaynak golden dizileri) `mediapipe33` olarak okunur. `null` nokta motora görünürlük 0 ve `NaN` koordinat olarak verilir. Ayrıntılar:
  - `image` ve `world` her karede 33 elemanlı dizidir (MediaPipe sırası). `mediapipe33`'te hiçbir eleman `null` olamaz. `vision19`'da Vision'da olmayan 16 eklem (aşağıda "Eksik eklemler") **mutlaka** `null`, diğer 17 eklem `null` olmayan noktadır (görülmeyen eklem `visibility: 0` ile yazılır).
  - `formatVersion: 2`'de üst düzey `imageAspect` (pozitif sayı: işlenen görüntünün genişliği / yüksekliği, kişinin dik göründüğü yönde) zorunludur ve her kareye `Frame.imageAspect` olarak geçer; `formatVersion: 1` dizileri 1 (kare görüntü, kaynak sentetik üretici) kabul edilir. Yeni 2B fonksiyonları x'i bununla düzeltir (04 "En-boy düzeltmesi").
  - 3B verisi olmayan kayıtta (H2, kademeli çalışma) `world` alanı kare başına `null` yazılır; motora bütün world noktaları `NaN` koordinat ve görünürlük 0 olarak verilir. JSON `NaN` taşıyamadığı için bu tek gösterimdir.
- Swift sentetik vücut aracına `toVision19(frame)` eklenir: MediaPipe çerçevesinden eksik noktaları atar, 3B'de burun yerine `centerHead` tahminini koyar (iki kulağın world orta noktası; görünürlüğü 2B burnunki) ve 3B'de olmayan göz ve kulakları eksik yapar. İsteğe bağlı olarak world tamamen kaldırılır (H2). Böylece kaynak golden dizileri `vision19`'a indirgenip yeni davranışın anlık görüntülerinde kullanılır.

### Etkilenen şablonlar
Mevcut şablonların hiçbiri 2B'de eksik bir eklemi kullanmıyor. Sorun world (3B) hesaplanan metriklerde:

| Şablon | World kullanan metrik | Vision'da durum | Etki |
|---|---|---|---|
| `slip`, `slip_left`, `slip_right` | `lateralLean(nose, hip)` (baş), `lateralLean(shoulder, hip)` (gövde) | Baş: **burun 3B'de yok**. Gövde: tamam | Baş metriği vekil ya da 2B'ye geçiş gerekir |
| `duck` | `chainHeight(nose, shoulder, hip, knee, ankle)` | **Burun 3B'de yok** | Aynı |
| `squat`, `pushup`, `shoulder_press`, `straight_punch` | `angle` (diz, dirsek, omuz) | Eklemler 3B'de var | H1'de yalnız eşik kalibrasyonu; H2'de `angle2d` ile yeniden yazılır |
| `teep`, `knee_strike`, `mae_geri` | Yalnız 2B (`diffY`, `angleFromVertical`) | Tamam | Yalnız eşik kalibrasyonu |
| Yeni `lean_back_front` (refleks, önden) | `sagittalLean` (3B derinlik, 04) | Derinlik doğruluğu bilinmiyor | **Deneysel**, yalnız H1 (04). Teknik modundaki `lean_back` yandan 2B'dir, etkilenmez |

Ayrıca `minVisibility` (0,6) MediaPipe "visibility" ölçeğine göredir; Vision güven ölçeği farklıdır. Tüm şablonlarda eşik yeniden belirlenir (aşağıda "Kalibrasyon").

### Baş noktası için karar (spike T0.2'ye bağlı)
| Seçenek | Ne yapılır | Ne zaman |
|---|---|---|
| **H1 – 3B vekil** | World `nose` = 3B `centerHead` (+ spike'ta ölçülen sabit ofset) | 3B her karede ya da ≥ 15 Hz çalışabiliyorsa ve `centerHead` slip/duck'ta burunla tutarlıysa (spike madde 4) |
| **H2 – 2B metrik** | World kullanan şablonlar bu projede 2B olarak yeniden yazılır: baş yatışı 2B görüntüden (`lateralLean2d`, 04), eğilme önden baş yüksekliği / omuz genişliğinden (`heightOverShoulders2d`; `chainHeight2d` önden öne eğilmeyi görmez, 04 açık soru 6), eklem açıları 2B'den (`angle2d`) | 3B yavaşsa; eskivler zaten **önden** ve ön düzlemde olduğu için 2B yatış doğrudan görüntü düzlemindedir; squat/şınav açıları **yandan** 2B'de doğru ölçülür |
| H3 – karma | 3B her N karede, araya 2B ile enterpolasyon | Önerilmez: iki hızlı veri akışı motoru karmaşıklaştırır |

**Varsayılan plan H2'dir** (2B, her karede, 30 FPS), çünkü refleks modu tepki süresi için kare hızına ve düşük gecikmeye öncelik verir. H2'de MVP'nin hiçbir şablonu 3B'ye bağlı değildir; tek istisna derinlik gerektiren `lean_back_front`'tur (04, deneysel) ve o yalnız H1 doğrulanırsa açılır. H1 doğrulanırsa 3B, açı metriklerinde de kullanılabilir. Karar spike tablosuna (02) ve bu bölüme yazılır.

## Koordinat dönüşümü (Vision → `Frame`)
`SoloPose`, Vision gözlemini ref 02'deki `Frame` sözleşmesine çevirir:
- **Görüntü (`image`):** Vision normalize koordinatlarının orijini **sol alt**tır; MediaPipe ise sol üst. `x' = x`, `y' = 1 − y`. Görüntü yönü (`.up`, `.right` …) kamera ve cihaz yönüne göre Vision isteğine `orientation` olarak verilir; çıkış her zaman "dik" kare koordinatındadır. Ön kamera kareleri motora aynasız gider (02).
- **Görünürlük:** Vision 2B güveni olduğu gibi `visibility` alanına yazılır; tanınmayan eklem `visibility = 0`.
- **World:** Vision 3B noktaları `root` merkezlenir, eksenler ref 04'e çevrilir: x kişinin görüntüdeki sağına, **y aşağı**, **z kameradan uzağa**, metre. Vision'ın kendi eksen yönleri spike'ta doğrulanıp dönüşüm matrisi buraya yazılır (şu an varsayım: x sağ, y yukarı, z kameraya doğru → `y' = −y`, `z' = −z`). 3B yoksa ya da kapalıysa (H2, kademeli çalışma) `world` alanı `NaN` doldurulur ve yükleyici world metrik (`angle`, `lateralLean`, `chainHeight`, `sagittalLean`) kullanan şablonu o oturum için `world_unavailable` hatasıyla reddeder; uygulama o şablonu listede göstermez.
- **Kişi seçimi:** Vision birden fazla gözlem döndürür. ref 07 "Seçim kuralları" aynen uygulanır (`numPoses` karşılığı: en fazla 2 aday değerlendirilir; diğerleri atılır).

## Kalibrasyon
Tüm şablonlar `status: "draft"`'tır ve eşikler MediaPipe sentetik verisiyle belirlenmiştir. Vision için:
1. Kayıt modunda (09) her eskiv için hoca + en az 3 öğrenciden, önden, etiketli kayıt (doğru / hatalı + hata türü).
2. Kayıtlar landmark dizisi (v2, `vision19`) olarak dışa aktarılır (`fixtures/recordings/`) ve `SoloCalibrate` aracıyla eşik taraması yapılır: `solo-calibrate report --files fixtures/recordings/slip_left --sweep rep.target.enter=0.26,0.28,0.30` (ref 09'daki ölçüt tanımları ve sweep yol sözdizimi).
3. Yeni eşikler doğrudan `exercises/<id>.json` dosyasına yazılır ve şablonun `version`'ı artar. Kaynak kopyalar (`exercises/source/`) değişmez.
4. Pilot ölçütlerini (sayım ≥ %95, yanlış alarm ≤ %10) karşılayan şablon `status: "calibrated"` olur.

## Kabul kriterleri
- AC-3.1: `tools/golden-export`, `c2fe3fd` kopyasında iki kez çalıştırıldığında bayt bayt aynı `fixtures/source-golden/` içeriğini üretir; üretilen her dosya `source.commit` taşır.
- AC-3.2: Swift motoru `superseded` listesinde olmayan tüm kaynak golden durumlarında olay, rep durumu ve metrik eşitlik kurallarını sağlar (CI, Linux).
- AC-3.3: İfade dili golden'ı: her ifade için ayrıştırma hatası kodu veya üç değerli sonuç kaynakla aynıdır; Swift ayrıştırıcısı ref AC-4.2'yi sağlar (kod çalıştırma yok).
- AC-3.4: `formatVersion: 1` (kaynak) ve `formatVersion: 2` (`mediapipe33`, `vision19`) dizileri Swift'te yüklenir; v2'de `skeleton` yoksa ya da eksik eklem `null` değilse reddedilir.
- AC-3.5: İskelette olmayan landmark kullanan şablon Swift yükleyicide `unsupported_landmark` hatasıyla reddedilir (test).
- AC-3.6: Vision → `Frame` dönüşümü: bilinen bir test görüntüsünde (sabit poz) y ekseni ve sol/sağ doğru; ön kamera karesinde `lateralLean2d` işareti kişinin soluna kaçışta pozitiftir (cihaz testi + sentetik birim testi).
- AC-3.7: Anlık görüntüden sapan motor değişikliği CI'da kırılır; `fixtures/source-golden/` altındaki bir dosyanın değişmesi ya da silinmesi CI'da kırılır (yalnız `superseded.json` eklenebilir).

## Açık sorular
1. Spike sonrası H1/H2 kararı. H2'de squat önden görünümde 2B diz açısı derinliği küçük gösterir (perspektif); squat iOS'ta yalnız yandan mı desteklenmeli?
2. Kalibrasyon kayıtları için yeterli katılımcı: hoca + 3 öğrenci yeterli mi, farklı boy/kilo/kıyafet çeşitliliği nasıl sağlanacak?
3. MediaPipe'ı iOS'ta da kullanmak (MediaPipe Tasks iOS SDK) bir seçenek olarak değerlendirilmedi; ürün kararı Vision. Spike'ta Vision yetersiz kalırsa yeniden açılmalı mı?
