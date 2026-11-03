#!/usr/bin/env bash
# =============================================================================
#  setup.sh - Installe la sécurité CI/CD dans un projet à partir de CONFIGURATION.md
# -----------------------------------------------------------------------------
#  1. Vérifie CONFIGURATION.md (valeurs manquantes ou incohérentes).
#  2. Génère dans le projet uniquement les fichiers des fonctions activées
#     (workflows, Dependabot, CODEOWNERS, SECURITY.md, exceptions...) et
#     retire ceux des fonctions désactivées lors d'une exécution précédente.
#  3. Si GITHUB_REPO est renseigné :
#       - envoie les secrets de .env dans les secrets GitHub Actions du repo ;
#       - active les réglages de sécurité du repo (Dependabot, secret
#         scanning, push protection...). Le ruleset est appliqué plus tard
#         par finalize.sh, après le merge de la PR d'activation.
#
#  Deux modes :
#    - sur place (défaut) : les fichiers sont générés à la racine du repo
#      contenant ce template (nouveau projet créé avec "Use this template") ;
#    - --target <dossier> : les fichiers sont générés dans un autre repo
#      (projet existant) ; seul le strict nécessaire y est copié.
#
#  Relançable à volonté : modifier CONFIGURATION.md puis relancer met le projet
#  à jour.
#
#  Usage :
#    bash scripts/setup.sh [--target <dossier>] [--local-only] [--force]
#                          [--config <fichier>] [--env <fichier>]
# =============================================================================

set -uo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

CONFIG="${TEMPLATE_ROOT}/CONFIGURATION.md"
ENV_PATH="${TEMPLATE_ROOT}/.env"
TARGET=""
LOCAL_ONLY=false
FORCE=false

usage() {
  cat <<'EOF'
Usage : bash scripts/setup.sh [--target <dossier>] [--local-only] [--force]

Options :
  --target <dossier>   Repo du projet existant à équiper (défaut : ce repo)
  --local-only         Génère les fichiers sans appeler l'API GitHub
  --force              Écrase les fichiers existants du projet portant le même nom
  --config <fichier>   Autre fichier de configuration (défaut : CONFIGURATION.md)
  --env <fichier>      Autre fichier de secrets (défaut : .env)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)     TARGET="${2:-}"; shift 2 ;;
    --local-only) LOCAL_ONLY=true; shift ;;
    --force)      FORCE=true; shift ;;
    --config)     CONFIG="${2:-}"; shift 2 ;;
    --env)        ENV_PATH="${2:-}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) fail "Option inconnue : $1"; usage >&2; exit 2 ;;
  esac
done

load_config "$CONFIG" "$ENV_PATH"

if [ -n "$TARGET" ]; then
  [ -d "$TARGET" ] || die "Dossier cible introuvable : ${TARGET}"
  DEST="$(cd "$TARGET" && pwd)"
  [ "$DEST" = "$TEMPLATE_ROOT" ] && DEST="$TEMPLATE_ROOT"
else
  DEST="$TEMPLATE_ROOT"
fi
SRC="${TEMPLATE_ROOT}/template"
[ -d "$SRC" ] || die "Dossier template/ introuvable : le template a déjà été finalisé ?"

# =============================================================================
#  1. Validation de la configuration
# =============================================================================
title "Vérification de $(basename "$CONFIG")"
ERRORS=0
err() { fail "$*"; ERRORS=$((ERRORS + 1)); }

