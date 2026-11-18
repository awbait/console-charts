{{/*
Chart-wide switch: root "enabled", true unless values say otherwise. Returns
"true" or "" (for if-tests). Every template of the chart hangs on it, so
enabled: false renders nothing at all. The namespace subcharts have switches of
their own (vegNamespace.enabled): a parent cannot
reach into them.
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
The identity block of the release, as JSON (callers fromJson it).

It lives in global.identity, not at the root: the namespace subchart builds its names from the same tags, and
global is the only place Helm copies into every subchart. A root identity is
refused rather than ignored, because the subcharts would fall back to the
default tags of their own values.yaml and name their namespaces after a
project nobody ordered. Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.identity" -}}
{{- if .Values.identity -}}
{{- fail "identity moved to global.identity: the namespace subcharts read the tags from there, a root identity would not reach them" -}}
{{- end -}}
{{- $identity := (.Values.global | default dict).identity | default dict -}}
{{- if not $identity -}}
{{- fail "global.identity is required: instance, cluster and project tags of the release" -}}
{{- end -}}
{{- $identity | toJson -}}
{{- end -}}

{{/*
Base application name (for labels) = identity.project.
*/}}
{{- define "egress-gateway.helpers.app.name" -}}
{{- $identity := include "egress-gateway.helpers.identity" . | fromJson -}}
{{- required "global.identity.project is required" $identity.project | toString | lower | trunc 63 | trimSuffix "-" -}}
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
the optional bounds .min (default 2) and .max (default 9).
Returns the value in lower-case.
*/}}
{{- define "egress-gateway.helpers.shortToken" -}}
{{- $min := .min | default 2 | int -}}
{{- $max := .max | default 9 | int -}}
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
Namespace name validation (senders.namespace and the like). Params: .label,
.value. Returns the value in lower-case.
*/}}
{{- define "egress-gateway.helpers.namespaceToken" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | trim | lower -}}
{{- if or (gt (len $value) 63) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value)) -}}
{{- fail (printf "%s must be a namespace name (DNS-like lowercase, up to 63 characters), got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Full resource name by convention:
  without parent: {instance}-{cluster}-{kindShort}-{project}-{name}
  with parent:    {instance}-{cluster}-{kindShort}-{parent}-{project}-{name}
Params: .context, .kindShort (egw|veg|np|ap|wp), .name (2..9 characters),
        .parent (optional, the egress name, 2..9 characters; for the
        NetworkPolicies, of which one waypoint has several).
The longest name the parts can make is 40 characters, well inside the 63 the
truncation below guards: 2 + 3 + 3 + 9 + 9 + 9 plus five dashes.
*/}}
{{- define "egress-gateway.helpers.app.fullname" -}}
{{- $identity := include "egress-gateway.helpers.identity" .context | fromJson -}}
{{- $instance := include "egress-gateway.helpers.tag" (dict "label" "global.identity.instance" "value" $identity.instance) -}}
{{- $cluster := include "egress-gateway.helpers.tag" (dict "label" "global.identity.cluster" "value" $identity.cluster) -}}
{{- $project := include "egress-gateway.helpers.shortToken" (dict "label" "global.identity.project" "value" $identity.project "max" 9) -}}
{{- $kind := required "kindShort is required" .kindShort | toString | lower -}}
{{- if not (has $kind (list "egw" "veg" "np" "ap" "wp")) -}}
{{- fail (printf "kindShort must be one of egw|veg|np|ap|wp, got %q" $kind) -}}
{{- end -}}
{{- $name := include "egress-gateway.helpers.shortToken" (dict "label" "name" "value" .name) -}}
{{- if .parent -}}
{{- $parent := include "egress-gateway.helpers.shortToken" (dict "label" "waypoint name" "value" .parent) -}}
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
Mode of the release: mesh (the senders sit in ambient, only the external hosts
named in serviceEntries leave through the waypoint and the VIP) or direct (the
senders are outside the mesh, everything that leaves their subnet goes through
the VIP). Returns the validated value. Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.mode" -}}
{{- $mode := .Values.mode | default "mesh" | toString | lower -}}
{{- if not (has $mode (list "mesh" "direct")) -}}
{{- fail (printf "mode must be mesh or direct, got %q" $mode) -}}
{{- end -}}
{{- $mode -}}
{{- end -}}

{{/* Validated sender namespace list, as JSON. */}}
{{- define "egress-gateway.helpers.sendersNamespaces" -}}
{{- $values := (.Values.senders | default dict).namespace -}}
{{- if not (kindIs "slice" $values) -}}
{{- fail "senders.namespace must be a non-empty list of namespace names" -}}
{{- end -}}
{{- if not $values -}}{{- fail "senders.namespace must contain at least one namespace" -}}{{- end -}}
{{- $all := list -}}
{{- range $index, $value := $values -}}
{{- if not (kindIs "string" $value) -}}{{- fail "senders.namespace items must be strings" -}}{{- end -}}
{{- $name := include "egress-gateway.helpers.namespaceToken" (dict "label" (printf "senders.namespace[%d]" $index) "value" $value) -}}
{{- if has $name $all -}}{{- fail (printf "senders.namespace[%d] %q is already listed" $index $name) -}}{{- end -}}
{{- $all = append $all $name -}}
{{- end -}}
{{- $all | toJson -}}
{{- end -}}

{{/*
Name of a namespace the namespace subchart creates, built the way that chart
builds it: {project}-{cluster}-ns-{purpose}, purpose 2..12 characters. The
subchart cannot report the name back, so the same formula is repeated here.
Params: .context, .purpose, .label (for the message).
*/}}
{{- define "egress-gateway.helpers.namespaceName" -}}
{{- $identity := include "egress-gateway.helpers.identity" .context | fromJson -}}
{{- $project := include "egress-gateway.helpers.shortToken" (dict "label" "global.identity.project" "value" $identity.project "max" 9) -}}
{{- $cluster := include "egress-gateway.helpers.tag" (dict "label" "global.identity.cluster" "value" $identity.cluster) -}}
{{- $purpose := include "egress-gateway.helpers.shortToken" (dict "label" .label "value" .purpose "max" 12) -}}
{{- printf "%s-%s-ns-%s" $project $cluster $purpose | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Namespace of the VpcEgressGateway, created by the vegNamespace subchart. */}}
{{- define "egress-gateway.helpers.vegNamespace" -}}
{{- $purpose := ((.Values.vegNamespace | default dict).namespace | default dict).name | default "" | toString -}}
{{- if not $purpose -}}
{{- fail "vegNamespace.namespace.name is required: the purpose part of the VpcEgressGateway namespace name, for example veg-vip" -}}
{{- end -}}
{{- include "egress-gateway.helpers.namespaceName" (dict "context" . "purpose" $purpose "label" "vegNamespace.namespace.name") -}}
{{- end -}}

{{/* Gateway name follows the egress name, identically in each sender namespace. */}}
{{- define "egress-gateway.helpers.gatewayFullname" -}}
{{- include "egress-gateway.helpers.app.fullname" (dict "kindShort" "wp" "name" .Values.vpcEgressGateway.name "context" .) -}}
{{- end -}}

{{/*
Full name of the VpcEgressGateway (kindShort veg). Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.vegFullname" -}}
{{- $veg := .Values.vpcEgressGateway | default dict -}}
{{- include "egress-gateway.helpers.app.fullname" (dict "kindShort" "veg" "name" (required "vpcEgressGateway.name is required" $veg.name) "context" .) -}}
{{- end -}}

{{/*
Selector of the pods the Istio Gateway controller creates for a Gateway. The
label is set by the controller and carries the full Gateway name, so it is how
the NetworkPolicy and the VpcEgressGateway reach the gateway workload.
Parameter: .gatewayResourceName.
*/}}
{{- define "egress-gateway.helpers.gatewayWorkloadSelectorLabels" -}}
gateway.networking.k8s.io/gateway-name: {{ required "gatewayResourceName is required" .gatewayResourceName | quote }}
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
Every invariant of the release, checked once per template so the order stops
with a readable message instead of a manifest that is wrong in the cluster.
Parameter: the root context. Renders nothing.
*/}}
{{- define "egress-gateway.helpers.validate" -}}
{{- range $key := list "waypointNamespace" "waypoint" -}}
{{- if hasKey $.Values $key -}}{{- fail (printf "%s is no longer supported: mesh creates a fixed waypoint in every senders.namespace" $key) -}}{{- end -}}
{{- end -}}
{{- range $key := list "additionalNamespaces" "additionalSubnets" -}}
{{- if hasKey ($.Values.senders | default dict) $key -}}{{- fail (printf "senders.%s is no longer supported: use senders.namespace or senders.subnet lists" $key) -}}{{- end -}}
{{- end -}}
{{- $mode := include "egress-gateway.helpers.mode" . -}}
{{- $sendersAll := include "egress-gateway.helpers.sendersNamespaces" . | fromJsonArray -}}
{{- $veg := .Values.vpcEgressGateway | default dict -}}
{{- $_ := include "egress-gateway.helpers.vegFullname" . -}}
{{- if not $veg.externalIPs -}}
{{- fail "vpcEgressGateway.externalIPs is required: the addresses the traffic leaves with, one replica per address" -}}
{{- end -}}
{{- $vegNs := .Values.vegNamespace | default dict -}}
{{- $fixedSubnet := dict "enabled" false "namespaceBinding" (dict "enabled" true) "subnet" (dict "name" "" "reservedIps" 0 "cidrBlock" "") -}}
{{- if ne (toJson $vegNs.subnet) (toJson $fixedSubnet) -}}
{{- fail "vegNamespace.subnet is not configurable: remove custom subnet settings; the VEG namespace uses ovn-default" -}}
{{- end -}}
{{- /* The namespace name must agree with the vegNamespace subchart. */ -}}
{{- if (.Values.global | default dict).namespaceOverride -}}
{{- fail "global.namespaceOverride is not supported here: use vegNamespace.namespace.name" -}}
{{- end -}}
{{- range $key := list "vegNamespace" -}}
{{- if ((index $.Values $key | default dict).namespace | default dict).namespaceOverride -}}
{{- fail (printf "%s.namespace.namespaceOverride is not supported here: the chart builds that namespace name itself from identity and the purpose" $key) -}}
{{- end -}}
{{- end -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $vegNs) "" -}}
{{- fail "vegNamespace.enabled must stay true: the VpcEgressGateway needs a namespace of its own in both modes" -}}
{{- end -}}
{{- $vegNsName := include "egress-gateway.helpers.vegNamespace" . -}}
{{- if ne (toString (($vegNs.serviceMesh | default dict).never | default false) | lower) "true" -}}
{{- fail "vegNamespace.serviceMesh.never must be true: a VpcEgressGateway pod breaks the moment ambient intercepts it, the namespace has to stay out of the mesh in every cluster" -}}
{{- end -}}
{{- if ne (($vegNs.namespace | default dict).role | default "" | toString) "egress" -}}
{{- fail "vegNamespace.namespace.role must be egress: the cluster policies tell the VpcEgressGateway namespace apart by that label" -}}
{{- end -}}
{{- if has $vegNsName $sendersAll -}}
{{- fail (printf "%q is the namespace the VpcEgressGateway is created in, but it is named among the senders (senders.namespace): the senders live in namespaces of their own, ordered separately" $vegNsName) -}}
{{- end -}}
{{- $networkPolicy := .Values.networkPolicy | default dict -}}
{{- $authorizationPolicy := .Values.authorizationPolicy | default dict -}}
{{- if eq $mode "mesh" -}}
{{- $_ := include "egress-gateway.helpers.gatewayFullname" . -}}
{{- $entries := list -}}
{{- range $entry := (.Values.serviceEntries | default list) -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $entry) "true" -}}
{{- $entries = append $entries $entry -}}
{{- end -}}
{{- end -}}
{{- if not $entries -}}
{{- fail "serviceEntries must contain at least one external service: in mode mesh only the hosts named there leave through the gateway" -}}
{{- end -}}
{{- include "egress-gateway.helpers.app.uniqueNames" . -}}
{{- else -}}
{{- if .Values.serviceEntries -}}
{{- fail "mode direct takes no serviceEntries: without a waypoint there is nothing to bind a ServiceEntry to, the whole external traffic of the senders leaves through the VIP" -}}
{{- end -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $networkPolicy) "true" -}}
{{- fail "mode direct has no network policies: they guard the waypoint, which does not exist here; set networkPolicy.enabled to false" -}}
{{- end -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $authorizationPolicy) "true" -}}
{{- fail "mode direct has no authorization policy: it targets the waypoint, which does not exist here; set authorizationPolicy.enabled to false" -}}
{{- end -}}
{{- $scope := include "egress-gateway.helpers.scope" . -}}
{{- if eq $scope "subnet" -}}
{{- $_ := include "egress-gateway.helpers.sendersSubnets" . -}}
{{- else -}}
{{- $_ := include "egress-gateway.helpers.egressLabel" . -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
What the VpcEgressGateway captures in mode direct: subnet (the whole subnet
of the senders) or label (only the pods carrying vpcEgressGateway.label).
Returns the validated value. Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.scope" -}}
{{- $scope := (.Values.vpcEgressGateway | default dict).scope | default "subnet" | toString | lower -}}
{{- if not (has $scope (list "subnet" "label")) -}}
{{- fail (printf "vpcEgressGateway.scope must be subnet or label, got %q" $scope) -}}
{{- end -}}
{{- $scope -}}
{{- end -}}

{{/* Validated Subnet name list for direct subnet scope, as JSON. */}}
{{- define "egress-gateway.helpers.sendersSubnets" -}}
{{- $values := (.Values.senders | default dict).subnet -}}
{{- if not (kindIs "slice" $values) -}}
{{- fail "senders.subnet must be a non-empty list of Subnet names in mode direct with scope subnet" -}}
{{- end -}}
{{- if not $values -}}
{{- fail "senders.subnet must contain at least one Subnet in mode direct with scope subnet" -}}
{{- end -}}
{{- $all := list -}}
{{- range $index, $value := $values -}}
{{- if not (kindIs "string" $value) -}}{{- fail "senders.subnet items must be strings" -}}{{- end -}}
{{- $name := include "egress-gateway.helpers.namespaceToken" (dict "label" (printf "senders.subnet[%d]" $index) "value" $value) -}}
{{- if has $name $all -}}
{{- fail (printf "senders.subnet[%d] %q is already listed" $index $name) -}}
{{- end -}}
{{- $all = append $all $name -}}
{{- end -}}
{{- $all | toJson -}}
{{- end -}}

{{/*
The label key that marks a sender pod in mode direct with scope label:
vpcEgressGateway.label, a label key with an optional prefix. Parameter: the
root context.
*/}}
{{- define "egress-gateway.helpers.egressLabel" -}}
{{- $value := (.Values.vpcEgressGateway | default dict).label | default "ecpk/egress" | toString | trim -}}
{{- if not (regexMatch "^([a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*/)?[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$" $value) -}}
{{- fail (printf "vpcEgressGateway.label must be a label key, got %q" $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Names that would collide in the cluster: two external services with one name
give two ServiceEntries called the same, two entries with one hostname bind the
same host twice. Checked from validate, so the order stops with a readable
message instead. Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.app.uniqueNames" -}}
{{- $entries := dict -}}
{{- $hostnames := dict -}}
{{- range $index, $entry := (.Values.serviceEntries | default list) -}}
{{- if eq (include "egress-gateway.helpers.app.enabled" $entry) "true" -}}
{{- $name := required (printf "serviceEntries[%d].name is required" $index) $entry.name | toString | lower -}}
{{- if hasKey $entries $name -}}
{{- fail (printf "serviceEntries[%d].name %q is already taken by another external service; the two would share one ServiceEntry" $index $name) -}}
{{- end -}}
{{- $_ := set $entries $name true -}}
{{- $hostname := required (printf "serviceEntries[%d].hostname is required" $index) $entry.hostname | toString | lower -}}
{{- if hasKey $hostnames $hostname -}}
{{- fail (printf "serviceEntries[%d].hostname %q is already taken by another external service; the two would bind one host twice" $index $hostname) -}}
{{- end -}}
{{- $_ := set $hostnames $hostname true -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Port of an external service: serviceEntries[].port, 443 when not set. The
schema checks the range too, it is repeated here for values that skip the
form. Parameters: entry, index.
*/}}
{{- define "egress-gateway.helpers.serviceEntryPort" -}}
{{- $raw := 443 -}}
{{- if and (hasKey .entry "port") (not (kindIs "invalid" .entry.port)) -}}
{{- $raw = .entry.port -}}
{{- end -}}
{{- if not (regexMatch "^[0-9]+$" (toString $raw)) -}}
{{- fail (printf "serviceEntries[%d].port must be a number from 1 to 65535, got %v" .index $raw) -}}
{{- end -}}
{{- $port := int64 $raw -}}
{{- if or (lt $port 1) (gt $port 65535) -}}
{{- fail (printf "serviceEntries[%d].port must be a number from 1 to 65535, got %v" .index $raw) -}}
{{- end -}}
{{- $port -}}
{{- end -}}

{{/*
Protocol of an external service: serviceEntries[].protocol, TLS when not set.
Upper case, one of TLS, HTTP, TCP. Parameters: entry, index.
*/}}
{{- define "egress-gateway.helpers.serviceEntryProtocol" -}}
{{- $protocol := .entry.protocol | default "TLS" | toString | upper -}}
{{- if not (has $protocol (list "TLS" "HTTP" "TCP")) -}}
{{- fail (printf "serviceEntries[%d].protocol must be one of TLS, HTTP, TCP, got %q" .index .entry.protocol) -}}
{{- end -}}
{{- $protocol -}}
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
{{- $identity := include "egress-gateway.helpers.identity" . | fromJson -}}
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
