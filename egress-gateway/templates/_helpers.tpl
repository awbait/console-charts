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
Params: .context, .kindShort (igw|egw|veg), .name (2..6 characters),
        .parent (optional, parent Gateway name, 2..6 characters; for TLSRoute).
*/}}
{{- define "egress-gateway.helpers.app.fullname" -}}
{{- $identity := .context.Values.identity | default dict -}}
{{- $instance := include "egress-gateway.helpers.tag" (dict "label" "identity.instance" "value" $identity.instance) -}}
{{- $cluster := include "egress-gateway.helpers.tag" (dict "label" "identity.cluster" "value" $identity.cluster) -}}
{{- $project := include "egress-gateway.helpers.shortToken" (dict "label" "identity.project" "value" $identity.project "max" 9) -}}
{{- $kind := required "kindShort is required" .kindShort | toString | lower -}}
{{- if not (has $kind (list "igw" "egw" "veg")) -}}
{{- fail (printf "kindShort must be one of igw|egw|veg, got %q" $kind) -}}
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
Listener protocol validation. Params: .label, .value (default TLS).
Allowed: TLS or HTTPS. Returns the canonical upper-case value.
*/}}
{{- define "egress-gateway.helpers.listenerProtocol" -}}
{{- $value := .value | default "TLS" | toString | upper -}}
{{- if not (has $value (list "TLS" "HTTPS")) -}}
{{- fail (printf "%s must be TLS or HTTPS, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Names that would collide in the cluster. Two point-of-exit entries with one name
give two ServiceEntries and two routes called the same, and two outbound
addresses with one name give two VpcEgressGateways: the second definition simply
overwrites the first. Checked here, once per render, so the order stops with a
readable message instead.
Parameter: the root context.
*/}}
{{- define "egress-gateway.helpers.app.uniqueNames" -}}
{{- $listeners := dict -}}
{{- range $index, $listener := ((.Values.egressGateway | default dict).listeners | default list) -}}
{{- $name := $listener.name | toString | lower -}}
{{- if hasKey $listeners $name -}}
{{- fail (printf "egressGateway.listeners[%d].name %q is already taken by another point of exit; the two would share the ServiceEntry and the route" $index $name) -}}
{{- end -}}
{{- $_ := set $listeners $name true -}}
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
Route Kind by listener protocol. Param: the canonical protocol string.
TLS -> TLSRoute, HTTPS -> HTTPRoute.
*/}}
{{- define "egress-gateway.helpers.routeKind" -}}
{{- if eq . "HTTPS" -}}HTTPRoute{{- else -}}TLSRoute{{- end -}}
{{- end -}}

{{/*
apiVersion for a route by its Kind. Param: the canonical route Kind.
HTTPRoute is GA (v1); TLSRoute is still v1alpha2.
*/}}
{{- define "egress-gateway.helpers.routeApiVersion" -}}
{{- if eq . "HTTPRoute" -}}gateway.networking.k8s.io/v1{{- else -}}gateway.networking.k8s.io/v1alpha2{{- end -}}
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
