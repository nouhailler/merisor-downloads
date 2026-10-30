#!/usr/bin/env bash

set -Eeuo pipefail

readonly INSTALLER_VERSION="1.0.0"
readonly REPOSITORY="nouhailler/merisor-downloads"
readonly RELEASES_URL="https://github.com/${REPOSITORY}/releases"
readonly API_URL="https://api.github.com/repos/${REPOSITORY}"

install_root="${MERISOR_INSTALL_ROOT:-${HOME:-}/.local}"
with_desktop=true
release_tag="${MERISOR_RELEASE_TAG:-}"
action="install"
temporary_directory=""

say() {
    printf 'MERISOR · %s\n' "$*"
}

warn() {
    printf 'MERISOR · avertissement : %s\n' "$*" >&2
}

fail() {
    printf 'MERISOR · erreur : %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Installateur Linux universel de MERISOR ${INSTALLER_VERSION}

Usage :
  install.sh [options]
  install.sh --uninstall [options]

Options :
  --release VERSION   Installer une release précise (exemple : 0.12.0).
  --prefix CHEMIN     Racine d'installation (défaut : ~/.local).
  --no-desktop        Ne pas créer de lanceur dans le menu des applications.
  --uninstall         Désinstaller MERISOR du profil utilisateur.
  -h, --help          Afficher cette aide.

L'installation ne demande pas sudo. L'AppImage est placée dans
~/.local/lib/merisor et la commande dans ~/.local/bin/merisor.
EOF
}

cleanup() {
    if [[ -n "$temporary_directory" && -d "$temporary_directory" ]]; then
        rm -rf -- "$temporary_directory"
    fi
}
trap cleanup EXIT

while (($#)); do
    case "$1" in
        --release)
            (($# >= 2)) || fail "--release attend un numéro de version."
            release_tag="$2"
            shift 2
            ;;
        --prefix)
            (($# >= 2)) || fail "--prefix attend un chemin."
            install_root="$2"
            shift 2
            ;;
        --no-desktop)
            with_desktop=false
            shift
            ;;
        --uninstall)
            action="uninstall"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "option inconnue : $1"
            ;;
    esac
done

[[ -n "${HOME:-}" ]] || fail "la variable HOME n'est pas définie."

app_directory="${install_root}/lib/merisor"
appimage_path="${app_directory}/MERISOR.AppImage"
version_path="${app_directory}/VERSION"
binary_directory="${install_root}/bin"
binary_path="${binary_directory}/merisor"
data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
desktop_directory="${data_home}/applications"
desktop_path="${desktop_directory}/io.github.nouhailler.merisor.desktop"
icon_directory="${data_home}/icons/hicolor/256x256/apps"
icon_path="${icon_directory}/io.github.nouhailler.merisor.png"

uninstall_merisor() {
    if [[ -f "$binary_path" ]] \
        && grep -q '^# Managed by MERISOR universal installer\.$' "$binary_path"; then
        rm -f -- "$binary_path"
    elif [[ -e "$binary_path" ]]; then
        warn "${binary_path} n'est pas le lanceur créé par MERISOR et a été conservé."
    fi

    rm -f -- "$appimage_path" "$version_path" "$desktop_path" "$icon_path"
    rmdir --ignore-fail-on-non-empty "$app_directory" 2>/dev/null || true
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$desktop_directory" >/dev/null 2>&1 || true
    fi
    say "désinstallation terminée."
}

if [[ "$action" == "uninstall" ]]; then
    uninstall_merisor
    exit 0
fi

for command_name in curl grep install mktemp sha256sum uname; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "commande requise introuvable : ${command_name}"
done

architecture="${MERISOR_ARCH:-$(uname -m)}"
case "$architecture" in
    x86_64|amd64)
        appimage_architecture="x86_64"
        ;;
    *)
        fail "architecture non prise en charge : ${architecture}. La release actuelle est x86_64."
        ;;
esac

curl_options=(--fail --location --silent --show-error --retry 3)
if [[ "${MERISOR_TEST_ALLOW_FILE:-0}" != "1" ]]; then
    curl_options+=(--proto '=https' --tlsv1.2)
fi

if [[ -z "$release_tag" ]]; then
    say "recherche de la dernière release…"
    latest_url="$(curl "${curl_options[@]}" --output /dev/null \
        --write-out '%{url_effective}' "${RELEASES_URL}/latest")" \
        || fail "impossible de déterminer la dernière release."
    release_tag="${latest_url##*/}"
fi
[[ "$release_tag" == v* ]] || release_tag="v${release_tag}"
version="${release_tag#v}"

