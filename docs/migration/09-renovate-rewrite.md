# 09 — Renovate rewrite

## Cél

A jelenlegi `.github/renovate.json5` + `.github/renovate/*.json` fragmens-szerkezet refaktorja bjw-s/onedr0p mintára: `.renovaterc.json5` a repo root-on, `.renovate/*.json5` fragmensekkel. Custom manager OCI URI-khoz (`oci://`). File pattern bővítés `.yaml.j2` Talos template-ekre.

## Inputs

- Cloud Renovate (Mend Renovate vagy GitHub App) marad — NEM self-hosted.
- A `talos` branch-en kerül implementálásra; cutover után main-be merge-elve a cloud Renovate átveszi.

## Tervezett fájl-layout

```
home-ops/
├── .renovaterc.json5                           # root config
└── .renovate/
    ├── allowedVersions.json5
    ├── autoMerge.json5
    ├── customManagers.json5                    # ÚJ — OCI URI + Talos extension regex
    ├── disabledDatasources.json5
    ├── groups.json5                            # ÚJ név (volt: groupPackages.json)
    ├── overrides.json5                         # ÚJ — packageRules override-ok
    └── prBodyNotes.json5
```

A `.github/renovate.json5` és `.github/renovate/*.json` **TÖRÖLŐDIK**.

## `.renovaterc.json5` (root config)

