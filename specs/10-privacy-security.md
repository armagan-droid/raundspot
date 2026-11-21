# 10 — Gizlilik ve Güvenlik

Kamera ve sağlık verisi kullanan bir uygulama olarak gizlilik hem güven hem mağaza onayı için belirleyicidir. KVKK ve GDPR ilkeleriyle tasarlanır. Temel yaklaşım: **veri cihazdan çıkmaz**.

## Veri envanteri
| Veri | Nerede | Ne kadar | Cihazdan çıkar mı |
|---|---|---|---|
| Kamera kareleri | Bellek | Kare işlenene kadar | Hayır |
| Eklem koordinatları (canlı) | Bellek | Set boyunca | Hayır |
| Profil (gard yönü, seviye, hedef, dil, isteğe bağlı kilo, boy) | SwiftData | Kullanıcı silene kadar | Hayır (iCloud yedeği hariç, aşağıda) |
| Antrenman kayıtları (set, deneme, tepki süresi, hata türü) | SwiftData | Kullanıcı silene kadar | Hayır |
| Postür ölçüleri (v1.0) | SwiftData | Kullanıcı silene kadar | Hayır |
| HealthKit'e yazılan antrenman, aktif enerji ve (bağlı nabız sensörü varsa) nabız | HealthKit | Kullanıcının Sağlık ayarları | Apple'ın Sağlık eşitlemesi (kullanıcı kontrolünde) |
| HealthKit'ten okunan kilo, nabız, yaş, cinsiyet | Bellek | Hesap süresince; saklanmaz | Hayır |
| Satın alma durumu (v1.0) | StoreKit (Apple) | — | Apple |
| Kayıt modu videosu ve poz verisi (yalnız TestFlight) | Uygulama kapsayıcısı, şifreli | ≤ 12 ay | Video hayır; takma adlı landmark yalnız elle dışa aktarımla (09) |
| Çökme raporları | Apple (TestFlight/App Store Connect, kullanıcı izniyle) | Apple | Apple |

## İlkeler
1. **Sunucu yok, hesap yok.** Kullanıcı adı, e-posta, telefon istenmez. Uygulama hiçbir kendi sunucusuna istek atmaz (00 kural 2).
2. **Üçüncü taraf SDK yok:** analitik, reklam, hata izleme, A/B test, uzaktan yapılandırma SDK'sı eklenmez. Bağımlılık eklemek bu spec'in güncellenmesini gerektirir.
3. **Ağ izin listesi:** Release derlemesinde uygulamanın açtığı tüm ağ bağlantıları Apple alan adlarına (StoreKit, sistem) gider. Otomatik test: UI testleri sırasında `URLProtocol` kaydıyla uygulama kaynaklı istek sayısı = 0.
4. **Kamera görüntüsü saklanmaz** (kayıt modu hariç, 09). Fotoğraf kitaplığına erişim istenmez.
5. **Mikrofon kullanılmaz** (AC-2.5).
6. **Yüz tanıma, kimlik tanıma yok.** Kişi seçimi yalnız konum ve boyuta göredir (ref 07).
7. Kadrajda başka biri varsa yalnız takip edilen kişinin eklemleri işlenir; diğerleri aynı karede atılır (ref 07).

## Rıza ve şeffaflık
- **İlk açılış** (12 O2): kısa aydınlatma: "Kamera görüntün yalnız bu telefonda işlenir, kaydedilmez ve hiçbir yere gönderilmez." + tıbbi uyarı + "Devam". Ayrı bir açık rıza ekranı gerekmez çünkü kişisel veri cihazdan çıkmaz ve geliştirici tarafından işlenmez; metin hukuki görüşe bağlıdır (açık soru).
- Kamera izni (`NSCameraUsageDescription`, TR/EN): "Hareketlerini saymak ve formunu kontrol etmek için. Görüntü kaydedilmez ve telefondan çıkmaz."
- Kamera açıkken ekranda küçük kamera ikonu + "Görüntü kaydedilmez" (kayıt modu hariç; orada kırmızı KAYIT bandı).
- Gizlilik politikası: uygulama içinde (Ayarlar) ve mağaza sayfasında, TR/EN; App Store HealthKit kuralları gereği zorunludur.

## App Store gereklilikleri
- **Gizlilik etiketi:** "Data Not Collected" (geliştirici veri toplamaz). HealthKit verisi cihazda kalır ve geliştiriciye gitmediği için "toplanan veri" değildir; v1.0 öncesi bu yorum App Store Connect yönergeleriyle yeniden kontrol edilir.
- **Gizlilik bildirimi (`PrivacyInfo.xcprivacy`):** izleme yok; kullanılan "gerekçe isteyen API"ler (ör. `UserDefaults`, dosya zaman damgası, sistem açılış süresi — zamanlama için) ve gerekçe kodları listelenir. Liste derleme sırasında kontrol edilir.
- **HealthKit:** HealthKit verisi reklam veya veri madenciliği için kullanılmaz, iCloud'a uygulama tarafından yazılmaz, üçüncü tarafla paylaşılmaz.
- **Sağlık iddiaları:** mağaza metni ve ekran görüntüleri 07 yasaklı ifade listesine uyar; "teşhis", "tedavi", "düzeltir" yoktur.
- **Yaş derecelendirmesi:** mağaza derecelendirmesi içerik anketine göre belirlenir (şiddet içeriği yok; dövüş sporu antrenmanı). 18+ kullanım koşulu ayrıca uygulama içi onayla sağlanır (aşağıda).

