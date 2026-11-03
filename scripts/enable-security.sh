#!/usr/bin/env bash
# =============================================================================
#  enable-security.sh - Active les fonctions de sécurité GitHub d'un repo
# -----------------------------------------------------------------------------
#  Appelé par setup.sh (réglages) et finalize.sh (ruleset). Peut aussi être
#  lancé seul. Les réglages sont lus dans CONFIGURATION.md (section 3).
#
#  Automatise via l'API REST GitHub (CLI "gh") ce qui se fait normalement à
#  la main dans Settings > Advanced Security et Settings > Rules :
#    - alertes Dependabot (+ dependency graph) et security updates ;
#    - signalement privé de vulnérabilités (repos publics) ;
#    - secret scanning et push protection ;
#    - licence Code Security sur un repo privé (si demandé) ;
#    - ruleset de la branche par défaut : PR obligatoire, approbations, revue
#      CODEOWNERS, pas de force-push ni de suppression, checks de sécurité
#      obligatoires (déduits des workflows présents), blocage CodeQL.
#
#  Idempotent : relançable sans effet de bord. Une étape en échec (licence
#  absente, politique d'organisation...) n'interrompt pas les suivantes.
#
#  Usage :
#    bash scripts/enable-security.sh [--skip-ruleset | --only-ruleset]
#        [--print-ruleset] [--dry-run] [--workflows-dir <dossier>]
#        [--repo <owner/nom>] [--config <fichier>] [--env <fichier>]
# =============================================================================

set -uo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

CONFIG="${TEMPLATE_ROOT}/CONFIGURATION.md"
ENV_PATH="${TEMPLATE_ROOT}/.env"
REPO_OVERRIDE=""
WORKFLOWS_DIR=""
DRY_RUN=false
SKIP_RULESET=false
ONLY_RULESET=false
PRINT_RULESET=false

RULESET_NAME="securite-branche-principale"
# Identifiant de l'application "GitHub Actions" : seuls les checks produits
# par GitHub Actions satisfont le ruleset (une autre intégration ne peut pas
# publier un faux statut "vert" portant le même nom).
GITHUB_ACTIONS_APP_ID=15368

while [ $# -gt 0 ]; do
  case "$1" in
    --config)        CONFIG="${2:-}"; shift 2 ;;
    --env)           ENV_PATH="${2:-}"; shift 2 ;;
    --repo)          REPO_OVERRIDE="${2:-}"; shift 2 ;;
    --workflows-dir) WORKFLOWS_DIR="${2:-}"; shift 2 ;;
    --dry-run)       DRY_RUN=true; shift ;;
    --skip-ruleset)  SKIP_RULESET=true; shift ;;
    --only-ruleset)  ONLY_RULESET=true; shift ;;
    --print-ruleset) PRINT_RULESET=true; shift ;;
    -h|--help)       sed -n '2,25p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
    *) die "Option inconnue : $1" ;;
  esac
done
$SKIP_RULESET && $ONLY_RULESET && die "--skip-ruleset et --only-ruleset sont incompatibles."

load_config "$CONFIG" "$ENV_PATH"
REPO="${REPO_OVERRIDE:-$(cfg GITHUB_REPO)}"
[ -n "$WORKFLOWS_DIR" ] || WORKFLOWS_DIR="${TEMPLATE_ROOT}/.github/workflows"
APPROVALS="$(cfg REQUIRED_APPROVALS 1)"
CODEQL_THRESHOLD="$(cfg CODEQL_BLOCK_SEVERITY high_or_higher)"

# ----------------------------------------------------------------------------
# Ruleset
# ----------------------------------------------------------------------------
# Correspondance workflow -> nom du check (= "name" du job). Uniquement des
# workflows déclenchés sur pull_request, sinon le check ne serait jamais
# rapporté et les PR resteraient bloquées.
required_checks() {
  local d="$WORKFLOWS_DIR"
  [ -f "$d/dependency-review.yml" ] && echo "SCA - Dependency Review"
  [ -f "$d/container-scan.yml" ]    && echo "Container - Trivy (image)"
  [ -f "$d/iac-scan.yml" ]          && echo "IaC - Trivy (config)"
  [ -f "$d/secrets-scan.yml" ]      && echo "Secrets - Gitleaks"
  if [ -f "$d/dast-zap.yml" ] && grep -qE '^  pull_request:' "$d/dast-zap.yml"; then
    echo "DAST - ZAP baseline"
  fi
  return 0
}

