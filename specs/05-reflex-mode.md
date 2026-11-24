# 05 — Teknik, Refleks ve Raunt Modu

Saf Swift, `SoloEngine/Reflex` ve `SoloEngine/Session`. Kamera, ses ve UI bilmez: girdi zaman damgalı motor olayları ve kare verisidir, çıktı komutlardır (`PLAY_CUE(at:)`, `SPEAK`, `SHOW`, `PERSIST`, `HAPTIC`). Zaman yalnız kare zamanı ve `TICK` ile ilerler; rastgelelik enjekte edilen tohumlu üreteçten gelir (testler deterministik).

## Modlar
| Mod | Amaç | Ne ölçülür | Sürüm |
|---|---|---|---|
| Teknik | Tek eskivi doğru öğrenmek | Tekrar, form hataları (ref 04/05) | **MVP** |
| Refleks | Saldırıya doğru eskivle, hızlı tepki | Tepki türü, doğruluk, tepki süresi, form hataları | **MVP** |
| Raunt | Gerçek hızda, raunt boyunca dayanıklılık | Refleks ölçümleri + gard yüzdesi, aktivite, hareketsizlik | v1.0 |

## Teknik modu
ref 03'teki set akışıyla aynıdır; tek fark seansın bu projenin seans motorunda yürümesidir (06 "Seans motoru").
- Blok: bir şablon, set sayısı, tekrar hedefi, dinlenme, `strict`/`lenient` (öntanımlı `lenient`: öğrenme modunda hatalı tekrar sayılır ama uyarılır).
- Form uyarıları ref 05 zamanlama kurallarına uyar (bekleme süresi, art arda deneme, öncelik, güvenlik duraklatması).
- Yavaş tempo: teknik modunda bir eskivin `minDurationMs`'i şablondaki değerin 2 katına çıkarılır (`techniqueTempo: slow`); çok hızlı yapılan tekrar `incomplete` olur ve "Daha yavaş, kontrollü" (`technique.slow_down`) söylenir. Tempo yalnız kullanıcı ayarıdır (`Profile.techniqueTempo`, öntanımlı `slow`, 11); blok tanımı tempo belirlemez (06). Refleks ve raunt modunda tempo çarpanı uygulanmaz, şablondaki `minDurationMs` geçerlidir.
- Hedef dairesi, yönlendirme okları ve balonlar ref 08 A5 ile aynıdır (12).

## Refleks modu
### Deneme döngüsü
Bir refleks seti N işaretten oluşur (öntanımlı 20, seviye tablosunda). Her işaret bir **deneme**dir.
```
HAZIRLIK → BEKLEME (rastgele ön süre) → İŞARET (t_cue) → PENCERE → SONUÇ → (sonraki deneme | SET_SONU)
```
1. **Hazırlık:** tüm aday tepki motorları `AT_START` durumunda ve gard duruşu (`reflex.readyPose`, aşağıda) tutuluyor. 5 sn sağlanmazsa "Gard al, ortaya gel" (`reflex.get_ready`) söylenir, 10 sn'de bir tekrarlanır.
2. **Bekleme (ön süre):** seviyenin `[foreMin, foreMax]` aralığından **düzgün dağılımlı** rastgele süre. Sabit ritim tahmini mümkün kılar; rastgelelik bunu engeller. Bekleme sırasında hareket başlarsa (herhangi bir motor `REP_STARTED`) bekleme sıfırlanır ve "Bekle, işareti dinle" (`reflex.wait_for_cue`, 15 sn bekleme süreli) söylenir.
3. **İşaret:** `PLAY_CUE` komutu verilir (`t_plan`) ve ses ileri bir host zamanına planlanır (≥ 80 ms ileri, ses yolunun hazır olması için); `t_cue` = planlanan zaman + çıkış gecikmesi (aşağıda "İşaret anı"). Planlandıktan sonra işaret geri alınmaz (güvenlik duraklatması hariç, "Geri bildirim").
4. **Pencere:** `[t_plan, t_cue + window]` içinde başlayan denemeler bu işarete aittir; `t_cue`'dan önce başlayanlar 3. sınıflandırma adımında `early` olur.
5. **Sonuç:** pencere kapanıp aday denemeler tamamlanınca (ya da `window + maxDurationMs` dolunca) sınıflandırılır (aşağıda).
6. Sonraki deneme kombinasyondaysa `comboGap` sonra, değilse yeniden Hazırlık'tan başlar.

