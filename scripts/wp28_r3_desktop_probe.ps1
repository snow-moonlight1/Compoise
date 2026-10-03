[CmdletBinding()]
param(
    [switch]$Run,
    [string]$EvidenceDirectory=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (!$Run) { Write-Output 'Blocked: WP28-R3 desktop probe requires -Run.'; exit 2 }
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$EvidenceDirectory) { $EvidenceDirectory = Join-Path $workspace ('build/wp28-r3/' + [guid]::NewGuid().ToString()) }
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$required='interactive Windows session that can CreateDesktop and OpenInputDesktop; a hosted runner without a usable desktop is a failure, not a skip'
$proof=Join-Path $evidence 'desktop.json'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class Wp28R3DesktopNative {
  const uint DESKTOP_ACCESS = 0x0001 | 0x0002 | 0x0040 | 0x0080 | 0x0100;
  const int UOI_NAME = 2;
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr CreateDesktopW(string desktop, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr sa);
  [DllImport("user32.dll", SetLastError=true)] static extern bool CloseDesktop(IntPtr handle);
  [DllImport("user32.dll", SetLastError=true)] static extern bool SetThreadDesktop(IntPtr handle);
  [DllImport("user32.dll")] static extern IntPtr GetThreadDesktop(uint threadId);
  [DllImport("user32.dll", SetLastError=true)] static extern IntPtr OpenInputDesktop(int flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern bool GetUserObjectInformationW(IntPtr handle, int index, StringBuilder info, int length, out int needed);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  static string Name(IntPtr handle) {
    if (handle == IntPtr.Zero) return "";
    StringBuilder buffer = new StringBuilder(512);
    int needed;
    if (!GetUserObjectInformationW(handle, UOI_NAME, buffer, buffer.Capacity * 2, out needed)) return "";
    return buffer.ToString();
  }
  public static string Probe(string createdName) {
    string result = "ERR|probe thread did not finish";
    Thread thread = new Thread(() => {
      IntPtr created = IntPtr.Zero;
      IntPtr input = IntPtr.Zero;
      IntPtr original = IntPtr.Zero;
      try {
        original = GetThreadDesktop(GetCurrentThreadId());
        if (original == IntPtr.Zero) { result = "ERR|GetThreadDesktop failed|" + Marshal.GetLastWin32Error(); return; }
        input = OpenInputDesktop(0, false, DESKTOP_ACCESS);
        if (input == IntPtr.Zero) { result = "ERR|OpenInputDesktop failed; hosted runner needs a controlled interactive session|" + Marshal.GetLastWin32Error(); return; }
        string inputName = Name(input);
        if (string.IsNullOrEmpty(inputName)) { result = "ERR|Input desktop has no name"; return; }
        created = CreateDesktopW(createdName, IntPtr.Zero, IntPtr.Zero, 0, DESKTOP_ACCESS, IntPtr.Zero);
        if (created == IntPtr.Zero) { result = "ERR|CreateDesktopW failed|" + Marshal.GetLastWin32Error(); return; }
        if (!SetThreadDesktop(created)) { result = "ERR|SetThreadDesktop onto the private desktop failed|" + Marshal.GetLastWin32Error(); return; }
        string observed = Name(GetThreadDesktop(GetCurrentThreadId()));
        bool isolated = observed == createdName && inputName != observed;
        if (!isolated) { result = "ERR|Private desktop is not isolated from input desktop|" + inputName + "|" + observed; return; }
        bool restored = SetThreadDesktop(original);
        result = "OK|" + inputName + "|" + createdName + "|" + observed + "|" + (restored ? "1" : "0");
      } catch (Exception ex) {
        result = "ERR|" + ex.Message;
      } finally {
        if (created != IntPtr.Zero) CloseDesktop(created);
        if (input != IntPtr.Zero) CloseDesktop(input);
      }
    });
    thread.IsBackground = true;
    thread.SetApartmentState(ApartmentState.MTA);
    thread.Start();
    thread.Join();
    return result;
  }
}
'@
$session=[Diagnostics.Process]::GetCurrentProcess().SessionId
$createdName='wp28-r3-probe-' + [guid]::NewGuid().ToString()
$usable=$false
$errorText=$null
$isolated=$false
$restored=$false
$inputName=''
$createdObserved=''
try {
    if ($session -eq 0) { throw 'Session 0 has no interactive desktop for private-desktop isolation.' }
    $raw=[Wp28R3DesktopNative]::Probe($createdName)
    $parts=$raw.Split('|')
    if ($parts[0] -eq 'OK') {
        $inputName=$parts[1]
        $createdObserved=$parts[3]
        $restored=($parts[4] -eq '1')
        $isolated=$true
        $usable=$true
    } else {
        $errorText=($parts[1..($parts.Length-1)] -join '|')
    }
} catch {
    $errorText=$_.Exception.Message
}
@{schema=1; usable=$usable; skip=$false; sessionId=$session; inputDesktop=$inputName; createdDesktop=$createdName;
  observedCreatedDesktop=$createdObserved; isolated=$isolated; threadDesktopRestored=$restored; error=$errorText;
  requiredRunner=$required} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $proof -Encoding utf8
Write-Output "Desktop probe: $proof; usable=$usable"
if (!$usable) { exit 1 }
exit 0
