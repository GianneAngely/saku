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

## 4. Pilih mode: In production atau Testing

Buka <https://console.cloud.google.com/auth/audience>.

| | In production (tanpa verifikasi) | Testing |
| --- | --- | --- |
| Syarat | **Branding** lengkap: home page, privacy policy, dan authorized domain milikmu sendiri | Email-mu di **Test users** |
| Siapa yang bisa masuk | Akun Google mana pun (maksimal 100 orang) | Cuma akun di **Test users** (maksimal 100) |
| Masa berlaku izin di Saku | Awet sampai kamu mencabutnya | **Habis 7 hari** setelah kamu masuk |

Punya halaman web sendiri? Pakai **In production**: sekali masuk, awet. Belum punya? Pakai **Testing**, lalu masuk lagi tiap 7 hari.

### In production

Google baru mengizinkan **Publish app** kalau Branding sudah berisi home page, privacy policy, dan domainnya. Semuanya harus milikmu sendiri, karena authorized domain terdaftar per project dan kamu pengelola aplikasi di project-mu. Jadi jangan pakai alamat situs Saku: alamat itu cuma untuk project pembuat Saku.

1. Siapkan dua halaman di domain milikmu, misalnya gratis di GitHub Pages: beranda yang menjelaskan aplikasinya, dan kebijakan privasi yang menjelaskan cara data Google Tasks dipakai. Sebagai contoh, lihat [kebijakan privasi Saku](https://gianneangely.github.io/saku-site/id/privacy.html).
2. Buka <https://console.cloud.google.com/auth/branding>. Di **Authorized domains** klik **Add domain**, lalu isi domainmu. Isi ini dulu, sebelum link-link di bawah.
3. Isi **Application home page** dan **Application privacy policy link** dengan alamat dua halaman tadi. **Application terms of service link** boleh diisi kalau kamu punya.
4. **App logo** biarkan kosong, karena logo membuat Google mewajibkan verifikasi. Klik **Save**.
5. Kembali ke <https://console.cloud.google.com/auth/audience>, klik **Publish app** › **Confirm**.

Setelah itu muncul banner "Your app requires verification". Biarkan saja dan tidak usah ajukan verifikasi, karena untuk dipakai sendiri tidak perlu. Akibatnya cuma dua: saat masuk ada layar peringatan (langkah 7), dan aplikasimu dibatasi 100 pengguna.

**Sudah terlanjur masuk waktu masih Testing?** Izin lama itu tetap habis di hari ke-7. Masuk sekali lagi setelah Publish (atau tunggu Saku memintanya), setelah itu awet.

### Testing

1. Di bagian **Test users** klik **Add users**.
2. Masukkan email Google yang tugasnya mau disinkronkan, lalu **Save**.

Izinnya habis 7 hari setelah kamu masuk. Kalau sudah habis, Pengaturan › To-do menulis **Google minta kamu masuk lagi**: klik **Masuk dengan Google** (langkah 7). Tugasmu tetap aman: salinannya ada di Mac, dan perubahan selama itu ikut terkirim begitu kamu masuk lagi.

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
3. Muncul **"Google belum memverifikasi aplikasi ini"**: klik **Lanjutan** (Advanced) › **Buka Saku (tidak aman)**. Ini muncul karena aplikasinya buatanmu sendiri dan belum ditinjau Google, dan cukup sekali tiap kamu masuk. Di mode Testing layarnya sedikit beda: tinggal klik **Lanjutkan** (Continue).
4. Izinkan **Lihat, edit, buat, dan hapus semua tugas Anda**, lalu **Lanjutkan**.
5. Tab browser bilang "Saku is connected to Google Tasks". Tutup tabnya. Di Saku statusnya jadi **Tersambung ke Google Tasks** dan daftar tugasmu muncul di tab To-do.

## Kalau ada masalah

- **"Sign-in timed out"**: browser tidak kembali ke Saku dalam 5 menit. Klik Masuk lagi.
- **"Error 403: access_denied"**: aplikasimu masih mode Testing dan akunmu belum ada di Test users (langkah 4).
- **"Google minta kamu masuk lagi"**: izin dari Google habis atau dicabut. Di mode Testing ini terjadi tiap 7 hari: Publish ke In production (langkah 4), lalu masuk sekali lagi. Di In production, ini cuma terjadi kalau aksesnya dicabut atau Saku 6 bulan tidak dipakai. Klik **Masuk dengan Google** lagi.
- **Mau putus**: Pengaturan › To-do › **Keluar**. Saku mencabut izinnya di Google, tugas di Google tetap aman. Bisa juga dicabut dari <https://myaccount.google.com/connections>.

## Data yang Saku simpan

- Token masuk: di **Keychain** macOS.
- File client: di `~/Library/Application Support/Saku/google-oauth.json` (tidak ada di aplikasi atau di repo).
- Salinan tugas untuk dipakai offline: `~/Library/Application Support/Saku/todo.json`. Perubahan saat offline ikut terkirim begitu internet kembali.

Kebijakan privasi lengkapnya ada di <https://gianneangely.github.io/saku-site/id/privacy.html>.
