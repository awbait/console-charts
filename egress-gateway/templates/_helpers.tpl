{{/*
Имя чарта для helm.sh/chart.
*/}}
{{- define "egress-gateway.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Базовое имя приложения (для labels) = projectTag.
*/}}
{{- define "egress-gateway.helpers.app.name" -}}
{{- required "naming.projectTag is required" (.Values.naming | default dict).projectTag | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Валидация DNS-тега (instanceTag, clusterTag). Параметры: .label, .value.
Возвращает значение в lower-case.
*/}}
{{- define "egress-gateway.helpers.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Валидация короткого 2..6-символьного DNS-тега (projectTag, name).
Параметры: .label, .value. Возвращает значение в lower-case.
*/}}
{{- define "egress-gateway.helpers.shortToken" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if or (lt (len $value) 2) (gt (len $value) 6) -}}
{{- fail (printf "%s must be 2..6 characters, got %q" .label $value) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Полное имя ресурса по конвенции:
  без parent: {instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
  с parent:   {instanceTag}-{clusterTag}-{kindShort}-{parent}-{projectTag}-{name}
Параметры: .context, .kindShort (igw|egw|veg), .name (2..6 символов),
           .parent (опц., имя родительского Gateway, 2..6 символов; для TLSRoute).
*/}}
{{- define "egress-gateway.helpers.app.fullname" -}}
{{- $naming := .context.Values.naming | default dict -}}
{{- $instance := include "egress-gateway.helpers.tag" (dict "label" "naming.instanceTag" "value" $naming.instanceTag) -}}
{{- $cluster := include "egress-gateway.helpers.tag" (dict "label" "naming.clusterTag" "value" $naming.clusterTag) -}}
{{- $project := include "egress-gateway.helpers.shortToken" (dict "label" "naming.projectTag" "value" $naming.projectTag) -}}
{{- $kind := required "kindShort is required" .kindShort | toString | lower -}}
{{- if not (has $kind (list "igw" "egw" "veg")) -}}
{{- fail (printf "kindShort must be one of igw|egw|veg, got %q" $kind) -}}
{{- end -}}
{{- $name := include "egress-gateway.helpers.shortToken" (dict "label" "name" "value" .name) -}}
{{- if .parent -}}
{{- $parent := include "egress-gateway.helpers.shortToken" (dict "label" "parentGatewayName" "value" .parent) -}}
{{- printf "%s-%s-%s-%s-%s-%s" $instance $cluster $kind $parent $project $name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s-%s-%s-%s" $instance $cluster $kind $project $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Selector labels — стабильная идентификация workload.
*/}}
{{- define "egress-gateway.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "egress-gateway.helpers.app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "egress-gateway.helpers.app.name" . }}
{{- end -}}

{{/*
Стандартные labels: selector + chart/managed-by/version + generic.labels.
*/}}
{{- define "egress-gateway.helpers.app.labels" -}}
{{ include "egress-gateway.helpers.app.selectorLabels" . }}
helm.sh/chart: {{ include "egress-gateway.helpers.app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- with (.Values.generic | default dict).labels }}
{{ include "egress-gateway.helpers.tplvalues.render" (dict "value" . "context" $) }}
{{- end }}
{{- end -}}

{{/*
Общие annotations (generic.annotations). Пусто → ничего не выводит.
*/}}
{{- define "egress-gateway.helpers.app.genericAnnotations" -}}
{{- with (.Values.generic | default dict).annotations -}}
{{ include "egress-gateway.helpers.tplvalues.render" (dict "value" . "context" $) }}
{{- end -}}
{{- end -}}

{{/*
Универсальный рендеринг шаблонных значений. Параметры: .value, .context.
*/}}
{{- define "egress-gateway.helpers.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
