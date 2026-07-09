{{/*
Chart name for helm.sh/chart.
*/}}
{{- define "ingress-gateway.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base application name (for labels) = projectTag.
*/}}
{{- define "ingress-gateway.helpers.app.name" -}}
{{- required "naming.projectTag is required" (.Values.naming | default dict).projectTag | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
DNS tag validation (instanceTag, clusterTag). Parameters: .label, .value.
Returns the value in lower-case.
*/}}
{{- define "ingress-gateway.helpers.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Validation of a short 2..6-character DNS tag (projectTag, name).
Parameters: .label, .value. Returns the value in lower-case.
*/}}
{{- define "ingress-gateway.helpers.shortToken" -}}
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
Short resource type code (kindShort) by k8s kind. Parameter: kind (string).
Allowed: igw (Gateway), cm (ConfigMap), ap (AuthorizationPolicy),
np (NetworkPolicy), hr (HTTPRoute), gr (GRPCRoute), tr (TLSRoute),
tcr (TCPRoute), ur (UDPRoute), secret (Secret). Unknown kind -> fail.
*/}}
{{- define "ingress-gateway.helpers.app.kindShort" -}}
{{- $kind := required "kind is required" . | toString | lower -}}
{{- if eq $kind "gateway" -}}igw
{{- else if eq $kind "configmap" -}}cm
{{- else if eq $kind "authorizationpolicy" -}}ap
{{- else if eq $kind "networkpolicy" -}}np
{{- else if eq $kind "httproute" -}}hr
{{- else if eq $kind "grpcroute" -}}gr
{{- else if eq $kind "tlsroute" -}}tr
{{- else if eq $kind "tcproute" -}}tcr
{{- else if eq $kind "udproute" -}}ur
{{- else if eq $kind "secret" -}}secret
{{- else -}}{{- fail (printf "unsupported kind for resourceName: %q" $kind) -}}
{{- end -}}
{{- end -}}

{{/*
TLS secret name for a listener by hostname (tlsMode: Terminate). Parameters: .hostname, .context.
The name is ALWAYS generated automatically (the user does not set tlsSecretName):
  contains "idp.ecpk.test" -> {instanceTag}-{clusterTag}-secret-{projectTag}-idptls (predefined wildcard cert)
  contains "edp.ecpk.test" -> {instanceTag}-{clusterTag}-secret-{projectTag}-edptls (predefined wildcard cert)
  otherwise              -> {instanceTag}-{clusterTag}-secret-{projectTag}-tls   (empty secret / change me)
*/}}
{{- define "ingress-gateway.helpers.app.tlsSecretName" -}}
{{- $hostname := .hostname | default "" | toString | lower -}}
{{- $token := "tls" -}}
{{- if contains "idp.ecpk.test" $hostname -}}{{- $token = "idptls" -}}
{{- else if contains "edp.ecpk.test" $hostname -}}{{- $token = "edptls" -}}
{{- end -}}
{{- include "ingress-gateway.helpers.app.resourceName" (dict "kind" "Secret" "name" $token "context" .context) -}}
{{- end -}}

