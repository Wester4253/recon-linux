# RECON on Linux

Install and run the RECON OSINT Aggregator on Debian, Ubuntu, Arch, and other
Linux distros.

## One-line install

```bash
chmod +x linux/setup.sh
./linux/setup.sh
```

## What it does

1. Detects your distro/package manager (`apt`, `pacman`, `dnf`, `yum`, `zypper`)
   and installs `python3`, `pip`, and `git` if missing.
2. Installs the core Python dependency: `aiohttp`.
3. Installs OSINT tools via `pip`: `maigret`, `sherlock-project`, `holehe`.
4. Clones `blackbird` and `spiderfoot` into the repo folder and installs their
   Python requirements.
5. Creates `recon` and `recon-web` launchers in `~/.local/bin`.

## Usage

After setup, add `~/.local/bin` to your `PATH` (the script tells you how if it's
missing), then:

```bash
recon-web                      # Web UI at http://localhost:8420
recon johndoe                  # CLI full scan
recon johndoe --skip-wmn       # Skip WhatsMyName
recon johndoe --skip-external  # Skip Blackbird/Maigret/Sherlock/Holehe
```

Or call the launchers directly without touching `PATH`:

```bash
~/.local/bin/recon-web
~/.local/bin/recon johndoe
```

## Supported distros

| Distro family | Package manager used |
|---------------|----------------------|
| Debian, Ubuntu | `apt` |
| Arch | `pacman` |
| Fedora | `dnf` |
| RHEL, CentOS | `yum` |
| openSUSE | `zypper` |

If your distro isn't detected, install `python3`, `pip`, and `git` manually,
then run `./linux/setup.sh` again.

## Uninstall

```bash
rm -f ~/.local/bin/recon ~/.local/bin/recon-web
rm -rf recon_*.json .recon_cache blackbird spiderfoot
# Also remove any pip-installed tools: pip uninstall maigret sherlock-project holehe
```
