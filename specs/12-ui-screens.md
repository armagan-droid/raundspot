# 12 — Ekranlar

SwiftUI, iPhone. Koyu tema varsayılan, açık tema seçilebilir. TR/EN (String Catalog). Dokunma hedefi ≥ 44 pt. Antrenman ekranları 2–3 m'den okunacak şekilde tasarlanır.

## Tasarım ilkeleri
- **Antrenman sırasında sesle yönetim:** kullanıcı ekrana dokunmadan bir antrenmanı baştan sona yapabilmeli (otomatik başlama, sesli geri sayım, otomatik geçiş). Dokunma yalnız seans başındaki alan onayı (S2), duraklatma ve bitirme için.
- **Tek odak:** antrenman ekranında kamera + bir büyük sayı (tekrar ya da son tepki süresi) + bir uyarı bandı. Başka bilgi yok.
- **Ciddi, sakin ton.** Oyun öğeleri (puan, rozet, maskot, konfeti) yok (00).
- **Renk tek başına bilgi taşımaz:** ikon + metin + ses.
- **Erişilebilirlik:** Dynamic Type (antrenman dışı ekranlarda), VoiceOver etiketleri, "Hareketi azalt" ayarında yanıp sönme yerine sabit vurgu.
- "Tıbbi tavsiye değildir" ibaresi 10'daki yerlerde.

## Gezinme
Alt sekme çubuğu (antrenman dışında): **Antrenman** · **İlerleme** · **Ayarlar**. Antrenman akışı tam ekran modal olarak açılır, sekme çubuğu gizlenir.

## O) İlk açılış
| # | Ekran | İçerik |
|---|---|---|
| O1 | Karşılama | Ürün adı, tek cümle ("Sanal rakibinle eskiv ve refleks çalış"), dil seçimi (sistem dili öntanımlı), "Başla" |
| O2 | Güvenlik ve gizlilik | "Görüntün telefonda işlenir, kaydedilmez, gönderilmez"; tıbbi uyarı; "18 yaşından büyüğüm" onayı; kısa sağlık beyanı (3 soru, 10; yanıt saklanmaz) |
| O3 | Gard yönü | Orthodox (sol ayak önde) / southpaw (sağ ayak önde), basit çizimle; "emin değilim" → orthodox + "Ayarlar'dan değiştirebilirsin" |
| O4 | Seviye ve hedef | Kaç yıldır çalışıyorsun (0–1 / 1–3 / 3+), hedef (eskiv ve refleks / kondisyon / dengeli); v1.0'da haftalık gün ve süre |
| O5 | Kilo (isteğe bağlı) | "Kalori tahmini için"; HealthKit'ten al / elle gir / şimdi değil |
| O6 | Apple Sağlık | Ne yazılacağı, ne okunacağı; "İzin ver" (sistem iletişim kutusu) / "Şimdi değil" |
| O7 | Kamera | Neden gerektiği; "İzin ver" (sistem iletişim kutusu). Reddedilirse E1 |
| O8 | Postür (v1.0) | "2 dakikalık duruş gözlemi yapalım mı?" → P1 / "Sonra" |
| O9 | İlk antrenman önerisi | "Eskiv temeli" kartı + "Başla"; ya da ana sayfaya |

## H) Ana sayfa (Antrenman sekmesi)
| # | Ekran | İçerik |
|---|---|---|
| H1 | Antrenman | Üstte: bugünün önerisi (v1.0: haftalık plandan; MVP: son yapılana göre). Kartlar: **Teknik** (eskiv seçimi), **Refleks** (seviye seçimi, son medyan RT), **Kondisyon**, **Hazır antrenmanlar**. Kilitli içerik kilit ikonuyla (v1.0) |
| H2 | Eskiv seçimi | Şablon listesi: ad, kısa `howTo`, kamera yönü (önden/yandan) ikonu, "taslak" etiketi (`draft`) TestFlight'ta |
| H3 | Refleks seviyesi | Seviye kartları (05 tablosu sade dille: "Tek işaret, yavaş", "2'li kombinasyon" …), önerilen seviye vurgulu |
| H4 | Haftalık plan (v1.0) | 7 gün şeridi, gün türü (teknik / kondisyon / mobilite / dinlenme), bugünün antrenmanı |

## S) Kurulum ve güvenlik (her antrenmanın başında, ilk bloktan önce; 06 `SETUP`)
Sıra: **S2 → S1 → S3**. Alan onayı, kullanıcı telefonu yerleştirirken (telefonun yanındayken) dokunarak verilir; ardından kullanıcı 2–3 m geri gider ve S1 kendiliğinden tamamlanır. Yalnız kamerasız bloklardan oluşan antrenmanda S1 atlanır, S2 atlanmaz.

