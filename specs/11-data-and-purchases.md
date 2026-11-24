# 11 — Yerel Veri Modeli ve Satın Alma

## Bölüm 1 — Yerel veri modeli (MVP)
SwiftData, tek yerel depo. Sunucu ve hesap yok (10). Kimlikler UUID, zamanlar UTC (`Date`), süreler ms tamsayı. Motor kayıtları yalnız kesinleşince yazılır ve sonra değişmez (ref 06 ilkesi).

```
Profile            (tekil)
  id, createdAt, language[tr|en|system], stance[orthodox|southpaw],
  level[beginner|intermediate|advanced], goal[defense|conditioning|balanced],
  weightKg? (yalnız elle girilen; HealthKit kilosu saklanmaz, 08), heightCm?,
  adultConfirmedAt, disclaimerShownVersion, healthScreeningShownAt?,
  camera[front|back], faultCueVoice bool, resultTones bool, techniqueTempo[slow|normal],   // işaret sesi ayar değildir (05)
  reflexLevel Int, sportPack String

Session
  id, workoutId, workoutVersion?, sport, startedAt, endedAt?, status[active|paused|done|aborted],
  warmupSkipped bool, activeMs, energyKcal?, energyMethod[met|heart_rate]?,
  healthKitWorkoutUUID?, stance, appVersion, degradations [no3d|fps24]   // boş = kademeli çalışma yok (02)

SessionBlock
  id, session → Session, position, kind[warmup|technique|reflex|conditioning|round|guided],
  exerciseId?, exerciseVersion?, catalogId?, catalogVersion?, level?, status[done|skipped|partial]

SetRecord
  id, block → SessionBlock, setIndex, startedAt, endedAt,
  plannedReps?, validReps, faultyReps, incompleteReps, view[front|side|ambiguous], belowTarget bool

Attempt                               // teknik/kondisyon tekrarı
  id, set → SetRecord, index, outcome[valid|faulty|incomplete], durationMs, faults [String]

ReflexTrial                           // refleks/raunt denemesi
  id, set → SetRecord, index, comboId?, comboIndex?, strikeId, isFeint bool,
  cueAtMs (seans başına göre), result[correct|correct_faulty|wrong|partial|missed|early|feint_ok|feint_bitten],
  responseExerciseId?, preferred bool?, reactionMs?, rtApproximate bool, faults [String]

RoundSummary (v1.0)
  id, set → SetRecord, roundIndex, guardPct, activityLevel[low|mid|high], accuracy, medianRtMs?

PostureAssessment (v1.0)
  id, takenAt, measures {code: value|null}, bands {code: band}, flags [String], quality

WeekPlan (v1.0)
  id, weekStart, seed, inputsHash, days [PlanDay(JSON)]

EntitlementCache (v1.0)
  productId, expiresAt?, verifiedAt        // yalnız çevrimdışı açılış için önbellek; doğruluk kaynağı StoreKit
```
- `workoutVersion` isteğe bağlıdır: hazır antrenman dosyaları (06) henüz sürüm taşımaz. Hareketin sürümü blokta (`exerciseVersion`) tutulur.
- **Yazım (T3.4):** motor kayıtları kesinleşince yazılır. Seans satırı başlangıçta `active` olarak açılır ve sonunda son durumunu alır. Tekrarlar setleri yazılınca, setler blokları yazılınca depoya girer. Aynı kimlikle ikinci kez gelen motor kaydı yok sayılır. Bunu uygulamadaki `SessionRecorder` yapar; motor kayıtlarının özellikleri dışarıdan yazılamaz (AC-11.2). Depo dosyası `NSFileProtectionCompleteUntilFirstUserAuthentication` ile korunur (10). v1.0 varlıkları kendi şema sürümleriyle gelir.
- **Kayıt modu** verisi bu depoda değildir; dosya paketleri olarak ayrı tutulur (09).
- **Türetilmiş istatistikler** (haftalık toplam, saldırı bazında medyan RT, en sık hata) saklanmaz, sorguyla hesaplanır. Performans gerekirse önbellek eklenir, doğruluk kaynağı ham kayıtlardır.
- **Göç:** SwiftData şema sürümleri (`VersionedSchema`) ve göç planı ilk sürümden itibaren tanımlanır; her şema değişikliği göç testi ister.
- **Dışa aktarma şeması** (10): yukarıdaki varlıkların JSON karşılığı, `exportVersion: 1`, katı.

## Bölüm 2 — Ücretsiz ve premium (v1.0)
MVP (TestFlight) **ücretsizdir ve her şey açıktır**; satın alma kodu Beta'da sahte StoreKit yapılandırmasıyla test edilir ama kilit uygulanmaz.

