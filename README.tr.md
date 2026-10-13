# GtaV Mobile

[English](README.md) · **Türkçe**

Bu depo, [kevinerikjs/gta5-ios-port](https://github.com/kevinerikjs/gta5-ios-port)
projesinin Qeyf hesabındaki forkudur. Kaynak v1.3.1 sürümüne dayanır; bu fork
1.3.2 sürümünü kullanır. Uygulama adı **GtaV Mobile**, çıktı dosyası
**`GtaV Mobile.ipa`** olur. Yerleşik ARM64 motoru, Metal görüntüleyicisi ve
mevcut kontrol sistemi korunur.

## Türkçe ve İngilizce

**Ayarlar › Dil › Uygulama dili** satırı uygulamanın iOS ayarlarını açar.
Burada tercih edilen dili **Türkçe** veya **English** olarak seçebilirsiniz.
İlk açılışta cihazın dili izlenir; iOS dil değişikliğini ve uygulamanın yeniden
açılmasını yönetir.

Ana ekran, grafik ayarları, kontrol düzenleyicisi, erişilebilirlik etiketleri,
dosya kurulum ekranları, indirme durumları, hatalar ve log paylaşma ekranları
Apple String Catalogs ile iki dile çevrilmiştir. Oyun motorunun ve kendi oyun
dosyalarınızdaki senaryo, diyalog ve menülerin dil desteği bu çeviri
kataloglarından bağımsızdır.

## Hile kodları

**Ayarlar › Hile kodları** altında 24 Hikâye modu hilesinin adlarını,
etkilerini, PC kodlarını ve oyun içi telefon numaralarını görebilirsiniz.
Arama ve kopyalama seçenekleri de iki dili destekler. Kodları çevirmek onları
geçersiz kılacağından kodlar ve numaralar aynı kalır.

Bu bölüm bir rehberdir: kopyalamak hileyi etkinleştirmez. Desteklendiğinde
karakterin oyun içindeki telefonunu veya fiziksel klavyeyle hile konsolunu
kullanın. Bazı hileler görev sırasında kullanılamayabilir. Hileler başarımları
geçici olarak kapatır; bir kaydı yeniden yüklemek veya oyunu yeniden başlatmak
hileleri sıfırlar.

## IPA derleme ve kurulum

Tam derleme için kendi oyun kopyanızın şu dosyaları gerekir:

- `b/8b0b5899ed/game.wasm`
- `data/manifest.json`
- `b/8b0b5899ed/shaders/` klasörü veya `shaders.zip`

Kaynak proje güvenlik gereği tam IPA derlemesini **özel (private) bir depo**
üzerinde çalıştırır. Bu açık forkta oyun motoru ve oyun verileri paylaşılmaz.
GitHub'da **Use this template › Create a new repository › Private** yoluyla
özel derleme kopyasını oluşturun. İngilizce README'deki dosya yükleme veya
Tailscale üzerinden derleme adımlarını uygulayın. Xcode proje ve şema adı
uyumluluk için `PlayGTA5Native` olarak kalır.

Apple Silicon Mac üzerinde:

```sh
./build_ipa.sh --mirror /oyun-klasorunun/yolu
./build_ipa.sh --mirror /oyun-klasorunun/yolu --paid
```

İkinci komut yalnızca ücretli Apple Developer hesabının ek bellek yetkileri
içindir. IPA imzasız üretilir; SideStore veya AltStore ile kendi hesabınızla
imzalayıp kurabilirsiniz.

Uygulamayı bir kez açtıktan sonra oyun klasörünü **Dosyalar › iPhone'umda ›
GtaV Mobile** içine taşıyın. Klasörde `data/` ve `b/` bulunmalıdır. Uygulama
dosyaları otomatik bulur; Hikâye modu veya Serbest mod seçip **Oyna**'ya dokunun.

## Doğrulama

**Verify GtaV Mobile UI and translations** GitHub Actions işi, oyun dosyaları
olmadan tüm Swift uygulama kodunu iOS SDK ile ve tüm çeviri kataloglarını
Apple araçlarıyla derler. Derleyicinin çıkardığı metin anahtarlarını
kataloglarla karşılaştırır. Bu kontrol tam oyun motoru/IPA derlemesinin
ve gerçek cihaz testinin yerine geçmez.

Apple kaynakları:

- https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog
- https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring

[İkon kaynağı](docs/asset-sources.md) · [MIT kod lisansı](LICENSE)
