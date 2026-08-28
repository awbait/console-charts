{{/*
Chart-wide switch: root "enabled", true unless values say otherwise. Returns
"true" or "" (for if-tests). Every template of the chart hangs on it, so
enabled: false renders nothing at all.
*/}}
{{- define "egress-gateway.helpers.chartEnabled" -}}
{{- if hasKey .Values "enabled" -}}
{{- ternary "true" "" (eq (toString .Values.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Chart name for helm.sh/chart.
*/}}
{{- define "egress-gateway.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base application name (for labels) = identity.project.
*/}}
{{- define "egress-gateway.helpers.app.name" -}}
{{- required "identity.project is required" (.Values.identity | default dict).project | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
DNS tag validation (identity.instance, identity.cluster). Params: .label, .value.
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
Short DNS tag validation (identity.project, name). Params: .label, .value and
the optional bounds .min (default 2) and .max (default 6).
Returns the value in lower-case.
*/}}
{{- define "egress-gateway.helpers.shortToken" -}}
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
Full resource name by convention:
  without parent: {instance}-{cluster}-{kindShort}-{project}-{name}
  with parent:    {instance}-{cluster}-{kindShort}-{parent}-{project}-{name}
Params: .context, .kindShort (egw|veg|np|ap|tr|rg), .name (2..6 characters),
        .parent (optional, parent Gateway name, 2..6 characters; for the
        NetworkPolicies, of which one gateway has two, and for the outbound
        TLSRoute, which shares its name with the inbound one).
*/}}
{{- define "egress-gateway.helpers.app.fullname" -}}
{{- $identity := .context.Values.identity | default dict -}}
{{- $instance := include "egress-gateway.helpers.tag" (dict "label" "identity.instance" "value" $identity.instance) -}}
{{- $cluster := include "egress-gateway.helpers.tag" (dict "label" "identity.cluster" "value" $identity.cluster) -}}
{{- $project := include "egress-gateway.helpers.shortToken" (dict "label" "identity.project" "value" $identity.project "max" 9) -}}
{{- $kind := required "kindShort is required" .kindShort | toString | lower -}}
{{- if not (has $kind (list "egw" "veg" "np" "ap" "tr" "rg")) -}}
{{- fail (printf "kindShort must be one of egw|veg|np|ap|tr|rg, got %q" $kind) -}}
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
Resolve an "enabled" flag. Param: the entity (dict). An explicit false is
respected; a missing key defaults to true. Returns "true" or "" (for if-tests).
Avoids the `| default true` pitfall that turns an explicit false into true.
*/}}
{{- define "egress-gateway.helpers.app.enabled" -}}
{{- $entity := . | default dict -}}
{{- if hasKey $entity "enabled" -}}
{{- ternary "true" "" (eq (toString $entity.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Listener name of an external service: the deepest level of its domain, which is
the first label of the hostname (kc.idp.ecpk.test -> kc). It names the listener
on the Gateway and pins the outbound route to it through sectionName.
Params: .label, .value (the hostname).
*/}}
{{- define "egress-gateway.helpers.app.listenerName" -}}
{{- $hostname := required (printf "%s is required" .label) .value | toString | lower | trim -}}
{{- $name := index (splitList "." $hostname) 0 -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name) -}}
{{- fail (printf "%s must start with a DNS-like label, got %q" .label $hostname) -}}
{{- end -}}
{{- $name -}}
{{- end -}}

{{/*
Namespace an external service lands in: serviceEntries[].namespace when set,
the release namespace otherwise. Params: .entry, .context.
*/}}
{{- define "egress-gateway.helpers.app.serviceEntryNamespace" -}}
{{- $namespace := (.entry | default dict).namespace | default "" | toString | trim -}}
{{- if $namespace -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $namespace) -}}
{{- fail (printf "serviceEntries namespace must be DNS-like lowercase, got %q" $namespace) -}}
{{- end -}}
{{- $namespace -}}
{{- else -}}
{{- .context.Release.Namespace -}}
{{- end -}}
{{- end -}}

