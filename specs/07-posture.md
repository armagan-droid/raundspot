# 07 — Postür Değerlendirmesi (v1.0)

İlk açılışta (atlanabilir) ve sonra 4 haftada bir önerilen, önden ve yandan **duruş gözlemi**. Sonuç haftalık programın mobilite ve kondisyon seçimlerini şekillendirir (06 kural 6). **Tıbbi teşhis değildir;** ölçülen şey kameranın gördüğü birkaç geometrik farktır.

## Dil kuralları (zorunlu)
Postür ekranlarında, seslerinde ve mağaza metninde:

| Kullanılır | Kullanılmaz |
|---|---|
| "duruş gözlemi", "hizalama", "fark", "eğilim", "alışkanlık", "programına şunu ekledik" | "teşhis", "bozukluk", "hastalık", "skolyoz", "kifoz", "lordoz", "düz boyun", "tedavi", "düzeltir", "iyileştirir", "ağrıyı giderir", "anormal" |
| "observation", "alignment", "difference", "tendency", "we added … to your plan" | "diagnosis", "disorder", "condition", "scoliosis", "kyphosis", "lordosis", "text neck", "treat", "cure", "fix", "corrects", "heals", "relieves pain", "abnormal" |

- Her sonuç ekranında: "Bu bir sağlık değerlendirmesi değildir. Ağrın, uyuşman ya da hareket kısıtlılığın varsa bir sağlık profesyoneline danış."
- Yasaklı ifade listesi String Catalog'a karşı otomatik test edilir (TR ve EN, büyük/küçük harf ve çekim ekleri dahil kök eşleşmesi). Kural 6 gereği test tüm katalogda çalışır (`ForbiddenPhraseTests`). Kökle başlayıp yasaklı kelime olmayan tek istisna "Conditioning"dir: ürünün antrenman türüdür (kondisyon), tıbbi "condition" değildir.

