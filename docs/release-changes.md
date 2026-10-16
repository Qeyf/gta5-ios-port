## 1.3.8 — Geliştirme / In development

**Türkçe**

- Grafik ayarlarına Apple MetalFX Kalite, MetalFX Performans ve Doğal çözünürlük seçenekleri eklendi. Seçilen çıkış çözünürlüğü korunur; iç render boyutu Kalite'de her eksende 2/3, Performans'ta 1/2 olur. Bu, yaklaşık %56 veya %75 daha az render pikselidir; FPS artışı ölçümü değildir. Desteklenmeyen GPU'lar doğal çözünürlüğü kullanır. Ayarlar giriş ve çıkış boyutunu Türkçe/İngilizce gösterir.
- Yükseltme mevcut Metal komut akışında Apple'ın `MTLFXSpatialScaler` API'sini kullanır; çözünürlük geçişleri veya oluşturma başarısızlığı için `MPSImageBilinearScale` yolu bulunur. Kare üretimi eklenmez. Görüntü ve oyun arayüzü birlikte yükseltilir; doğal çözünürlük tam boyutta render seçeneğidir.
- GPU'da sıkıştırılmış BC dokularının her mip seviyesi için RAM'de tutulan kalıcı ikinci kopya kaldırıldı. Yerel BC kopyaları ve okumaları sıralı GPU blit işlemleriyle yapılır; CPU ile çözülen eski cihaz yolu asıl blokları saklamaya devam eder. RAM kazancının miktarı henüz cihazda ölçülmedi.
- Aynı vertex düzeni yeni nesne kimliğiyle tekrar oluşturulduğunda aynı Metal pipeline'ının yeniden derlenmesi önlendi. Önbellek gerçek düzen ve vertex imza içeriğini paylaşır; farklı eşlemeler, tampon stride değerleri ve render durumları ayrı kalır. Tekrar kullanım sayaçları günlüğe eklenmiştir.
- Sağlanan normal/düşük profil kayıtlarından 502 Metal ön derleme tarifi oluşturuldu. Yüklemede gerçek motor shader imzaları geldikçe, boş komut kuyruğunda bekleyen derleme sayısı ikiden azsa ön derleme işi eklenir; ilk yoğun oyun karesinde veya bellek/ısı baskısında yeni işler durdurulur. Normal çizim talepleri bu sınırı beklemez ve aynı önbelleği kullanır. Düşük profil grafik ayarlarının yerine geçirilmez; cihazda takılma/FPS kazancı henüz ölçülmedi.
- Günlükte tamamlanmış bir karenin ilk GPU başlangıcından son GPU bitişine kadar olan aralık ayrıca ölçülür. Komut tamponu ortalamasıyla karıştırılmaz; tamponlar arası boşlukları içerir ve GPU doluluk ölçümü değildir. Sıra dışı callback, eksik zaman damgası ve arka plan geçişleri için testler eklendi.
- GitHub Actions kotası kullanmayan yerel `nektos/act` kontrolleri ve Mac IPA tarifi eklendi. Linux'ta taşınabilir testler geçti; bu sürüm henüz Apple SDK ile derlenmedi, GPU'da veya iPhone'da doğrulanmadı ve yayımlanmadı. Kararlı 120 FPS iddiası yoktur.

**English**

- Added Apple MetalFX Quality, MetalFX Performance and Native resolution choices. Preserve selected output resolution while rendering at 2/3 or 1/2 of each dimension: approximately 56% or 75% fewer rendered pixels, not a measured FPS gain. Unsupported GPUs retain native rendering. EN/TR settings show input and output sizes.
- Encode Apple's `MTLFXSpatialScaler` in the existing Metal command stream, with `MPSImageBilinearScale` for resolution transitions or scaler creation failure. No frame generation. Scene and game UI are upscaled together; Native remains the full-resolution option.
- Remove permanent CPU duplicates of native BC texture mip data. Native copies/readbacks use ordered GPU blits; CPU-decoded fallback textures retain original blocks. Actual device memory savings remain unmeasured.
- Reuse actual input-layout/vertex-signature contents across recreated engine objects instead of compiling another identical Metal pipeline for each new object ID. Preserve distinct signatures, buffer strides and render state; expose session cache counters.
- Convert supplied normal/low-profile recordings into 502 native warmup recipes. During idle loading, use real engine shader signatures and add speculative work only when fewer than two render compiles are pending. Demand misses remain unrestricted. Stop new startup jobs at the first world-sized frame or memory/thermal pressure; actual draws share the same cache. Preserve graphics settings. Device stutter/FPS benefit remains unmeasured.
- Report completed first-GPU-start to last-GPU-end frame intervals separately from average command-buffer duration. This includes inter-buffer gaps and is not GPU occupancy. Tests cover out-of-order/concurrent handlers, incomplete timestamps and foreground transitions.
- Add local `nektos/act` checks and a Mac IPA recipe without hosted Actions minutes. Portable checks passed on Linux. This development version has not been compiled with Apple's SDK, executed on an Apple GPU or tested on iPhone, and is not released. No sustained 120 FPS claim.

