# 00 — Vizyon

> **Ürün adı:** GymSpot Solo *(çalışma adı)*. Ad, tek yerden (`AppBrand` sabiti ve String Catalog'daki `app.name` anahtarı) değiştirilir; spec'lerde ve kodda başka yerde sabit yazılmaz.
>
> Bu repo bireysel iOS uygulamasının **bağımsız** projesidir. Hareket şablonu formatı ve kural motorunun davranışı, GymSpot salon ürününden (B2B PWA, `github.com/armagan-droid/gymspot`) **çatallanmıştır** (fork, commit `c2fe3fd`, 15 Kasım 2026). O andaki salon spec'lerinin salt okunur kopyası `docs/reference/b2b/` altındadır ve `ref NN` diye anılır (01 "Atıf kuralı"). Bundan sonra iki proje bağımsız gelişir; salon ürünündeki değişiklikler buraya kendiliğinden gelmez, gerekirse spec değişikliğiyle elle alınır.

## Problem
Muay Thai'de savunma, özellikle baş hareketi (eskiv: slip, duck, lean back, bob & weave), en geç oturan ve en az tek başına çalışılabilen beceridir. Salonda hoca ya da partner olmadan:
- Öğrenci hareketi doğru yapıp yapmadığını (gövdeyle mi kaçıyor, gard düşüyor mu) göremez.
- Refleks çalışılamaz: gölge boksunda saldırıyı kimse "atmaz", öğrenci hep kendi bildiği sırayla hareket eder.
- Tepkinin hızlanıp hızlanmadığı ölçülemez.

Fikir bir Muay Thai hocasından geldi: öğrencilerin eskivi evde, tek başına ve geri bildirimle çalışabileceği bir araç.

## Çözüm
Telefonun kamerasıyla çalışan **sanal rakip**:
1. Uygulama rastgele sesli işaret verir ("jab!", "kroşe!", "yüksek tekme!").
2. Kullanıcı o saldırıya uygun eskivle tepki verir.
3. Kamera hem **hareketin doğruluğunu** (doğru eskiv mi, formu doğru mu) hem **tepki süresini** ölçer.
4. Seviye arttıkça işaretler hızlanır, kombinasyonlar uzar, aldatmalar girer.

Bunun etrafında:
- **Teknik modu:** yavaş, kontrollü tekrar; kamera pozisyonu ve form hatalarını denetler (GymSpot salon ürünündeki eskiv drillerinin kural motorundan türetildi).
- **Raunt modu** (v1.0): gerçek hız, raunt zamanlayıcısı ve dinlenme araları; ritim, aktivite ve gardın düşmesi izlenir.
- **Kuvvet ve kondisyon:** Muay Thai'nin yoğun kullandığı kas gruplarına yönelik, kameranın izleyebildiği hareketler (06).
- **Haftalık program** (v1.0): seviye ve hedefe göre teknik, kondisyon ve mobilite günlerini karıştıran plan (06).
- **Postür değerlendirmesi** (v1.0): önden ve yandan duruş gözlemi; programı şekillendirir, teşhis koymaz (07).
- **Kalori tahmini ve HealthKit:** antrenmanlar Sağlık uygulamasına yazılır (08).

## Kullanıcılar
| Kullanıcı | İhtiyaç |
|---|---|
| Muay Thai öğrencisi (başlangıç–orta, 0–5 yıl) | Eskivi evde doğru ve hızlı çalışmak, ilerlemesini görmek |
| Hoca | Öğrencinin salon dışında da doğru çalıştığından emin olmak; içerik onayı (rolü açık soru, aşağıda) |
| Geliştirici + hoca (TestFlight) | Kayıt modu ile eşik kalibrasyonu ve motor test verisi (09) |

Hedef yaş: 18+ (bkz. 10 "Yaş"). Rakip partner, ped, torba yok; tek kişi, tek kamera.

## Ürün ilkeleri
- **Önce doğruluk:** yanlış "doğru!" ya da yanlış "hata!" güveni bitirir. Belirsizlikte uygulama yorum yapmaz (ref 05 ile aynı ilke).
- **Sakin ve ciddi ton.** Oyunlaştırma yok: rozet, sıralama tablosu, karakter yok. İlerleme sayılarla gösterilir (tepki süresi, isabet oranı).
- **Sesle yönetilir.** Kullanıcı 2–3 m uzakta, ekrana bakmıyor; her şey sesle duyulur, ekran destekler.
- **Sağlık iddiası yok.** Postür ve kalori çıktıları "gözlem" ve "tahmin"dir; tıbbi teşhis, tedavi, düzeltme iddiası kesinlikle yoktur (07, 08).
- **Telefonda kalır.** MVP'de sunucu, hesap, analitik SDK'sı yok (10).

## Spor kapsamı
- **İlk spor:** Muay Thai.
- **Sonra (spor paketi):** kickboks, boks. Aynı motor, farklı şablon ve işaret setleri (11 "Spor paketleri").
- **Kapsam dışı:** güreş temelli sanatlar (BJJ, judo, güreş): yer çalışması ve temas tek kameradan anlamlı izlenemez.

## Kapsam dışı (bu ürün için)
- GymSpot salon ürünü (PWA) ve onunla entegrasyon (sonra konuşulacak).
- Tekme ve yumruk **hızı veya kuvveti** ölçümü. Raunt modundaki "aktivite" göstergesi birimsizdir ve kuvvet ya da hız olarak sunulmaz (05).
- Android ve web.
- Partnerle çalışma, sparring, ped/torba çalışması.
- Tıbbi, fizyoterapi ya da rehabilitasyon amaçlı kullanım.
- Beslenme takibi.

## İş modeli (özet, ayrıntı 11)
- **Freemium.** Ücretsiz çekirdek: temel eskiv (teknik modu, ilk refleks seviyeleri) ve temel kondisyon. Premium: tüm programlar, gelişmiş refleks seviyeleri, raunt modu, yeni spor paketleri.
- **Yıllık abonelik** ve **ömür boyu** satın alma. Haftalık/aylık abonelik yok.
- İlk kullanıcılar Türkiye'den ve kurucunun salonundan; gelirin ağırlıklı olarak İngilizce konuşulan pazarlardan gelmesi beklenir. Bu yüzden TR ve EN baştan eşit kalitede.
- Hedef: büyük bir şirket değil; kullanışlı bir ürün ve aylık birkaç yüz dolar ek gelir. Altyapı maliyeti sıfıra yakın tutulur (sunucu yok).

## Değişmez kurallar
Bu projenin değişmez kurallarıdır; `CLAUDE.md` bunlara atıf yapar. `docs/reference/b2b/` altındaki salon spec'lerinin kendi kuralları burada geçerli değildir; çelişkide bu liste geçerlidir.

1. **Kamera görüntüsü cihazdan çıkmaz ve diske yazılmaz.** Kareler yalnızca bellekte poz modeline gider. **Tek ve dar istisna: Kayıt modu** (09): yalnız TestFlight derlemesinde vardır, kaydedilen kişinin ayrı açık rızasıyla açılır, kayıt telefonda kalır; dışarı yalnız takma adlı, görüntüsüz veri (landmark dizisi ve ona bağlı işaret/deneme satırları, 09 "Dışa aktarma") aktarılabilir; video ve kare görüntüsü asla.
2. **Sunucu yok (MVP ve v1.0).** Ağ isteği yalnız Apple servislerine (StoreKit, TestFlight) gider. Üçüncü taraf analitik, reklam ya da hata izleme SDK'sı eklenmez (10).
3. **Hareket kuralları JSON'dur.** Format, salon ürününün şablon formatından çatallanmıştır (ref 04) ve bu projede 04'teki eklemelerle genişler. Yeni hareket eklemek Swift kodu gerektirmez. Formata eklenen her alan, fonksiyon ya da ifade yapısı önce 04'e yazılır.
4. **Tek motor Swift motorudur.** Çatallanma anındaki davranışı, salon ürününün TypeScript motorundan bir kez üretilen kaynak golden verisiyle sabitlenir (03 "Kaynak uyumluluğu"); bu testler hiçbir zaman silinmez. Kaynak davranışı bilerek değiştiren bir değişiklik, ilgili golden dosyasını spec'te gerekçesiyle `superseded` işaretler.
5. **Geri bildirim kısa olur;** aynı uyarı bekleme süresi dolmadan tekrarlanmaz (ref 05 kuralları).
6. **Sağlık iddiası yok.** "Tıbbi tavsiye değildir" ibaresi ilk açılışta, her antrenman başlangıcında (12 S2 alan onayı ekranı) ve ayarlarda görünür. Postür ve kalori dili 07 ve 08'deki yasaklı ifade listesine uyar.
7. **Güvenlik önce:** alan onayı olmadan hiçbir antrenman, kamera kurulumu (2–3 m, tüm vücut görünür) olmadan kameralı hiçbir antrenman başlamaz. İkisi de seansın ilk bloğundan (ısınma dahil) önce yapılır (06 `SETUP`); ısınma atlanabilir ama atlanınca uyarılır (12).
8. **TR ve EN baştan:** kullanıcıya görünen her metin String Catalog'dadır; eksik çeviri derlemede test hatasıdır.

## Başarı ölçütleri
**MVP (salon pilotu, 13):**
- Refleks modunda tepki sınıflandırma doğruluğu (doğru eskiv / yanlış eskiv / kaçırıldı) ≥ %90, hocanın etiketine göre.
- Tepki süresi ölçüm hatası: medyan ≤ 50 ms, p95 ≤ 100 ms (05 "Doğrulama").
- Teknik modunda sayım doğruluğu ≥ %95, yanlış form uyarısı ≤ %10 (ref 09 tanımlarıyla).
- Çökmesiz antrenman oranı ≥ %99.
- Pilot kullanıcıların ≥ %60'ı 3 hafta boyunca haftada en az 2 antrenman yapar.

**v1.0 (App Store, ilk 6 ay):**
- Ücretsizden premiuma dönüşüm ≥ %3.
- Aylık net gelir birkaç yüz dolar (hedef aralık 11 açık sorusu).
- App Store puanı ≥ 4,5.

## Açık sorular
1. **Hocanın rolü:** içerik onayı mı, danışman mı, gelir ortağı mı? Adı uygulamada geçecek mi (ör. "İçerik onayı: …")? Ses kayıtları onun sesiyle mi olacak? Bu karar 05 (işaret eşlemesi onayı), 11 (gelir paylaşımı) ve mağaza metnini etkiler.
2. **Ürün adı:** v1.0 öncesi seçilmeli; App Store'da benzer adlı uygulama ve marka taraması yapılmalı.
3. **Hedef yaş:** 16–17 yaş öğrenciler salonda çok; bunları kapsamak ebeveyn rızası ve App Store yaş derecelendirmesi gerektirir. MVP'de 18+.
4. **Başarı ölçütü eşikleri** (dönüşüm %3, 3 hafta tutunma) sezgiseldir; pilot verisiyle güncellenmeli.
