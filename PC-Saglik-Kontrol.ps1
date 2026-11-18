<#
    PC Sağlık ve Güncellik Kontrolü
    - RAM, CPU, ekran kartı (sıcaklık dahil), diskler, çökmeler, oyun ayarları
    - BIOS, chipset ve ekran kartı sürücüsü yaşı, Windows Update güncelliği, pil sağlığı
    Her Windows 10/11 bilgisayarda çalışır (NVIDIA / AMD / Intel).
    Sonuç: Masaüstüne HTML rapor kaydeder ve tarayıcıda açar.
    Yönetici olarak çalıştırmak için yanındaki "Kontrol-Et.bat" dosyasına çift tıkla.
#>
param([switch]$NoOpen, [switch]$SkipWindowsUpdate, [switch]$NoPause)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

# ---------------------------------------------------------------
#  AYARLAR
# ---------------------------------------------------------------
# Sürücü bu kadar aydan eskiyse "güncellenmeli" uyarısı verilir.
$DriverMaxAgeMonths = 4
# BIOS bu kadar aydan eskiyse üreticinin sitesine bakılması önerilir.
$BiosMaxAgeMonths   = 24

$Links = @{
    Nvidia     = 'https://www.nvidia.com/tr-tr/drivers/'
    AmdGpu     = 'https://www.amd.com/en/support/download/drivers.html'
    IntelGpu   = 'https://www.intel.com.tr/content/www/tr/tr/support/detect.html'
    AmdChipset = 'https://www.amd.com/en/support/download/drivers.html'
    IntelChip  = 'https://www.intel.com.tr/content/www/tr/tr/support/detect.html'
}
function Months-Old($date) { if (-not $date) { return $null }; return [int](((Get-Date) - $date).TotalDays / 30.4) }