### İşaret kataloğu ve eşleme (veri)
Saldırılar, kabul edilen tepkiler ve seviyeler **veridir** (JSON), kod değildir: `exercises/reflex/muay_thai.json`. Şema `SoloEngine` içinde tanımlanır (bu projeye özgüdür, kaynak formatta karşılığı yoktur), yüklemede doğrulanır, `status: "draft" | "approved"` taşır. **Eşleme hoca onayından geçmeden `approved` olmaz.**

Eşleme, rakibin kullanıcıyla **aynı gard yönünde** (ayna sparring) olduğunu varsayar. `orthodox` için yazılır; `southpaw` için sol↔sağ aynalanarak türetilir (`slip_left` ↔ `slip_right`, `bob_weave_left` ↔ `bob_weave_right`; `duck`, `lean_back_front` değişmez). Konuşulan saldırı adı da gard yönüne göre çözülür (orthodox rakibin ön kolu soldur).

**MVP taslak kataloğu (orthodox kullanıcı, orthodox rakip):**
| Saldırı | TR işaret | EN işaret | Kabul edilen tepkiler | Tercih edilen | Not |
|---|---|---|---|---|---|
| `jab` | "Jab!" | "Jab!" | `slip_right`, `slip_left` | `slip_right` (dış eskiv) | Rakibin sol eli sağ tarafımdan gelir; dışına kaçış sağa |
| `cross` | "Düz!" | "Cross!" | `slip_left`, `slip_right` | `slip_left` (dış eskiv) | |
| `lead_hook` | "Sol kroşe!" | "Left hook!" | `bob_weave_left`, `duck` | `bob_weave_left` | Kroşe sağımdan gelir; altından sola geçiş |
| `rear_hook` | "Sağ kroşe!" | "Right hook!" | `bob_weave_right`, `duck` | `bob_weave_right` | |
| `high_kick` | "Yüksek tekme!" | "High kick!" | `lean_back_front` | `lean_back_front` | **Yalnız 03 H1 doğrulanırsa** (önden lean back, 04); değilse işaret de şablon da katalogda yer almaz |
| `stop` (aldatma) | "Dur!" | "Hold!" | — (tepki verilmemeli) | — | Aşağıda "Aldatma" |

v1.0 eklemeleri: `low_kick` → `check` (ön bacak), `body_kick` → (hoca kararı), `uppercut` → (hoca kararı).

```jsonc
// exercises/reflex/muay_thai.json (kesit)
{
  "id": "muay_thai", "version": 1, "status": "draft",
  "assumes": { "opponentStance": "same" },
  "responses": ["slip_left", "slip_right", "duck", "bob_weave_left", "bob_weave_right"],  // H1 doğrulanırsa + "lean_back_front" (ve high_kick saldırısı)
  "specificity": [["bob_weave_left", "duck"], ["bob_weave_left", "slip_left"], ["bob_weave_right", "duck"], ["bob_weave_right", "slip_right"]],
  "strikes": [
    { "id": "jab", "say": { "orthodox": "strike.jab", "southpaw": "strike.jab" },
      "accept": ["slip_right", "slip_left"], "prefer": "slip_right" },
    { "id": "lead_hook", "say": { "orthodox": "strike.left_hook", "southpaw": "strike.right_hook" },
      "accept": ["bob_weave_left", "duck"], "prefer": "bob_weave_left" }
  ],
  "feints": [ { "id": "stop", "say": "strike.stop" } ],
  "levels": [ /* aşağıdaki tablo */ ]
}
```
`accept`/`prefer` her zaman orthodox için yazılır; southpaw aynalaması motor tarafından yapılır (test edilir).

