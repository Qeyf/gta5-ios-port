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
