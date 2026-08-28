{{/*
Base chart name (respecting nameOverride).
*/}}
{{- define "console.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full release name. fullnameOverride takes precedence; otherwise release-name +
chart name (without doubling if release already contains the name).
*/}}
{{- define "console.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Value for the helm.sh/chart label.
*/}}
{{- define "console.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Component names.
*/}}
{{- define "console.portal.fullname" -}}
{{- printf "%s-portal" (include "console.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "console.collector.fullname" -}}
{{- printf "%s-collector" (include "console.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Portal Secret name: external (existingSecret) or generated.
*/}}
{{- define "console.portal.secretName" -}}
{{- if .Values.portal.existingSecret -}}
{{- .Values.portal.existingSecret -}}
{{- else -}}
{{- printf "%s-secrets" (include "console.portal.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Collector Secret name: external (existingSecret) or generated.
*/}}
{{- define "console.collector.secretName" -}}
{{- if .Values.collector.existingSecret -}}
{{- .Values.collector.existingSecret -}}
{{- else -}}
{{- printf "%s-secrets" (include "console.collector.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Whether a component's Secret is filled by the External Secrets Operator instead
of from values. Empty output means "no" - templates test it with `if`, so keep
it emitting nothing rather than "false". Parameter: the component values block.
*/}}
{{- define "console.externalSecret.enabled" -}}
{{- if (.externalSecret | default dict).enabled -}}
true
{{- end -}}
{{- end -}}

{{/*
Whether a component renders a Secret of its own. It does not when the Secret is
somebody else's (existingSecret) or the operator's (externalSecret).
Parameter: the component values block.
*/}}
{{- define "console.ownSecret.enabled" -}}
{{- if and (not .existingSecret) (not (include "console.externalSecret.enabled" .)) -}}
true
{{- end -}}
{{- end -}}

{{/*
ExternalSecret for one component: the same Secret its Deployment mounts, filled
by the External Secrets Operator from Vault rather than written into values.
The chart holds no secret in this mode - only the address of the store and which
paths to read. Parameters (dict):
  .root      - the chart context
  .component - .Values.portal or .Values.collector
  .name      - "portal" or "collector", for the Secret name and the labels
*/}}
{{- define "console.externalSecret" -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $es := .component.externalSecret | default dict -}}
{{- $ref := $es.secretStoreRef | default dict -}}
{{- $target := include (printf "console.%s.secretName" $name) $root -}}
apiVersion: {{ $es.apiVersion | default "external-secrets.io/v1" }}
kind: ExternalSecret
metadata:
  name: {{ $target }}
  labels:
    {{- include "console.labels" $root | nindent 4 }}
    {{- include (printf "console.%s.selectorLabels" $name) $root | nindent 4 }}
spec:
  refreshInterval: {{ $es.refreshInterval | default "1h" | quote }}
  secretStoreRef:
    name: {{ required (printf "%s.externalSecret.secretStoreRef.name is required - the SecretStore that points at Vault" $name) $ref.name | quote }}
    kind: {{ $ref.kind | default "SecretStore" }}
  target:
    name: {{ $target }}
    creationPolicy: {{ $es.creationPolicy | default "Owner" }}
    {{- with $es.template }}
    template:
      {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- with $es.dataFrom }}
  dataFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $es.data }}
  data:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}

{{/*
Invariants of the external-secret mode. Parameters (dict):
  .component - .Values.portal or .Values.collector
  .name      - "portal" or "collector", for the message
*/}}
{{- define "console.externalSecret.validate" -}}
{{- $name := .name -}}
{{- $es := .component.externalSecret | default dict -}}
{{- if $es.enabled -}}
{{- if .component.existingSecret -}}
{{- fail (printf "console: %s.existingSecret and %s.externalSecret.enabled are two answers to the same question - keep one of them" $name $name) -}}
{{- end -}}
{{- if and (not $es.data) (not $es.dataFrom) -}}
{{- fail (printf "console: %s.externalSecret needs data or dataFrom - with neither, the operator creates an empty Secret and the pod starts without the values it cannot run without" $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Invariants of running more than one portal. The replicas share a Redis: the
events that keep an open page current travel through it, and so does the lease
that decides which replica runs the background loops. Without it every replica
would reconcile in parallel, asking GitLab and Argo CD the same questions and
racing each other writing the answers back.

The same applies to autoscaling, which is only a second replica arriving on its
own. Both need a portal that knows how to share (app 0.10.0 and newer).
*/}}
{{- define "console.portal.validateScale" -}}
{{- $portal := .Values.portal -}}
{{- $auto := $portal.autoscaling | default dict -}}
{{- $replicas := $portal.replicaCount | default 1 | int -}}
{{- if or $auto.enabled (gt $replicas 1) -}}
{{- if ne (($portal.config).CACHE | toString) "redis" -}}
{{- fail "console: more than one portal replica requires portal.config.CACHE=redis - with the in-memory cache each replica keeps its own sessions, hears none of the others' events and runs the background loops on its own" -}}
{{- end -}}
{{- end -}}
{{- if $auto.enabled -}}
{{- $min := $auto.minReplicas | default 1 | int -}}
{{- $max := $auto.maxReplicas | default 1 | int -}}
{{- if lt $min 1 -}}
{{- fail (printf "console: portal.autoscaling.minReplicas must be at least 1, got %d" $min) -}}
{{- end -}}
{{- if lt $max $min -}}
{{- fail (printf "console: portal.autoscaling.maxReplicas (%d) must not be below minReplicas (%d)" $max $min) -}}
{{- end -}}
{{- if not (or $auto.targetCPUUtilizationPercentage $auto.targetMemoryUtilizationPercentage) -}}
{{- fail "console: portal.autoscaling needs targetCPUUtilizationPercentage or targetMemoryUtilizationPercentage - an autoscaler with no metric never scales" -}}
{{- end -}}
{{- if and $auto.targetCPUUtilizationPercentage (not (dig "requests" "cpu" "" ($portal.resources | default dict))) -}}
{{- fail "console: portal.autoscaling scales on CPU, which is a percentage of portal.resources.requests.cpu - set the request or drop targetCPUUtilizationPercentage" -}}
{{- end -}}
{{- if and $auto.targetMemoryUtilizationPercentage (not (dig "requests" "memory" "" ($portal.resources | default dict))) -}}
{{- fail "console: portal.autoscaling scales on memory, which is a percentage of portal.resources.requests.memory - set the request or drop targetMemoryUtilizationPercentage" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Portal ServiceAccount name.
*/}}
{{- define "console.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "console.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Collector ServiceAccount name (separate SA: it needs read-only RBAC on the cluster).
*/}}
{{- define "console.collector.serviceAccountName" -}}
{{- if .Values.collector.serviceAccount.create -}}
{{- default (include "console.collector.fullname" .) .Values.collector.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.collector.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Trusted CA: extra root certificates for upstreams behind a private CA (Keycloak,
Argo CD, GitLab, Harbor). Empty output means "not configured" - the templates
test it with `if`, so keep it emitting nothing rather than "false".
*/}}
{{- define "console.trustedCA.enabled" -}}
{{- if or .Values.trustedCA.existingConfigMaps .Values.trustedCA.existingSecrets .Values.trustedCA.certs -}}
true
{{- end -}}
{{- end -}}

{{/*
Name of the ConfigMap rendered from trustedCA.certs. Existing ConfigMaps keep
their own names and are mounted alongside it.
*/}}
{{- define "console.trustedCA.configMapName" -}}
{{- printf "%s-trusted-ca" (include "console.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Own directory, never a subPath into /etc/ssl/certs: mounting over that directory
would hide the public bundle shipped in the image.
*/}}
{{- define "console.trustedCA.mountPath" -}}
/etc/ssl/certs/extra
{{- end -}}

{{/*
One projected source. Parameters (dict):
  .kind - "configMap" or "secret"
  .item - either a plain name, or a map with .name and an optional .keys map
          (key in the object -> file name in the directory)
*/}}
{{- define "console.trustedCA.projectedSource" -}}
{{- $kind := .kind -}}
{{- $item := .item -}}
{{- if kindIs "string" $item -}}
- {{ $kind }}:
    name: {{ $item }}
{{- else -}}
- {{ $kind }}:
    name: {{ $item.name }}
    {{- with $item.keys }}
    items:
      {{- range $key, $path := . }}
      - key: {{ $key }}
        path: {{ $path }}
      {{- end }}
    {{- end }}
{{- end -}}
{{- end -}}

{{/*
A projected volume, so certificates coming from several ConfigMaps and Secrets
end up in one directory. File names must not collide: kubelet refuses to mount
two sources under the same name.
*/}}
{{- define "console.trustedCA.volume" -}}
- name: trusted-ca
  projected:
    sources:
      {{- if .Values.trustedCA.certs }}
      - configMap:
          name: {{ include "console.trustedCA.configMapName" . }}
      {{- end }}
      {{- range .Values.trustedCA.existingConfigMaps }}
      {{- include "console.trustedCA.projectedSource" (dict "kind" "configMap" "item" .) | nindent 6 }}
      {{- end }}
      {{- range .Values.trustedCA.existingSecrets }}
      {{- include "console.trustedCA.projectedSource" (dict "kind" "secret" "item" .) | nindent 6 }}
      {{- end }}
{{- end -}}

{{- define "console.trustedCA.volumeMount" -}}
- name: trusted-ca
  mountPath: {{ include "console.trustedCA.mountPath" . }}
  readOnly: true
{{- end -}}

{{/*
Go reads SSL_CERT_DIR as a colon-separated list and scans every entry, so the
system directory stays in the list and the extra roots are added to it.
*/}}
{{- define "console.trustedCA.env" -}}
- name: SSL_CERT_DIR
  value: "/etc/ssl/certs:{{ include "console.trustedCA.mountPath" . }}"
{{- end -}}

{{/*
GOMEMLIMIT: goRuntime.memLimitPercent of the container memory limit, in MiB.
The downward API cannot scale a value, so the quantity is parsed here - and the
percentage matters: at 100% the collector fights the limit instead of leaving
the runtime room to release memory before the kernel kills the container.
Parameters are the same dict as console.componentEnv. Renders nothing when no
memory limit is set or the percentage is zero.
*/}}
{{- define "console.goMemLimit" -}}
{{- $root := .root -}}
{{- $pct := $root.Values.goRuntime.memLimitPercent | default 0 | float64 -}}
{{- $limit := dig "limits" "memory" "" (.component.resources | default dict) | toString -}}
{{- if and $limit (gt $pct 0.0) -}}
{{- $number := regexFind "^[0-9]+(\\.[0-9]+)?" $limit -}}
{{- $unit := regexFind "[A-Za-z]*$" $limit -}}
{{- $units := dict "" 1.0 "k" 1000.0 "K" 1000.0 "M" 1000000.0 "G" 1000000000.0 "T" 1000000000000.0 "Ki" 1024.0 "Mi" 1048576.0 "Gi" 1073741824.0 "Ti" 1099511627776.0 -}}
{{- if or (not $number) (not (hasKey $units $unit)) -}}
{{- fail (printf "console: cannot read the memory limit %q - set goRuntime.memLimitPercent to 0 to skip GOMEMLIMIT" $limit) -}}
{{- end -}}
{{- $mib := divf (mulf (float64 $number) (get $units $unit) $pct 0.01) 1048576.0 | floor | int64 -}}
{{- if lt $mib 1 -}}
{{- $mib = 1 -}}
{{- end -}}
{{- printf "%dMiB" $mib -}}
{{- end -}}
{{- end -}}

{{/*
Every env var of a component: the trusted-CA path, GOMAXPROCS and GOMEMLIMIT
derived from the container limits, and whatever extraEnv adds. Parameters (dict):
  .root      - the chart context
  .component - .Values.portal or .Values.collector

Without GOMAXPROCS the Go runtime sizes itself by the node's CPU count and gets
throttled against a much smaller limit. The downward API rounds the limit up to
a whole core, so it is only rendered where a CPU limit exists - otherwise the
field would silently resolve to the node's allocatable CPU.
*/}}
{{- define "console.componentEnv" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- if include "console.trustedCA.enabled" $root }}
{{- include "console.trustedCA.env" $root }}
{{- end }}
{{- if and $root.Values.goRuntime.maxProcsFromLimits (dig "limits" "cpu" "" ($component.resources | default dict)) }}
- name: GOMAXPROCS
  valueFrom:
    resourceFieldRef:
      resource: limits.cpu
      divisor: "1"
{{- end }}
{{- with include "console.goMemLimit" (dict "root" $root "component" $component) }}
- name: GOMEMLIMIT
  value: {{ . | quote }}
{{- end }}
{{- with $component.extraEnv }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "console.labels" -}}
helm.sh/chart: {{ include "console.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: console
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end -}}

{{/*
Component selector labels (stable across releases of the same version).
*/}}
{{- define "console.portal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "console.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: portal
{{- end -}}

{{- define "console.collector.selectorLabels" -}}
app.kubernetes.io/name: {{ include "console.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: collector
{{- end -}}

{{/*
Build the image reference: [registry/]repository:tag. Parameters (dict):
  .image  - map with repository/tag/pullPolicy
  .registry - global registry prefix (may be empty)
  .defaultTag - default tag (usually .Chart.AppVersion)
*/}}
{{- define "console.image" -}}
{{- $tag := .image.tag | default .defaultTag -}}
{{- if .registry -}}
{{- printf "%s/%s:%s" .registry .image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" .image.repository $tag -}}
{{- end -}}
{{- end -}}
