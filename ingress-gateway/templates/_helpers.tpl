{{/*
Chart name for helm.sh/chart.
*/}}
{{- define "ingress-gateway.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base application name (for labels) = identity.project.
*/}}
{{- define "ingress-gateway.helpers.app.name" -}}
{{- required "identity.project is required" (.Values.identity | default dict).project | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
DNS tag validation (identity.instance, identity.cluster). Parameters: .label, .value.
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
Validation of a short DNS tag (identity.project, name). Parameters: .label,
.value and the optional bounds .min (default 2) and .max (default 6).
Returns the value in lower-case.
*/}}
{{- define "ingress-gateway.helpers.shortToken" -}}
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
Short resource type code (kindShort) by k8s kind. Parameter: kind (string).
Allowed: igw (Gateway), cm (ConfigMap), ap (AuthorizationPolicy),
np (NetworkPolicy), hr (HTTPRoute), gr (GRPCRoute), tr (TLSRoute),
tcr (TCPRoute), ur (UDPRoute), secret (Secret), es (ExternalSecret).
Unknown kind -> fail.
*/}}
{{- define "ingress-gateway.helpers.app.kindShort" -}}
{{- $kind := required "kind is required" . | toString | lower -}}
{{- if eq $kind "gateway" -}}igw
{{- else if eq $kind "externalsecret" -}}es
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
Does a certificate for .domain cover .hostname? Parameters: .domain, .hostname.
A wildcard domain covers one label, exactly as the certificate itself does:
  *.idp.ecpk.test covers app.idp.ecpk.test and *.idp.ecpk.test itself,
  but neither idp.ecpk.test nor a.str.idp.ecpk.test.
Returns "true", or nothing at all (an empty string is false at the call site).
*/}}
{{- define "ingress-gateway.helpers.app.hostCovered" -}}
{{- $domain := .domain | default "" | toString | lower -}}
{{- $hostname := .hostname | default "" | toString | lower -}}
{{- if and $domain $hostname -}}
{{- if eq $hostname $domain -}}true
{{- else if hasPrefix "*." $domain -}}
{{- $suffix := trimPrefix "*" $domain -}}
{{- if and (hasSuffix $suffix $hostname) (not (hasPrefix "*" $hostname)) -}}
{{- $label := trimSuffix $suffix $hostname -}}
{{- if and $label (not (contains "." $label)) -}}true{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Certificate for a listener with tlsMode: Terminate. Parameters: .hostname, .context.
The hostname is looked up in tls.certificates (the certificates of this order)
and then in tls.platform (the ones the platform prepared), first match wins.
Returns a JSON object, empty when no certificate covers the hostname:
  name        - short name of the entry, the {name} part of the Secret name
  path        - where the certificate lies in the store
  storeName   - name of the SecretStore, always in the namespace of the release
  crtProperty - key of the certificate inside the stored entry
  keyProperty - key of its private key
*/}}
{{- define "ingress-gateway.helpers.app.certificate" -}}
{{- $tls := .context.Values.tls | default dict -}}
{{- $hostname := .hostname | default "" | toString | lower -}}
{{- $found := dict -}}
{{- range $entry := concat ($tls.certificates | default list) ($tls.platform | default list) -}}
{{- if and (not $found) (eq (include "ingress-gateway.helpers.app.hostCovered" (dict "domain" $entry.domain "hostname" $hostname)) "true") -}}
{{- $name := required "tls certificate: name is required" $entry.name | toString -}}
{{- $found = dict
      "name" $name
      "path" (required (printf "tls certificate %q: path is required" $name) $entry.path | toString)
      "storeName" (required (printf "tls certificate %q: store is required (set it on the entry or in tls.store)" $name) ($entry.store | default $tls.store) | toString)
      "crtProperty" ($entry.crtProperty | default $tls.crtProperty | default "tls.crt" | toString)
      "keyProperty" ($entry.keyProperty | default $tls.keyProperty | default "tls.key" | toString)
-}}
{{- end -}}
{{- end -}}
{{- $found | toJson -}}
{{- end -}}

{{/*
Name of the Secret a listener certificate lands in. Parameters: .name, .context.
*/}}
{{- define "ingress-gateway.helpers.app.tlsSecretName" -}}
{{- include "ingress-gateway.helpers.app.resourceName" (dict "kind" "Secret" "name" .name "context" .context) -}}
{{- end -}}

