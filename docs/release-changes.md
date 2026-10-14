
## 1.3.4 — Değişiklikler / Changes

**Türkçe**

- Hileleri giriş başlamadan reddeden yanlış bellek hizalama kontrolü düzeltildi. Konsol ve gamepad girişleri, çalışan referans sürümün zamanlamalarını korur; Türkçe ve İngilizce hile arayüzü devam eder.
- Uygun BC dokuları, destekleyen GPU’larda sıkıştırılmış biçimde yüklenir. CPU’da gereksiz doku açma ve büyük GPU kopyaları azaltılır; uyumsuz cihaz ve dokular mevcut yazılım yolunu kullanır.
- Yoğun motor logları, açık tutulan dosyaya arka planda toplu yazılır. Dokunmatik giriş ve arayüz her log satırı için beklemez.
- Tam ekran menüler dahil, sahne devre dışıyken Metal gönderimleri durdurulur ve geri dönüşte bekleyen işler devam eder.
- Bellek baskısında yalnızca GPU işi tamamlanmış, kullanılmayan yükleme tamponları bırakılır. Metal bellek kullanımı, sıcaklık durumu ve hile girişinin hangi aşamada olduğu loglara eklenir.

**English**

- Fixed the incorrect input-block alignment check that rejected cheats before injection started. Console and gamepad timing matches the working reference; Turkish and English cheat UI remains supported.
- Eligible BC textures stay compressed on capable GPUs, avoiding unnecessary CPU decoding and expanded GPU textures. Unsupported devices and texture configurations retain the software fallback.
- Engine diagnostics use batched background writes through a persistent file handle instead of per-line main-thread file I/O.
- Scene deactivation suspends Metal submissions, including when full-screen menus are open; pending work resumes on activation.
- Memory pressure reclaims only unused upload buffers whose GPU work has completed. Logs now expose Metal allocations, thermal state and cheat submission stages.

FPS gains depend on the device, scene and thermal conditions. The build does not claim physical-device gameplay or in-game cheat acceptance testing.
