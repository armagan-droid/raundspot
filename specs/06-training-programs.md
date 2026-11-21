# 06 — Seans Motoru, Kondisyon ve Haftalık Program

Saf Swift, `SoloEngine/Session` ve `SoloEngine/Planner`. ref 03'teki program motorunun **bireysel** karşılığı: istasyon, devir, QR, tenant kavramları yoktur.

## Bölüm 1 — Seans motoru (MVP)
### Veri
```swift
Workout { id, name: Localized, sport: "muay_thai", blocks: [Block], estimatedMinutes }
Block =
  | warmup(steps: [GuidedStep])                     // kamerasız, sesli zamanlayıcı; kamerayla sayım yok
  | technique(exerciseId, sets, reps, restSec, mode: strict|lenient)  // tempo: Profile.techniqueTempo (05)
  | reflex(catalogId, level, cues: Int?, restSec)   // 05
  | conditioning(exerciseId, sets, reps?, durationSec?, restSec, mode)
  | round(catalogId, level, rounds, roundSec, restSec)  // v1.0, 05 "Raunt modu"
  | guided(steps: [GuidedStep])                     // mobilite / soğuma, kamerasız
GuidedStep { textKey, durationSec, audioKey? }
```
- Hazır antrenmanlar (MVP) veridir: `exercises/workouts/*.json`. Haftalık program (v1.0) bunları ve blok kalıplarını kullanır.
- Her blok, şablonun sürümünü seans başında sabitler ve kayda yazar (ref 03 ilkesi).

### Durumlar
```
IDLE → SETUP → WARMUP → READY → COUNTDOWN → ACTIVE ⇄ CONFIRM → (REST → READY) | BLOCK_DONE
BLOCK_DONE → READY (sonraki blok) | COOLDOWN → SESSION_DONE
```
- `SETUP`: seansın **ilk bloğundan önce**, bir kez: tıbbi uyarı ve alan onayı (12 S2), ardından antrenmanda en az bir kameralı blok varsa kamera kurulumu (12 S1). Isınma dahil hiçbir blok bundan önce başlamaz (00 kural 7). Yalnız kamerasız bloklardan oluşan antrenmanda (ör. rehberli mobilite) S1 atlanır, S2 atlanmaz. Seans sırasında takip kaybından sonra (ref 03 kural 10) yalnız S1 kontrolleri yeniden sağlanır; alan onayı yeniden istenmez.
- `WARMUP`: ısınma adımları sesli; `SKIP_WARMUP` ile atlanabilir, atlanınca bir kez "Isınmadan başlamak sakatlık riskini artırır" (`safety.warmup_skipped`) gösterilir ve seans kaydına `warmupSkipped = true` yazılır.
- `ACTIVE`: bloğun türüne göre teknik/kondisyon seti (ref 03 kural 3–5) ya da refleks seti (05 deneme döngüsü).
- `CONFIRM`: hareketsizlik (ref 03 kural 5: 10/20 sn) yalnız teknik ve kondisyon setlerinde; refleks setinde kullanılmaz (deneme döngüsünün kendi "Hazırlık" uyarısı vardır).
- `PAUSED`, `ABORTED`: ref 03'teki gibi; ayrıca uygulama arka plana geçince, telefon araması gelince ya da kamera kesilince (`AVCaptureSession` kesinti bildirimi) otomatik `PAUSED`; öne gelince elle "Devam".
- Terminal: `SESSION_DONE`, `ABORTED`.

### Geçiş kuralları
ref 03'ün şu kuralları aynen geçerlidir: 2 (geri sayım), 3 (sayaç; strict/lenient), 4 (set sonu), 5 (hareketsizlik, yalnız teknik/kondisyon), 6 (dinlenme), 10 (takip kaybı, 5 sn), 11 (güvenlik duraklatması), 12 (iptal), 15 (geçersiz girdi). Kaldırılanlar: 1'in yürütücü kısmı, 7'nin `TRANSFER`'i, 8, 9'un `TRANSFER` kısmı, 13, 14 (elle kayıt yok: kamera yoksa uygulama zaten antrenman başlatmaz).
Eklenenler:
- **E1 Refleks bloğu:** `ACTIVE`'de 05 deneme döngüsü yürür; set, işaret sayısı dolunca biter (`END_SET` ile erken bitirilebilir). Set özeti 05.
- **E2 Ses kesintisi:** başka uygulama ses oturumunu alırsa (ör. sesli mesaj) refleks seti `PAUSED` olur; teknik setinde yalnız uyarılar susar.
- **E3 Antrenman sonu:** son bloktan sonra `COOLDOWN` (guided adımlar, atlanabilir), sonra `SESSION_DONE`; HealthKit kaydı (08) ve özet.
- **E4 Kaldığı yerden devam:** durum `serialize/deserialize` edilir (ref AC-3.5). Uygulama kapanırsa 30 dk içinde açıldığında "Antrenmana devam et" önerilir; sonra seans `ABORTED` olarak kapanır.

