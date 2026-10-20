# Sunucu Durum

Sunucunun durumunu (kaynaklar, konteynerler, servisler, yedekler, VPN) macOS menü çubuğunda gösteren küçük bir uygulama.

1. `ayar.ornek.json` dosyasını `~/Library/Application Support/Sunucu Durum/ayar.json` olarak kopyalayıp kendi sunucuna göre düzenle.
2. Ayardaki ssh adı `~/.ssh/config` içinde tanımlı olmalı ve anahtarla şifresiz giriş yapılabilmeli.
3. `./paketle.sh` ile derleyip kur.

Klavyedeki parlaklık tuşları, fare imlecinin bulunduğu harici ekranın parlaklığını DDC/CI ile (DDC desteklemeyen ekranlarda yazılımsal karartmayla) değiştirir; bunun için uygulamaya Gizlilik ve Güvenlik > Erişilebilirlik bölümünden izin verilmelidir. MonitorControl açıksa kapatılmalıdır, çünkü parlaklık tuşlarını o yakalar.