{{/*
Resource name by convention:
  without parent: {instance}-{cluster}-{kindShort}-{project}-{name}
  with parent:    {instance}-{cluster}-{kindShort}-{parent}-{project}-{name}
Parameters: .context, .kind (k8s kind), .name (2..6 characters, 2..9 for the
kinds named after a gateway), .parent (optional gateway name, 2..9; routes use
it, so two routes of one kind may carry one name under different gateways).
kindShort is derived from .kind (see ingress-gateway.helpers.app.kindShort).
The result is truncated to 63 characters.
Examples: ed-dev-igw-nbox-main, ed-dev-hr-main-nbox-app.
*/}}
{{- define "ingress-gateway.helpers.app.resourceName" -}}
{{- $identity := .context.Values.identity | default dict -}}
{{- $instance := include "ingress-gateway.helpers.tag" (dict "label" "identity.instance" "value" $identity.instance) -}}
{{- $cluster := include "ingress-gateway.helpers.tag" (dict "label" "identity.cluster" "value" $identity.cluster) -}}
{{- $project := include "ingress-gateway.helpers.shortToken" (dict "label" "identity.project" "value" $identity.project "max" 9) -}}
{{- $kind := required "resourceName.kind is required" .kind | toString | lower -}}
{{- $kindShort := include "ingress-gateway.helpers.app.kindShort" $kind -}}
{{/* These four are named after gateways[].name, which is allowed 9 characters; everything else is named after a route or a certificate and stays at 6. */}}
{{- $nameMax := ternary 9 6 (has $kind (list "gateway" "configmap" "authorizationpolicy" "networkpolicy")) -}}
{{- $name := include "ingress-gateway.helpers.shortToken" (dict "label" "name" "value" .name "max" $nameMax) -}}
{{- if .parent -}}
{{- $parent := include "ingress-gateway.helpers.shortToken" (dict "label" "parentGatewayName" "value" .parent "max" 9) -}}
{{- printf "%s-%s-%s-%s-%s-%s" $instance $cluster $kindShort $parent $project $name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s-%s-%s-%s" $instance $cluster $kindShort $project $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Name of the only enabled Gateway, or "" when there is none or more than one.
Parameter: the root context.
*/}}
{{- define "ingress-gateway.helpers.app.soleGateway" -}}
{{- $enabled := list -}}
{{- range $g := .Values.gateways -}}
{{- if eq (include "ingress-gateway.helpers.app.enabled" $g) "true" -}}{{- $enabled = append $enabled $g -}}{{- end -}}
{{- end -}}
{{- if eq (len $enabled) 1 -}}{{- (index $enabled 0).name -}}{{- end -}}
{{- end -}}

{{/*
Gateway a route hangs on: the gateway of its first parentRef, or the only
enabled Gateway when the route leaves it out. It goes into the route name, so
the same route name under two gateways gives two different resources.
Parameters: .route, .index (position in xroutes, for the message), .context.
*/}}
{{- define "ingress-gateway.helpers.app.routeParent" -}}
{{- $parentRefs := .route.parentRefs | default list -}}
{{- if not $parentRefs -}}
{{- fail (printf "xroutes[%d].parentRefs is required for route %s" (.index | int) (.route.name | toString)) -}}
{{- end -}}
{{- $first := index $parentRefs 0 | default dict -}}
{{- $parent := $first.gateway | default (include "ingress-gateway.helpers.app.soleGateway" .context) -}}
{{- if not $parent -}}
{{- fail (printf "xroutes[%d].parentRefs[].gateway is required (multiple Gateways - specify it explicitly)" (.index | int)) -}}
{{- end -}}
{{- $parent -}}
{{- end -}}

{{/*
Names that would collide in the cluster. Two resources of one kind cannot share
a name in a namespace, and nothing else stops values from asking for that: the
second definition would simply overwrite the first. Checked here, once per
render, so the order stops with a readable message instead.
Parameter: the root context.
*/}}
{{- define "ingress-gateway.helpers.app.uniqueNames" -}}
{{- $seen := dict -}}
{{- range $index, $gateway := .Values.gateways -}}
{{- if eq (include "ingress-gateway.helpers.app.enabled" $gateway) "true" -}}
{{- $name := $gateway.name | toString | lower -}}
{{- if hasKey $seen $name -}}
{{- fail (printf "gateways[%d].name %q is already taken by another Gateway; the two would share every resource name" $index $name) -}}
{{- end -}}
{{- $_ := set $seen $name true -}}
{{- end -}}
{{- end -}}
{{- $routes := dict -}}
{{- range $index, $route := .Values.xroutes -}}
{{- if eq (include "ingress-gateway.helpers.app.enabled" $route) "true" -}}
{{- $kind := $route.kind | default "HTTPRoute" | toString | lower -}}
{{- $parent := include "ingress-gateway.helpers.app.routeParent" (dict "route" $route "index" $index "context" $) -}}
{{- $key := printf "%s/%s/%s" $kind $parent ($route.name | toString | lower) -}}
{{- if hasKey $routes $key -}}
{{- fail (printf "xroutes[%d].name %q is already taken by another %s on gateway %q" $index ($route.name | toString) ($route.kind | default "HTTPRoute") $parent) -}}
{{- end -}}
{{- $_ := set $routes $key true -}}
{{- end -}}
{{- end -}}
{{- $certs := dict -}}
{{- range $index, $cert := ((.Values.tls | default dict).certificates | default list) -}}
{{- $name := $cert.name | toString | lower -}}
{{- if hasKey $certs $name -}}
{{- fail (printf "tls.certificates[%d].name %q is already taken by another certificate; a listener would get whichever of them was found first" $index $name) -}}
{{- end -}}
{{- $_ := set $certs $name true -}}
{{- end -}}
{{- end -}}

{{/*
Selector labels - stable identification of chart resources.
*/}}
{{- define "ingress-gateway.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ingress-gateway.helpers.app.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app: {{ .Chart.Name | quote }}
{{- end -}}

{{/*
Identity labels: ecpk/instance, ecpk/cluster, ecpk/project.

Each label is rendered only when the matching identity.* value is set, so a
partially filled identity block never produces an empty label value. Values are
lower-cased, exactly as they go into the resource name.
*/}}
{{- define "ingress-gateway.helpers.identityLabels" -}}
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
{{- define "ingress-gateway.helpers.app.labels" -}}
{{ include "ingress-gateway.helpers.app.selectorLabels" . }}
helm.sh/chart: {{ include "ingress-gateway.helpers.app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- include "ingress-gateway.helpers.identityLabels" . }}
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
