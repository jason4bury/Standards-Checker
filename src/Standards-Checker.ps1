<#
.SYNOPSIS
    Checks every Home tool against the Launcher & GitHub house style and reports pass/fail per rule.

.DESCRIPTION
    Scans each project folder under E:\Created\Home (and Home\Private when the vault is unlocked)
    and checks the repo files and versions against the "Launcher & GitHub Standards Proposal":
    Source\ and Builds\ layout, README headings and badge row, CHANGELOG, MIT LICENSE,
    build.json / launcher.json, exe names and versions, Docker files, git hygiene and the
    GitHub About box and visibility.

    It only reads. It never changes, creates or deletes a file, and never writes to git or GitHub.
    The only outside commands it runs are "git ls-files" / "git remote get-url" (read the repo)
    and "gh repo view" (read the GitHub About box and visibility). Use -Offline to skip GitHub.

    It checks repo files and version numbers only. It does not judge how an app's GUI looks:
    house style never restyles an app's GUI.

    Version:   1.00 (keep in step with CHANGELOG.md)

.PARAMETER Root
    The Home folder to scan. Default: E:\Created\Home

.PARAMETER Tool
    Only check tools whose folder name matches this wildcard, e.g. "TV-*".

.PARAMETER IncludeShared
    Also check repos under E:\Created\_shared (e.g. Launcher-Engine).

.PARAMETER Offline
    Skip the GitHub checks (About box, topics, visibility).

.PARAMETER FailuresOnly
    Only show rules that did not pass.

.PARAMETER CsvPath
    Also save every result to this CSV file. This is the only file the script writes, and only
    when you ask for it.

.PARAMETER PassThru
    Return the result objects to the pipeline as well as printing them.

.EXAMPLE
    .\Standards-Checker.ps1

.EXAMPLE
    .\Standards-Checker.ps1 -Tool "Stash-*" -FailuresOnly

.EXAMPLE
    .\Standards-Checker.ps1 -CsvPath "$env:USERPROFILE\Desktop\standards.csv"

.NOTES
    Exit code: 0 when nothing failed, 1 when at least one rule failed.
    Runs on Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param(
    [string]$Root = 'E:\Created\Home',
    [string]$Tool = '*',
    [switch]$IncludeShared,
    [switch]$Offline,
    [switch]$FailuresOnly,
    [string]$CsvPath,
    [switch]$PassThru
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppVersion = '1.00'
$script:GitHubOwner = 'jason4bury'
$script:CopyrightName = 'Jason Rhodes'

# ---------------------------------------------------------------------------------------------
# House-style constants
# Emoji are built from code points so this file stays plain ASCII (safe in PowerShell 5.1).
# ---------------------------------------------------------------------------------------------
function U([int]$CodePoint) { [char]::ConvertFromUtf32($CodePoint) }

# README H2 sections, in the required order, each with its emoji.
$script:Sections = @(
    [pscustomobject]@{ Name = 'Features';      Emoji = (U 0x2728)  }
    [pscustomobject]@{ Name = 'Screenshots';   Emoji = (U 0x1F5BC) }
    [pscustomobject]@{ Name = 'Requirements';  Emoji = (U 0x1F4CB) }
    [pscustomobject]@{ Name = 'Installation';  Emoji = (U 0x1F4E6) }
    [pscustomobject]@{ Name = 'Usage';         Emoji = (U 0x1F680) }
    [pscustomobject]@{ Name = 'Configuration'; Emoji = (U 0x2699)  }
    [pscustomobject]@{ Name = 'Changelog';     Emoji = (U 0x1F4DD) }
    [pscustomobject]@{ Name = 'Licence';       Emoji = (U 0x1F4C4) }
)
$script:RequiredSections = @('Features', 'Requirements', 'Installation', 'Usage', 'Changelog', 'Licence')

# Badge order: version, platform, language, licence, last commit.
$script:BadgeOrder = @('version', 'platform', 'language', 'licence', 'last commit')
$script:LanguageBadges = 'powershell|python|node\.?js|javascript|typescript|c#|csharp'

# Folder / repo / script names: Title-Case-With-Hyphens (MP3 and similar all-caps parts allowed).
$script:TitleCaseName = '^[A-Z0-9][A-Za-z0-9]*(-[A-Z0-9][A-Za-z0-9]*)*$'
# Versions: v<major>.<two-digit minor>
$script:VersionText = '\d+\.\d{2}'
# About box: "<Language>/<UI> tool for <what it does>"
$script:AboutFormula = '^[A-Za-z0-9.#+]+/[A-Za-z0-9.#+]+ tool for \S'

# ---------------------------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------------------------
$script:Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [Parameter(Mandatory)] [string]$Project,
        [Parameter(Mandatory)] [string]$Area,
        [Parameter(Mandatory)] [string]$Rule,
        [Parameter(Mandatory)] [ValidateSet('PASS', 'FAIL', 'WARN', 'INFO', 'SKIP')] [string]$Status,
        [string]$Detail = ''
    )
    $script:Results.Add([pscustomobject]@{
        Project = $Project
        Area    = $Area
        Rule    = $Rule
        Status  = $Status
        Detail  = $Detail
    })
}