codeql_rule_enabled() {
  [ -f "$WORKFLOWS_DIR/codeql.yml" ] && [ "$CODEQL_THRESHOLD" != "none" ]
}

code_owner_review() {
  if [ "$APPROVALS" -gt 0 ] && is_true ENABLE_CODEOWNERS; then echo true; else echo false; fi
}

build_ruleset() {
  local checks_json="" first=true check
  while IFS= read -r check; do
    [ -z "$check" ] && continue
    $first || checks_json+=","
    checks_json+=$'\n'"          { \"context\": \"${check}\", \"integration_id\": ${GITHUB_ACTIONS_APP_ID} }"
    first=false
  done < <(required_checks)

  cat <<EOF
{
  "name": "${RULESET_NAME}",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": ${APPROVALS},
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": $(code_owner_review),
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    }
EOF
  if [ -n "$checks_json" ]; then
    cat <<EOF
    ,{
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": true,
        "required_status_checks": [${checks_json}
        ]
      }
    }
EOF
  fi
  if codeql_rule_enabled; then
    cat <<EOF
    ,{
      "type": "code_scanning",
      "parameters": {
        "code_scanning_tools": [
          { "tool": "CodeQL", "security_alerts_threshold": "${CODEQL_THRESHOLD}", "alerts_threshold": "errors" }
        ]
      }
    }
EOF
  fi
  printf '  ]\n}\n'
}

if $PRINT_RULESET; then
  build_ruleset
  exit 0
fi

# ----------------------------------------------------------------------------
# Vérifications préalables
# ----------------------------------------------------------------------------
[ -n "$REPO" ] || die "GITHUB_REPO est vide dans CONFIGURATION.md (ou utilisez --repo)."
gh_ready; rc=$?
[ "$rc" -eq 1 ] && die "GitHub CLI (gh) introuvable : https://cli.github.com"
[ "$rc" -eq 2 ] && die "GitHub CLI non authentifié : lancez 'gh auth login' ou renseignez GH_TOKEN dans .env"

if ! repo_info="$(gh api "repos/${REPO}" --jq '[.permissions.admin, .visibility, .default_branch] | @tsv' 2>&1)"; then
  die "Repo ${REPO} inaccessible : ${repo_info}"
fi
IFS=$'\t' read -r IS_ADMIN VISIBILITY DEFAULT_BRANCH <<< "$repo_info"

title "Repo ${REPO} (${VISIBILITY}, branche par défaut : ${DEFAULT_BRANCH})"
$DRY_RUN && info "simulation (--dry-run) : aucune modification"
[ "$IS_ADMIN" = "true" ] || warn "votre compte n'est pas administrateur du repo : les étapes risquent d'échouer."
if [ "$DEFAULT_BRANCH" != "$(cfg DEFAULT_BRANCH main)" ]; then
  warn "DEFAULT_BRANCH=$(cfg DEFAULT_BRANCH main) dans CONFIGURATION.md, mais la branche par défaut du repo est ${DEFAULT_BRANCH}."
fi

# ----------------------------------------------------------------------------
# Exécution
# ----------------------------------------------------------------------------
RESULTS=()
FAILURES=0

api_call() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    { gh api --method "$method" "$path" --input - >/dev/null <<< "$body"; } 2>&1
  else
    { gh api --method "$method" "$path" >/dev/null; } 2>&1
  fi
}

# step "<libellé>" <méthode> <chemin API> [corps JSON]
step() {
  local label="$1" method="$2" path="$3" body="${4:-}" out
  if $DRY_RUN; then
    info "[simulation] ${method} /${path}"
    RESULTS+=("SIMULÉ  ${label}")
    return 0
  fi
  if out="$(api_call "$method" "$path" "$body")"; then
    ok "$label"
    RESULTS+=("OK      ${label}")
    return 0
  fi
  fail "$label"
  printf '       %s\n' "$out" | head -3
  RESULTS+=("ÉCHEC   ${label}")
  FAILURES=$((FAILURES + 1))
  return 1
}

