#!/usr/bin/env bash
# Installs or updates Dev Cockpit (review-radar) from the GitHub releases of the public dist repo,
# with the gh CLI the developers are already logged into. Later versions arrive inside the app.
set -euo pipefail

REPO="${REVIEW_RADAR_REPO:-jeremie-vasco/dev-cockpit-dist}"
APP_NAME="Dev Cockpit"
CHANNEL="stable"
VERSION=""
DRY_RUN=0
FROM_FILE=""
LINUX_FORMAT="appimage"
FORCE=0

usage() {
  cat <<USAGE
Usage : install.sh [options]

  --beta               dernière version beta (sinon : dernière version stable)
  --version vX.Y.Z     version précise
  --deb                Linux : paquet .deb (sudo, mises à jour manuelles) au lieu de l'AppImage
  --from-file CHEMIN   installe un artefact déjà téléchargé (.app.tar.gz, .AppImage ou .deb)
  --force              réinstalle même si la version est déjà là
  --dry-run            affiche ce qui serait fait, sans rien modifier
  --repo owner/nom     dépôt des releases (défaut : $REPO)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --beta) CHANNEL="beta" ;;
    --version) VERSION="${2:?--version attend une version}"; shift ;;
    --deb) LINUX_FORMAT="deb" ;;
    --from-file) FROM_FILE="${2:?--from-file attend un chemin}"; shift ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --repo) REPO="${2:?--repo attend owner/nom}"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

step() { printf '→ %s\n' "$*"; }
ok() { printf '✓ %s\n' "$*"; }
done_msg() {
  if [ "$DRY_RUN" = 1 ]; then printf '✓ dry-run terminé : %s serait installé.\n' "$APP_NAME $TARGET_VERSION"; else ok "$*"; fi
}
warn() { printf '! %s\n' "$*" >&2; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }
# Every change goes through `run`, so that --dry-run shows it without doing it.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Darwin) PATTERN="*_universal.app.tar.gz" ;;
  Linux)
    [ "$ARCH" = "x86_64" ] || die "Linux $ARCH n'est pas supporté (x86_64 uniquement)."
    if [ "$LINUX_FORMAT" = "deb" ]; then PATTERN="*_amd64.deb"; else PATTERN="*_amd64.AppImage"; fi
    ;;
  *) die "Système non supporté : $OS" ;;
esac

echo "$APP_NAME · installation ($OS $ARCH)"
[ "$DRY_RUN" = 1 ] && echo "Mode dry-run : rien ne sera modifié."

resolve_tag() {
  if [ -n "$VERSION" ]; then
    case "$VERSION" in v*) echo "$VERSION" ;; *) echo "v$VERSION" ;; esac
    return
  fi
  # The API lists the newest release first: stable skips prereleases, beta takes the newest of all.
  local filter='.[] | select(.draft | not) | .tag_name'
  [ "$CHANNEL" = "stable" ] && filter='.[] | select((.draft | not) and (.prerelease | not)) | .tag_name'
  gh api "repos/$REPO/releases?per_page=30" --jq "$filter" | head -n 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -n "$FROM_FILE" ]; then
  [ -f "$FROM_FILE" ] || die "Fichier introuvable : $FROM_FILE"
  ARTIFACT="$(cd "$(dirname "$FROM_FILE")" && pwd)/$(basename "$FROM_FILE")"
  TAG="$(basename "$FROM_FILE" | sed -nE 's/.*_([0-9]+\.[0-9]+\.[0-9]+[^_]*)_.*/v\1/p')"
  TAG="${TAG:-${VERSION:-local}}"
  step "artefact local : $ARTIFACT"
else
  command -v gh >/dev/null || die "gh introuvable : installe GitHub CLI (https://cli.github.com) puis lance « gh auth login »."
  gh auth status >/dev/null 2>&1 || die "gh n'est pas connecté : lance « gh auth login »."
  ok "gh connecté"
  TAG="$(resolve_tag)"
  [ -n "$TAG" ] || die "Aucune release $CHANNEL trouvée dans $REPO (accès au dépôt ?)."
  step "version $CHANNEL : $TAG"
  ARTIFACT=""
fi
TARGET_VERSION="${TAG#v}"

download() {
  [ -n "$ARTIFACT" ] && return
  step "téléchargement de $PATTERN depuis $REPO@$TAG"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] gh release download %s --repo %s --pattern %q --dir %s\n' "$TAG" "$REPO" "$PATTERN" "$TMP"
    ARTIFACT="$TMP/$(echo "$PATTERN" | tr -d '*')"
    return
  fi
  gh release download "$TAG" --repo "$REPO" --pattern "$PATTERN" --dir "$TMP"
  ARTIFACT="$(find "$TMP" -maxdepth 1 -type f | head -n 1)"
  [ -n "$ARTIFACT" ] || die "Aucun fichier $PATTERN dans la release $TAG."
}