# Shorthand: PASS when $Ok, otherwise $FailStatus (FAIL by default).
function Test-Rule {
    param(
        [string]$Project, [string]$Area, [string]$Rule, [bool]$Ok,
        [string]$FailDetail = '', [string]$PassDetail = '', [string]$FailStatus = 'FAIL'
    )
    if ($Ok) { Add-Result $Project $Area $Rule 'PASS' $PassDetail }
    else     { Add-Result $Project $Area $Rule $FailStatus $FailDetail }
}

# ---------------------------------------------------------------------------------------------
# Read-only helpers
# ---------------------------------------------------------------------------------------------
function Read-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Read-Json([string]$Path) {
    $text = Read-Text $Path
    if ($null -eq $text) { return $null }
    try { $text | ConvertFrom-Json } catch { 'INVALID' }
}

function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object -or $Object -is [string]) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

# Turns "1.07", "v1.07" or "1.7.0" into a comparable [version] (major.minor).
function ConvertTo-Ver([string]$Text) {
    if ($Text -match '(\d+)\.(\d+)') { return [version]::new([int]$Matches[1], [int]$Matches[2]) }
    $null
}

# Runs git against a repo without changing it. -c safe.directory avoids the
# "dubious ownership" stop on drives formatted by another user; it is not saved anywhere.
function Invoke-GitRead([string]$Repo, [string[]]$GitArgs) {
    if (-not $script:HasGit) { return $null }
    $out = & git -c safe.directory=* -C $Repo @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    @($out)
}

function Get-PlainText([string]$Text) { $Text -replace [char]0xFE0F, '' }

