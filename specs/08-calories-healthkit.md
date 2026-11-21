# 08 — Kalori Tahmini ve HealthKit

`SoloEngine/Energy` (saf hesap) ve `SoloHealth` (HealthKit). Kalori her yerde **tahmin** olarak sunulur.

## Kalori formülü
```
brüt kcal = MET × kilo (kg) × süre (saat)
net (aktif) kcal = (MET − 1) × kilo (kg) × süre (saat)
```
- 1 MET = 3,5 mL O₂/kg/dk (2024 Adult Compendium of Physical Activities, 18–59 yaş).
- **HealthKit'e net değer yazılır** (`activeEnergyBurned`, dinlenme metabolizması hariç); kullanıcıya da net değer gösterilir ("aktif kalori"). Brüt değer gösterilmez (iki sayı kafa karıştırır).
- Hesap **segment bazlıdır**: seans, set/deneme süreleri ve dinlenmelerden oluşan zaman çizelgesidir; her segment kendi MET değeriyle hesaplanır. Duraklatılan süre sayılmaz.

## MET tablosu
| Segment | MET | Kaynak | Durum |
|---|---|---|---|
| Teknik modu seti (yavaş, kontrollü) | 5,3 | Compendium 15425: dövüş sanatları, yavaş tempo, acemi, pratik | doğrulandı |
| Refleks seti | 7,8 | 15425 ile 15430'un ortası (deneme aralıkları ve hazırlık beklemesi dahil) | **varsayım**, hoca + nabız verisiyle gözden geçirilecek |
| Raunt (v1.0) | 10,3 | Compendium 15430: dövüş sanatları, orta tempo (kickboks, Muay Thai dahil) | doğrulandı |
| Kondisyon seti (squat, şınav, lunge, jumping jack) | 8,0 | Compendium, kalistenik, yüksek efor | **doğrulanacak** (2024 kodu) |
| Isınma, soğuma, mobilite | 2,3–3,0 | Compendium, esneme / hafif kalistenik | **doğrulanacak** |
| Setler arası dinlenme | 1,5 | ayakta hafif hareket | **doğrulanacak** |
- Tablo veridir (`exercises/energy/met.json`); her satır Compendium kodunu taşır. "Doğrulanacak" satırlar T6.1'de Compendium'un 2024 tablosundan kontrol edilip kodlarıyla güncellenir.
- 60 yaş ve üstü için 2024 Older Adult Compendium farklı bir taban (2,7 mL/kg/dk) kullanır; MVP'de ayrıca ele alınmaz (açık soru).

## Kilo
1. HealthKit'te `bodyMass` okuma izni varsa son kayıt (90 günden yeni) kullanılır. Değer her hesapta HealthKit'ten okunur ve uygulamada saklanmaz (10 veri envanteri); profile kopyalanmaz.
2. Yoksa profilde kullanıcının girdiği kilo (isteğe bağlı, ilk açılışta sorulur, "şimdi değil" denebilir).
3. İkisi de yoksa kalori **gösterilmez** ve HealthKit'e enerji örneği yazılmaz; antrenman yine yazılır. Ekranda "Kilonu girersen kalori tahmini görürsün."
- Birim: kg/lb, bölge ayarına göre; içeride her zaman kg.

## Nabızla iyileştirme
Nabız verisi **yeterliyse** MET yerine nabız tabanlı tahmin kullanılır.
- **Kaynaklar:**
  - **Canlı:** iOS 26'da iPhone'da çalışan `HKWorkoutSession` + `HKLiveWorkoutBuilder`, eşleşmiş Bluetooth nabız sensörlerinden (göğüs bandı, nabız ölçen kulaklık) nabzı kendisi toplar. iPhone'un nabız sensörü yoktur.
  - **Sonradan:** antrenman bitince HealthKit'ten aynı zaman aralığındaki `heartRate` örnekleri okunur (ör. Apple Watch'un o sırada kaydettiği). Watch'ta antrenman açık değilse örnekler seyrek olur ve çoğu zaman yeterlilik eşiğini geçmez.
  - **Apple Watch uygulaması** (canlı nabız, 14 yol haritası) MVP'de yok.
- **Yeterlilik:** aktif sürenin her dakikasında en az bir örnek, toplamda aktif sürenin ≥ %70'i kapsanmış.
- **Formül:** Keytel ve ark. (2005) nabız → enerji denklemleri (cinsiyet, yaş, kilo, ortalama nabız). Yaş ve cinsiyet HealthKit'ten (`dateOfBirth`, `biologicalSex`) okunur; okunamazsa nabız tahmini yapılmaz, MET kullanılır. Denklem katsayıları uygulamadan önce kaynağından doğrulanır (T6.1).
- Sonuç ekranında hangi yöntemin kullanıldığı yazılır: "Tahmin: hareket türü ve süre" ya da "Tahmin: nabız verisi".

## HealthKit'e yazma
- **Antrenman:** her seans tek bir `HKWorkout`. Bloklar `HKWorkoutActivity` olarak eklenir; tür eşlemesi:

