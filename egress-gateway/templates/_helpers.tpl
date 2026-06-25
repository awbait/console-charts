{{/*
Chart name for helm.sh/chart.
*/}}
{{- define "egress-gateway.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base application name (for labels) = projectTag.
*/}}
{{- define "egress-gateway.helpers.app.name" -}}
{{- required "naming.projectTag is required" (.Values.naming | default dict).projectTag | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
DNS tag validation (instanceTag, clusterTag). Params: .label, .value.
Returns the value in lower-case.
*/}}
{{- define "egress-gateway.helpers.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Short 2..6-character DNS tag validation (projectTag, name).
Params: .label, .value. Returns the value in lower-case.
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
Full resource name by convention:
  without parent: {instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
  with parent:    {instanceTag}-{clusterTag}-{kindShort}-{parent}-{projectTag}-{name}
Params: .context, .kindShort (igw|egw|veg), .name (2..6 characters),
        .parent (optional, parent Gateway name, 2..6 characters; for TLSRoute).
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
Selector labels - stable workload identification.
*/}}
{{- define "egress-gateway.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "egress-gateway.helpers.app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "egress-gateway.helpers.app.name" . }}
{{- end -}}

{{/*
Standard labels: selector + chart/managed-by/version + generic.labels.
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
Common annotations (generic.annotations). Empty -> outputs nothing.
*/}}
{{- define "egress-gateway.helpers.app.genericAnnotations" -}}
{{- with (.Values.generic | default dict).annotations -}}
{{ include "egress-gateway.helpers.tplvalues.render" (dict "value" . "context" $) }}
{{- end -}}
{{- end -}}

{{/*
Generic templated-value rendering. Params: .value, .context.
*/}}
{{- define "egress-gateway.helpers.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
