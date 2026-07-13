{{/*
Chart name and version for the helm.sh/chart label.
*/}}
{{- define "project.helpers.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels: chart identity + generic.labels.
*/}}
{{- define "project.helpers.labels" -}}
helm.sh/chart: {{ include "project.helpers.chart" . }}
app.cpaas.io/name: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $k, $v := (.Values.generic | default dict).labels }}
{{ $k }}: {{ tpl (toString $v) $ | quote }}
{{- end }}
{{- end -}}

{{/*
Common metadata (labels + annotations) for every chart resource. Renders the
full "labels:" block and, only when non-empty, the "annotations:" block, so a
resource wires both in one call and never silently drops generic.* on a new
manifest. Parameters:
  .context     - root context ($), required;
  .labels      - optional dict of extra per-resource labels;
  .annotations - optional dict of extra per-resource annotations.
Call right under metadata.name:
  {{- include "project.helpers.metadata" (dict "context" $) | nindent 2 }}
*/}}
{{- define "project.helpers.metadata" -}}
{{- $ctx := .context -}}
labels:
  {{- include "project.helpers.labels" $ctx | nindent 2 }}
  {{- range $k, $v := .labels }}
  {{ $k }}: {{ tpl (toString $v) $ctx | quote }}
  {{- end }}
{{- $ann := (.context.Values.generic | default dict).annotations | default dict -}}
{{- $extra := .annotations | default dict -}}
{{- if or $ann $extra }}
annotations:
  {{- range $k, $v := $ann }}
  {{ $k }}: {{ tpl (toString $v) $ctx | quote }}
  {{- end }}
  {{- range $k, $v := $extra }}
  {{ $k }}: {{ tpl (toString $v) $ctx | quote }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Validated Project name: required, RFC 1123 DNS-like lowercase, max 63 chars.
Fails the render with a clear message on an invalid value.
*/}}
{{- define "project.helpers.name" -}}
{{- $name := required "project.name is required" .Values.project.name | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name) -}}
{{- fail (printf "project.name must be DNS-like lowercase (RFC 1123), got %q" $name) -}}
{{- end -}}
{{- $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Validated cluster list for spec.clusters. Fails when the list is empty or when
an element has no name. Returns the list rendered as YAML.
*/}}
{{- define "project.helpers.clusters" -}}
{{- $clusters := .Values.clusters -}}
{{- if not $clusters -}}
{{- fail "clusters is required and must contain at least one cluster" -}}
{{- end -}}
{{- range $i, $c := $clusters -}}
{{- if not $c.name -}}
{{- fail (printf "clusters[%d].name is required" $i) -}}
{{- end -}}
{{- end -}}
{{- toYaml $clusters -}}
{{- end -}}