KNOWN_KEYS=" GITHUB_REPO DEFAULT_BRANCH ENABLE_SAST ENABLE_DEPENDENCY_REVIEW ENABLE_DEPENDABOT_UPDATES
 ENABLE_SECRETS_SCAN ENABLE_DOCKER ENABLE_IAC ENABLE_DAST ENABLE_PRECOMMIT ENABLE_CODEOWNERS
 ENABLE_SECURITY_POLICY ENABLE_PR_TEMPLATE ENABLE_DEPENDABOT_ALERTS ENABLE_DEPENDABOT_SECURITY_UPDATES
 ENABLE_SECRET_SCANNING ENABLE_PUSH_PROTECTION ENABLE_PRIVATE_VULN_REPORTING ENABLE_CODE_SECURITY_LICENSE
 ENABLE_BRANCH_RULESET REQUIRED_APPROVALS FAIL_ON_SEVERITY CODEQL_BLOCK_SEVERITY BLOCK_UNFIXED_VULNERABILITIES
 DENY_LICENSES CODEQL_LANGUAGES CODEQL_BUILD_MODE CODEQL_BUILD_COMMAND CODEQL_QUERY_SUITE
 DEPENDENCY_MANIFESTS DEPENDABOT_INTERVAL DEPENDABOT_COOLDOWN_DAYS IMAGE_NAME DOCKERFILE_PATH
 BUILD_CONTEXT PRIVATE_REGISTRY IAC_PATH DAST_MODE DAST_TARGET_URL PORT_MAPPING DAST_HEALTHCHECK_PATH
 DAST_ON_PULL_REQUEST DAST_AUTH_HEADER DEFAULT_OWNERS SECURITY_OWNERS SECURITY_CONTACT_EMAIL
 SUPPORTED_VERSION ACK_DELAY TRIAGE_DELAY FIX_DELAY_CRITICAL SCAN_SCHEDULE_CRON REPORT_RETENTION_DAYS
 KEEP_DOCUMENTATION "
# shellcheck disable=SC2086
KNOWN_KEYS=" $(printf '%s ' $KNOWN_KEYS)"
for k in $CFG_KEYS; do
  case "$KNOWN_KEYS" in *" $k "*) ;; *) warn "Clé inconnue ignorée dans $(basename "$CONFIG") : ${k}" ;; esac
done
# Une case supprimée par erreur équivaut à une case décochée : on le signale.
for k in $KNOWN_KEYS; do
  case "$k" in ENABLE_*|BLOCK_UNFIXED_VULNERABILITIES|DAST_ON_PULL_REQUEST|KEEP_DOCUMENTATION) ;; *) continue ;; esac
  case " $CFG_KEYS " in *" $k "*) ;; *) warn "${k} absent de $(basename "$CONFIG") : considéré comme désactivé." ;; esac
done

# Aucune valeur ne doit contenir de caractère cassant le YAML ou le shell.
for k in $CFG_KEYS; do
  v="$(cfg "$k")"
  # shellcheck disable=SC2016
  case "$v" in *\"*|*\`*|*'$('*) err "${k} : les caractères \" \` et \$( sont interdits." ;; esac
done

for k in ENABLE_SAST ENABLE_DEPENDENCY_REVIEW ENABLE_DEPENDABOT_UPDATES ENABLE_SECRETS_SCAN ENABLE_DOCKER \
         ENABLE_IAC ENABLE_DAST ENABLE_PRECOMMIT ENABLE_CODEOWNERS ENABLE_SECURITY_POLICY ENABLE_PR_TEMPLATE \
         ENABLE_DEPENDABOT_ALERTS ENABLE_DEPENDABOT_SECURITY_UPDATES ENABLE_SECRET_SCANNING \
         ENABLE_PUSH_PROTECTION ENABLE_PRIVATE_VULN_REPORTING ENABLE_CODE_SECURITY_LICENSE \
         ENABLE_BRANCH_RULESET BLOCK_UNFIXED_VULNERABILITIES DAST_ON_PULL_REQUEST KEEP_DOCUMENTATION; do
  case "$(cfg "$k" false)" in true|false) ;; *) err "${k} doit valoir true ou false." ;; esac
done

repo="$(cfg GITHUB_REPO)"
if [ -n "$repo" ] && ! printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
  err "GITHUB_REPO doit être au format owner/nom (valeur : ${repo})."
fi
[ -n "$(cfg DEFAULT_BRANCH)" ] || err "DEFAULT_BRANCH est vide."

for k in REQUIRED_APPROVALS DEPENDABOT_COOLDOWN_DAYS REPORT_RETENTION_DAYS; do
  printf '%s' "$(cfg "$k" 0)" | grep -Eq '^[0-9]+$' || err "${k} doit être un entier."
done

case "$(cfg FAIL_ON_SEVERITY high)" in low|medium|high|critical) ;; *)
  err "FAIL_ON_SEVERITY doit valoir low, medium, high ou critical." ;; esac
