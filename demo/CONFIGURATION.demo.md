# Configuration de la sécurité du projet (démo)

> Configuration de démonstration pour l'application vulnérable de `demo/`.
> Copie : `cp demo/CONFIGURATION.demo.md CONFIGURATION.md`, puis renseignez
> `GITHUB_REPO` et remplacez `@votre-compte` par votre compte GitHub.

C'est **le seul fichier à remplir** (les secrets éventuels vont dans `.env`).
Une fois rempli, lancez :

```bash
bash scripts/setup.sh
```

**Mode d'emploi**

- Case cochée `- [x]` = activé, case vide `- [ ]` = désactivé.
- Dans les tableaux, modifiez uniquement la colonne **Valeur**.
- Ne modifiez pas les noms entre `accents graves` : c'est ce que lit le script.
- Les sections d'une fonction décochée peuvent être ignorées.
- Modifier ce fichier puis relancer `setup.sh` met le projet à jour (ajout ou
  retrait des fichiers concernés).

---

## 1. Projet

| Paramètre | Valeur | Aide |
|---|---|---|
| `GITHUB_REPO` |  | Repo au format `owner/nom`. Vide = générer les fichiers sans toucher à GitHub |
| `DEFAULT_BRANCH` | main | Branche principale à protéger |

## 2. Scans et fichiers à installer

- [x] **Analyse du code source** (CodeQL) · `ENABLE_SAST` · licence *Code Security* sur repo privé
- [x] **Blocage des PR qui ajoutent une dépendance vulnérable** (Dependency Review) · `ENABLE_DEPENDENCY_REVIEW` · licence *Code Security* sur repo privé
- [x] **PR automatiques de mise à jour des dépendances** (Dependabot) · `ENABLE_DEPENDABOT_UPDATES`
- [x] **Détection de secrets dans l'historique Git** (Gitleaks) · `ENABLE_SECRETS_SCAN`
- [x] **Scan de l'image Docker** (Trivy) · `ENABLE_DOCKER` · le projet a un Dockerfile
- [x] **Scan de l'Infrastructure as Code** (Trivy) · `ENABLE_IAC` · Terraform, Kubernetes, Helm, Dockerfile...
- [x] **Scan dynamique de l'application** (OWASP ZAP) · `ENABLE_DAST` · le projet expose une interface HTTP
- [x] **Détection de secrets avant chaque commit** (pre-commit + Gitleaks) · `ENABLE_PRECOMMIT`
- [x] **Relecteurs obligatoires par zone du code** (CODEOWNERS) · `ENABLE_CODEOWNERS`
- [x] **Politique de signalement des vulnérabilités** (SECURITY.md) · `ENABLE_SECURITY_POLICY`
- [x] **Modèle de PR avec checklist sécurité** · `ENABLE_PR_TEMPLATE`

## 3. Réglages GitHub

Appliqués automatiquement si `GITHUB_REPO` est renseigné.

