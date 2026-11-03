# Template de sécurité CI/CD pour GitHub

Kit prêt à l'emploi pour ajouter les scans de sécurité aux pipelines GitHub
d'un projet. Tout se règle dans **un fichier à cases à cocher**
(`CONFIGURATION.md`) et s'installe avec **une commande**.

| Fichier | Rôle | Commité ? |
|---|---|---|
| `CONFIGURATION.md` | Cases à cocher (fonctions activées ou non) et valeurs du projet | Non : supprimé à la finalisation |
| `.env` | Secrets éventuels (jeton GitHub, registre privé, token DAST) | **Jamais** |

| Commande | Rôle |
|---|---|
| `bash scripts/setup.sh` | Génère les fichiers des fonctions cochées, envoie les secrets, active les réglages GitHub |
| `bash scripts/finalize.sh` | Après le merge : protège la branche principale puis supprime le template |

Durée indicative : 15 minutes.

**Sommaire**

1. [Comment ça marche](#1-comment-ça-marche)
2. [Démarrage rapide](#2-démarrage-rapide)
3. [Ce que couvre le template](#3-ce-que-couvre-le-template)
4. [Les workflows](#4-les-workflows)
5. [Quand les scans s'exécutent](#5-quand-les-scans-sexécutent)
6. [Réglages GitHub et licences](#6-réglages-github-et-licences)
7. [Exceptions et faux positifs](#7-exceptions-et-faux-positifs)
8. [Démo et formation](#8-démo-et-formation)
9. [Référence des scripts](#9-référence-des-scripts)
10. [Dépannage](#10-dépannage)
11. [Limites](#11-limites)

---

## 1. Comment ça marche

```
 CONFIGURATION.md          scripts/setup.sh                 Projet
 ────────────────          ────────────────                 ──────
 - [x] CodeQL       ──►    lit les cases           ──►      .github/workflows/codeql.yml
 - [ ] DAST                et les valeurs                   (pas de dast-zap.yml)
 | branche | main |        remplit les modèles              valeurs du projet insérées
                           de template/                     + réglages GitHub activés
```

1. **Vous cochez** dans `CONFIGURATION.md` ce que vous voulez (`- [x]`) et
   décochez le reste (`- [ ]`). Dans les tableaux, vous remplissez la colonne
   *Valeur* (branche, langages, Dockerfile...).
2. **`setup.sh` lit ce fichier.** Il ne regarde que deux choses : les lignes
   à case à cocher et les lignes de tableau commençant par un nom entre
   accents graves (`` `ENABLE_SAST` ``). Tout le reste (titres, explications)
   est ignoré, vous pouvez donc annoter le fichier librement.
3. **Pour chaque case cochée**, le script copie le fichier correspondant
   depuis `template/` dans le projet et y insère vos valeurs. **Pour chaque
   case décochée**, rien n'est copié (et le fichier est retiré s'il avait été
   généré auparavant).
4. **Pour les réglages GitHub** (section 3 du fichier), le script appelle
   l'API GitHub pour activer ou non chaque option du repo.

Changer d'avis = cocher/décocher puis relancer `setup.sh`. Le fichier n'est
jamais exécuté, seulement lu : une erreur de saisie ne peut pas lancer de
commande, et le script explique chaque valeur invalide avant de modifier quoi
que ce soit.

| Case | Fichiers générés si cochée |
|---|---|
| `ENABLE_SAST` | `.github/workflows/codeql.yml`, `.github/codeql/codeql-config.yml` |
| `ENABLE_DEPENDENCY_REVIEW` | `.github/workflows/dependency-review.yml` |
| `ENABLE_DEPENDABOT_UPDATES` | `.github/dependabot.yml` |
| `ENABLE_SECRETS_SCAN` | `.github/workflows/secrets-scan.yml`, `.gitleaks.toml` |
| `ENABLE_DOCKER` | `.github/workflows/container-scan.yml`, `.trivyignore` |
| `ENABLE_IAC` | `.github/workflows/iac-scan.yml`, `.trivyignore` |
| `ENABLE_DAST` | `.github/workflows/dast-zap.yml`, `.zap/rules.tsv` |
| `ENABLE_PRECOMMIT` | `.pre-commit-config.yaml`, `.gitleaks.toml` |
| `ENABLE_CODEOWNERS` | `.github/CODEOWNERS` |
| `ENABLE_SECURITY_POLICY` | `SECURITY.md` |
| `ENABLE_PR_TEMPLATE` | `.github/pull_request_template.md` |

---

## 2. Démarrage rapide

### Prérequis

| Élément | Pourquoi |
|---|---|
| Bash : Linux, macOS, **Git Bash** ou WSL sous Windows | Exécution des scripts |
| [GitHub CLI](https://cli.github.com), connecté (`gh auth login` ou `GH_TOKEN` dans `.env`) | Secrets, réglages, ruleset |
| Droits **admin** sur le repo | Modifier les réglages de sécurité |
| Licences si repo privé | Voir [section 6](#6-réglages-github-et-licences) |

Sans GitHub CLI : `bash scripts/setup.sh --local-only` génère les fichiers,
les réglages se font alors à la main (section 6).

### Cas 1 - Nouveau projet

Le template devient le repo du projet.

1. Sur GitHub : **Use this template** > **Create a new repository**, puis
   clonez-le. (Préférez-le à un *fork* : un fork reste lié au repo d'origine et
   a plusieurs fonctions de sécurité désactivées.)
2. Remplissez `CONFIGURATION.md`. Si le projet a des secrets à fournir :
   `cp .env.example .env` et remplissez-le.
3. Générez et activez :

   ```bash
   bash scripts/setup.sh
   ```

4. Ouvrez la PR d'activation :

   ```bash
   git checkout -b activation-securite
   git add -A && git commit -m "Activation des scans de sécurité"
   git push -u origin activation-securite
   ```

   Les scans tournent sur la PR et donnent un premier état des lieux. Mergez.
5. Attendez la fin des workflows sur la branche principale (onglet *Actions*,
   surtout « SAST - CodeQL »), puis :

   ```bash
   bash scripts/finalize.sh
   ```

   Il active la protection de la branche, puis supprime après confirmation
   les fichiers du template (`template/`, `scripts/`, `demo/`,
   `CONFIGURATION.md`, `.env`, ce README). Commitez ce nettoyage via une PR.

### Cas 2 - Projet existant

Le template reste dans un dossier à part, seuls les fichiers utiles sont
copiés dans le projet.

```bash
git clone https://github.com/<owner>/<template>.git security-template
# mon-projet/  et  security-template/  côte à côte
```

1. Dans `security-template/`, remplissez `CONFIGURATION.md` (et `.env` si
   besoin). Les chemins sont relatifs à la **racine du projet**.
2. Générez dans le projet :

   ```bash
   cd security-template
   bash scripts/setup.sh --target ../mon-projet
   ```

   Si le projet a déjà un fichier du même nom (ex : `.github/CODEOWNERS`), le
   script s'arrête **avant toute modification**. Renommez le fichier existant
   puis relancez (et fusionnez à la main), ou relancez avec `--force`.
3. Ouvrez la PR d'activation dans le projet (mêmes commandes que le cas 1).
   Sur du code ancien, attendez-vous à des alertes : corrigez, justifiez
   (section 7), ou démarrez avec `FAIL_ON_SEVERITY` à `critical`, puis durcissez.
4. Une fois mergée et les workflows terminés :

   ```bash
   bash scripts/finalize.sh --target ../mon-projet
   ```

   Supprimez ensuite `security-template/` (il contient `.env`).

### Secrets (`.env`)

| Clé | Usage | Envoyée dans GitHub ? |
|---|---|---|
| `GH_TOKEN` | Authentification des scripts (alternative à `gh auth login`) | Non |
| `REGISTRY_USERNAME`, `REGISTRY_PASSWORD` | Image de base dans un registre privé | Oui, si `PRIVATE_REGISTRY` est renseigné |
| `DAST_AUTH_HEADER_VALUE` | Scan DAST authentifié | Oui, si DAST coché et `DAST_AUTH_HEADER` renseigné |

Une valeur vide n'est pas envoyée. Le script refuse de continuer si `.env` est
suivi par Git.

### Après la mise en place

| Vérification | Où |
|---|---|
| Fonctions activées | *Settings* > *Advanced Security* (ou *Code security*) |
| Ruleset actif | *Settings* > *Rules* > *Rulesets* |
| Alertes | Onglet *Security* |
| Blocage | Une PR qui ajoute une dépendance vulnérable doit échouer sur *SCA - Dependency Review* |

Hook pre-commit (si coché), une fois par poste : `pip install pre-commit && pre-commit install`.

Après la finalisation, les scripts n'existent plus : un réglage se modifie
directement dans le fichier généré (chaque fichier indique en en-tête les
clés dont il est issu).

---

## 3. Ce que couvre le template

Principe : contrôler **chaque modification**, **tôt** (dans la PR, en
quelques minutes), avec **les mêmes règles pour tous les projets**, et
**bloquer le merge** au-delà d'un seuil de risque.

| Risque | Exemple | Contrôle |
|---|---|---|
| Faille dans le code | Injection SQL, XSS, path traversal | **CodeQL** (SAST) |
| Dépendance vulnérable ajoutée | `PyYAML 5.3.1` (CVE-2020-14343) | **Dependency Review** |
| Dépendance devenue vulnérable | Nouvelle CVE sur une bibliothèque déjà utilisée | **Dependabot** |
| Secret committé | Clé d'API, token, mot de passe | **Push protection**, **secret scanning**, **Gitleaks** |
| Image Docker vulnérable | Image de base obsolète | **Trivy image** |
| Infrastructure mal configurée | Bucket S3 public, SSH ouvert, conteneur root | **Trivy config** (IaC) |
| Mauvaise config à l'exécution | En-têtes absents, cookie sans `HttpOnly` | **OWASP ZAP** (DAST) |
| Contournement des contrôles | Merge direct sur `main`, exception non revue | **Ruleset** + **CODEOWNERS** |
| Pipeline compromis | Action tierce modifiée par un attaquant | Actions **épinglées par SHA**, permissions minimales |

**Le pipeline est lui-même une cible.** En mars 2026, l'action
`aquasecurity/trivy-action` a été compromise (CVE-2026-33634) : ses tags ont
été réécrits pour exfiltrer les secrets des pipelines. Les projets qui
l'épinglaient par empreinte de commit n'ont pas été touchés. D'où, dans tous
les workflows du template : actions épinglées par SHA (mises à jour par
Dependabot après 7 jours), binaires vérifiés par empreinte, permissions
minimales, token Git non conservé, aucune interpolation de données
contrôlables par un tiers, analyse CodeQL des workflows, `.github/` protégé
par CODEOWNERS.

**Défense en profondeur** : aucun outil ne détecte tout, les contrôles se
superposent.

```
 Poste dev      Push           Pull Request           Branche principale    Planifié
 pre-commit  →  Push        →  CodeQL              →  CodeQL             →  CodeQL
 (Gitleaks)     protection     Dependency Review      Trivy image/IaC       Trivy image
                               Trivy image / IaC      Gitleaks (historique) Gitleaks
                               Gitleaks (commits PR)  ZAP baseline          ZAP, Dependabot
                               Revue CODEOWNERS
```

---

## 4. Les workflows

| Workflow | Case | Déclencheurs | Bloque si | Résultats |
|---|---|---|---|---|
| `codeql.yml` | `ENABLE_SAST` | PR, push, planifié, manuel | Alerte ≥ `CODEQL_BLOCK_SEVERITY` (via ruleset) | Security > Code scanning, annotations PR |
| `dependency-review.yml` | `ENABLE_DEPENDENCY_REVIEW` | PR | Dépendance **ajoutée/modifiée** vulnérable ≥ `FAIL_ON_SEVERITY`, ou licence interdite | Résumé du job, commentaire PR |
| `container-scan.yml` | `ENABLE_DOCKER` | PR, push, planifié, manuel | CVE ≥ `FAIL_ON_SEVERITY` **avec correctif** | Security (`container-image`), artefact |
| `iac-scan.yml` | `ENABLE_IAC` | PR, push, manuel | Mauvaise config ≥ `FAIL_ON_SEVERITY` | Security (`iac`), artefact |
| `secrets-scan.yml` | `ENABLE_SECRETS_SCAN` | PR, push, planifié, manuel | Tout secret | Security (`secrets`), artefact |
| `dast-zap.yml` | `ENABLE_DAST` | Push, planifié, manuel (+ PR si coché) | Règle `FAIL` de `.zap/rules.tsv` | Artefact (HTML, JSON, Markdown) |

Points à retenir :

- **CodeQL** analyse chaque langage de `CODEQL_LANGUAGES` plus les workflows
  eux-mêmes. Exclusions et règles : `.github/codeql/codeql-config.yml`.
- **Dependency Review** ne regarde que le **différentiel** : une PR n'est pas
  bloquée par une dette qu'elle n'a pas créée (la dette existante remonte en
  alerte Dependabot).
- **Trivy image** ignore par défaut les failles **sans correctif** dans le
  contrôle bloquant (non actionnables), mais elles restent dans le rapport.
- **Gitleaks** analyse les seuls commits de la PR, et tout l'historique sur
  la branche principale et en planifié. Les secrets sont masqués.
- **ZAP baseline** est **passif** (aucune attaque envoyée), sans risque pour
  l'environnement ciblé. Mode `local` : l'image tourne sur le runner ; mode
  `remote` : environnement de recette.

Conventions communes : `permissions: {}` puis droits par job, actions
épinglées par SHA, `persist-credentials: false`, `timeout-minutes`,
`concurrency` (un nouveau commit annule l'analyse obsolète), rapport SARIF
publié en `continue-on-error` (le pipeline fonctionne sans licence), rapport
archivé `REPORT_RETENTION_DAYS` jours.

**Interrupteur d'urgence** : la variable de repo `SECURITY_SCANS_ENABLED=false`
(*Settings* > *Secrets and variables* > *Actions* > *Variables*) suspend tous
les scans sans toucher aux fichiers.

**Lire les résultats** : checks de la PR, annotations dans *Files changed*,
onglet **Security** (Code scanning, Dependabot, Secret scanning), et rapports
bruts dans *Actions* > run > *Artifacts*. Une alerte corrigée se ferme
automatiquement à l'analyse suivante.

---

## 5. Quand les scans s'exécutent

| Moment | Outils | Bloquant | Intérêt | Limite |
|---|---|---|---|---|
| **IDE** | Extensions CodeQL, Semgrep, SonarQube for IDE, Trivy | Non | Retour pendant la frappe | Facultatif, par poste |
| **Commit** | pre-commit + Gitleaks | Oui (local) | Le secret n'entre jamais dans l'historique | Contournable (`--no-verify`) |
| **Push** | Push protection | Oui | Bloque côté serveur, pour tous | Formats de secrets connus |
| **Pull Request** | CodeQL, Dependency Review, Trivy, Gitleaks | Oui (ruleset) | Retour avant merge, là où le dev travaille | Ne voit que le différentiel |
| **Branche principale** | Tous, dont ZAP | Signale | Référence de l'onglet Security | Code déjà mergé |
| **Planifié** | CodeQL, Trivy, Gitleaks, ZAP, Dependabot | Signale | Détecte les **nouvelles** CVE sur du code inchangé | A posteriori |
| **Manuel** | Tous (*Actions* > *Run workflow*) | Selon workflow | Vérifier une correction | Manuel |

Le planifié est souvent oublié : **un code qui ne change pas peut devenir
vulnérable**. Horaire en UTC via `SCAN_SCHEDULE_CRON` (défaut lundi 03:23).
GitHub désactive les workflows planifiés d'un repo public inactif depuis 60
jours.

| Contexte | Réglage conseillé |
|---|---|
| Projet existant avec dette | `FAIL_ON_SEVERITY` à `critical` au départ, puis `high` |
| Projet critique, exposé sur Internet | Tout cocher, DAST sur chaque PR, `FAIL_ON_SEVERITY` à `medium`, 2 approbations |
| Monorepo | Une entrée `DEPENDENCY_MANIFESTS` par sous-projet |
| Bibliothèque sans déploiement | Décocher Docker, IaC et DAST |

> Attention aux filtres `paths` ajoutés à la main sur un workflow **exigé par
> le ruleset** : s'il ne s'exécute pas, la PR reste bloquée en attente du check.

---

## 6. Réglages GitHub et licences

Les workflows arrivent par une PR ; les fonctions ci-dessous sont des
**réglages du repo**, activés par `setup.sh` (et le ruleset par
`finalize.sh`) via l'API, ou à la main dans *Settings*.

| Fonction | Où dans *Settings* | Case | Repo privé |
|---|---|---|---|
| Alertes Dependabot + dependency graph | *Advanced Security* > *Dependabot alerts* | `ENABLE_DEPENDABOT_ALERTS` | Gratuit |
| Dependabot security updates | *Advanced Security* > *Dependabot security updates* | `ENABLE_DEPENDABOT_SECURITY_UPDATES` | Gratuit |
| Secret scanning | *Advanced Security* > *Secret Protection* | `ENABLE_SECRET_SCANNING` | Licence Secret Protection |
| Push protection | *Advanced Security* > *Push protection* | `ENABLE_PUSH_PROTECTION` | Licence Secret Protection |
| Signalement privé de vulnérabilités | *Advanced Security* > *Private vulnerability reporting* | `ENABLE_PRIVATE_VULN_REPORTING` | Repos publics uniquement |
| Licence Code Security | *Advanced Security* > *GitHub Code Security* | `ENABLE_CODE_SECURITY_LICENSE` | C'est la licence |
| Ruleset de branche | *Rules* > *Rulesets* | `ENABLE_BRANCH_RULESET` | Plan Team / Enterprise |

Le menu peut s'appeler *Code security* selon l'organisation.

### Licences

| Fonction | Repo public | Repo privé |
|---|---|---|
| Dependabot | Gratuit | Gratuit |
| CodeQL, Dependency Review | Gratuit | **GitHub Code Security** |
| Secret scanning + push protection | Gratuit | **GitHub Secret Protection** |
| Rulesets | Gratuit | Plan Team ou Enterprise |
| Trivy, Gitleaks, ZAP | Open source | Open source |

Sans licence sur un repo privé : décochez CodeQL et Dependency Review. Trivy,
Gitleaks et ZAP restent bloquants ; seul l'envoi vers l'onglet Security échoue
(sans casser le pipeline), les rapports restant en artefacts.

### Ruleset de la branche principale

Appliqué en dernier par `finalize.sh` : la règle CodeQL exige une analyse
existante sur la branche, activée trop tôt elle bloquerait la PR d'activation.

| Règle | Effet |
|---|---|
| `deletion`, `non_fast_forward` | Ni suppression de la branche, ni `push --force` |
| `pull_request` | Merge via PR, `REQUIRED_APPROVALS` approbation(s), revue CODEOWNERS, approbations invalidées par un nouveau commit, conversations résolues |
| `required_status_checks` | Les checks des workflows présents doivent réussir |
| `code_scanning` | Merge bloqué si alerte CodeQL ≥ `CODEQL_BLOCK_SEVERITY` |

Checks exigés : `SCA - Dependency Review`, `Container - Trivy (image)`,
`IaC - Trivy (config)`, `Secrets - Gitleaks`, et `DAST - ZAP baseline` si le
DAST tourne sur les PR. **Ne renommez pas les jobs**, sinon les PR attendent
un check qui n'arrive jamais. Personne ne peut contourner le ruleset
(administrateurs compris) ; pour une liste de contournement d'urgence :
*Bypass list* dans l'interface.

### Code scanning : default ou advanced setup

Le template utilise l'*advanced setup* (fichier `codeql.yml` versionné et
personnalisable). Les deux modes sont **exclusifs** : si le *default setup*
est actif dans l'interface, les analyses de `codeql.yml` sont refusées.

### À l'échelle d'une organisation

Les *security configurations* (*Settings* de l'organisation > *Advanced
Security* > *Configurations*) et les rulesets d'organisation appliquent ces
réglages à de nombreux repos d'un coup. Ce template reste utile pour un repo
isolé, une organisation sans Enterprise, ou en formation.

---

## 7. Exceptions et faux positifs

Une exception doit être **justifiée, tracée, datée et validée**. Corrigez
d'abord ; n'excluez jamais un chemin, ne relevez jamais un seuil pour faire
passer une PR sans la même validation.

| Qualification | Exemple |
|---|---|
| Faux positif | Chaîne aléatoire prise pour un secret |
| Non exploitable | Fonction vulnérable jamais appelée |
| Risque accepté | Aucune version corrigée disponible |
| Utilisé dans les tests | Faux mot de passe dans une fixture |

| Outil | Exception ponctuelle | Exception structurelle |
|---|---|---|
| CodeQL | Alerte > *Dismiss alert* + motif + commentaire | `paths-ignore` / `query-filters` dans `.github/codeql/codeql-config.yml` |
| Dependency Review | `allow-ghsas: GHSA-xxxx` dans le workflow (avec ticket) | `warn-only: true` pour une adoption progressive |
| Dependabot | *Dismiss alert* + motif | — |
| Trivy | `.trivyignore` (voir ci-dessous) | `#trivy:ignore:AWS-0089` au-dessus de la ressource IaC |
| Gitleaks | `# gitleaks:allow` en fin de ligne | `[[allowlists]]` dans `.gitleaks.toml` |
| Secret scanning | *Close as* + motif | Contournement de push protection tracé |
| ZAP | Passer la règle en `WARN` ou `IGNORE` dans `.zap/rules.tsv` (tabulations) | — |

Exemple `.trivyignore` (l'exception expire à la date `exp:`) :

```
# Non exploitable : fonction vulnérable de libxyz jamais appelée.
# Auteur : prenom.nom | Ticket : SEC-123 | Validé par : equipe-securite
CVE-2024-12345 exp:2026-12-31
```

> **Un vrai secret n'est jamais une exception.** Committé, il est compromis :
> révoquez-le, générez-en un nouveau, stockez-le dans un gestionnaire de
> secrets. Le retirer du code ne suffit pas, il reste dans l'historique.

Gouvernance : les fichiers d'exceptions et `.github/` sont protégés par
CODEOWNERS (revue de l'équipe sécurité obligatoire), versionnés dans Git, et
le modèle de PR a une section « Alertes justifiées ». Revue conseillée chaque
trimestre des alertes fermées et des exceptions sans date.

---

## 8. Démo et formation

Le dossier `demo/` contient une application **volontairement vulnérable**
(ne jamais la déployer) et sa configuration `demo/CONFIGURATION.demo.md`.

| Fichier | Faille | Détectée par |
|---|---|---|
| `app/app.py` `/user`, `/ping`, `/hello`, `/file`, `/import` | Injection SQL, injection de commande, XSS, path traversal, YAML non sûr | CodeQL |
| `app/app.py` fin de fichier | Flask en mode debug | CodeQL |
| `app/app.py` `API_KEY` | Secret en dur (valeur aléatoire, non valide) | Gitleaks |
| `app/app.py` `/` | Cookie sans `HttpOnly` | ZAP |
| `app/requirements.txt` | Dépendances obsolètes | Dependency Review, Dependabot, Trivy |
| `Dockerfile` | Image ancienne, exécution en root | Trivy image et config |
| `infra/main.tf` | Bucket S3 public, SSH ouvert, disque non chiffré | Trivy config |

Scénario (repo **public** de test, tout y est gratuit) :

1. *Use this template* > nouveau repo public, puis clonez-le.
2. `cp demo/CONFIGURATION.demo.md CONFIGURATION.md`, renseignez
   `GITHUB_REPO` et remplacez `@votre-compte`.
3. `bash scripts/setup.sh`, puis PR `activation-securite`. Attendu : CodeQL
   vert avec ~6 alertes dans Security ; Trivy image et IaC rouges ; Gitleaks
   vert sur la PR (secret antérieur) mais rouge sur `main` (historique).
4. Montrez l'onglet Security, puis corrigez `/user` en direct :
   `"... WHERE id = ?", (user_id,)` : l'alerte se ferme toute seule.
5. Mergez (aucun ruleset encore), attendez les workflows, `bash scripts/finalize.sh`.
6. Nouvelle PR ajoutant `urllib3==1.26.4` à `demo/app/requirements.txt` :
   Dependency Review échoue, le merge est impossible.
7. Ajoutez une exception justifiée et datée dans `.trivyignore`.

Lancer l'appli en local : `cd demo && docker build -t demo-app . && docker run --rm -p 8080:8080 demo-app`.

---

## 9. Référence des scripts

| Script | Rôle |
|---|---|
| `setup.sh` | Vérifie `CONFIGURATION.md`, génère/retire les fichiers, envoie les secrets, active les réglages |
| `finalize.sh` | Vérifie la branche principale, applique le ruleset, lance le nettoyage |
| `cleanup.sh` | Supprime les fichiers du template (appelé par `finalize.sh`) |
| `enable-security.sh` | Appels à l'API GitHub (réglages et ruleset) |

```bash
bash scripts/setup.sh --local-only                    # fichiers seulement, sans GitHub
bash scripts/setup.sh --target ../mon-projet --force  # projet existant, écrase les conflits
bash scripts/enable-security.sh --dry-run             # simule les appels API
bash scripts/enable-security.sh --print-ruleset > ruleset.json   # import manuel du ruleset
bash scripts/cleanup.sh --dry-run                     # aperçu du nettoyage
```

Chaque script accepte `--help`. Garanties : la configuration et `.env` sont
lus, jamais exécutés ; aucun fichier du projet n'est écrasé sans `--force` ;
seuls les fichiers générés par le template (mention `security-template:`)
sont supprimés ; les fichiers d'exceptions ne sont jamais écrasés ; les
secrets passent à `gh` par l'entrée standard ; `cleanup.sh` demande
confirmation.

---

## 10. Dépannage

| Symptôme | Solution |
|---|---|
| `HTTP 404` sur toutes les étapes | Compte non admin ou token sans scope `repo` : `gh auth refresh -s repo` |
| `HTTP 422` sur secret scanning (privé) | Pas de licence Secret Protection : décochez et gardez Gitleaks |
| Envoi SARIF en échec | Pas de licence Code Security ou PR de fork : rapports en artefacts |
| `Dependency review is not supported` | Dependency graph inactif ou licence absente : relancez `setup.sh` |
| PR bloquée « Waiting for status » | Check exigé jamais exécuté (job renommé, workflow supprimé) : corrigez le ruleset |
| `finalize.sh` refuse le ruleset | PR non mergée ou CodeQL pas terminé sur la branche : attendez puis relancez |
| Impossible d'approuver sa propre PR | Projet solo : `REQUIRED_APPROVALS` à `0`, relancez `finalize.sh` |
| « Fichier déjà présent » | Renommez puis relancez, ou `--force` |
| « .env est suivi par Git » | `git rm --cached .env` et révoquez les secrets |
| « X absent de CONFIGURATION.md » | Une ligne à case a été supprimée : remettez-la (absente = décochée) |

---

## 11. Limites

- **Faux positifs** : sans processus d'exception, les équipes contournent les
  contrôles (section 7).
- **Faux négatifs** : les failles de logique métier (contrôle d'accès)
  échappent aux outils. Revue de code et tests d'intrusion restent nécessaires.
- **DAST baseline** : passif uniquement ; un scan actif ou un pentest valide
  l'exploitabilité.
- **Seuils** : tout bloquer dès le premier jour sur un projet existant crée
  une dette ingérable. Démarrez sur HIGH/CRITICAL, durcissez ensuite.
