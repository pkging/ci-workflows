# ci-workflows

Ein zentrales Repository mit wiederverwendbaren GitHub Actions Workflows, Hooks und Container-Skripten zum Bauen, Testen, Signieren und Uploaden von RPM- und DEB-Paketen fuer mehrere Distributionen und Architekturen.

## 🚀 Features

- Multi-Distro (z. B. AlmaLinux, Rocky, Fedora)
- Multi-Arch (x86_64/amd64, aarch64/arm64, ppc64le, s390x)
- Reproduzierbare RPM-Builds in Containern
- Getrennte Artefakte:
  - Binär-RPMs (`rpm-bin-*`)
  - Source-RPMs (`rpm-src-*`)
- SPEC-Datei im Projekt-Root
- Hook-System für projektbezogene Anpassungen
- Automatische Artefakt-Benennung mit Distro-Suffix
- Smoke-Tests im Container
- Wiederverwendbarer Pulp-Upload-Workflow für Tag-Releases
- Wiederverwendbarer Package-Orchestrierungsworkflow für Build, Test und Upload
- Optionale zentrale Paket-Signierung vor dem Upload
- Zentrale Zielaufloesung fuer Uploads ueber TARGET_TYPE, TARGET_FAMILY und TARGET_VERSION
- Taegliches Spiegeln der Build-Containerimages von Docker Hub nach GHCR

## 📁 Repository-Struktur

```
ci-workflows/
│
├── .github/workflows/
│   ├── build.yml              # Reusable Build/Test Workflow
│   ├── mirror-build-images.yml # Daily mirror Docker Hub -> GHCR
│   ├── package.yml            # Reusable Package Orchestration Workflow
│   └── pulp-upload.yml        # Reusable Pulp Upload Workflow
│
└── hooks/
├── pre_build_in_runner.sh
├── pre_test_in_runner.sh
├── pre_build_in_container.sh
├── pre_test_in_container.sh
├── rpmbuild_in_container.sh
├── rpmtest_in_container.sh
└── lib/
├── common.sh
├── distro.sh
└── container_images.sh

└── scripts/
  └── pulp-bootstrap.sh
```


## 🧩 Verwendung im Zielrepo

```yaml
jobs:
  package:
    uses: pkging/ci-workflows/.github/workflows/package.yml@main
    with:
      ci_workflows_ref: "main"
      source_event_name: "workflow_dispatch"
      source_ref_name: "main"
      source_ref_type: "branch"
      run_upload: false
      matrix: |
        el9: x86_64
        debian12: x86_64
        ubuntu24: x86_64
```

Mehrere Architekturen pro Distribution werden ebenfalls unterstuetzt:

```yaml
matrix: |
  el9:
    - x86_64
    - aarch64
  ubuntu24: [x86_64, arm64]
```

Alternativ kann `matrix` auch als JSON-Mapping uebergeben werden:

```yaml
matrix: '{"el9": ["x86_64", "aarch64"], "ubuntu24": "x86_64"}'
```

Standardverhalten: `sign_packages` ist per Default `true`.
Nur bei Bedarf abschalten mit:

```yaml
sign_packages: false
```

### Build-Images nach GHCR spiegeln (taeglich)

Der Workflow [ci-workflows/.github/workflows/mirror-build-images.yml](.github/workflows/mirror-build-images.yml) spiegelt die benoetigten Basis-Images taeglich von Docker Hub nach GHCR:

- Quelle: `almalinux`, `fedora`, `debian`, `ubuntu` (feste Tag-Liste im Workflow)
- Ziel: `ghcr.io/pkging/build-images/<name>:<tag>`
- Trigger:
  - `schedule` (taeglich)
  - `workflow_dispatch` (manuell)

Auth-Modell:

- Kein manuell gepflegtes Secret noetig.
- Push nach GHCR laeuft ueber `GITHUB_TOKEN`.
- Der Workflow braucht `permissions: packages: write`.

