# 04 — Hareket Kuralları ve Yeni Şablonlar

Temel: ref 04 (şema, tekrar algılama, ifade dili, görünüm, görünürlük, metrik fonksiyonları). Bu proje o formatı çatallanma anındaki haliyle devralır; bu dosya **bu projedeki eklemeleri**, şablon setini ve yeni şablonları tanımlar. ref 04 ile bu dosya çelişirse bu dosya geçerlidir.

## Genişletme ilkeleri
1. **Kapalı liste korunur:** her yeni metrik fonksiyonu, ifade yapısı ya da alan önce bu dosyaya yazılır, sonra Swift'e (testleriyle) girer. Spec'te olmayan alan yükleyicide hatadır (ref 04 katılığı sürer).
2. **Kaynak davranış korunur:** devralınan alan ve fonksiyonların anlamı değişmez; kaynak golden testleri (03) bunu sabitler. Anlam değişikliği gerekiyorsa yeni bir ad (fonksiyon, alan) eklenir.
3. **Kaynak kopyalar dokunulmazdır:** `exercises/source/` altındaki şablonlar yalnız kaynak golden içindir, uygulamaya girmez. Uygulamanın şablonları `exercises/` altındadır; kaynak bir şablondan türetilen şablon aynı `id`'yi taşır ve `derivedFrom: { "id", "version", "commit": "c2fe3fd" }` ile kökenini belirtir.
4. Her yeni şablon `status: "draft"` ile başlar ve `howTo` (TR/EN) taşır (ref 04'te eskiv paketleri için zorunlu olan kural bu projede tüm şablonlara uygulanır).

## Şema eklemeleri
### MVP
**`derivedFrom`** (opsiyonel): `{ id, version, commit }` — kaynak şablon kökeni (yalnız bilgi; motor davranışını etkilemez).

**`overlay.headTarget.back`** (opsiyonel, pozitif sayı): yan görünümde geriye yatma eşiği; `lean_back` hedef çizimi için. Kural ref 04'teki gibi: rep `target.enter` ile aynı değeri taşır (test).

**Yeni metrik fonksiyonları** (ref 04 "Metrik fonksiyonları" kapalı listesine eklenir):

| Fonksiyon | Tanım | Koordinat |
|---|---|---|
| `min: [m1, m2]` | iki metriğin küçüğü; biri `NaN` ise diğeri (`max`'in eşi). Sağ/sol değişen hareketlerde azalan tekrar metriği için (lunge) | — |
| `angle2d: [a, b, c]` | b noktasındaki a-b-c açısı, görüntü düzleminde (0–180°). Görüntü en-boy oranı düzeltilir (x, kare genişliği/yüksekliği oranıyla ölçeklenir) | görüntü (2B) |
| `lateralLean2d: [a, b]` | b→a doğrusunun görüntüde dikeyden işaretli sapması: a'nın b'ye göre kişinin soluna yatay uzaklığı / a–b görüntü uzunluğu. Kişinin solu: görüntüde sol omuzdan sağ omuza x farkının işaretiyle. Omuzların görüntü açıklığı / gövde boyu < 0,30 ise (kişi yan dönmüş) `NaN` | görüntü (2B) |
| `chainHeight2d: [p1, …, pn]` (2–6) | p1'in pn'den görüntüdeki dikey yüksekliği / zincirin görüntüdeki parça uzunlukları toplamı. 1 = dümdüz ve dik | görüntü (2B) |
| `sagittalLean: [a, b]` | a'nın b'ye göre kişinin **arkasına** doğru yatay uzaklığı / a–b uzunluğu (pozitif = geriye). "Ön" yönü: omuz çizgisine dik yatay birim vektör; önden görünümde kameraya doğru, yandan görünümde görüntüde burnun yakın kulağa göre bulunduğu taraf | world (3B) |
| `sagittalLean2d: [a, b]` | `sagittalLean`'in yan görünüm karşılığı, görüntü düzleminde. Görünüm `side` değilse `NaN` | görüntü (2B) |

- 2B fonksiyonlar H2 planının (03) temelidir: world kullanan her MVP şablonu bunlarla yeniden yazılır.
- `sagittalLean` yalnız 03'te H1 doğrulanırsa kullanılır (`lean_back_front`, önden).
- Test kapsamı: her yeni fonksiyon için tanımsız geometri (`NaN`), işaret yönü ve aynalama birim testleri + anlık görüntü (03).

### v1.0
**`lead_` / `rear_` sanal noktaları:** `near_`/`far_` gibi `LandmarkRef`'e eklenir. Çözüm seansın gard yönüne göredir: `orthodox` → lead = left, rear = right; `southpaw` → tersi. Gard yönü `ExerciseSetup`'a `stance` olarak girer. Kullanım: jab/cross ayrımı, "ön bacak teep", ön bacak check.

**`sequence:` hata konumu:** sıralama hatası için.
```ebnf
check    = position ":" expr | "sequence" ":" expr "before" expr ;
```
- Anlam: deneme boyunca A ifadesinin **ilk** doğru olduğu an `tA`, B'ninki `tB` (her ikisi de `holdMs` kadar kesintisiz doğru kalmalı; varsayılan 100 ms). `tA` tanımlı ve (`tB` tanımsız veya `tA < tB`) ise hata tespit edilir.
- Deneme bitince bir kez değerlendirilir (uyarı zamanlaması `at_turn` ile aynı, ref 05).
- Bilinmeyen değer kuralı aynen geçerlidir: bilinmeyen kare "doğru değil" sayılır.
- `before` ve `sequence` ayrılmış sözcük olur.

**`hold` tipi:** ref 04'te ayrılmış, MVP dışı. v1.0 tanımı:
```jsonc
"type": "hold",
"hold": {
  "condition": "hip_line > -0.05 and hip_line < 0.05",   // tutuş koşulu
  "enterMs": 1000,          // koşul bu kadar sağlanınca süre sayımı başlar
  "graceMs": 500,           // koşul bu süreden kısa bozulursa süre durmaz
  "targetMs": 30000         // bloktaki durationSec ile ezilebilir
}
```
Hatalar `during_hold:` konumuyla yazılır (koşulun alt bozulmaları, ör. kalça sarkması). `rep` alanı `hold` tipinde yoktur.

**Durumlu metrik `riseFromBaseline: [a]`** (ip atlama için): a'nın son 2 sn'lik yürüyen medyanına göre görüntüde yükselişi / gövde boyu. ref 04'teki "metrikler her karede bağımsız hesaplanır" varsayımını bozduğu için ayrı onay gerektirir (açık soru).

## Şablon seti
| Şablon | Kaynak | Görünüm | Mod | Sürüm | Not |
|---|---|---|---|---|---|
| `slip_left`, `slip_right` | kaynaktan türetilmiş, 2B | front | teknik, refleks | **MVP** | Baş: `lateralLean2d(nose, …)` |
| `slip` | kaynaktan türetilmiş, 2B | front | teknik | **MVP** | Yön serbest (`max`); refleks kataloğunda yoktur, çünkü refleks modunda yön ölçülür (05) |
| `duck` | kaynaktan türetilmiş, 2B | front | teknik, refleks | **MVP** | `chainHeight2d` |
| `bob_weave_left`, `bob_weave_right` | **yeni** | front | teknik, refleks | **MVP** | aşağıda |
| `lean_back` | **yeni** | side | teknik | **MVP** (deneysel) | aşağıda |
| `lean_back_front` | **yeni** (world) | front | refleks | yalnız 03 H1 doğrulanırsa (deneysel) | aşağıda |
| `squat` | kaynaktan türetilmiş (`angle2d`) | side | kondisyon | **MVP** | yandan |
| `pushup` | kaynaktan türetilmiş (`angle2d`) | side | kondisyon | **MVP** | |
| `reverse_lunge` | **yeni** | side | kondisyon | **MVP** | aşağıda |
| `jumping_jack` | **yeni** | front | kondisyon | **MVP** | aşağıda; ısınmada kamerasız rehberli adım olarak da geçer (06), orada sayılmaz |
| `check` | **yeni** | front | teknik, refleks | v1.0 | aşağıda |
| `teep` | kaynaktan türetilmiş + yeni hata (`sequence`) | side | teknik | v1.0 | aşağıda |
| `knee_strike` | kaynaktan türetilmiş | side | teknik, kondisyon | v1.0 | |
| `plank`, `single_leg_balance` | **yeni** (`hold`) | side / front | kondisyon, mobilite | v1.0 | |
| `jump_rope` | **yeni** (`riseFromBaseline`) | front | kondisyon | v1.0 | açık soru |
| `guard_hold` | **yeni** (`hold`) | front | kondisyon | v1.0 | tanım bekliyor; tutuş koşulu gard tanımıyla aynı (`guard_l > -0.3 and guard_r > -0.3`, 05) |
| `glute_bridge` | **yeni** | side | kondisyon | v1.0 | tanım bekliyor |
| `superman` | **yeni** (`hold`) | side | kondisyon | v1.0 | tanım bekliyor |
| `burpee` | **yeni** | side | kondisyon | v1.0 | tanım bekliyor |
| `standing_rotation` | **yeni** (yeni metrik gerekir) | front | kondisyon | v1.0, koşullu | tanım bekliyor; 06 açık soru 2, metrik kabul edilmezse rehberli kalır |
| `straight_punch`, `mae_geri`, `shoulder_press` | yalnız `exercises/source/` | — | — | kapsam dışı | Muay Thai programına girmez (mae geri karate) ya da sonraki spor paketi |

"Tanım bekliyor" satırları yalnız yer ayırır (06 ve 07 bu adlara atıf yapar). Tam tanımları (metrikler, bölgeler, hatalar, `howTo`) bu dosyaya yazılıp hoca onayından geçmeden şablon dosyası oluşturulmaz ve program kalıplarına girmez (14 T8.10).

### Kaynaktan türetilen eskivler (MVP)
Kaynak şablonun metrik adları ve hata kimlikleri **aynı kalır** (kaynak golden ile karşılaştırılabilsin), yalnız tanımlar 2B'ye geçer:
```jsonc
// exercises/slip_left.json (kesit)
{ "id": "slip_left", "version": 2, "status": "draft",
  "derivedFrom": { "id": "slip_left", "version": 1, "commit": "c2fe3fd" },
  "metrics": {
    "head_l_lh": { "lateralLean2d": ["nose", "left_hip"] },
    "head_l_rh": { "lateralLean2d": ["nose", "right_hip"] },
    "torso_l_l": { "lateralLean2d": ["left_shoulder", "left_hip"] }
    /* … diğerleri kaynak şablondaki gibi, lateralLean → lateralLean2d */ },
  "camera": { "minVisibility": 0.5 /* Vision güven ölçeğine göre kalibre edilecek */ } }
```
Eşikler (`rep.start`, `rep.target`, `neck_only` eşiği, `overlay.headTarget`) kalibrasyonla yeniden belirlenir (03). Başlangıç değerleri sentetik `vision19` dizilerinden çıkarılır.

## Yeni şablonlar
Aşağıdaki eşikler sentetik verilerle **başlangıç değerleridir**; hepsi `draft`'tır ve kayıt modunda hocanın etiketli kayıtlarıyla kalibre edilir (03, 09). `howTo` ve `cue` metinleri hoca onayından geçer.

### Lean back (`lean_back`)
Yüksek tekmeye (ve düz yumruğa) karşı gövdeyi arka bacağın üzerine geriye yatırma; çene içeride, gözler önde, eller yukarıda.
- **Teknik modu: yandan.** Tekrar metriği `lean = sagittalLean2d(nose, near_hip)` (artan yön): baş kalçanın arkasına geçtikçe büyür. `start: { enter: 0.05, exit: 0.10 }`, `target: { enter: 0.30, exit: 0.25 }`, `attemptMinExcursion: 0.06`, `minDurationMs: 250`, `maxDurationMs: 2500`.
- **Refleks modu: ayrı şablon `lean_back_front`, önden, yalnız H1.** Şablon formatı tek bir metrik seti taşır; yandan 2B ve önden 3B tanım aynı dosyada olamaz, bu yüzden refleks sürümü ayrı bir şablondur. Tekrar metriği world'den: `lean = avg(sagittalLean(nose, left_hip), sagittalLean(nose, right_hip))` (`nose` 3B'de `centerHead` vekilidir, 03 H1). Bölgelerin başlangıç değerleri teknik sürümle aynıdır; kalibrasyonla ayrı belirlenir. Hatalar: `too_far` (aşağıdaki gibi, güvenlik için) ve `guard_dropped` (slip ile aynı, `guard_l`/`guard_r`; önden görünümde `near_` kullanılmaz). `readyPose`: `guard_l > -0.3 and guard_r > -0.3 and lean < 0.08 for 1000ms`. `overlay.headTarget` yoktur (refleks modunda balon çizilmez, 12). H1 doğrulanmazsa şablon dosyası oluşturulmaz; `lean_back_front` ve `high_kick` katalogda yer almaz (05).
- Hatalar (`lean_back`):
  - `guard_dropped` (minor, `during_rep`, `holdMs: 200`): `guard_near < -0.5` (yandan) — "Ellerin yukarıda kalsın" / "Keep your hands up".
  - `forward_lean_start` (minor, `at_start`): denemeye öne eğilerek başlama, `lean < -0.05` — "Dik başla, ağırlığın arka bacakta" / "Start upright, weight on the back leg".
  - `too_far` (major, `at_turn`): `lean > 0.6` — aşırı geriye yatma, denge kaybı riski — "Çok geriye gitme, dengeni koru" / "Don't lean back too far, stay balanced". `major` olduğu için art arda iki denemede güvenlik duraklatması (ref 05).
- `readyPose` (`lean_back`): `guard_near > -0.3 and lean < 0.08 for 1000ms`.
- `overlay.headTarget` (`lean_back`): yandan görünüm için `back: 0.30` (yeni opsiyonel alan; yalnız çizim, 12).

### Bob & weave (`bob_weave_left`, `bob_weave_right`)
Kroşenin altından eğilip yana geçme: baş aşağı iner, alt noktada yana kayar, karşı tarafta doğrulur. Duck ile slip'in birleşimi. Yön, **başın alt noktada kaydığı taraftır** (kişinin solu/sağı), saldırıya göre değil; saldırı eşlemesi 05'tedir.
- Görünüm: front. `minVisibleLandmarks`: duck ile aynı (baştan ayağa).
- Tekrar metriği: duck'ın `head_height = avg(chainHeight2d(nose, l_shoulder, l_hip, l_knee, l_ankle), chainHeight2d(…sağ…))` (azalan). Bölgeler duck ile aynı başlangıç değerleri.
- Ek metrikler: `head_left` / `head_right` (`slip_left`'teki `lateralLean2d` tanımları).
- Hatalar:
  - `no_weave` (minor, **`affectsValidity: true`**, `at_turn`): alt noktada başın yana kayması yetersiz; `bob_weave_left` için `head_left < 0.15`. Yana kaymayan deneme bob & weave sayılmaz (`faulty`); refleks sınıflandırıcısı onu duck olarak değerlendirir (05). Cue: "Eğilirken yana da geç" / "Weave to the side as you dip".
  - `weave_before_dip` (minor, `at_start`): denemeye yana kayarak başlama (önce slip, sonra eğilme), `head_left > 0.20` — "Önce eğil, sonra yana geç" / "Dip first, then weave".
  - `guard_dropped`: duck ile aynı.
- `readyPose`: duck ile aynı.
- `overlay.headTarget`: `{ "height": <target.enter>, "lateral": 0.15, "sides": ["left"] }`; çizimde balon kesikli çizginin altında, ilgili tarafta (12).

### Check (`check`, v1.0)
Alçak tekmeye karşı kaval kemiğiyle blok: ön (veya arka) diz kalkar ve dışa açılır, kaval kemiği dik ya da hafif dışa eğik, ayak bileği dizin altında kalır.
- Görünüm: front (refleks modunda diğer tepkilerle aynı kadraj).
- Tekrar metriği: `knee_lift = max(diffY(left_knee, left_hip), diffY(right_knee, right_hip))` (artan). `start: { enter: -0.70, exit: -0.60 }`, `target: { enter: -0.20, exit: -0.30 }`.
- Ek metrikler (pozitif = dışa): `knee_out_l = lateralLean2d(left_knee, left_hip)` (sol diz kişinin soluna), `knee_out_r = lateralLean2d(right_hip, right_knee)` (argümanlar ters: sağ diz kişinin sağına gidince pozitif). `shin_l = angleFromVertical(left_knee, left_ankle)`, `shin_r` aynı.
- Hatalar:
  - `knee_not_out` (minor, `at_turn`): `max(knee_out_l, knee_out_r) < 0.10` — kalkmayan bacağın değeri ~0 olduğundan `max` kalkan bacağı seçer. "Dizini dışa aç" / "Turn your knee out".
  - `foot_forward` (minor, `at_turn`): kaval kemiği öne uzamış (teep'e benziyor): `max(shin_l, shin_r) > 45` — "Kaval kemiğin dik kalsın" / "Keep your shin vertical".
  - `guard_dropped`: slip ile aynı.
- Not: Vision'da ayak ucu yoktur; ayak açısı ölçülmez (03).

### Teep sıralama hatası (v1.0)
Bu projenin `teep` şablonuna yeni hata (şablon sürümü artar):
- Ek metrikler: `kick_knee_l = angle2d(left_hip, left_knee, left_ankle)`, `kick_knee_r` aynı; `knee_height_l/r = diffY(left_knee, left_hip)`.
- Hata `extended_before_chamber` (minor, `affectsValidity: false`, `minConsecutiveReps: 1`):
```
"check": "sequence: (kick_knee_l > 150 and kick_height_l > -0.9) or (kick_knee_r > 150 and kick_height_r > -0.9) before max(knee_height_l, knee_height_r) > -0.2"
```
  Okunuşu: bacak, diz kalça hizasına kalkmadan düzleşip yükselmişse. Cue: "Önce dizini kaldır, sonra it" / "Lift your knee first, then push".

### Ters lunge (`reverse_lunge`, MVP)
Arka bacakla geri adım, iki diz ~90°'ye iner, başlangıca dönülür. Kalça, arka bacak ve tek ayak dengesi için.
- Görünüm: side. Tekrar metriği: `knee = min(angle2d(left_hip, left_knee, left_ankle), angle2d(right_hip, right_knee, right_ankle))` (azalan). `start: { enter: 160, exit: 150 }`, `target: { enter: 100, exit: 110 }`, `minDurationMs: 800`, `maxDurationMs: 6000`.
- Hatalar: `insufficient_depth` (`at_turn: knee > 100`, `affectsValidity: true`), `torso_forward` (`at_turn: angleFromVertical(near_hip, near_shoulder) > 30`), `knee_past_toe` **yok** (ayak ucu yok; yerine hoca onayına bağlı bir kural aranır, açık soru).
- Taraf: kullanıcı bacakları sırayla değiştirir; sayım iki bacağı birlikte sayar.

### Jumping jack (`jumping_jack`, MVP)
Isınma ve kondisyon. Kollar yukarı + bacaklar açık, sonra başlangıç.
- Görünüm: front. Tekrar metriği: `arms = min(diffY(left_wrist, nose), diffY(right_wrist, nose))` (artan: bilekler burnun üstüne çıkınca). `start: { enter: -1.0, exit: -0.8 }`, `target: { enter: 0.1, exit: 0.0 }`, `minDurationMs: 300`, `maxDurationMs: 2500`.
- Hata: MVP'de yok; yalnız kollar sayılır. Bacakların açılıp açılmadığını ölçmek için yatay mesafe fonksiyonu (`diffX`) gerekir, kapalı listede yok (açık soru 3).
- `readyPose`: `arms < -0.9 for 800ms` (kollar yanda).

## Kabul kriterleri
- AC-4.1: `exercises/` ve `exercises/source/` altındaki tüm şablonlar Swift doğrulayıcısından geçer (bilinmeyen alan, tanımsız metrik, döngüsel metrik = hata; `solo-calibrate validate`, CI).
- AC-4.2: `exercises/source/` altındaki dosyalar kaynak commit'teki dosyalarla bayt bayt aynıdır (sağlama toplamı listesi, CI); uygulama paketine girmez.
- AC-4.3: Her yeni metrik fonksiyonu için Swift'te birim testi ve anlık görüntü vardır: işaret yönü, aynalama (sol↔sağ), tanımsız geometri → `NaN`.
- AC-4.4: `lateralLean2d` ve `chainHeight2d` ile yazılmış `slip_left`/`duck`'ın **başlangıç sürümü** (`version: 2`, kalibrasyondan önce), kaynak golden dizilerinin `vision19` indirgemesinde kaynak şablonla aynı tekrar ve hata sonucunu verir (eşdeğerlik testi). Bu sürümün dondurulmuş kopyası `fixtures/equivalence/` altında tutulur; kalibrasyonla `exercises/` altındaki sürüm değişince test bu kopyayla çalışmaya devam eder. Kalibre sürümler gerçek kayıtlarla (03 "Kalibrasyon") ve anlık görüntülerle korunur.
- AC-4.5: `bob_weave_left`: yana kaymayan eğilme `faulty` + `no_weave` olur, yana kayan `valid` olur; ters yöne kayan `faulty` (sentetik test).
- AC-4.6: (v1.0) `sequence:` hatası: diz önce kalkarsa tetiklenmez, bacak önce düzleşirse tetiklenir, iki koşul hiç sağlanmazsa tetiklenmez (sentetik test).
- AC-4.7: (v1.0) `lead_`/`rear_`: aynı fixture orthodox'ta ve aynalanmış southpaw'da aynı sonucu verir.
- AC-4.8: `exercises/` altındaki her şablonda `howTo` vardır; eksikse test hatası.

## Açık sorular
1. **Hoca onayı:** lean back, bob & weave ve check'in hata listesi ve cue metinleri; özellikle lean back'te çenenin içeride olması, ağırlığın arka bacakta olması kameradan ölçülebilir mi?
2. Lunge'da "diz ayak ucunu geçmesin" yerine hangi form kuralı kullanılmalı (Vision'da ayak ucu yok)?
3. Jumping jack bacak kontrolü için `diffX` (yatay fark) metrik fonksiyonu eklensin mi?
4. `riseFromBaseline` (durumlu metrik) ip atlama için kabul edilebilir mi, yoksa ip atlama süre bazlı (hold benzeri, "zıplıyor/durdu") mu sayılmalı?
5. Bob & weave tek tekrar mı (alt noktada yana kayıp dön) yoksa U çizip karşı tarafta mı biter? Seçilen tanım tekrar metriğinin merkeze dönüşünü gerektirir; U hareketinde baş merkezden geçmeden karşı tarafta doğrulursa bu şablon yetmez.
