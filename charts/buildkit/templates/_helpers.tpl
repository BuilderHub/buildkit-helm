{{/*
Expand the name of the chart.
*/}}
{{- define "buildkit.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "buildkit.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Per-daemon full name: release + daemon name.
*/}}
{{- define "buildkit.daemonFullname" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- printf "%s-%s" (include "buildkit.fullname" $root) $daemon.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Chart name and version for labels.
*/}}
{{- define "buildkit.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels for all resources.
*/}}
{{- define "buildkit.labels" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
helm.sh/chart: {{ include "buildkit.chart" $root }}
{{ include "buildkit.selectorLabels" (list $root $daemon) }}
{{- if $root.Chart.AppVersion }}
app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
app.kubernetes.io/component: buildkit
{{- with $root.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- with $daemon.extraLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels (daemon-scoped).
*/}}
{{- define "buildkit.selectorLabels" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
app.kubernetes.io/name: {{ include "buildkit.name" $root }}
app.kubernetes.io/instance: {{ $root.Release.Name }}
buildkit.builderhub.dev/daemon: {{ $daemon.name }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "buildkit.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "buildkit.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Daemon variant (buildkit | hive).
*/}}
{{- define "buildkit.daemonVariant" -}}
{{- $daemon := . }}
{{- default "buildkit" $daemon.variant }}
{{- end }}

{{/*
Image defaults for a daemon variant.
*/}}
{{- define "buildkit.imageValues" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $variant := include "buildkit.daemonVariant" $daemon }}
{{- if eq $variant "hive" }}
{{- toYaml $root.Values.image.hive }}
{{- else }}
{{- toYaml $root.Values.image.buildkit }}
{{- end }}
{{- end }}

{{- define "buildkit.imageRepository" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $img := fromYaml (include "buildkit.imageValues" (list $root $daemon)) }}
{{- $over := $daemon.image | default dict }}
{{- default $img.repository $over.repository }}
{{- end }}

{{- define "buildkit.imageTag" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $variant := include "buildkit.daemonVariant" $daemon }}
{{- $img := fromYaml (include "buildkit.imageValues" (list $root $daemon)) }}
{{- $over := $daemon.image | default dict }}
{{- $tag := default "" $over.tag }}
{{- if not $tag }}
{{- if eq $variant "hive" }}
{{- $img.tag }}
{{- else if $daemon.rootless }}
{{- printf "%s-rootless" (default $root.Chart.AppVersion $img.tag) }}
{{- else }}
{{- default $root.Chart.AppVersion $img.tag }}
{{- end }}
{{- else }}
{{- $tag }}
{{- end }}
{{- end }}

{{- define "buildkit.imagePullPolicy" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $img := fromYaml (include "buildkit.imageValues" (list $root $daemon)) }}
{{- $over := $daemon.image | default dict }}
{{- default $img.pullPolicy $over.pullPolicy }}
{{- end }}

{{/*
Default storage mount path by rootless flag.
*/}}
{{- define "buildkit.storageMountPath" -}}
{{- $daemon := . }}
{{- if $daemon.storage.mountPath }}
{{- $daemon.storage.mountPath }}
{{- else if $daemon.rootless }}
{{- "/home/user/.local/share/buildkit" }}
{{- else }}
{{- "/var/lib/buildkit" }}
{{- end }}
{{- end }}

{{/*
Arch nodeSelector fragment.
*/}}
{{- define "buildkit.archNodeSelector" -}}
{{- $daemon := . }}
{{- if $daemon.arch }}
kubernetes.io/arch: {{ $daemon.arch | quote }}
{{- end }}
{{- end }}

{{/*
Whether buildkitd needs --config.
*/}}
{{- define "buildkit.needsConfig" -}}
{{- $daemon := . }}
{{- $cfg := $daemon.config | default dict }}
{{- if or $cfg.inline $cfg.existingConfigMap (eq (include "buildkit.hivePostgresInit" $daemon) "true") }}
true
{{- end }}
{{- end }}

{{/*
ConfigMap name for inline config.
*/}}
{{- define "buildkit.configMapName" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- printf "%s-config" (include "buildkit.daemonFullname" (list $root $daemon)) }}
{{- end }}

{{/*
Whether hive postgres init container is required.
*/}}
{{- define "buildkit.hivePostgresInit" -}}
{{- $daemon := . }}
{{- $cfg := $daemon.config | default dict }}
{{- $sec := $daemon.secrets | default dict }}
{{- $pg := $sec.postgres | default dict }}
{{- if and (eq ($daemon.variant | default "buildkit") "hive") $pg.enabled $pg.existingSecret (not $cfg.existingConfigMap) }}
true
{{- end }}
{{- end }}

{{/*
Server TLS secret name (chart-created or existing).
*/}}
{{- define "buildkit.tlsServerSecretName" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $server := ($daemon.tls | default dict).server | default dict }}
{{- if $server.existingSecret }}
{{- $server.existingSecret }}
{{- else }}
{{- printf "%s-server-certs" (include "buildkit.daemonFullname" (list $root $daemon)) }}
{{- end }}
{{- end }}

{{/*
Client TLS secret name for NOTES.
*/}}
{{- define "buildkit.tlsClientSecretName" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $client := ($daemon.tls | default dict).client | default dict }}
{{- if $client.existingSecret }}
{{- $client.existingSecret }}
{{- else }}
{{- printf "%s-client-certs" (include "buildkit.daemonFullname" (list $root $daemon)) }}
{{- end }}
{{- end }}

{{/*
Metrics enabled for daemon (global + per-daemon override).
*/}}
{{- define "buildkit.metricsEnabled" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $dm := $daemon.metrics | default dict }}
{{- $enabled := $root.Values.metrics.enabled }}
{{- if hasKey $dm "enabled" }}
{{- $enabled = $dm.enabled }}
{{- end }}
{{- if $enabled }}true{{- end }}
{{- end }}

{{/*
buildkitd container spec.
*/}}
{{- define "buildkit.buildkitdContainer" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $cfg := $daemon.config | default dict }}
{{- $svc := $daemon.service | default dict }}
{{- $tls := $daemon.tls | default dict }}
{{- $server := $tls.server | default dict }}
{{- $sec := $daemon.secrets | default dict }}
{{- $s3 := $sec.s3 | default dict }}
{{- $pg := $sec.postgres | default dict }}
- name: buildkitd
  image: {{ include "buildkit.imageRepository" (list $root $daemon) }}:{{ include "buildkit.imageTag" (list $root $daemon) }}
  imagePullPolicy: {{ include "buildkit.imagePullPolicy" (list $root $daemon) }}
  args:
    {{- if include "buildkit.needsConfig" $daemon }}
    - --config
    - {{ default "/etc/buildkit/buildkitd.toml" $cfg.mountPath }}
    {{- end }}
    - --addr
    - unix:///run/buildkit/buildkitd.sock
    {{- if $svc.enabled }}
    - --addr
    - tcp://0.0.0.0:{{ default 1234 $svc.port }}
    {{- end }}
    {{- if $server.enabled }}
    - --tlscacert
    - {{ default "/certs" $server.mountPath }}/ca.pem
    - --tlscert
    - {{ default "/certs" $server.mountPath }}/cert.pem
    - --tlskey
    - {{ default "/certs" $server.mountPath }}/key.pem
    {{- end }}
    {{- if $daemon.rootless }}
    - --oci-worker-no-process-sandbox
    {{- end }}
    {{- with $daemon.args }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- $s3env := and (eq ($daemon.variant | default "buildkit") "hive") $s3.enabled $s3.existingSecret (default true $s3.mountAsEnv) }}
  {{- if or $daemon.env $s3env }}
  env:
    {{- if $s3env }}
    {{- range $envName, $secretKey := ($s3.secretKeys | default dict) }}
    {{- if $secretKey }}
    - name: {{ $envName }}
      valueFrom:
        secretKeyRef:
          name: {{ $s3.existingSecret }}
          key: {{ $secretKey }}
    {{- end }}
    {{- end }}
    {{- end }}
    {{- with $daemon.env }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
  ports:
    {{- if $svc.enabled }}
    - name: buildkit
      containerPort: {{ default 1234 $svc.port }}
      protocol: TCP
    {{- end }}
  {{- with $daemon.livenessProbe }}
  livenessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $daemon.readinessProbe }}
  readinessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  securityContext:
    {{- if $daemon.rootless }}
    runAsUser: 1000
    runAsGroup: 1000
    seccompProfile:
      type: Unconfined
    appArmorProfile:
      type: Unconfined
    {{- else }}
    privileged: true
    {{- end }}
  {{- with $daemon.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- else }}
  resources: {}
  {{- end }}
  volumeMounts:
    - name: buildkit-socket
      mountPath: /run/buildkit
    - name: buildkitd-storage
      mountPath: {{ include "buildkit.storageMountPath" $daemon }}
    {{- if include "buildkit.needsConfig" $daemon }}
    - name: buildkitd-config
      mountPath: {{ dir (default "/etc/buildkit/buildkitd.toml" $cfg.mountPath) }}
      subPath: {{ base (default "/etc/buildkit/buildkitd.toml" $cfg.mountPath) }}
      readOnly: true
    {{- end }}
    {{- if $server.enabled }}
    - name: buildkitd-server-tls
      mountPath: {{ default "/certs" $server.mountPath }}
      readOnly: true
    {{- end }}
    {{- if and (eq ($daemon.variant | default "buildkit") "hive") $pg.enabled $pg.existingSecret }}
    - name: buildkit-postgres-secret
      mountPath: {{ default "/etc/buildkit/secrets/postgres" $pg.mountPath }}
      readOnly: true
    {{- end }}
    {{- with $daemon.extraVolumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}

{{/*
Metrics agent sidecar container.
*/}}
{{- define "buildkit.metricsAgentContainer" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $metrics := $root.Values.metrics }}
{{- $dm := $daemon.metrics | default dict }}
{{- if hasKey $dm "port" }}
{{- $metrics = merge $metrics (dict "port" $dm.port) }}
{{- end }}
- name: buildkit-metrics-agent
  image: {{ $metrics.image.repository }}:{{ $metrics.image.tag }}
  imagePullPolicy: {{ $metrics.image.pullPolicy }}
  env:
    - name: BUILDKIT_ADDR
      value: unix:///run/buildkit/buildkitd.sock
    - name: METRICS_ADDR
      value: {{ printf "0.0.0.0:%v" $metrics.port | quote }}
    - name: SCRAPE_INTERVAL_SECS
      value: {{ $metrics.scrapeIntervalSecs | quote }}
    {{- with $dm.env }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  ports:
    - name: metrics
      containerPort: {{ $metrics.port }}
      protocol: TCP
  livenessProbe:
    httpGet:
      path: /metrics
      port: metrics
    initialDelaySeconds: 10
    periodSeconds: 30
  readinessProbe:
    httpGet:
      path: /metrics
      port: metrics
    initialDelaySeconds: 10
    periodSeconds: 15
  {{- if $daemon.rootless }}
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
  {{- end }}
  {{- with $metrics.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- else }}
  resources: {}
  {{- end }}
  volumeMounts:
    - name: buildkit-socket
      mountPath: /run/buildkit
{{- end }}

{{/*
Hive postgres DSN init container.
*/}}
{{- define "buildkit.hiveInitContainer" -}}
{{- $daemon := . }}
{{- $cfg := $daemon.config | default dict }}
{{- $pg := ($daemon.secrets | default dict).postgres | default dict }}
{{- $mountPath := default "/etc/buildkit/buildkitd.toml" $cfg.mountPath }}
{{- $cmKey := default "buildkitd.toml" $cfg.configMapKey }}
{{- $dsnKey := default "dsn" (($pg.secretKeys | default dict).dsn) }}
- name: config-merge
  image: busybox:1.36
  command:
    - sh
    - -ec
    - |
      DSN=$(cat {{ default "/etc/buildkit/secrets/postgres" $pg.mountPath }}/{{ $dsnKey }})
      cp /config-base/{{ $cmKey }} /config-out/{{ base $mountPath }}
      if grep -q '^[[:space:]]*postgresDSN[[:space:]]*=' /config-out/{{ base $mountPath }}; then
        sed -i "s|^[[:space:]]*postgresDSN[[:space:]]*=.*|postgresDSN = \"${DSN}\"|" /config-out/{{ base $mountPath }}
      else
        printf '\npostgresDSN = "%s"\n' "${DSN}" >> /config-out/{{ base $mountPath }}
      fi
  volumeMounts:
    - name: buildkitd-config-base
      mountPath: /config-base
      readOnly: true
    - name: buildkit-postgres-secret
      mountPath: {{ default "/etc/buildkit/secrets/postgres" $pg.mountPath }}
      readOnly: true
    - name: buildkitd-config
      mountPath: {{ dir $mountPath }}
{{- end }}

{{/*
Pod spec volumes for a daemon.
*/}}
{{- define "buildkit.podVolumes" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $mode := index . 2 }}
{{- $cfg := $daemon.config | default dict }}
{{- $stor := $daemon.storage | default dict }}
{{- $tls := $daemon.tls | default dict }}
{{- $server := $tls.server | default dict }}
{{- $pg := ($daemon.secrets | default dict).postgres | default dict }}
- name: buildkit-socket
  emptyDir: {}
{{- if include "buildkit.hivePostgresInit" $daemon }}
- name: buildkitd-config-base
  configMap:
    name: {{ include "buildkit.configMapName" (list $root $daemon) }}
- name: buildkitd-config
  emptyDir: {}
{{- else if include "buildkit.needsConfig" $daemon }}
- name: buildkitd-config
  {{- if $cfg.existingConfigMap }}
  configMap:
    name: {{ $cfg.existingConfigMap }}
  {{- else }}
  configMap:
    name: {{ include "buildkit.configMapName" (list $root $daemon) }}
  {{- end }}
{{- end }}
{{- if $server.enabled }}
- name: buildkitd-server-tls
  secret:
    secretName: {{ include "buildkit.tlsServerSecretName" (list $root $daemon) }}
    items:
      - key: {{ ($server.secretKeys | default dict).ca | default "ca.pem" }}
        path: ca.pem
      - key: {{ ($server.secretKeys | default dict).cert | default "cert.pem" }}
        path: cert.pem
      - key: {{ ($server.secretKeys | default dict).key | default "key.pem" }}
        path: key.pem
{{- end }}
{{- if and (eq ($daemon.variant | default "buildkit") "hive") $pg.enabled $pg.existingSecret }}
- name: buildkit-postgres-secret
  secret:
    secretName: {{ $pg.existingSecret }}
{{- end }}
{{- if eq ($stor.type | default "emptyDir") "pvc" }}
{{- if ne $mode "statefulset" }}
- name: buildkitd-storage
  {{- $pvc := $stor.pvc | default dict }}
  {{- if $pvc.existingClaim }}
  persistentVolumeClaim:
    claimName: {{ $pvc.existingClaim }}
  {{- else }}
  persistentVolumeClaim:
    claimName: {{ include "buildkit.daemonFullname" (list $root $daemon) }}-storage
  {{- end }}
{{- end }}
{{- else if eq $stor.type "hostPath" }}
- name: buildkitd-storage
  hostPath:
    path: {{ ($stor.hostPath | default dict).path | default "/var/lib/buildkit" }}
    type: {{ default "DirectoryOrCreate" ($stor.hostPath | default dict).type }}
{{- else }}
- name: buildkitd-storage
  {{- if $stor.emptyDir }}
  emptyDir:
    {{- toYaml $stor.emptyDir | nindent 4 }}
  {{- else }}
  emptyDir: {}
  {{- end }}
{{- end }}
{{- with $daemon.extraVolumes }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
StatefulSet volumeClaimTemplates when using PVC.
*/}}
{{- define "buildkit.volumeClaimTemplates" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $stor := $daemon.storage | default dict }}
{{- $pvc := $stor.pvc | default dict }}
{{- if and (eq ($stor.type | default "emptyDir") "pvc") (not $pvc.existingClaim) }}
- metadata:
    name: buildkitd-storage
  spec:
    accessModes:
      {{- toYaml (default (list "ReadWriteOnce") $pvc.accessModes) | nindent 6 }}
    resources:
      requests:
        storage: {{ default "50Gi" $pvc.size }}
    {{- if $pvc.storageClassName }}
    storageClassName: {{ $pvc.storageClassName }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Shared pod template metadata and spec.
*/}}
{{- define "buildkit.podTemplateLabels" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- include "buildkit.labels" (list $root $daemon) }}
{{- end }}

{{- define "buildkit.podTemplate" -}}
{{- $root := index . 0 }}
{{- $daemon := index . 1 }}
{{- $mode := index . 2 }}
serviceAccountName: {{ include "buildkit.serviceAccountName" $root }}
{{- with $root.Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with (include "buildkit.nodeSelector" $daemon) }}
nodeSelector:
  {{- . | nindent 2 }}
{{- end }}
{{- with $daemon.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $daemon.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if include "buildkit.hivePostgresInit" $daemon }}
initContainers:
  {{- include "buildkit.hiveInitContainer" $daemon | nindent 2 }}
{{- end }}
containers:
  {{- include "buildkit.buildkitdContainer" (list $root $daemon) | nindent 2 }}
    {{- if include "buildkit.metricsEnabled" (list $root $daemon) }}
  {{- include "buildkit.metricsAgentContainer" (list $root $daemon) | nindent 2 }}
  {{- end }}
volumes:
  {{- include "buildkit.podVolumes" (list $root $daemon $mode) | nindent 2 }}
{{- end }}

{{/*
Merged nodeSelector with arch.
*/}}
{{- define "buildkit.nodeSelector" -}}
{{- $daemon := . }}
{{- $sel := dict }}
{{- if $daemon.nodeSelector }}
{{- $sel = merge $sel $daemon.nodeSelector }}
{{- end }}
{{- if $daemon.arch }}
{{- $_ := set $sel "kubernetes.io/arch" $daemon.arch }}
{{- end }}
{{- if $sel }}
{{- toYaml $sel }}
{{- end }}
{{- end }}