## 1.3.7 — Değişiklikler / Changes

**Türkçe**

- Karakter hazır olduğu hâlde dokunmatik kontrolleri sürekli gizleyen yükleme denetimi düzeltildi. Bazı Serbest Mod açılışlarında açık kalan “ilk yükleme” işareti yerine motorun gerçek etkin yükleme ekranı durumu kullanılır. İlk yükleme, ara sahne ve karakterin bulunmadığı durumlar için denetimler korunur.
- Motor, render ve ses iş parçacıklarının farklı bellek adreslerinde beklerken tek bir kilitte sıraya girmesi azaltıldı. Adrese göre ayrılmış bekleme kuyrukları, aynı adres için bildirim sayısını ve zaman aşımı davranışını korur.
- Günlükler dokunmatik kontrollerin hangi koşul nedeniyle gizlendiğini yalnızca durum değiştiğinde kaydeder. Böylece yükleme, bağlı oyun kumandası ve klavye/fare tercihi ayırt edilebilir.
- Arayüz testi artık gerçek yükleme denetimini ve Serbest Mod'da kalıcı olabilen işareti birlikte sınar. Yerel motor testleri farklı ve çakışan adreslerde 32/64 bit beklemeleri de kapsar.

**English**

- Correct the loading check that could keep touch controls hidden after the player was ready. Use the engine's active loading-screen context instead of the initial-loading marker, which can remain set after Sandbox startup. Initial loading, cutscene and missing-player protections remain.
- Reduce contention between unrelated engine, renderer and audio waits by separating wait queues by backing address. Exact notification counts and timeout behavior for the same address are retained.
- Log touch visibility causes only on transitions, distinguishing loading, connected controllers and keyboard/mouse preferences.
- UIKit tests now exercise the production loading snapshot with the persistent Sandbox marker; native runtime checks cover independent and colliding addresses with both 32-bit and 64-bit waits.

The supplied 1.3.6 device log requests 120 Hz correctly and records world windows at 81.6 and 63.8 FPS. The wait-queue optimization has a targeted concurrency regression and a host microbenchmark, not a measured iPhone FPS uplift. Sustained 120 FPS still requires device verification. Game Mode, ProMotion support, bounded CPU concurrency and device-local game files remain enabled.

## 1.3.6 — Değişiklikler / Changes

**Türkçe**

- Konsol hilelerinin harfleri artık yalnızca metin kuyruğuna yazılır. RAPIDGT ve PAINKILLER içindeki I harfinin motorun uçuş kısayolunu tetikleyerek karakteri sürüklemesi önlenir; konsolu açma ve onaylama tuşları korunur.
- Dokunmatik kontroller, yükleme ekranı kapandığında ve yerel karakter yönetilebilir olduğunda açılır. Grafik işlem hatlarının derlenmesini beklemez; yükleme, ara sahne ve karakterin bulunmadığı durumlarda gizlenir.
- Oynat’a basılmadan değiştirilen FPS seçimi ekran yenileme isteğine de uygulanır. Sınırsız/120 Hz seçimi, ekranın desteklediği üst hızı ister; 30/60 seçimine geri dönüldüğünde önceki istek sıfırlanır.
- Altı veya daha fazla etkin işlemci çekirdeği olan cihazlarda motorun eşzamanlılık bütçesi 2’den 4’e çıkarılır. Bağımlılık, oyun ve kumaş zamanlayıcıları bir yerine ikişer çalışan kullanabilir. Bağımsız iş havuzlarının aşırı büyümesini sınırlamak için tüm donanım çekirdekleri motora verilmez. Donanım sayısı ve motor bütçesi günlükte ayrı gösterilir.
- Güncel iOS Game Mode bildirim anahtarı eklendi; eski sistem desteği korunur.
- Üretim sürümünde ham günlük/JSON konsolu gösterilmez. Tamamlanmayan açılış sonrası kısa bir kurtarma iletisi gösterilir; doğrulanmamış bellek yetersizliği iddiası kaldırıldı. Günlükler isteğe bağlı paylaşılabilir.
- Aynı rapor devam ederken farklı bir ekrandan ikinci gönderim başlatılamaz. Not, geçerli ve önceki günlükler tek istekte gönderilir. Önceki fazladan üç ileti kurulum testleriydi; bu sürümün testleri gerçek e-posta göndermeden çalışır.

