#Requires -RunAsAdministrator
# Восстанавливает рабочее состояние ввода на HP Pavilion x360 14-dh0xxx.
# Не перезапускает клавиатуру ACPI\HPQ8001 и не трогает USB-мышь.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$destDir = "C:\ProgramData\ForceLaptopMode"
$destPs1 = Join-Path $destDir "force-laptop.ps1"

function Get-PublishedDrivers {
  $raw = pnputil /enum-drivers | Out-String
  $parts = [regex]::Split($raw, '(?=Published Name:)')
  foreach ($b in $parts) {
    if ($b -notmatch 'Published Name:\s+(\S+)') { continue }
    [pscustomobject]@{
      Published = $Matches[1]
      Original  = if ($b -match 'Original Name:\s+(\S+)') { $Matches[1] } else { "" }
      Version   = if ($b -match 'Driver Version:\s+(.+)') { $Matches[1].Trim() } else { "" }
    }
  }
}

function Keep-IntelMe {
  $bundleRoot = Join-Path (Split-Path $here -Parent) "drivers"
  foreach ($rel in @(
      "heci-2036.100.0.1024\heci.inf",
      "lms-2316.5.1.12\lms.inf",
      "dal-1.38.2020.805\dal.inf"
    )) {
    $inf = Join-Path $bundleRoot $rel
    if (Test-Path $inf) {
      Write-Output "Публикую $rel"
      pnputil /add-driver $inf /install
    }
  }
  $keep = @(
    @{ Name = "heci.inf"; Good = "2036\.100\.0\.1024"; Bad = "2603\.9\.4\.0" }
    @{ Name = "lms.inf";  Good = "2316\.5\.1\.12";    Bad = "2613\.9\.7\.0" }
    @{ Name = "dal.inf";  Good = "1\.38\.2020\.0*805"; Bad = "1\.46\.2024\.0*221" }
  )
  $drivers = @(Get-PublishedDrivers)
  foreach ($item in $keep) {
    $good = $drivers | Where-Object { $_.Original -eq $item.Name -and $_.Version -match $item.Good }
    $bad = $drivers | Where-Object { $_.Original -eq $item.Name -and $_.Version -match $item.Bad }
    if (-not $bad) { continue }
    if (-not $good) {
      Write-Warning "$($item.Name) $($item.Bad) стоит, а $($item.Good) в хранилище нет. Пакет не удаляю."
      continue
    }
    Write-Output "Удаляю $($bad.Published) $($item.Name) $($item.Bad)"
    pnputil /delete-driver $bad.Published /uninstall /force
  }
  pnputil /scan-devices | Out-Null

  $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
  if (-not (Test-Path $wu)) { New-Item -Path $wu -Force | Out-Null }
  New-ItemProperty -Path $wu -Name ExcludeWUDriversInQualityUpdate -Value 1 -PropertyType DWord -Force | Out-Null
  Write-Output "Драйверы из Центра обновления отключены. Обновления Windows остаются."
}

function Set-InputPower {
  $roots = @(
    "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\HPQ8001",
    "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\SYNA328B",
    "HKLM:\SYSTEM\CurrentControlSet\Enum\HID",
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_8086&DEV_9DE8",
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_8086&DEV_9DE9"
  )
  foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
      $name = $_.PSChildName
      $parent = $_.PSParentPath
      $isTouch = $name -match "SYNA328B&Col01" -or $parent -match "SYNA328B&Col01"
      $isTarget = $root -notmatch "\\HID$" -or $isTouch
      if (-not $isTarget) { return }
      if (-not (Get-ItemProperty $_.PSPath -Name Service -ErrorAction SilentlyContinue) -and -not (Get-ItemProperty $_.PSPath -Name DeviceDesc -ErrorAction SilentlyContinue)) { return }
      New-ItemProperty -Path $_.PSPath -Name PnPCapabilities -Value 24 -PropertyType DWord -Force | Out-Null
      if ($root -match "ACPI\\SYNA328B$") {
        New-ItemProperty -Path $_.PSPath -Name EnhancedPowerManagementEnabled -Value 0 -PropertyType DWord -Force | Out-Null
      }
    }
  }
  powercfg /change hibernate-timeout-ac 0 | Out-Null
  powercfg /change hibernate-timeout-dc 0 | Out-Null
}

function Install-Tasks {
  New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  Copy-Item -Path (Join-Path $here "force-laptop.ps1") -Destination $destPs1 -Force
  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destPs1`""
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
  $system = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
  $boot = New-ScheduledTaskTrigger -AtStartup
  $boot.Delay = "PT20S"
  Register-ScheduledTask -TaskName "ForceLaptopMode" -Action $action -Trigger $boot -Principal $system -Settings $settings -Force | Out-Null
  Unregister-ScheduledTask -TaskName "ForceLaptopModeWake" -Confirm:$false -ErrorAction SilentlyContinue
  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
  </Settings>
  <Triggers>
    <EventTrigger>
      <Delay>PT8S</Delay>
      <Subscription>&lt;QueryList&gt;&lt;Query&gt;&lt;Select Path='System'&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=107)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $destPs1</Arguments></Exec></Actions>
</Task>
"@
  Register-ScheduledTask -TaskName "ForceLaptopModeWake" -Xml $xml -Force | Out-Null
  $logonUser = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $logon = New-ScheduledTaskTrigger -AtLogOn -User $logonUser
  $logon.Delay = "PT5S"
  $userPrincipal = New-ScheduledTaskPrincipal -UserId $logonUser -RunLevel Highest -LogonType Interactive
  Register-ScheduledTask -TaskName "ForceLaptopModeLogon" -Action $action -Trigger $logon -Principal $userPrincipal -Settings $settings -Force | Out-Null
}

$kbdClass = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96b-e325-11ce-bfc1-08002be10318}"
Set-ItemProperty -Path $kbdClass -Name UpperFilters -Value ([string[]]@("kbdclass"))
$tpReg = "HKLM:\SYSTEM\CurrentControlSet\Enum\HID\SYNA328B&Col01\5&29f54c&0&0000"
if ((Get-ItemProperty $tpReg -ErrorAction SilentlyContinue).UpperFilters -contains "SynTP") {
  Remove-ItemProperty -Path $tpReg -Name UpperFilters
}
Keep-IntelMe
Set-InputPower
Install-Tasks
Write-Output "Готово. Клавиатуру не перезапускал. Проверьте версии драйверов ME, LMS и DAL и один цикл сна."
