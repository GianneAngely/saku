# Sambungkan Google Tasks ke Saku

Tab **To-do** di Saku langsung bisa dipakai sebagai daftar tugas di Mac ini. Biar tugasnya sinkron dua arah dengan Google Tasks (dan aplikasi Tasks di HP Android), Saku butuh **OAuth client milikmu sendiri** dari Google Cloud. Gratis, sekali bikin, kira-kira 10 menit.

Kenapa harus bikin sendiri? Saku tidak punya server dan tidak membawa kunci Google siapa pun. Kamu yang membuat "pintu masuk" ke akun Google-mu, Saku cuma memakainya di Mac ini. Saku hanya minta izin untuk **Google Tasks**, bukan email, Drive, atau yang lain.

> Masuk ke Google Cloud dengan akun Google yang tugasnya mau disinkronkan. Kalau tampilan console-nya sedikit beda dari panduan ini, cari menu **Google Auth Platform** di sebelah kiri.

## 1. Buat project

1. Buka <https://console.cloud.google.com/projectcreate>.
2. **Project name**: `Saku`. Lokasi biarkan "No organization".
3. Klik **Create**, lalu pastikan project `Saku` terpilih di bagian atas halaman.

## 2. Nyalakan Google Tasks API

1. Buka <https://console.cloud.google.com/apis/library/tasks.googleapis.com>.
2. Pastikan project `Saku` terpilih, lalu klik **Enable**.

## 3. Atur layar izin (OAuth consent screen)

1. Buka <https://console.cloud.google.com/auth/overview> lalu klik **Get started**.
2. **App name**: `Saku`. **User support email**: pilih email kamu.
3. **Audience**: pilih **External** (akun Gmail biasa selalu External).
4. **Contact information**: email kamu. Centang persetujuan, lalu **Create**.
5. Buka <https://console.cloud.google.com/auth/scopes> (Data Access) › **Add or remove scopes**, cari `Google Tasks API`, centang `.../auth/tasks`, lalu **Update** dan **Save**.

## 4. Pilih mode: Testing atau In production

Buka <https://console.cloud.google.com/auth/audience>.

| | Testing | In production (tanpa verifikasi) |
| --- | --- | --- |
| Siapa yang bisa masuk | Cuma akun yang kamu daftarkan sebagai **Test users** | Akun Google mana pun |
| Masa berlaku izin di Saku | **Habis tiap 7 hari**: tiap minggu harus masuk lagi | Awet sampai kamu mencabutnya |
| Layar peringatan | Tidak ada | Muncul sekali saat masuk: "Google belum memverifikasi aplikasi ini" |
| Verifikasi Google | Tidak perlu | Tidak perlu untuk pemakaian pribadi (batasnya 100 pengguna) |

**Rekomendasi: In production tanpa verifikasi.** Untuk dipakai sendiri, ini yang paling nyaman: sekali masuk, sinkronnya jalan terus. Layar peringatannya cuma muncul sekali, karena aplikasinya buatanmu sendiri dan belum ditinjau Google, dan itu aman.

- Mau **In production**: klik **Publish app** › **Confirm**. Tidak usah ajukan verifikasi.
- Mau tetap **Testing**: di bagian **Test users** klik **Add users**, masukkan email Google kamu. Ingat, tiap 7 hari Saku akan minta kamu masuk lagi.

## 5. Buat OAuth client tipe Desktop

1. Buka <https://console.cloud.google.com/auth/clients/create>.
2. **Application type**: **Desktop app**. **Name**: `Saku Mac`.
3. Klik **Create**, lalu **Download JSON** di jendela yang muncul (atau ikon unduh di daftar client). Namanya mirip `client_secret_123….apps.googleusercontent.com.json`.

File ini rahasia kecil milikmu: jangan dikirim ke orang lain atau diunggah ke GitHub.

## 6. Masukkan ke Saku

Pilih salah satu:

- **Paling gampang:** Saku › Pengaturan › **To-do** › **Impor JSON client…**, lalu pilih file yang barusan diunduh.
- **Manual:** ganti nama filenya jadi `google-oauth.json`, lalu taruh di folder Saku. Di Finder: menu **Go › Go to Folder…**, ketik `~/Library/Application Support/Saku/`, lalu pindahkan filenya ke sana.
- **Tanpa file:** di Pengaturan › To-do buka "Atau tempel client ID dan secret", tempel **Client ID** dan **Client secret** dari halaman client, lalu **Simpan**.

## 7. Masuk dengan Google

1. Pengaturan › To-do › **Masuk dengan Google**. Browser kamu terbuka.
2. Pilih akun Google kamu.
3. Kalau muncul **"Google belum memverifikasi aplikasi ini"**: klik **Lanjutan** (Advanced) › **Buka Saku (tidak aman)**. Ini muncul karena aplikasinya buatanmu sendiri.
4. Izinkan **Lihat, edit, buat, dan hapus semua tugas Anda**, lalu **Lanjutkan**.
5. Tab browser bilang "Saku is connected to Google Tasks". Tutup tabnya. Di Saku statusnya jadi **Tersambung ke Google Tasks** dan daftar tugasmu muncul di tab To-do.

## Kalau ada masalah

- **"Sign-in timed out"**: browser tidak kembali ke Saku dalam 5 menit. Klik Masuk lagi.
- **"Error 403: access_denied"**: aplikasimu masih mode Testing dan akunmu belum ada di Test users (langkah 4).
- **Tiap minggu disuruh masuk lagi**: aplikasimu masih mode Testing. Publish ke In production (langkah 4), lalu masuk sekali lagi.
- **Mau putus**: Pengaturan › To-do › **Keluar**. Saku mencabut izinnya di Google, tugas di Google tetap aman. Bisa juga dicabut dari <https://myaccount.google.com/connections>.

## Yang Saku simpan

- Token masuk: di **Keychain** macOS.
- File client: di `~/Library/Application Support/Saku/google-oauth.json` (tidak ada di aplikasi atau di repo).
- Salinan tugas untuk dipakai offline: `~/Library/Application Support/Saku/todo.json`. Perubahan saat offline ikut terkirim begitu internet kembali.