{{/*
Every namespace a sender of this release sits in: the release namespace plus the
namespace of each enabled external service. Returned as a JSON array in
declaration order. It drives who may reach the gateway (NetworkPolicy,
AuthorizationPolicy) and which namespaces need a ReferenceGrant. A single element
means every sender sits in the release namespace and nothing crosses a boundary.
Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.app.backendNamespaces" -}}
{{- $namespaces := list .Release.Namespace -}}
{{- range $index, $entry := (.Values.serviceEntries | default list) -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $entry) "true" -}}
{{- $namespace := include "egress-gateway.helpers.app.serviceEntryNamespace" (dict "entry" $entry "context" $) -}}
{{- if not (has $namespace $namespaces) -}}
{{- $namespaces = append $namespaces $namespace -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $namespaces | toJson -}}
{{- end -}}

{{/*
Names that would collide in the cluster. Two external services with one name in
one namespace give two ServiceEntries called the same, two hostnames sharing a
first label give two listeners called the same, and two outbound addresses with
one name give two VpcEgressGateways: the second definition simply overwrites the
first. Checked here, once per render, so the order stops with a readable message
instead.
Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.app.uniqueNames" -}}
{{- $entries := dict -}}
{{- $listeners := dict -}}
{{- range $index, $entry := (.Values.serviceEntries | default list) -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $entry) "true" -}}
{{- $namespace := include "egress-gateway.helpers.app.serviceEntryNamespace" (dict "entry" $entry "context" $) -}}
{{- $key := printf "%s/%s" $namespace ($entry.name | toString | lower) -}}
{{- if hasKey $entries $key -}}
{{- fail (printf "serviceEntries[%d].name %q is already taken by another external service in namespace %q; the two would share one ServiceEntry" $index ($entry.name | toString | lower) $namespace) -}}
{{- end -}}
{{- $_ := set $entries $key true -}}
{{- $listener := include "egress-gateway.helpers.app.listenerName" (dict "label" (printf "serviceEntries[%d].hostname" $index) "value" $entry.hostname) -}}
{{- if hasKey $listeners $listener -}}
{{- fail (printf "serviceEntries[%d].hostname %q starts with %q, which another external service already uses for its listener; give the two domains different first labels" $index ($entry.hostname | toString | lower) $listener) -}}
{{- end -}}
{{- $_ := set $listeners $listener true -}}
{{- end -}}
{{- end -}}
{{- $vegs := dict -}}
{{- range $index, $veg := (.Values.vpcEgressGateway | default list) -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $veg) "true" -}}
{{- $name := $veg.name | toString | lower -}}
{{- if hasKey $vegs $name -}}
{{- fail (printf "vpcEgressGateway[%d].name %q is already taken by another outbound address" $index $name) -}}
{{- end -}}
{{- $_ := set $vegs $name true -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
The egress Gateway this release builds everything around: fails when the gateway
is switched off or unnamed, returns its full resource name otherwise. Every
resource that points at the gateway (ServiceEntry labels, VpcEgressGateway
selectors) goes through here. Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.app.gatewayFullname" -}}
{{- $gw := .Values.egressGateway | default dict -}}
{{- if not (and $gw (eq (include "egress-gateway.helpers.app.enabled" $gw) "true")) -}}
{{- fail "egressGateway must be enabled: the external services, the routes and the outbound addresses of this release all point at it" -}}
{{- end -}}
{{- $gwName := required "egressGateway.name is required" $gw.name -}}
{{- include "egress-gateway.helpers.app.fullname" (dict "kindShort" "egw" "name" $gwName "context" .) -}}
{{- end -}}

{{/*
Selector of the pods the Istio Gateway controller creates for a Gateway. The
label is set by the controller and carries the full Gateway name, so it is how
the NetworkPolicy and the VpcEgressGateway reach the gateway workload.
Parameter: .gatewayResourceName.
*/}}
{{- define "egress-gateway.helpers.app.gatewayWorkloadSelectorLabels" -}}
gateway.networking.k8s.io/gateway-name: {{ required "gatewayResourceName is required" .gatewayResourceName | quote }}
{{- end -}}