Konsumenten (Build/Test):

- [ci-workflows/.github/workflows/build.yml](.github/workflows/build.yml) nutzt GHCR-Login mit `GITHUB_TOKEN` und `permissions: packages: read`.
- Die Image-Aufloesung erfolgt ueber [ci-workflows/hooks/lib/container_images.sh](hooks/lib/container_images.sh).

### Vorgefertigte CI-Images

Fuer alle Matrixziele werden CI-Images mit gemeinsamen Build- und
Testwerkzeugen gebaut. Die Dockerfiles liegen unter `images/<familie>/<version>/`;
`.github/workflows/build-ci-images.yml` baut sie fuer `linux/amd64` und
`linux/arm64` und publiziert versionierte Tags wie
`ghcr.io/pkging/build-images/ubuntu:26.04-ci-v1`.
`container_images.sh` verwendet diese Tags fuer die jeweiligen Distro-Keys.
Die globalen Build-/Test-Hooks erkennen das im Dockerfile gesetzte
`/etc/pkging-ci-image`-Merkmal und installieren die dort bereits enthaltenen
Werkzeuge nicht erneut. Paketbezogene Hooks und deren Abhaengigkeiten laufen
weiter wie bisher.

Bei Aenderungen unter `images/` wird das betroffene Image bei Push nach `main`
automatisch neu gebaut. Fuer eine kontrollierte Werkzeugaktualisierung einen
neuen Tag (zum Beispiel `26.04-ci-v2`) veroeffentlichen und erst danach das
Mapping in `container_images.sh` umstellen. Die unveraenderten Basisimages
werden weiterhin separat vom Mirror-Workflow gespiegelt.

### GitHub Klickreihenfolge: Package auf Public stellen

Falls bei einem Package steht "Setting is disabled by organization administrators", ist die Public-Visibility auf Org- oder Enterprise-Ebene gesperrt.

Org-Ebene freigeben (Owner/Admin):

1. GitHub -> Organization `pkging` -> `Settings`
2. In der linken Navigation `Packages` oeffnen
3. Richtlinie fuer Package-Visibility suchen (Container/GHCR)
4. Option aktivieren, dass Packages auf `Public` gestellt werden duerfen
5. Speichern

Danach Package sichtbar machen:

1. Organization `pkging` -> `Packages`
2. Package oeffnen (z. B. `build-images/debian`)
3. `Package settings`
4. `Change visibility` -> `Public`
5. Bestaetigen

Wenn weiterhin gesperrt:

1. Als Enterprise-Admin in die Enterprise-Settings wechseln
2. Dort die uebergeordnete Policy fuer Package-Visibility (GHCR) freigeben
3. Anschliessend die Org-/Package-Schritte oben erneut ausfuehren

### Troubleshooting: Mirror und GHCR Pulls

`docker: unauthorized` oder `error from registry: unauthorized`

- Ursache: Repo darf privates GHCR-Package nicht lesen.
- Pruefen:
  - Im Package unter `Manage Actions access` ist das konsumierende Repo mit `Read` eingetragen.
  - Im Workflow sind `permissions: packages: read` gesetzt.
  - Der Schritt `Login to GHCR` laeuft vor `docker run`.

`denied: permission denied` beim Mirror-Workflow

- Ursache: Schreibrechte auf GHCR fehlen.
- Pruefen:
  - Im Mirror-Workflow sind `permissions: packages: write` gesetzt.
  - Die Org erlaubt Package-Push fuer Actions in diesem Repo.
  - Workflow laeuft im Repo `pkging/ci-workflows` (Owner muss zur Ziel-Registry passen).

`manifest unknown` oder Tag nicht gefunden

- Ursache: Tag wurde noch nicht gespiegelt oder Tippfehler im Mapping.
- Pruefen:
  - Mirror-Workflow manuell starten (`workflow_dispatch`).
  - Ziel-Tag in GHCR existiert.
  - Mapping in [ci-workflows/hooks/lib/container_images.sh](hooks/lib/container_images.sh) stimmt exakt mit dem GHCR-Tag ueberein.

