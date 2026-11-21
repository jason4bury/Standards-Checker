# Standards Checker

A read-only PowerShell report that checks every Home tool against the house style and says what passes and what doesn't.

![Version](https://img.shields.io/badge/version-v1.05-blue)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Licence](https://img.shields.io/badge/licence-MIT-green)
![Last commit](https://img.shields.io/github/last-commit/jason4bury/Standards-Checker)

## ✨ Features

- Scans every project in your Home folder (the `Home` folder beside the `_shared` folder it is kept in, or one you give with `-Root`) and, when the vault is unlocked, `Home\Private`. If `Home\Private` is locked it says so and carries on.
- **Read only.** It never creates, changes or deletes a file and never writes to git or GitHub. The only file it can write is the CSV you ask for with `-CsvPath`.
- Gives every rule a **PASS**, **FAIL**, **WARN**, **INFO** or **SKIP**, grouped by tool, with a summary table at the end.
- Checks repo files and version numbers only. It never judges how an app's GUI looks, because the house style never restyles an app's GUI.

What it checks for each tool:

| Area | Rules |
| --- | --- |
| Layout | `Source\` and `Builds\` folders, `src\` `docs\` `assets\`, Title-Case-With-Hyphens folder name (small joining words such as `and` may be lower case), anything else in the project folder |
| README | H1 title, tagline, badge row directly under the tagline, badge order (version, platform, language, licence, last commit), **no Last-commit badge on private repos**, version badge matches the CHANGELOG, every H2 has its emoji, sections in house order, link to CHANGELOG.md |
| CHANGELOG | Present, `# Changelog`, `[Unreleased]`, entries as `## [x.yy] - YYYY-MM-DD`, newest first, current version |
| LICENSE | MIT, `Copyright (c) <year> Jason Rhodes` |
| Git | `Source\` is a repo, `.gitignore` covers `*.exe`, `config.local.json`, `*.log` (when logs exist), `.env` and `node_modules` (Docker apps), no exe in `Source\`, no exe, `.env` or `config.local.json` tracked |
| Build | `build.json` with AppName, EntryScript and Icon that exist, folder and main script named after the app, script version matches the CHANGELOG |
| Release | Script tools with no exe (`build.json` has a `Release` section): the release files exist and include the main script, README, CHANGELOG, LICENSE, the shortcut maker and a start `.cmd`; `Build.cmd` is there and no exe build script or exe settings are left; `Builds\` has `<App Name> v<x.yy>\` for the CHANGELOG version (the newest), its zip, `<App Name>.lnk` for the Home Launcher, and no old exes |
| Exe | Tools still built as an exe (a WARN, since antivirus flags PS2EXE exes): exe names are `<App Name> v<x.yy>.exe`, the exe for the CHANGELOG version is in `Builds\`, the newest exe matches the CHANGELOG |
| Docker | `docker-compose.yml`, `Dockerfile` pinned to an exact Node.js version, `.env.example`, `package.json` version matches the CHANGELOG |
| Launcher | `launcher.json` is valid JSON when present (it's optional) |
| GitHub | origin remote (a tool not on GitHub yet gets a FAIL, not a crash), repo name matches the folder, About description present and in the `<Language>/<UI> tool for ...` form, matches `build.json` Description, topics set, private tools have a PRIVATE repo |

Docker apps are recognised by `docker-compose.yml` and skip the release, exe and `build.json` rules.

## 📋 Requirements

- Windows PowerShell 5.1 or PowerShell 7.
- `git` on the PATH, for the tracked-file and remote checks.
- [GitHub CLI](https://cli.github.com/) (`gh`) signed in, for the About box, topics and visibility checks. Without it those rules show **SKIP**, or use `-Offline`.

## 📦 Installation

Nothing to install. Keep the repo in `<your tools folder>\_shared\Standards-Checker\Source` (beside your `Home` folder) and run the script from `src\`, or double-click **Standards Checker.cmd**, which runs it and keeps the window open. The Home Launcher lists it under Utilities.

## 🚀 Usage

```powershell
# Every Home tool, every rule
.\src\Standards-Checker.ps1

# Only the problems
.\src\Standards-Checker.ps1 -FailuresOnly

# One tool, or a few
.\src\Standards-Checker.ps1 -Tool "TV-Toolkit"
.\src\Standards-Checker.ps1 -Tool "MP3-*"

# No GitHub lookups, and save everything to a CSV
.\src\Standards-Checker.ps1 -Offline -CsvPath "$env:USERPROFILE\Desktop\standards.csv"
```

| Parameter | What it does |
| --- | --- |
| `-Root <folder>` | Home folder to scan. Default: the `Home` folder beside `_shared`, else the current folder. |
| `-CopyrightName <name>` | The name the LICENSE copyright line must show. Default: your git `user.name`. |
| `-Tool <wildcard>` | Only tools whose folder name matches. |
| `-IncludeShared` | Also check the repos in the `_shared` folder beside the Home folder. |
| `-Offline` | Skip the GitHub checks. |
| `-FailuresOnly` | Only show FAIL and WARN lines. |
| `-CsvPath <file>` | Also save every result to a CSV file. |
| `-PassThru` | Return the results as objects as well. |

The exit code is 1 when any rule failed and 0 otherwise, so it can be used in a scheduled task or before a release.

**FAIL** breaks a rule in the standards proposal. **WARN** is worth a look but may be a deliberate choice (for example a main script that isn't named after the folder). **INFO** is for information only.

## ⚙️ Configuration

There are no settings files. The GitHub account, copyright name, section emoji and badge order are constants at the top of `src\Standards-Checker.ps1`, so a change to the house style is a change to the script.

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md).

## 📄 Licence

MIT. See [LICENSE](LICENSE).
