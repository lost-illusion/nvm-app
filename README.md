# nvm-app

Native Swift (SwiftUI, SwiftPM) GUI for [nvm-sh](https://github.com/nvm-sh/nvm) on macOS:
see installed Node versions at a glance, browse the remote catalog, install with package
migration, set the new-shell default, manage aliases visually.

Capability reference and design rationale: [`docs/nvm-capabilities.md`](docs/nvm-capabilities.md).

## Run

```sh
swift build          # NVMCore library + NVMApp executable
swift test           # core parser tests
swift run NVMApp     # opens the window
```

Requires an nvm-sh install (`~/.nvm/nvm.sh`; Homebrew copies unsupported). Override the
directory with `defaults write nvm-app nvmDirOverride -string 'path/to/nvm'` (or set `XDG_CONFIG_HOME`).

## How it talks to nvm

`nvm` is a shell **function**, not a binary (`which nvm` fails). Every command runs as:

```
zsh -c 'export NVM_DIR="…"; . "$NVM_DIR/nvm.sh" --no-use; nvm <args>'
```

`--no-use` keeps read-only queries from switching anything; `TERM=dumb` + `--no-colors`
keep output parseable. Read-only state (installed versions, alias files, install locks) is
read directly off disk in `NVMLayout`.

**A GUI cannot switch versions inside your existing terminals** — `nvm use` edits one
shell's PATH. The real levers this app provides:

- **Set default** → `nvm alias default <v>` (applies to every new shell)
- **Install** → `nvm install` with `--offline` / `--reinstall-packages-from=` options
- **Per project** → write a `.nvmrc`, watch folders, scan for pins
- **New shell** → terminal icon opens Terminal (tab if open) with the version active;
  folder rows `cd` there first — or install the zsh `chpwd` auto-use hook in Settings
- **Existing shell** → `nvm use <v>` yourself; the app cannot reach live shells

## Layout

- `Sources/NVMCore` — `NVMLayout` (disk state + installed extras: globals, size, install date),
  `NVMShellRunner` (zsh bridge), `RemoteCatalogParser` (`ls-remote` parsing),
  `DistMetadata` (nodejs.org `index.json` fetch + gzip inflate + on-disk cache),
  `Nvmrc` + `NvmrcScanner` (pins + bounded tree scan), `AutoUseHook` (marker-delimited
  zsh `chpwd` block in `~/.zshrc`), `TerminalLauncher` (Terminal.app automation),
  `NodeVersion`, `NVMModel` (observable state)
- `Sources/NVMApp` — SwiftUI: Home (banner + filters + Full/Compact table), install sheet, setup view
- `Tests/NVMCoreTests` — swift-testing suites for parsing, tree grouping, dist decoding + cache

Catalog metadata is cached at `~/Library/Application Support/nvm-app/dist-index.json`:
launch renders from cache instantly, refreshes in background when older than 24 h,
and the table still works offline with cached data. Download requests gzip
(~600 KB vs ~5 MB raw) and inflates via zlib.

## Roadmap

1. ~~`.nvmrc` awareness~~ — done: PinCard under the banner (choose folder, see the
   pin → `nvm version` / `version-remote` resolution, install/set-default, edit
   or remove the file; right-click any table row to pin it)
2. ~~Shell integration helper~~ — done: Settings installs the zsh `chpwd` auto-use hook
   as a marker-delimited `~/.zshrc` block (one-time backup, foreign-hook detection,
   optional auto-install-missing toggle)
3. ~~"Run in Terminal with this version"~~ — done: terminal icon on installed rows and
   pinned folder rows; new tab if Terminal is open, new window otherwise
4. Health checks: `~/.npmrc prefix=` incompatibility, `~/.nvm` ownership, Homebrew-nvm warning
5. Apple Silicon guard: warn that node < v16 needs Rosetta/source builds
