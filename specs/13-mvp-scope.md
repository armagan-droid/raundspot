# 13 — MVP ve v1.0 Kapsamı

## Amaç
**MVP:** kurucunun salonunda hoca ve 5–10 öğrenciyle, TestFlight üzerinden 4–6 hafta denenecek, ürünün kalbini (eskiv + refleks) kanıtlayan en küçük sürüm. Para kazanmak değil, doğru ölçtüğünü ve işe yaradığını göstermek.

**v1.0:** App Store'da ücretli (freemium) ilk sürüm.

## MVP — dahil
- **Muay Thai eskiv şablonları** (04): `slip_left`, `slip_right`, `slip` (teknik), `duck`, `bob_weave_left`, `bob_weave_right`; `lean_back` teknik modunda yandan (deneysel); önden refleks sürümü `lean_back_front` yalnız 03 H1 doğrulanırsa.
- **Teknik modu** (05): set, tekrar, form uyarısı, güvenlik duraklatması, hedef dairesi.
- **Refleks modu** (05): taslak işaret kataloğu (jab, cross, sol/sağ kroşe, `stop` aldatması; `high_kick` koşullu), seviye 1–6, kombinasyonlar, tepki süresi, set özeti.
- **Orthodox / southpaw** (05 eşleme aynalaması). Şablonlarda `lead_`/`rear_` yok (v1.0).
- **Kondisyon hareketleri** (04, 06): `squat`, `pushup` (yandan, 2B'ye uyarlanmış), `reverse_lunge`, `jumping_jack`.
- **Seans motoru ve 4 hazır antrenman** (06): ısınma, soğuma, rehberli mobilite adımları.
- **Kurulum ve güvenlik** (12 S1–S3): mesafe, tüm vücut, alan onayı, ısınma.
- **HealthKit ve kalori tahmini** (08): iPhone'da antrenman oturumu, blok bazında etkinlik, MET tahmini, varsa nabız.
- **Kayıt modu** (09): yalnız Beta; rıza, kayıt, oynatma, not, yeniden oynatma, landmark dışa aktarma.
- **Motor:** Swift motoru + kaynak uyumluluğu (03); format eklemeleri (`formatVersion 2`, `vision19`, 2B metrik fonksiyonları, `min`, `derivedFrom`); `solo-calibrate` aracı.
- **Yerel veri, geçmiş, basit ilerleme** (11, 12 G1–G3), dışa aktarma ve silme (10).
- **TR/EN**, koyu/açık tema.
- Her şey açık (ödeme yok).

## MVP — hariç (v1.0'a)
Raunt modu · haftalık program motoru · postür değerlendirmesi · StoreKit ve kilitler · `check` ve `low_kick` · teep sıralama hatası (`sequence:`) · `lead_`/`rear_` · `hold` tipi (plank, tek ayak denge, gard tutma) · `knee_strike` · `burpee`, `jump_rope` · App Store yayını.

## v1.0 sonrası (14)
Apple Watch uygulaması (canlı nabız, bilekte titreşimli işaret) · kickboks ve boks paketleri · iCloud eşitlemesi · hocanın sesiyle işaret paketi · görsel işaret modu · uzaktan şablon güncellemesi (karar gerektirir, 10).

## Pilot planı
| Hafta | Ne | Kim |
|---|---|---|
| 0 | Kalibrasyon kayıtları: her eskiv için teknik + refleks setleri, bilinçli hatalı tekrarlar (09 "Salon pilotu akışı") | Hoca + 3–5 öğrenci |
| 1 | Eşik taraması, şablon ve katalog güncellemesi; RT doğrulaması (05) | Geliştirici |
| 2–5 | Öğrenciler evde kullanır; haftada bir salonda kısa görüşme ve hocanın kayıt inceleme oturumu | 5–10 öğrenci |
| 6 | Ölçütlerin değerlendirilmesi, v1.0 kapsamının güncellenmesi | Geliştirici + hoca |

## Pilot kabul ölçütleri
| Ölçüt | Hedef | Nasıl ölçülür |
|---|---|---|
| Tepki sınıflandırma doğruluğu | ≥ %90 | Kayıt modu etiketleri vs. uygulama sonucu (`correct`/`wrong`/`missed` …) |
| Tepki süresi ölçüm hatası | medyan ≤ 50 ms, p95 ≤ 100 ms | 05 "Doğrulama" (ağır çekim karşılaştırma) |
| Teknik modunda sayım doğruluğu | ≥ %95 | ref 09 tanımı, etiketli kayıtlar |
| Yanlış form uyarısı | ≤ %10 | ref 09 tanımı |
| Form uyarısı gecikmesi (p95) | ≤ 250 ms | cihaz ölçümü |
| Çökmesiz antrenman | ≥ %99 | TestFlight çökme raporları + yerel seans durumu (`aborted` sebebi) |
| Tutunma | Katılımcıların ≥ %60'ı 3 hafta boyunca haftada ≥ 2 antrenman | Katılımcıların gönüllü dışa aktardığı veri (10 "Kullanıcı hakları") ya da görüşme |
| Hocanın değerlendirmesi | "Öğrencilerime önerirdim" | Görüşme |

**Telemetri yok:** tutunma ve kullanım verisi uygulamadan otomatik gönderilmez (10). Pilot katılımcısı isterse Ayarlar → Verilerim → "Dışa aktar (JSON)" ile verisini (görüntü ve landmark içermez, 10) paylaşır; görüşmeler ana kaynaktır.

## Pilot geri bildirim listesi
Kayıt notlarından ve görüşmelerden gelen her bulgu: tarih, kaynak (hoca/öğrenci/kayıt), ilgili spec (04, 05, 12 …), önem (engelleyici / önemli / küçük), karar. Liste bu dosyanın sonuna eklenir; v1.0 kapsamı buna göre güncellenir.

## Varsayımlar ve riskler
| Risk | Etki | Azaltma |
|---|---|---|
| Vision 2B ile önden baş yatışı ve eğilme yeterince kararlı değil | Eskiv sayımı ve refleks sınıflandırması bozulur | Spike T0.2; kalibrasyon; gerekirse 3B (H1) ya da MediaPipe'ın yeniden değerlendirilmesi (03 açık soru 3) |
| Ses çıkış gecikmesi (özellikle Bluetooth) RT'yi bozar | RT anlamsızlaşır | Hoparlörü öner; Bluetooth'ta "yaklaşık" etiketi |
| Bob & weave ve duck ayrımı belirsiz | Kroşelerde yanlış "doğru/yanlış" | Özgüllük kuralı, `no_weave` eşiği, hoca etiketleriyle kalibrasyon |
| Lean back önden ölçülemez | `high_kick` MVP'de yok | Katalogdan çıkarılır, v1.0'da yeniden değerlendirilir |
| Ev ortamında alan dar, ışık zayıf | Takip kaybı, güvenlik | Kurulum ipuçları, alan onayı, ışık uyarısı (açık soru) |
| Hocanın zamanı sınırlı | Onay ve etiketleme gecikir | Pilot hafta 0'ı tek oturumda planla; etiketleme oynatma ekranında hızlı |

## Açık sorular
1. Pilot katılımcı sayısı ve seçimi (seviye karışımı, en az bir southpaw).
2. Düşük ışık uyarısı: Vision güven ortalaması düşükse "Ortamı aydınlat" ipucu MVP'ye girsin mi?
3. MVP'nin TestFlight dış test grubu için Apple'ın Beta incelemesi gerekecek; inceleme notunda kayıt modunun nasıl açıklanacağı.