### MVP hazır antrenmanları (taslak, hoca onayına bağlı)
| Antrenman | Süre | Bloklar |
|---|---|---|
| Eskiv temeli | ~15 dk | Isınma (3 dk) → teknik `slip_left` 2×8, `slip_right` 2×8, `duck` 2×8, `bob_weave_left/right` 1×6 → refleks seviye 1 (15) → soğuma (2 dk) |
| Refleks | ~11 dk | Isınma (3 dk) → refleks seçilen seviye ×3 set (60 sn dinlenme) → soğuma |
| Kondisyon | ~15 dk | Isınma → devre ×3: `jumping_jack` 20, `squat` 12, `pushup` 8, `reverse_lunge` 10 (her bacak), 60 sn dinlenme → soğuma |
| Hızlı karma | ~20 dk | Isınma → teknik (seçilen 2 eskiv) → refleks seviye seçimi ×2 → kondisyon devresi ×2 → soğuma |

## Bölüm 2 — Kuvvet ve kondisyon içeriği
Muay Thai'nin yoğun kullandığı kas grupları ve kameranın izleyebildiği hareketler. "İzlenir" = şablonla sayılır ve form denetlenir; "rehberli" = kamerasız, sesli zamanlayıcıyla.

| Kas grubu / beceri | Muay Thai'deki rolü | İzlenen hareketler | Rehberli | Sürüm |
|---|---|---|---|---|
| Kalça ve kalça bükücüler | Diz, tekme, teep | `squat`, `reverse_lunge`; `knee_strike` serisi | Kalça açıcı esneme | MVP; diz v1.0 |
| Arka bacak (kalça arkası, arka uyluk, baldır) | Tekme gücü, sıçrayış, lean back'te ağırlık | `reverse_lunge`; `glute_bridge` (yan) | Arka uyluk esnemesi | MVP; köprü v1.0 |
| Gövde dönmesi | Yumruk ve tekmenin kalçadan gelmesi | `standing_rotation` (önden: omuz açıklığı değişimi, yeni metrik gerekir) | Dönüşlü lunge (rehberli) | v1.0 |
| Gövde dengesi (core) | Clinch, darbe alma | `plank` (hold) | Ölü böcek (rehberli) | v1.0 |
| Omuz dayanıklılığı | Gardı raunt boyunca tutmak | `pushup`; `guard_hold` (hold, gard tutma) | Omuz çevirme | MVP; gard v1.0 |
| Boyun ve üst sırt | Clinch, darbe alma | `superman` (yan, hold) | Boyun izometrik (yalnız rehberli, yavaş, uyarılı) | v1.0 |
| Tek ayak denge | Teep, check, diz | `single_leg_balance` (hold, önden) | — | v1.0 |
| Dayanıklılık / kondisyon | Raunt temposu | `jumping_jack`; `burpee`, `jump_rope` | — | MVP; diğerleri v1.0 |
| Mobilite | Yüksek tekme, lean back, bob & weave | — | Kalça, ayak bileği, göğüs omurgası, omuz rutinleri | MVP (rehberli) |