**Seviye kaydı ve doğrulama (T4.1, 2026-11-24):**
- Seviye kaydının biçimi: `{ "level": 1, "strikes": ["jab", "cross"], "foreSec": [2.0, 4.0], "windowMs": 1500, "comboLen": [1, 1], "comboGapMs": 900, "feintRate": 0, "cues": 15 }`. `comboGapMs`, `comboLen` üst sınırı 1'den büyükse zorunludur, değilse yazılmaz.
- Yükleyici katıdır, bilinmeyen alan hatadır. Ayrıca şunları denetler:
  - `id` tanımlayıcıdır, `version` ≥ 1, `status` `draft` ya da `approved`, `assumes.opponentStance` `same`.
  - `responses` boş olmayan ve tekrarsızdır.
  - `specificity` iki farklı `responses` öğesinden oluşan çiftlerdir.
  - Saldırı kimlikleri tekrarsızdır ve aldatma kimlikleriyle çakışmaz. `say.orthodox` ve `say.southpaw` boş olmaz. `accept` boş olmaz ve `responses`'un alt kümesidir; `prefer` `accept` içindedir.
  - Seviyeler 1'den başlar ve ardışıktır. Bir seviyenin `strikes` listesi boş olmaz, tekrarsızdır ve tanımlı saldırılardan oluşur.
  - Sayılar: `0 < foreSec[0] ≤ foreSec[1]`, `windowMs > 0`, `1 ≤ comboLen[0] ≤ comboLen[1]`, `0 ≤ feintRate < 1` (`feintRate > 0` ise en az bir aldatma tanımlı olmalı), `cues ≥ 1`.
- Şablonlara bağlı denetimler `solo-calibrate validate` içindedir (AC-5.6):
  - `responses`'taki her şablon `exercises/` altında bulunur ve `front` görünümü destekler.
  - `comboGapMs`, o seviyedeki saldırıların `accept` şablonlarının en büyük `minDurationMs` değerinden kısa olamaz.
  - Hazır antrenmanlardaki `catalogId` `exercises/reflex/` altında bir katalog olmalıdır (06).
- **Southpaw aynalaması:** `accept`, `prefer` ve `specificity` içindeki şablon kimliklerinde `_left` ile `_right` yer değiştirir (`slip_left` ↔ `slip_right`, `bob_weave_left` ↔ `bob_weave_right`). `duck` ve `lean_back_front` değişmez. Konuşulan anahtar `say.<gard>`'dan seçilir.

### Tepki motorları
- Refleks seti başlarken katalogdaki `responses` listesindeki her şablon için bir `ExerciseEngine` örneği açılır (hepsi `front`). Kurulum (12 S1) bu şablonların `minVisibleLandmarks` birleşimini ister: baştan ayağa.
- Motorların form uyarıları kapalıdır (`cuesEnabled = false`); tespit edilen hatalar `REP_COMPLETED.faults` içinde toplanır, refleks katmanı kendi kuralıyla seslendirir (aşağıda "Geri bildirim").
- `reflex.readyPose`: tüm aday şablonların `readyPose` ifadelerinin **ve**'si; en uzun `for` süresi kullanılır.
- Güvenlik duraklatması (ref 05) refleks modunda da geçerlidir: herhangi bir motor `SAFETY_PAUSE` üretirse set durur.

### Sınıflandırma
Bir denemenin penceresi kapanınca:
1. **Adaylar:** pencere içinde **başlayan** (`REP_STARTED`) ve tamamlanan tüm denemeler, tüm motorlardan.
2. Hiç aday yoksa → `missed`.
3. En erken başlayan adayın `t_move < t_cue` ya da `t_move − t_cue < minHumanRtMs` (öntanımlı 120 ms) ise → `early` (tahmin). Bekleme sırasında başlamış hareket zaten 2. adımda engellendiği için bu, işaretle neredeyse aynı anda başlayan hareketlerdir.
4. **Seçim:** `valid` sonuçlu adaylar arasından **en özel** olan (katalogdaki `specificity` sırası: `[A, B]` "A, B'den özeldir"); eşitlikte dönüş noktasında hedefi en çok aşan (normalize: `(dönüş − start.exit) / (target.enter − start.exit)`). `valid` aday yoksa aynı kural `faulty` adaylara uygulanır. Yalnız `incomplete` aday varsa → `partial` (yarım eskiv).
5. Seçilen tepki `accept` içindeyse: hatası yoksa `correct`, en az bir hatası varsa `correct_faulty`; değilse `wrong`.
6. `prefer` dışında kabul edilen tepki `correct` sayılır ama istatistikte ayrı tutulur ("dış eskiv oranı").
7. **Aldatma** denemesinde: aday yoksa `feint_ok`, varsa `feint_bitten`.