{{/*
Namespace the VpcEgressGateway lands in: the namespace the chart creates when
egressNamespace.enabled, the release namespace otherwise. The kube-ovn subnet
the outbound traffic is SNAT'ed from carries the same name, so this is also the
subnet name that goes into the VpcEgressGateway policies.
Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.app.egressNamespace" -}}
{{- $egressNamespace := .Values.egressNamespace | default dict -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $egressNamespace) "true" -}}
{{- $name := required "egressNamespace.name is required when egressNamespace.enabled=true" $egressNamespace.name | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $name) -}}
{{- fail (printf "egressNamespace.name must be DNS-like lowercase, got %q" $name) -}}
{{- end -}}
{{- $name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Namespace -}}
{{- end -}}
{{- end -}}

{{/*
CIDR of the egress subnet: required when the namespace is created, and always a
/29 - the subnet holds one gateway address and a handful of VpcEgressGateway
pods, nothing else.
Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.app.egressSubnetCidr" -}}
{{- $egressNamespace := .Values.egressNamespace | default dict -}}
{{- $cidr := required "egressNamespace.cidrBlock is required when egressNamespace.enabled=true" $egressNamespace.cidrBlock | toString | trim -}}
{{- if not (regexMatch "^([0-9]{1,3}\\.){3}[0-9]{1,3}/29$" $cidr) -}}
{{- fail (printf "egressNamespace.cidrBlock must be an IPv4 /29 block, got %q" $cidr) -}}
{{- end -}}
{{- $cidr -}}
{{- end -}}

{{/*
Gateway address of a subnet: the network address plus one, the same rule the
namespace chart follows. Parameter: the CIDR block.
*/}}
{{- define "egress-gateway.helpers.app.subnetGatewayIP" -}}
{{- $octets := splitList "." (index (splitList "/" .) 0) -}}
{{- printf "%s.%s.%s.%d" (index $octets 0) (index $octets 1) (index $octets 2) (add (index $octets 3 | int) 1) -}}
{{- end -}}

{{/*
Address of an external endpoint as a NetworkPolicy CIDR: a bare IP becomes a
single-host block, a CIDR is passed through. Params: .label, .value.
*/}}
{{- define "egress-gateway.helpers.app.endpointCidr" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | trim -}}
{{- if contains "/" $value -}}
{{- $value -}}
{{- else -}}
{{- printf "%s/32" $value -}}
{{- end -}}
{{- end -}}

{{/*
Selector labels - stable workload identification.
*/}}
{{- define "egress-gateway.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "egress-gateway.helpers.app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Chart.Name }}
{{- end -}}

{{/*
Identity labels: ecpk/instance, ecpk/cluster, ecpk/project.

Each label is rendered only when the matching identity.* value is set, so a
partially filled identity block never produces an empty label value. Values are
lower-cased, exactly as they go into the resource name.
*/}}
{{- define "egress-gateway.helpers.identityLabels" -}}
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
{{- define "egress-gateway.helpers.app.labels" -}}
{{ include "egress-gateway.helpers.app.selectorLabels" . }}
helm.sh/chart: {{ include "egress-gateway.helpers.app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- include "egress-gateway.helpers.identityLabels" . }}
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
Common metadata (labels + annotations) for every chart resource. Renders the
full "labels:" block and, only when non-empty, the "annotations:" block, so a
resource wires both in one call and never silently drops generic.* on a new
manifest. Parameters:
  .context     - root context ($), required;
  .labels      - optional dict of extra per-resource labels;
  .annotations - optional dict of extra per-resource annotations.
Call right under metadata.name/namespace:
  {{- include "egress-gateway.helpers.app.metadata" (dict "context" $) | nindent 2 }}
*/}}
{{- define "egress-gateway.helpers.app.metadata" -}}
{{- $ctx := .context -}}
labels:
  {{- include "egress-gateway.helpers.app.labels" $ctx | nindent 2 }}
  {{- with .labels }}
  {{- include "egress-gateway.helpers.tplvalues.render" (dict "value" . "context" $ctx) | nindent 2 }}
  {{- end }}
{{- $generic := include "egress-gateway.helpers.app.genericAnnotations" $ctx | trim -}}
{{- $extra := "" -}}
{{- with .annotations }}{{- $extra = include "egress-gateway.helpers.tplvalues.render" (dict "value" . "context" $ctx) | trim -}}{{- end -}}
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
Generic templated-value rendering. Params: .value, .context.
*/}}
{{- define "egress-gateway.helpers.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
