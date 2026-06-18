{{/*
Базовое имя чарта (с учётом nameOverride).
*/}}
{{- define "console.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Полное имя релиза. fullnameOverride имеет приоритет; иначе release-name +
имя чарта (без удвоения, если release уже содержит имя).
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
Значение для метки helm.sh/chart.
*/}}
{{- define "console.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Имена компонентов.
*/}}
{{- define "console.portal.fullname" -}}
{{- printf "%s-portal" (include "console.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Имя Secret портала: внешний (existingSecret) либо генерируемый.
*/}}
{{- define "console.portal.secretName" -}}
{{- if .Values.portal.existingSecret -}}
{{- .Values.portal.existingSecret -}}
{{- else -}}
{{- printf "%s-secrets" (include "console.portal.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Имя ServiceAccount.
*/}}
{{- define "console.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "console.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Общие метки.
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
Selector-метки компонентов (стабильны между релизами одной версии).
*/}}
{{- define "console.portal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "console.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: portal
{{- end -}}

{{/*
Сборка ссылки на образ: [registry/]repository:tag. Параметры (dict):
  .image  - map с repository/tag/pullPolicy
  .registry - глобальный префикс реестра (может быть пустым)
  .defaultTag - tag по умолчанию (обычно .Chart.AppVersion)
*/}}
{{- define "console.image" -}}
{{- $tag := .image.tag | default .defaultTag -}}
{{- if .registry -}}
{{- printf "%s/%s:%s" .registry .image.repository $tag -}}
{{- else -}}
{{- printf "%s:%s" .image.repository $tag -}}
{{- end -}}
{{- end -}}