# ---------------------------------------------------------------------------------------------
# README checks
# ---------------------------------------------------------------------------------------------
function Test-Readme {
    param([string]$Name, [string]$Source, [bool]$IsPrivate, [string]$ChangelogVersion)

    $area = 'README'
    $path = Join-Path $Source 'README.md'
    $text = Read-Text $path
    Test-Rule $Name $area 'README.md present in Source\' ($null -ne $text) 'README.md is missing'
    if ($null -eq $text) { return }

    $lines = $text -split "`r?`n"

    # --- H1 title ---------------------------------------------------------------------------
    $h1Index = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^# \S') { $h1Index = $i; break } }
    Test-Rule $Name $area 'H1 title' ($h1Index -ge 0) 'No "# Title" line found'
    if ($h1Index -lt 0) { return }

    # Only a banner/icon may sit above the title.
    $above = @($lines[0..([Math]::Max(0, $h1Index - 1))] | Where-Object { $h1Index -gt 0 -and $_.Trim() -ne '' })
    $aboveOk = $true
    foreach ($l in $above) {
        if ($l -notmatch '(?i)<img|<p\b|</p>|<div\b|</div>|^!\[|<picture|</picture|<source') { $aboveOk = $false }
    }
    Test-Rule $Name $area 'Only a banner or icon above the title' $aboveOk 'There is text above the H1 title' -FailStatus 'WARN'

    # --- Tagline then badge row -------------------------------------------------------------
    $i = $h1Index + 1
    while ($i -lt $lines.Count -and $lines[$i].Trim() -eq '') { $i++ }
    $taglineIndex = $i
    $tagline = if ($i -lt $lines.Count) { $lines[$i] } else { '' }
    $taglineOk = $tagline -ne '' -and $tagline -notmatch '^\s*(#|!\[|\[!\[|<img)'
    Test-Rule $Name $area 'One-line tagline under the title' $taglineOk 'The line after the title is not a tagline'

    # Badge row: the next non-blank block after the tagline, made only of badge images.
    $i = $taglineIndex + 1
    while ($i -lt $lines.Count -and $lines[$i].Trim() -eq '') { $i++ }
    $badgeLines = New-Object System.Collections.Generic.List[string]
    while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '' -and $lines[$i] -match 'img\.shields\.io') {
        $badgeLines.Add($lines[$i]); $i++
    }
    $badgeRowOk = $badgeLines.Count -gt 0
    $anyBadges = $text -match 'img\.shields\.io'
    $detail = if ($anyBadges) { 'Badges found, but not directly under the tagline' } else { 'No shields.io badges found' }
    Test-Rule $Name $area 'Badge row directly under the tagline' $badgeRowOk $detail
    if (-not $badgeRowOk) { return }

    # Classify each badge from its alt text and URL.
    $badgeText = $badgeLines -join ' '
    $badges = [regex]::Matches($badgeText, '!\[([^\]]*)\]\(([^)\s]+)')
    $kinds = New-Object System.Collections.Generic.List[string]
    $versionBadge = $null
    foreach ($b in $badges) {
        $alt = $b.Groups[1].Value; $url = $b.Groups[2].Value
        $both = "$alt $url"
        $kind = 'other'
        if     ($url -match '(?i)/last-commit/' -or $alt -match '(?i)last.?commit') { $kind = 'last commit' }
        elseif ($alt -match '(?i)^version$' -or $url -match '(?i)/badge/version-') {
            $kind = 'version'
            if ($url -match '(?i)/badge/version-v?(\d+\.\d+)') { $versionBadge = $Matches[1] }
        }
        elseif ($both -match '(?i)platform') { $kind = 'platform' }
        elseif ($both -match '(?i)licen[cs]e') { $kind = 'licence' }
        elseif ($both -match "(?i)$($script:LanguageBadges)") { $kind = 'language' }
        $kinds.Add($kind)
    }
    $kindList = ($kinds -join ', ')

    # Expected set: private repos leave out the Last-commit badge (it can't read a private repo).
    $expected = if ($IsPrivate) { $script:BadgeOrder | Where-Object { $_ -ne 'last commit' } } else { $script:BadgeOrder }
    $expectedList = ($expected -join ', ')
    Test-Rule $Name $area 'Badge order: version, platform, language, licence[, last commit]' `
        ($kindList -eq $expectedList) "Found: $kindList. Expected: $expectedList" "$kindList"

    if ($IsPrivate) {
        Test-Rule $Name $area 'Private repo has no Last-commit badge' (-not $kinds.Contains('last commit')) `
            'Private repo shows a Last-commit badge (it shows "repo not found" on GitHub)'
    }
    else {
        Test-Rule $Name $area 'Public repo has the Last-commit badge' ($kinds.Contains('last commit')) 'Last-commit badge is missing'
    }

    if ($kinds.Contains('version') -and $ChangelogVersion) {
        $ok = $versionBadge -and ((ConvertTo-Ver $versionBadge) -eq (ConvertTo-Ver $ChangelogVersion)) -and $versionBadge -match "^$($script:VersionText)$"
        Test-Rule $Name $area 'Version badge matches CHANGELOG' $ok "Badge says v$versionBadge, CHANGELOG says v$ChangelogVersion" "v$versionBadge"
    }

    # --- H2 sections: emoji, names and order --------------------------------------------------
    $h2 = @($lines | Where-Object { $_ -match '^## ' } | ForEach-Object { ($_ -replace '^##\s+', '').Trim() })
    $found = New-Object System.Collections.Generic.List[object]
    $emojiProblems = New-Object System.Collections.Generic.List[string]
    $unknown = New-Object System.Collections.Generic.List[string]
    foreach ($heading in $h2) {
        $clean = Get-PlainText $heading
        $match = $null
        foreach ($s in $script:Sections) {
            if ($clean -match "(?i)\b$($s.Name)\b" -or ($s.Name -eq 'Licence' -and $clean -match '(?i)\bLicense\b')) { $match = $s; break }
        }
        if ($null -eq $match) { $unknown.Add($heading); continue }
        $found.Add($match)
        $wanted = "$($match.Emoji) $($match.Name)"
        if ($clean -ne $wanted) { $emojiProblems.Add("'$heading' should be '$wanted'") }
    }

    Test-Rule $Name $area 'Every H2 starts with its house-style emoji' ($emojiProblems.Count -eq 0) ($emojiProblems -join '; ')

    $order = @($found | ForEach-Object { [array]::IndexOf(@($script:Sections.Name), $_.Name) })
    $sorted = @($order | Sort-Object)
    $inOrder = ($order -join ',') -eq ($sorted -join ',')
    Test-Rule $Name $area 'H2 sections in house-style order' $inOrder ("Order found: " + (($found | ForEach-Object Name) -join ', '))

    $missing = @($script:RequiredSections | Where-Object { @($found.Name) -notcontains $_ })
    Test-Rule $Name $area 'Core sections present (Features, Requirements, Installation, Usage, Changelog, Licence)' `
        ($missing.Count -eq 0) ("Missing: " + ($missing -join ', ')) -FailStatus 'WARN'

    if ($unknown.Count -gt 0) {
        Add-Result $Name $area 'No sections outside the house-style list' 'WARN' ("Extra H2: " + ($unknown -join '; '))
    }
    else {
        Add-Result $Name $area 'No sections outside the house-style list' 'PASS'
    }

    Test-Rule $Name $area 'Changelog section links to CHANGELOG.md' ($text -match '\(CHANGELOG\.md\)') 'No link to CHANGELOG.md' -FailStatus 'WARN'
}

# ---------------------------------------------------------------------------------------------
# CHANGELOG checks. Returns the current (latest released) version, e.g. "1.07".
# ---------------------------------------------------------------------------------------------
function Test-Changelog {
    param([string]$Name, [string]$Source)

    $area = 'CHANGELOG'
    $text = Read-Text (Join-Path $Source 'CHANGELOG.md')
    Test-Rule $Name $area 'CHANGELOG.md present in Source\' ($null -ne $text) 'CHANGELOG.md is missing'
    if ($null -eq $text) { return $null }

    Test-Rule $Name $area 'Starts with "# Changelog"' ($text -match '(?m)^# Changelog\s*$') 'No "# Changelog" heading' -FailStatus 'WARN'
    Test-Rule $Name $area 'Has an [Unreleased] section' ($text -match '(?m)^## \[Unreleased\]') 'No "## [Unreleased]" heading' -FailStatus 'WARN'

    $entries = [regex]::Matches($text, '(?m)^## \[(?!Unreleased)([^\]]+)\](.*)$')
    Test-Rule $Name $area 'Has at least one version entry' ($entries.Count -gt 0) 'No "## [x.yy] - date" entries'
    if ($entries.Count -eq 0) { return $null }

    $bad = @($entries | Where-Object {
        $_.Groups[1].Value -notmatch "^$($script:VersionText)$" -or $_.Groups[2].Value -notmatch '^\s+-\s+\d{4}-\d{2}-\d{2}\s*$'
    } | ForEach-Object { "[$($_.Groups[1].Value)]$($_.Groups[2].Value)" })
    Test-Rule $Name $area 'Entries use "## [x.yy] - YYYY-MM-DD"' ($bad.Count -eq 0) ("Not in the house format: " + ($bad -join '; '))

    # Current version = highest numbered entry; it should also be the first one listed.
    $versions = @($entries | ForEach-Object { $_.Groups[1].Value } | Where-Object { ConvertTo-Ver $_ })
    if ($versions.Count -eq 0) { return $null }
    $current = $versions | Sort-Object { ConvertTo-Ver $_ } -Descending | Select-Object -First 1
    Test-Rule $Name $area 'Newest version is listed first' ($versions[0] -eq $current) "First entry is $($versions[0]) but $current is higher" -FailStatus 'WARN'
    Add-Result $Name $area 'Current version' 'INFO' "v$current"
    $current
}

# ---------------------------------------------------------------------------------------------
# LICENSE
# ---------------------------------------------------------------------------------------------
function Test-License {
    param([string]$Name, [string]$Source)
    $area = 'LICENSE'
    $text = Read-Text (Join-Path $Source 'LICENSE')
    Test-Rule $Name $area 'LICENSE present in Source\' ($null -ne $text) 'LICENSE is missing'
    if ($null -eq $text) { return }
    Test-Rule $Name $area 'MIT licence' ($text -match '^\s*MIT License') 'LICENSE is not the MIT licence'
    $line = ($text -split "`r?`n" | Where-Object { $_ -match '^\s*Copyright' } | Select-Object -First 1)
    Test-Rule $Name $area "Copyright (c) <year> $($script:CopyrightName)" `
        ($line -match "^\s*Copyright \(c\) \d{4}(-\d{4})? $([regex]::Escape($script:CopyrightName))\s*$") "Found: $line" $line
}