## Ölçüm protokolü
1. **Hazırlık ekranı:** dar ya da vücuda oturan kıyafet, saç toplu, ayakkabısız, 2–3 m mesafe, düz zemin, telefon bel hizasında ve dik. Bunlar kullanıcı onayıdır; kamera yalnız mesafe ve tüm vücudun göründüğünü denetler.
2. **Önden:** "Rahat dur, kollar yanda, karşıya bak." 3 sn hareketsizlik bekleme, ardından 3 sn ölçüm.
3. **Yandan:** "Sol yanını kameraya dön." (Yakın taraf sol; sağ yan isteğe bağlı ikinci ölçüm.) Aynı süreler.
4. **Kalite kapıları** (ölçüm penceresinin her karesi için): ilgili eklemlerin hepsi görünür (2B güven eşiği, 03), görünüm doğru (`front`/`side`), hareketsizlik (eklemlerin görüntüdeki sapması gövde boyunun %2'sinden az), kişi seçimi belirsiz değil. Karelerin < %80'i geçerse ölçüm tekrarlanır.
5. **Değer:** her ölçü için geçerli karelerin **medyanı**.
6. **Tekrarlanabilirlik:** önden ölçüm iki kez alınır (arada "bir adım at, geri gel"); iki ölçüm arasındaki fark ölçünün tolerans değerini aşarsa "Ölçümler tutarsız, bir kez daha deneyelim" ve üçüncü ölçüm; yine aşarsa o ölçü "belirsiz" sayılır ve programa etki etmez.

## Ölçüler (2B, Vision 19 eklem)
| Kod | Görünüm | Tanım | Bant (taslak) | Tolerans |
|---|---|---|---|---|
| `shoulder_tilt` | önden | Omuz çizgisinin yataydan açısı (°) | < 2 dengeli, 2–4 hafif, > 4 belirgin | 1,5° |
| `hip_tilt` | önden | Kalça çizgisinin yataydan açısı (°) | < 2 / 2–4 / > 4 | 1,5° |
| `head_tilt` | önden | Göz çizgisinin yataydan açısı (°) | < 3 / 3–6 / > 6 | 2° |
| `head_shift` | önden | Burnun omuz ortasına yatay uzaklığı / omuz genişliği | < 0,05 / 0,05–0,10 / > 0,10 | 0,03 |
| `knee_inward` | önden | `kneeInwardRatio` iki diz (ayakta) | < 0,03 / 0,03–0,06 / > 0,06 | 0,02 |
| `head_forward` | yandan | Kulağın omuza göre öne yatay uzaklığı / gövde boyu | < 0,10 / 0,10–0,20 / > 0,20 | 0,04 |
| `shoulder_forward` | yandan | Omzun kalçaya göre öne yatay uzaklığı / gövde boyu | < 0,08 / 0,08–0,15 / > 0,15 | 0,04 |
| `trunk_lean` | yandan | Kalça→omuz doğrusunun dikeyden açısı (°) | < 5 / 5–10 / > 10 | 2° |
| `knee_lock` | yandan | Dizin kalça–ayak bileği doğrusunun gerisinde kalması (`signedOffset`) | < 0,02 / 0,02–0,04 / > 0,04 | 0,015 |

- Bantlar **taslaktır**; literatürdeki klinik eşikler değildir ve öyle sunulmaz. Kayıt modu verisiyle (gönüllü katılımcılar, aynı kişinin tekrarlı ölçümü) tolerans ve bantlar yeniden belirlenir.
- Yan görünümde "ön" yönü burnun yakın kulağa göre bulunduğu taraftır (04 `sagittalLean2d` ile aynı tanım).
- Kamera eğikse (telefon dik değil) önden açılar yanılır: ölçüm başında telefonun eğimi hareket sensöründen (`CMMotionManager`, yerçekimi vektörü) okunur; eğim > 3° ise "Telefonu dik koy" uyarısı ve ölçülen açılar bu eğim kadar düzeltilir.

## Sonuç
- Her ölçü için bant: **dengeli / hafif fark / belirgin fark / belirsiz**. Sayılar "ayrıntı" altında gösterilir; ana ekranda yalnız metin + basit çizim (iskelet üstünde çizgi; fotoğraf yok).
- **Bayraklar** (programa giden): yalnız "belirgin fark" ve tekrarlanabilir ölçüler bayrak üretir.

| Bayrak | Programa etkisi (06 kural 6) | Kullanıcıya metin (TR) |
|---|---|---|
| `head_forward` | Göğüs omurgası mobilitesi + `superman` (hold) öne alınır | "Başın omuz hizasının önünde duruyor. Programına üst sırt ve göğüs açıcı çalışmalar ekledik." |
| `shoulder_forward` | Göğüs ve omuz açıcılar, `guard_hold` öncesi omuz çevirme | "Omuzların öne doğru duruyor. Omuz açıcı çalışmalar ekledik." |
| `shoulder_tilt` / `hip_tilt` | Tek taraflı hareketlerde (lunge, tek ayak denge) iki taraf eşit hacim; mobilitede yan esneme | "Omuz/kalça yüksekliğinde fark görüldü. Tek taraflı çalışmaları iki tarafa eşit dağıttık." |
| `knee_inward` | `squat`/`reverse_lunge` öncesi kalça aktivasyonu; squat'ta `knee_valgus` uyarısı öncelikli | "Dizlerin içe doğru duruyor. Kalça çalışmaları ekledik." |
| `knee_lock` | Ayakta drillerde "dizleri hafif bük" ipucu sıklığı artar | "Ayakta dizlerini geriye kilitleme eğilimi var." |
| `head_tilt`, `head_shift`, `trunk_lean` | Program etkisi yok; yalnız bilgi | — |

## Veri ve gizlilik
- Görüntü, video ya da landmark dizisi saklanmaz; yalnız ölçü değerleri, bantlar, tarih ve kalite bilgisi (11 `PostureAssessment`).
- Kullanıcı tüm postür sonuçlarını silebilir; silince program bayrakları da kalkar.
- HealthKit'e postür verisi **yazılmaz**.

## Kabul kriterleri
- AC-7.1: Her ölçü sentetik vücutta (bilinen eğim, bilinen baş ofseti) ±tolerans/2 içinde hesaplanır (Swift sentetik vücut aracıyla).
- AC-7.2: Kalite kapısı: hareketli, kısmen görünen ya da yanlış görünümdeki dizi ölçüm üretmez.
- AC-7.3: Tekrarlanabilirlik kuralı: tolerans dışı iki ölçümde üçüncü istenir; yine tutarsızsa ölçü "belirsiz" olur ve bayrak üretmez.
- AC-7.4: Yasaklı ifade testi TR ve EN String Catalog'da sıfır eşleşme verir.
- AC-7.5: Telefon eğimi düzeltmesi: 5° eğik sentetik görüntüde düzeltme sonrası omuz açısı ±0,5° içinde.
- AC-7.6: Postür sonucu silinince program bir sonraki üretimde bayraksız üretilir.

## Açık sorular
1. Bantlar ve bayrak → program eşlemesi bir fizyoterapist ya da antrenörün görüşünden geçmeli mi? (Hoca dışında bir uzman.)
2. Sağ yan ölçümü zorunlu mu olmalı (iki yan karşılaştırması daha anlamlı ama süreyi uzatır)?
3. *(Karara bağlandı, 11 Bölüm 2: ölçüm ve sonuç ücretsiz, programa etkisi premium.)*