case "$(cfg CODEQL_BLOCK_SEVERITY high_or_higher)" in none|critical|high_or_higher|medium_or_higher|all) ;; *)
  err "CODEQL_BLOCK_SEVERITY doit valoir none, critical, high_or_higher, medium_or_higher ou all." ;; esac

cron="$(cfg SCAN_SCHEDULE_CRON "23 3 * * 1")"
[ "$(printf '%s' "$cron" | awk '{print NF}')" = "5" ] || err "SCAN_SCHEDULE_CRON doit comporter 5 champs (valeur : ${cron})."

if is_true ENABLE_SAST; then
  [ -n "$(cfg CODEQL_LANGUAGES)" ] || err "CODEQL_LANGUAGES est vide (ENABLE_SAST=true)."
  for lang in $(cfg CODEQL_LANGUAGES | tr ',' ' '); do
    case "$lang" in python|javascript-typescript|java-kotlin|csharp|go|ruby|c-cpp|rust|swift) ;;
      *) err "CODEQL_LANGUAGES : langage non supporté '${lang}'." ;; esac
  done
  case "$(cfg CODEQL_BUILD_MODE auto)" in auto|none|autobuild|manual) ;; *)
    err "CODEQL_BUILD_MODE doit valoir auto, none, autobuild ou manual." ;; esac
  if [ "$(cfg CODEQL_BUILD_MODE auto)" = "manual" ] && [ -z "$(cfg CODEQL_BUILD_COMMAND)" ]; then
    err "CODEQL_BUILD_COMMAND est obligatoire avec CODEQL_BUILD_MODE=manual."
  fi
  case "$(cfg CODEQL_QUERY_SUITE security-extended)" in default|security-extended|security-and-quality) ;; *)
    err "CODEQL_QUERY_SUITE doit valoir default, security-extended ou security-and-quality." ;; esac
fi

if is_true ENABLE_DEPENDABOT_UPDATES; then
  for m in $(cfg DEPENDENCY_MANIFESTS | tr ',' ' '); do
    printf '%s' "$m" | grep -Eq '^[a-z0-9-]+:/[A-Za-z0-9_./-]*$' \
      || err "DEPENDENCY_MANIFESTS : entrée invalide '${m}' (format ecosysteme:/dossier)."
  done
  case "$(cfg DEPENDABOT_INTERVAL weekly)" in daily|weekly|monthly) ;; *)
    err "DEPENDABOT_INTERVAL doit valoir daily, weekly ou monthly." ;; esac
fi

NEED_IMAGE=false
is_true ENABLE_DOCKER && NEED_IMAGE=true
if is_true ENABLE_DAST; then
  case "$(cfg DAST_MODE local)" in
    local)  NEED_IMAGE=true
            printf '%s' "$(cfg PORT_MAPPING)" | grep -Eq '^[0-9]+:[0-9]+$' \
              || err "PORT_MAPPING doit être au format hote:conteneur (ex : 8080:8080)." ;;
    remote) ;;
    *) err "DAST_MODE doit valoir local ou remote." ;;
  esac
  printf '%s' "$(cfg DAST_TARGET_URL)" | grep -Eq '^https?://[^/]+' \
    || err "DAST_TARGET_URL doit commencer par http:// ou https://."
fi
if $NEED_IMAGE; then
  printf '%s' "$(cfg IMAGE_NAME)" | grep -Eq '^[a-z0-9][a-z0-9._/-]*$' \
    || err "IMAGE_NAME doit être en minuscules (lettres, chiffres, . _ - /)."
  [ -n "$(cfg DOCKERFILE_PATH)" ] || err "DOCKERFILE_PATH est vide."
  [ -n "$(cfg BUILD_CONTEXT)" ]   || err "BUILD_CONTEXT est vide."
  df="${DEST}/$(cfg DOCKERFILE_PATH)"
  [ -f "$df" ] || warn "Dockerfile introuvable dans le projet : $(cfg DOCKERFILE_PATH)"
fi
is_true ENABLE_IAC && { [ -n "$(cfg IAC_PATH)" ] || err "IAC_PATH est vide."; }