| Özellik | Ücretsiz | Premium |
|---|---|---|
| Teknik modu: `slip`, `slip_left`, `slip_right`, `duck`, `bob_weave_*` | ✓ | ✓ |
| Teknik modu: `lean_back`, `check` | — | ✓ |
| Refleks seviye 1–2 | ✓ | ✓ |
| Refleks seviye 3–6, aldatma | — | ✓ |
| Raunt modu | — | ✓ |
| Hazır antrenmanlar: "Eskiv temeli", "Kondisyon" | ✓ | ✓ |
| Tüm hazır antrenmanlar, haftalık program | — | ✓ |
| Postür ölçümü ve sonucu | ✓ | ✓ |
| Postürün programa etkisi | — | ✓ |
| HealthKit, kalori tahmini, geçmiş, dışa aktarma | ✓ | ✓ |
| Yeni spor paketleri (kickboks, boks) | — | ✓ |
- `bob_weave_*` ücretsizdir: ücretsiz refleks seviye 2'deki kroşelerin tercih edilen tepkisidir ve ücretsiz "Eskiv temeli" antrenmanında yer alır; ücretsiz kullanıcı refleksin istediği tepkiyi teknik modunda çalışabilmelidir.
- İlke: ücretsiz sürüm **kendi başına işe yarar** (temel eskiv + refleksin başı + temel kondisyon); premium derinlik ve çeşitlilik satar. Güvenlik özellikleri (kurulum, ısınma, güvenlik duraklatması) asla premiuma bağlanmaz.
- Kilit uygulama: kilitli içerik listede görünür, kilit ikonuyla; dokununca satın alma ekranı. Bir antrenmanın ortasında kilit çıkmaz (antrenman başlamadan kontrol edilir).

## Bölüm 3 — Ürünler ve StoreKit 2 (v1.0)
| Ürün kimliği (taslak) | Tür | Not |
|---|---|---|
| `solo.premium.yearly` | Otomatik yenilenen abonelik (grup `solo.premium`) | Tanıtım teklifi: 7 gün ücretsiz deneme (yalnız ilk kez) |
| `solo.premium.lifetime` | Tüketilmeyen (non-consumable) | Tek seferlik |
- Haftalık ve aylık abonelik **yok** (ürün kararı).
- **Yetki:** `Transaction.currentEntitlements` içinde doğrulanmış (`VerificationResult.verified`) yıllık abonelik ya da ömür boyu varsa premium. Doğrulama tamamen cihazda (StoreKit 2 JWS). Uygulama açılışında ve `Transaction.updates` dinlenerek güncellenir.
- **Çevrimdışı:** son doğrulanmış yetki `EntitlementCache`'te tutulur; abonelik bitiş tarihine kadar çevrimdışı premium çalışır. Ömür boyu süresizdir.
- **Geri yükleme:** Ayarlar'da "Satın alımları geri yükle" (`AppStore.sync()`).
- **İade ve iptal:** `revocationDate` dolu işlem yetki vermez.
- **Aile Paylaşımı:** ömür boyu ve abonelik için açık (öneri; açık soru).
- **Spor paketleri:** premium ve ömür boyu sahipleri için dahil (öneri; açık soru: ömür boyu satın alan kişinin gelecekteki tüm paketleri alması gelir açısından riskli olabilir).

## Satın alma ekranı kuralları
- Fiyat, süre, yenileme koşulu ve deneme bitiş tarihi açıkça yazılır (App Store 3.1.2); "Kullanım koşulları" ve "Gizlilik politikası" bağlantıları ekranda.
- Kapatma düğmesi her zaman görünür; ilk açılışta zorla gösterilmez. Gösterildiği yerler: kilitli içeriğe dokununca, Ayarlar'da, seviye 2'yi 3 kez bitirdikten sonra bir kez ("Seviye 3'ü denemek ister misin?").
- Karanlık örüntü yok: sahte geri sayım, gizli kapatma, ön seçili pahalı seçenek yok.

## Fiyat (taslak, açık soru)
| Pazar | Yıllık | Ömür boyu |
|---|---|---|
| ABD (referans) | 29,99 USD | 69,99 USD |
| Türkiye | App Store Connect'in bölge fiyatı yerine elle, yerel alım gücüne göre | aynı |
- Hedef "aylık birkaç yüz dolar" (00): 29,99 USD yıllıkta Apple payı (Küçük İşletme Programı'nda %15) sonrası ~25 USD (vergiler düşülmeden); ayda 300 USD için yılda ~140 yıllık abonelik eşdeğeri gerekir.

## Kabul kriterleri
- AC-11.1: SwiftData şeması sürümlüdür; her şema değişikliği için göç testi vardır.
- AC-11.2: Bir motor kaydı (deneme, refleks denemesi) yazıldıktan sonra değiştirilemez (API düzeyinde yalnız ekleme; test).
- AC-11.3: (v1.0) StoreKit sahte yapılandırmasıyla: satın alma, deneme, yenileme, iptal, iade, geri yükleme, çevrimdışı açılış senaryoları test edilir; iade edilen işlem yetki vermez.
- AC-11.4: (v1.0) Kilitli içerik antrenman başlamadan kontrol edilir; antrenman sırasında yetki düşse bile antrenman biter.
- AC-11.5: Güvenlik ve sağlık özellikleri hiçbir yetki durumunda kapanmaz (test).
- AC-11.6: Beta (TestFlight) derlemesinde tüm içerik açıktır.

## Açık sorular
1. Fiyatlar ve Türkiye fiyatlandırması; ilk kullanıcılar salondan geldiğinde onlara indirim kodu (App Store teklif kodu) verilsin mi?
2. Ömür boyu satın alma gelecekteki spor paketlerini kapsasın mı?
3. Aile Paylaşımı açık olsun mu?
4. Hocanın gelir payı (00 açık soru 1) varsa, App Store gelir raporundan elle mi hesaplanacak?
5. App Store Küçük İşletme Programı'na başvuru (komisyon %15).