Docker Hub `429 Too Many Requests` im Mirror-Workflow

- Ursache: Mirror zieht zu oft/parallel anonym von Docker Hub.
- Optionen:
  - Spiegel-Zeitpunkt auf weniger frequenten Slot legen.
  - Doppelte/unnuetze Runs vermeiden (Concurrency ist bereits gesetzt).
  - Falls noetig zusaetzlich Docker-Hub-Auth fuer den Mirror aktivieren.

`pull access denied` im Build/Test trotz erfolgreichem Login

- Ursache: Caller-Workflow begrenzt Token-Rechte.
- Pruefen:
  - Im aufrufenden Repository eigener `permissions`-Block vorhanden?
  - Falls ja: dort explizit `packages: read` setzen.
  - Reusable-Workflow-Rechte alleine reichen sonst nicht immer.

### Tag-Policy fuer Uploads

Der Reusable-Workflow in [ci-workflows/.github/workflows/package.yml](.github/workflows/package.yml) unterscheidet Uploads nach Tag-Namen:

- `rpm/vX.Y.Z` oder `rpm/vX.Y.Z-suffix`: Upload nur fuer RPM-Ziele (`target_type=rpm`)
- `deb/vX.Y.Z` oder `deb/vX.Y.Z-suffix`: Upload nur fuer APT/DEB-Ziele (`target_type=apt`)
- `vX.Y.Z` oder `vX.Y.Z-suffix` (ohne Prefix): Upload fuer alle Zieltypen in der Matrix

Nicht passende Tags werden abgewiesen (kein Upload).

Beispiele:

- `rpm/v1.0.0-2` -> nur RPM Upload
- `deb/v1.0.0` -> nur DEB/APT Upload
- `v1.0.0-2` -> RPM und DEB/APT Upload

Wichtig fuer aufrufende Repositories: Bei `workflow_call` muss der Event-/Ref-Kontext an den Reusable-Workflow durchgereicht werden, damit Tag-Pushes korrekt ausgewertet werden:

```yaml
with:
  source_event_name: ${{ github.event_name }}
  source_ref_name: ${{ github.ref_name }}
  source_ref_type: ${{ github.ref_type }}
```

### Upload-Zielmodell (zentral)

Die Zielzuordnung fuer Pulp-Uploads wird zentral in `ci-workflows/.github/workflows/package.yml` aus `matrix.distro` berechnet.

Wichtig:

- Aufrufende Repos geben nur `matrix` (Distro/Arch), `run_upload` und optional `sign_packages` an.
- Die bisherigen Inputs `rpm_repository` und `deb_repository` werden nicht mehr verwendet.
- Unbekannte Distros oder ungueltige Zielkombinationen fuehren zu einem sofortigen Hard-Fail.

Aktuelles zentrales Mapping:

| matrix.distro | TARGET_TYPE | TARGET_FAMILY | TARGET_VERSION |
| --- | --- | --- | --- |
| `el8` | `rpm` | `epel` | `8` |
| `el9` | `rpm` | `epel` | `9` |
| `el10` | `rpm` | `epel` | `10` |
| `fedora43` | `rpm` | `fedora` | `43` |
| `fedora44` | `rpm` | `fedora` | `44` |
| `debian12` | `apt` | `debian` | `bookworm` |
| `debian13` | `apt` | `debian` | `trixie` |
| `ubuntu22` | `apt` | `ubuntu` | `jammy` |
| `ubuntu24` | `apt` | `ubuntu` | `noble` |
| `ubuntu26` | `apt` | `ubuntu` | `resolute` |

Aufloesung im Upload:

- RPM: Repository `rpm-<family>-<version>`, Base-Path `rpm/<family>/<version>`
- APT Debian: Repository `debian-apt`, Base-Path `debian`, Suite ueber `TARGET_VERSION`
- APT Ubuntu: Repository `ubuntu-apt`, Base-Path `ubuntu`, Suite ueber `TARGET_VERSION`

### Neue Distversion hinzufuegen

Eine neue Distversion muss an mehreren Stellen freigeschaltet werden. Ein Eintrag
in der Matrix eines Paket-Repositories allein reicht nicht aus. Die Aenderungen
muessen in `pkging/ci-workflows` und, falls dort versionsspezifische Hooks liegen,
auch im jeweiligen Paket-Repository erfolgen.

1. **Build-Image spiegeln:** `.github/workflows/mirror-build-images.yml` enthaelt
  eine eigene Liste der Quell-Images. Ergaenze dort den Upstream-Tag und starte
  den Mirror-Workflow. Falls GitHub meldet, dass `workflow_dispatch` fuer einen
  deaktivierten Workflow nicht moeglich ist, aktiviere den Workflow in GitHub
  Actions und starte ihn erneut. Pruefe nach erfolgreichem Lauf, dass das Image
  unter `ghcr.io/pkging/build-images/<name>:<tag>` erreichbar ist. Die Liste
  wird nicht automatisch aus dem Image-Mapping erzeugt.
2. **Distro-Key auf Image abbilden:** Ergaenze denselben Matrix-Key in
  [container_images.sh](hooks/lib/container_images.sh) mit dem exakten GHCR-Image.
  Der Key muss mit dem im aufrufenden Paket-Workflow verwendeten Matrix-Key
  uebereinstimmen.
3. **Zielmapping ergaenzen:** Fuege den Key in `TARGET_MAP` in
  `.github/workflows/package.yml` ein. Setze `target_type`, `target_family` und
  `target_version` passend zum Paketformat und zum Repository-Ziel. Bei APT ist
  `target_version` der Suite-Name (zum Beispiel `noble`), nicht die numerische
  Ubuntu-Version. Aktualisiere auch die Mapping-Tabelle direkt oberhalb dieser
  Checkliste.
4. **Upload-Validierung ergaenzen:** Wenn die neue Familie oder Suite noch nicht
  erlaubt ist, aktualisiere die passenden Allowlisten in
  `.github/workflows/pulp-upload.yml` und `scripts/pulp-bootstrap.sh`. Pruefe,
  dass Repository-Name, Suite und Pulp-Basispfad fuer das Ziel tatsaechlich
  eingerichtet sind.
5. **Paket-Hooks und Release-Paket pruefen:** Im Paket-Repository die Hooks unter
  `.github/hooks/` auf versionsspezifische Allowlisten und Installations-URLs
  pruefen, insbesondere `pre_build.sh`, `pre_test.sh` und `smoke.sh`, sofern
  vorhanden. Das passende OpenVox-Release-Paket muss fuer die Distribution
  verfuegbar sein; ein Eintrag in einer lokalen Allowlist erzeugt es nicht.
6. **Aufrufende Paket-Matrix erweitern:** Erst wenn Image, Build/Test und
  gegebenenfalls Upload vorbereitet sind, den Distro-Key samt Architektur in
  `.github/workflows/package.yml` des Paket-Repositories aufnehmen.
7. **Validieren:** Einen Build und Paket-Test fuer die neue Matrix-Kombination
  ausfuehren. Bei aktiviertem Upload zusaetzlich Upload/Bootstrap pruefen. Bei
  Fehlern die erste fehlgeschlagene Stufe auswerten: Matrix-Aufloesung,
  Image-Pull, Release-Paket-Installation, Paketinstallation oder Pulp-Upload.

### Self-Hosted Runner Voraussetzungen

Auf einem Self-Hosted Runner werden mehrere Tools und Rechte vorausgesetzt, die auf `ubuntu-latest` bereits vorhanden sind, im pkging aber haeufig fehlen:

