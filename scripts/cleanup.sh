#!/usr/bin/env bash
# =============================================================================
#  cleanup.sh - Supprime les fichiers du template devenus inutiles
# -----------------------------------------------------------------------------
#  À utiliser quand le template a été appliqué sur place (nouveau projet créé
#  avec "Use this template"), une fois la sécurité en place. Appelé par
#  finalize.sh, utilisable seul.
#
#  Supprimés : template/ (sources), scripts/, demo/ (sauf s'il est le projet
#              analysé), CONFIGURATION.md, .env.example, .env et le README.md
#              du template (renommé SECURITE-CICD.md avec --keep-docs).
#  Conservés : les fichiers générés (.github/, SECURITY.md, fichiers
#              d'exceptions...) et le reste du projet.
#
#  Usage : bash scripts/cleanup.sh [--keep-docs] [--yes] [--dry-run]
# =============================================================================

set -uo pipefail
# shellcheck source=scripts/lib/common.sh
. "$(dirname "$0")/lib/common.sh"

main() {
  local keep_docs=false yes=false dry=false answer item
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep-docs) keep_docs=true; shift ;;
      --yes|-y)    yes=true; shift ;;
      --dry-run)   dry=true; shift ;;
      -h|--help)   sed -n '2,15p' "$0" | sed 's/^# \{0,2\}//'; return 0 ;;
      *) fail "Option inconnue : $1"; return 2 ;;
    esac
  done

  cd "$TEMPLATE_ROOT" || return 1

  # Garde-fou : la sécurité doit avoir été générée avant de supprimer les sources.
  if [ ! -d .github/workflows ] || ! grep -rqs 'security-template:' .github; then
    fail "Aucun fichier généré trouvé dans .github/ : lancez d'abord scripts/setup.sh."
    return 1
  fi

  local items=(template scripts CONFIGURATION.md security.conf .env.example .env)
  local readme=false
  # demo/ est conservé s'il est le projet analysé (scénario de démonstration).
  if grep -rqs -- './demo' .github/workflows; then
    info "demo/ conservé : les workflows générés l'utilisent."
  else
    items+=(demo)
  fi
  # README.md du template uniquement (pas celui du projet s'il a été remplacé).
  if [ -f README.md ] && head -1 README.md | grep -q "Template de sécurité CI/CD"; then
    readme=true
    $keep_docs || items+=(README.md)
  fi

  local present=()
  for item in "${items[@]}"; do [ -e "$item" ] && present+=("$item"); done
  if [ "${#present[@]}" -eq 0 ] && ! { $readme && $keep_docs; }; then
    ok "Rien à supprimer."
    return 0
  fi

  title "Nettoyage du template"
  echo "Éléments supprimés :"
  printf '  - %s\n' "${present[@]}"
  if $readme && $keep_docs; then echo "Renommé : README.md -> SECURITE-CICD.md (documentation conservée)"; fi
  echo "Conservés : .github/ et les fichiers de sécurité générés."

  if $dry; then info "simulation (--dry-run) : rien n'a été supprimé"; return 0; fi
  if ! $yes; then
    printf '\nConfirmer la suppression ? [o/N] '
    read -r answer
    case "$answer" in o|O|oui|y|Y|yes) ;; *) info "annulé"; return 0 ;; esac
  fi

  for item in "${present[@]}"; do rm -rf -- "$item"; done
  if $readme && $keep_docs; then mv README.md SECURITE-CICD.md; fi
  ok "Template nettoyé"
  cat <<'EOF'

Pensez à commiter ce nettoyage (via une PR, la branche principale étant protégée) :
  git checkout -b nettoyage-template
  git add -A && git commit -m "Suppression des fichiers du template de sécurité"
  git push -u origin nettoyage-template

Les réglages se modifient désormais directement dans les fichiers générés
(.github/workflows/*.yml, .github/dependabot.yml, .github/CODEOWNERS...).
EOF
}

# Le script se supprime lui-même : tout le code est dans main(), entièrement
# lu par bash avant l'exécution.
main "$@"; exit $?