| # | Ekran | İçerik |
|---|---|---|
| S1 | Kamera kurulumu | ref 08 A3'ün karşılığı: tam ekran önizleme (ön kamerada aynalı gösterim), hedef siluet, kılavuz çerçeve, sorunlu kenarlarda kırmızı bant, büyük ipucu, sesli ipucu. Kontroller ref 08 "A3 kurulum kontrolleri"ndeki gibi (tüm vücut, çok uzak/yakın değil, görünüm uygun, tek kişi) + **mesafe**: görünen vücut kutusunun yüksekliğinden ve kamera görüş açısından tahmin edilen mesafe 2–3 m aralığında değilse "Biraz yaklaş" / "Bir adım geri" (boy profilde varsa onunla, yoksa 1,70 m varsayımıyla). Telefon eğimi > 10° ise "Telefonu dik koy". Refleks modunda gereken landmark birleşimi (baştan ayağa) |
| S2 | Alan onayı ve tıbbi uyarı | Seans başına bir kez, S1'den önce: "Tıbbi tavsiye değildir. Ağrı hissedersen dur." (10) + "Etrafında en az 2×2 m boş alan var mı? Kaygan zemin, eşya, evcil hayvan?" → "Alan güvenli" düğmesine **dokunarak** onay. Sesle ya da duruşla onay yoktur: bilinçli bir kullanıcı eylemi olmalıdır. Kamera engelleri göremez; bu kullanıcı onayıdır |
| S3 | Isınma | Adım adım sesli rehber (06), kalan süre büyük, "Atla" (atlanınca uyarı bir kez). Kamerayla sayım yapılmaz (06 `warmup`) |

Kurulum hazır 1,5 sn kesintisiz sürerse sonraki adıma kendiliğinden geçilir (ref 08 "Otomatik başlama").

### S1 hesapları (`SoloEngine` `assessSetup`, T2.6)
Kaynak `assessSetup` (ref 08 A3: son ~1 sn'lik örneklerin ≥ %80'i geçer, ipucu sırası, sorunlu kenarlar) ve kişi seçimi (ref 07 "Seçim kuralları"; Vision gözlemleri güvene göre sıralanır, ilk 2 aday değerlendirilir) aynen çevrilir. Ekler:
- **Mesafe:** yalnız `camera.posture: standing` ve görüntünün dikey görüş açısı (`FOV_v`, kişinin dik göründüğü yönde; `SoloCapture` verir) biliniyorsa. `h` = görünür baş noktalarının (`nose`, gözler, kulaklar) en üstü ile görünür ayak bileklerinin en altı arasındaki dikey fark (görüntü yüksekliği oranı). Bu aralığın gerçek boyu `0,90 × boy` kabul edilir (göz–ayak bileği; boy profilde yoksa 1,70 m). `d = 0,90·boy / (2·tan(FOV_v/2)·h)`. Örnek başına: `d < 2,0 m` → `setup.hint.step_back`, `d > 3,0 m` → `setup.hint.move_closer`; baş ya da bilek görünmüyorsa mesafe hesaplanmaz. Mesafe hesaplanabildiğinde ref 08'in "kutu ≥ %45" kuralı **uygulanmaz**: dikey ön kamerada (~70° görüş) 3 m'deki kişi görüntünün yalnız ~%36'sını kaplar ve iki kural çelişir. Mesafe hesaplanamıyorsa (`horizontal` duruş, görüş açısı yok) %45 kuralı geçerlidir.
- **Telefon eğimi:** uygulama cihazın dikeyden sapmasını (derece, CoreMotion) verir; > 10° ise `setup.hint.phone_upright`. Son değere bakılır, örnek oranına girmez; kurulumu hazır saydırmaz.
- **Telefonu çevir:** `camera.posture: horizontal` ve `imageAspect < 1` (dikey görüntü) ise `setup.hint.rotate_phone` (ref 08 "Telefonu çevir"); kurulumu hazır saydırmaz.
- **Birden çok şablon (refleks modu, seviyenin `accept` şablonları):** gereken landmark'lar `minVisibleLandmarks` birleşimi, kabul edilen görünümler kesişimi, `minVisibility` en büyüğü; `activeFaults` şablon başına. Kesişim boşsa kurulum hazır olmaz (görünüm ipucu `adjust_angle`).
- **İpucu sırası:** `rotate_phone`, `phone_upright`, `multiple_people`, `show_full_body`, `step_back`, `move_closer`, ardından görünüm ipuçları (`turn_side`, `face_camera`, `adjust_angle`). Hazır değilse en az bir ipucu vardır; hazırsa ipucu yoktur.