- Tablodaki v1.0 izlenen hareketlerin bir kısmının (`guard_hold`, `glute_bridge`, `superman`, `burpee`, `standing_rotation`) tanımı 04'te henüz "tanım bekliyor" durumundadır; tanımlar yazılmadan program kalıplarına girmez (14 T8.10).
- **Boyun:** boyun egzersizleri kamerayla izlenmez ve yalnız izometrik (direnç hareketsiz) olarak, "ağrı varsa yapma" uyarısıyla rehberli verilir. Köprü (wrestler's bridge) gibi boyuna yük bindiren hareketler yoktur.
- Isınma ve soğuma içeriği hoca onayına bağlıdır; MVP taslağı: yerinde hafif sıçrama, kol çevirme, kalça çevirme, gölge hareketi (1 dk), dinamik esneme.

## Bölüm 3 — Haftalık program motoru (v1.0)
Saf, deterministik fonksiyon: `plan(profile, preferences, history, posture?, seed) → WeekPlan`.

### Girdi
| Alan | Değerler |
|---|---|
| Seviye | `beginner` (0–1 yıl), `intermediate` (1–3 yıl), `advanced` (3+ yıl) |
| Hedef | `defense` (eskiv ve refleks), `conditioning`, `balanced` |
| Haftalık gün | 2–5 |
| Seans süresi | 15, 20, 30, 45 dk |
| Uygun günler | Hafta günleri kümesi (opsiyonel) |
| Gard yönü | orthodox / southpaw |
| Postür bulguları | 07'deki bayraklar (opsiyonel) |
| Geçmiş | son 4 haftanın tamamlanan seansları, refleks seviyesi ve isabeti |

### Çıktı
```swift
WeekPlan { weekIndex, days: [PlanDay] }
PlanDay { weekday, kind: technique|conditioning|mobility|rest, workout: Workout }
```

### Kurallar
1. **Dağılım** (gün sayısı → T teknik+refleks, K kondisyon, M mobilite):

| Gün | `defense` | `balanced` | `conditioning` |
|---|---|---|---|
| 2 | T, T | T, K | K, T |
| 3 | T, T, K | T, K, T | K, T, K |
| 4 | T, T, K, M | T, K, T, M | K, T, K, M |
| 5 | T, T, K, T, M | T, K, T, K, M | K, T, K, T, M |
Teknik günlerinin hepsinde refleks bloğu vardır; kondisyon günleri 5–10 dk teknik bloğuyla başlayabilir (yorgunken teknik bozulmasın diye bu teknik bloğu kondisyondan önce gelir); kondisyon günlerinde refleks bloğu yoktur.
2. **Ardışıklık:** iki kondisyon günü ardışık gelmez; uygun günler buna izin vermiyorsa ikincisi mobiliteye çevrilir.
3. **Süreye sığdırma:** her gün kalıbı blokların tahmini süreleriyle seans süresine sığdırılır; sığmayan blok önce set sayısı azaltılarak, sonra bloğu çıkararak kırpılır. Isınma hiçbir zaman çıkarılmaz (en az 3 dk).
4. **İlerleme (4 haftalık döngü):** 1.–3. haftada hacim (set × tekrar) her hafta en fazla %10 artar; 4. hafta hafif (hacim %60). Refleks seviyesi, 05 "Seviye önerisi"ne göre kullanıcı kabul ederse yükselir; program kendiliğinden seviye değiştirmez.
5. **Kaçırılan gün:** plan sabit takvim değil sıradır: kaçırılan gün bir sonraki uygun güne kayar; aynı gün iki antrenman önerilmez.
6. **Postür etkisi:** 07 bayrakları mobilite ve kondisyon bloklarında hareket seçimini değiştirir (ör. "baş önde" → göğüs omurgası mobilitesi + `superman`), içerik tablosu 07'dedir. Postür bayrağı programdan bir hareket çıkarmaz, yalnız ekler veya öne alır.
7. **Tekrarlanabilirlik:** aynı girdi + aynı tohum → aynı plan (test). Tohum hafta başında üretilir ve planla saklanır.
8. Program kalıpları veridir: `exercises/programs/muay_thai.json` (gün kalıpları, blok havuzları, ilerleme parametreleri).

## Kabul kriterleri
- AC-6.1: Seans motorunun her geçişi birim testle kapsanır (ref AC-3.1 kapsamında kalan kurallar + E1–E4).
- AC-6.2: "Eskiv temeli" antrenmanı sentetik olay akışıyla baştan sona `SESSION_DONE`'a ulaşır ve beklenen komut sırasını üretir.
- AC-6.3: Hiçbir blok (ısınma dahil) alan onayından önce, kameralı antrenmanda hiçbir blok kamera kurulumu hazır olmadan başlamaz; ısınma atlanınca uyarı bir kez gösterilir ve kayda yazılır.
- AC-6.4: Arka plana geçiş, arama ve kamera kesintisi seansı `PAUSED` yapar; 30 dk içinde yeniden açılınca devam önerilir, sonra `ABORTED` (sahte saat).
- AC-6.5: Hazır antrenman JSON'ları şemaya uyar ve kullandıkları her şablon 04 şablon setinde vardır (CI).
- AC-6.6: (v1.0) Program üretici: dağılım tablosu, ardışık kondisyon yasağı, süreye sığdırma, %10 artış sınırı ve 4. hafta hafiflemesi testlerle doğrulanır; aynı tohum aynı planı verir.
- AC-6.7: (v1.0) Postür bayrağı yalnız ekleme/öne alma yapar, hiçbir hareketi çıkarmaz (test).

## Açık sorular
1. Hazır antrenmanların set/tekrar sayıları ve ısınma/soğuma içeriği hoca onayından geçmeli.
2. Gövde dönmesi için izlenebilir bir hareket: önden omuz açıklığı değişimiyle "ayakta dönüş" sayılabilir mi, yeni metrik (`shoulderSpanRatio`) gerekir; değer görülmezse rehberli kalsın mı?
3. Seviye tanımı (yıl bazlı) yeterli mi, yoksa ilk açılışta kısa bir refleks testiyle (10 işaret) seviye mi önerilmeli?
4. Antrenman hatırlatma bildirimi (yerel bildirim) v1.0'da olmalı mı?
