#Requires -Version 5.1
<#
  Watch-Bugle.ps1
  Watches Bugle.md, Calendar.html, Go.ps1, and Build-Bugle.ps1.
  On save, debounces ~500ms and runs Go.ps1.
  Leave this running in a terminal. Ctrl+C to stop.
#>

$ErrorActionPreference = 'Stop'

$state = [hashtable]::Synchronized(@{
    Root        = $PSScriptRoot
    Files       = @('Bugle.md', 'Calendar.html', 'Go.ps1', 'Build-Bugle.ps1')
    SelfFile    = 'Watch-Bugle.ps1'
    LastRun     = [DateTime]::MinValue
    DebounceMs  = 500
    ShouldExit  = $false
})

function Write-Stamp([string]$msg, [ConsoleColor]$color = 'Gray') {
    $ts = (Get-Date).ToString('HH:mm:ss')
    Write-Host "[$ts] $msg" -ForegroundColor $color
}

$watcher = New-Object System.IO.FileSystemWatcher $state.Root
$watcher.IncludeSubdirectories = $false
$watcher.NotifyFilter          = [System.IO.NotifyFilters]'LastWrite, FileName, Size'
$watcher.EnableRaisingEvents   = $true

$handler = {
    $s    = $Event.MessageData
    $name = $Event.SourceEventArgs.Name
    if (-not $name) { return }
    $leaf = Split-Path $name -Leaf

    $now = Get-Date
    if (($now - $s.LastRun).TotalMilliseconds -lt $s.DebounceMs) { return }

    if ($leaf -ieq $s.SelfFile) {
        $s.LastRun = $now
        $ts = $now.ToString('HH:mm:ss')
        Write-Host "[$ts] $leaf changed - exiting so you can relaunch." -ForegroundColor Magenta
        $s.ShouldExit = $true
        return
    }

    if ($s.Files -notcontains $leaf) { return }
    $s.LastRun = $now

    $ts = $now.ToString('HH:mm:ss')
    Write-Host "[$ts] $leaf changed - rebuilding..." -ForegroundColor Cyan
    try {
        Push-Location $s.Root
        & (Join-Path $s.Root 'Go.ps1')
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Build finished." -ForegroundColor Green
    } catch {
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Build failed: $_" -ForegroundColor Red
    } finally {
        Pop-Location
    }
}

$handlers = foreach ($evt in 'Changed','Created','Renamed') {
    Register-ObjectEvent -InputObject $watcher -EventName $evt -Action $handler -MessageData $state
}

Write-Stamp "Watching $($state.Root)" Yellow
Write-Stamp ("Files: " + ($state.Files -join ', ')) Yellow
Write-Stamp "Press Ctrl+C to stop." Yellow

try {
    while (-not $state.ShouldExit) { Start-Sleep -Milliseconds 250 }
} finally {
    $handlers | ForEach-Object { Unregister-Event -SourceIdentifier $_.Name -ErrorAction SilentlyContinue }
    $watcher.Dispose()
    Write-Stamp "Watcher stopped." Yellow
}