asset_name="MERISOR-${version}-${appimage_architecture}.AppImage"
asset_url="${MERISOR_APPIMAGE_URL:-${RELEASES_URL}/download/${release_tag}/${asset_name}}"
checksum_url="${MERISOR_CHECKSUM_URL:-${asset_url}.sha256}"
icon_url="${MERISOR_ICON_URL:-https://raw.githubusercontent.com/${REPOSITORY}/main/assets/merisor.png}"

temporary_directory="$(mktemp -d)"
downloaded_appimage="${temporary_directory}/${asset_name}"
downloaded_checksum="${temporary_directory}/${asset_name}.sha256"

say "téléchargement de MERISOR ${version}…"
curl "${curl_options[@]}" "$asset_url" --output "$downloaded_appimage" \
    || fail "téléchargement impossible. Vérifiez que la release est publique et que ${asset_name} existe."

expected_sha256="${MERISOR_APPIMAGE_SHA256:-}"
if [[ -z "$expected_sha256" ]] \
    && curl "${curl_options[@]}" "$checksum_url" --output "$downloaded_checksum" 2>/dev/null; then
    expected_sha256="$(awk 'NR == 1 {print $1}' "$downloaded_checksum")"
fi

if [[ -z "$expected_sha256" ]]; then
    release_metadata_url="${MERISOR_RELEASE_METADATA_URL:-${API_URL}/releases/tags/${release_tag}}"
    release_json="$(curl "${curl_options[@]}" \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        -H 'User-Agent: MERISOR-Linux-Installer' \
        "$release_metadata_url")" \
        || fail "impossible de lire les métadonnées d'intégrité GitHub."
    normalized_json="$(printf '%s' "$release_json" \
        | tr -d '\n\r' \
        | sed -E 's/"name"[[:space:]]*:[[:space:]]*/"name":/g; s/"digest"[[:space:]]*:[[:space:]]*/"digest":/g')"
    asset_section="${normalized_json#*\"name\":\"${asset_name}\"}"
    [[ "$asset_section" != "$normalized_json" ]] \
        || fail "la release ne contient pas l'artefact ${asset_name}."
    asset_section="${asset_section%%\"name\":*}"
    expected_sha256="$(printf '%s' "$asset_section" \
        | sed -nE 's/.*"digest":"sha256:([0-9a-fA-F]{64})".*/\1/p')"
fi

[[ "$expected_sha256" =~ ^[0-9a-fA-F]{64}$ ]] \
    || fail "aucune somme SHA-256 fiable n'est publiée pour ${asset_name}."

actual_sha256="$(sha256sum "$downloaded_appimage" | awk '{print $1}')"
[[ "${actual_sha256,,}" == "${expected_sha256,,}" ]] \
    || fail "la somme SHA-256 de l'AppImage ne correspond pas à la release."
say "intégrité SHA-256 vérifiée."

install -d "$app_directory" "$binary_directory"
install -m 0755 "$downloaded_appimage" "$appimage_path"
printf '%s\n' "$version" >"$version_path"
printf -v quoted_appimage_path '%q' "$appimage_path"
cat >"$binary_path" <<EOF
#!/usr/bin/env bash
# Managed by MERISOR universal installer.
appimage=${quoted_appimage_path}

if [[ -c /dev/fuse ]] \
    && { command -v fusermount >/dev/null 2>&1 || command -v fusermount3 >/dev/null 2>&1; }; then
    exec "\$appimage" "\$@"
fi

APPIMAGE_EXTRACT_AND_RUN=1 exec "\$appimage" "\$@"
EOF
chmod 0755 "$binary_path"

if [[ "$with_desktop" == true ]]; then
    install -d "$desktop_directory" "$icon_directory"
    if curl "${curl_options[@]}" "$icon_url" --output "${temporary_directory}/merisor.png"; then
        install -m 0644 "${temporary_directory}/merisor.png" "$icon_path"
    else
        warn "le logo n'a pas pu être téléchargé ; le lanceur utilisera une icône générique."
    fi

    cat >"$desktop_path" <<EOF
[Desktop Entry]
Type=Application
Name=MERISOR
GenericName=Éditeur MERISE
Comment=Concevoir des MCD, générer des MLD et produire du SQL
Exec=${binary_path}
TryExec=${binary_path}
Icon=io.github.nouhailler.merisor
Terminal=false
Categories=Development;Education;Database;
StartupNotify=true
EOF
    chmod 0644 "$desktop_path"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$desktop_directory" >/dev/null 2>&1 || true
    fi
fi

say "MERISOR ${version} est installé."
say "commande : ${binary_path}"
case ":${PATH}:" in
    *":${binary_directory}:"*) ;;
    *) warn "ajoutez ${binary_directory} à PATH pour lancer MERISOR avec la commande 'merisor'." ;;
esac
say "pour désinstaller : curl -fsSL https://raw.githubusercontent.com/${REPOSITORY}/main/landing-page/install.sh | bash -s -- --uninstall"
