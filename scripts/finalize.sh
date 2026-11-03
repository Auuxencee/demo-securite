#!/usr/bin/env bash
# =============================================================================
#  finalize.sh - Dernière étape, après le merge de la PR d'activation
# -----------------------------------------------------------------------------
#  1. Vérifie que les workflows de sécurité sont bien présents sur la branche
#     principale et que la première analyse CodeQL y est disponible.
#  2. Applique le ruleset de protection de la branche principale
#     (checks obligatoires, revue, blocage CodeQL).
#  3. Supprime les fichiers du template devenus inutiles (scripts, sources,
#     documentation, configuration, .env) via cleanup.sh.
#     En mode --target, le projet ne contient déjà que les fichiers utiles :
#     il suffit de supprimer le dossier du template.
#
#  Usage :
#    bash scripts/finalize.sh [--target <dossier>] [--skip-ruleset] [--yes]
# =============================================================================

set -uo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

CONFIG="${TEMPLATE_ROOT}/CONFIGURATION.md"
ENV_PATH="${TEMPLATE_ROOT}/.env"
TARGET=""
SKIP_RULESET=false
YES=false

while [ $# -gt 0 ]; do
  case "$1" in
    --target)       TARGET="${2:-}"; shift 2 ;;
    --skip-ruleset) SKIP_RULESET=true; shift ;;
    --yes|-y)       YES=true; shift ;;
    --config)       CONFIG="${2:-}"; shift 2 ;;
    --env)          ENV_PATH="${2:-}"; shift 2 ;;
    -h|--help)      sed -n '2,16p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
    *) die "Option inconnue : $1" ;;
  esac
done

load_config "$CONFIG" "$ENV_PATH"
if [ -n "$TARGET" ]; then
  [ -d "$TARGET" ] || die "Dossier cible introuvable : ${TARGET}"
  DEST="$(cd "$TARGET" && pwd)"
else
  DEST="$TEMPLATE_ROOT"
fi
WF="${DEST}/.github/workflows"
REPO="$(cfg GITHUB_REPO)"
BRANCH="$(cfg DEFAULT_BRANCH main)"

# =============================================================================
#  1-2. Ruleset
# =============================================================================
if $SKIP_RULESET || ! is_true ENABLE_BRANCH_RULESET; then
  title "Ruleset"
  info "ignoré"
elif [ -z "$REPO" ]; then
  title "Ruleset"
  warn "GITHUB_REPO vide dans CONFIGURATION.md : ruleset non appliqué."
else
  title "Vérification de la branche ${BRANCH} sur ${REPO}"
  gh_ready || die "GitHub CLI indisponible ou non authentifié (gh auth login, ou GH_TOKEN dans .env)."

  remote_files="$(gh api "repos/${REPO}/contents/.github/workflows?ref=${BRANCH}" --jq '.[].name' 2>/dev/null || true)"
  missing=""
  for f in "$WF"/*.yml; do
    [ -e "$f" ] || continue
    printf '%s\n' "$remote_files" | grep -qxF "$(basename "$f")" || missing="${missing} $(basename "$f")"
  done
  if [ -n "$missing" ]; then
    die "Workflows absents de la branche ${BRANCH} :${missing}. Mergez d'abord la PR d'activation."
  fi
  ok "Workflows présents sur ${BRANCH}"

  if [ -f "$WF/codeql.yml" ] && [ "$(cfg CODEQL_BLOCK_SEVERITY high_or_higher)" != "none" ]; then
    analyses="$(gh api "repos/${REPO}/code-scanning/analyses?ref=refs/heads/${BRANCH}&tool_name=CodeQL&per_page=1" \
      --jq 'length' 2>/dev/null || echo 0)"
    if [ "${analyses:-0}" = "0" ]; then
      die "Aucune analyse CodeQL sur ${BRANCH} pour l'instant. Attendez la fin du workflow \"SAST - CodeQL\" (onglet Actions) puis relancez : sans elle, la règle de blocage CodeQL bloquerait toutes les PR."
    fi
    ok "Analyse CodeQL disponible sur ${BRANCH}"
  fi

  bash "$(dirname "$0")/enable-security.sh" --config "$CONFIG" --env "$ENV_PATH" \
    --workflows-dir "$WF" --only-ruleset || die "Ruleset non appliqué : nettoyage annulé. Corrigez puis relancez."
fi

# =============================================================================
#  3. Nettoyage
# =============================================================================
if [ "$DEST" = "$TEMPLATE_ROOT" ]; then
  args=(); $YES && args+=(--yes)
  is_true KEEP_DOCUMENTATION && args+=(--keep-docs)
  exec bash "$(dirname "$0")/cleanup.sh" "${args[@]}"
else
  title "Nettoyage"
  info "Le projet ${DEST} ne contient que les fichiers de sécurité utiles."
  info "Vous pouvez supprimer le dossier du template : ${TEMPLATE_ROOT}"
  [ -f "$ENV_PATH" ] && warn "Il contient encore ${ENV_PATH} (secrets) : supprimez-le."
  if is_true KEEP_DOCUMENTATION; then
    info "Pour conserver la documentation : copiez ${TEMPLATE_ROOT}/README.md dans le projet (ex : SECURITE-CICD.md)."
  fi
fi
