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

## 4. Pakai mode Testing

Buka <https://console.cloud.google.com/auth/audience>.

| | Testing | In production (tanpa verifikasi) |
| --- | --- | --- |
| Syarat | Cukup daftarkan email-mu di **Test users** | **Branding** lengkap: home page, privacy policy, dan authorized domain |
| Siapa yang bisa masuk | Cuma akun di **Test users** (maksimal 100) | Akun Google mana pun (maksimal 100 orang selama belum diverifikasi Google) |
| Masa berlaku izin di Saku | **Habis 7 hari** setelah kamu masuk, lalu harus masuk lagi | Awet sampai kamu mencabutnya |

**Pakai Testing dulu.** Google baru mengizinkan **Publish app** kalau Branding sudah lengkap: alamat home page, alamat privacy policy, dan domain kedua halaman itu terdaftar di **Authorized domains**. Selama belum ada halaman web untuk dua alamat itu, Testing satu-satunya pilihan.

1. Di bagian **Test users** klik **Add users**.
2. Masukkan email Google yang tugasnya mau disinkronkan, lalu **Save**.

Di mode Testing, izin dari Google habis 7 hari setelah kamu masuk. Kalau sudah habis, Pengaturan › To-do menulis **Google minta kamu masuk lagi**: klik **Masuk dengan Google** (langkah 7). Tugasmu tetap aman: salinannya ada di Mac, dan perubahan selama itu ikut terkirim begitu kamu masuk lagi.

> **Catatan untuk nanti: pindah ke In production.** Biar tidak perlu masuk tiap 7 hari, Branding butuh halaman web dan privacy policy. Saku belum punya keduanya; rencananya dibuat di GitHub Pages saat Saku dirilis publik. Begitu ada (atau kalau kamu punya halaman web sendiri):
>
> 1. Di <https://console.cloud.google.com/auth/branding> isi **Application home page** dan **Application privacy policy link**, tambahkan domainnya di **Authorized domains**, lalu **Save**.
> 2. Di <https://console.cloud.google.com/auth/audience> klik **Publish app** › **Confirm**. Tidak usah ajukan verifikasi untuk dipakai sendiri.
> 3. Izin lama dari mode Testing tetap habis di hari ke-7. Setelah kamu masuk lagi, izin barunya awet.

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
3. Kalau muncul **"Google belum memverifikasi aplikasi ini"**: di mode Testing tinggal klik **Lanjutkan** (Continue). Kalau aplikasimu sudah In production, klik **Lanjutan** (Advanced) › **Buka Saku (tidak aman)**. Ini muncul karena aplikasinya buatanmu sendiri dan belum ditinjau Google.
4. Izinkan **Lihat, edit, buat, dan hapus semua tugas Anda**, lalu **Lanjutkan**.
5. Tab browser bilang "Saku is connected to Google Tasks". Tutup tabnya. Di Saku statusnya jadi **Tersambung ke Google Tasks** dan daftar tugasmu muncul di tab To-do.

## Kalau ada masalah

- **"Sign-in timed out"**: browser tidak kembali ke Saku dalam 5 menit. Klik Masuk lagi.
- **"Error 403: access_denied"**: aplikasimu masih mode Testing dan akunmu belum ada di Test users (langkah 4).
- **"Google minta kamu masuk lagi"**: di mode Testing ini normal, izinnya habis 7 hari setelah kamu masuk. Klik **Masuk dengan Google** lagi. Biar tidak berulang, lihat catatan In production di langkah 4.
- **Mau putus**: Pengaturan › To-do › **Keluar**. Saku mencabut izinnya di Google, tugas di Google tetap aman. Bisa juga dicabut dari <https://myaccount.google.com/connections>.

## Data yang Saku simpan

- Token masuk: di **Keychain** macOS.
- File client: di `~/Library/Application Support/Saku/google-oauth.json` (tidak ada di aplikasi atau di repo).
- Salinan tugas untuk dipakai offline: `~/Library/Application Support/Saku/todo.json`. Perubahan saat offline ikut terkirim begitu internet kembali.