**Fájl:** `.renovaterc.json5`

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  extends: [
    ":enableRenovate",
    "config:recommended",
    ":disableRateLimiting",
    ":dependencyDashboard",
    ":semanticCommits",
    ":separatePatchReleases",
    "docker:enableMajor",
    ":enablePreCommit",
    "helpers:pinGitHubActionDigests",

    // Local fragments
    "github>zhorvath83/home-ops//.renovate/allowedVersions.json5",
    "github>zhorvath83/home-ops//.renovate/autoMerge.json5",
    "github>zhorvath83/home-ops//.renovate/customManagers.json5",
    "github>zhorvath83/home-ops//.renovate/disabledDatasources.json5",
    "github>zhorvath83/home-ops//.renovate/groups.json5",
    "github>zhorvath83/home-ops//.renovate/overrides.json5",
    "github>zhorvath83/home-ops//.renovate/prBodyNotes.json5",
  ],

  dependencyDashboardTitle: "Renovate Dashboard 🤖",
  suppressNotifications: ["prIgnoreNotification"],
  rebaseWhen: "conflicted",
  assignees: ["@zhorvath83"],
  timezone: "Europe/Budapest",
  minimumReleaseAge: "3 days",
  minimumReleaseAgeBehaviour: "timestamp-optional",

  // === Flux/Helm/Kubernetes file pattern: .yaml + .yaml.j2 (Talos) ===
  flux: {
    managerFilePatterns: [
      "/^kubernetes/.+\\.yaml(?:\\.j2)?$/",
    ],
  },
  "helm-values": {
    managerFilePatterns: [
      "/^kubernetes/.+\\.yaml(?:\\.j2)?$/",
    ],
  },
  kubernetes: {
    managerFilePatterns: [
      "/^kubernetes/.+\\.yaml(?:\\.j2)?$/",
    ],
  },
  helmfile: {
    managerFilePatterns: [
      "/^kubernetes/bootstrap/helmfile\\.d/.+\\.yaml$/",
    ],
  },
}
```

**Új elemek**:

- `.yaml.j2` pattern — Talos jinja2 template-eket Renovate követni tudja.
- `helmfile` manager — a `kubernetes/bootstrap/helmfile.d/*.yaml` chart verziói automatikusan frissülnek.

## `.renovate/customManagers.json5`

OCI URI-k (`oci://...:VERSION`) — sok HelmRelease ezt használja chartRef-ben.

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  customManagers: [
    {
      customType: "regex",
      description: "Process OCI dependencies in YAML files",
      managerFilePatterns: [
        "/^kubernetes/.+\\.yaml(?:\\.j2)?$/",
      ],
      matchStrings: [
        "oci://(?<depName>[^:\\s]+):(?<currentValue>\\S+)",
      ],
      datasourceTemplate: "docker",
    },
    {
      customType: "regex",
      description: "Process inline `# renovate:` annotations",
      managerFilePatterns: [
        "/^kubernetes/.+\\.yaml(?:\\.j2)?$/",
      ],
      matchStrings: [
        "datasource=(?<datasource>\\S+) depName=(?<depName>\\S+)( versioning=(?<versioning>\\S+))?\\n.*?\"(?<currentValue>.*)\"\\n",
      ],
      datasourceTemplate: "{{#if datasource}}{{{datasource}}}{{else}}github-releases{{/if}}",
      versioningTemplate: "{{#if versioning}}{{{versioning}}}{{else}}semver{{/if}}",
    },
    {
      customType: "regex",
      description: "Process Talos system extensions (factory.talos.dev image URLs)",
      managerFilePatterns: [
        "/^kubernetes/talos/.+\\.yaml(?:\\.j2)?$/",
      ],
      matchStrings: [
        "factory\\.talos\\.dev/(?<depName>metal-installer|image)/(?<schematic>[a-f0-9]+):(?<currentValue>v\\d+\\.\\d+\\.\\d+)",
      ],
      datasourceTemplate: "github-releases",
      depNameTemplate: "siderolabs/talos",
      versioningTemplate: "semver",
    },
    {
      customType: "regex",
      description: "Process Kubernetes container images by tag",
      managerFilePatterns: [
        "/^kubernetes/.+\\.yaml(?:\\.j2)?$/",
      ],
      matchStrings: [
        "registry\\.k8s\\.io/(?<depName>[^:]+):(?<currentValue>v\\d+\\.\\d+\\.\\d+)",
      ],
      datasourceTemplate: "docker",
      packageNameTemplate: "registry.k8s.io/{{depName}}",
    },
  ],
}
```

**Új**: Talos installer image, k8s controller image-ek (apiserver, controller-manager stb.) regex-szel felismerve.

## `.renovate/groups.json5`

Csoportosított PR-ek (group: ha N verzió együtt frissítendő).

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  packageRules: [
    {
      description: "Cilium group",
      groupName: "Cilium",
      matchDatasources: ["docker", "helm"],
      matchPackageNames: ["/cilium/"],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 1,
    },
    {
      description: "Flux Operator group",
      groupName: "Flux Operator",
      matchDatasources: ["docker"],
      matchPackageNames: ["/flux-operator/", "/flux-instance/", "/flux-operator-manifests/"],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 2,
    },
    {
      description: "1Password Connect group",
      groupName: "1Password Connect",
      matchDatasources: ["docker", "helm"],
      matchPackageNames: ["/1password/"],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 2,
    },
    {
      description: "Kubernetes core images",
      groupName: "Kubernetes",
      matchDatasources: ["docker"],
      matchPackageNames: [
        "/kube-apiserver/",
        "/kube-controller-manager/",
        "/kube-scheduler/",
        "/kubelet/",
      ],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 4,
    },
    {
      description: "Talos group",
      groupName: "Talos",
      matchDatasources: ["docker", "github-releases"],
      matchPackageNames: ["/siderolabs\\/talos$/", "/installer/"],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 1,
    },
    {
      description: "Cert-manager group",
      groupName: "cert-manager",
      matchDatasources: ["docker", "helm"],
      matchPackageNames: ["/cert-manager/"],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 2,
    },
    {
      description: "External Secrets group",
      groupName: "External Secrets",
      matchDatasources: ["docker", "helm"],
      matchPackageNames: ["/external-secrets/"],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 1,
    },
    {
      description: "Prometheus stack group",
      groupName: "Prometheus stack",
      matchDatasources: ["docker", "helm"],
      matchPackageNames: ["/kube-prometheus-stack/", "/prometheus-operator/", "/prometheus/"],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 2,
    },
    {
      description: "Envoy Gateway group",
      groupName: "Envoy Gateway",
      matchDatasources: ["docker", "helm"],
      matchPackageNames: ["/envoy-gateway/", "/envoyproxy/"],
      group: { commitMessageTopic: "{{{groupName}}} group" },
      minimumGroupSize: 1,
    },
  ],
}
```

A groupok lefedik a stack főbb komponenseit. Új groupok hozzáadhatók a stack bővülésekor.

## `.renovate/autoMerge.json5`

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  packageRules: [
    {
      description: "Auto merge container digests",
      matchDatasources: ["docker"],
      automerge: true,
      matchUpdateTypes: ["digest"],
      matchPackagePrefixes: [
        "ghcr.io/home-operations",
        "ghcr.io/onedr0p",
        "ghcr.io/bjw-s",
        "ghcr.io/bjw-s-labs",
      ],
    },
    {
      description: "Auto merge minor and patch updates on trusted images",
      matchDatasources: ["docker"],
      automerge: true,
      matchUpdateTypes: ["minor", "patch"],
      matchPackageNames: [
        "ghcr.io/home-operations/",
        "ghcr.io/onedr0p/",
        "ghcr.io/bjw-s/",
        "ghcr.io/bjw-s-labs/",
        "ghcr.io/coredns/",
      ],
    },
    {
      description: "Auto merge minor and patch helm chart updates",
      matchDatasources: ["helm"],
      automerge: true,
      matchUpdateTypes: ["minor", "patch"],
    },
    {
      description: "Auto merge pre-commit hook updates",
      matchManagers: ["pre-commit"],
      automerge: true,
      matchUpdateTypes: ["minor", "patch", "digest"],
    },
  ],
}
```

**Auto-merge policy**: csak megbízható publisher-ek (home-operations, onedr0p, bjw-s) minor/patch + digest. Major-t és külsősök frissítését manuálisan review-zd.

## `.renovate/overrides.json5`

Speciális verzió-kezelés (loose, regex):

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  packageRules: [
    {
      description: "Loose versioning for non-semver packages",
      matchDatasources: ["docker"],
      matchPackageNames: ["/plex/", "/qbittorrent/"],
      versioning: "loose",
    },
    {
      description: "Regex versioning for calibre-web-automated (V/v-prefixed)",
      matchDatasources: ["docker"],
      matchPackageNames: ["ghcr.io/crocodilestick/calibre-web-automated"],
      versioning: "regex:^[Vv](?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)$",
    },
    {
      description: "Labels for image updates",
      matchDatasources: ["docker"],
      matchUpdateTypes: ["major"],
      labels: ["renovate/image", "dep/major"],
    },
    {
      matchDatasources: ["docker"],
      matchUpdateTypes: ["minor"],
      labels: ["renovate/image", "dep/minor"],
    },
    {
      matchDatasources: ["docker"],
      matchUpdateTypes: ["patch"],
      labels: ["renovate/image", "dep/patch"],
    },
    {
      description: "Labels for helm updates",
      matchDatasources: ["helm"],
      matchUpdateTypes: ["major"],
      labels: ["renovate/helm", "dep/major"],
    },
    {
      matchDatasources: ["helm"],
      matchUpdateTypes: ["minor"],
      labels: ["renovate/helm", "dep/minor"],
    },
    {
      matchDatasources: ["helm"],
      matchUpdateTypes: ["patch"],
      labels: ["renovate/helm", "dep/patch"],
    },
    {
      description: "Helm chart separateMinorPatch",
      matchDatasources: ["helm"],
      separateMinorPatch: true,
      ignoreDeprecated: true,
    },
  ],
}
```

## `.renovate/disabledDatasources.json5`

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  packageRules: [
    {
      description: "Disable Flux controller updates (managed by FluxInstance)",
      matchPackageNames: [
        "ghcr.io/fluxcd/helm-controller",
        "ghcr.io/fluxcd/image-automation-controller",
        "ghcr.io/fluxcd/image-reflector-controller",
        "ghcr.io/fluxcd/kustomize-controller",
        "ghcr.io/fluxcd/notification-controller",
        "ghcr.io/fluxcd/source-controller",
      ],
      enabled: false,
    },
  ],
}
```

A Flux controller-eket a FluxInstance kezeli (a `distribution.artifact` verzió alapján). A Renovate **NE** írja át őket.

## `.renovate/allowedVersions.json5`

Speciális verzió-konstraintek (ha valami nem mehet major-ig pl. K8s csak 1.36.x):

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  packageRules: [
    {
      description: "Pin Kubernetes to 1.36.x line",
      matchDatasources: ["docker", "github-releases"],
      matchPackageNames: [
        "/kube-apiserver/",
        "/kube-controller-manager/",
        "/kube-scheduler/",
        "/kubelet/",
        "ghcr.io/siderolabs/kubelet",
      ],
      allowedVersions: "1.36.x",
    },
  ],
}
```

A K8s minor-t manuálisan léptetjük (`just talos upgrade-k8s v1.37.0`), tehát Renovate ne nyomjon major/minor PR-eket. Az `allowedVersions` ezt biztosítja.

## `.renovate/prBodyNotes.json5`

```json5
{
  $schema: "https://docs.renovatebot.com/renovate-schema.json",
  packageRules: [
    {
      description: "Add manual review note for major bumps",
      matchUpdateTypes: ["major"],
      prBodyNotes: [
        "⚠️ **Major version bump** — review breaking changes manually before merge.",
      ],
    },
    {
      description: "Add note for Talos updates",
      matchPackageNames: ["/talos/"],
      prBodyNotes: [
        "ℹ️ Talos upgrade — also update `kubernetes/talos/schematic.yaml` and rerun `just talos gen-schematic-id`.",
      ],
    },
    {
      description: "Add note for Cilium updates",
      matchPackageNames: ["/cilium/"],
      prBodyNotes: [
        "ℹ️ Cilium upgrade — also update `kubernetes/bootstrap/helmfile.d/01-apps.yaml`. Don't auto-merge.",
      ],
    },
  ],
}
```

## Helmfile chart frissítés inline annotációval

A bootstrap helmfile-ben a `version:` mezőkre Renovate inline annotációkkal mutatható rá:

```yaml
releases:
  - name: cilium
    chart: oci://quay.io/cilium/charts/cilium
    # renovate: datasource=docker depName=quay.io/cilium/charts/cilium
    version: 1.19.4
```

**De**: az `oci://` URI custom managere már elkapja ezt — nem feltétlen kell inline annotation, csak ha override-olni kell a datasource-t.

## Validation

### Lokálisan Renovate dry-run

```bash
# A Renovate CLI lokálisan futtatható (npx via mise nélkül):
LOG_LEVEL=debug npx renovate@latest --platform=local --dry-run=full
# kimenetet ad: milyen PR-ek készülnének
```

### Dependency Dashboard

A Renovate cloud lefutása után a repón egy `🤖 Renovate Dashboard` issue lesz — összefoglalva az aktuális detektált dep-eket és a tervezett PR-eket.

## Migráció lépésről lépésre (talos branch)

1. `mkdir -p .renovate`
2. `.renovaterc.json5` létrehozás (új tartalom)
3. `.renovate/*.json5` fájlok létrehozás (átalakítás + új tartalom)
4. **TÖRÖL**: `.github/renovate.json5`
5. **TÖRÖL**: `.github/renovate/*.json` (a 6 fragmens)
6. Git commit: `🧹 chore(renovate): rewrite to .renovaterc.json5 + .renovate/ fragments`
7. Push a `talos` branch-re
8. Cutover-kor merge main-be → cloud Renovate detektálja az új helyet automatikusan (mindkét formátum kompatibilis Renovate-cloud oldalon).

## Rollback

A `.github/renovate.json5` és a `.renovate/.renovaterc.json5` **párhuzamosan nem létezhet** — Renovate első találatot olvas. Ha main-en megmarad a `.github/renovate.json5`, a talos branch-en lévő `.renovaterc.json5` nem aktív. Cutover-kor (talos → main merge) az új helyzet él.

Ha valami nem stimmel: `git revert <merge-commit>` → vissza az `.github/renovate.json5`-höz.

## Open issues

- **Forgejo Actions** (bjw-s) vs **GitHub Actions** (nálad): a `pinGitHubActionDigests` preset GitHub-specifikus. Bjw-s nem használja (Forgejo-ra váltott). Nálad megmarad.
- **`bjw-s/renovate-config` shared base**: a bjw-s saját shared config-ot fenntart. Mi nem extend-eljük (saját preset-ünk a `:enableRenovate` + `config:recommended` elég).
- **`onCommitPath` git hook**: ha lokálisan Renovate-tel akarsz dolgozni (nem cloud), a `.renovaterc.json5` szerepe ugyanaz, csak `npx renovate --platform=local` fut.
- **Renovate Cloud GitHub App jogosultságok**: az új `.renovate/` mappa nem igényel külön jogosultság-update — a Renovate App már fér hozzá a teljes repóhoz.
- **`grafanaDashboards.json5`** (bjw-s) opcionális — Grafana dashboard JSON-okat is Renovate-tel követhetnénk, ha a stack-ben dashboard-okat tárolunk.  Most NEM építünk be (kihagyható).