check_owners() {
  local key="$1" o
  [ -n "$(cfg "$key")" ] || { err "${key} est vide (ENABLE_CODEOWNERS=true)."; return; }
  for o in $(cfg "$key"); do
    case "$o" in @*|*@*.*) ;; *) err "${key} : '${o}' doit être @utilisateur, @org/equipe ou un e-mail." ;; esac
  done
}
if is_true ENABLE_CODEOWNERS; then check_owners DEFAULT_OWNERS; check_owners SECURITY_OWNERS; fi
if is_true ENABLE_SECURITY_POLICY; then
  [ -n "$(cfg SECURITY_CONTACT_EMAIL)" ] || err "SECURITY_CONTACT_EMAIL est vide (ENABLE_SECURITY_POLICY=true)."
fi

[ "$ERRORS" -eq 0 ] || die "${ERRORS} erreur(s) dans ${CONFIG}. Corrigez puis relancez."
ok "Configuration valide"

# =============================================================================
#  2. Valeurs dérivées et blocs conditionnels
# =============================================================================
case "$(cfg FAIL_ON_SEVERITY high)" in
  low)      TRIVY_SEVERITIES="LOW,MEDIUM,HIGH,CRITICAL"; DR_SEVERITY=low ;;
  medium)   TRIVY_SEVERITIES="MEDIUM,HIGH,CRITICAL";     DR_SEVERITY=moderate ;;
  high)     TRIVY_SEVERITIES="HIGH,CRITICAL";            DR_SEVERITY=high ;;
  critical) TRIVY_SEVERITIES="CRITICAL";                 DR_SEVERITY=critical ;;
esac
if is_true BLOCK_UNFIXED_VULNERABILITIES; then IGNORE_UNFIXED=false; else IGNORE_UNFIXED=true; fi

dockerfile_dir="$(dirname "$(cfg DOCKERFILE_PATH ./Dockerfile)")"
dockerfile_dir="${dockerfile_dir#.}"; dockerfile_dir="/${dockerfile_dir#/}"
target_host="$(cfg DAST_TARGET_URL | sed -E 's#^https?://([^/]+).*#\1#')"

# Valeur de chaque placeholder <<CLE>>.
placeholder_value() {
  case "$1" in
    TRIVY_SEVERITIES)           printf '%s' "$TRIVY_SEVERITIES" ;;
    DEPENDENCY_REVIEW_SEVERITY) printf '%s' "$DR_SEVERITY" ;;
    TRIVY_IGNORE_UNFIXED)       printf '%s' "$IGNORE_UNFIXED" ;;
    DOCKERFILE_DIR)             printf '%s' "$dockerfile_dir" ;;
    DAST_TARGET_HOST)           printf '%s' "$target_host" ;;
    DENY_LICENSES)              cfg DENY_LICENSES | sed 's/[[:space:]]*,[[:space:]]*/, /g' ;;
    SCAN_SCHEDULE_CRON)         cfg SCAN_SCHEDULE_CRON "23 3 * * 1" ;;
    REPORT_RETENTION_DAYS)      cfg REPORT_RETENTION_DAYS 30 ;;
    DEPENDABOT_INTERVAL)        cfg DEPENDABOT_INTERVAL weekly ;;
    DEPENDABOT_COOLDOWN_DAYS)   cfg DEPENDABOT_COOLDOWN_DAYS 7 ;;
    CODEQL_QUERY_SUITE)         cfg CODEQL_QUERY_SUITE security-extended ;;
    DAST_HEALTHCHECK_PATH)      cfg DAST_HEALTHCHECK_PATH / ;;
    *)                          cfg "$1" ;;
  esac
}

