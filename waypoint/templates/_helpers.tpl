{{/*
Имя чарта для helm.sh/chart.
*/}}
{{- define "waypoint.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Базовое имя приложения (для labels) = projectTag.
*/}}
{{- define "waypoint.helpers.app.name" -}}
{{- required "naming.projectTag is required" (.Values.naming | default dict).projectTag | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Валидация DNS-тега (instanceTag, clusterTag). Параметры: .label, .value.
Возвращает значение в lower-case.
*/}}
{{- define "waypoint.helpers.tag" -}}
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
{{- define "waypoint.helpers.shortToken" -}}
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
Имя ресурса по конвенции:
  {instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
Параметры: .context, .kindShort (wp), .name (2..6 символов).
Итог обрезается до 63 символов. Пример: ru1-k8s1-wp-nbox-mesh.
*/}}
{{- define "waypoint.helpers.app.resourceName" -}}
{{- $naming := .context.Values.naming | default dict -}}
{{- $instance := include "waypoint.helpers.tag" (dict "label" "naming.instanceTag" "value" $naming.instanceTag) -}}
{{- $cluster := include "waypoint.helpers.tag" (dict "label" "naming.clusterTag" "value" $naming.clusterTag) -}}
{{- $project := include "waypoint.helpers.shortToken" (dict "label" "naming.projectTag" "value" $naming.projectTag) -}}
{{- $kind := required "kindShort is required" .kindShort | toString | lower -}}
{{- if not (has $kind (list "wp")) -}}
{{- fail (printf "kindShort must be one of wp, got %q" $kind) -}}
{{- end -}}
{{- $name := include "waypoint.helpers.shortToken" (dict "label" "name" "value" .name) -}}
{{- printf "%s-%s-%s-%s-%s" $instance $cluster $kind $project $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels — стабильная идентификация ресурсов чарта.
*/}}
{{- define "waypoint.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "waypoint.helpers.app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "waypoint.helpers.app.name" . }}
{{- end -}}

{{/*
Стандартные labels: selector + chart/managed-by/version + generic.labels.
*/}}
{{- define "waypoint.helpers.app.labels" -}}
{{ include "waypoint.helpers.app.selectorLabels" . }}
helm.sh/chart: {{ include "waypoint.helpers.app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- with (.Values.generic | default dict).labels }}
{{ include "waypoint.helpers.tplvalues.render" (dict "value" . "context" $) }}
{{- end }}
{{- end -}}

{{/*
Общие annotations (generic.annotations). Пусто → ничего не выводит.
*/}}
{{- define "waypoint.helpers.app.genericAnnotations" -}}
{{- with (.Values.generic | default dict).annotations -}}
{{ include "waypoint.helpers.tplvalues.render" (dict "value" . "context" $) }}
{{- end -}}
{{- end -}}

{{/*
Признак включённости сущности (enabled). Параметр: entity (map).
Корректно учитывает явный enabled: false (в отличие от `| default true`).
enabled отсутствует → "true"; enabled: false → "" (выключено); иначе по значению.
*/}}
{{- define "waypoint.helpers.app.enabled" -}}
{{- $entity := . | default dict -}}
{{- if hasKey $entity "enabled" -}}
{{- ternary "true" "" (eq (toString $entity.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Валидация значения istio.io/waypoint-for. Параметр: value.
Допустимо: service (default) | workload | all.
*/}}
{{- define "waypoint.helpers.app.for" -}}
{{- $value := . | default "service" | toString | lower -}}
{{- if not (has $value (list "service" "workload" "all")) -}}
{{- fail (printf "waypoints[].for must be one of service|workload|all, got %q" $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Универсальный рендеринг шаблонных значений. Параметры: .value, .context.
*/}}
{{- define "waypoint.helpers.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
