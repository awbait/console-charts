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
