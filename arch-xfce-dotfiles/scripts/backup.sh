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

# Copy the actual wallpaper image files referenced by xfce4-desktop's xfconf settings
# (the xml only stores an absolute path, the image itself usually lives outside ~/.config).
WALLPAPER_SRC_XML="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
WALLPAPER_DEST_DIR="$CONFIG_DIR/wallpapers"
if [ -f "$WALLPAPER_SRC_XML" ]; then
  echo "==> Copying wallpaper images referenced by XFCE desktop settings"
  mkdir -p "$WALLPAPER_DEST_DIR"
  MANIFEST="$WALLPAPER_DEST_DIR/manifest.txt"
  : > "$MANIFEST"
  declare -A seen_paths=()
  i=0
  while IFS= read -r imgpath; do
    [ -n "$imgpath" ] && [ -f "$imgpath" ] || continue
    [ -n "${seen_paths[$imgpath]:-}" ] && continue
    seen_paths["$imgpath"]=1
    i=$((i+1))
    base="$(printf '%03d-%s' "$i" "$(basename "$imgpath")")"
    cp -a "$imgpath" "$WALLPAPER_DEST_DIR/$base"
    printf '%s\t%s\n' "$imgpath" "$base" >> "$MANIFEST"
  done < <(grep -oE 'name="last-image" type="string" value="[^"]+"' "$WALLPAPER_SRC_XML" | sed -E 's/.*value="([^"]+)"/\1/')
  [ -s "$MANIFEST" ] || rm -f "$MANIFEST"
  echo "  $(wc -l < "$MANIFEST" 2>/dev/null || echo 0) wallpaper(s) captured."
fi

# Locate the default Firefox profile from profiles.ini (relative-path profiles only).
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

FF_PROFILE="$(get_firefox_profile_dir || true)"
if [ -n "${FF_PROFILE:-}" ] && [ -d "$FF_PROFILE" ]; then
  echo "==> Copying Firefox settings (prefs/search/containers/userChrome — no history, cookies or passwords)"
  copy "$FIREFOX_DIR/profiles.ini" "$CONFIG_DIR/mozilla/firefox/profiles.ini"
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
