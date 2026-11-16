# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with versions written as
v<major>.<minor>.

## [Unreleased]

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
