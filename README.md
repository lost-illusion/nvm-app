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
- **Per project** → write a `.nvmrc` (roadmap)
- **Existing shell** → right-click *Copy `nvm use` command* and paste

## Layout

- `Sources/NVMCore` — `NVMLayout` (disk state + installed extras: globals, size, install date),
  `NVMShellRunner` (zsh bridge), `RemoteCatalogParser` (`ls-remote` parsing),
  `DistMetadata` (nodejs.org `index.json` fetch + gzip inflate + on-disk cache),
  `NodeVersion`, `NVMModel` (observable state)
- `Sources/NVMApp` — SwiftUI: Home (banner + filters + Full/Compact table), install sheet, setup view
- `Tests/NVMCoreTests` — swift-testing suites for parsing, tree grouping, dist decoding + cache

Catalog metadata is cached at `~/Library/Application Support/nvm-app/dist-index.json`:
launch renders from cache instantly, refreshes in background when older than 24 h,
and the table still works offline with cached data. Download requests gzip
(~600 KB vs ~5 MB raw) and inflates via zlib.

## Roadmap

1. `.nvmrc` awareness: show the pin for a chosen project folder, write/edit it
2. Shell integration helper: install the zsh `chpwd` auto-use hook (README recipe in nvm)
3. "Run in Terminal with this version" button (PATH-prefixed launch)
4. Health checks: `~/.npmrc prefix=` incompatibility, `~/.nvm` ownership, Homebrew-nvm warning
5. Apple Silicon guard: warn that node < v16 needs Rosetta/source builds
