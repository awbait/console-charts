{{/*
Chart name for helm.sh/chart.
*/}}
{{- define "waypoint.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base application name (for labels) = projectTag.
*/}}
{{- define "waypoint.helpers.app.name" -}}
{{- required "naming.projectTag is required" (.Values.naming | default dict).projectTag | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
DNS tag validation (instanceTag, clusterTag). Parameters: .label, .value.
Returns the value in lower-case.
*/}}
{{- define "waypoint.helpers.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Short 2..6-character DNS tag validation (projectTag, name).
Parameters: .label, .value. Returns the value in lower-case.
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
Resource name by convention:
  {instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
Parameters: .context, .kindShort (wp), .name (2..6 characters).
The result is truncated to 63 characters. Example: ru1-k8s1-wp-nbox-mesh.
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
Selector labels - stable identification of chart resources.
*/}}
{{- define "waypoint.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "waypoint.helpers.app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "waypoint.helpers.app.name" . }}
{{- end -}}

{{/*
Standard labels: selector + chart/managed-by/version + generic.labels.
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
Common annotations (generic.annotations). Empty -> outputs nothing.
*/}}
{{- define "waypoint.helpers.app.genericAnnotations" -}}
{{- with (.Values.generic | default dict).annotations -}}
{{ include "waypoint.helpers.tplvalues.render" (dict "value" . "context" $) }}
{{- end -}}
{{- end -}}

{{/*
Entity enabled flag (enabled). Parameter: entity (map).
Correctly honors an explicit enabled: false (unlike `| default true`).
enabled missing -> "true"; enabled: false -> "" (disabled); otherwise by value.
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
Validation of the istio.io/waypoint-for value. Parameter: value.
Allowed: service (default) | workload | all.
*/}}
{{- define "waypoint.helpers.app.for" -}}
{{- $value := . | default "service" | toString | lower -}}
{{- if not (has $value (list "service" "workload" "all")) -}}
{{- fail (printf "waypoints[].for must be one of service|workload|all, got %q" $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Generic rendering of templated values. Parameters: .value, .context.
*/}}
{{- define "waypoint.helpers.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