| Blok | `HKWorkoutActivityType` |
|---|---|
| teknik, refleks, raunt | `.martialArts` (spor paketlerinde: kickboks `.kickboxing`, boks `.boxing`) |
| kondisyon | `.functionalStrengthTraining` (jumping jack devresi `.mixedCardio`) |
| ısınma, soğuma, mobilite | `.preparationAndRecovery` / `.flexibility` |
| seansın ana türü | en uzun bloğun türü |
- Kapalı alan: `HKMetadataKeyIndoorWorkout = true`.
- **Enerji:** her blok için bir `activeEnergyBurned` örneği (net kcal), antrenmana bağlı. `HKLiveWorkoutBuilder`'ın kendi enerji toplaması **kapatılır** (veri kaynağında yalnız nabız etkin) ki çift sayım olmasın; davranış spike'ta doğrulanır (açık soru).
- **Yazılmayanlar:** tekrar sayıları, form hataları, tepki süreleri, postür. Bunlar uygulamaya özgüdür ve HealthKit'te karşılığı yoktur; yalnız yerel veride kalır (11).
- **Yaşam döngüsü:** seansın ilk bloğu başladığında (`SETUP` bitip `WARMUP`'a, ısınma yoksa ilk bloğa geçilince) oturum başlar (`.running`); kurulum süresi antrenmana girmez. Her blok başında yeni bir `HKWorkoutActivity` açılır, blok bitince kapanır (dinlenme ait olduğu bloğun içindedir). `PAUSED` ile `.paused`, `SESSION_DONE` ile `finishWorkout`. `ABORTED` seans, aktif süresi ≥ 3 dk ise yazılır ("Yarım kaldı" bilgisi yerel kayıtta), değilse oturum atılır (`discardWorkout`).
- Uygulamadan bir seans silinince kullanıcıya "Sağlık'taki kaydı da sil?" sorulur; evetse uygulamanın yazdığı `HKWorkout` ve örnekleri silinir.

## İzinler
- İlk HealthKit kullanımında (ilk antrenman sonu ya da ilk açılış adımı 12 O6) istenir; reddedilirse uygulama tam çalışır, yalnız Sağlık'a yazmaz.
- **Yazma:** `workoutType`, `activeEnergyBurned`, `heartRate` (canlı sensör verisi oturum üzerinden yazılır).
- **Okuma:** `bodyMass`, `heartRate`, `dateOfBirth`, `biologicalSex` — her biri ayrı açıklamayla; okuma izni olmadan ilgili özellik sessizce devre dışı kalır.
- `NSHealthShareUsageDescription` ve `NSHealthUpdateUsageDescription` TR/EN, ne için kullanıldığını tek cümleyle söyler.
- HealthKit verisi reklam, analitik ya da üçüncü tarafla paylaşım için kullanılmaz; uygulama dışına çıkmaz (10).

## Gösterim
- "≈ 135 kcal (tahmin)" — 5'e yuvarlanır. Altında yöntem. Dokununca açıklama: "Kalori; hareket türü, süre ve kilona göre tahmin edilir. Gerçek değer kişiden kişiye değişir."
- Haftalık özette toplam aktif kalori; grafik yok (MVP).

## Kabul kriterleri
- AC-8.1: Segment bazlı hesap: bilinen zaman çizelgesi ve kilo için net kcal beklenen değerle (± 0,5 kcal) aynı; duraklatma süresi sayılmaz (birim testi).
- AC-8.2: Kilo yoksa enerji örneği yazılmaz, antrenman yazılır (HealthKit sahte nesnesiyle test).
- AC-8.3: Nabız yeterlilik kuralı: %69 kapsamada MET, %70'te nabız yöntemi seçilir; yaş/cinsiyet yoksa MET (test).
- AC-8.4: Karma seans, blok başına doğru `HKWorkoutActivityType` ile tek `HKWorkout` olarak yazılır; enerji çift sayılmaz (cihaz testi: Sağlık uygulamasındaki toplam = uygulamanın gösterdiği).
- AC-8.5: 3 dk'dan kısa iptal edilen seans HealthKit'e yazılmaz.
- AC-8.6: HealthKit izni reddedilince hiçbir akış kesilmez (UI testi).
- AC-8.7: Her kalori gösteriminde "tahmin" ibaresi vardır (snapshot testi).

## Açık sorular
1. Refleks seti MET değeri (7,8) varsayımdır; pilotta nabız bandı takan birkaç kullanıcıyla kontrol edilmeli.
2. 60 yaş ve üstü kullanıcılar için Older Adult Compendium kullanılsın mı?
3. `HKLiveWorkoutBuilder`'da enerji toplamasını kapatmak iPhone'da beklendiği gibi çalışıyor mu (iOS 26'da builder'ın enerji hesabıyla ilgili hata raporları var)? Çalışmazsa `HKWorkoutBuilder` (canlı olmayan) ile seans sonunda yazmak yedek plan.
4. Apple Watch uygulaması (canlı nabız ve bilekten işaret titreşimi) v1.x'te mi yapılmalı? Watch'tan titreşimli işaret, sesin yerine geçebilir.