Örnek: kullanıcı "sol kroşe"ye eğilip yana kaymadan doğrulursa `bob_weave_left` `faulty` (`no_weave`) olur, `duck` `valid` olur → seçim `duck` → kabul edilen tepki → `correct`, istatistikte "tercih edilmeyen tepki".

### Uygulama ayrıntıları (T4.2, 2026-11-24)
- **Bekleme sırasında hareket:** bekleme sırasında bir motor `REP_STARTED` üretirse döngü Hazırlık'a döner. Ön süre, kullanıcı yeniden hazır olunca baştan çekilir.
- **Hazır olma:** tüm motorlar `AT_START` durumundadır ve her motorun `readyPose`'u tutuluyordur. Hepsinin birlikte tutulduğu süre, en uzun `for` süresine ulaşmalıdır.
- **Kombinasyon ve aldatma:** her kombinasyon için önce uzunluk seçilir. Sonra `feintRate` olasılıkla kombinasyonun son işareti aldatma olur (uzunluk 1 ise tek başına aldatma). Saldırılar seviyenin listesinden, ardışık tekrarsız seçilir. Aldatma da bir işarettir ve setin işaret sayısına girer. Kombinasyon setin kalan işaret sayısını aşmaz.
- **Atama:** bir motorun denemesi, başlangıcını (`t_move`) içeren ve o motordan henüz deneme almamış en erken açık pencereye atanır. Böylece bir pencerede motor başına en fazla bir aday olur ve bir deneme yalnız bir pencereye girer.
- **Sonuçlanma:** bir pencere, `t_cue + window` geçtikten sonra şu iki koşuldan biri sağlanınca sonuçlanır: atanmış tüm denemeler tamamlanmıştır, ya da yanıt şablonlarının en büyük `maxDurationMs`'i kadar daha süre geçmiştir. Tamamlanmayan deneme aday değildir.
- **Kayıt:** `cueAtMs`, `t_cue`'dur. `reactionMs` yalnız `correct`, `correct_faulty`, `wrong` ve `partial` denemelerde, seçilen adayın `t_move − t_cue`'su olarak yazılır.
- **Rastgelelik:** tohumlu SplitMix64 üreteci kullanılır.

### Tepki süresi
**İşaret anı (`t_cue`):** `PLAY_CUE(at: hostTime)` komutu sesi planlar. `t_cue = hostTime + outputLatency + ioBufferDuration` (AVAudioSession değerleri, işaret anında okunur) + `cueOnsetMs` (ses dosyasının başındaki sessizlik; her dosya için üretimde ölçülür ve dosya adının yanındaki meta veride tutulur). TTS yedeğinde (`AVSpeechSynthesizer`) çıkış anı bilinemediği için deneme `rtApproximate = true` işaretlenir.

**Tepki anı (`t_move`):** ref 04'teki deneme kesinleşme anı (`REP_STARTED`: metrik `start.exit`'ten `attemptMinExcursion` kadar uzaklaşır). İki düzeltme:
1. **Yumuşatma gecikmesi:** motor yumuşatılmış metrikle karar verir; One Euro filtresi gecikme ekler. Swift motoru her karenin **ham** metrik değerini de tutar (en az şablonun `maxDurationMs` süresi kadar geriye; yan değişiminde temizlenir). Kesinleşme anından geriye doğru, ham metriğin kesinleşme eşiğini **son** kez geçtiği iki kare bulunur ve zaman doğrusal interpolasyonla hesaplanır. Ham geçiş, deneme başlangıcından önceye düşemez.
2. **Kare zamanı:** kare zamanı, karenin sunum zaman damgasıdır (02 "Saat tabanı"), işlendiği an değil.

`RT = t_move − t_cue`. `missed`, `early`, `feint_*` denemeleri RT istatistiğine girmez. `rtApproximate` denemeler istatistikte ayrı gösterilir.

**Bluetooth:** ses çıkışı Bluetooth ise `outputLatency`'nin güvenilirliği spike'ta ölçülür (02). Güvenilmezse set başında "Bluetooth kulaklıkta tepki süresi yaklaşıktır" gösterilir ve tüm denemeler `rtApproximate`.

