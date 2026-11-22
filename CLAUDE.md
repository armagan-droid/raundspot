# GymSpot Solo — Proje Kuralları (Claude Code için)

Muay Thai öğrencileri için **bireysel iOS uygulaması**: sanal rakip gibi sesli işaret veren, kullanıcının eskiv tepkisini kamerayla sınıflandıran ve tepki süresini ölçen antrenman aracı. Swift 6 + SwiftUI, AVFoundation, Apple Vision, HealthKit. Sunucu yok.

## Çalışma yöntemi: Spec-Driven Development
- Önce `specs/` okunur, sonra kod yazılır. Spec'te olmayan davranış **eklenmez**; gerekiyorsa önce spec güncellenir.
- Her görev bir ana spec'e bağlıdır (`specs/14-roadmap.md`). Görev bitince o spec'in **kabul kriterleri** testlerle karşılanmış olmalı.
- Önce test, sonra uygulama. `Packages/SoloEngine` saf Swift'tir (yalnız Foundation) ve kamera olmadan, Linux'ta da test edilir.
- Spec ile kod çelişirse spec doğru kabul edilir, çelişki raporlanır.
- `docs/reference/b2b/` salt okunurdur; atıflarda `ref NN` olarak geçer (`specs/01` "Atıf kuralı").

## Spec dizini
- `specs/00-vision.md` — problem, kullanıcılar, kapsam, **değişmez kurallar**
- `specs/01-glossary.md` — terimler, atıf kuralı
- `specs/02-architecture.md` — mimari, repo yerleşimi, saat tabanı, performans, spike
- `specs/03-engine-integration.md` — Swift motoru, kaynak golden, Vision eklem eşlemesi, kalibrasyon
- `specs/04-exercise-rules.md` — format eklemeleri, şablon seti, yeni şablonlar
- `specs/05-reflex-mode.md` — teknik, refleks ve raunt modu
- `specs/06-training-programs.md` — seans motoru, kondisyon, haftalık program
- `specs/07-posture.md` — postür değerlendirmesi (v1.0)
- `specs/08-calories-healthkit.md` — kalori tahmini, HealthKit
- `specs/09-recording-mode.md` — kayıt modu (yalnız TestFlight)
- `specs/10-privacy-security.md` — gizlilik ve güvenlik
- `specs/11-data-and-purchases.md` — yerel veri modeli, satın alma
- `specs/12-ui-screens.md` — ekranlar
- `specs/13-mvp-scope.md` — MVP ve v1.0 kapsamı, pilot
- `specs/14-roadmap.md` — uygulama sırası (Claude Code görev listesi)
- `exercises/*.json` — hareket şablonları (veri, kod değil); `exercises/source/` kaynak kopyalar, dokunulmaz

## Değişmez kurallar
Tam liste ve gerekçeler: `specs/00-vision.md` "Değişmez kurallar". Özet:
1. **Kamera görüntüsü cihazdan çıkmaz ve diske yazılmaz.** Tek istisna Beta derlemesindeki, ayrı rızalı kayıt modu (`specs/09`); video telefondan asla çıkmaz.
2. **Sunucu yok;** üçüncü taraf SDK (analitik, reklam, hata izleme) yok.
3. Hareket kuralları JSON'dur; yeni hareket Swift kodu gerektirmez. Formata ekleme önce `specs/04`'e yazılır.
4. Tek motor Swift motorudur; `fixtures/source-golden/` testleri hep yeşil kalır, bu dosyalar değiştirilmez.
5. Geri bildirim kısa olur; aynı uyarı bekleme süresi dolmadan tekrarlanmaz.
6. Sağlık iddiası yok: "tıbbi tavsiye değildir" ibaresi zorunlu; postür ve kalori dili yasaklı ifade listesine uyar.
7. Alan onayı ve (kameralı antrenmanda) kurulum (2–3 m, tüm vücut) olmadan antrenman başlamaz; ikisi ısınmadan önce yapılır.
8. TR ve EN baştan; kullanıcıya görünen her metin String Catalog'dadır.

## Komutlar
- Motor testleri (Linux/macOS): `swift test --package-path Packages/SoloEngine`
- Araç testleri: `swift test --package-path Packages/SoloCalibrate`
- Şablon doğrulama: `swift run --package-path Packages/SoloCalibrate solo-calibrate validate exercises/` (şema + ifadeler; `exercises/` kökünde `howTo` zorunlu, `source/` hariç; tanınmayan alt dizin hata)
- Kaynak sağlama toplamı (AC-4.2): `cd exercises/source && shasum -a 256 -c SHA256SUMS`
- Kalibrasyon raporu: `swift run --package-path Packages/SoloCalibrate solo-calibrate report --files fixtures/recordings/<şablon> [--rules exercises] [--exercise <id>] [--sweep <yol>=<v1>,<v2>]` (etiketli `*.json` diziler; şablonlar `--rules` dizininden `<id>.json`)
- Uygulama testleri (macOS): `xcodebuild test -project GymSpotSolo.xcodeproj -scheme GymSpotSolo -destination 'platform=iOS Simulator,name=…' CODE_SIGNING_ALLOWED=NO`
- Paket testleri (iOS paketleri): `cd Packages/<Paket> && xcodebuild test -scheme <Paket> -destination 'platform=iOS Simulator,name=…'`
- Release ikili kontrolü (AC-2.3, AC-2.5): `scripts/ci/check-release-binary.sh <derived-data-dizini>`
- Anlık görüntüleri güncelleme (yalnız spec değişikliğiyle): `UPDATE_SNAPSHOTS=1 swift test …`

## Proje yapısı notları
- İki uygulama hedefi aynı `App/` kaynaklarını paylaşır: `GymSpotSolo` (Debug/Release, App Store) ve `GymSpotSoloBeta` (Beta, TestFlight; `SoloRecording` ve `RECORDING_MODE` yalnız burada) — `specs/02` "Derleme yapılandırmaları".
- `App/` ve `AppTests/` Xcode'da senkron klasördür: yeni dosya eklemek için `project.pbxproj` düzenlenmez.
- Bundle kimliği `com.gymspot.solo` yer tutucudur; ürün adıyla birlikte kesinleşir (`specs/00` açık soru 2).

## Araç notları
- Node/TypeScript yalnız `tools/golden-export` içindir ve bir kez çalıştırılır (`specs/03`); CI ve derlemede yoktur.
- Swift Package bağımlılığı eklemek `specs/10`'da gerekçelendirilmeden yapılmaz.
- Claude Code bulut oturumunda (Linux) yalnız `SoloEngine` ve `SoloCalibrate` görevleri tam yapılabilir; Xcode, Vision, kamera ve cihaz gerektiren görevler Mac'te yürütülür.

## Dil
Kod ve tanımlayıcılar İngilizce; spec'ler ve kullanıcıya görünen metinler Türkçe ve İngilizce (String Catalog, varsayılan sistem dili).