$results = New-Object System.Collections.Generic.List[object]
function Add-Item {
    param([string]$Kategori, [string]$Baslik, [ValidateSet('ok','warn','bad','info')][string]$Durum, [string]$Deger, [string]$Oneri = '')
    $results.Add([pscustomobject]@{ Kategori = $Kategori; Baslik = $Baslik; Durum = $Durum; Deger = $Deger; Oneri = $Oneri })
}
function Step([string]$t) { Write-Host ("  > " + $t) -ForegroundColor Cyan }
function Fmt-GB([double]$bytes) { '{0:N1} GB' -f ($bytes / 1GB) }
function To-Version([string]$s) {
    $clean = ($s -replace '[^0-9\.]', '').Trim('.')
    $v = $null
    if ([version]::TryParse($clean, [ref]$v)) { return $v }
    return $null
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host '  PC Sağlık ve Güncellik Kontrolü' -ForegroundColor Green
Write-Host '  ----------------------------------' -ForegroundColor Green
if (-not $isAdmin) { Write-Host '  (Yönetici değil: disk sağlığı ve bazı kayıtlar eksik olabilir)' -ForegroundColor Yellow }

# ---------------------------------------------------------------
#  1. SİSTEM
# ---------------------------------------------------------------
Step 'Sistem bilgisi'
$os   = Get-CimInstance Win32_OperatingSystem
$cs   = Get-CimInstance Win32_ComputerSystem
$nt   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$osText = '{0} {1} (Derleme {2}.{3})' -f $os.Caption, $nt.DisplayVersion, $nt.CurrentBuild, $nt.UBR
Add-Item 'Sistem' 'İşletim sistemi' 'info' $osText

$uptime = (Get-Date) - $os.LastBootUpTime
$upText = '{0} gün {1} saat' -f [int][math]::Floor($uptime.TotalDays), $uptime.Hours
if ($uptime.TotalDays -gt 7) {
    Add-Item 'Sistem' 'Açık kalma süresi' 'warn' $upText 'Bir haftadan uzun süredir yeniden başlatılmamış. Yeniden başlatmak bellek ve güncelleme sorunlarını temizler.'
} else {
    Add-Item 'Sistem' 'Açık kalma süresi' 'ok' $upText
}

# ---------------------------------------------------------------
#  2. İŞLEMCİ
# ---------------------------------------------------------------
Step 'İşlemci'
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuLoad = [int]((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average)
Add-Item 'İşlemci' 'Model' 'info' ('{0} ({1} çekirdek / {2} iş parçacığı)' -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
if ($cpuLoad -ge 60) {
    Add-Item 'İşlemci' 'Anlık yük' 'warn' "%$cpuLoad" 'Oyun açık değilken yük yüksek. Aşağıdaki en çok kaynak kullanan programlara bak.'
} else {
    Add-Item 'İşlemci' 'Anlık yük' 'ok' "%$cpuLoad"
}

# ---------------------------------------------------------------
#  3. RAM
# ---------------------------------------------------------------
Step 'RAM'
$totalKB = [double]$os.TotalVisibleMemorySize
$freeKB  = [double]$os.FreePhysicalMemory
$usedPct = [int](100 * ($totalKB - $freeKB) / $totalKB)
$ramText = '%{0} dolu ({1} / {2})' -f $usedPct, (Fmt-GB (($totalKB - $freeKB) * 1KB)), (Fmt-GB ($totalKB * 1KB))
if ($usedPct -ge 85) {
    Add-Item 'RAM' 'Kullanım' 'bad' $ramText 'RAM neredeyse dolu, oyunlarda takılma yapar. Tarayıcı gibi büyük programları kapat.'
} elseif ($usedPct -ge 70) {
    Add-Item 'RAM' 'Kullanım' 'warn' $ramText 'Oyun açmadan önce tarayıcı ve gereksiz programları kapatmak iyi olur.'
} else {
    Add-Item 'RAM' 'Kullanım' 'ok' $ramText
}

$mods = @(Get-CimInstance Win32_PhysicalMemory)
if ($mods.Count -gt 0) {
    $modList = ($mods | ForEach-Object {
        '{0} {1} @ {2} MT/s ({3})' -f (Fmt-GB $_.Capacity), ($_.Manufacturer -replace '\s+$',''), $_.ConfiguredClockSpeed, ($_.PartNumber -replace '\s+$','')
    }) -join '<br>'
    Add-Item 'RAM' 'Modüller' 'info' $modList

    if ($mods.Count -eq 1) {
        Add-Item 'RAM' 'Çift kanal' 'warn' 'Tek modül (tek kanal)' 'Tek RAM ile çalışıyor. İki eş modül (çift kanal) oyunlarda FPS''i belirgin artırır. (Laptoplarda RAM lehimli olabilir.)'
    } else {
        Add-Item 'RAM' 'Çift kanal' 'ok' ('{0} modül takılı' -f $mods.Count)
    }

    $cfg   = ($mods | Measure-Object -Property ConfiguredClockSpeed -Minimum).Minimum
    $rated = ($mods | Measure-Object -Property Speed -Maximum).Maximum
    $memType = ($mods | Select-Object -First 1).SMBIOSMemoryType
    $typeName = switch ($memType) { 26 { 'DDR4' } 34 { 'DDR5' } 24 { 'DDR3' } default { '' } }
    $isLaptop = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes | Where-Object { $_ -in 8,9,10,11,12,14,18,21,30,31,32 }
    $spdText = "$cfg MT/s $typeName".Trim()
    if ($rated -gt 0 -and $cfg -gt 0 -and $cfg -lt $rated) {
        Add-Item 'RAM' 'Hız (XMP/EXPO)' 'warn' "$spdText (modül: $rated MT/s)" 'RAM desteklediği hızın altında çalışıyor. BIOS''ta XMP / EXPO / DOCP profilini aç.'
    } elseif (-not $isLaptop -and (($typeName -eq 'DDR4' -and $cfg -le 2666) -or ($typeName -eq 'DDR5' -and $cfg -le 4800))) {
        Add-Item 'RAM' 'Hız (XMP/EXPO)' 'warn' $spdText 'RAM standart (düşük) hızda çalışıyor. BIOS''ta XMP / EXPO / DOCP profilini açmak oyunlarda FPS''i artırabilir.'
    } else {
        Add-Item 'RAM' 'Hız (XMP/EXPO)' 'ok' $spdText
    }
}

Step 'En çok RAM kullanan programlar'
$top = Get-Process | Group-Object ProcessName | ForEach-Object {
    [pscustomobject]@{ Ad = $_.Name; Bellek = ($_.Group | Measure-Object WorkingSet64 -Sum).Sum; Adet = $_.Count }
} | Sort-Object Bellek -Descending | Select-Object -First 8
$topText = ($top | ForEach-Object { '{0} ({1}x): {2}' -f $_.Ad, $_.Adet, (Fmt-GB $_.Bellek) }) -join '<br>'
Add-Item 'RAM' 'En çok kullananlar' 'info' $topText

# ---------------------------------------------------------------
#  4. EKRAN KARTI
# ---------------------------------------------------------------
Step 'Ekran kartı'
$gpus = @(Get-CimInstance Win32_VideoController)
$gpus = @($gpus | Where-Object { $_.Name -notmatch 'Basic Display|Remote Display|Virtual|Parsec|Meta|Mirage' })
if ($gpus.Count -eq 0) {
    Add-Item 'Ekran kartı' 'Kart' 'bad' 'Ekran kartı sürücüsü yüklü değil (Microsoft Basic Display)' 'Ekran kartının sürücüsünü üreticinin sitesinden kur.'
}
foreach ($g in $gpus) {
    $isIntegrated = $g.Name -match '^AMD Radeon\(TM\) Graphics$|Radeon Graphics$|Radeon\(TM\) \d+M|Intel\(R\) (UHD|HD|Iris)'
    $ver = $g.DriverVersion
    $vendor = ''; $link = ''; $how = ''
    if ($g.Name -match 'NVIDIA') {
        $vendor = 'NVIDIA'; $link = $Links.Nvidia; $how = 'NVIDIA App veya '
        $digits = ($g.DriverVersion -replace '\.', '')
        if ($digits.Length -ge 5) {
            $last5 = $digits.Substring($digits.Length - 5)
            $ver = '{0}.{1}' -f $last5.Substring(0, 3), $last5.Substring(3)
        }
    } elseif ($g.Name -match 'AMD|Radeon') {
        $vendor = 'AMD'; $link = $Links.AmdGpu; $how = 'AMD Software (Adrenalin) veya '
    } elseif ($g.Name -match 'Intel') {
        $vendor = 'Intel'; $link = $Links.IntelGpu; $how = 'Intel Driver & Support Assistant veya '
    }

    $kind = 'Kart'; if ($isIntegrated) { $kind = 'Dahili grafik' }
    Add-Item 'Ekran kartı' $kind 'info' $g.Name

    $age = Months-Old $g.DriverDate
    $txt = 'Yüklü: {0} ({1:dd.MM.yyyy})' -f $ver, $g.DriverDate
    $title = "$vendor ekran kartı sürücüsü".Trim()
    if ($isIntegrated -and $gpus.Count -gt 1) {
        Add-Item 'Güncellik' "$title (dahili)" 'info' $txt 'Harici kartın varken dahili grafiğin sürücüsü oyunlar için önemli değil.'
    } elseif ($age -ne $null -and $age -gt $DriverMaxAgeMonths) {
        Add-Item 'Güncellik' $title 'warn' ("$txt, $age aylık") ("Muhtemelen daha yenisi var. $how<a href='$link'>resmi siteden</a> güncelle.")
    } else {
        Add-Item 'Güncellik' $title 'ok' $txt
    }
}

# Monitörlerin desteklediği en yüksek yenileme hızında çalışıp çalışmadığı
try {
    if (-not ('PcCheck.Disp' -as [type])) { Add-Type -Namespace PcCheck -Name Disp -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public struct DEVMODE {
  [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
  public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra; public int dmFields;
  public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
  public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
  [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
  public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight; public int dmDisplayFlags; public int dmDisplayFrequency;
  public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
}
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public struct DISPLAY_DEVICE {
  public int cb;
  [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
  [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
  public int StateFlags;
  [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
  [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
}
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
'@ -ErrorAction Stop }
    $i = 0
    while ($true) {
        $dd = New-Object 'PcCheck.Disp+DISPLAY_DEVICE'
        $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)
        if (-not [PcCheck.Disp]::EnumDisplayDevices($null, [uint32]$i, [ref]$dd, 0)) { break }
        $i++
        if (($dd.StateFlags -band 1) -eq 0) { continue }   # masaüstüne bağlı değil
        $cur = New-Object 'PcCheck.Disp+DEVMODE'
        $cur.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf($cur)
        if (-not [PcCheck.Disp]::EnumDisplaySettings($dd.DeviceName, -1, [ref]$cur)) { continue }
        $max = $cur.dmDisplayFrequency; $m = 0
        while ($true) {
            $dm = New-Object 'PcCheck.Disp+DEVMODE'
            $dm.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf($dm)
            if (-not [PcCheck.Disp]::EnumDisplaySettings($dd.DeviceName, $m, [ref]$dm)) { break }
            if ($dm.dmPelsWidth -eq $cur.dmPelsWidth -and $dm.dmPelsHeight -eq $cur.dmPelsHeight -and $dm.dmDisplayFrequency -gt $max) { $max = $dm.dmDisplayFrequency }
            $m++
        }
        $mon = New-Object 'PcCheck.Disp+DISPLAY_DEVICE'
        $mon.cb = [Runtime.InteropServices.Marshal]::SizeOf($mon)
        $monName = $dd.DeviceName.TrimStart('\','.')
        if ([PcCheck.Disp]::EnumDisplayDevices($dd.DeviceName, 0, [ref]$mon, 0) -and $mon.DeviceString) { $monName = "$($mon.DeviceString) ($monName)" }
        $txt = '{0}: {1} x {2} @ {3} Hz' -f $monName, $cur.dmPelsWidth, $cur.dmPelsHeight, $cur.dmDisplayFrequency
        if ($max -gt $cur.dmDisplayFrequency + 1) {
            Add-Item 'Ekran kartı' 'Monitör yenileme hızı' 'warn' "$txt (desteklenen: $max Hz)" "Monitör $max Hz destekliyor ama daha düşükte çalışıyor. Ayarlar > Sistem > Ekran > Gelişmiş ekran'dan $max Hz seç."
        } else {
            Add-Item 'Ekran kartı' 'Monitör yenileme hızı' 'ok' $txt
        }
    }
} catch { }

$smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
if (Test-Path $smi) {
    $q = & $smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,fan.speed --format=csv,noheader,nounits 2>$null
    if ($q) {
        $p = ($q | Select-Object -First 1).Split(',') | ForEach-Object { $_.Trim() }
        $temp = [int]$p[0]
        $txt = '{0} °C, yük %{1}, VRAM {2}/{3} MB, güç {4} W, fan %{5}' -f $p[0], $p[1], $p[2], $p[3], $p[4], $p[5]
        if ($temp -ge 85) {
            Add-Item 'Ekran kartı' 'Sıcaklık ve yük' 'bad' $txt 'Ekran kartı çok sıcak. Kasa içi tozu temizle, fan eğrisini kontrol et.'
        } elseif ($temp -ge 75) {
            Add-Item 'Ekran kartı' 'Sıcaklık ve yük' 'warn' $txt 'Boştayken bu sıcaklık yüksek; oyun açıksa normal olabilir.'
        } else {
            Add-Item 'Ekran kartı' 'Sıcaklık ve yük' 'ok' $txt
        }
    }
}

# ---------------------------------------------------------------
#  5. BIOS
# ---------------------------------------------------------------
Step 'BIOS'
$bios  = Get-CimInstance Win32_BIOS
$board = Get-CimInstance Win32_BaseBoard
$biosVer  = ($bios.SMBIOSBIOSVersion).Trim()
$biosDate = $bios.ReleaseDate
$model = $board.Product
if ($cs.Manufacturer -and $cs.Model -and $cs.Model -notmatch 'System Product Name|To be filled|Default string') { $model = "$($cs.Model)" }
$biosText = '{0} {1}, BIOS {2} ({3:dd.MM.yyyy})' -f $board.Manufacturer, $model, $biosVer, $biosDate
$search = 'https://www.google.com/search?q=' + [uri]::EscapeDataString("$($board.Manufacturer) $model BIOS download")
$biosAge = Months-Old $biosDate
if ($biosAge -ne $null -and $biosAge -gt $BiosMaxAgeMonths) {
    Add-Item 'Güncellik' 'BIOS' 'warn' ("$biosText, $biosAge aylık") "Eski bir BIOS. <a href='$search'>Üreticinin destek sayfasından</a> yeni sürüm var mı bak. BIOS güncellemesi risklidir; elektrik kesilmeyecek bir anda, talimatlara uyarak yap."
} else {
    Add-Item 'Güncellik' 'BIOS' 'ok' $biosText "En yeni sürüm olup olmadığını <a href='$search'>üreticinin sitesinden</a> görebilirsin. Sorun yaşamıyorsan güncellemek şart değil."
}
$sb = $null; try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch { }
if ($sb -eq $true) {
    Add-Item 'Güvenlik' 'Secure Boot' 'ok' 'Açık'
} elseif ($sb -eq $false) {
    Add-Item 'Güvenlik' 'Secure Boot' 'info' 'Kapalı' 'Valorant, Battlefield 6, yeni Call of Duty gibi bazı oyunların hile korumaları Secure Boot ister. Gerekirse BIOS''tan açılır.'
}

# ---------------------------------------------------------------
#  6. CHIPSET
# ---------------------------------------------------------------
Step 'Chipset sürücüsü'
$uninstallPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installed = Get-ItemProperty $uninstallPaths | Where-Object { $_.DisplayName }
function Parse-InstallDate($s) {
    if ($s -match '^\d{8}$') { try { return [datetime]::ParseExact($s, 'yyyyMMdd', $null) } catch { } }
    return $null
}
if ($cpu.Manufacturer -match 'AMD') {
    $chip = $installed | Where-Object { $_.DisplayName -match 'AMD Chipset Software' } | Select-Object -First 1
    if ($chip) {
        $d = Parse-InstallDate $chip.InstallDate
        $age = Months-Old $d
        $txt = "Yüklü: $($chip.DisplayVersion)"; if ($d) { $txt += (' ({0:dd.MM.yyyy} tarihinde kuruldu)' -f $d) }
        if ($age -ne $null -and $age -gt 6) {
            Add-Item 'Güncellik' 'AMD chipset sürücüsü' 'warn' $txt "6 aydan uzun süredir güncellenmemiş. <a href='$($Links.AmdChipset)'>AMD sitesinden</a> anakartının chipset'ini (ör. B550, X670) seçip en yenisini kur."
        } else {
            Add-Item 'Güncellik' 'AMD chipset sürücüsü' 'ok' $txt "Yeni sürüm çıkıp çıkmadığını <a href='$($Links.AmdChipset)'>AMD sitesinden</a> görebilirsin."
        }
    } else {
        Add-Item 'Güncellik' 'AMD chipset sürücüsü' 'warn' 'Yüklü değil' "AMD işlemcilerde chipset sürücüsü önemlidir. <a href='$($Links.AmdChipset)'>AMD sitesinden</a> kur."
    }
} elseif ($cpu.Manufacturer -match 'Intel') {
    $chip = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'SYSTEM' -and $_.Manufacturer -match 'Intel' -and $_.DriverDate } |
            Sort-Object DriverDate -Descending | Select-Object -First 1
    if ($chip) {
        $age = Months-Old $chip.DriverDate
        $txt = 'En yeni Intel sistem sürücüsü: {0} ({1:dd.MM.yyyy})' -f $chip.DriverVersion, $chip.DriverDate
        if ($age -gt 24) {
            Add-Item 'Güncellik' 'Intel chipset sürücüleri' 'warn' $txt "Sürücüler eski görünüyor. <a href='$($Links.IntelChip)'>Intel Driver & Support Assistant</a> ile kontrol et."
        } else {
            Add-Item 'Güncellik' 'Intel chipset sürücüleri' 'ok' $txt
        }
    }
}

# ---------------------------------------------------------------
#  7. WINDOWS UPDATE
# ---------------------------------------------------------------
$rebootPending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                 (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
if ($rebootPending) {
    Add-Item 'Güncellik' 'Yeniden başlatma' 'warn' 'Güncellemeler yeniden başlatma bekliyor' 'Bilgisayarı yeniden başlat.'
}

if (-not $SkipWindowsUpdate) {
    Step 'Windows Update taranıyor (1-2 dakika sürebilir)'
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $found    = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $ups = @()
        foreach ($u in $found.Updates) { $ups += $u }
        if ($ups.Count -eq 0) {
            Add-Item 'Güncellik' 'Windows Update' 'ok' 'Bekleyen güncelleme yok'
        } else {
            $drivers = @($ups | Where-Object { $_.Type -eq 2 })
            $soft    = @($ups | Where-Object { $_.Type -ne 2 })
            $optional = @($soft | Where-Object { $_.Title -match 'Feature update|Özellik güncelleştirmesi|version \d\dH\d' })
            $needed   = @($soft | Where-Object { $optional -notcontains $_ })
            if ($needed.Count -gt 0) {
                Add-Item 'Güncellik' 'Windows Update' 'warn' (($needed | ForEach-Object { $_.Title }) -join '<br>') 'Ayarlar > Windows Update üzerinden kur.'
            } else {
                Add-Item 'Güncellik' 'Windows Update' 'ok' 'Gerekli güncelleme yok'
            }
            if ($optional.Count -gt 0) {
                Add-Item 'Güncellik' 'Windows sürüm yükseltmesi' 'info' (($optional | ForEach-Object { $_.Title }) -join '<br>') 'İsteğe bağlı; acelesi yok.'
            }
            if ($drivers.Count -gt 0) {
                Add-Item 'Güncellik' 'Windows Update sürücüleri' 'info' (($drivers | ForEach-Object { $_.Title }) -join '<br>') 'İsteğe bağlı sürücüler. Bir sorun yaşamıyorsan şart değil.'
            }
        }
    } catch {
        Add-Item 'Güncellik' 'Windows Update' 'info' 'Taranamadı' 'Ayarlar > Windows Update sayfasından elle kontrol et.'
    }
}

# ---------------------------------------------------------------
#  8. DİSKLER
# ---------------------------------------------------------------
Step 'Diskler'
$pds = @(Get-PhysicalDisk)
foreach ($d in $pds) {
    $name = '{0} ({1}, {2})' -f $d.FriendlyName, $d.MediaType, (Fmt-GB $d.Size)
    $extra = ''
    $rel = $d | Get-StorageReliabilityCounter
    if ($rel) {
        $parts = @()
        if ($rel.Temperature)             { $parts += ('{0} °C' -f $rel.Temperature) }
        if ($rel.Wear -ne $null -and $d.MediaType -ne 'HDD') { $parts += ('aşınma %{0}' -f $rel.Wear) }
        if ($rel.ReadErrorsUncorrected)   { $parts += ('düzeltilemeyen okuma hatası: {0}' -f $rel.ReadErrorsUncorrected) }
        if ($rel.PowerOnHours)            { $parts += ('{0} saat çalışma' -f $rel.PowerOnHours) }
        if ($parts.Count -gt 0) { $extra = ' - ' + ($parts -join ', ') }
    }
    $val = "$name$extra"
    if ($d.HealthStatus -ne 'Healthy') {
        Add-Item 'Diskler' $d.FriendlyName 'bad' ("Durum: $($d.HealthStatus). " + $val) 'Disk sorun bildiriyor! Önemli dosyalarını hemen yedekle.'
    } elseif ($rel -and ($rel.ReadErrorsUncorrected -gt 0 -or $rel.Wear -ge 80)) {
        Add-Item 'Diskler' $d.FriendlyName 'warn' $val 'Diskte hata veya yüksek aşınma var. Yedek almayı düşün.'
    } else {
        Add-Item 'Diskler' $d.FriendlyName 'ok' $val
    }
}
if (-not $isAdmin) {
    Add-Item 'Diskler' 'Ayrıntılı disk sağlığı' 'info' 'Yönetici izni olmadan okunamadı' 'Kontrol-Et.bat ile çalıştırırsan sıcaklık/aşınma da görünür.'
}

$vols = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }
foreach ($v in $vols) {
    $freePct = [int](100 * $v.SizeRemaining / $v.Size)
    $txt = '{0}: {1} boş / {2} (%{3})' -f $v.DriveLetter, (Fmt-GB $v.SizeRemaining), (Fmt-GB $v.Size), $freePct
    if ($freePct -lt 10) {
        Add-Item 'Diskler' "$($v.DriveLetter): sürücüsü" 'bad' $txt 'Disk neredeyse dolu. Gereksiz oyun ve dosyaları sil.'
    } elseif ($freePct -lt 15) {
        Add-Item 'Diskler' "$($v.DriveLetter): sürücüsü" 'warn' $txt 'Boş alan azalıyor.'
    } else {
        Add-Item 'Diskler' "$($v.DriveLetter): sürücüsü" 'ok' $txt
    }
}

# ---------------------------------------------------------------
#  9. ÇÖKMELER VE DONANIM HATALARI (son 30 gün)
# ---------------------------------------------------------------
Step 'Çökme kayıtları'
$since = (Get-Date).AddDays(-30)
$bsod = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since })
$kp   = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since })
$whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } | Where-Object { $_.Level -le 3 })

if ($bsod.Count -gt 0) {
    $codes = ($bsod | ForEach-Object { if ($_.Message -match '0x[0-9a-fA-F]{8}') { $Matches[0] } } | Select-Object -Unique) -join ', '
    Add-Item 'Kararlılık' 'Mavi ekran' 'bad' ('{0} kez, son: {1:dd.MM.yyyy HH:mm}. Kod: {2}' -f $bsod.Count, $bsod[0].TimeCreated, $codes) 'Sık tekrarlıyorsa RAM (XMP kapatıp dene), sürücüler veya aşırı ısınma kontrol edilmeli.'
} else {
    Add-Item 'Kararlılık' 'Mavi ekran' 'ok' 'Son 30 günde yok'
}
if ($kp.Count -gt 0) {
    Add-Item 'Kararlılık' 'Beklenmedik kapanma' 'warn' ('{0} kez, son: {1:dd.MM.yyyy HH:mm}' -f $kp.Count, $kp[0].TimeCreated) 'Elektrik kesintisi veya tuşla kapatma da bunu yazar. Kendi kendine kapanıyorsa güç kaynağı / ısınma şüphelidir.'
} else {
    Add-Item 'Kararlılık' 'Beklenmedik kapanma' 'ok' 'Son 30 günde yok'
}
if ($whea.Count -gt 0) {
    Add-Item 'Kararlılık' 'Donanım hatası (WHEA)' 'warn' ('{0} kayıt, son: {1:dd.MM.yyyy HH:mm}' -f $whea.Count, $whea[0].TimeCreated) 'İşlemci, RAM veya PCIe tarafında donanım hatası kaydedilmiş. Hız aşırtma / XMP varsa kapatıp gözlemle.'
} else {
    Add-Item 'Kararlılık' 'Donanım hatası (WHEA)' 'ok' 'Son 30 günde yok'
}

$bad = @(Get-PnpDevice -PresentOnly | Where-Object { $_.Status -eq 'Error' })
if ($bad.Count -gt 0) {
    $names = ($bad | ForEach-Object { $_.FriendlyName }) -join '<br>'
    $onlyVirtual = -not ($bad | Where-Object { $_.FriendlyName -notmatch 'VMware|VirtualBox|Hyper-V|Virtual' })
    if ($onlyVirtual) {
        Add-Item 'Kararlılık' 'Sorunlu aygıtlar' 'info' $names 'Sadece sanal aygıtlar; zararsız.'
    } else {
        Add-Item 'Kararlılık' 'Sorunlu aygıtlar' 'warn' $names 'Aygıt Yöneticisi''nden bu aygıtların sürücüsünü güncelle.'
    }
} else {
    Add-Item 'Kararlılık' 'Sorunlu aygıtlar' 'ok' 'Yok'
}

# ---------------------------------------------------------------
#  10. OYUN / FPS AYARLARI
# ---------------------------------------------------------------
Step 'Oyun ayarları'
$gm = (Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar').AutoGameModeEnabled
if ($gm -eq 0) {
    Add-Item 'Oyun ayarları' 'Oyun Modu' 'warn' 'Kapalı' 'Ayarlar > Oyun > Oyun Modu''nu aç.'
} else {
    Add-Item 'Oyun ayarları' 'Oyun Modu' 'ok' 'Açık'
}

$hags = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers').HwSchMode
if ($hags -eq 2) {
    Add-Item 'Oyun ayarları' 'Donanım hızlandırmalı GPU zamanlaması' 'ok' 'Açık'
} else {
    Add-Item 'Oyun ayarları' 'Donanım hızlandırmalı GPU zamanlaması' 'warn' 'Kapalı' 'Ayarlar > Sistem > Ekran > Grafik > Gelişmiş grafik ayarları''ndan aç.'
}

$dx = (Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences').DirectXUserGlobalSettings
if ($dx -match 'SwapEffectUpgradeEnable=1') {
    Add-Item 'Oyun ayarları' 'Pencereli oyun iyileştirmeleri' 'ok' 'Açık'
} elseif ($dx -match 'SwapEffectUpgradeEnable=0') {
    Add-Item 'Oyun ayarları' 'Pencereli oyun iyileştirmeleri' 'warn' 'Kapalı' 'Ayarlar > Sistem > Ekran > Grafik''ten aç.'
} else {
    Add-Item 'Oyun ayarları' 'Pencereli oyun iyileştirmeleri' 'info' 'Varsayılan'
}

$dvr = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR').HistoricalCaptureEnabled
if ($dvr -eq 1) {
    Add-Item 'Oyun ayarları' 'Arka planda kayıt' 'warn' 'Açık' 'Sürekli kayıt FPS yer. Ayarlar > Oyun > Yakalamalar''dan "Olanları kaydet"i kapat.'
} else {
    Add-Item 'Oyun ayarları' 'Arka planda kayıt' 'ok' 'Kapalı'
}

$overlay = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes').ActiveOverlayAcPowerScheme
$scheme  = (powercfg /getactivescheme) -join ' '
if ($overlay -eq 'ded574b5-45a0-4f42-8737-46345c09c238' -or $scheme -match 'High performance|Yüksek performans|Ultimate|Nihai') {
    Add-Item 'Oyun ayarları' 'Güç modu' 'ok' 'En iyi performans'
} else {
    Add-Item 'Oyun ayarları' 'Güç modu' 'warn' 'Dengeli / tasarruf' 'Ayarlar > Sistem > Güç > Güç modu: "En iyi performans" seç.'
}

$hvci = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity').Enabled
if ($hvci -eq 1) {
    Add-Item 'Oyun ayarları' 'Bellek bütünlüğü' 'info' 'Açık' 'Güvenlik için iyi, ama oyunlarda birkaç FPS düşürebilir.'
} else {
    Add-Item 'Oyun ayarları' 'Bellek bütünlüğü' 'ok' 'Kapalı (FPS için avantajlı)'
}

# ---------------------------------------------------------------
#  11. BAŞLANGIÇ PROGRAMLARI
# ---------------------------------------------------------------
Step 'Başlangıç programları'
$approved = @{}
foreach ($k in @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder')) {
    $item = Get-Item $k
    if ($item) {
        foreach ($n in $item.GetValueNames()) {
            $b = $item.GetValue($n)
            if ($b -is [byte[]] -and $b.Length -gt 0) { $approved[$n] = ($b[0] % 2 -eq 0) }
        }
    }
}
$startup = @(Get-CimInstance Win32_StartupCommand)
$enabled = @()
foreach ($s in $startup) {
    $key = $s.Name
    if ($s.Location -match 'Startup' -and $s.Command) { $key = Split-Path $s.Command -Leaf }
    $isOn = $true
    if ($approved.ContainsKey($s.Name)) { $isOn = $approved[$s.Name] }
    elseif ($approved.ContainsKey($key)) { $isOn = $approved[$key] }
    if ($isOn) { $enabled += $s.Name }
}
$enabled = $enabled | Sort-Object -Unique
$stTxt = ('{0} program açılışta başlıyor:<br>{1}' -f $enabled.Count, ($enabled -join ', '))
if ($enabled.Count -gt 10) {
    Add-Item 'Başlangıç' 'Açılışta başlayanlar' 'warn' $stTxt 'Görev Yöneticisi > Başlangıç uygulamaları''ndan gereksizleri devre dışı bırak.'
} else {
    Add-Item 'Başlangıç' 'Açılışta başlayanlar' 'ok' $stTxt
}

# ---------------------------------------------------------------
#  11b. PİL (laptop)
# ---------------------------------------------------------------
if (Get-CimInstance Win32_Battery) {
    Step 'Pil'
    $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData | Select-Object -First 1).DesignedCapacity
    $full   = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity | Select-Object -First 1).FullChargedCapacity
    if ($design -gt 0 -and $full -gt 0) {
        $health = [int](100 * $full / $design)
        if ($health -gt 100) { $health = 100 }
        $txt = 'Pil sağlığı %{0} ({1} / {2} mWh)' -f $health, $full, $design
        if ($health -lt 60) {
            Add-Item 'Pil' 'Pil sağlığı' 'bad' $txt 'Pil kapasitesinin çoğunu kaybetmiş; değiştirmeyi düşün.'
        } elseif ($health -lt 80) {
            Add-Item 'Pil' 'Pil sağlığı' 'warn' $txt 'Pil yıpranmaya başlamış.'
        } else {
            Add-Item 'Pil' 'Pil sağlığı' 'ok' $txt
        }
    } else {
        Add-Item 'Pil' 'Pil sağlığı' 'info' 'Okunamadı' 'Yönetici olarak çalıştırınca görünebilir.'
    }
    $ac = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus | Select-Object -First 1).PowerOnline
    if ($ac -eq $false) {
        Add-Item 'Pil' 'Güç kaynağı' 'warn' 'Pilden çalışıyor' 'Laptoplar pildeyken ekran kartını kısar. Oyun oynarken şarj aletini tak.'
    }
}

# ---------------------------------------------------------------
#  12. GÜVENLİK
# ---------------------------------------------------------------
Step 'Güvenlik'
$mp = Get-MpComputerStatus
if ($mp) {
    if ($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled) {
        Add-Item 'Güvenlik' 'Windows Defender' 'ok' 'Açık, gerçek zamanlı koruma çalışıyor'
    } else {
        Add-Item 'Güvenlik' 'Windows Defender' 'bad' 'Gerçek zamanlı koruma kapalı' 'Başka bir antivirüs yoksa Windows Güvenliği''nden aç.'
    }
    $sigAge = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
    if ($sigAge -gt 3) {
        Add-Item 'Güvenlik' 'Virüs tanımları' 'warn' ('Son güncelleme: {0:dd.MM.yyyy}' -f $mp.AntivirusSignatureLastUpdated) 'Windows Güvenliği''nden tanımları güncelle.'
    } else {
        Add-Item 'Güvenlik' 'Virüs tanımları' 'ok' ('Güncel ({0:dd.MM.yyyy})' -f $mp.AntivirusSignatureLastUpdated)
    }
    if ($mp.QuickScanEndTime) {
        $scanAge = ((Get-Date) - $mp.QuickScanEndTime).TotalDays
        if ($scanAge -gt 14) {
            Add-Item 'Güvenlik' 'Son tarama' 'warn' ('{0:dd.MM.yyyy}' -f $mp.QuickScanEndTime) 'İki haftadır tarama yapılmamış; hızlı tarama başlat.'
        } else {
            Add-Item 'Güvenlik' 'Son tarama' 'ok' ('{0:dd.MM.yyyy}' -f $mp.QuickScanEndTime)
        }
    }
} else {
    Add-Item 'Güvenlik' 'Windows Defender' 'info' 'Okunamadı (başka antivirüs kullanılıyor olabilir)'
}

# ---------------------------------------------------------------
#  RAPOR
# ---------------------------------------------------------------
Step 'Rapor hazırlanıyor'
$nOk   = @($results | Where-Object Durum -eq 'ok').Count
$nWarn = @($results | Where-Object Durum -eq 'warn').Count
$nBad  = @($results | Where-Object Durum -eq 'bad').Count
if ($nBad -gt 0)      { $overall = 'Dikkat gerektiren sorunlar var'; $ovClass = 'bad' }
elseif ($nWarn -gt 0) { $overall = 'Sağlıklı, birkaç iyileştirme önerisi var'; $ovClass = 'warn' }
else                  { $overall = 'Her şey yolunda'; $ovClass = 'ok' }

$labels = @{ ok = 'İyi'; warn = 'Uyarı'; bad = 'Sorun'; info = 'Bilgi' }
$order  = @('Güncellik','Sistem','İşlemci','RAM','Ekran kartı','Diskler','Kararlılık','Oyun ayarları','Başlangıç','Pil','Güvenlik')

$todo = @($results | Where-Object { $_.Durum -in @('bad','warn') } | Sort-Object @{ Expression = { if ($_.Durum -eq 'bad') { 0 } else { 1 } } })
$todoHtml = ''
if ($todo.Count -gt 0) {
    $todoHtml = '<section class="todo"><h2>Yapılacaklar</h2><ol>' + (($todo | ForEach-Object {
        "<li><span class='badge $($_.Durum)'>$($labels[$_.Durum])</span> <b>$($_.Baslik):</b> $($_.Oneri)</li>"
    }) -join '') + '</ol></section>'
}

$sections = foreach ($cat in $order) {
    $rows = @($results | Where-Object Kategori -eq $cat)
    if ($rows.Count -eq 0) { continue }
    $tr = ($rows | ForEach-Object {
        $o = ''; if ($_.Oneri) { $o = "<div class='hint'>$($_.Oneri)</div>" }
        "<tr><td class='st'><span class='badge $($_.Durum)'>$($labels[$_.Durum])</span></td><td class='k'>$($_.Baslik)</td><td>$($_.Deger)$o</td></tr>"
    }) -join ''
    "<section><h2>$cat</h2><table>$tr</table></section>"
}

$adminNote = ''
if (-not $isAdmin) { $adminNote = '<p class="note">Yönetici olarak çalıştırılmadı; bazı disk bilgileri eksik olabilir. Tam rapor için Kontrol-Et.bat dosyasını kullan.</p>' }

$html = @"
<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8"><title>PC Sağlık Raporu - $($env:COMPUTERNAME)</title>
<style>
:root{--bg:#111418;--card:#1a1f26;--line:#2a313b;--fg:#e6e9ee;--mut:#9aa4b2;--ok:#2fb26a;--warn:#e0a526;--bad:#e5484d;--info:#5b8def}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 "Segoe UI",system-ui,sans-serif}
.wrap{max-width:980px;margin:0 auto;padding:32px 20px 60px}
h1{margin:0 0 4px;font-size:26px}.sub{color:var(--mut);margin:0 0 24px}
.summary{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:24px}
.pill{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 18px;min-width:120px}
.pill b{display:block;font-size:24px}.pill.overall{flex:1;min-width:260px}
.pill.overall.ok b{color:var(--ok)}.pill.overall.warn b{color:var(--warn)}.pill.overall.bad b{color:var(--bad)}
section{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin-bottom:16px}
h2{font-size:16px;margin:0 0 10px;color:#fff}
table{width:100%;border-collapse:collapse}td{padding:9px 8px;border-top:1px solid var(--line);vertical-align:top}
tr:first-child td{border-top:none}td.st{width:80px}td.k{width:230px;color:var(--mut)}
.badge{display:inline-block;font-size:12px;font-weight:600;padding:2px 8px;border-radius:999px;color:#0b0d10}
.badge.ok{background:var(--ok)}.badge.warn{background:var(--warn)}.badge.bad{background:var(--bad);color:#fff}.badge.info{background:var(--info);color:#fff}
.hint{color:var(--mut);font-size:13px;margin-top:4px}a{color:#7fb0ff}
.todo ol{margin:0;padding-left:20px}.todo li{margin:6px 0}
.note{color:var(--warn)}.foot{color:var(--mut);font-size:13px;margin-top:24px}
</style></head><body><div class="wrap">
<h1>PC Sağlık Raporu</h1>
<p class="sub">$($env:COMPUTERNAME) &middot; $(Get-Date -Format 'dd.MM.yyyy HH:mm')</p>
<div class="summary">
<div class="pill overall $ovClass"><span>Genel durum</span><b>$overall</b></div>
<div class="pill"><span>İyi</span><b style="color:var(--ok)">$nOk</b></div>
<div class="pill"><span>Uyarı</span><b style="color:var(--warn)">$nWarn</b></div>
<div class="pill"><span>Sorun</span><b style="color:var(--bad)">$nBad</b></div>
</div>
$adminNote
$todoHtml
$($sections -join "`n")
<p class="foot">Windows ve Windows Update üzerinden sunulan sürücüler doğrudan taranır. Ekran kartı, chipset ve BIOS için sürücünün/BIOS'un tarihine bakılır; "eski" uyarısı alırsan bağlantıdan üreticinin sitesindeki en yeni sürümle karşılaştır.</p>
</div></body></html>
"@

$desk = [Environment]::GetFolderPath('Desktop')
if (-not $desk -or -not (Test-Path $desk)) { $desk = $env:USERPROFILE }
$out = Join-Path $desk ('PC-Saglik-Raporu_{0}.html' -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
[IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding($true)))

Write-Host ''
Write-Host ("  Genel durum: " + $overall) -ForegroundColor Green
Write-Host ("  İyi: $nOk   Uyarı: $nWarn   Sorun: $nBad") -ForegroundColor Green
Write-Host ("  Rapor: " + $out) -ForegroundColor Green
Write-Host ''
if (-not $NoOpen) { Start-Process $out }
if (-not $NoPause) { [void](Read-Host '  Kapatmak için Enter''a bas') }