FLAGS=","
flag() { FLAGS="${FLAGS}$1,"; }
[ "$(cfg CODEQL_BUILD_MODE auto)" = "manual" ]               && flag CODEQL_MANUAL_BUILD
[ "$(cfg CODEQL_QUERY_SUITE security-extended)" != "default" ] && flag CODEQL_EXTRA_QUERIES
[ -n "$(cfg DENY_LICENSES)" ]                               && flag DENY_LICENSES
[ -n "$(cfg PRIVATE_REGISTRY)" ]                            && flag PRIVATE_REGISTRY
is_true ENABLE_DOCKER                                       && flag DOCKER
is_true ENABLE_DAST                                         && flag DAST
is_true DAST_ON_PULL_REQUEST                                && flag DAST_ON_PR
[ "$(cfg DAST_MODE local)" = "local" ]                      && flag DAST_LOCAL
[ "$(cfg DAST_MODE local)" = "local" ] && [ -n "$(cfg PRIVATE_REGISTRY)" ] && flag DAST_REGISTRY
[ -n "$(cfg DAST_AUTH_HEADER)" ]                            && flag DAST_AUTH
{ is_true ENABLE_DOCKER || is_true ENABLE_IAC; }            && flag TRIVY_FILES
{ is_true ENABLE_SECRETS_SCAN || is_true ENABLE_PRECOMMIT; } && flag GITLEAKS_FILES
is_true ENABLE_PRECOMMIT                                    && flag PRECOMMIT
is_true ENABLE_SECURITY_POLICY                              && flag SECURITY_POLICY

# Blocs générés.
GEN_DIR="$(mktemp -d)"
trap 'rm -rf "$GEN_DIR"' EXIT

# Langages interprétés : toujours "none". Langages compilés : mode choisi,
# ou en "auto" : "none" quand CodeQL sait analyser sans compiler, sinon "autobuild".
codeql_mode() {
  local lang="$1" mode
  mode="$(cfg CODEQL_BUILD_MODE auto)"
  case "$lang" in python|javascript-typescript|ruby) printf 'none'; return ;; esac
  if [ "$mode" = "auto" ]; then
    case "$lang" in go|c-cpp|swift) mode=autobuild ;; *) mode=none ;; esac
  fi
  printf '%s' "$mode"
}
{
  for lang in $(cfg CODEQL_LANGUAGES | tr ',' ' '); do
    runner=ubuntu-latest; [ "$lang" = "swift" ] && runner=macos-latest
    printf '          - language: %s\n            build-mode: %s\n            runner: %s\n' \
      "$lang" "$(codeql_mode "$lang")" "$runner"
  done
} > "${GEN_DIR}/CODEQL_MATRIX"

{
  i=0
  for m in $(cfg DEPENDENCY_MANIFESTS | tr ',' ' '); do
    i=$((i + 1))
    [ "$i" -gt 1 ] && echo
    cat <<EOF
  - package-ecosystem: "${m%%:*}"
    directory: "${m#*:}"
    schedule:
      interval: "$(cfg DEPENDABOT_INTERVAL weekly)"
    cooldown:
      default-days: $(cfg DEPENDABOT_COOLDOWN_DAYS 7)
    open-pull-requests-limit: 10
    groups:
      # Corrections de sécurité regroupées dans une PR distincte, prioritaire.
      security-${i}:
        applies-to: security-updates
        patterns: ["*"]
      # Montées de version mineures/correctives regroupées pour limiter le bruit.
      minor-and-patch-${i}:
        applies-to: version-updates
        update-types: ["minor", "patch"]
    labels: ["dependencies"]
EOF
  done
} > "${GEN_DIR}/DEPENDABOT_MANIFESTS"

# Applique les blocs ">>> IF:X" / ">>> GEN:X" d'un fichier.
render_blocks() {
  awk -v flags="$FLAGS" -v gendir="$GEN_DIR" '
    /^[[:space:]]*# >>> (IF|GEN):[A-Z_]+[[:space:]]*$/ {
      tag = $0; sub(/^.*# >>> /, "", tag); sub(/[[:space:]]*$/, "", tag)
      kind = substr(tag, 1, index(tag, ":") - 1); name = substr(tag, index(tag, ":") + 1)
      inblock = 1
      if (kind == "IF") { keep = (index(flags, "," name ",") > 0) }
      else {
        keep = 0; f = gendir "/" name
        while ((getline line < f) > 0) print line
        close(f)
      }
      next
    }
    /^[[:space:]]*# <<< (IF|GEN):[A-Z_]+[[:space:]]*$/ { inblock = 0; next }
    { if (!inblock || keep) print }
  ' "$1"
}

