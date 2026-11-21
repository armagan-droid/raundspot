# 01 — Sözlük

**Atıf kuralı:** `05` bu repodaki `specs/05-…md` dosyasıdır; `ref 04` salon ürününün çatallanma anındaki spec kopyası `docs/reference/b2b/04-exercise-rules.md`'dir (salt okunur, commit `c2fe3fd`). Bir `ref` dosyasındaki kural burada yalnız bu spec'ler ona açıkça atıf yaptığında geçerlidir. Salon sözlüğündeki (ref 01) terimler (Rule Pack, Attempt, Valid/Faulty/Incomplete, Turn point, View, near_/far_, Fault, Cue, Landmarks, Frame) burada da aynı anlamdadır; aşağıda yalnız yeni ya da farklı anlamlı terimler var.

## Ürün ve modlar
| Terim | Tanım |
|---|---|
| Teknik modu | Tek bir eskiv ya da hareketin yavaş, kontrollü tekrarlandığı set. Form hataları uyarılır. Salon ürünündeki set akışının bireysel karşılığı (06 "Seans motoru"). |
| Refleks modu | Uygulamanın rastgele **işaret** verdiği, kullanıcının uygun **tepki** ile cevap verdiği set. Tepki türü, doğruluğu ve süresi ölçülür (05). |
| Raunt modu | (v1.0) Refleks modunun gerçek hızda, raunt zamanlayıcısı ve dinlenme aralarıyla oynanan biçimi; ritim, aktivite ve gard izlenir (05). |
| Kondisyon hareketi | Kuvvet ve kondisyon programındaki kamerayla izlenen hareket (squat, şınav, lunge vb.); kaynak formattaki `reps` hareketiyle aynı motor (06). |
| Seans | Bir antrenman: ısınma + bloklar + soğuma. Cihazda saklanır (11). |
| Blok | Seans içindeki tek bir çalışma birimi: teknik bloğu, refleks bloğu, kondisyon bloğu, mobilite bloğu. |
| Haftalık program | (v1.0) Seviye ve hedeften üretilen 7 günlük plan (06). |
| Spor paketi | Bir sporun şablon, işaret ve program setleri (Muay Thai, sonra kickboks, boks) (11). |

## Refleks
| Terim | Tanım |
|---|---|
| İşaret (cue, refleks) | Uygulamanın sanal rakip olarak verdiği sesli komut: rakibin saldırısını adlandırır ("jab!"). Salon ürünündeki "cue" (form uyarısı) ile karışmaması için kodda `Prompt` / `strikeCue` adı kullanılır; form uyarısı `faultCue` olarak kalır. |
| Saldırı (strike) | İşaretin temsil ettiği rakip tekniği: `jab`, `cross`, `lead_hook`, `rear_hook`, `high_kick` vb. (05 "İşaret kataloğu"). |
| Tepki (response) | Kullanıcının yaptığı savunma hareketi: bir eskiv şablonunun (`slip_left`, `duck`, `bob_weave_left`…) tamamlanmış denemesi. |
| Kabul edilen tepki | Bir saldırıya karşı doğru sayılan tepkiler kümesi; gard yönüne göre çözülür (05 "Eşleme"). Biri **tercih edilen** olarak işaretlenebilir. |
| İşaret anı (`t_cue`) | İşaret sesinin ilk örneğinin hoparlörden çıktığı an (ses çıkış gecikmesi düzeltilmiş), kamera saatiyle aynı saat tabanında (05). |
| Tepki anı (`t_move`) | Tepki şablonunun denemesinin **kesinleştiği** an: tekrar metriğinin `start.exit`'ten `attemptMinExcursion` kadar uzaklaştığı an (ref 04'teki `REP_STARTED`), ham metrik üzerinden ve kare zamanına göre interpolasyonla (05). |
| Tepki süresi (RT) | `t_move − t_cue`, milisaniye. |
| Tepki penceresi | İşaretten sonra tepkinin başlaması gereken en uzun süre; seviyeye bağlı. Aşılırsa **kaçırıldı**. |
| Erken tepki | İşaretle neredeyse aynı anda başlayan tepki: işaret planlandıktan sonra `t_cue`'dan önce ya da `t_cue`'dan sonra insanca mümkün olmayacak kadar kısa sürede (`minHumanRtMs`, varsayılan 120 ms) başlar. Tahmin sayılır, RT istatistiğine girmez. İşaret planlanmadan önce (bekleme sırasında) başlayan hareket deneme sayılmaz, beklemeyi sıfırlar (05). |
| Deneme sonucu (trial result) | `correct`, `correct_faulty` (doğru eskiv, form hatalı), `wrong` (yanlış eskiv), `partial` (eskiv başladı ama hedefe ulaşmadı), `missed`, `early`, `feint_ok` (aldatmaya tepki verilmedi), `feint_bitten` (aldatmaya tepki verildi). |
| Kombinasyon | Art arda verilen 2+ işaret; her birinin tepkisi ayrı değerlendirilir. |
| Aldatma (feint) | Tepki **verilmemesi** gereken işaret ("dur!") ya da kombinasyon içinde beklenmeyen yön değişimi (05 "Aldatma"). |
| Seviye | Refleks zorluğu: işaret aralığı, tepki penceresi, kombinasyon uzunluğu, aldatma oranı ve işaret seti (05 "Seviyeler"). |

