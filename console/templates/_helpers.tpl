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
{{- if or .Values.trustedCA.existingConfigMaps .Values.trustedCA.certs -}}
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
A projected volume, so certificates coming from several ConfigMaps end up in one
directory. Keys must not collide: kubelet refuses to mount two sources under the
same file name.
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
      - configMap:
          name: {{ . }}
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