- Build und Test benoetigen eine funktionierende Docker-Installation inklusive laufendem Daemon.
- Multi-Arch Builds und Tests (`aarch64` oder `arm64`, `ppc64le`, `s390x`) benoetigen zusaetzlich QEMU bzw. `binfmt_misc`, damit `docker/setup-qemu-action` Container fuer Fremdarchitekturen registrieren kann.
- Die Runner-Hooks und der Signing-Job installieren Pakete per `apt-get`, daher ist der aktuelle Workflow fuer Debian-/Ubuntu-basierte Runner mit `apt-get` ausgelegt.
- Fuer diese Paketinstallation wird `sudo` oder ein Runner mit Root-Rechten benoetigt.
- Der Signing-Job benoetigt ausserdem `gnupg`, `rpm` und fuer DEB-Signaturen `dpkg-sig` oder `debsigs`; der Workflow installiert diese Pakete aktuell selbst.
- Der Upload-Job richtet Python ueber `actions/setup-python` ein und installiert `pulp-cli` per `pip`; dafuer braucht der Runner Netzwerkzugriff auf GitHub/PyPI.

Diese Voraussetzungen werden jetzt vor den eigentlichen Build-, Sign- und Upload-Schritten per Preflight geprueft, damit ein Self-Hosted Runner frueh mit einer klaren Fehlermeldung abbricht.

Fuer Ubuntu/Debian gibt es ausserdem ein Bootstrap-Skript in [scripts/prepare-selfhosted-runner.sh](scripts/prepare-selfhosted-runner.sh), das die ueblichen Host-Voraussetzungen installiert und konfiguriert.

Wenn ein Runner diese Voraussetzungen nicht erfuellt, sollte entweder ein passendes Runner-Label verwendet oder `sign_packages: false` gesetzt werden.

### 🔐 Signierung

Die zentrale Pipeline signiert RPM- und DEB-Pakete standardmaessig vor dem Upload.

Im Workflow werden dabei genau zwei Werte aus dem aufrufenden Package-Repo erwartet:

- `PACKAGE_SIGNING_PRIVATE_KEY` (ASCII-armored private key)
- `PACKAGE_SIGNING_KEY_ID`

Im Signing-Job von [ci-workflows/.github/workflows/package.yml](ci-workflows/.github/workflows/package.yml) wird der private Schlüssel importiert und die Key-ID für RPM- und DEB-Signaturen verwendet. Das ist der Schlüssel, der für die eigentliche Paket-Signierung im CI-Workflow gebraucht wird.

Wichtig: Diese Werte müssen im aufrufenden Workflow-Repository als GitHub-Secrets vorhanden sein und dem Reusable-Workflow über `secrets: inherit` mitgegeben werden. Die Preflight-Hook liest sie direkt aus der Job-Umgebung; wenn sie dort fehlen, bricht der Lauf mit einer Meldung wie `PACKAGE_SIGNING_PRIVATE_KEY secret is required when sign_packages=true` ab.

Im Repository dieser Arbeitsumgebung existieren zusätzlich zwei Export-Dateien für GPG-Schlüsselmaterial:

- [gpg-signing-export-20260709-184342/private-key.asc](gpg-signing-export-20260709-184342/private-key.asc) und [gpg-signing-export-20260709-184342/public-key.asc](gpg-signing-export-20260709-184342/public-key.asc)
- [gpg-signing-export-20260709-184342/pulp-signing-private.asc](gpg-signing-export-20260709-184342/pulp-signing-private.asc) und [gpg-signing-export-20260709-184342/pulp-signing-public.asc](gpg-signing-export-20260709-184342/pulp-signing-public.asc)

Diese beiden Schlüsselpaare sind nicht identisch. Sie sind getrennte Exporte, die in unterschiedlichen Kontexten verwendet werden können: ein allgemeiner Signing-Key für die Paket-Signierung und ein Pulp-/Repository-spezifischer Key für den Upload- und Signing-Flow. In der aktuellen GitHub-Secret-Setup-Routine wird der gewählte private Schlüssel über [scripts/set-gh-pulp-secrets.sh](scripts/set-gh-pulp-secrets.sh) als `PACKAGE_SIGNING_PRIVATE_KEY` in die Ziele überführt.

