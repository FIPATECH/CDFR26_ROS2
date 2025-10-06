#!/usr/bin/env bash

# =====================================================================
# CDFR26_ROS2 setup script
#
# Objectif :
#   Préparer un environnement ROS 2 local, cloner un dépôt GitHub privé
#   dans ros2_ws/src, puis garantir que ~/.bashrc contient les lignes 
#   utiles à ROS 2 Humble, au RMW Cyclone DDS et au workspace courant
#
# Comportement :
#   1) Vérifie les outils requis, git, mkdir, ssh
#   2) Vérifie l'authentification SSH vers GitHub
#   3) Vérifie l'accès au dépôt privé
#   4) Crée ros2_ws/src si nécessaire
#   5) Clone le dépôt, ou propose overwrite, skip si déjà présent
#   6) Ajoute dans ~/.bashrc les lignes nécessaires
#
# Prérequis :
#   - Clé SSH chargée et autorisée sur GitHub
#   - Accès au dépôt GitHub privé
#   - ROS 2 Humble installé
#
# Sorties :
#   - ros2_ws/src/CDFR26_ROS2 cloné dans le répertoire courant
#   - Mise à jour de ~/.bashrc
# =====================================================================

set -euo pipefail

REPO_PATH="FIPATECH/CDFR26_ROS2"
REPO_SSH="git@github.com:${REPO_PATH}.git"

# ---------------------------------------------------------------------
# Couleurs pour les logs, activées uniquement si la sortie est un TTY
# ---------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_INFO="\033[1;34m"   # bleu
  C_WARN="\033[1;33m"   # jaune
  C_ERR="\033[1;31m"    # rouge
  C_RST="\033[0m"
else
  C_INFO=""; C_WARN=""; C_ERR=""; C_RST=""
fi

# ---------------------------------------------------------------------
# Journalisation et gestion d'erreurs
# ---------------------------------------------------------------------
log()   { echo -e "${C_INFO}[INFO]${C_RST} $*"; }
warn()  { echo -e "${C_WARN}[WARN]${C_RST} $*" >&2; }
error() { echo -e "${C_ERR}[ERREUR]${C_RST} $*" >&2; exit 1; }

# Vérifie la présence d'une commande
need_cmd() { command -v "$1" >/dev/null 2>&1 || error "Commande manquante, installez: $1"; }

# ---------------------------------------------------------------------
# Bannière d'accueil
# ---------------------------------------------------------------------
print_banner() {
  cat <<'ASCII'


    ░░░░░░░ ░░ ░░░░░░   ░░░░░  ░░░░░░░░ ░░░░░░░  ░░░░░░ ░░   ░░ 
    ▒▒      ▒▒ ▒▒   ▒▒ ▒▒   ▒▒    ▒▒    ▒▒      ▒▒      ▒▒   ▒▒ 
    ▒▒▒▒▒   ▒▒ ▒▒▒▒▒▒  ▒▒▒▒▒▒▒    ▒▒    ▒▒▒▒▒   ▒▒      ▒▒▒▒▒▒▒ 
    ▓▓      ▓▓ ▓▓      ▓▓   ▓▓    ▓▓    ▓▓      ▓▓      ▓▓   ▓▓ 
    ██      ██ ██      ██   ██    ██    ███████  ██████ ██   ██     CDFR26_ROS2 setup script
                                                                                                                                                
ASCII
  echo
}

# ---------------------------------------------------------------------
# Vérifie les outils requis
# ---------------------------------------------------------------------
preflight_git() { need_cmd git; need_cmd mkdir; need_cmd ssh; }

# ---------------------------------------------------------------------
# Authentification SSH GitHub, confirme qu'une clé utilisable est chargée
# ---------------------------------------------------------------------
check_ssh_ready() {
  log "-> Test d'authentification SSH vers GitHub"
  set +e
  local out; out="$(ssh -o BatchMode=yes -T git@github.com 2>&1)"
  set -e
  if echo "${out}" | grep -qi "success\|authenticated"; then
    log "SSH GitHub confirmé"
    return 0
  fi
  warn "SSH non confirmé, message GitHub, ${out}"
  warn "Ajoutez votre clé SSH dans GitHub puis réessayez"
  return 1
}

# ---------------------------------------------------------------------
# Vérification d'accès au dépôt privé, évite un clonage inutile
# ---------------------------------------------------------------------
check_repo_access() {
  local url="$1"
  log "-> Vérification d'accès au dépôt privé ${REPO_PATH}"
  if git ls-remote "${url}" >/dev/null 2>&1; then
    log "Accès au dépôt confirmé"
    return 0
  fi
  warn "Accès refusé, droits manquants ou clé non autorisée"
  return 1
}

# ---------------------------------------------------------------------
# Choix utilisateur si le dépôt existe déjà
#   Interactif, propose overwrite ou skip
#   Non interactif, skip par défaut
# ---------------------------------------------------------------------
USER_CHOICE="skip"
get_user_choice() {
  if [[ -r /dev/tty ]]; then
    warn "Le dépôt est déjà présent dans ce répertoire"
    printf "Choisir : [o] overwrite, [s] skip, [skip par défaut] ? " 1>&2
    local ans=""
    IFS= read -r ans < /dev/tty || ans=""
    ans="${ans//[[:space:]]/}"
    if [[ "$ans" == "o" || "$ans" == "O" ]]; then
      USER_CHOICE="overwrite"
    else
      USER_CHOICE="skip"
    fi
  else
    warn "Terminal non interactif détecté, dépôt déjà présent, conservation et passage à l'étape suivante"
    USER_CHOICE="skip"
  fi
}

