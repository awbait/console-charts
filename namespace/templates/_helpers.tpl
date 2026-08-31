{{/*
Chart-wide switch: root "enabled", true unless values say otherwise. Returns
"true" or "" (for if-tests). Every template of the chart hangs on it, so
enabled: false renders nothing at all.

The switch used to be global.enable. Helm reserves "global" for the values a
parent chart injects, so the chart could not accept a real global at all. A
leftover global.enable: false stops the render outright: it must be moved to
enabled: false, and silently rendering everything instead is worse than saying so.
*/}}
{{- define "namespace.helpers.chartEnabled" -}}
{{- $global := .Values.global | default dict -}}
{{- if and (hasKey $global "enable") (not $global.enable) -}}
{{- fail "global.enable is no longer read: move the switch to the root, enabled: false" -}}
{{- end -}}
{{- if hasKey .Values "enabled" -}}
{{- ternary "true" "" (eq (toString .Values.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{- define "namespace.helpers.parseStorageQuotas" -}}
{{- if .Values.resourceQuotas.storage }}
{{- fromJson .Values.resourceQuotas.storage | toYaml }}
{{- else }}
{}
{{- end }}
{{- end }}


{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "namespace.helpers.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
DNS tag validation (identity.cluster). Parameters: .label, .value.
Returns the value in lower-case.
*/}}
{{- define "namespace.helpers.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Short DNS tag validation (identity.project, the purpose part of a name).
Parameters: .label, .value and the optional bounds .min (default 2) and .max
(default 12). Returns the value in lower-case.
*/}}
{{- define "namespace.helpers.shortToken" -}}
{{- $min := .min | default 2 | int -}}
{{- $max := .max | default 12 | int -}}
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
Resource name: {project}-{cluster}-{kindShort}-{purpose}.

The order names only the purpose (namespace.name, subnet.subnets[].name); the
project and the cluster come from identity, so a name can never disagree with
the tags the same values put on the resource. Parameters: .context, .kindShort
(ns|subnet), .name. Truncated to 63 characters, e.g. nbox-dev-ns-app.
*/}}
{{- define "namespace.helpers.resourceName" -}}
{{- $identity := .context.Values.identity | default dict -}}
{{- $project := include "namespace.helpers.shortToken" (dict "label" "identity.project" "value" $identity.project "max" 9) -}}
{{- $cluster := include "namespace.helpers.tag" (dict "label" "identity.cluster" "value" $identity.cluster) -}}
{{- $kind := required "kindShort is required" .kindShort | toString | lower -}}
{{- if not (has $kind (list "ns" "subnet")) -}}
{{- fail (printf "kindShort must be one of ns, subnet, got %q" $kind) -}}
{{- end -}}
{{- $name := include "namespace.helpers.shortToken" (dict "label" (printf "%s name" $kind) "value" .name) -}}
{{- printf "%s-%s-%s-%s" $project $cluster $kind $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the Namespace the chart creates, e.g. nbox-dev-ns-app.
Every template that needs it calls this, so the Namespace, the ResourceQuota
inside it and the Subnet bound to it can never drift apart.
*/}}
{{- define "namespace.helpers.namespaceName" -}}
{{- include "namespace.helpers.resourceName" (dict "context" . "kindShort" "ns" "name" (.Values.namespace | default dict).name) -}}
{{- end -}}

{{/*
Identity labels: ecpk/instance, ecpk/cluster, ecpk/project.

Each label is rendered only when the matching identity.* value is set, so a
partially filled identity block never produces an empty label value. Values are
lower-cased.
*/}}
{{- define "namespace.helpers.identityLabels" -}}
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
{{- end }}

{{/*
Common labels: chart identity + ecpk identity labels + generic.labels.
*/}}
{{- define "namespace.helpers.labels" -}}
helm.sh/chart: {{ include "namespace.helpers.chart" . }}
app: {{ .Chart.Name }}
app.cpaas.io/name: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- include "namespace.helpers.identityLabels" . }}
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
  {{- include "namespace.helpers.metadata" (dict "context" $root) | nindent 2 }}
*/}}
{{- define "namespace.helpers.metadata" -}}
{{- $ctx := .context -}}
labels:
  {{- include "namespace.helpers.labels" $ctx | nindent 2 }}
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
  {{ include "namespace.helpers.jsonListToYamlList" .Values.myJsonString }}
*/}}
{{- define "namespace.helpers.jsonListToYamlList" -}}
{{- $unmarshaled := fromJson . -}}
{{- toYaml $unmarshaled | nindent 0 -}}
{{- end -}}

{{/*
Get the gateway IP from cidrBlock by incrementing the last octet of an IP address by 1
Net mask is supposed to be >= 24
*/}}
{{- define "namespace.helpers.getGatewayIP" -}}
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