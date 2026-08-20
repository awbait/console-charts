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
