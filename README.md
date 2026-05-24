# buildkit-helm

Helm chart for deploying [moby/buildkit](https://github.com/moby/buildkit) and [BuilderHub/buildkit-hive](https://github.com/BuilderHub/buildkit-hive) on Kubernetes.

## Features

- Multiple daemons per release (`daemons[]`)
- Workload modes: `pod`, `daemon`, `statefulset`
- Architecture selection via `arch` (`amd64` / `arm64`)
- Storage: PVC, hostPath, or emptyDir
- Per-daemon mTLS (server + client secrets, inline or bring-your-own)
- `buildkitd.toml`: inline ConfigMap or existing ConfigMap
- **buildkit-hive**: S3 credentials via Secret env vars; Postgres DSN via BYO ConfigMap or init merge
- **buildkit-metrics-agent** sidecar (enabled by default)

## Install

```bash
helm install buildkit ./charts/buildkit \
  --namespace buildkit \
  --create-namespace
```

### OCI chart (GitHub Release)

Publish a [GitHub Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository) with a semver tag (`v0.1.0` or `0.1.0`). The release tag becomes the chart version pushed to GHCR.

```bash
helm install buildkit oci://ghcr.io/builderhub/buildkit --version 0.1.0
```

## Quick examples

### Plain BuildKit (rootless pod)

```yaml
daemons:
  - name: local
    variant: buildkit
    mode: pod
    rootless: true
    storage:
      type: emptyDir
    service:
      enabled: true
```

### buildkit-hive (shared cache)

```yaml
daemons:
  - name: hive
    variant: hive
    mode: statefulset
    replicas: 3
    arch: amd64
    config:
      inline: |
        [cache]
          backend = "postgres"
          [cache.s3]
            bucket = "my-buildkit-cache"
            region = "us-east-1"
    secrets:
      s3:
        enabled: true
        existingSecret: buildkit-s3-credentials
        secretKeys:
          AWS_ACCESS_KEY_ID: AWS_ACCESS_KEY_ID
          AWS_SECRET_ACCESS_KEY: AWS_SECRET_ACCESS_KEY
      postgres:
        enabled: true
        existingSecret: buildkit-postgres
        secretKeys:
          dsn: connection-string
```

See [buildkit-hive buildkitd.toml docs](https://github.com/BuilderHub/buildkit-hive/blob/master/docs/buildkitd.toml.md) for cache configuration.

### mTLS (BYO secret keys)

```yaml
tls:
  server:
    enabled: true
    existingSecret: my-server-tls
    secretKeys:
      ca: ca.crt
      cert: tls.crt
      key: tls.key
  client:
    enabled: true
    existingSecret: my-client-tls
    secretKeys:
      ca: ca.crt
      cert: tls.crt
      key: tls.key
```

## Metrics

When `metrics.enabled` is true, the chart adds a [buildkit-metrics-agent](https://github.com/BuilderHub/buildkit-metrics-agent) sidecar and exposes port `9090` on the daemon Service. Configure scrape outside the chart (Prometheus, Grafana Agent, etc.).

## CI

- **on-pr.yaml**: `helm lint`, chart-testing lint, kind install, port-forward, buildx remote build
- **on-release.yaml**: on `release` published, packages the chart using the release tag as version and pushes `oci://ghcr.io/builderhub/buildkit`

Local checks:

```bash
helm lint charts/buildkit
helm template test charts/buildkit -f ci/values-lint.yaml
```

## License

MIT — see [LICENSE](LICENSE).
