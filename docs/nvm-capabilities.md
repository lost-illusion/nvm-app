# NVM Capabilities Reference

Working spec for a native Swift (macOS) app that visually controls Node.js versions.
Sources (fetched 2026-11-02):

- `nvm-sh/nvm` README, v0.40.8 — <https://github.com/nvm-sh/nvm/blob/master/README.md>
- nvmnode.com usage guide — <https://www.nvmnode.com/guide/usage.html>
- nvmnode.com CLI reference (nvm-windows) — <https://www.nvmnode.com/cli/>

---

## 1. The two nvm implementations (know which one you're targeting)

| | nvm-sh (nvm-sh/nvm) | nvm-windows (coreybutler/nvm-windows) |
|---|---|---|
| Platform | Linux, macOS, WSL — any POSIX shell (sh, dash, ksh, zsh, bash) | Windows (cmd/PowerShell) |
| Form | **A shell function sourced from `~/.nvm/nvm.sh`, not a binary** | A real executable |
| State dir | `~/.nvm` (or `$XDG_CONFIG_HOME/nvm`) | Install dir with `settings.txt`, versions under `root` |
| `exec`/`run` | Yes | No — workaround: `nvm use X && node script.js` |
| `.nvmrc` auto-read | `nvm use` / `install` / `which` read it automatically | Must read manually: `nvm use $(type .nvmrc)` |
| Relevant for our Swift app | **Yes — this is what Mac users have** | No (reference only) |

`nvm` is verified with `command -v nvm` (outputs `nvm`); `which nvm` fails because it is a sourced shell function. **This is the single most important fact for the Swift app.**

---

## 2. How nvm-sh works internally (the model the GUI operates on)

### Install layout — `~/.nvm` (`$NVM_DIR`)

```
~/.nvm/
├── nvm.sh                  # the shell function itself (sourced by profile)
├── install.sh, bash_completion
├── versions/node/vX.Y.Z/   # one dir per installed version
│   ├── bin/                # node, npm, npx  ← what gets prepended to PATH
│   └── lib/node_modules/   # global npm packages FOR THIS VERSION ONLY
├── alias/                  # one file per alias
│   ├── default             # version used in every NEW shell
│   ├── <custom aliases>    # no spaces or slashes allowed
│   └── lts/<codename>      # managed by nvm — NEVER edit/remove these
├── .cache/                 # downloaded tarballs + .cache/locks (install locks)
└── default-packages        # optional: one npm package per line, auto-installed on every `nvm install`
```

- First version installed automatically becomes `default`. New shells start at `default`.
- LTS aliases under `alias/lts/` are recreated whenever nvm connects to nodejs.org; meddling with them is explicitly unsupported.
- `nvm use` is essentially: prepend `~/.nvm/versions/node/vX.Y.Z/bin` to `PATH` (+ update `MANPATH`, and `NODE_PATH` if present).
- Per-version advisory install lock (a dir under `$NVM_DIR/.cache/locks`) prevents two shells installing the same version concurrently; different versions never block.

### Environment variables nvm sets

| Var | Meaning |
|---|---|
| `NVM_DIR` | nvm install dir |
| `NVM_BIN` | bin dir of the active version (node/npm/npx + globals) |
| `NVM_INC` | node headers dir (C/C++ addons) |
| `NVM_CD_FLAGS` | zsh compatibility bookkeeping |
| `NVM_RC_VERSION` | version from a used `.nvmrc` |

### Shell loading (what's in the user's `~/.zshrc`)

```sh
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"          # loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
```

- `\. "$NVM_DIR/nvm.sh" --no-use` loads nvm without auto-using `default` (faster startup).
- Homebrew installs of nvm are **not supported** (the app should detect and warn).
- `zsh-nvm` plugin exists; `NVM_AUTO_USE=true` auto-applies `.nvmrc` — third-party.

---

## 3. Full command surface (nvm-sh)

Completes offered by `nvm`'s bash completion — the authoritative command list:

```
alias    cache     current   deactivate  exec      help      install   install-latest-npm
list     list-remote  ls     ls-remote   reinstall-packages  run      unalias
uninstall  unload  use      version     version-remote  which
```

### Command reference