skipped() { RESULTS+=("IGNORÉ  $1"); info "ignoré   $1"; }

R="repos/${REPO}"
sa() { printf '{"security_and_analysis":{"%s":{"status":"enabled"}}}' "$1"; }

if ! $ONLY_RULESET; then
  title "Fonctions de sécurité"

  if is_true ENABLE_CODE_SECURITY_LICENSE && [ "$VISIBILITY" != "public" ]; then
    # Nouvelles licences (Code Security, depuis 2025) ; repli sur l'ancienne
    # licence groupée "Advanced Security" si refusé.
    if $DRY_RUN || api_call PATCH "$R" "$(sa code_security)" >/dev/null; then
      ok "Licence Code Security"; RESULTS+=("OK      Licence Code Security")
    else
      step "Licence Advanced Security (ancienne offre)" PATCH "$R" "$(sa advanced_security)"
    fi
  fi

  if is_true ENABLE_DEPENDABOT_ALERTS; then
    step "Alertes Dependabot + dependency graph" PUT "$R/vulnerability-alerts"
  else skipped "Alertes Dependabot (décoché dans CONFIGURATION.md)"; fi

  if is_true ENABLE_DEPENDABOT_SECURITY_UPDATES; then
    step "Dependabot security updates" PUT "$R/automated-security-fixes"
  else skipped "Dependabot security updates (désactivé)"; fi

  if is_true ENABLE_PRIVATE_VULN_REPORTING; then
    if [ "$VISIBILITY" = "public" ]; then
      step "Signalement privé de vulnérabilités" PUT "$R/private-vulnerability-reporting"
    else skipped "Signalement privé de vulnérabilités (repos publics uniquement)"; fi
  fi

  if is_true ENABLE_SECRET_SCANNING; then
    step "Secret scanning" PATCH "$R" "$(sa secret_scanning)"
  else skipped "Secret scanning (désactivé)"; fi

  if is_true ENABLE_PUSH_PROTECTION; then
    step "Push protection" PATCH "$R" "$(sa secret_scanning_push_protection)"
  else skipped "Push protection (désactivé)"; fi
fi

if ! $SKIP_RULESET; then
  title "Ruleset de la branche ${DEFAULT_BRANCH}"
  if ! is_true ENABLE_BRANCH_RULESET; then
    skipped "Ruleset (ENABLE_BRANCH_RULESET=false)"
  else
    [ -d "$WORKFLOWS_DIR" ] || warn "Dossier de workflows introuvable : ${WORKFLOWS_DIR}"
    checks="$(required_checks)"
    info "Approbations requises : ${APPROVALS} ; revue CODEOWNERS : $(code_owner_review)"
    if [ -n "$checks" ]; then
      info "Checks obligatoires :"
      while IFS= read -r c; do info "  - ${c}"; done <<< "$checks"
    fi
    codeql_rule_enabled && info "Blocage CodeQL : alertes ${CODEQL_THRESHOLD}"

    ruleset_json="$(build_ruleset)"
    existing_id=""
    if ! $DRY_RUN; then
      existing_id="$(gh api "$R/rulesets" --paginate \
        --jq ".[] | select(.name == \"${RULESET_NAME}\" and .source_type == \"Repository\") | .id" 2>/dev/null | head -1)"
    fi
    if [ -n "$existing_id" ]; then
      step "Ruleset '${RULESET_NAME}' (mise à jour)" PUT "$R/rulesets/${existing_id}" "$ruleset_json"
    else
      step "Ruleset '${RULESET_NAME}' (création)" POST "$R/rulesets" "$ruleset_json"
    fi
  fi
fi

title "Bilan"
printf '  %s\n' "${RESULTS[@]}"
echo
info "Vérification : https://github.com/${REPO}/settings/security_analysis"
info "               https://github.com/${REPO}/settings/rules"

if [ "$FAILURES" -gt 0 ]; then
  echo
  warn "${FAILURES} étape(s) en échec. Causes fréquentes : droits insuffisants, licence absente"
  warn "sur un repo privé, fonction désactivée par une politique d'organisation."
  exit 1
fi
exit 0