# Remplace les placeholders <<CLE>> d'un fichier.
render_placeholders() {
  local file="$1" keys k v esc script=""
  keys="$(grep -oE '<<[A-Z0-9_]+>>' "$file" | sort -u | tr -d '<>' || true)"
  for k in $keys; do
    v="$(placeholder_value "$k")"
    esc="$(printf '%s' "$v" | sed -e 's/[\\&|]/\\&/g')"
    script="${script}s|<<${k}>>|${esc}|g;"
  done
  if [ -n "$script" ]; then sed -e "$script" "$file"; else cat "$file"; fi
}

# =============================================================================
#  3. Génération des fichiers dans le projet
# =============================================================================
if [ "$DEST" = "$TEMPLATE_ROOT" ]; then
  title "Génération des fichiers (sur place)"
else
  title "Génération des fichiers dans ${DEST}"
fi

# chemin|fonction requise
MANIFEST="
.github/workflows/codeql.yml|SAST
.github/codeql/codeql-config.yml|SAST
.github/workflows/dependency-review.yml|DEPENDENCY_REVIEW
.github/dependabot.yml|DEPENDABOT_UPDATES
.github/workflows/secrets-scan.yml|SECRETS_SCAN
.gitleaks.toml|GITLEAKS_FILES
.github/workflows/container-scan.yml|DOCKER
.github/workflows/iac-scan.yml|IAC
.trivyignore|TRIVY_FILES
.github/workflows/dast-zap.yml|DAST
.zap/rules.tsv|DAST
.pre-commit-config.yaml|PRECOMMIT
.github/CODEOWNERS|CODEOWNERS
SECURITY.md|SECURITY_POLICY
.github/pull_request_template.md|PR_TEMPLATE
"

feature_on() {
  case "$1" in
    GITLEAKS_FILES) is_true ENABLE_SECRETS_SCAN || is_true ENABLE_PRECOMMIT ;;
    TRIVY_FILES)    is_true ENABLE_DOCKER || is_true ENABLE_IAC ;;
    *)              is_true "ENABLE_$1" ;;
  esac
}

# Fichiers d'exceptions : générés une seule fois, jamais écrasés ensuite
# (ils contiennent les exceptions ajoutées par l'équipe).
preserve_existing() {
  case "$1" in .trivyignore|.gitleaks.toml|.zap/rules.tsv) return 0 ;; *) return 1 ;; esac
}

is_ours() { grep -q 'security-template:' "$1" 2>/dev/null; }

# Contrôle préalable : aucun fichier existant du projet n'est écrasé sans --force.
CONFLICTS=0
while IFS='|' read -r path feature; do
  [ -z "$path" ] && continue
  dst="${DEST}/${path}"
  if feature_on "$feature" && [ -e "$dst" ] && ! is_ours "$dst" && ! $FORCE; then
    fail "Fichier déjà présent dans le projet : ${path}"
    CONFLICTS=$((CONFLICTS + 1))
  fi
done <<< "$MANIFEST"
if [ "$CONFLICTS" -gt 0 ]; then
  info "Fusionnez ces fichiers manuellement (renommez-les puis relancez), ou relancez avec"
  info "--force pour les remplacer. Aucun fichier n'a été modifié."
  exit 1
fi

GENERATED=()
while IFS='|' read -r path feature; do
  [ -z "$path" ] && continue
  src="${SRC}/${path}"; dst="${DEST}/${path}"
  if feature_on "$feature"; then
    if [ -e "$dst" ] && is_ours "$dst" && preserve_existing "$path"; then
      info "conservé  ${path} (contient vos exceptions)"
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    tmp="${GEN_DIR}/render.tmp"
    render_blocks "$src" > "$tmp"
    render_placeholders "$tmp" > "$dst"
    GENERATED+=("$path")
    ok "$path"
  elif [ -e "$dst" ]; then
    if is_ours "$dst"; then
      rm -f "$dst"
      info "supprimé  ${path} (fonction désactivée)"
      rmdir -p "$(dirname "$dst")" 2>/dev/null || true
    fi
  fi
done <<< "$MANIFEST"

