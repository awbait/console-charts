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
IPv4 address as a number, so addresses can be counted off without caring where
the octet boundaries fall. Parameter: the dotted address.
*/}}
{{- define "namespace.helpers.ipToInt" -}}
{{- $octets := splitList "." (toString .) -}}
{{- if ne (len $octets) 4 -}}
{{- fail (printf "IPv4 address must have 4 octets, got %q" .) -}}
{{- end -}}
{{- $value := 0 -}}
{{- range $octets -}}
{{- if not (regexMatch "^[0-9]{1,3}$" .) -}}
{{- fail (printf "IPv4 octet must be a number 0..255, got %q" .) -}}
{{- end -}}
{{- $octet := int . -}}
{{- if gt $octet 255 -}}
{{- fail (printf "IPv4 octet must be a number 0..255, got %q" .) -}}
{{- end -}}
{{- $value = add (mul $value 256) $octet -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
The inverse of ipToInt: a number back into a dotted address.
*/}}
{{- define "namespace.helpers.intToIp" -}}
{{- $value := int64 . -}}
{{- printf "%d.%d.%d.%d" (div $value 16777216) (mod (div $value 65536) 256) (mod (div $value 256) 256) (mod $value 256) -}}
{{- end -}}

{{/*
Number of addresses in a CIDR block. The mask is limited to 16..30: a wider
block is never handed to one namespace, and a narrower one has no room for the
gateway plus a single pod. Parameter: the mask as a string or number.
*/}}
{{- define "namespace.helpers.subnetSize" -}}
{{- $mask := toString . -}}
{{- if not (regexMatch "^[0-9]{1,2}$" $mask) -}}
{{- fail (printf "subnet mask must be a number 16..30, got %q" $mask) -}}
{{- end -}}
{{- $bits := int $mask -}}
{{- if or (lt $bits 16) (gt $bits 30) -}}
{{- fail (printf "subnet mask must be 16..30, got %q" $mask) -}}
{{- end -}}
{{- $size := 1 -}}
{{- range until (sub 32 $bits | int) -}}
{{- $size = mul $size 2 -}}
{{- end -}}
{{- $size -}}
{{- end -}}

{{/*
First address of a subnet as a number, with the CIDR block validated on the way.
Parameter: the cidrBlock string, e.g. 10.24.8.0/22.
*/}}
{{- define "namespace.helpers.subnetBase" -}}
{{- $parts := splitList "/" (toString .) -}}
{{- if ne (len $parts) 2 -}}
{{- fail (printf "cidrBlock must be written as address/mask, got %q" .) -}}
{{- end -}}
{{- $base := include "namespace.helpers.ipToInt" (index $parts 0) | int64 -}}
{{- $size := include "namespace.helpers.subnetSize" (index $parts 1) | int64 -}}
{{- if ne (mod $base $size) (int64 0) -}}
{{- fail (printf "cidrBlock must start at the first address of the block, got %q" .) -}}
{{- end -}}
{{- $base -}}
{{- end -}}

{{/*
Gateway address of a subnet: the first address after the network one.
Parameter: the cidrBlock string.
*/}}
{{- define "namespace.helpers.subnetGateway" -}}
{{- include "namespace.helpers.intToIp" (add (include "namespace.helpers.subnetBase" . | int64) 1) -}}
{{- end -}}

{{/*
Addresses kept away from pods, as a comma-separated list: the gateway, then as
many addresses right behind it as the order asked to reserve. The order names a
count rather than addresses, because it has no way to know which addresses the
block holds. Parameters: .cidrBlock, .count.

The last address of the block is the broadcast one and the first is the network
itself, so what is left for pods is size-2; reserving all of it leaves the
subnet with no room and stops the render.
*/}}
{{- define "namespace.helpers.subnetExcludeIps" -}}
{{- $base := include "namespace.helpers.subnetBase" .cidrBlock | int64 -}}
{{- $size := include "namespace.helpers.subnetSize" (index (splitList "/" (toString .cidrBlock)) 1) | int64 -}}
{{- $count := .count | default 0 | int64 -}}
{{- if lt $count (int64 0) -}}
{{- fail (printf "reservedIps must not be negative, got %d" $count) -}}
{{- end -}}
{{- if ge (add $count 3) $size -}}
{{- fail (printf "cidrBlock %s has no room for %d reserved addresses on top of the gateway" .cidrBlock $count) -}}
{{- end -}}
{{- $addresses := list (include "namespace.helpers.intToIp" (add $base 1)) -}}
{{- range $i := until (int $count) -}}
{{- $addresses = append $addresses (include "namespace.helpers.intToIp" (add $base 2 $i)) -}}
{{- end -}}
{{- join "," $addresses -}}
{{- end -}}