| Command | Syntax | Behavior / notes |
|---|---|---|
| `install` | `nvm install <version>` | Download (default: prebuilt binary from nodejs.org mirror; verify checksum), install, and **use** it. `<version>` may be exact (`18.16.0`), partial (`18`, `18.12` → latest matching), or an alias (`node`, `lts/*`, `lts/argon`, `system`, custom). With no arg, uses `.nvmrc`; if neither → exit **127**. |
| | `nvm install --lts` / `--lts=iron` / `'lts/*'` / `lts/iron` | Install latest LTS (optionally a named LTS line). |
| | `nvm install node` | Latest current release. |
| | `nvm install --reinstall-packages-from=<src>` | Install, then migrate global npm packages from `<src>` (alias like `node`/`default`/`current` or version). Deliberately **does not** touch the npm version. |
| | `nvm install --reinstall-packages-from=default --latest-npm 'lts/*'` | …and also update npm to latest supported. |
| | `nvm install --offline 14.7.0` | Install from cache/installed only; no network. Works with `--lts`. Resolves versions against local data only. |
| | `nvm install -s <ver>` | Force **compile from source** (slow; needs C++ toolchain). Mutually exclusive with `-b`. |
| | `nvm install -b <ver>` | Never fall back to source build if the binary download fails (persistent as `NVM_NO_SOURCE_FALLBACK=1`). |
| | `nvm install --only=alpha,lts,non-lts` | Version-category filter (see §6). |
| | `nvm install iojs` | Legacy io.js lines (v1–v3, merged back into node v4). |
| `use` | `nvm use <version>` | Switch **the current shell only** (PATH prepend). Accepts aliases (`node`, `system`, `default`, custom, `current`). No arg → `.nvmrc`; nothing found → exit 127. |
| | `nvm use --lts` / `--lts=argon` etc. | LTS forms supported. |
| | `nvm use system` | Fall back to system-installed node. |
| `uninstall` | `nvm uninstall <version>` | Delete an installed version. LTS forms supported (`--lts`, `lts/*`). |
| `ls` / `list` | `nvm ls [pattern]` | Installed versions; marks current (`*`/`->`), aliases, LTS status. Pattern resolves to latest matching installed version (last line of `nvm ls --no-colors <pattern>`). |
| `ls-remote` / `list-remote` | `nvm ls-remote [pattern]` | All installable versions from the mirror. Without filter, annotations mark what `node` would install (`Latest: node`) and which versions your own aliases resolve to (`Aliases: name`), and `Latest LTS: <codename>` — annotations start at fixed columns, safe to slice. |
| | `nvm ls-remote --lts` / `--lts=argon` | Filter to LTS lines. |
| `alias` | `nvm alias <name> <version>` | Custom alias (no spaces/slashes). The first installed version becomes `default`. |
| | `nvm alias default 18` / `18.12` / `node` | Partial matches resolve to latest **installed** matching version. |
| | `nvm alias default --lts node` / `--lts=iron 20` | LTS-aware default. |
| | `nvm alias default --only=alpha node` | An alias may store `--only=`. |
| `unalias` | `nvm unalias <name>` | Remove custom alias (`default` is protected). |
| `current` | `nvm current` | Version active in this shell (`node` on PATH). Equivalent to `node -v`. Alias `current` also usable as a version pointer in other commands and is **not** affected by `.nvmrc`. |
| `which` | `nvm which 12.22` | Absolute path of the resolved version's node binary. No arg → `.nvmrc`; nothing → 127. |
| `exec` | `nvm exec <version> <cmd...>` | Run arbitrary command in a subshell with that version active. LTS forms supported. Follows `.nvmrc` lookup but falls back to active version if unresolved (undefined behavior — always pass explicit version in scripts/GUI). |
| `run` | `nvm run <version> <script.js> [args...]` | Run a script under a specific version. Same LTS forms. |
| `reinstall-packages` | `nvm use <dst> && nvm reinstall-packages <src>` | Migrate globals between already-installed versions without reinstalling node. npm version itself is not changed. |
| `install-latest-npm` | `nvm install-latest-npm` | Latest npm compatible with the **active** node. |
| `deactivate` | `nvm deactivate` | Remove nvm's modifications from `PATH` (restore system node for this shell). |
| `cache` | `nvm cache clear` | Delete cached downloads. Required cleanup after a failed/corrupt download (`curl: (33) … Cannot resume`). |
| `version` | `nvm version [alias]` | Resolve an alias/partial locally (`N/A` if not resolvable). `nvm --version` / `nvm version` = nvm's own version. |
| `version-remote` | `nvm version-remote 20` / `--lts` | Resolve a version pattern against the remote list. |
| `unload` | `nvm unload` | Remove the nvm function from the session and delete the install dir contents — full removal. |
| `set-colors` | `nvm set-colors rgBcm` | 5 display colors (`r/R g/G b/B c/C m/M y/Y k/K e/W` = normal/bold, grey/white). Persist via `NVM_COLORS='cmgRY'`. |
| `help` | `nvm help` / `-h` / `--help` | Usage. |