### Kombinasyonlar
- Kombinasyon = seviyenin `comboLen` aralığından rastgele uzunlukta, katalogdan rastgele (tekrarsız ardışık) saldırı dizisi; işaretler arası `comboGap`.
- Her işaretin penceresi ayrı açılır; bir deneme, başlangıç anını içeren **en erken açık** pencereye atanır; bir pencereye en fazla bir deneme atanır (ilk seçilen).
- Önceki eskivin dönüşü bitmeden sonraki işaret gelebilir; bir sonraki eskiv deneme olarak ancak baş başlangıç bölgesine dönünce başlayabilir (ref 04 histerezisi). Bu, gerçek hayattaki "ortaya dön" zorunluluğudur ve bilinçli olarak korunur. Her seviyede `comboGap`, o seviyedeki saldırıların `accept` kümelerindeki şablonların **en büyük** `minDurationMs` değerinden kısa olamaz: bir tepkinin tamamlanabileceği en kısa süredir (doğrulayıcı; refleks modunda tempo çarpanı olmadığı için şablondaki değer kullanılır).

### Aldatma
- **MVP:** `stop` işareti ("Dur!"): tepki **verilmemelidir**. Tek başına ya da kombinasyonun içinde (ör. "Jab! … Dur!") gelir. Seviyenin `feintRate`'i kadar denemede.
- Pencere süresi boyunca hiçbir motor deneme başlatmazsa `feint_ok`.
- v1.0 adayı: hocanın tarif edeceği ikinci tür (ör. vücut aldatması, ses tonu farkı); açık soru.

### Seviyeler (taslak)
| Seviye | Saldırılar | Ön süre (sn) | Pencere (ms) | Kombinasyon | Ara (ms) | Aldatma | İşaret/set | Erişim (v1.0) |
|---|---|---|---|---|---|---|---|---|
| 1 | jab, cross | 2,0–4,0 | 1500 | 1 | — | %0 | 15 | Ücretsiz |
| 2 | + lead_hook, rear_hook | 1,5–3,5 | 1200 | 1 | — | %0 | 20 | Ücretsiz |
| 3 | hepsi | 1,2–3,0 | 1000 | 1–2 | 900 | %0 | 20 | Premium |
| 4 | hepsi | 1,0–2,5 | 850 | 1–3 | 700 | %10 | 24 | Premium |
| 5 | hepsi | 0,8–2,0 | 700 | 2–4 | 550 | %15 | 24 | Premium |
| 6 | hepsi + `high_kick` (varsa) | 0,6–1,8 | 600 | 2–4 | 450 | %20 | 30 | Premium |
- MVP (TestFlight) tüm seviyeler açıktır (11).
- **Seviye önerisi** (otomatik değil): son 2 sette isabet (`correct` + `correct_faulty` + `feint_ok`) / toplam ≥ %85 ve medyan RT ≤ pencerenin %60'ı ise "Bir üst seviyeyi dene" önerilir. İsabet < %50 ise bir alt seviye önerilir.