install_macos() {
  local dest="/Applications"
  [ -w "$dest" ] || dest="$HOME/Applications"
  local app="$dest/$APP_NAME.app"
  if [ -d "$app" ] && [ "$FORCE" = 0 ]; then
    local current
    current="$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
    if [ "$current" = "$TARGET_VERSION" ]; then
      ok "$APP_NAME $current est déjà installé dans $dest (--force pour réinstaller)."
      return
    fi
    step "mise à jour de $current vers $TARGET_VERSION"
  fi
  download
  if pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null 2>&1; then
    step "fermeture de $APP_NAME pendant le remplacement"
    run osascript -e "quit app \"$APP_NAME\"" || true
    [ "$DRY_RUN" = 1 ] || sleep 2
  fi
  step "extraction"
  run tar -xzf "$ARTIFACT" -C "$TMP"
  run mkdir -p "$dest"
  step "installation dans $app"
  run rm -rf "$app"
  run cp -R "$TMP/$APP_NAME.app" "$app"
  # Not notarized: without this, Gatekeeper would block the first launch of a downloaded app.
  if [ "$DRY_RUN" = 1 ] || xattr -p com.apple.quarantine "$app" >/dev/null 2>&1; then
    step "app non notarisée : retrait de l'attribut de quarantaine, sinon macOS bloquerait la première ouverture"
    run xattr -dr com.apple.quarantine "$app"
  fi
  done_msg "$APP_NAME $TARGET_VERSION installé : ouvre-le depuis $dest. Les mises à jour suivantes arriveront dans l'app."
}

install_appimage() {
  local dir="$HOME/Applications"
  local app="$dir/dev-cockpit.AppImage"
  local data="${XDG_DATA_HOME:-$HOME/.local/share}"
  local marker="$data/dev-cockpit/installed-version"
  if [ -f "$app" ] && [ "$FORCE" = 0 ] && [ "$(cat "$marker" 2>/dev/null)" = "$TARGET_VERSION" ]; then
    ok "$APP_NAME $TARGET_VERSION est déjà installé dans $app (--force pour réinstaller)."
    return
  fi
  download
  step "installation dans $app"
  run mkdir -p "$dir" "$HOME/.local/bin" "$data/applications" "$data/icons/hicolor/128x128/apps" "$data/dev-cockpit"
  # The updater replaces this very file, so its name stays the same across versions.
  run cp "$ARTIFACT" "$app.partial"
  run chmod +x "$app.partial"
  run mv -f "$app.partial" "$app"
  run ln -sf "$app" "$HOME/.local/bin/dev-cockpit"

  step "icône et entrée du lanceur"
  local icon="$data/icons/hicolor/128x128/apps/dev-cockpit.png"
  local png=""
  if [ "$DRY_RUN" = 0 ]; then
    (cd "$TMP" && "$app" --appimage-extract 'usr/share/icons/hicolor/128x128/apps/*.png' >/dev/null 2>&1) || true
    png="$(find "$TMP/squashfs-root" -name '*.png' 2>/dev/null | head -n 1 || true)"
  fi
  if [ -n "$png" ]; then
    cp "$png" "$icon"
  else
    [ "$DRY_RUN" = 1 ] || warn "icône non extraite de l'AppImage : le lanceur utilisera l'icône par défaut."
  fi
  local desktop="$data/applications/dev-cockpit.desktop"
  if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] écrire %s\n' "$desktop"
  else
    cat >"$desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Reviews, cartes YouTrack, PR et workflows
Exec="$app" %U
Icon=$icon
Terminal=false
Categories=Development;
DESKTOP
    echo "$TARGET_VERSION" >"$marker"
    command -v update-desktop-database >/dev/null && update-desktop-database "$data/applications" >/dev/null 2>&1 || true
  fi

  if ! { ldconfig -p 2>/dev/null || true; } | grep -q 'libfuse.so.2'; then
    warn "libfuse2 semble absent : les AppImage en ont besoin (sudo apt install libfuse2)."
  fi
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "$HOME/.local/bin n'est pas dans le PATH : lance l'app depuis le lanceur." ;; esac
  done_msg "$APP_NAME $TARGET_VERSION installé. Les mises à jour suivantes arriveront dans l'app."
}

install_deb() {
  download
  warn "Le paquet .deb s'installe avec sudo, et ses mises à jour aussi (l'app te les signalera). L'AppImage se met à jour seule."
  step "installation du paquet (sudo indispensable pour dpkg)"
  run sudo apt-get install -y "$ARTIFACT"
  done_msg "$APP_NAME $TARGET_VERSION installé."
}

case "$OS" in
  Darwin) install_macos ;;
  Linux) if [ "$LINUX_FORMAT" = "deb" ]; then install_deb; else install_appimage; fi ;;
esac