# ---------------------------------------------------------------------------------------------
# Git hygiene (reads the index only)
# ---------------------------------------------------------------------------------------------
function Test-Git {
    param([string]$Name, [string]$Source, [bool]$IsDocker)
    $area = 'Git'

    $isRepo = Test-Path -LiteralPath (Join-Path $Source '.git')
    Test-Rule $Name $area 'Source\ is a git repo' $isRepo 'No .git folder in Source\'

    $gi = Read-Text (Join-Path $Source '.gitignore')
    Test-Rule $Name $area '.gitignore present' ($null -ne $gi) '.gitignore is missing'
    if ($null -ne $gi) {
        $giLines = @($gi -split "`r?`n" | ForEach-Object { $_.Trim() })
        Test-Rule $Name $area '.gitignore excludes *.exe' ($giLines -contains '*.exe') '*.exe is not in .gitignore'
        Test-Rule $Name $area '.gitignore excludes config.local.json' (($giLines -match '^/?config\.local\.json$').Count -gt 0) `
            'config.local.json is not in .gitignore' -FailStatus 'WARN'
        $logs = @(Get-ChildItem -LiteralPath $Source -Filter *.log -File -ErrorAction SilentlyContinue)
        if ($logs.Count -gt 0) {
            Test-Rule $Name $area '.gitignore excludes *.log (log files are present)' ($giLines -contains '*.log') `
                ("*.log not ignored; found " + ($logs.Name -join ', '))
        }
        if ($IsDocker) {
            Test-Rule $Name $area '.gitignore excludes .env' (($giLines -match '^/?\.env$').Count -gt 0) '.env is not in .gitignore'
            Test-Rule $Name $area '.gitignore excludes node_modules' (($giLines -match '^/?node_modules/?$').Count -gt 0) 'node_modules is not in .gitignore'
        }
    }

    # Exe files sitting inside Source\ (excluding node_modules and .git).
    $exes = @(Get-ChildItem -LiteralPath $Source -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(node_modules|\.git)\\' })
    Test-Rule $Name $area 'No exe files inside Source\' ($exes.Count -eq 0) `
        ("Found: " + (($exes | ForEach-Object { $_.FullName.Substring($Source.Length + 1) }) -join ', '))

    if (-not $isRepo) { return }
    if (-not $script:HasGit) { Add-Result $Name $area 'Tracked-file checks' 'SKIP' 'git is not installed'; return }

    $tracked = Invoke-GitRead $Source @('ls-files')
    if ($null -eq $tracked) { Add-Result $Name $area 'Tracked-file checks' 'SKIP' 'git ls-files failed'; return }
    $trackedExe = @($tracked | Where-Object { $_ -match '(?i)\.exe$' })
    Test-Rule $Name $area 'No exe tracked by git' ($trackedExe.Count -eq 0) ("Tracked: " + ($trackedExe -join ', '))
    $secrets = @($tracked | Where-Object { $_ -match '(?i)(^|/)(\.env|config\.local\.json)$' })
    Test-Rule $Name $area 'No .env or config.local.json tracked by git' ($secrets.Count -eq 0) ("Tracked: " + ($secrets -join ', '))
}

