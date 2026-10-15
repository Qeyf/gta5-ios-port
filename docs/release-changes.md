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