## Duruş ve taraf
| Terim | Tanım |
|---|---|
| Gard yönü (stance) | `orthodox` (sol ayak önde) veya `southpaw` (sağ ayak önde). Profilde seçilir, her seansta değiştirilebilir. |
| lead_ / rear_ | (v1.0, 04) Öndeki/arkadaki taraf eklemini gösteren sanal landmark adı; gard yönüne göre çözülür (orthodox: lead = left). `near_`/`far_` gibi çalışır. |
| Kişinin solu/sağı | Anatomik sol/sağ (ref 04 "Kişinin solu"). `slip_left` başın kişinin soluna gitmesidir; gard yönü bunu değiştirmez. |
| Dış / iç eskiv | Saldıran kolun dışına/içine kaçış. Hangi yöne karşılık geldiği gard yönüne ve saldırıya bağlıdır; eşleme tablosunda çözülür (05). |

## Kamera ve motor
| Terim | Tanım |
|---|---|
| İskelet (skeleton) | Poz modelinin eklem seti. `mediapipe33` (kaynak motor, MediaPipe) veya `vision19` (Apple Vision 2B) (03). |
| Vision 3B | `DetectHumanBodyPose3DRequest`: 17 eklemli, metre cinsinden 3B iskelet (03). |
| World koordinatı | Kalça merkezli, metre, x sağa, y aşağı, z kameradan uzağa (ref 04). Vision verisi bu eksenlere çevrilerek motora verilir (03 "Koordinat dönüşümü"). |
| Kaynak motor | GymSpot salon ürününün `packages/engine` (TypeScript) motoru, commit `c2fe3fd`. Bu projeye kod olarak girmez; yalnız bir kez golden verisi üretmek için kullanılır (03). |
| Swift motoru | `Packages/SoloEngine`; kaynak motorun egzersiz katmanından çevrilen, bu projenin tek motoru (03). |
| Kaynak golden | Kaynak motorun bir landmark dizisinden ürettiği olay akışı; `fixtures/source-golden/` altında, değiştirilmez (03). |
| Anlık görüntü (snapshot) | Swift motorunun yeni davranış için ürettiği, gözden geçirilip onaylanmış beklenen çıktı; `fixtures/snapshots/` (03). |
| Kaynak uyumluluğu | Swift motorunun tüm kaynak golden dosyalarında kaynak motorla aynı olayları üretmesi (03). |
| Kare zamanı | Kameranın kareye verdiği sunum zaman damgası (`CMSampleBuffer` PTS), host saatinde. Tüm zamanlamalar bu saate göre yapılır. |

## Kayıt modu
| Terim | Tanım |
|---|---|
| Kayıt modu | Yalnız TestFlight derlemesindeki geliştirici aracı: video + kare kare poz + motor durumu birlikte kaydedilir (09). |
| Kayıt paketi | Bir kaydın klasörü (`.gsrec`): video, poz akışı, motor olayları, notlar, rıza kimliği (09). |
| Katılımcı | Kayıt modunda kaydedilen kişi; takma adla (`participant_ref`) tutulur. |
| Not (annotation) | Hocanın videonun belirli bir anına eklediği yorum; isteğe bağlı olarak bir etiket (doğru/hatalı + hata türü) taşır. |
| Yeniden oynatma (replay) | Kaydedilmiş poz akışını, değiştirilmiş eşiklerle motordan yeniden geçirme (09). |

## Sağlık ve kalori
| Terim | Tanım |
|---|---|
| MET | Metabolik eşdeğer; 1 MET = 3,5 mL O₂/kg/dk (2024 Adult Compendium) (08). |
| Brüt / net kalori | Brüt = MET × kg × saat. Net (aktif) = (MET − 1) × kg × saat. HealthKit'e **net** yazılır (08). |
| Postür gözlemi | (v1.0) Önden ve yandan duruşta ölçülen birkaç geometrik fark (omuz yüksekliği farkı, baş önde vb.); teşhis değildir (07). |

## Açık sorular
1. Salonda kullanılan terimler: öğrenciler "kroşe" mi "hook" mu diyor, "lean back" Türkçede nasıl söyleniyor? İşaret seslerinin TR sürümü buna göre seçilir (05).
