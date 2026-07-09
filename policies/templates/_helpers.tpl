{{/*
Chart name.
*/}}
{{- define "security-policies.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels: chart identity + generic.labels.
*/}}
{{- define "security-policies.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | quote }}
app.kubernetes.io/name: {{ include "security-policies.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
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
Call right under metadata.name/namespace:
  {{- include "security-policies.metadata" (dict "context" $root) | nindent 2 }}
*/}}
{{- define "security-policies.metadata" -}}
{{- $ctx := .context -}}
labels:
  {{- include "security-policies.labels" $ctx | nindent 2 }}
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
Resolve policy.enabled flag (defaults to true).
*/}}
{{- define "security-policies.enabled" -}}
{{- $policy := .policy -}}
{{- if hasKey $policy "enabled" -}}
{{- ternary "true" "" (eq (toString $policy.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Validate a DNS tag (instanceTag, clusterTag). Params: .label, .value.
Returns the value lower-cased.
*/}}
{{- define "security-policies.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Validate a 2..6-char DNS token (projectTag, policy.name). Params: .label, .value.
Returns the value lower-cased.
*/}}
{{- define "security-policies.shortToken" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if or (lt (len $value) 2) (gt (len $value) 6) -}}
{{- fail (printf "%s must be from 2 to 6 characters, got %q" .label $value) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must match DNS-like format, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Resource name following the convention:
  {instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}

Params: .context, .shortkind (np|ap), .name (2..6 characters).

kindShort:
- np - NetworkPolicy
- ap - AuthorizationPolicy

Examples:
- ru1-k8s1-np-nbox-core
- ru1-k8s1-ap-nbox-core
*/}}
{{- define "security-policies.resourceName" -}}
{{- $naming := .context.Values.naming | default dict -}}
{{- $instance := include "security-policies.tag" (dict "label" "naming.instanceTag" "value" $naming.instanceTag) -}}
{{- $cluster := include "security-policies.tag" (dict "label" "naming.clusterTag" "value" $naming.clusterTag) -}}
{{- $project := include "security-policies.shortToken" (dict "label" "naming.projectTag" "value" $naming.projectTag) -}}
{{- $kind := required "shortkind is required" .shortkind | toString | lower -}}
{{- if not (has $kind (list "np" "ap")) -}}
{{- fail (printf "shortkind must be one of np|ap, got %q" $kind) -}}
{{- end -}}
{{- $name := include "security-policies.shortToken" (dict "label" "policy.name" "value" .name) -}}
{{- printf "%s-%s-%s-%s-%s" $instance $cluster $kind $project $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Render NetworkPolicy peer.

Supported formats:

- namespace + selector
- namespaceSelector + podSelector
- ipBlock
*/}}
{{- define "security-policies.netpolPeer" -}}
{{- $root := .root -}}
{{- $peer := .peer -}}
{{- if $peer.ipBlock -}}
ipBlock:
  cidr: {{ required "peer.ipBlock.cidr is required" $peer.ipBlock.cidr | quote }}
{{- if $peer.ipBlock.except }}
  except:
{{- range $cidr := $peer.ipBlock.except }}
    - {{ $cidr | quote }}
{{- end }}
{{- end }}
{{- else -}}
{{- $hasNs := or $peer.namespace $peer.namespaceSelector -}}
{{- $hasPod := or $peer.selector $peer.podSelector -}}
{{- if not (or $hasNs $hasPod) -}}
{{- fail (printf "netpol peer must define ipBlock, namespace/namespaceSelector, or selector/podSelector; got %v" $peer) -}}
{{- end }}
{{- if $peer.namespace }}
namespaceSelector:
  matchLabels:
    {{ default "kubernetes.io/metadata.name" $root.Values.defaults.namespaceLabelKey }}: {{ $peer.namespace | quote }}
{{- else if $peer.namespaceSelector }}
namespaceSelector:
{{ toYaml $peer.namespaceSelector | indent 2 }}
{{- end }}
{{- if $peer.selector }}
podSelector:
  matchLabels:
{{ toYaml $peer.selector | indent 4 }}
{{- else if $peer.podSelector }}
podSelector:
{{ toYaml $peer.podSelector | indent 2 }}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Render NetworkPolicy ports.

ports:
  - 8080
  - port: 8080
    protocol: TCP
*/}}
{{- define "security-policies.netpolPorts" -}}
{{- $root := .root -}}
{{- $defaultProto := default "TCP" $root.Values.defaults.protocol -}}
{{- range $port := .ports }}
{{- $portValue := $port -}}
{{- $protocol := $defaultProto -}}
{{- if kindIs "map" $port -}}
{{- $portValue = required "port.port is required" $port.port -}}
{{- $protocol = default $defaultProto $port.protocol -}}
{{- end }}
- port: {{ $portValue }}
  protocol: {{ $protocol | quote }}
{{- end }}
{{- end -}}

{{/*
Build Istio principal.

Input:
- namespace
- name
*/}}
{{- define "security-policies.istioPrincipal" -}}
{{- $root := .root -}}
{{- $sa := .serviceAccount -}}
{{- $trustDomain := default "cluster.local" $root.Values.defaults.trustDomain -}}
{{- $namespace := required "serviceAccount.namespace is required" $sa.namespace -}}
{{- $name := required "serviceAccount.name is required" $sa.name -}}
{{- printf "%s/ns/%s/sa/%s" $trustDomain $namespace $name -}}
{{- end -}}

{{/*
Render AuthorizationPolicy source.

Supported:
from:
  serviceAccounts:
    - namespace: app
      name: app-sa

  principals:
    - cluster.local/ns/app/sa/app-sa

  ipBlocks:
    - 0.0.0.0/0

  namespaces:
    - app
*/}}
{{- define "security-policies.authzSource" -}}
{{- $root := .root -}}
{{- $from := .from -}}
{{- if not (or $from.principals $from.serviceAccounts $from.ipBlocks $from.namespaces) -}}
{{- fail (printf "authz source must define principals, serviceAccounts, ipBlocks, or namespaces; got %v" $from) -}}
{{- end -}}
{{- if $from.principals }}
principals:
{{- range $principal := $from.principals }}
  - {{ $principal | quote }}
{{- end }}
{{- else if $from.serviceAccounts }}
principals:
{{- range $sa := $from.serviceAccounts }}
  - {{ include "security-policies.istioPrincipal" (dict "root" $root "serviceAccount" $sa) | quote }}
{{- end }}
{{- end }}
{{- if $from.ipBlocks }}
ipBlocks:
{{- range $ipBlock := $from.ipBlocks }}
  - {{ $ipBlock | quote }}
{{- end }}
{{- end }}
{{- if $from.namespaces }}
namespaces:
{{- range $namespace := $from.namespaces }}
  - {{ $namespace | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Render AuthorizationPolicy ports.

AuthorizationPolicy operation.ports expects strings.
*/}}
{{- define "security-policies.authzPorts" -}}
{{- $_ := .root -}}
{{- range $port := .ports }}
{{- $portValue := $port -}}
{{- if kindIs "map" $port -}}
{{- $portValue = required "port.port is required" $port.port -}}
{{- end }}
- {{ $portValue | toString | quote }}
{{- end }}
{{- end -}}