# ---------------------------------------------------------------------------------------------
# build.json, launcher.json, exe names and script version (PowerShell tools)
# ---------------------------------------------------------------------------------------------
function Test-Build {
    param([string]$Name, [string]$ProjectPath, [string]$Source, [string]$ChangelogVersion)
    $area = 'Build'

    $buildPath = Join-Path $Source 'build.json'
    $build = Read-Json $buildPath
    Test-Rule $Name $area 'build.json present in Source\' ($null -ne $build) 'build.json is missing'
    if ($null -eq $build) { return $null }
    if ($build -eq 'INVALID') { Add-Result $Name $area 'build.json is valid JSON' 'FAIL' 'build.json could not be read as JSON'; return $null }

    $appName = Get-Prop $build 'AppName'
    $entry = Get-Prop $build 'EntryScript'
    $icon = Get-Prop $build 'Icon'
    Test-Rule $Name $area 'build.json has AppName' ([bool]$appName) 'AppName is missing'
    Test-Rule $Name $area 'build.json has EntryScript' ([bool]$entry) 'EntryScript is missing'

    if ($appName) {
        $expectedFolder = $appName -replace ' ', '-'
        Test-Rule $Name $area 'Folder name matches AppName' ($expectedFolder -eq $Name) `
            "AppName '$appName' would give folder '$expectedFolder'" -FailStatus 'WARN'
    }

    $entryPath = $null
    if ($entry) {
        $entryPath = Join-Path $Source $entry
        Test-Rule $Name $area 'EntryScript file exists' (Test-Path -LiteralPath $entryPath -PathType Leaf) "Not found: $entry"
        $leaf = [System.IO.Path]::GetFileNameWithoutExtension($entry)
        Test-Rule $Name $area 'Main script named after the folder' ($leaf -eq $Name) "Main script is $leaf, folder is $Name" -FailStatus 'WARN'
    }
    if ($icon) {
        Test-Rule $Name $area 'Icon file exists' (Test-Path -LiteralPath (Join-Path $Source $icon) -PathType Leaf) "Not found: $icon"
    }
    else {
        Add-Result $Name $area 'build.json has Icon' 'WARN' 'Icon is not set'
    }

    # Version inside the script (VersionFile if build.json names one, otherwise EntryScript).
    $versionFile = Get-Prop $build 'VersionFile'
    $vPath = if ($versionFile) { Join-Path $Source $versionFile } else { $entryPath }
    if ($vPath -and (Test-Path -LiteralPath $vPath -PathType Leaf) -and $ChangelogVersion) {
        $m = Select-String -LiteralPath $vPath -Pattern '^\s*\$(?:script:|global:)?\w*Version\s*=\s*[''"]v?(\d+\.\d+)[''"]' | Select-Object -First 1
        if ($m) {
            $sv = $m.Matches[0].Groups[1].Value
            Test-Rule $Name $area 'Script version matches CHANGELOG' ((ConvertTo-Ver $sv) -eq (ConvertTo-Ver $ChangelogVersion)) `
                "Script says $sv, CHANGELOG says $ChangelogVersion" "v$sv"
        }
        else {
            Add-Result $Name $area 'Script version matches CHANGELOG' 'WARN' "No `$...Version = 'x.yy' line found in $([System.IO.Path]::GetFileName($vPath))"
        }
    }

    # --- Builds\ ---------------------------------------------------------------------------
    $builds = Join-Path $ProjectPath 'Builds'
    if (-not (Test-Path -LiteralPath $builds -PathType Container)) { return $build }
    $exeFiles = @(Get-ChildItem -LiteralPath $builds -Filter *.exe -File -ErrorAction SilentlyContinue)
    Test-Rule $Name 'Exe' 'Builds\ has at least one exe' ($exeFiles.Count -gt 0) 'No exe in Builds\'
    if ($exeFiles.Count -eq 0 -or -not $appName) { return $build }

    $pattern = '^' + [regex]::Escape($appName) + ' v(' + $script:VersionText + ')\.exe$'
    $badNames = @($exeFiles | Where-Object { $_.Name -notmatch $pattern } | ForEach-Object Name)
    Test-Rule $Name 'Exe' "Exe names follow '<App Name> v<x.yy>.exe'" ($badNames.Count -eq 0) ("Not matching '$appName vX.YY.exe': " + ($badNames -join ', '))

    $named = @($exeFiles | Where-Object { $_.Name -match $pattern } | ForEach-Object {
        $null = $_.Name -match $pattern; [pscustomobject]@{ Name = $_.Name; Ver = ConvertTo-Ver $Matches[1]; Text = $Matches[1] } })
    if ($ChangelogVersion) {
        $wanted = "$appName v$ChangelogVersion.exe"
        Test-Rule $Name 'Exe' 'Exe for the CHANGELOG version is in Builds\' (Test-Path -LiteralPath (Join-Path $builds $wanted)) "Missing: $wanted" $wanted
        if ($named.Count -gt 0) {
            $top = $named | Sort-Object Ver -Descending | Select-Object -First 1
            Test-Rule $Name 'Exe' 'Newest exe matches the CHANGELOG version' ($top.Ver -eq (ConvertTo-Ver $ChangelogVersion)) `
                "Newest exe is $($top.Name), CHANGELOG is v$ChangelogVersion"
        }
    }
    $others = @(Get-ChildItem -LiteralPath $builds -Force -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne '.exe' })
    if ($others.Count -gt 0) { Add-Result $Name 'Exe' 'Only exe files in Builds\' 'INFO' ("Also there: " + ($others.Name -join ', ')) }
    $build
}

function Test-Launcher {
    param([string]$Name, [string]$Source)
    $path = Join-Path $Source 'launcher.json'
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Result $Name 'Launcher' 'launcher.json (optional)' 'INFO' 'Not present; the launcher uses the folder name and defaults'
        return
    }
    $j = Read-Json $path
    Test-Rule $Name 'Launcher' 'launcher.json is valid JSON' ($j -ne 'INVALID') 'launcher.json could not be read as JSON'
}

# ---------------------------------------------------------------------------------------------
# Docker apps (Node.js web apps)
# ---------------------------------------------------------------------------------------------
function Test-Docker {
    param([string]$Name, [string]$Source, [string]$ChangelogVersion)
    $area = 'Docker'
    Test-Rule $Name $area 'docker-compose.yml in the repo root' (Test-Path -LiteralPath (Join-Path $Source 'docker-compose.yml')) 'docker-compose.yml is missing'
    Test-Rule $Name $area '.env.example committed' (Test-Path -LiteralPath (Join-Path $Source '.env.example')) '.env.example is missing'

    $df = Read-Text (Join-Path $Source 'Dockerfile')
    Test-Rule $Name $area 'Dockerfile in the repo root' ($null -ne $df) 'Dockerfile is missing'
    if ($df) {
        # Pinned = an exact x.y.z Node tag, either on FROM or in an ARG used by FROM.
        $pinned = $df -match '(?im)node:\d+\.\d+\.\d+'
        Test-Rule $Name $area 'Dockerfile pins an exact Node.js version' $pinned 'No node:<x.y.z> tag found (e.g. node:22 or node:latest is not pinned)'
    }

    $pkg = Read-Json (Join-Path $Source 'package.json')
    if ($pkg -and $pkg -ne 'INVALID' -and $ChangelogVersion) {
        $pv = Get-Prop $pkg 'version'
        Test-Rule $Name $area 'package.json version matches CHANGELOG' ((ConvertTo-Ver $pv) -eq (ConvertTo-Ver $ChangelogVersion)) `
            "package.json says $pv, CHANGELOG says $ChangelogVersion" "$pv"
    }
}

