#!/usr/bin/env bash
# Apply this repo's packages + XFCE/GTK config to the CURRENT (target) machine.
# Run on a fresh Arch install after cloning this repo.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$REPO_DIR/config"
PKG_DIR="$REPO_DIR/packages"

command -v pacman >/dev/null 2>&1 || { echo "pacman not found — this script targets Arch Linux." >&2; exit 1; }
[ "$EUID" -ne 0 ] || { echo "Run as your normal user (not root) — sudo is invoked where needed." >&2; exit 1; }

echo "==> Installing base tools"
sudo pacman -S --needed --noconfirm base-devel git rsync xfce4 xfce4-goodies

if [ -s "$PKG_DIR/pacman.txt" ]; then
  echo "==> Installing native packages from packages/pacman.txt"
  sudo pacman -S --needed --noconfirm - < "$PKG_DIR/pacman.txt"
fi

if [ -s "$PKG_DIR/aur.txt" ]; then
  if ! command -v yay >/dev/null 2>&1; then
    echo "==> Installing yay (AUR helper)"
    tmpdir="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"
    (cd "$tmpdir/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
  fi
  echo "==> Installing AUR packages from packages/aur.txt"
  yay -S --needed --noconfirm - < "$PKG_DIR/aur.txt"
fi

restore() {
  local src="$1" dest="$2"
  [ -e "$src" ] || return 0
  mkdir -p "$(dirname "$dest")"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$src" "$dest"
  else
    cp -a "$src" "$dest"
  fi
}

echo "==> Restoring XFCE + GTK config"
restore "$CONFIG_DIR/config/xfce4/"             "$HOME/.config/xfce4/"
restore "$CONFIG_DIR/config/Thunar/"            "$HOME/.config/Thunar/"
restore "$CONFIG_DIR/config/gtk-3.0/"           "$HOME/.config/gtk-3.0/"
restore "$CONFIG_DIR/config/autostart/"         "$HOME/.config/autostart/"
restore "$CONFIG_DIR/local/share/applications/" "$HOME/.local/share/applications/"
restore "$CONFIG_DIR/local/share/fonts/"        "$HOME/.local/share/fonts/"
restore "$CONFIG_DIR/fonts/"                    "$HOME/.fonts/"
restore "$CONFIG_DIR/icons/"                    "$HOME/.icons/"
restore "$CONFIG_DIR/themes/"                   "$HOME/.themes/"
restore "$CONFIG_DIR/gtkrc-2.0"                  "$HOME/.gtkrc-2.0"
restore "$CONFIG_DIR/config/user-dirs.dirs"      "$HOME/.config/user-dirs.dirs"
# xfce4-terminal's config is restored as part of config/xfce4/ above.

# Restore wallpaper images and rewrite the (now stale, source-machine) absolute
# paths baked into the xfconf xml files we just restored above.
WALLPAPER_MANIFEST="$CONFIG_DIR/wallpapers/manifest.txt"
WALLPAPER_TARGET_DIR="$HOME/.local/share/backgrounds/dotfiles"
if [ -f "$WALLPAPER_MANIFEST" ]; then
  echo "==> Restoring wallpapers"
  mkdir -p "$WALLPAPER_TARGET_DIR"

  sed_escape_pattern() { printf '%s' "$1" | sed -e 's/[.[\*^$#\\]/\\&/g'; }
  sed_escape_replacement() { printf '%s' "$1" | sed -e 's/[#&\\]/\\&/g'; }

  while IFS=$'\t' read -r orig base; do
    [ -n "$orig" ] && [ -n "$base" ] || continue
    cp -a "$CONFIG_DIR/wallpapers/$base" "$WALLPAPER_TARGET_DIR/$base"
    newpath="$WALLPAPER_TARGET_DIR/$base"
    esc_old="$(sed_escape_pattern "$orig")"
    esc_new="$(sed_escape_replacement "$newpath")"
    find "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml" -name '*.xml' -print0 2>/dev/null \
      | xargs -0 -r grep -lF "$orig" \
      | while IFS= read -r f; do
          sed -i "s#${esc_old}#${esc_new}#g" "$f"
        done
  done < "$WALLPAPER_MANIFEST"
fi

FIREFOX_DIR="$HOME/.config/mozilla/firefox"
get_firefox_profile_dir() {
  local ini="$FIREFOX_DIR/profiles.ini"
  [ -f "$ini" ] || return 1
  local rel
  rel="$(grep -m1 -E '^Path=.*default-release' "$ini" | cut -d'=' -f2-)"
  [ -n "$rel" ] || rel="$(grep -m1 '^Path=' "$ini" | cut -d'=' -f2-)"
  [ -n "$rel" ] || return 1
  echo "$FIREFOX_DIR/$rel"
}

if [ -d "$CONFIG_DIR/mozilla/firefox" ]; then
  echo "==> Restoring Firefox settings"
  if ! command -v firefox >/dev/null 2>&1; then
    echo "  firefox not installed, skipping"
  else
    TARGET_PROFILE="$(get_firefox_profile_dir || true)"
    if [ -z "${TARGET_PROFILE:-}" ] || [ ! -d "$TARGET_PROFILE" ]; then
      echo "  No existing profile, creating one"
      firefox --headless -CreateProfile "default-release" >/dev/null 2>&1 || true
      TARGET_PROFILE="$(get_firefox_profile_dir || true)"
    fi
    SRC_PROFILE="$(find "$CONFIG_DIR/mozilla/firefox" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [ -n "${TARGET_PROFILE:-}" ] && [ -n "${SRC_PROFILE:-}" ]; then
      for f in prefs.js user.js search.json.mozlz4 containers.json handlers.json; do
        [ -f "$SRC_PROFILE/$f" ] && cp -a "$SRC_PROFILE/$f" "$TARGET_PROFILE/$f"
      done
      restore "$SRC_PROFILE/chrome/" "$TARGET_PROFILE/chrome/"
    else
      echo "  Could not determine a target Firefox profile, skipping"
    fi
  fi
fi

command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$HOME/.fonts" "$HOME/.local/share/fonts" >/dev/null 2>&1 || true

echo "==> Done. Log out and back in (or reboot) for everything to apply cleanly."
echo "If XFCE is already running, you can try: xfce4-panel -r && xfsettingsd --replace & xfdesktop --reload"