### Geri bildirim
- **Öncelik:** güvenlik duraklatması > işaret sesi > form uyarısı > sonuç sesi. Güvenlik duraklatması planlanmış ya da çalmakta olan işaret sesini iptal eder (oynatıcı durdurulur, deneme kaydedilmez) ve set durur; böylece işaretle üst üste binmez.
- Güvenlik duraklatması dışında işaret seslerinin önüne hiçbir şey geçmez: işaretin planlandığı andan 600 ms önce başlayacak bir konuşma ertelenir ya da atılır.
- **Sonuç sesi:** her denemede kısa, konuşmasız ton (doğru: yüksek kısa "tık"; yanlış/kaçırıldı: alçak "tok"; aldatma ısırıldı: çift "tok"). Sonuç tonları ve form uyarısı sesi ayarlardan kapatılabilir; işaret sesi kapatılamaz, çünkü refleks modunun asıl kanalıdır ve RT ona göre ölçülür (11, 12 A). Ekranda sonuç ikonu + RT (ms).
- **Form uyarısı:** refleks modunda deneme başına en fazla bir, yalnız `correct_faulty` denemelerinde, ref 05 bekleme süresiyle; bir sonraki işaret planlanmışsa ve konuşma bitmeyecekse atılır.
- **Yanlış yön:** art arda 2 `wrong` aynı saldırıda ise bir kez "Jab'a dışa kaç: sağa" (`reflex.hint.<strike>`, gard yönüne göre çözülür) söylenir; set başına saldırı başına en fazla bir kez.
- **Uygulama (T4.3, 2026-11-24):**
  - Konuşma, planlanmış bir işaret sesinin 600 ms öncesinden sesin bitişine kadar olan aralıkla çakışmaz. Yeni işaret de süren bir konuşma bitmeden ve 600 ms geçmeden planlanmaz.
  - Sığmayan form uyarısı ile "Gard al" / "Bekle" atılır; yön ipucu ertelenir ve sığdığı ilk anda söylenir.
  - Süreler için tahmin kullanılır: işaret sesi ~600 ms, konuşma anahtar başına verilen süre.
  - Form uyarısının bekleme süresi şablondaki `cooldownMs`'tir.
  - "Art arda 2 `wrong`" o saldırının kendi denemeleri içindedir, çünkü saldırılar ardışık tekrar etmez.
  - Yön ipucu anahtarı `reflex.hint.<saldırı>.<gard>`'dır.
  - Sonuç tonları: `correct` / `correct_faulty` / `feint_ok` → doğru; `feint_bitten` → çift ton; diğerleri → yanlış.
  - Özetin söylediği tepki süresi ortalamadır; ekrandaki istatistik medyan ve p90'dır. "En zor" saldırı, isabeti en düşük olan saldırıdır (eşitlikte medyan RT'si daha yavaş olan); adı `strike.name.<anahtar>` ile söylenir.
- Set sonu özeti (≤ 8 sn, sesli kısa): "20 işaret, 17 doğru, ortalama tepki 410 milisaniye. En zor: sağ kroşe."

### Set özeti ve kayıt
Kaydedilen (11): her deneme için saldırı, aldatma mı, `t_cue`, sonuç, seçilen tepki, RT, `rtApproximate`, form hataları, kombinasyon kimliği/sırası. Özet: isabet oranı, medyan ve p90 RT, saldırı bazında isabet ve medyan RT, tercih edilen tepki oranı, aldatma başarısı, en sık form hatası.

### Doğrulama (cihazda)
Tepki süresi ölçümünün doğruluğu bir kez yöntemle, sonra her ana sürümde tekrar ölçülür:
1. İkinci bir iPhone, ağır çekim (240 FPS, sesli) ile kullanıcıyı ve uygulamayı çalıştıran telefonun hoparlörünü aynı anda kaydeder.
2. Ağır çekim videoda işaret sesinin başlangıcı (ses dalgası) ve hareketin başlangıcı (başın başlangıç bölgesinden çıkışı, kayıt modu tanımıyla aynı eşik) elle işaretlenir.
3. Uygulamanın ölçtüğü RT ile karşılaştırılır. Hedef: hata medyanı ≤ 50 ms, p95 ≤ 100 ms (00). En az 50 deneme, hoparlör ve (varsa) Bluetooth ayrı.

## Raunt modu (v1.0)
Refleks modunun raunt formatında oynanması.
- **Yapı:** raunt sayısı (1–5, öntanımlı 3), raunt süresi (1–3 dk, öntanımlı 3), dinlenme (30–120 sn, öntanımlı 60). Raunt başı/sonu zil sesi, son 10 sn'de "Son on saniye" uyarısı.
- **İşaretler:** seçilen seviyenin parametreleriyle, raunt boyunca kesintisiz; deneme döngüsündeki "Hazırlık" beklemesi yerine kullanıcı gard duruşundaysa ön süre başlar (raunt akmaya devam eder).
- **Ek ölçümler:**
  - **Gard yüzdesi:** raunt boyunca, takip edilen karelerde iki elin de gard eşiğinin üstünde olduğu karelerin oranı (`guard_l > -0.3 and guard_r > -0.3`, eskiv şablonlarıyla aynı tanım).
  - **Aktivite:** birimsiz gösterge. Her saniye: burun, iki bilek ve iki ayak bileğinin görüntüdeki hızlarının toplamı / gövde boyu, 3 sn'lik yürüyen ortalama. Kullanıcının kendi son 5 raunt ortalamasına göre "düşük / orta / yüksek" olarak gösterilir. **Kuvvet, hız ya da kalori olarak sunulmaz** (00 kapsam dışı).
  - **Hareketsizlik:** aktivite 4 sn boyunca kullanıcının ortalamasının %20'sinin altındaysa "Hareket et!" (`round.keep_moving`, 15 sn bekleme süresi).
