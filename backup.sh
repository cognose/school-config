#!/usr/bin/env bash
# Capture packages + XFCE/GTK config from the CURRENT machine into this repo.
# Run this on the machine whose setup you want to clone, then commit + push.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$REPO_DIR/config"
PKG_DIR="$REPO_DIR/packages"

command -v pacman >/dev/null 2>&1 || { echo "pacman not found — this script targets Arch Linux." >&2; exit 1; }

mkdir -p "$CONFIG_DIR" "$PKG_DIR"

echo "==> Dumping package lists"
pacman -Qqen > "$PKG_DIR/pacman.txt"          # explicitly installed, native (official repos)
pacman -Qqem > "$PKG_DIR/aur.txt" || true      # foreign packages (AUR / local builds)

# Rsync copies with a safe fallback to cp -a
copy() {
  local src="$1" dest="$2"
  [ -e "$src" ] || return 0
  mkdir -p "$(dirname "$dest")"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude 'Cache' --exclude 'cache' --exclude 'thumbnails' --exclude '*.lock' \
      "$src" "$dest"
  else
    rm -rf "$dest"
    cp -a "$src" "$dest"
  fi
}

echo "==> Copying XFCE + GTK config"
copy "$HOME/.config/xfce4/"            "$CONFIG_DIR/config/xfce4/"
copy "$HOME/.config/Thunar/"           "$CONFIG_DIR/config/Thunar/"
copy "$HOME/.config/gtk-3.0/"          "$CONFIG_DIR/config/gtk-3.0/"
copy "$HOME/.config/autostart/"        "$CONFIG_DIR/config/autostart/"
copy "$HOME/.local/share/applications/" "$CONFIG_DIR/local/share/applications/"
copy "$HOME/.local/share/fonts/"       "$CONFIG_DIR/local/share/fonts/"
copy "$HOME/.fonts/"                   "$CONFIG_DIR/fonts/"
copy "$HOME/.icons/"                   "$CONFIG_DIR/icons/"
copy "$HOME/.themes/"                  "$CONFIG_DIR/themes/"
copy "$HOME/.gtkrc-2.0"                "$CONFIG_DIR/gtkrc-2.0"
copy "$HOME/.config/user-dirs.dirs"    "$CONFIG_DIR/config/user-dirs.dirs"
# xfce4-terminal's config lives under ~/.config/xfce4/terminal/ — already covered above.

# Locate the default Firefox profile from profiles.ini (relative-path profiles only).
get_firefox_profile_dir() {
  local ini="$HOME/.mozilla/firefox/profiles.ini"
  [ -f "$ini" ] || return 1
  local rel
  rel="$(grep -m1 -E '^Path=.*default-release' "$ini" | cut -d'=' -f2-)"
  [ -n "$rel" ] || rel="$(grep -m1 '^Path=' "$ini" | cut -d'=' -f2-)"
  [ -n "$rel" ] || return 1
  echo "$HOME/.mozilla/firefox/$rel"
}

FF_PROFILE="$(get_firefox_profile_dir || true)"
if [ -n "${FF_PROFILE:-}" ] && [ -d "$FF_PROFILE" ]; then
  echo "==> Copying Firefox settings (prefs/search/containers/userChrome — no history, cookies or passwords)"
  copy "$HOME/.mozilla/firefox/profiles.ini" "$CONFIG_DIR/mozilla/firefox/profiles.ini"
  FF_DEST="$CONFIG_DIR/mozilla/firefox/$(basename "$FF_PROFILE")"
  mkdir -p "$FF_DEST"
  for f in prefs.js user.js search.json.mozlz4 containers.json handlers.json; do
    [ -f "$FF_PROFILE/$f" ] && cp -a "$FF_PROFILE/$f" "$FF_DEST/$f"
  done
  copy "$FF_PROFILE/chrome/" "$FF_DEST/chrome/"
else
  echo "==> No Firefox profile found, skipping"
fi

echo "==> Done."
echo "Packages: $(wc -l < "$PKG_DIR/pacman.txt") native, $(wc -l < "$PKG_DIR/aur.txt") AUR/foreign."
echo "Now review 'git status', commit, and push this repo to your own remote (GitHub/GitLab/…)."
