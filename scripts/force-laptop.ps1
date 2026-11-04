$ErrorActionPreference = "Continue"
$log = "C:\ProgramData\ForceLaptopMode\force-laptop.log"
function Log($m) { "$(Get-Date -Format o) $m" | Add-Content -Path $log -Encoding utf8 }

if (-not ("SlateIface" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class SlateIface {
  [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr SetupDiGetClassDevs(ref Guid ClassGuid, string Enumerator, IntPtr hwndParent, uint Flags);
  [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool SetupDiEnumDeviceInterfaces(IntPtr DeviceInfoSet, IntPtr DeviceInfoData, ref Guid InterfaceClassGuid, uint MemberIndex, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);
  [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet, ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData, IntPtr DeviceInterfaceDetailData, uint DeviceInterfaceDetailDataSize, out uint RequiredSize, IntPtr DeviceInfoData);
  [DllImport("setupapi.dll", SetLastError=true)]
  static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr s, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool WriteFile(IntPtr hFile, byte[] buf, uint n, out uint written, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool CloseHandle(IntPtr h);
  [DllImport("user32.dll")]
  public static extern int GetSystemMetrics(int nIndex);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
  [StructLayout(LayoutKind.Sequential)]
  struct SP_DEVICE_INTERFACE_DATA { public uint cbSize; public Guid InterfaceClassGuid; public uint Flags; public IntPtr Reserved; }
  static string PathOf() {
    Guid guid = new Guid("317fc439-3f77-41c8-b09e-08ad63272aa3");
    IntPtr set = SetupDiGetClassDevs(ref guid, null, IntPtr.Zero, 0x12);
    if (set == (IntPtr)(-1)) return null;
    var data = new SP_DEVICE_INTERFACE_DATA();
    data.cbSize = (uint)Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
    if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, 0, ref data)) { SetupDiDestroyDeviceInfoList(set); return null; }
    uint req; SetupDiGetDeviceInterfaceDetail(set, ref data, IntPtr.Zero, 0, out req, IntPtr.Zero);
    IntPtr detail = Marshal.AllocHGlobal((int)req);
    Marshal.WriteInt32(detail, 8);
    bool ok = SetupDiGetDeviceInterfaceDetail(set, ref data, detail, req, out req, IntPtr.Zero);
    string path = ok ? Marshal.PtrToStringUni(new IntPtr(detail.ToInt64() + 4)) : null;
    Marshal.FreeHGlobal(detail); SetupDiDestroyDeviceInfoList(set); return path;
  }
  public static string EnsureLaptop() {
    int before = GetSystemMetrics(0x2003);
    if (before != 0) return "already-laptop metric=" + before;
    string path = PathOf();
    if (path == null) return "no-interface metric=" + before;
    IntPtr h = CreateFile(path, 0x40000000, 0, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (h == (IntPtr)(-1)) return "open-failed " + Marshal.GetLastWin32Error() + " metric=" + before;
    uint written; bool ok = WriteFile(h, new byte[]{0}, 1, out written, IntPtr.Zero);
    int err = Marshal.GetLastWin32Error(); CloseHandle(h);
    System.Threading.Thread.Sleep(400);
    int after = GetSystemMetrics(0x2003);
    return "toggled before=" + before + " after=" + after + " ok=" + ok + " err=" + err;
  }
  public static void Broadcast() {
    UIntPtr r; SendMessageTimeout((IntPtr)0xffff, 0x1A, UIntPtr.Zero, "ConvertibleSlateMode", 2, 2000, out r);
  }
}
"@
}

Log "start"
try {
  New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name ConvertibleSlateMode -Value 1 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name ConvertibilityEnabled -Value 0 -PropertyType DWord -Force | Out-Null
  $result = [SlateIface]::EnsureLaptop()
  Log $result
  Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match "^S-1-5-21-" -and $_.PSChildName -notmatch "_Classes$" } | ForEach-Object {
    $tip = Join-Path $_.PSPath "Software\Microsoft\TabletTip\ConvertibleSlateModeChanged"
    if (Test-Path $tip) { New-ItemProperty -Path $tip -Name ConvertibleSlateModeChanged -Value 0 -PropertyType DWord -Force | Out-Null; Log "cleared tip $($_.PSChildName)" }
    $tp = Join-Path $_.PSPath "SOFTWARE\Synaptics\SynTP\TouchPadHIDPTP"
    if (Test-Path $tp) {
      New-ItemProperty -Path $tp -Name DisableDevice -Value 0 -PropertyType DWord -Force | Out-Null
      New-ItemProperty -Path $tp -Name DisableDeviceUntilSessionEnd -Value 0 -PropertyType DWord -Force | Out-Null
    }
    $im = Join-Path $_.PSPath "SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell"
    if (Test-Path $im) { New-ItemProperty -Path $im -Name TabletMode -Value 0 -PropertyType DWord -Force | Out-Null }
  }
  $kbdClass = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96b-e325-11ce-bfc1-08002be10318}"
  Set-ItemProperty -Path $kbdClass -Name UpperFilters -Value ([string[]]@("kbdclass"))
  $tpReg = "HKLM:\SYSTEM\CurrentControlSet\Enum\HID\SYNA328B&Col01\5&29f54c&0&0000"
  if ((Get-ItemProperty $tpReg -ErrorAction SilentlyContinue).UpperFilters -contains "SynTP") {
    Remove-ItemProperty -Path $tpReg -Name UpperFilters -ErrorAction SilentlyContinue
    Log "removed SynTP from touchpad"
  }
  [SlateIface]::Broadcast()
  Log "broadcast metric=$([SlateIface]::GetSystemMetrics(0x2003)) reg=$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl').ConvertibleSlateMode)"
} catch { Log ("ERROR " + $_.Exception.Message) }