## Yaş
- İlk açılışta doğum yılı değil yalnız "18 yaşından büyüğüm" onayı istenir (12 O2). 18 yaş altı kullanıcı için MVP'de uygulama kullanılamaz ("Bu sürüm yetişkinler içindir") — açık soru 00-3.
- Kayıt modunda 18 yaş altı katılımcı kaydedilemez (09).

## Kullanıcı hakları
- **Dışa aktarma:** Ayarlar → Verilerim → "Dışa aktar (JSON)": profil, antrenmanlar, refleks denemeleri, postür ölçüleri. Paylaşım sayfasıyla.
- **Silme:** "Tüm verilerimi sil": SwiftData deposu, tercihler, önbellekler silinir; HealthKit kayıtları için ayrıca sorulur ("Sağlık'a yazılan antrenmanları da sil?"). Satın alma Apple hesabına bağlıdır, silinmez; "Satın alımları geri yükle" ile geri gelir.
- Tek antrenman silme (08 "Sağlık'taki kaydı da sil?").

## Yedekleme
- SwiftData deposu varsayılan iOS yedeğine (iCloud/bilgisayar) dahildir; böylece telefon değişince geçmiş kaybolmaz. Bu, Apple'ın kullanıcı kontrolündeki yedeğidir; geliştiriciye veri gitmez.
- Kayıt modu verisi yedekten hariçtir (09).
- iCloud ile cihazlar arası eşitleme (CloudKit) v1.0 sonrası (14).

## Güvenlik
- Depolama: SwiftData deposu `NSFileProtectionCompleteUntilFirstUserAuthentication` (seans arka plana alındığında da yazılabilsin); kayıt modu `NSFileProtectionComplete`.
- Kural paketleri ve katalog JSON'ları uygulamayla birlikte gelir; MVP ve v1.0'da ağdan şablon indirilmez (App Store 2.5.2 açısından da sorun yok: veridir, kod değil). Uzaktan şablon güncellemesi ileride eklenirse imzalı paket gerekir (açık soru).
- İfade dili `eval` içermez; Swift ayrıştırıcısı ref AC-4.2'yi sağlar (AC-3.3).
- Bağımlılık: yalnız Apple çerçeveleri ve Swift standart kütüphanesi; Swift Package bağımlılığı eklemek bu spec'te gerekçelendirilir.
- Gizli anahtar yoktur (sunucu yok); StoreKit doğrulaması cihazdadır (11).

## Güvenlik ve sağlık sınırları
- "Tıbbi tavsiye değildir. Ağrı hissedersen dur." ibaresi ilk açılışta, her antrenman başlangıcında (12 S2 alan onayı ekranında) ve Ayarlar'da.
- İlk açılışta kısa sağlık beyanı (PAR-Q benzeri 3 soru: kalp rahatsızlığı, göğüs ağrısı/baş dönmesi, son 3 ayda sakatlık). "Evet" yanıtında: "Başlamadan önce doktoruna danışmanı öneririz." — kullanım engellenmez, yanıtlar **saklanmaz** (yalnız gösterildiği kaydedilir).
- Güvenlik duraklatması (ref 05) ve alan kontrolü (12 S2) kapatılamaz; salon ürünündeki gibi yönetici ayarı yoktur.

## Kabul kriterleri
- AC-10.1: Release derlemesinin UI test akışlarında uygulama kaynaklı ağ isteği 0 (StoreKit sahte ortamı hariç).
- AC-10.2: Uygulama ikili dosyasında üçüncü taraf SDK yoktur (bağımlılık listesi testi: yalnız izinli paketler).
- AC-10.3: "Tüm verilerimi sil" sonrası SwiftData deposu boştur ve uygulama ilk açılış durumuna döner (test).
- AC-10.4: Dışa aktarma JSON'u katı şemaya uyar ve landmark/görüntü içermez (test).
- AC-10.5: `PrivacyInfo.xcprivacy` mevcuttur ve kodda kullanılan her gerekçe isteyen API listelenmiştir (derleme kontrolü).
- AC-10.6: Tıbbi uyarı ilk açılışta, her antrenman başlangıcında (S2) ve ayarlarda görünür (snapshot testi).
- AC-10.7: Sağlık beyanı yanıtları kalıcı depoya yazılmaz (test).

## Açık sorular
1. İlk açılıştaki aydınlatma metni ve gizlilik politikası hukukçuya okutulmalı; cihazda kalan veri için açık rıza gerekmediği yorumu doğrulanmalı.
2. Hoca ya da salonla gelecekte veri paylaşımı (öğrencinin ilerlemesini hocaya göstermek) istenirse sunucusuz yaklaşım (dışa aktarılan özet dosyası) yeterli mi?
3. İleride uzaktan şablon/katalog güncellemesi (yeni hareketler için uygulama güncellemesi beklememek) istenecek mi? İstenirse imzalı paket ve küçük bir statik barındırma gerekir; bu 00 kural 2'yi değiştirir.