- **Özet:** raunt başına isabet, medyan RT, gard yüzdesi, aktivite eğrisi; raundlar arası düşüş (yorgunluk göstergesi) "3. raunt isabeti 1. raunda göre %12 düşük" biçiminde.

## Kabul kriterleri
- AC-5.1: Deneme döngüsü sahte saat ve tohumlu rastgeleyle deterministiktir; aynı tohum aynı işaret sırasını ve aynı sonuçları üretir.
- AC-5.2: Sınıflandırma tablosu birim testle kapsanır: `correct`, `correct_faulty`, `wrong`, `missed`, `early`, `partial`, `feint_ok`, `feint_bitten`; bob & weave / duck / slip özgüllük örnekleri dahil.
- AC-5.3: Southpaw aynalaması: orthodox katalogdan türetilen kabul kümeleri ve konuşulan adlar beklenen tabloyla aynıdır; aynalanmış sentetik dizi aynalanmış sonuç verir.
- AC-5.4: RT, sentetik dizide (bilinen hareket başlangıcı, bilinen `t_cue`) ±1 kare (33 ms) içinde ölçülür; yumuşatma düzeltmesi kapalıyken ölçülen gecikme düzeltmenin ölçtüğü kadar büyüktür (test).
- AC-5.5: Bekleme sırasında başlayan hareket işareti erteler; işaret planlandıktan sonra `t_cue`'dan önce ya da `minHumanRtMs` altında başlayan tepki `early` olur ve RT istatistiğine girmez.
- AC-5.6: Kombinasyonda bir deneme yalnız bir pencereye atanır; `comboGap` ilgili şablonların en büyük `minDurationMs` değerinden kısaysa katalog doğrulamada reddedilir.
- AC-5.7: Hiçbir konuşma, planlanmış işaret sesiyle üst üste binmez; güvenlik duraklatması planlanmış işareti iptal eder (sahte ses çıkışıyla zaman çizelgesi testi).
- AC-5.8: `status: "draft"` katalog TestFlight'ta "taslak eşleme" ibaresiyle gösterilir; Release derlemesi yalnız `approved` katalogla çalışır.
- AC-5.9: Cihazda RT doğrulaması (yukarıdaki yöntem) hoparlörde hedefleri sağlar; sonuç 02 spike tablosunun yanına yazılır.
- AC-5.10: (v1.0) Raunt zamanlayıcısı, dinlenme ve son 10 sn uyarısı sahte saatle test edilir; gard yüzdesi sentetik dizide beklenen orana ±%2 içinde eşittir.

## Açık sorular
1. **Hoca onayı (en önemli):** saldırı → tepki eşlemesi; içe eskiv (jab'a sola) doğru mu sayılmalı yoksa "kabul edilir ama tercih edilmez" mi? Kroşeye duck kabul mü?
2. Rakip gard yönü: hep "aynı gard" (ayna) mı, yoksa kullanıcı "rakip southpaw" seçebilmeli mi (orthodox vs southpaw eşlemesi farklı)?
3. TR işaret dili: "Düz!" mü "Cross!" mu, "Kroşe" mi "Hook" mu? Salonda kullanılan dil seçilmeli.
4. İşaret sesleri hocanın sesiyle mi kaydedilecek? (Ses dosyası + `cueOnsetMs` ölçümü üretim adımı.)
5. İkinci aldatma türü (yön değişimi, vücut aldatması) sesle nasıl temsil edilir?
6. Görsel işaret seçeneği (ekran parlaması) işitme engelli kullanıcılar ve gürültülü ortam için v1.0'a alınmalı mı? Ekran gecikmesi ayrıca ölçülmeli.
7. Seviye tablosundaki pencere süreleri sezgiseldir; pilotta öğrencilerin medyan RT dağılımına göre ayarlanmalı.
