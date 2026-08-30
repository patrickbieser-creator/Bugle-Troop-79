<#
Build-Bugle.ps1

Converts a Markdown Bugle newsletter into email-safe HTML using a template.

Rules:
- Markdown is used ONLY for text content
- Each "## Heading" becomes a new section with <hr> and a numbered badge

Requirements:
- pandoc installed and on PATH
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TemplatePath,
    [Parameter(Mandatory = $true)][string]$MarkdownPath,
    [Parameter(Mandatory = $true)][string]$OutPath,

    [Parameter(Mandatory = $false)][string]$BugleDate,
    [Parameter(Mandatory = $false)][string]$HeroImage,
    [Parameter(Mandatory = $true)][string]$LogoImage,

    [Parameter(Mandatory = $false)][string]$UnsubscribeUrl = "{{UnsubscribeURL}}",
    [Parameter(Mandatory = $false)][string]$SenderInfoLine = "{{SenderInfoLine}}",

    [Parameter(Mandatory = $false)][int]$BadgeStart = 10,
    [Parameter(Mandatory = $false)][int]$BadgeEnd = 1,
    [Parameter(Mandatory = $false)][string]$BadgeBaseUrl = "https://Troop79.b-cdn.net",

    [Parameter(Mandatory = $false)][switch]$UseIntroFromMarkdown
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -----------------------------
# Utility functions
# -----------------------------

function Assert-FileExists([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
}

function Assert-PandocAvailable {
    if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
        throw "pandoc was not found on PATH. Install from https://pandoc.org/installing.html"
    }
}

function Convert-MarkdownToHtml([string]$MarkdownText) {
    if (-not $MarkdownText -or -not $MarkdownText.Trim()) {
        return ""
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "pandoc"
    $psi.Arguments = "-f gfm+attributes -t html --wrap=none"
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    $p.StandardInput.Write($MarkdownText)
    $p.StandardInput.Close()

    $html = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()

    $p.WaitForExit()

    if ($p.ExitCode -ne 0) {
        throw "pandoc failed: $err"
    }

    return $html.Trim()
}

function HtmlEncode([string]$Text) {
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Parse-MarkdownSections([string]$Md) {
    $Md = $Md -replace "`r`n", "`n" -replace "`r", "`n"

    # Remove top-level H1 if present
    $Md = $Md -replace "(?m)^\#\s+.*\n+", ""

    $intro = ""
    $sections = @()

    $firstH2 = [regex]::Match($Md, "(?m)^\#\#\s+")
    if ($firstH2.Success) {
        $intro = $Md.Substring(0, $firstH2.Index).Trim()
        $rest = $Md.Substring($firstH2.Index).Trim()
    }
    else {
        $intro = $Md.Trim()
        $rest = ""
    }

    if ($rest) {
        $matches = [regex]::Matches(
            $rest,
            "(?ms)^\#\#\s+(?<title>[^\n]+)\n(?<body>.*?)(?=^\#\#\s+|\z)"
        )

        foreach ($m in $matches) {
            $sections += [pscustomobject]@{
                Title = $m.Groups["title"].Value.Trim()
                Body  = $m.Groups["body"].Value.Trim()
            }
        }
    }

    return [pscustomobject]@{
        IntroMd  = $intro
        Sections = $sections
    }
}

function Render-SectionHtml(
    [int]$BadgeNumber,
    [string]$Title,
    [string]$BodyHtml
) {
    $badgeHtml = ""
    if ($BadgeNumber -ge $BadgeEnd -and $BadgeNumber -le $BadgeStart) {
        $badgeHtml = "<img alt=`"$BadgeNumber`" class=`"badge`" src=`"$BadgeBaseUrl/$BadgeNumber.jpg`">"
    }

    $titleEsc = HtmlEncode $Title

    $out = @()
    $out += "<br>"
    $out += "<hr>"
    $out += "<h1 class=`"section-title`">$badgeHtml$titleEsc</h1>"
    $out += "<div style=`"height:8px; line-height:8px;`">&nbsp;</div>"

    if ($BodyHtml -and $BodyHtml.Trim()) {
        $out += $BodyHtml
    }

    return ($out -join "`n")
}

# -----------------------------
# Main
# -----------------------------

Assert-FileExists $TemplatePath "TemplatePath"
Assert-FileExists $MarkdownPath "MarkdownPath"
Assert-PandocAvailable

$template = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
$md = Get-Content -LiteralPath $MarkdownPath -Raw -Encoding UTF8

$parsed = Parse-MarkdownSections $md

# Intro block
$introHtml = ""
if ($UseIntroFromMarkdown -and $parsed.IntroMd) {
    $introHtml = Convert-MarkdownToHtml $parsed.IntroMd
}

# Build sections
$sectionsHtml = @()

# Start badge at the smaller of (BadgeStart) and (# of sections)
$badge = [Math]::Min($BadgeStart, $parsed.Sections.Count)
if ($badge -lt $BadgeEnd) { $badge = $BadgeEnd }  # safety

foreach ($s in $parsed.Sections) {

    $bodyHtml = Convert-MarkdownToHtml $s.Body

    $sectionsHtml += Render-SectionHtml `
        -BadgeNumber $badge `
        -Title $s.Title `
        -BodyHtml $bodyHtml

    if ($badge -gt $BadgeEnd) {
        $badge--
    }
}

# Fill template
$outHtml = $template
$outHtml = $outHtml.Replace("{{BUGLE_DATE}}", (HtmlEncode $BugleDate))
$outHtml = $outHtml.Replace("{{BUGLE_HERO_IMAGE}}", $HeroImage)
$outHtml = $outHtml.Replace("{{BUGLE_LOGO_IMAGE}}", $LogoImage)
$outHtml = $outHtml.Replace("{{BUGLE_INTRO_HTML}}", $introHtml)
$outHtml = $outHtml.Replace("{{BUGLE_SECTIONS_HTML}}", ($sectionsHtml -join "`n"))
$outHtml = $outHtml.Replace("{{UNSUBSCRIBE_URL}}", $UnsubscribeUrl)
$outHtml = $outHtml.Replace("{{SENDER_INFO_LINE}}", $SenderInfoLine)

# Write output
$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
}

Set-Content -LiteralPath $OutPath -Value $outHtml -Encoding UTF8
Write-Host "Built Bugle HTML: $OutPath"

