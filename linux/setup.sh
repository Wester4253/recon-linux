#!/usr/bin/env bash
# RECON - OSINT Aggregator Linux Setup
# Works on Debian, Ubuntu, Arch, and other distros with apt/pacman/zypper/dnf/yum.
# Usage:
#   chmod +x linux/setup.sh
#   ./linux/setup.sh
#
# Installs system packages (python3, pip, git), Python deps (aiohttp + OSINT tools),
# clones Blackbird & SpiderFoot, and creates `recon` / `recon-web` launchers in ~/.local/bin.
set -euo pipefail


log()  { printf '  [*] %s\n' "$*"; }
ok()   { printf '  [+] %s\n' "$*"; }
fail() { printf '  [!] %s\n' "$*" >&2; }
# ── Resolve repo directory ────────────────────────────────────────────
# Works both as a file (./linux/setup.sh) and piped via stdin (curl | bash),
# where $0/BASH_SOURCE are unreliable. We must end up inside the repo
# (the directory that contains recon.py).
resolve_repo_dir() {
    local dir="$PWD"
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        local src
        src="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" && dir="$src/.."
    fi
    dir="$(cd "$dir" 2>/dev/null && pwd)" || dir="$PWD"
    if [ -f "$dir/recon.py" ]; then
        echo "$dir"; return 0
    fi
    if [ -f "$PWD/recon.py" ]; then
        echo "$PWD"; return 0
    fi
    return 1
}

REPO_DIR="$(resolve_repo_dir)" || {
    fail "Could not locate the recon repo (recon.py not found)."
    fail "Run this script from inside the recon-linux checkout, e.g.:"
    fail "  git clone https://github.com/Wester4253/recon-linux.git"
    fail "  cd recon-linux && ./linux/setup.sh"
    exit 1
}
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

# ── Detect distro & package manager ───────────────────────────────────────────
ID_LIKE=""
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    ID_LIKE="${ID_LIKE:-}"
fi

have() { command -v "$1" >/dev/null 2>&1; }

install_pkgs() {
    # $1 = package manager command, rest = packages
    local pm="$1"; shift
    if have "$pm"; then
        log "Installing system packages via $pm: $*"
        case "$pm" in
            apt)   sudo $pm update -y && sudo $pm install -y "$@" ;;
            pacman) sudo $pm -S --needed --noconfirm "$@" ;;
            *)     sudo $pm install -y "$@" ;;
        esac
        ok "System packages installed."
        return 0
    fi
    return 1
}

log "Detecting package manager..."
for pm in apt pacman dnf yum zypper; do
    if have "$pm"; then
        case "$pm" in
            apt)   pkgs="python3 python3-pip python3-venv git" ;;
            pacman) pkgs="python python-pip git" ;;
            *)     pkgs="python3 python3-pip git" ;;
        esac
        install_pkgs "$pm" $pkgs
        break
    fi
done
if ! have python3 && ! have python; then
    fail "Could not install python3 automatically."
    fail "Install python3, pip, and git manually, then re-run this script."
    exit 1
fi
ok "System packages ready."

# ── Python / pip ──────────────────────────────────────────────────────────────
PY=""
for cand in python3 python; do
    if have "$cand"; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then fail "python3 not found after install."; exit 1; fi
log "Using Python: $PY ($($PY --version))"

if ! have pip3 && ! $PY -m pip --version >/dev/null 2>&1; then
    log "pip not found; bootstrapping via ensurepip..."
    $PY -m ensurepip --upgrade || true
fi

VENV="$REPO_DIR/.venv"
VENV_PY="$VENV/bin/python"

# Use a repo-local virtualenv so we work on both normal and
# PEP 668 "externally-managed" systems (Arch, Debian, Ubuntu, …).
if [ ! -x "$VENV_PY" ]; then
    log "Creating virtualenv in $VENV..."
    $PY -m venv "$VENV"
fi
ok "Virtualenv ready at $VENV"
$VENV_PY -m pip install --upgrade pip >/dev/null 2>&1 || true

# ── Core dependency ───────────────────────────────────────────────────────────
log "Installing core dependency: aiohttp..."
$VENV_PY -m pip install aiohttp --quiet
ok "aiohttp installed."

# ── OSINT tools via pip ───────────────────────────────────────────────────────
for tool in maigret sherlock-project holehe; do
    log "Installing $tool via pip..."
    if $VENV_PY -m pip install "$tool" --quiet; then
        ok "$tool installed."
    else
        fail "pip install $tool failed (non-fatal, continuing)."
    fi
done

clone_tool() {
    local name="$1" url="$2" req="$3"
    if [ -d "$REPO_DIR/$name" ]; then
        log "$name/ already exists, skipping clone."
    else
        log "Cloning $name..."
        if ! git clone "$url" "$REPO_DIR/$name" --quiet 2>/dev/null; then
            fail "git clone $name failed (non-fatal)."
            return
        fi
    fi
    if [ -f "$REPO_DIR/$name/$req" ]; then
        log "Installing $name requirements..."
        $VENV_PY -m pip install -r "$REPO_DIR/$name/$req" --quiet \
            >/dev/null 2>&1 || \
            fail "pip install -r $name/$req failed (non-fatal)."
    fi
    ok "$name ready."
}

clone_tool blackbird  https://github.com/p1ngul1n0/blackbird.git  requirements.txt
clone_tool spiderfoot https://github.com/smicallef/spiderfoot.git requirements.txt

cat > "$BIN_DIR/recon" <<EOF
#!/usr/bin/env bash
# RECON CLI launcher
exec "$VENV_PY" "$REPO_DIR/recon.py" "\$@"
EOF
chmod +x "$BIN_DIR/recon"

cat > "$BIN_DIR/recon-web" <<EOF
#!/usr/bin/env bash
# RECON web UI launcher
exec "$VENV_PY" "$REPO_DIR/server.py"
EOF
chmod +x "$BIN_DIR/recon-web"
ok "Launchers created: recon, recon-web"

# ── PATH hint ─────────────────────────────────────────────────────────────────
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    cat <<EOF

  [!] $BIN_DIR is not on your PATH. Add it to your shell rc file (e.g. ~/.bashrc,
      ~/.zshrc) and restart your terminal:

      export PATH="\$HOME/.local/bin:\$PATH"

  Or call the launchers directly:
      $BIN_DIR/recon johndoe
      $BIN_DIR/recon-web

EOF
fi

echo
echo "  =============================================="
ok "Setup complete!"
echo "  Web UI:    recon-web   (http://localhost:8420)"
echo "  CLI:       recon <username>"
echo "  Install tools again anytime: python3 recon.py --install-tools"
echo "  =============================================="