# ---------------------------------------------------------------------
# Clone conditionnel du dépôt, applique la politique choisie
# ---------------------------------------------------------------------
clone_or_decide() {
  local url="$1"; local dest="$2"
  if [[ -d "${dest}/.git" ]]; then
    get_user_choice
    log "Choix utilisateur : ${USER_CHOICE}"
    if [[ "$USER_CHOICE" == "overwrite" ]]; then
      warn "-> Suppression complète du répertoire avant re-clonage"
      rm -rf "${dest}"
      log "-> Clonage du dépôt"
      git clone "${url}" "${dest}"
    else
      log "-> Dépôt existant conservé, aucune modification"
    fi
  else
    log "-> Clonage du dépôt"
    git clone "${url}" "${dest}"
  fi
}

# ---------------------------------------------------------------------
# Ajout portable et idempotent des lignes ROS 2 dans ~/.bashrc
# ---------------------------------------------------------------------
ensure_bashrc_ros2_lines() {
  local brc="$HOME/.bashrc"
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  [[ -f "$brc" ]] || touch "$brc"
  cp -a "$brc" "${brc}.bak.${ts}"

  local ABS_CWD LC_WS
  ABS_CWD="$(pwd -P)"
  LC_WS="source ${ABS_CWD}/ros2_ws/install/setup.bash"

  # Ajoute une ligne si et seulement si elle est absente, évite les doublons
  local header_printed="no"
  add_line_once() {
    local line="$1"
    local pattern="$2"
    if ! grep -Eq "$pattern" "$brc"; then
      # Ajout d'un saut de ligne si le fichier non vide ne se termine pas par \n
      if [[ -s "$brc" ]]; then
        if [[ "$(tail -c1 "$brc" 2>/dev/null | wc -l)" -eq 0 ]]; then echo >> "$brc"; fi
      fi
      if [[ "$header_printed" == "no" ]]; then
        header_printed="yes"
      fi
      echo "$line" >> "$brc"
      log "-> Ajout : $line"
    fi
  }

  # 1. Garantit le source de ROS 2 Humble
  add_line_once "source /opt/ros/humble/setup.bash" \
                '^[[:space:]]*source[[:space:]]+/opt/ros/humble/setup\.bash[[:space:]]*$'

  # 2. Garantit le RMW Cyclone DDS
  add_line_once "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" \
                '^[[:space:]]*export[[:space:]]+RMW_IMPLEMENTATION=rmw_cyclonedds_cpp[[:space:]]*$'

  # 3. Garantit la ligne du workspace courant (tolère ~ et $HOME)
  local found="no"
  mapfile -t existing_ws < <(
    awk '
      /^[[:space:]]*source[[:space:]]+([^#]*\/ros2_ws\/install\/setup\.bash)[[:space:]]*$/ {print $0}
    ' "$brc"
  )
  for l in "${existing_ws[@]:-}"; do
    local p
    p="$(printf '%s\n' "$l" | sed -e 's/^[[:space:]]*source[[:space:]]\+//' \
                                  -e 's/[[:space:]]*$//' \
                                  -e 's/^"//' -e 's/"$//' \
                                  -e "s/^'//" -e "s/'$//" \
                                  -e "s|^~/|$HOME/|" \
                                  -e "s|^\$HOME/|$HOME/|")"
    if [[ "source $p" == "$LC_WS" ]]; then found="yes"; break; fi
  done
  if [[ "$found" == "no" ]]; then
    add_line_once "$LC_WS" \
                  "^[[:space:]]*source[[:space:]]+$(printf '%s' "${ABS_CWD}/ros2_ws/install/setup.bash" | sed 's|/|\\/|g')[[:space:]]*$"
  fi
}

# ---------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------
main() {
    print_banner
    log "Début du script d'installation"

    preflight_git

    local WORKDIR SRC_DIR ROS_WS REPO_DIR
    WORKDIR="$(pwd -P)"
    ROS_WS="${WORKDIR}/ros2_ws"
    SRC_DIR="${ROS_WS}/src"
    REPO_DIR="${SRC_DIR}/$(basename "$REPO_PATH")"

    [[ -d "$SRC_DIR" ]] || { log "-> Création des dossiers, ${SRC_DIR}"; mkdir -p "${SRC_DIR}"; }

    check_ssh_ready || error "SSH pas prêt, ajoutez la clé dans GitHub"
    check_repo_access "${REPO_SSH}" || error "Accès refusé au dépôt via SSH, vérifiez vos droits"

    clone_or_decide "${REPO_SSH}" "${REPO_DIR}"

    # log "-> Mise à jour de ~/.bashrc"
    # ensure_bashrc_ros2_lines

    log "CDFR26_ROS2 correctement installé !"
}

main
