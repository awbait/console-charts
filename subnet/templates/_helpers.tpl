{{/* Resolve the chart-wide enable switch. */}}
{{- define "subnet.helpers.chartEnabled" -}}
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


{{/* Chart name and version label. */}}
{{- define "subnet.helpers.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/* Prefer global identity when supplied by a parent. */}}
{{- define "subnet.helpers.identity" -}}
{{- $global := (.Values.global | default dict).identity | default dict -}}
{{- if gt (len $global) 0 -}}
{{- $global | toJson -}}
{{- else -}}
{{- .Values.identity | default dict | toJson -}}
{{- end -}}
{{- end -}}


{{/* Validate a DNS tag. */}}
{{- define "subnet.helpers.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}


{{/* Validate a bounded DNS token. */}}
{{- define "subnet.helpers.shortToken" -}}
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


{{/* Build the cpaas-style resource name. */}}
{{- define "subnet.helpers.resourceName" -}}
{{- $identity := include "subnet.helpers.identity" .context | fromJson -}}
{{- $project := include "subnet.helpers.shortToken" (dict "label" "identity.project" "value" $identity.project "max" 9) -}}
{{- $cluster := include "subnet.helpers.tag" (dict "label" "identity.cluster" "value" $identity.cluster) -}}
{{- $kind := required "kindShort is required" .kindShort | toString | lower -}}
{{- if not (has $kind (list "ns" "subnet")) -}}
{{- fail (printf "kindShort must be one of ns, subnet, got %q" $kind) -}}
{{- end -}}
{{- $name := include "subnet.helpers.shortToken" (dict "label" (printf "%s name" $kind) "value" .name) -}}
{{- $full := printf "%s-%s-%s-%s" $project $cluster $kind $name -}}
{{- if gt (len $full) 63 -}}{{- fail "subnet resource name must be at most 63 characters" -}}{{- end -}}
{{- $full -}}
{{- end -}}


{{/* Render identity labels. */}}
{{- define "subnet.helpers.identityLabels" -}}
{{- $identity := include "subnet.helpers.identity" . | fromJson -}}
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


{{/* Render standard and generic labels. */}}
{{- define "subnet.helpers.labels" -}}
helm.sh/chart: {{ include "subnet.helpers.chart" . }}
app: {{ .Chart.Name }}
app.cpaas.io/name: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- include "subnet.helpers.identityLabels" . }}
{{- range $k, $v := (.Values.generic | default dict).labels }}
{{ $k }}: {{ tpl (toString $v) $ | quote }}
{{- end }}
{{- end }}


{{/* Merge resource labels and annotations. */}}
{{- define "subnet.helpers.metadata" -}}
{{- $ctx := .context -}}
{{- $labels := include "subnet.helpers.labels" $ctx | fromYaml -}}
{{- $labels = mergeOverwrite $labels (.labels | default dict) -}}
labels:
  {{- $labels | toYaml | nindent 2 }}
{{- $ann := deepCopy (($ctx.Values.generic | default dict).annotations | default dict) -}}
{{- $ann = mergeOverwrite $ann (.annotations | default dict) -}}
{{- if $ann }}
annotations:
  {{- range $k, $v := $ann }}
  {{ $k }}: {{ tpl (toString $v) $ctx | quote }}
  {{- end }}
{{- end }}
{{- end }}

{{/* Argo CD sync wave as an annotation dictionary. */}}

{{/* Render syncWave. */}}
{{- define "subnet.helpers.syncWave" -}}
{{- dict "argocd.argoproj.io/sync-wave" (toString .) | toJson -}}
{{- end -}}


{{/* Convert an IPv4 address to an integer. */}}
{{- define "subnet.helpers.ipToInt" -}}
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


{{/* Convert an integer to an IPv4 address. */}}
{{- define "subnet.helpers.intToIp" -}}
{{- $value := int64 . -}}
{{- printf "%d.%d.%d.%d" (div $value 16777216) (mod (div $value 65536) 256) (mod (div $value 256) 256) (mod $value 256) -}}
{{- end -}}


{{/* Count addresses for a /16 through /30 block. */}}
{{- define "subnet.helpers.subnetSize" -}}
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


{{/* Validate and return the network address. */}}
{{- define "subnet.helpers.subnetBase" -}}
{{- $parts := splitList "/" (toString .) -}}
{{- if ne (len $parts) 2 -}}
{{- fail (printf "cidrBlock must be written as address/mask, got %q" .) -}}
{{- end -}}
{{- $base := include "subnet.helpers.ipToInt" (index $parts 0) | int64 -}}
{{- $size := include "subnet.helpers.subnetSize" (index $parts 1) | int64 -}}
{{- if ne (mod $base $size) (int64 0) -}}
{{- fail (printf "cidrBlock must start at the first address of the block, got %q" .) -}}
{{- end -}}
{{- $base -}}
{{- end -}}


{{/* Use the first address after the network address. */}}
{{- define "subnet.helpers.subnetGateway" -}}
{{- include "subnet.helpers.intToIp" (add (include "subnet.helpers.subnetBase" . | int64) 1) -}}
{{- end -}}


{{/*
Addresses kept away from pods, comma-separated: the gateway, then as many
addresses right behind it as reservedIps asks for. The order names a count
rather than addresses, because it cannot know which block the platform will
reserve for it. Parameter: the subnet values block.
*/}}
{{- define "subnet.helpers.reservedAddresses" -}}
{{- $base := include "subnet.helpers.subnetBase" .cidrBlock | int64 -}}
{{- $addresses := list (include "subnet.helpers.intToIp" (add $base 1)) -}}
{{- range $i := until (.reservedIps | default 0 | int) -}}
{{- $addresses = append $addresses (include "subnet.helpers.intToIp" (add $base 2 $i)) -}}
{{- end -}}
{{- join "," $addresses -}}
{{- end -}}


{{/* Validate addresses and ranges before rendering. */}}
{{- define "subnet.helpers.validate" -}}
{{- $s := .Values.subnet -}}
{{- if not $s.cidrBlock -}}{{- fail "subnet.cidrBlock is required: fill in the reserved range before enabling the subnet" -}}{{- end -}}
{{- $cidrMask := index (splitList "/" (toString $s.cidrBlock)) 1 | default "" -}}
{{- /* The order asks for a mask and the platform reserves a block for it; a mismatch means the reservation went wrong. */ -}}
{{- if and $s.mask (ne (toString $s.mask) (toString $cidrMask)) -}}
{{- fail (printf "subnet.cidrBlock %q does not carry the ordered mask /%v" (toString $s.cidrBlock) $s.mask) -}}
{{- end -}}
{{- $base := include "subnet.helpers.subnetBase" $s.cidrBlock | int64 -}}
{{- $size := include "subnet.helpers.subnetSize" $cidrMask | int64 -}}
{{- $reserved := $s.reservedIps | default 0 | int64 -}}
{{- if lt $reserved (int64 0) -}}{{- fail (printf "subnet.reservedIps must not be negative, got %d" $reserved) -}}{{- end -}}
{{- if ge (add $reserved 3) $size -}}
{{- fail (printf "subnet.cidrBlock %s has no room for %d reserved addresses on top of the gateway" $s.cidrBlock $reserved) -}}
{{- end -}}
{{- if not (has $s.gatewayType (list "distributed" "centralized")) -}}{{- fail "subnet.gatewayType must be distributed or centralized" -}}{{- end -}}
{{- if and (eq $s.gatewayType "centralized") (empty $s.gatewayNodes) -}}{{- fail "subnet.gatewayNodes is required for centralized gateways" -}}{{- end -}}
{{- range $s.excludeIPs -}}
{{- $ends := splitList ".." . -}}
{{- if gt (len $ends) 2 -}}{{- fail "excludeIPs must contain IPv4 addresses or start..end ranges" -}}{{- end -}}
{{- $start := include "subnet.helpers.ipToInt" (first $ends) | int64 -}}
{{- $end := include "subnet.helpers.ipToInt" (last $ends) | int64 -}}
{{- if or (lt $start $base) (ge $end (add $base $size)) (gt $start $end) -}}{{- fail "excludeIPs must be ordered ranges inside cidrBlock" -}}{{- end -}}
{{- end -}}
{{- range $s.allowSubnets -}}
{{- $parts := splitList "/" . -}}
{{- if ne (len $parts) 2 -}}{{- fail "allowSubnets must contain IPv4 CIDRs" -}}{{- end -}}
{{- $ip := include "subnet.helpers.ipToInt" (first $parts) -}}
{{- $mask := last $parts -}}
{{- if not (regexMatch "^([0-9]|[12][0-9]|3[0-2])$" $mask) -}}{{- fail "allowSubnets mask must be 0..32" -}}{{- end -}}
{{- end -}}
{{- range $s.namespaces -}}
{{- if or (gt (len .) 63) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" .)) -}}{{- fail "namespaces must contain DNS labels of at most 63 characters" -}}{{- end -}}
{{- end -}}
{{- end -}}


{{/* Resolve the subnet purpose, optionally inherited from the namespace. */}}
{{- define "subnet.helpers.purpose" -}}
{{- $name := .Values.subnet.name -}}
{{- if and (not $name) .Values.namespaceBinding.enabled -}}
{{- $name = .Values.namespaceBinding.purpose | default (.Values.global | default dict).namespacePurpose -}}
{{- end -}}
{{- include "subnet.helpers.shortToken" (dict "label" "subnet.name or namespace purpose" "value" $name) -}}
{{- end -}}

{{/* Resolve the exact namespace selected by the parent chart. */}}
{{- define "subnet.helpers.boundNamespace" -}}
{{- $binding := .Values.namespaceBinding -}}
{{- $global := .Values.global | default dict -}}
{{- $name := $binding.namespaceOverride | default $global.namespaceOverride -}}
{{- if $name -}}
{{- if or (gt (len $name) 63) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name)) -}}
{{- fail "namespaceBinding.namespaceOverride must be a DNS label of at most 63 characters" -}}
{{- end -}}
{{- $name -}}
{{- else -}}
{{- include "subnet.helpers.resourceName" (dict "context" . "kindShort" "ns" "name" ($binding.purpose | default $global.namespacePurpose)) -}}
{{- end -}}
{{- end -}}

{{/* Automatic parent binding and explicit namespaces are mutually exclusive. */}}
{{- define "subnet.helpers.namespaces" -}}
{{- if .Values.namespaceBinding.enabled -}}
{{- if .Values.subnet.namespaces -}}{{- fail "subnet.namespaces must be empty when namespaceBinding.enabled=true" -}}{{- end -}}
{{- list (include "subnet.helpers.boundNamespace" .) | toJson -}}
{{- else -}}
{{- .Values.subnet.namespaces | toJson -}}
{{- end -}}
{{- end -}}
