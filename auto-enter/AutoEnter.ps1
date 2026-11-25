<#
  AutoEnter.ps1 - presses the main-keyboard Enter key at a random interval.

  Default: every 30-40 seconds (strictly more than 30 and less than 40),
  with a human-like random hold time on each press.

  The key is sent through the Windows SendInput API as a hardware scan code
  (0x1C, the main Enter key), so it goes through the same input path as your
  keyboard: apps see a normal WM_KEYDOWN / WM_KEYUP for VK_RETURN, and games
  that read scan codes (DirectInput / raw input) see Enter too.

  The keypress goes to whichever window has focus.
  Stop it with Ctrl+C or by closing the window.

  Usage:
    .\AutoEnter.ps1
    .\AutoEnter.ps1 -MinSeconds 30 -MaxSeconds 40 -StartDelay 5
#>
param(
    [double]$MinSeconds = 30,
    [double]$MaxSeconds = 40,
    [int]$StartDelay = 5
)

$ErrorActionPreference = 'Stop'

if ($MaxSeconds -le $MinSeconds) {
    throw "MaxSeconds ($MaxSeconds) must be greater than MinSeconds ($MinSeconds)."
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class EnterKeySender
{
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT
    {
        public int dx; public int dy; public uint mouseData;
        public uint dwFlags; public uint time; public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT
    {
        public ushort wVk; public ushort wScan; public uint dwFlags;
        public uint time; public IntPtr dwExtraInfo;
    }

    // MOUSEINPUT is the largest member, so including it gives INPUT the
    // size Windows expects (28 bytes on 32-bit, 40 bytes on 64-bit).
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    const uint INPUT_KEYBOARD     = 1;
    const uint KEYEVENTF_KEYUP    = 0x0002;
    const uint KEYEVENTF_SCANCODE = 0x0008;
    const ushort SC_RETURN        = 0x1C;   // main Enter key (not numpad)

    static bool Send(uint extraFlags)
    {
        INPUT[] inputs = new INPUT[1];
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].U.ki.wVk = 0;                    // ignored with SCANCODE; Windows maps 0x1C -> VK_RETURN
        inputs[0].U.ki.wScan = SC_RETURN;
        inputs[0].U.ki.dwFlags = KEYEVENTF_SCANCODE | extraFlags;
        return SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT))) == 1;
    }

    public static bool Down() { return Send(0); }
    public static bool Up()   { return Send(KEYEVENTF_KEYUP); }
}
'@

$rng = New-Object System.Random

# Interval in ms, strictly inside (MinSeconds, MaxSeconds).
$minMs = [int][Math]::Floor($MinSeconds * 1000) + 1
$maxMs = [int][Math]::Ceiling($MaxSeconds * 1000)   # Random.Next upper bound is exclusive

Write-Host "AutoEnter: pressing Enter every $MinSeconds-$MaxSeconds s (randomized)."
Write-Host "Click into the target window now. Ctrl+C here to stop."
for ($i = $StartDelay; $i -gt 0; $i--) {
    Write-Host -NoNewline "`rStarting in $i s...   "
    Start-Sleep -Seconds 1
}
Write-Host ""

$count = 0
while ($true) {
    $waitMs = $rng.Next($minMs, $maxMs)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $waitMs) {
        $left = ($waitMs - $sw.ElapsedMilliseconds) / 1000
        Write-Host -NoNewline ("`rNext Enter in {0,5:N1} s  (sent: {1})   " -f $left, $count)
        Start-Sleep -Milliseconds ([Math]::Min(200, [Math]::Max(1, $waitMs - $sw.ElapsedMilliseconds)))
    }

    # Human-like press: hold the key for a random 50-140 ms.
    $holdMs = $rng.Next(50, 141)
    $ok = [EnterKeySender]::Down()
    Start-Sleep -Milliseconds $holdMs
    $ok = ([EnterKeySender]::Up()) -and $ok

    $count++
    $stamp = Get-Date -Format 'HH:mm:ss'
    if ($ok) {
        Write-Host ("`r[{0}] Enter #{1} sent (waited {2:N2} s, held {3} ms)            " -f $stamp, $count, ($waitMs / 1000), $holdMs)
    } else {
        Write-Host ("`r[{0}] Enter #{1} was BLOCKED by Windows (target app may be running as admin)" -f $stamp, $count)
    }
}