## T) Teknik ve kondisyon seti
| # | Ekran | İçerik |
|---|---|---|
| T1 | Hazır / geri sayım | Hareket adı, `howTo`, set x/toplam; hazır duruşla ya da "Başla" ile sesli 3-2-1 |
| T2 | Aktif set | ref 08 A5 ile aynı yerleşim ve kurallar: kamera + iskelet (kapatılabilir), büyük sayaç (x / hedef, ekran yüksekliğinin ≥ %25'i), uyarı bandı, form hatasında eklem vurgusu, güvenlik duraklatmasında kırmızı kutu ve çerçeve. **Eskiv hedef dairesi, oklar ve balonlar** ref 08'deki gibi; eğilme çizgisi (`duck`, `bob_weave_*`) `ayak bileği ortası.y − headTarget.height · omuz genişliği` yüksekliğindedir (`heightOverShoulders2d`, 04); `bob_weave_*` için balon kesikli çizginin altında yana kayık; `lean_back` (yandan) için başın arkasında dikey kesikli çizgi ve balon. Düğmeler: ses, duraklat, seti bitir |
| T3 | Dinlenme | Geri sayım, set özeti (ref 05), sonraki set/hareket, "Hazırım" |

## R) Refleks seti
| # | Ekran | İçerik |
|---|---|---|
| R1 | Hazırlık | "Gard al, ortaya gel"; tüm aday tepkilerin hazır olduğu gösterilir (başın etrafında nötr daire). Seviye, işaret sayısı. Bluetooth çıkışta "tepki süresi yaklaşık" notu |
| R2 | Aktif | Kamera + iskelet. İşaret anında ekranın ortasında **saldırının adı** büyük yazıyla 600 ms (ses asıl kanal; yazı yalnız destek, RT ölçümü sese göredir). Tepki sonrası sonuç ikonu (✓ / ✗ / ⏱ kaçırıldı / ⚡ erken) + RT ms, 1 sn. Sağ üstte işaret sayacı (12/20). Form hatası olan doğru tepkide küçük uyarı bandı. Hedef balonları **yoktur** (yönü kullanıcı seçer; balon cevabı söylemiş olur) |
| R3 | Set özeti | İsabet %, medyan ve p90 RT, saldırı bazında satırlar (isabet, medyan RT), tercih edilen tepki oranı, aldatma başarısı, en sık form hatası; seviye önerisi (05) |
| R4 | Raunt (v1.0) | R2 + üstte raunt saati ve raunt numarası; dinlenmede raunt özeti (isabet, RT, gard %, aktivite) |

## Y) Antrenman sonu
| # | Ekran | İçerik |
|---|---|---|
| Y1 | Özet | Süre, bloklar, tekrar/isabet, medyan RT (varsa), "≈ kcal (tahmin)" ve yöntemi, "Sağlık'a kaydedildi" (izin varsa), "Bitir" |

## G) İlerleme sekmesi
| # | Ekran | İçerik |
|---|---|---|
| G1 | Genel | Son 8 hafta: haftalık antrenman sayısı, refleks medyan RT eğilimi (seviye bazında), isabet oranı; MVP'de basit çubuk/çizgi (Swift Charts) |
| G2 | Geçmiş | Antrenman listesi → detay (bloklar, setler, denemeler, hatalar); silme (08 Sağlık sorusuyla) |
| G3 | Eskiv detayı | Şablon bazında temiz tekrar oranı, en sık hatalar (son 30 gün) |

## P) Postür (v1.0)
| # | Ekran | İçerik |
|---|---|---|
| P1 | Hazırlık | Kıyafet, mesafe, telefon yüksekliği onayları; telefon eğimi göstergesi |
| P2 | Ölçüm | Önden → yandan; sesli yönerge, ilerleme halkası, kalite uyarıları (07) |
| P3 | Sonuç | Ölçü başına bant + kısa metin + iskelet üstünde çizgi (fotoğraf yok); "Programına eklediklerimiz"; sağlık uyarısı; "Ayrıntılar" (sayılar) |

## A) Ayarlar
Dil, tema, gard yönü, seviye/hedef, kilo/boy, kamera (ön/arka), form uyarısı sesi ve sonuç tonları (işaret sesleri kapatılamaz, 05), teknik tempo (yavaş/normal), Apple Sağlık (durum + sistem ayarlarına git), verilerimi dışa aktar, tüm verilerimi sil, satın alımları geri yükle (v1.0), gizlilik politikası, kullanım koşulları, tıbbi uyarı, sürüm. Beta: **Geliştirici** bölümü (tanı paneli, kayıt modu, sahte kamera — Debug).

## X) Kayıt modu (yalnız Beta, 09)
| # | Ekran | İçerik |
|---|---|---|
| X1 | Kayıtlar | Liste (tarih, katılımcı kodu, şablon/mod, süre, not sayısı), boş alan göstergesi, toplu sil |
| X2 | Katılımcılar | Kod listesi, rıza durumu ve sürümü, "Rızayı geri çek" |
| X3 | Rıza | Aydınlatma metni, 18+ kutusu, kabul (katılımcının kendisi işaretler) |
| X4 | Kayıt | Normal antrenman ekranı + kırmızı KAYIT bandı ve çerçeve, süre, "Durdur" |
| X5 | Oynatma | Video + çizim katmanı, zaman çizelgesi ve olay işaretleri, kare kare kontrol, hız, not ekle/düzenle (metin + etiket) |
| X6 | Yeniden oynat | Parametre/sürüm seçimi, değer taraması, sonuç tablosu ve eski/yeni olay şeritleri |
| X7 | Dışa aktar | Seçili kayıtlar → landmark JSON (video yok), paylaşım sayfası |

## E) Hata durumları
| # | Durum | İçerik |
|---|---|---|
| E1 | Kamera izni yok | Neden gerektiği + "Ayarlar'ı aç"; kamerasız antrenman yok (yalnız rehberli mobilite önerilir) |
| E2 | Kişi görünmüyor / birden fazla kişi / bölge görünmüyor | ref 08 A5 takip kaybı metinleri ve çizimi |
| E3 | Cihaz yetersiz | Spike'taki alt sınırın altında: "Bu cihazda kamera takibi yeterince hızlı değil" |
| E4 | Termal | Kademeli çalışmada kullanıcıya bir şey gösterilmez; ciddi ısınmada (`critical`) "Telefon çok ısındı, kısa bir mola" ve seans `PAUSED` |
| E5 | Depolama dolu | Kayıt yazılamazsa: "Antrenman kaydedilemedi, telefonunda yer aç" (antrenman kesilmez) |

## Yönlendirme ve yerleşim
| Ekran | Telefon yatay (önerilen) | Telefon dikey |
|---|---|---|
| S1, T2, R2, X4 | Kamera tam ekran (`contain`, kırpma yok, ref 08); panel sağda yarı saydam | Kamera tam ekran; ipucu üstte, panel altta |
| Diğer | Dikey öncelikli; yatayda tek sütun ortalanmış | Tek sütun |
- Kurulumda dikey tutulan telefona "Önden eskiv için telefonu yan çevir" önerilir (zorunlu değil).

## Kabul kriterleri
- AC-12.1: T2 ve R2, en küçük desteklenen iPhone ekranında ve en büyük ekranda, yatay ve dikey, taşmasız (snapshot testleri).
- AC-12.2: T2 sayacı ekran yüksekliğinin ≥ %25'i; R2 saldırı adı ≥ %20'si.
- AC-12.3: Bir hazır antrenman, seans başındaki tek alan onayı dokunuşu (S2) dışında ekrana dokunmadan (kurulum + otomatik başlama + sesli geçişler) tamamlanabilir (UI testi, sahte kamera).
- AC-12.4: S2 alan onayı seans başına bir kez, ilk bloktan (ısınma dahil) önce istenir ve onaysız hiçbir blok başlamaz.
- AC-12.5: TR/EN, koyu/açık tema geçişi tüm ekranlarda çalışır; String Catalog'da eksik çeviri yok (test).
- AC-12.6: VoiceOver ile O1–O7, O9 (MVP), O8 (v1.0) ve A tamamlanabilir.
- AC-12.7: R2'de hedef balonu çizilmez; T2'de eskiv şablonlarında çizilir.

## Açık sorular
1. Arka kamera öntanımlı olmalı mı? Daha geniş görüş ve daha iyi kalite, ama kullanıcı ekranı göremez (ses yeterli olabilir).
2. R2'de saldırı adının ekranda gösterilmesi bazı kullanıcılar için görsel ipucu olup sesi gereksiz kılar mı? Yalnız ses modu (ekran yazısı kapalı) seçeneği gerekli mi?
3. İlerleme ekranında RT eğilimi seviye değişince karşılaştırılamaz; seviye başına ayrı çizgi mi, normalize bir skor mu?
