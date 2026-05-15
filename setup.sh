#!/usr/bin/env bash
# setup.sh — Initialize developer tooling for home-ops
#
# What it does (idempotent — safe to run multiple times):
#   1. Installs mise CLI if missing (via brew on macOS, otherwise mise.run).
#   2. Wires mise into the shell rc so tools land on PATH automatically:
#        - interactive shell:    eval "$(mise activate <shell>)" in rc
#        - non-interactive shell: mise shims dir prepended in env rc
#   3. Trusts this repo's .mise.toml.
#   4. Installs every tool declared in .mise.toml (`mise install`).
#   5. Installs the pre-commit git hooks.
#
# Run from anywhere: `./setup.sh` or `bash setup.sh`.

set -euo pipefail

# --- helpers ------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
log_step() { printf "\n${BLUE}==>${NC} %s\n" "$*"; }
die()      { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; exit 1; }

# Idempotent append: only adds the line if not already present in $file.
ensure_line_in_file() {
    local line=$1 file=$2
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if grep -qxF "$line" "$file"; then
        log_info "Already present in $file: $line"
    else
        printf '\n# Added by home-ops setup.sh\n%s\n' "$line" >> "$file"
        log_info "Appended to $file: $line"
    fi
}

# --- preconditions ------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ -f "$REPO_ROOT/.mise.toml" ] || die ".mise.toml not found at $REPO_ROOT — wrong directory?"

SHELL_NAME=$(basename "${SHELL:-/bin/zsh}")
case "$SHELL_NAME" in
    zsh)
        RC_INTERACTIVE="$HOME/.zshrc"
        RC_ENV="$HOME/.zshenv"
        ACTIVATE_LINE='eval "$(mise activate zsh)"'
        ;;
    bash)
        RC_INTERACTIVE="$HOME/.bashrc"
        RC_ENV="$HOME/.bash_profile"
        ACTIVATE_LINE='eval "$(mise activate bash)"'
        ;;
    *)
        die "Unsupported shell: $SHELL_NAME. Configure mise activation manually per https://mise.jdx.dev/getting-started.html#activate-mise"
        ;;
esac
SHIMS_LINE='export PATH="$HOME/.local/share/mise/shims:$PATH"'

# --- 1. mise CLI --------------------------------------------------------------

log_step "Checking mise CLI"

if ! command -v mise >/dev/null 2>&1; then
    log_warn "mise not found — installing"
    if [[ "$OSTYPE" == "darwin"* ]] && command -v brew >/dev/null 2>&1; then
        brew install mise
    else
        curl -fsSL https://mise.run | sh
    fi
    # Installer typically lands at $HOME/.local/bin/mise — make it reachable for the rest of this run.
    export PATH="$HOME/.local/bin:$PATH"
    command -v mise >/dev/null 2>&1 || die "mise install completed but binary still not on PATH — open a new shell and re-run."
fi
log_info "mise: $(mise --version)"

# --- 2. shell wiring ----------------------------------------------------------

log_step "Wiring mise into $SHELL_NAME shell"

ensure_line_in_file "$ACTIVATE_LINE" "$RC_INTERACTIVE"
ensure_line_in_file "$SHIMS_LINE"    "$RC_ENV"

# --- 3. trust .mise.toml ------------------------------------------------------

log_step "Trusting $REPO_ROOT/.mise.toml"
mise trust "$REPO_ROOT/.mise.toml"

# --- 4. install tools ---------------------------------------------------------

log_step "Installing tools from .mise.toml"
( cd "$REPO_ROOT" && mise install )

# --- 5. pre-commit hooks ------------------------------------------------------

log_step "Installing pre-commit git hooks"
if ( cd "$REPO_ROOT" && mise exec -- pre-commit --version >/dev/null 2>&1 ); then
    ( cd "$REPO_ROOT" && mise exec -- pre-commit install --install-hooks )
else
    log_warn "pre-commit not available via mise — skipping. Check .mise.toml [tools] section."
fi

# --- done ---------------------------------------------------------------------

cat <<EOF

${GREEN}✓ Done.${NC}

To activate mise in your CURRENT shell session (one-time, until you open a new terminal):

    eval "\$(mise activate $SHELL_NAME)"

Then run \`just\` to list available recipes. New terminals pick this up automatically.
EOF