Global flag: `--no-colors` on `ls`, `ls-remote`, `alias`, `help` (or `TERM=dumb`) — **always use this from the app when parsing output.**

---

## 4. Special aliases (version pointers)

| Alias | Resolves to |
|---|---|
| `node` | Latest release of node (never an alpha by default) |
| `iojs` | Latest io.js (legacy) |
| `stable` | Deprecated alias for `node` (only meaningful for ≤ v0.12) |
| `unstable` | Historical: node v0.11 |
| `current` | The version active in this shell via PATH — **not** affected by `.nvmrc` |
| `system` | System-installed node (non-nvm) |
| `default` | Version used in new shells (`~/.nvm/alias/default`) |
| `lts/*` | Latest LTS |
| `lts/<codename>` | Latest of a named LTS line (argon, boron, carbon, dubnium, erbium, … iron for v20, jod for v22, newer codenames added over time) |

Partial-version semantics: `nvm use 20` → latest installed **v20.x.y**; `nvm ls-remote 20` / `install 20` → latest **remote** v20.x.y.

---

## 5. LTS support

- LTS lines are referenced as `lts/*` and `lts/<codename>` in aliases and `.nvmrc`.
- `--lts`, `--lts=<codename>` work on: `install`, `uninstall`, `use`, `exec`, `run`, `ls-remote`, `version-remote`.
- LTS status of installed versions comes from the mirror's `index.tab`, recorded each time nvm downloads the remote list; first command needing it triggers that download.
- `alias/lts/*` files are nvm-managed — the GUI must treat them read-only.

---

## 6. Version categories (`--only=`)

Every version belongs to exactly one category: `alpha` (prerelease, e.g. `v27.0.0-alpha.1.0.0`), `lts`, `non-lts`, `iojs`.

- Default: all categories except `alpha` — `install node`, `install 27`, `ls-remote` never pick/show alphas.
- `nvm ls-remote --only=alpha`, `nvm install --only=alpha 27`, `nvm use --only=alpha,lts,non-lts 27.0.0-alpha.1.0.0`.
- Env `NVM_ONLY` sets the default list; `--only=` overrides it. Aliases can store `--only=`.
- `--lts` selection goes through the `lts/` alias and can't combine with an `--only=` that excludes `lts`.

GUI idea: a "show alphas" toggle maps 1:1 to `--only=`.

---

## 7. `.nvmrc` (project pinning)

- File in project root (or **any ancestor directory** — lookup walks upward).
- Contents: exactly **one** version string that nvm understands, followed by newline. Accepts partials (`5.9`), `lts/*`, `node`, aliases.
- Parsing: `#` comments ignored (to end of line), blank lines ignored, leading/trailing whitespace trimmed; tabs allowed; any other control character invalidates the file. `key=value` pairs are currently ignored but reserved.
- `nvm use` / `nvm install` / `nvm which` with no explicit version use it; if neither resolves → exit **127**. (`nvm exec`/`run` follow the lookup but fall back to the active version — treat as undefined.)
- `nvm install` with `.nvmrc` installs the pinned version if missing, then uses it.
- `npx nvmrc` validates a file if you want a checker.
- Shell auto-switch-on-cd recipes exist for bash/zsh/fish (README provides a zsh `add-zsh-hook chpwd load-nvmrc` snippet using internal helpers `nvm_find_nvmrc`, `nvm version`, `nvm ls --no-colors`). The GUI can offer to install this snippet.