Für ein neues Setup empfiehlt sich daher: genau einen Signing-Key pro Zweck wählen, diesen privaten Schlüssel und die zugehörige Key-ID als GitHub-Secrets speichern und dabei sicherstellen, dass der Secret-Wert und die Key-ID zueinander passen.

### 🪝 Projekt-Hooks

```
.github/hooks/
├── pre_build.sh
├── post_build.sh
├── pre_test.sh
├── post_test.sh
└── smoke.sh
```

Alle Hooks sind optional.

#### Reihenfolge und Verantwortlichkeiten im Test-Container

Die Test-Hooks werden in fester Reihenfolge ausgeführt:

1. pre_test.sh
2. smoke.sh
3. post_test.sh

Semantik:

- pre_test.sh: Bereitet den Testlauf vor (z. B. zusätzliche Repositories, Testdaten, Umgebung).
- smoke.sh: Enthält die eigentlichen Funktionsprüfungen nach der Paketinstallation.
- post_test.sh: Nachgelagerte Schritte wie Cleanup, Log-Sammlung oder zusätzliche Diagnose.

Wichtig: Der Testlauf verwendet set -euo pipefail. Wenn smoke.sh mit Fehler beendet wird, wird post_test.sh nicht mehr ausgeführt.

Referenz der tatsächlichen Aufrufreihenfolge:

- [ci-workflows/hooks/test_in_container.sh](hooks/test_in_container.sh)

### 📦 Artefakte

* rpm-bin-<distro>-<arch> → Binär-RPMs
* rpm-src-<distro>-<arch> → Source-RPMs

Beide werden automatisch korrekt benannt, z.B.:

```
mypkg-1.2.3-1.x86_64.almalinux9.rpm
mypkg-1.2.3-1.src.almalinux9.rpm
```

🧭 **Architekturdiagramm**

```mermaid
flowchart TD

    subgraph Repo["Zielrepo"]
        SPEC["*.spec (Root)"]
        SRC["Projektquellen"]
        HOOKS[".github/hooks/*"]
    end

    subgraph CI["ci-workflows"]
        WF["Reusable Workflow"]
        PRE_RUN["pre_build_in_runner.sh"]
        PRE_CONT["pre_build_in_container.sh"]
        BUILD["rpmbuild_in_container.sh"]
        TEST["rpmtest_in_container.sh"]
    end

    subgraph Container["Build/Test Container"]
        DNF["dnf install deps"]
        RPMBUILD["rpmbuild -ba"]
        INSTALL["dnf install *.rpm"]
        SMOKE["smoke.sh"]
    end

    Repo --> WF
    WF --> PRE_RUN
    WF --> PRE_CONT
    PRE_CONT --> BUILD
    BUILD -->|RPMS/SRPMS| WF
    WF --> TEST
    TEST --> INSTALL
    INSTALL --> SMOKE
```

### 🧪 Smoke-Tests

Smoke-Tests laufen im Container und können beliebige Kommandos ausführen:

```
.github/hooks/smoke.sh
```

Vorlage:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "[SMOKE] Running smoke tests..."

# Beispiel: Binary vorhanden?
if ! command -v mybinary >/dev/null; then
  echo "❌ mybinary not found"
  exit 1
fi

# Beispiel: Version check
mybinary --version

# Beispiel: Config check
if [ -f /etc/myapp/config.yml ]; then
  echo "[OK] Config file exists"
else
  echo "❌ Config file missing"
  exit 1
fi

# Beispiel: Service check (falls vorhanden)
if systemctl list-unit-files | grep -q myservice; then
  systemctl status myservice || true
fi

echo "[SMOKE] All tests passed."
```