# ---------------------------------------------------------------------------------------------
# GitHub: About box, topics, visibility, repo name (read only, via gh)
# ---------------------------------------------------------------------------------------------
# Reads the origin remote and, when online, the GitHub repo details. Changes nothing.
function Get-RepoInfo {
    param([string]$Source)
    $result = [pscustomobject]@{ Repo = $null; Info = $null; Why = '' }
    $remote = @(Invoke-GitRead $Source @('remote', 'get-url', 'origin'))
    if ($remote.Count -gt 0 -and ([string]$remote[0] -match 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?/?$')) {
        $result.Repo = "$($Matches[1])/$($Matches[2])"
    }
    if ($Offline)                { $result.Why = '-Offline'; return $result }
    if (-not $script:HasGh)      { $result.Why = 'gh is not installed or not signed in'; return $result }
    if (-not $result.Repo)       { $result.Why = 'no GitHub remote'; return $result }
    $json = & gh repo view $result.Repo --json description,visibility,repositoryTopics 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { $result.Why = "gh could not read $($result.Repo)"; return $result }
    $result.Info = ($json -join "`n") | ConvertFrom-Json
    $result
}

function Test-GitHub {
    param([string]$Name, [bool]$IsPrivate, $Build, $Gh)
    $area = 'GitHub'

    $repo = $Gh.Repo
    Test-Rule $Name $area 'origin points at a GitHub repo' ([bool]$repo) 'No GitHub origin remote' "$repo"
    if ($repo) {
        Test-Rule $Name $area 'Repo name matches the folder' (($repo -split '/')[1] -eq $Name) "Repo is $repo, folder is $Name"
    }

    # About description from build.json (if it keeps a copy) - checked even offline.
    $localDesc = Get-Prop $Build 'Description'

    if ($null -eq $Gh.Info) {
        $status = if ($Gh.Why -like 'gh could not*') { 'FAIL' } else { 'SKIP' }
        Add-Result $Name $area 'GitHub About box, topics and visibility' $status $Gh.Why
        if ($localDesc) {
            Test-Rule $Name $area 'build.json Description follows the About formula' ($localDesc -match $script:AboutFormula) `
                "'$localDesc' is not '<Language>/<UI> tool for ...'" -FailStatus 'WARN'
        }
        return
    }

    $info = $Gh.Info
    $desc = [string]$info.description
    $vis = [string]$info.visibility
    $topics = @(@(Get-Prop $info 'repositoryTopics') | Where-Object { $_ } | ForEach-Object { $_.name })

    Test-Rule $Name $area 'About description present' ($desc.Trim() -ne '') 'The repo has no About description'
    if ($desc.Trim() -ne '') {
        Test-Rule $Name $area "About follows '<Language>/<UI> tool for <what it does>'" ($desc -match $script:AboutFormula) "Is: $desc" $desc
    }
    if ($localDesc -and $desc) {
        Test-Rule $Name $area 'build.json Description matches GitHub About' ($localDesc.Trim() -eq $desc.Trim()) `
            "build.json: '$localDesc'" -FailStatus 'WARN'
    }
    Test-Rule $Name $area 'About topics set' ($topics.Count -gt 0) 'No topics on the repo' ($topics -join ', ') -FailStatus 'WARN'

    if ($IsPrivate) {
        Test-Rule $Name $area 'Private tool has a PRIVATE repo' ($vis -eq 'PRIVATE') "Repo is $vis"
    }
    else {
        Add-Result $Name $area 'Repo visibility' 'INFO' $vis
    }
}

# ---------------------------------------------------------------------------------------------
# One project
# ---------------------------------------------------------------------------------------------
function Test-Project {
    param([System.IO.DirectoryInfo]$Dir, [bool]$IsPrivate)

    $name = $Dir.Name
    $path = $Dir.FullName
    $source = Join-Path $path 'Source'

    Test-Rule $name 'Layout' 'Folder name is Title-Case-With-Hyphens' ($name -cmatch $script:TitleCaseName) "'$name' is not Title-Case-With-Hyphens"
    $hasSource = Test-Path -LiteralPath $source -PathType Container
    Test-Rule $name 'Layout' 'Source\ folder' $hasSource 'No Source\ folder'
    if (-not $hasSource) { return }

    $isDocker = Test-Path -LiteralPath (Join-Path $source 'docker-compose.yml')
    if ($isDocker) { Add-Result $name 'Layout' 'Project type' 'INFO' 'Docker app (no exe, no build.json expected)' }

    $hasBuilds = Test-Path -LiteralPath (Join-Path $path 'Builds') -PathType Container
    if ($isDocker) { Test-Rule $name 'Layout' 'Builds\ folder' $hasBuilds 'No Builds\ folder (empty is fine for a Docker app)' -FailStatus 'WARN' }
    else           { Test-Rule $name 'Layout' 'Builds\ folder' $hasBuilds 'No Builds\ folder' }

    foreach ($d in 'src', 'docs', 'assets') {
        if (-not ($isDocker -and $d -eq 'src')) {
            Test-Rule $name 'Layout' "Source\$d\ folder" (Test-Path -LiteralPath (Join-Path $source $d) -PathType Container) "No Source\$d\" -FailStatus 'WARN'
        }
    }

    $extra = @(Get-ChildItem -LiteralPath $path -Force | Where-Object { $_.Name -notin @('Source', 'Builds') })
    if ($extra.Count -gt 0) { Add-Result $name 'Layout' 'Only Source\ and Builds\ in the project folder' 'INFO' ("Also there: " + ($extra.Name -join ', ')) }
    else { Add-Result $name 'Layout' 'Only Source\ and Builds\ in the project folder' 'PASS' }

    # A repo counts as private for the badge rule when it sits in Home\Private, build.json says
    # "Private": true, or GitHub reports it as PRIVATE (a Home tool may choose a private repo).
    $gh = Get-RepoInfo $source
    $buildJson = Read-Json (Join-Path $source 'build.json')
    $privateRepo = $IsPrivate -or ((Get-Prop $buildJson 'Private') -eq $true) -or
        ($gh.Info -and [string]$gh.Info.visibility -eq 'PRIVATE')

    $version = Test-Changelog $name $source
    Test-Readme $name $source $privateRepo $version
    Test-License $name $source
    Test-Git $name $source $isDocker

    $build = $null
    if ($isDocker) { Test-Docker $name $source $version }
    else { $build = Test-Build $name $path $source $version }
    Test-Launcher $name $source
    Test-GitHub $name $IsPrivate $build $gh
}

# ---------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------
$script:Colours = @{ PASS = 'Green'; FAIL = 'Red'; WARN = 'Yellow'; INFO = 'Cyan'; SKIP = 'DarkGray' }

function Write-Report {
    $projects = $script:Results | Group-Object Project
    foreach ($p in $projects) {
        $fails = @($p.Group | Where-Object Status -eq 'FAIL').Count
        $warns = @($p.Group | Where-Object Status -eq 'WARN').Count
        $head = if ($fails) { 'Red' } elseif ($warns) { 'Yellow' } else { 'Green' }
        Write-Host ''
        Write-Host ("=== {0}  ({1} fail, {2} warn)" -f $p.Name, $fails, $warns) -ForegroundColor $head
        $rows = $p.Group
        if ($FailuresOnly) { $rows = @($rows | Where-Object { $_.Status -in 'FAIL', 'WARN' }) }
        foreach ($r in $rows) {
            Write-Host ("  [{0}] " -f $r.Status) -ForegroundColor $script:Colours[$r.Status] -NoNewline
            Write-Host ("{0,-9} {1}" -f $r.Area, $r.Rule) -NoNewline
            if ($r.Detail) { Write-Host "  - $($r.Detail)" -ForegroundColor DarkGray } else { Write-Host '' }
        }
    }

    Write-Host ''
    Write-Host '=== Summary' -ForegroundColor White
    $summary = foreach ($p in $projects) {
        [pscustomobject]@{
            Project = $p.Name
            Pass    = @($p.Group | Where-Object Status -eq 'PASS').Count
            Fail    = @($p.Group | Where-Object Status -eq 'FAIL').Count
            Warn    = @($p.Group | Where-Object Status -eq 'WARN').Count
        }
    }
    $summary | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------
$script:HasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
$script:HasGh = $false
if (-not $Offline -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    $null = & gh auth status 2>&1
    $script:HasGh = ($LASTEXITCODE -eq 0)
}

Write-Host "Standards Checker v$($script:AppVersion) - read only, nothing is changed" -ForegroundColor White
Write-Host "Root: $Root"

if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Root folder not found: $Root" }

$targets = New-Object System.Collections.Generic.List[object]
foreach ($d in Get-ChildItem -LiteralPath $Root -Directory | Where-Object { $_.Name -notmatch '^_' -and $_.Name -ne 'Private' }) {
    $targets.Add([pscustomobject]@{ Dir = $d; Private = $false })
}

$privateRoot = Join-Path $Root 'Private'
$privateDirs = $null
try { $privateDirs = @(Get-ChildItem -LiteralPath $privateRoot -Directory -ErrorAction Stop) } catch { $privateDirs = $null }
if ($null -eq $privateDirs) {
    Write-Host "Home\Private is locked or missing - private tools skipped." -ForegroundColor Yellow
}
else {
    foreach ($d in $privateDirs) { $targets.Add([pscustomobject]@{ Dir = $d; Private = $true }) }
}

if ($IncludeShared) {
    $shared = Join-Path (Split-Path $Root -Parent) '_shared'
    foreach ($d in Get-ChildItem -LiteralPath $shared -Directory -ErrorAction SilentlyContinue) {
        if (Test-Path -LiteralPath (Join-Path $d.FullName 'Source')) { $targets.Add([pscustomobject]@{ Dir = $d; Private = $false }) }
    }
}

$targets = @($targets | Where-Object { $_.Dir.Name -like $Tool })
if ($targets.Count -eq 0) { Write-Host "No tools matched '$Tool'." -ForegroundColor Yellow; exit 0 }
Write-Host ("Checking {0} tool(s){1}" -f $targets.Count, $(if ($script:HasGh) { ', with GitHub' } else { ', without GitHub' }))

foreach ($t in $targets) {
    try { Test-Project -Dir $t.Dir -IsPrivate $t.Private }
    catch { Add-Result $t.Dir.Name 'Checker' 'Checker ran' 'FAIL' "Checker error: $($_.Exception.Message)" }
}

Write-Report

if ($CsvPath) {
    $script:Results | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results saved to $CsvPath"
}
if ($PassThru) { $script:Results }

$failCount = @($script:Results | Where-Object Status -eq 'FAIL').Count
if ($failCount -gt 0) { exit 1 } else { exit 0 }