---

## 8. npm / global packages model

- Each node version bundles its own npm; switching node switches npm.
- Global packages live under each version (`…/vX.Y.Z/lib/node_modules`) → **per-version**; reinstall them for every version you want them on.
- Migration: `--reinstall-packages-from=` at install time, or standalone `nvm reinstall-packages <src>` after `nvm use <dst>`. npm binary itself is intentionally not upgraded by migration; `--latest-npm` is the opt-in.
- `$NVM_DIR/default-packages` file: auto-installed on every new version. GUI-friendly "package profile" feature.
- `nvm` is incompatible with npm `prefix` config: `~/.npmrc` `prefix=…`, `$NPM_CONFIG_PREFIX`, `$PREFIX` cause errors — the app should detect and offer fix.
- Never `sudo` with nvm; `npm install -g` needs no sudo under nvm. Permission problems on `~/.nvm` are fixed with `chown -R $(whoami) ~/.nvm`.

---

## 9. Downloads, mirrors, offline

- Default sources: `https://nodejs.org/dist` (node), `https://iojs.org/dist` (io.js). Authoritative listings: `index.tab` at each mirror root.
- `NVM_NODEJS_ORG_MIRROR` / `NVM_IOJS_ORG_MIRROR` override sources (env var only — no CLI flag on nvm-sh; unlike nvm-windows' `node_mirror`/`npm_mirror` commands).
- `NVM_AUTH_HEADER="Bearer …"` sends an Authorization header to the mirror only; masked as `***@` in URLs; curl ≥7.58 drops it on cross-host redirects.
- Unofficial binaries: point the node mirror at `https://unofficial-builds.nodejs.org/download/release` (musl, arm variants, loong64, riscv64 etc.). Where neither official nor unofficial has a binary, install compiles from source (slow) unless `-b` / `NVM_NO_SOURCE_FALLBACK=1`.
- `NVM_SYMLINK_CURRENT=true` → `nvm use` creates a `current` symlink under `$NVM_DIR` "sometimes useful for IDEs" (race conditions across multiple shells — a GUI could read this symlink, but only if the user opts in).
- Cache: `.cache` holds downloads; failed installs → `nvm cache clear` before retry.
- Install concurrency knobs: `NVM_INSTALL_LOCK_TIMEOUT` (default 600 s), `NVM_INSTALL_LOCK_STALE` (default 0 = never steal abandoned locks; on timeout the lock path is printed so it can be removed manually).

---

## 10. Platforms & architecture (macOS-critical facts)

- nvm-sh on macOS: works with zsh (default shell since 10.15) and bash; needs Xcode Command Line Tools for install/source builds.
- Apple Silicon: official darwin **arm64** packages from node **v16.0.0** (source-build arm64 experimental from v14.17.0). For node < v16: install under Rosetta (`arch -x86_64 zsh`), build with `--shared-zlib` to avoid `incorrect data check` npm errors; verify with `node -p process.arch`.
- Known macOS quirks worth surfacing in the app:
  - `nvm` version not picked up inside vim shells → `sudo chmod ugo-x /usr/libexec/path_helper`.
  - `$HOME` path casing mismatch with actual `/Users/<Name>` → "nvm is not compatible with the npm config prefix" errors.
  - `set -e` in a shell breaks nvm.
  - A "system" node install coexists: other users use `/usr/local/lib/node_modules`, nvm user uses `~/.nvm/.../lib/node_modules` → possible version mismatch confusion.
- Linux/Windows/FreeBSD/Alpine details exist (see README) but are out of scope for a macOS Swift app.

---

## 11. Configuration env vars (app settings screen maps to these)

| Var | Purpose |
|---|---|
| `NVM_DIR` | install dir (defaults `~/.nvm`, or `$XDG_CONFIG_HOME/nvm` if XDG set) |
| `NVM_NODEJS_ORG_MIRROR`, `NVM_IOJS_ORG_MIRROR` | mirrors |
| `NVM_AUTH_HEADER` | mirror auth |
| `NVM_SYMLINK_CURRENT=true` | `current` symlink for IDEs |
| `NVM_COLORS` | persistent list colors |
| `NVM_ONLY` | default version categories |
| `NVM_NO_SOURCE_FALLBACK=1` | never source-compile |
| `NVM_INSTALL_LOCK_TIMEOUT`, `NVM_INSTALL_LOCK_STALE` | install lock behavior |
| `TERM=dumb` | suppress colors |

---

## 12. nvm-windows CLI (for completeness only — from nvmnode.com/cli)

```
nvm arch                      32/64-bit mode of active node
nvm install <version|latest> [arch] [--insecure]   --insecure bypasses SSL
nvm list [available] / nvm ls / nvm ls available
nvm on / nvm off              enable/disable version management globally
nvm proxy [url|none]          download proxy
nvm node_mirror [url]         default https://nodejs.org/dist/
nvm npm_mirror [url]          default https://github.com/npm/cli/archive/
nvm uninstall <version>
nvm use [version] [arch]
nvm root [path]               storage dir for versions
nvm version / v / -v / -version
nvm alias default <version>   (from usage guide)
nvm current / node -v         (from usage guide)
```

No `exec`/`run`; `.nvmrc` not auto-read. Persisted in `settings.txt`.

---

## 13. Swift app design implications

1. **Invoke nvm via shell.** No `nvm` binary to exec. Use `zsh -c 'export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh" --no-use; nvm <args>'` (`--no-use` avoids auto-using default per call). Always append `--no-colors` for parseable output. `TERM=dumb` as belt-and-braces.
2. **Read state directly from disk** where possible (no shell round-trip): installed versions = `~/.nvm/versions/node/*` (parse dir names, strip `v`); aliases = `~/.nvm/alias/*`; `default` file; `alias/lts/*` read-only; install locks = `~/.nvm/.cache/locks/*`.
3. **"Active version" is per-shell.** A GUI cannot switch versions in the user's existing terminals — `nvm use` only edits that shell's PATH. Real GUI actions:
   - **Set default** (`nvm alias default X`) → applies to every *new* shell. Direct file write to `~/.nvm/alias/default` is equivalent but prefer the command.
   - **Pin per project**: write/edit `.nvmrc`.
   - **Launch with a version**: spawn processes with `PATH` = `~/.nvm/versions/node/vX/bin:` + original PATH (this is exactly what `nvm use` does), or wrap with `nvm exec <ver> …`, or open Terminal with the right PATH.
   - **Offer shell integration**: install the README's zsh `chpwd` hook so user terminals auto-switch on cd.
4. **Version resolution needs two modes:** local (`nvm version <pattern>` → `N/A` if absent) vs remote (`nvm version-remote`, `nvm ls-remote`). Parse `ls-remote` annotations (fixed columns) for LTS/latest/alias badges rather than hardcoding LTS dates.
5. **Exit-code contract:** `127` = no version resolved (missing arg and no `.nvmrc`); `N/A` output = alias resolves to nothing installed. Surface these as user-facing errors.
6. **Install UX:** network-bound (download + checksum); show progress from curl output; serialize per-version (nvm's own lock blocks duplicates; `NVM_INSTALL_LOCK_TIMEOUT` default 600 s). Offer "migrate global packages from …" (`--reinstall-packages-from=`) and "also update npm" (`--latest-npm`) as checkboxes. `default-packages` file = "install these packages with every new version".
7. **Catalog view:** `ls-remote` grouped by major; category filter (`--only=` toggle for alpha/iojs); LTS badge from annotations; `--offline` install option when tarball is cached.
8. **Health checks:** `command -v nvm` equivalent = existence + sourcing test of `$NVM_DIR/nvm.sh`; detect Homebrew nvm (unsupported — prompt reinstall); detect `~/.npmrc` `prefix=` / `$PREFIX` (incompatibility); `~/.nvm` ownership; `$HOME` casing on macOS.
9. **Arch awareness:** on Apple Silicon, block/warn for node < v16 installs (needs Rosetta + `-s`/`--shared-zlib` path).
10. **Uninstall safety:** `nvm uninstall` deletes `~/.nvm/versions/node/vX.Y.Z` (globals die with it); warn when removing the `default`-pointing version.