# Contrôle final : aucun placeholder ne doit rester.
remaining=""
for p in "${GENERATED[@]}"; do
  r="$(grep -nE '<<[A-Z0-9_]+>>' "${DEST}/${p}" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
  [ -n "$r" ] && remaining="${remaining}${p}: ${r}"$'\n'
done
[ -z "$remaining" ] || die "Placeholders non remplacés :"$'\n'"${remaining}"

# Protection du fichier de secrets.
if [ "$DEST" = "$TEMPLATE_ROOT" ]; then
  gi="${DEST}/.gitignore"
  grep -qxF '.env' "$gi" 2>/dev/null || printf '\n# Secrets locaux : ne jamais commiter\n.env\n' >> "$gi"
fi
if [ -f "$ENV_PATH" ] && git_tracked "$ENV_PATH"; then
  die "${ENV_PATH} est suivi par Git : retirez-le (git rm --cached .env) et révoquez les secrets qu'il contient."
fi

# =============================================================================
#  4. Réglages GitHub (secrets + fonctions de sécurité)
# =============================================================================
if $LOCAL_ONLY || [ -z "$repo" ]; then
  title "Réglages GitHub"
  if $LOCAL_ONLY; then info "ignorés (--local-only)"; else info "ignorés (GITHUB_REPO vide dans la configuration)"; fi
else
  title "Secrets GitHub Actions (${repo})"
  gh_ready; rc=$?
  if [ "$rc" -ne 0 ]; then
    [ "$rc" -eq 1 ] && warn "GitHub CLI (gh) introuvable : https://cli.github.com"
    [ "$rc" -eq 2 ] && warn "GitHub CLI non authentifié : lancez 'gh auth login' ou renseignez GH_TOKEN dans .env"
    die "Fichiers générés, mais réglages GitHub non appliqués. Relancez setup.sh une fois gh prêt."
  fi

  existing_secrets="$(gh secret list --repo "$repo" --json name --jq '.[].name' 2>/dev/null || true)"
  push_secret() {
    local name="$1" value
    value="$(envv "$name")"
    if [ -n "$value" ]; then
      if printf '%s' "$value" | gh secret set "$name" --repo "$repo" >/dev/null 2>&1; then
        ok "secret ${name} envoyé"
      else
        fail "échec de l'envoi du secret ${name}"
      fi
    elif printf '%s\n' "$existing_secrets" | grep -qxF "$name"; then
      info "secret ${name} déjà présent dans GitHub (conservé)"
    else
      warn "secret ${name} absent : renseignez-le dans .env puis relancez setup.sh"
    fi
  }
  needed=0
  if [ -n "$(cfg PRIVATE_REGISTRY)" ] && { is_true ENABLE_DOCKER || { is_true ENABLE_DAST && [ "$(cfg DAST_MODE local)" = "local" ]; }; }; then
    push_secret REGISTRY_USERNAME; push_secret REGISTRY_PASSWORD; needed=1
  fi
  if is_true ENABLE_DAST && [ -n "$(cfg DAST_AUTH_HEADER)" ]; then
    push_secret DAST_AUTH_HEADER_VALUE; needed=1
  fi
  [ "$needed" -eq 1 ] || info "aucun secret requis par la configuration"

  bash "$(dirname "$0")/enable-security.sh" --config "$CONFIG" --env "$ENV_PATH" \
    --workflows-dir "${DEST}/.github/workflows" --skip-ruleset || warn "Certaines étapes ont échoué (voir le bilan ci-dessus)."
fi

# =============================================================================
#  5. Suite
# =============================================================================
title "Terminé"
echo "Fichiers générés : ${#GENERATED[@]}"
cat <<EOF

Étapes suivantes :
  1. Dans ${DEST} :
       git checkout -b activation-securite
       git add -A && git commit -m "Activation des scans de sécurité"
       git push -u origin activation-securite
  2. Ouvrez la PR : les scans s'exécutent dessus. Corrigez ou justifiez les
     alertes, puis mergez.
  3. Une fois la PR mergée et les premiers scans terminés sur la branche
     ${CFG_DEFAULT_BRANCH:-main} :
       bash scripts/finalize.sh${TARGET:+ --target ${TARGET}}
EOF