**English**

- Console cheat letters now use only the text queue. I in RAPIDGT/PAINKILLER no longer presses the engine's flight hotkey and causes character sliding; console open/submit key edges are retained.
- Touch controls appear once loading screens close and a local player is controllable, independently of graphics pipeline compilation. Loading, cutscenes and missing-player states hide them.
- Apply the current Home frame-cap choice to the display link again at Play. Unlocked requests the screen's supported maximum refresh rate; returning to 30/60 clears the earlier request.
- On devices with at least six active CPUs, raise the engine concurrency budget from 2 to 4. Dependency, game and cloth schedulers can use two workers each instead of one, without the larger independent-pool expansion caused by advertising all hardware cores. Logs distinguish hardware count from engine budget.
- Declare Game Mode eligibility with the current iOS key while keeping compatibility with older systems.
- Shipping builds cannot display the raw startup log/JSON console. Unfinished-launch recovery uses a short neutral message, with explicit log sharing and no unverified out-of-memory claim.
- One app-wide upload guard prevents overlapping submissions across report screens. The note and current/previous logs remain one request. The earlier three extra emails were setup tests; this release's tests use a local mocked transport only.

The supplied device logs used a 60 FPS cap. These changes remove verified scheduling/input/startup obstacles; sustained 120 FPS and the CPU-budget benefit still require a fresh physical-device run in the same combat/crowd route. No fixed FPS is claimed. Existing device-local game files remain supported.

## 1.3.5 — Değişiklikler / Changes

**Türkçe**

- Günlük gönderimi, bu projenin Cloudflare servisine taşındı. Alıcı e-posta adresi yalnızca sunucuda tutulur; uygulamada gösterilmez ve IPA içine konmaz. Geçerli ve önceki loglar arka planda okunur; başarı yalnızca e-posta servisi raporu kabul edince bildirilir.
- Yerel oyun dosyalarında, sunucu önbelleğini doldurmayan gereksiz ön okuma işleri ve geçici 1 MiB kopyalar kaldırıldı. Asıl oyun okumaları ve sunucudan akış önbelleği korunur.
- Otomatik hile girişi konsolu kullanır; böylece hile dizisinin araçtan inme veya saldırı tuşlarına dönüşmesi önlenir. Açıkça seçilen Gamepad yöntemi normal oyun tuşlarını göndermeye devam eder.
- Menü ve hile geçişlerinde bekleyen dokunma darbeleri, kısa basış süreleri ve radyo yönü temizlenir. Oyun kontrolleri, dünya ve yönetilebilir karakter hazır olduğunda görünür; yükleme ve ara sahnelerde gizlenir.
- Jiroskopta sensör zaman damgalarıyla çalışan süzme, güncel örnek okuma ve ayrı bir yumuşak giriş eğrisi kullanılır. Menüden veya arka plandan dönüşte eski hareket birikimi oynatılmaz.
- Loglara gerçek sunulan kare aralıkları, p50/p95/p99, GPU komut süresi ve bekleme nedenleri eklendi. Arka plan süresi bu ölçüm pencerelerine katılmaz.

**English**

- Moved diagnostic uploads to this project's Cloudflare relay. The recipient is configured only on the server, never displayed or embedded in the IPA. Bounded current/previous logs are read off-main; success requires validated email-service acceptance.
- Removed redundant local-file prefetch jobs and temporary 1 MiB copies that could never populate the server-only cache. Authoritative demand reads and server streaming/cache behavior remain intact.
- Automatic cheats use console delivery to avoid synthesizing vehicle-exit or attack buttons. Explicit Gamepad mode retains ordinary controller sequences.
- Menu/cheat transitions clear queued touch pulses, minimum-press state and radio direction. Gameplay controls appear after the world and a controllable local player are ready, and hide during loading/cutscenes.
- Gyro input uses fresh processed samples, sensor-clock filtering and a dedicated continuous curve. Modal/background transitions discard stale motion instead of replaying it.
- Local logs report actual drawable presentation cadence, frame-time percentiles, completed GPU command durations and relevant waits. Background intervals are excluded.

Physical-device combat FPS, thermal behavior and gyro feel still require a fresh device run. This release does not promise a fixed 60 or 120 FPS. Existing device-local game files remain supported; embedding the same files in an IPA is not required for these fixes.
