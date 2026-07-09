{{- define "managed-ns.parseStorageQuotas" -}}
{{- if .Values.resourceQuotas.storage }}
{{- fromJson .Values.resourceQuotas.storage | toYaml }}
{{- else }}
{}
{{- end }}
{{- end }}


{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "managed-ns.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels: chart identity + generic.labels.
*/}}
{{- define "managed-ns.labels" -}}
helm.sh/chart: {{ include "managed-ns.chart" . }}
app.cpaas.io/name: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- range $k, $v := (.Values.generic | default dict).labels }}
{{ $k }}: {{ tpl (toString $v) $ | quote }}
{{- end }}
{{- end }}

{{/*
Common metadata (labels + annotations) for every chart resource. Renders the
full "labels:" block and, only when non-empty, the "annotations:" block, so a
resource wires both in one call and never silently drops generic.* on a new
manifest. Parameters:
  .context     - root context ($), required;
  .labels      - optional dict of extra per-resource labels;
  .annotations - optional dict of extra per-resource annotations.
Call right under metadata.name/namespace:
  {{- include "managed-ns.metadata" (dict "context" $root) | nindent 2 }}
*/}}
{{- define "managed-ns.metadata" -}}
{{- $ctx := .context -}}
labels:
  {{- include "managed-ns.labels" $ctx | nindent 2 }}
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
{{- end }}


{{/*
Parses a JSON list and renders it as YAML list.
Usage:
  {{ include "managed-ns.jsonListToYamlList" .Values.myJsonString }}
*/}}
{{- define "managed-ns.jsonListToYamlList" -}}
{{- $unmarshaled := fromJson . -}}
{{- toYaml $unmarshaled | nindent 0 -}}
{{- end -}}

{{/*
Get the gateway IP from cidrBlock by incrementing the last octet of an IP address by 1
Net mask is supposed to be >= 24
*/}}
{{- define "managed-ns.getGatewayIP" -}}
{{- $cidr := . -}}

{{/* Split CIDR to get IP part */}}
{{- $splitResult := splitList "/" $cidr -}}
{{- if lt (len $splitResult) 2 -}}
{{- printf "Invalid CIDR format: %s" $cidr | fail -}}
{{- end -}}

{{- $ipPart := index $splitResult 0 -}}
{{- $maskPart := index $splitResult 1 -}}

{{/* Split IP into octets */}}
{{- $octets := splitList "." $ipPart -}}
{{- if ne (len $octets) 4 -}}
{{- printf "Invalid IP address format: must contain exactly 4 octets, got: %s" $ipPart | fail -}}
{{- end -}}

{{/* Get last octet and convert to integer */}}
{{- $lastOctetStr := index $octets 3 -}}
{{- $lastOctet := $lastOctetStr | int -}}

{{/* Validate octet range */}}
{{- if or (lt $lastOctet 0) (gt $lastOctet 254) -}}
{{- printf "Last octet must be between 0 and 254, got: %s" $lastOctetStr | fail -}}
{{- end -}}

{{/* Increment last octet */}}
{{- $newLastOctet := add $lastOctet 1 -}}

{{/* Build new IP address */}}
{{- $firstOctet := index $octets 0 -}}
{{- $secondOctet := index $octets 1 -}}
{{- $thirdOctet := index $octets 2 -}}

{{/* Join octets back together */}}
{{- printf "%s.%s.%s.%d" $firstOctet $secondOctet $thirdOctet $newLastOctet -}}
{{- end -}}