#!/usr/bin/env bash
# ============================================================================
# fixwval installer (Linux / macOS)
# Installs GnuCOBOL if missing, builds fixwval + fwmode, copies to PREFIX/bin.
#
#   ./install.sh                 # system install (may use sudo), PREFIX=/usr/local
#   PREFIX=$HOME/.local ./install.sh   # user install, no sudo
# ============================================================================
set -eu

PREFIX="${PREFIX:-/usr/local}"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

need_sudo() { if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then echo sudo; fi; }
SUDO="$(need_sudo)"

install_cobc() {
  if command -v cobc >/dev/null 2>&1; then return 0; fi
  echo ">> GnuCOBOL not found; attempting install ..."
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -qq && $SUDO apt-get install -y gnucobol
  elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y gnucobol
  elif command -v yum >/dev/null 2>&1; then
    $SUDO yum install -y gnucobol
  elif command -v pacman >/dev/null 2>&1; then
    $SUDO pacman -S --noconfirm gnucobol
  elif command -v brew >/dev/null 2>&1; then
    brew install gnu-cobol || brew install gnucobol
  else
    echo "!! No known package manager. Install GnuCOBOL manually, then re-run."
    exit 1
  fi
}

install_cobc

if ! command -v cobc >/dev/null 2>&1; then
  echo "!! cobc still not on PATH after install attempt."; exit 1
fi

echo ">> building with $(cobc --version | head -1)"
cobc -x -free -o fixwval fixwval.cob
cobc -x -free -o fwmode  fwmode.cob

echo ">> smoke test"
./fixwval demos/session_clean.fix >/dev/null && echo "   fixwval OK"

DEST="$PREFIX/bin"
echo ">> installing to $DEST"
$SUDO mkdir -p "$DEST"
$SUDO cp fixwval "$DEST/fixwval"
$SUDO cp fwmode  "$DEST/fwmode"
echo ">> done. Try:  fixwval demos/session_broken.fix"