- [x] **Alertes Dependabot** sur les dépendances vulnérables · `ENABLE_DEPENDABOT_ALERTS` · gratuit
- [x] **PR automatiques de correction** des dépendances vulnérables · `ENABLE_DEPENDABOT_SECURITY_UPDATES` · gratuit
- [x] **Secret scanning** (détection des secrets par GitHub) · `ENABLE_SECRET_SCANNING` · licence *Secret Protection* sur repo privé
- [x] **Push protection** (refus d'un push contenant un secret) · `ENABLE_PUSH_PROTECTION` · même licence
- [x] **Signalement privé de vulnérabilités** · `ENABLE_PRIVATE_VULN_REPORTING` · repos publics uniquement
- [ ] **Activer la licence payante Code Security** sur un repo privé · `ENABLE_CODE_SECURITY_LICENSE` · à valider avec l'admin de l'organisation
- [x] **Protection de la branche principale** (ruleset) · `ENABLE_BRANCH_RULESET` · appliquée par `finalize.sh`

| Paramètre | Valeur | Aide |
|---|---|---|
| `REQUIRED_APPROVALS` | 0 | Approbations exigées avant merge. `0` pour un projet solo |

## 4. Seuils de blocage

| Paramètre | Valeur | Aide |
|---|---|---|
| `FAIL_ON_SEVERITY` | high | Gravité qui bloque une PR (dépendances, image, IaC) : `low` · `medium` · `high` · `critical` |
| `CODEQL_BLOCK_SEVERITY` | high_or_higher | Gravité CodeQL qui bloque le merge : `critical` · `high_or_higher` · `medium_or_higher` · `all` |
| `DENY_LICENSES` |  | Licences de dépendances interdites, séparées par des virgules. Ex : `AGPL-3.0-only,GPL-3.0-only` |

- [ ] **Bloquer aussi les failles sans correctif disponible** · `BLOCK_UNFIXED_VULNERABILITIES` · décoché recommandé

## 5. Analyse du code (si CodeQL coché)

| Paramètre | Valeur | Aide |
|---|---|---|
| `CODEQL_LANGUAGES` | python | Séparés par des virgules : `python` · `javascript-typescript` · `java-kotlin` · `csharp` · `go` · `ruby` · `c-cpp` · `rust` · `swift` |
| `CODEQL_BUILD_MODE` | auto | Langages compilés : `auto` (recommandé) · `none` · `autobuild` · `manual` |
| `CODEQL_BUILD_COMMAND` |  | Seulement si `manual`. Ex : `mvn -B -DskipTests package` |
| `CODEQL_QUERY_SUITE` | security-extended | `default` · `security-extended` (recommandé) · `security-and-quality` |

## 6. Dépendances (si Dependabot coché)

| Paramètre | Valeur | Aide |
|---|---|---|
| `DEPENDENCY_MANIFESTS` | pip:/demo/app | `ecosysteme:/dossier`, séparés par des virgules. Ex : `pip:/,npm:/frontend`. Les actions GitHub et Docker sont ajoutées automatiquement |
| `DEPENDABOT_INTERVAL` | weekly | `daily` · `weekly` · `monthly` |
| `DEPENDABOT_COOLDOWN_DAYS` | 7 | Jours d'attente avant de proposer une nouvelle version |

## 7. Docker (si Docker ou DAST coché)

| Paramètre | Valeur | Aide |
|---|---|---|
| `IMAGE_NAME` | demo-app | Nom local de l'image, en minuscules |
| `DOCKERFILE_PATH` | ./demo/Dockerfile | Chemin depuis la racine du repo |
| `BUILD_CONTEXT` | ./demo | Contexte de build |
| `PRIVATE_REGISTRY` |  | Registre privé de l'image de base (ex : `ghcr.io`). Identifiants dans `.env` |

## 8. Infrastructure as Code (si IaC coché)

| Paramètre | Valeur | Aide |
|---|---|---|
| `IAC_PATH` | ./demo | Dossier analysé. `.` = tout le repo. Ex : `./infra` |

## 9. Scan dynamique (si DAST coché)

| Paramètre | Valeur | Aide |
|---|---|---|
| `DAST_MODE` | local | `local` : l'image est lancée sur le runner · `remote` : environnement de recette déjà déployé |
| `DAST_TARGET_URL` | http://localhost:8080 | URL ciblée. Jamais la production sans accord |
| `PORT_MAPPING` | 8080:8080 | Mode local : ports `hote:conteneur` |
| `DAST_HEALTHCHECK_PATH` | / | Chemin utilisé pour vérifier que l'application répond |
| `DAST_AUTH_HEADER` |  | En-tête d'authentification (ex : `Authorization`). Le token va dans `.env` |

- [ ] **Lancer aussi le DAST sur chaque PR** (plus lent) · `DAST_ON_PULL_REQUEST`

## 10. Relecteurs (si CODEOWNERS coché)

| Paramètre | Valeur | Aide |
|---|---|---|
| `DEFAULT_OWNERS` | @votre-compte | Relecteurs de tout le code : `@utilisateur` ou `@org/equipe`, séparés par des espaces |
| `SECURITY_OWNERS` | @votre-compte | Relecteurs obligatoires des fichiers de sécurité |

## 11. Politique de sécurité (si SECURITY.md coché)

| Paramètre | Valeur | Aide |
|---|---|---|
| `SECURITY_CONTACT_EMAIL` | securite@example.com | Adresse de signalement |
| `SUPPORTED_VERSION` | 1.x | Version maintenue |
| `ACK_DELAY` | 2 jours ouvrés | Délai d'accusé de réception |
| `TRIAGE_DELAY` | 5 jours ouvrés | Délai d'analyse |
| `FIX_DELAY_CRITICAL` | 30 jours | Délai de correction d'une faille critique |

## 12. Planification et rapports

| Paramètre | Valeur | Aide |
|---|---|---|
| `SCAN_SCHEDULE_CRON` | 23 3 * * 1 | Scans récurrents, format cron, heure UTC (défaut : lundi 03:23) |
| `REPORT_RETENTION_DAYS` | 30 | Conservation des rapports en artefacts (jours) |

## 13. Finalisation

- [x] **Conserver la documentation après nettoyage** · `KEEP_DOCUMENTATION` · le README est conservé sous le nom `SECURITE-CICD.md`
