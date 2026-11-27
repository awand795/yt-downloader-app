# TubeGrab — YouTube Downloader (Flutter, Android)

Aplikasi Android untuk mengunduh video YouTube dengan pilihan format:

- **Video + Audio** — video HD/4K, audio otomatis digabung dengan FFmpeg menjadi satu berkas (MP4/MKV).
- **Video saja** — berkas gambar tanpa trek suara, untuk diedit ulang.
- **Audio saja** — M4A kualitas asli atau MP3 128/192/320 kbps.

Unduhan disimpan ke folder **Download/TubeGrab**, lengkap dengan riwayat, progres, ETA, dan tombol buka/bagikan/hapus.

## Cara kerja

Aplikasi menjalankan **yt-dlp** asli di dalam perangkat (bukan API server pihak ketiga):

| Lapisan | Peran |
| --- | --- |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Bridge `MethodChannel`: inisialisasi yt-dlp + FFmpeg, `analyze` (`--dump-single-json`), `download` (argumen `-f` pilihan), progres via `EventChannel`, batal, simpan ke MediaStore, buka/bagikan/hapus. |
| `lib/models/video_info.dart` | Parsing JSON yt-dlp (format, codec, resolusi, ukuran). |
| `lib/models/download_options.dart` | Menyusun pilihan kualitas: mengelompokkan per resolusi, memilih H.264/MP4 bila tersedia, menyusun selector `video+audio`, dan opsi MP3/M4A. |
| `lib/services/download_manager.dart` | Antrean satu unduhan aktif, progres dua fase (video lalu audio), publikasi ke folder Download, riwayat persisten. |
| `lib/screens/` | Beranda (input tautan, status mesin, riwayat) dan layar hasil (pemilih mode + kualitas). |

yt-dlp diperbarui otomatis (maksimal sekali per 12 jam) agar tetap kompatibel saat YouTube berubah. Ini penting karena sejak 2026 YouTube mewajibkan PO Token: ekstraktor berbasis Dart murni tidak lagi bisa mengunduh penuh.

## Menjalankan

```bash
flutter pub get
flutter run -d <device-id>
```

Persyaratan: Flutter 3.47+, Android SDK 36, `minSdk 24`.

## Build APK

```bash
flutter build apk --release --split-per-abi
```

Hasil di `build/app/outputs/flutter-apk/`:

- `app-arm64-v8a-release.apk` — untuk hampir semua HP modern (disarankan)
- `app-armeabi-v7a-release.apk` — perangkat 32-bit lama
- `app-x86_64-release.apk` — emulator

APK berukuran besar (±52–66 MB) karena membawa Python + yt-dlp + FFmpeg di dalamnya.

Catatan build:

- Release ditandatangani dengan debug keystore. Ganti dengan keystore sendiri sebelum dipublikasikan.
- Minifikasi R8 dimatikan (`isMinifyEnabled = false`) karena `youtubedl-android` memuat kelas via reflection; obfuscation membuat mesin gagal start.
- `kotlin.incremental=false` di `android/gradle.properties` untuk menghindari bug cache Kotlin ketika cache pub dan proyek berada di drive berbeda.

## Pengujian

```bash
flutter test                                                    # unit + widget (tanpa perangkat)
flutter test integration_test/download_flow_test.dart -d <dev>  # butuh jaringan + perangkat/emulator
```

Integration test mengunduh audio, pasangan video+audio hasil merge, dan video tanpa audio dari video uji nyata, lalu memastikan berkas tersimpan.

## Batasan yang diketahui

- YouTube kadang memunculkan verifikasi "Sign in to confirm you're not a bot" bila terlalu banyak unduhan datang dari IP yang sama. Pesan asli yt-dlp ditampilkan di kartu unduhan; pengguna dapat mengimpor berkas `cookies.txt` (format Netscape) lewat menu Mesin unduhan untuk melanjutkan.
- Kualitas di atas 1080p (4K/8K) butuh perangkat yang sanggup memutar codec-nya (VP9/AV1) karena hasil merge memakai wadah MP4.
- Satu unduhan berjalan pada satu waktu; unduhan berikutnya menunggu yang aktif selesai.

## Catatan hukum

Gunakan hanya untuk konten yang Anda miliki haknya atau yang lisensinya mengizinkan unduhan. Mengunduh video YouTube pihak ketiga melanggar Ketentuan Layanan YouTube. Proyek ini tidak berafiliasi dengan YouTube.
