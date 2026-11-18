# PC Sağlık ve Güncellik Kontrolü

Windows 10/11 için tek tıkla çalışan bir sağlık kontrol programı. Bilgisayarını tarar, sonucu renkli bir HTML rapor olarak tarayıcıda açar ve masaüstüne kaydeder. Raporun en üstünde önem sırasına göre bir **Yapılacaklar** listesi bulunur.

NVIDIA, AMD ve Intel; masaüstü ve laptop fark etmeksizin çalışır. Ek bir program kurmak gerekmez.

## Kullanım

1. Depoyu indir (**Code → Download ZIP**) ve bir klasöre çıkar.
2. **`Kontrol-Et.bat`** dosyasına çift tıkla.
3. Yönetici izni istenince **Evet** de.
4. 1-2 dakika sonra rapor tarayıcıda açılır.

> Windows "Bilgisayarınız korundu" uyarısı verirse **Ek bilgi → Yine de çalıştır** seç.

## Neleri kontrol eder?

| Bölüm | Kontroller |
|---|---|
| **RAM** | Doluluk, takılı modüller, çift kanal, XMP / EXPO açık mı, en çok RAM kullanan programlar |
| **Ekran kartı** | Sürücü yaşı, monitörler en yüksek Hz'de mi; NVIDIA'da sıcaklık, yük, VRAM |
| **Güncellik** | Windows Update (bekleyen güncellemeler ve sürücüler), BIOS yaşı, AMD / Intel chipset sürücüsü, bekleyen yeniden başlatma |
| **Diskler** | Sağlık durumu, sıcaklık, aşınma, okuma hataları, boş alan |
| **Kararlılık** | Son 30 gündeki mavi ekranlar, beklenmedik kapanmalar, WHEA donanım hataları, sorunlu aygıtlar |
| **Oyun ayarları** | Oyun Modu, donanım hızlandırmalı GPU zamanlaması, pencereli oyun iyileştirmeleri, arka plan kaydı, güç modu, bellek bütünlüğü |
| **Başlangıç** | Açılışta başlayan programlar |
| **Pil** | Laptoplarda pil sağlığı ve şarj durumu |
| **Güvenlik** | Windows Defender, virüs tanımları, son tarama, Secure Boot |

## Ayarlar

`PC-Saglik-Kontrol.ps1` dosyasının başındaki iki değeri değiştirebilirsin:

- `$DriverMaxAgeMonths = 4`: Ekran kartı sürücüsü bundan eskiyse uyarı verir.
- `$BiosMaxAgeMonths = 24`: BIOS bundan eskiyse uyarı verir.

## Komut satırından çalıştırma

```powershell
powershell -ExecutionPolicy Bypass -File .\PC-Saglik-Kontrol.ps1 [-NoOpen] [-SkipWindowsUpdate] [-NoPause]
```

- `-NoOpen`: Raporu tarayıcıda açmaz.
- `-SkipWindowsUpdate`: Windows Update taramasını atlar (daha hızlı).
- `-NoPause`: Sonda Enter beklemez.

## Notlar

- Program internetten "en son sürüm" bilgisi çekmez. Ekran kartı, chipset ve BIOS için kurulu sürümün **tarihine** bakar ve eskiyse üreticinin indirme sayfasına bağlantı verir. Windows güncellemeleri ise doğrudan Windows Update'e sorularak kontrol edilir.
- Hiçbir ayarı değiştirmez, sadece okur.
- Yönetici olarak çalıştırılmazsa disk sağlığı ve Secure Boot gibi bazı bilgiler eksik kalır.
