#!/usr/bin/env bash
# =============================================================================
#  Fonctions communes aux scripts (lecture de CONFIGURATION.md et de .env,
#  affichage). Ce fichier est chargé par les autres scripts, il ne s'exécute
#  pas seul.
# =============================================================================

# shellcheck disable=SC2034
# Racine du template (dossier contenant CONFIGURATION.md, scripts/, template/).
TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Affichage -------------------------------------------------------------
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""; C_RESET=""
fi
title() { printf '\n%s== %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
ok()    { printf '%sOK%s     %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info()  { printf '       %s\n' "$*"; }
warn()  { printf '%sATTENTION%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fail()  { printf '%sERREUR%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { fail "$*"; exit 1; }

# --- Lecture d'un fichier CLE=valeur -----------------------------------------
# Le fichier n'est jamais exécuté (pas de "source") : chaque ligne est
# analysée, ce qui évite l'exécution de code arbitraire.
#   load_kv_file <fichier> <préfixe>
# Crée une variable <préfixe><CLE> par entrée et remplit <préfixe>KEYS.
load_kv_file() {
  local file="$1" prefix="$2" line key value n=0 keys=""
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"                                   # fins de ligne Windows
    case "$line" in ''|[[:space:]]*'#'*|'#'*) continue ;; esac
    if ! printf '%s' "$line" | grep -Eq '^[[:space:]]*[A-Z][A-Z0-9_]*[[:space:]]*='; then
      [ -z "$(printf '%s' "$line" | tr -d '[:space:]')" ] && continue
      die "${file}:${n} : ligne invalide (format attendu CLE=valeur) : ${line}"
    fi
    key="$(printf '%s' "${line%%=*}" | tr -d '[:space:]')"
    value="${line#*=}"
    value="${value#"${value%%[![:space:]]*}"}"             # espaces en tête
    case "$value" in
      \"*) value="${value#\"}"
           case "$value" in *\"*) ;; *) die "${file}:${n} : guillemet non fermé pour ${key}" ;; esac
           value="${value%%\"*}" ;;
      \'*) value="${value#\'}"
           case "$value" in *\'*) ;; *) die "${file}:${n} : guillemet non fermé pour ${key}" ;; esac
           value="${value%%\'*}" ;;
      *)   value="$(printf '%s' "$value" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')" ;;
    esac
    printf -v "${prefix}${key}" '%s' "$value"
    keys="${keys} ${key}"
  done < "$file"
  printf -v "${prefix}KEYS" '%s' "$keys"
  return 0
}

# --- Lecture de CONFIGURATION.md ---------------------------------------------
# Seules deux formes de ligne sont lues, tout le reste (titres, texte,
# explications) est ignoré :
#   - [x] Libellé · `CLE` · ...      case à cocher : true si cochée, sinon false
#   | `CLE` | valeur | aide |         ligne de tableau : valeur de la 2e colonne
# Remplit CFG_<CLE> et CFG_KEYS, comme load_kv_file.
load_md_config() {
  local file="$1" line n=0 keys="" key value re_box re_row
  re_box='^[[:space:]]*[-*][[:space:]]+\[([ xX])\][^`]*`([A-Z][A-Z0-9_]*)`'
  re_row='^[[:space:]]*\|[[:space:]]*`([A-Z][A-Z0-9_]*)`[[:space:]]*\|([^|]*)\|'
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%$'\r'}"
    if [[ $line =~ $re_box ]]; then
      key="${BASH_REMATCH[2]}"
      if [ "${BASH_REMATCH[1]}" = " " ]; then value=false; else value=true; fi
    elif [[ $line =~ $re_row ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      value="${value#"${value%%[![:space:]]*}"}"           # espaces en tête
      value="${value%"${value##*[![:space:]]}"}"           # espaces en fin
      value="${value#\`}"; value="${value%\`}"             # `valeur`
      value="${value#\"}"; value="${value%\"}"             # "valeur"
    else
      continue
    fi
    case " $keys " in *" $key "*) die "${file}:${n} : ${key} apparaît deux fois." ;; esac
    printf -v "CFG_${key}" '%s' "$value"
    keys="${keys} ${key}"
  done < "$file"
  CFG_KEYS="$keys"
  return 0
}

# cfg CLE [défaut] : valeur lue dans CONFIGURATION.md
cfg() {
  local name="CFG_$1"
  if [ -n "${!name+x}" ] && [ -n "${!name}" ]; then
    printf '%s' "${!name}"
  else
    printf '%s' "${2:-}"
  fi
}

# envv CLE : valeur lue dans .env
envv() {
  local name="ENV_$1"
  printf '%s' "${!name:-}"
}

# is_true CLE : la clé booléenne vaut true
is_true() { [ "$(cfg "$1" false)" = "true" ]; }

# Charge la configuration (obligatoire) et .env (facultatif).
# CONFIGURATION.md par défaut ; un ancien fichier CLE=valeur reste accepté.
#   load_config <chemin CONFIGURATION.md> [chemin .env]
load_config() {
  local conf="$1" env_file="${2:-}"
  [ -f "$conf" ] || die "Fichier de configuration introuvable : ${conf}"
  case "$conf" in
    *.md) load_md_config "$conf" ;;
    *)    load_kv_file "$conf" CFG_ ;;
  esac
  if [ -n "$env_file" ] && [ -f "$env_file" ]; then
    load_kv_file "$env_file" ENV_
    # Jeton GitHub facultatif pour la CLI gh.
    if [ -n "$(envv GH_TOKEN)" ]; then
      GH_TOKEN="$(envv GH_TOKEN)"
      export GH_TOKEN
    fi
  fi
}

# Vérifie que la CLI GitHub est disponible et authentifiée.
gh_ready() {
  command -v gh >/dev/null 2>&1 || return 1
  gh auth status >/dev/null 2>&1 || return 2
  return 0
}

# Le fichier est-il suivi par Git ? (protection contre le commit de .env)
git_tracked() {
  local file="$1" dir
  dir="$(cd "$(dirname "$file")" && pwd)"
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  git -C "$dir" ls-files --error-unmatch "$(basename "$file")" >/dev/null 2>&1
}
