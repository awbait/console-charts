{{/*
Chart name for helm.sh/chart.
*/}}
{{- define "waypoint.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base application name (for labels) = identity.project.
*/}}
{{- define "waypoint.helpers.app.name" -}}
{{- required "identity.project is required" (.Values.identity | default dict).project | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
DNS tag validation (identity.instance, identity.cluster). Parameters: .label, .value.
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
Short DNS tag validation (identity.project, name). Parameters: .label, .value
and the optional bounds .min (default 2) and .max (default 6).
Returns the value in lower-case.
*/}}
{{- define "waypoint.helpers.shortToken" -}}
{{- $min := .min | default 2 | int -}}
{{- $max := .max | default 6 | int -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if or (lt (len $value) $min) (gt (len $value) $max) -}}
{{- fail (printf "%s must be %d..%d characters, got %q" .label $min $max $value) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Resource name by convention:
  {instance}-{cluster}-{kindShort}-{project}-{name}
Parameters: .context, .kindShort (wp), .name (2..6 characters).
The result is truncated to 63 characters. Example: ed-dev-wp-nbox-mesh.
*/}}
{{- define "waypoint.helpers.app.resourceName" -}}
{{- $identity := .context.Values.identity | default dict -}}
{{- $instance := include "waypoint.helpers.tag" (dict "label" "identity.instance" "value" $identity.instance) -}}
{{- $cluster := include "waypoint.helpers.tag" (dict "label" "identity.cluster" "value" $identity.cluster) -}}
{{- $project := include "waypoint.helpers.shortToken" (dict "label" "identity.project" "value" $identity.project "max" 9) -}}
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
app: {{ .Chart.Name }}
{{- end -}}

{{/*
Identity labels: ecpk/instance, ecpk/cluster, ecpk/project.

Each label is rendered only when the matching identity.* value is set, so a
partially filled identity block never produces an empty label value. Values are
lower-cased, exactly as they go into the resource name.
*/}}
{{- define "waypoint.helpers.identityLabels" -}}
{{- $identity := .Values.identity | default dict -}}
{{- with $identity.instance }}
ecpk/instance: {{ . | toString | lower | quote }}
{{- end }}
{{- with $identity.cluster }}
ecpk/cluster: {{ . | toString | lower | quote }}
{{- end }}
{{- with $identity.project }}
ecpk/project: {{ . | toString | lower | quote }}
{{- end }}
{{- end -}}

{{/*
Standard labels: selector + chart/managed-by/version + identity + generic.labels.
*/}}
{{- define "waypoint.helpers.app.labels" -}}
{{ include "waypoint.helpers.app.selectorLabels" . }}
helm.sh/chart: {{ include "waypoint.helpers.app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- include "waypoint.helpers.identityLabels" . }}
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
Common metadata (labels + annotations) for every chart resource. Renders the
full "labels:" block and, only when non-empty, the "annotations:" block, so a
resource wires both in one call and never silently drops generic.* on a new
manifest. Parameters:
  .context     - root context ($), required;
  .labels      - optional dict of extra per-resource labels;
  .annotations - optional dict of extra per-resource annotations.
Call right under metadata.name/namespace:
  {{- include "waypoint.helpers.app.metadata" (dict "context" $root) | nindent 2 }}
*/}}
{{- define "waypoint.helpers.app.metadata" -}}
{{- $ctx := .context -}}
labels:
  {{- include "waypoint.helpers.app.labels" $ctx | nindent 2 }}
  {{- with .labels }}
  {{- include "waypoint.helpers.tplvalues.render" (dict "value" . "context" $ctx) | nindent 2 }}
  {{- end }}
{{- $generic := include "waypoint.helpers.app.genericAnnotations" $ctx | trim -}}
{{- $extra := "" -}}
{{- with .annotations }}{{- $extra = include "waypoint.helpers.tplvalues.render" (dict "value" . "context" $ctx) | trim -}}{{- end -}}
{{- if or $generic $extra }}
annotations:
  {{- with $generic }}
  {{- . | nindent 2 }}
  {{- end }}
  {{- with $extra }}
  {{- . | nindent 2 }}
  {{- end }}
{{- end }}
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