{{/*
Resource name by convention:
  {instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
Parameters: .context, .kind (k8s kind), .name (2..6 characters).
kindShort is derived from .kind (see ingress-gateway.helpers.app.kindShort).
The result is truncated to 63 characters.
Examples: ru1-k8s1-igw-nbox-main, ru1-k8s1-hr-nbox-app.
*/}}
{{- define "ingress-gateway.helpers.app.resourceName" -}}
{{- $naming := .context.Values.naming | default dict -}}
{{- $instance := include "ingress-gateway.helpers.tag" (dict "label" "naming.instanceTag" "value" $naming.instanceTag) -}}
{{- $cluster := include "ingress-gateway.helpers.tag" (dict "label" "naming.clusterTag" "value" $naming.clusterTag) -}}
{{- $project := include "ingress-gateway.helpers.shortToken" (dict "label" "naming.projectTag" "value" $naming.projectTag) -}}
{{- $kindShort := include "ingress-gateway.helpers.app.kindShort" (required "resourceName.kind is required" .kind) -}}
{{- $name := include "ingress-gateway.helpers.shortToken" (dict "label" "name" "value" .name) -}}
{{- printf "%s-%s-%s-%s-%s" $instance $cluster $kindShort $project $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels - stable identification of chart resources.
*/}}
{{- define "ingress-gateway.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ingress-gateway.helpers.app.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app: {{ include "ingress-gateway.helpers.app.name" . | quote }}
{{- end -}}

{{/*
Standard labels: selector + chart/managed-by/version + generic.labels.
*/}}
{{- define "ingress-gateway.helpers.app.labels" -}}
{{ include "ingress-gateway.helpers.app.selectorLabels" . }}
helm.sh/chart: {{ include "ingress-gateway.helpers.app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- range $k, $v := (.Values.generic | default dict).labels }}
{{ $k }}: {{ tpl (toString $v) $ | quote }}
{{- end }}
{{- end -}}

{{/*
Common annotations (generic.annotations). Empty -> outputs nothing.
*/}}
{{- define "ingress-gateway.helpers.app.genericAnnotations" -}}
{{- range $k, $v := (.Values.generic | default dict).annotations }}
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
  {{- include "ingress-gateway.helpers.app.metadata" (dict "context" $root) | nindent 2 }}
*/}}
{{- define "ingress-gateway.helpers.app.metadata" -}}
{{- $ctx := .context -}}
labels:
  {{- include "ingress-gateway.helpers.app.labels" $ctx | nindent 2 }}
  {{- with .labels }}
  {{- include "ingress-gateway.helpers.tplvalues.render" (dict "value" . "context" $ctx) | nindent 2 }}
  {{- end }}
{{- $generic := include "ingress-gateway.helpers.app.genericAnnotations" $ctx | trim -}}
{{- $extra := "" -}}
{{- with .annotations }}{{- $extra = include "ingress-gateway.helpers.tplvalues.render" (dict "value" . "context" $ctx) | trim -}}{{- end -}}
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
{{- define "ingress-gateway.helpers.app.enabled" -}}
{{- $entity := . | default dict -}}
{{- if hasKey $entity "enabled" -}}
{{- ternary "true" "" (eq (toString $entity.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
matchLabels for selecting the Gateway workload in NetworkPolicy/AuthorizationPolicy.
The Istio Gateway controller sets on the pods the label
gateway.networking.k8s.io/gateway-name = metadata.name of the Gateway.
Parameters: .gatewayResourceName (full Gateway name).
*/}}
{{- define "ingress-gateway.helpers.app.gatewayWorkloadSelectorLabels" -}}
gateway.networking.k8s.io/gateway-name: {{ required "gatewayResourceName is required" .gatewayResourceName | quote }}
{{- end -}}

{{/*
Canonical kind for xRoute. Parameters: .kind, .name.
*/}}
{{- define "ingress-gateway.helpers.app.xRouteKind" -}}
{{- $name := .name | default "<unknown>" -}}
{{- $kind := required (printf "xroutes.%s.kind is required" $name) .kind | toString | trim | lower -}}
{{- if eq $kind "httproute" -}}HTTPRoute
{{- else if eq $kind "grpcroute" -}}GRPCRoute
{{- else if eq $kind "tlsroute" -}}TLSRoute
{{- else if eq $kind "tcproute" -}}TCPRoute
{{- else if eq $kind "udproute" -}}UDPRoute
{{- else -}}{{- fail (printf "xroutes.%s.kind must be one of HTTPRoute, GRPCRoute, TLSRoute, TCPRoute, UDPRoute" $name) -}}
{{- end -}}
{{- end -}}

{{/*
apiVersion for xRoute by kind. apiVersion is intentionally not taken from values.
Parameters: .kind (canonical), .name.
*/}}
{{- define "ingress-gateway.helpers.app.xRouteApiVersion" -}}
{{- $name := .name | default "<unknown>" -}}
{{- $kind := required (printf "xroutes.%s.kind is required" $name) .kind | toString | trim -}}
{{- if or (eq $kind "HTTPRoute") (eq $kind "GRPCRoute") -}}gateway.networking.k8s.io/v1
{{- else if or (eq $kind "TLSRoute") (eq $kind "TCPRoute") (eq $kind "UDPRoute") -}}gateway.networking.k8s.io/v1alpha2
{{- else -}}{{- fail (printf "xroutes.%s.kind must be one of HTTPRoute, GRPCRoute, TLSRoute, TCPRoute, UDPRoute" $name) -}}
{{- end -}}
{{- end -}}

{{/*
Generic rendering of templated values. Parameters: .value, .context.
*/}}
{{- define "ingress-gateway.helpers.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
