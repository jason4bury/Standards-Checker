# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with versions written as
v<major>.<minor>.

## [Unreleased]

## [1.05] - 2026-11-21
### Changed
- **Works from any folder.** The Home folder to check is no longer fixed: it is the `Home` folder
  beside the `_shared` folder the checker is kept in (or `-Root`), else the current folder.
- **New `-CopyrightName`** for the LICENSE rule; by default it is your git `user.name`.
- The help example uses `TV-*`.

## [1.04] - 2026-11-21
### Added
- **Standards Checker.cmd** runs the checker in a console window and waits for a key, so the results
  stay on screen. Arguments are passed on. The Home Launcher starts it from its Utilities
  section, which `launcher.json` sets.

## [1.03] - 2026-11-17
### Changed
- **Small joining words allowed in folder names.** The Title-Case-With-Hyphens folder rule now
  accepts the lower-case words `and`, `of`, `the`, `for`, `to`, `in` and `on` as whole parts between
  capitalised parts (never first or last), so a folder named from an AppName such as
  "Disk and NAS Health" (`Disk-and-NAS-Health`) passes. Everything else is unchanged.

## [1.02] - 2026-11-17
### Fixed
- **No more crash on a new tool that isn't on GitHub yet.** Under Windows PowerShell 5.1 the
  checker stopped with a "Checker error" when `git remote get-url origin` found no `origin`
  remote, and the rest of that tool's rules were lost. Git and `gh` messages on stderr no longer
  stop the run: a missing remote is now a normal **FAIL** ("No GitHub origin remote yet") and the
  GitHub About box check shows **SKIP**, and the other rules still run. The same fix covers
  `gh repo view` on a repo that doesn't exist and `gh auth status`.

## [1.01] - 2026-11-15
### Added
- **Script releases (no exe).** A tool whose `build.json` has a `Release` section (the Homelab
  model) gets Release rules instead of Exe rules: `Release.Files` sources exist and include the
  EntryScript, README, CHANGELOG and LICENSE; `Release.Shortcut` names a shortcut maker that ships;
  a start `.cmd` ships; `Build.cmd` is in `Source\` and no exe build script is left; `Builds\`
  has the `<App Name> v<x.yy>` folder for the CHANGELOG version (and it's the newest), its
  `<App-Name>-v<x.yy>.zip` and `<App Name>.lnk` for the Home Launcher; no exe settings or old
  exes are left behind.

### Changed
- A tool still built as an exe gets a WARN: Home tools are moving to script releases because
  antivirus flags PS2EXE exes as false positives. The exe rules themselves are unchanged.

## [1.00] - 2026-11-13
### Added
- First version. Read-only check of every Home and Home\Private tool against the
  Launcher & GitHub Standards Proposal: layout, README headings and badge row, CHANGELOG,
  MIT LICENSE, git hygiene, build.json and launcher.json, exe names and versions, Docker
  files, and the GitHub About box, topics and visibility.
- `-Tool`, `-Offline`, `-FailuresOnly`, `-IncludeShared`, `-CsvPath` and `-PassThru`.
