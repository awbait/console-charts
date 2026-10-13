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
The identity block the release runs under, as JSON (callers fromJson it).

global.identity wins over identity when a parent sets it: a parent chart hands
its tags to every subchart through global, and the default identity this chart
ships in values.yaml must not shadow them. With no parent, or a parent that
says nothing, the chart's own identity is used. Parameter: the root context.
*/}}
{{- define "namespace.helpers.identity" -}}
{{- $global := (.Values.global | default dict).identity | default dict -}}
{{- if gt (len $global) 0 -}}
{{- $global | toJson -}}
{{- else -}}
{{- .Values.identity | default dict | toJson -}}
{{- end -}}
{{- end -}}

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

The order names only the purpose (namespace.name); the
project and the cluster come from identity, so a name can never disagree with
the tags the same values put on the resource. Parameters: .context, .kindShort
(ns|subnet), .name. Truncated to 63 characters, e.g. nbox-dev-ns-app.
*/}}
{{- define "namespace.helpers.resourceName" -}}
{{- $identity := include "namespace.helpers.identity" .context | fromJson -}}
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
The purpose the namespace is named after: namespace.name, or
global.namespacePurpose when the chart's own field is empty.

Subcharts cannot read their parent's values, but Helm copies global into every
one of them, so a purpose entered once in global reaches both this chart and the
waypoint subchart, and the two arrive at the same namespace with nothing to keep
in sync by hand.
*/}}
{{- define "namespace.helpers.namespacePurpose" -}}
{{- $global := .Values.global | default dict -}}
{{- (.Values.namespace | default dict).name | default $global.namespacePurpose -}}
{{- end -}}

{{/*
The namespace name given outright: namespace.namespaceOverride, or
global.namespaceOverride when the chart's own field is empty. Empty when
neither is set. Validated as a DNS label of at most 63 characters and returned
in lower-case.

Some teams name namespaces by a scheme of their own rather
than the {project}-{cluster}-ns-{purpose} the chart builds. The global form is
the one the waypoint subchart reads too, so a single value moves both. A parent
that installs this chart twice (egress-gateway) must not use the global form:
both copies would claim the same namespace.
*/}}
{{- define "namespace.helpers.namespaceOverride" -}}
{{- $global := .Values.global | default dict -}}
{{- $override := (.Values.namespace | default dict).namespaceOverride | default $global.namespaceOverride | default "" | toString -}}
{{- if $override -}}
{{- $value := $override | lower -}}
{{- if gt (len $value) 63 -}}
{{- fail (printf "namespaceOverride must be at most 63 characters, got %q" $override) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "namespaceOverride must be DNS-like lowercase, got %q" $override) -}}
{{- end -}}
{{- $value -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Namespace the chart creates: the override when one is set,
otherwise built from identity and the purpose, e.g. nbox-dev-ns-app.
Every template that needs it calls this, so the Namespace, the ResourceQuota
inside it and the Subnet bound to it can never drift apart. The Subnet keeps
its own purpose-based name either way.
*/}}
{{- define "namespace.helpers.namespaceName" -}}
{{- $override := include "namespace.helpers.namespaceOverride" . -}}
{{- if $override -}}
{{- $override -}}
{{- else -}}
{{- include "namespace.helpers.resourceName" (dict "context" . "kindShort" "ns" "name" (include "namespace.helpers.namespacePurpose" .)) -}}
{{- end -}}
{{- end -}}

{{/*
Identity labels: ecpk/instance, ecpk/cluster, ecpk/project.

Each label is rendered only when the matching identity.* value is set, so a
partially filled identity block never produces an empty label value. Values are
lower-cased.
*/}}
{{- define "namespace.helpers.identityLabels" -}}
{{- $identity := include "namespace.helpers.identity" . | fromJson -}}
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
Argo CD sync wave of a resource, as an annotation dict for the metadata helper.
Cluster-scoped things have to exist before anything is put inside them: the
Namespace goes first (-3), the Subnet and the ResourceQuota next (-2), and
whatever a parent chart adds on top of them keeps the default wave 0. Outside
Argo CD the annotation is inert. Parameter: the wave as a string.
*/}}
{{- define "namespace.helpers.syncWave" -}}
{{- dict "argocd.argoproj.io/sync-wave" (toString .) | toJson -}}
{{- end -}}

{{/*
Whether the namespace is kept out of the mesh for good: serviceMesh.never.
Returns "true" or "" (for if-tests).

A namespace that holds a transit workload (the VpcEgressGateway pod of an egress
order) breaks the moment ambient intercepts it, in every cluster, so "never"
outranks the platform rule below that switches the mesh on outside dev.
*/}}
{{- define "namespace.helpers.serviceMeshNever" -}}
{{- $mesh := .Values.serviceMesh | default dict -}}
{{- ternary "true" "" (eq (toString ($mesh.never | default false) | lower) "true") -}}
{{- end -}}

{{/*
Whether the service mesh is on for this namespace. Returns "true" or "" (for
if-tests).

serviceMesh.never wins everywhere. Otherwise only the dev cluster leaves the
choice open: everywhere else the mesh is part of the platform and
serviceMesh.enabled is ignored rather than obeyed, so a namespace cannot quietly
opt out of the rules the environment runs on.
*/}}
{{- define "namespace.helpers.serviceMeshEnabled" -}}
{{- if eq (include "namespace.helpers.serviceMeshNever" .) "true" -}}
{{- "" -}}
{{- else -}}
{{- $identity := include "namespace.helpers.identity" . | fromJson -}}
{{- $cluster := include "namespace.helpers.tag" (dict "label" "identity.cluster" "value" $identity.cluster) -}}
{{- $mesh := .Values.serviceMesh | default dict -}}
{{- if eq $cluster "dev" -}}
{{- ternary "true" "" (eq (toString $mesh.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Whether the namespace is only discovered by the mesh: serviceMesh.discovery.
Returns "true" or "" (for if-tests).

Such a namespace gets istio-discovery: enabled, so Istio sees it and its
services resolve inside the mesh, and nothing else: no ambient label, so its
pods stay out of the ambient dataplane and nothing intercepts their traffic.
It is asked for explicitly and holds in every cluster, also where the platform
switches the mesh on: that rule decides between ambient and nothing, and this
is the third answer. serviceMesh.never still outranks it.
*/}}
{{- define "namespace.helpers.serviceMeshDiscovery" -}}
{{- $mesh := .Values.serviceMesh | default dict -}}
{{- ternary "true" "" (eq (toString ($mesh.discovery | default false) | lower) "true") -}}
{{- end -}}

{{/*
Pod Security Standards level of the namespace: namespace.podSecurity, one of
restricted|baseline|privileged, or empty when the namespace is left to the
platform. Returns the validated value (lower-case) or "".
*/}}
{{- define "namespace.helpers.podSecurity" -}}
{{- $value := (.Values.namespace | default dict).podSecurity | default "" | toString | lower -}}
{{- if and $value (not (has $value (list "restricted" "baseline" "privileged"))) -}}
{{- fail (printf "namespace.podSecurity must be one of restricted|baseline|privileged or empty, got %q" $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Guards the waypoint subchart: it is a mesh feature, and it deploys into the
namespace this chart creates.

The subchart cannot read this chart's values; it finds its namespace through
its own namespaceOverride / namespacePurpose or through the same two keys in
global. Whatever it will resolve to is rebuilt here and compared with the
namespace this chart creates: a waypoint standing in a namespace nobody
ordered, or falling back to the release namespace, is refused with a message
instead.
*/}}
{{- define "namespace.helpers.checkWaypoint" -}}
{{- $mesh := .Values.serviceMesh | default dict -}}
{{- if $mesh.waypoint -}}
{{- if eq (include "namespace.helpers.serviceMeshNever" .) "true" -}}
{{- fail "serviceMesh.waypoint and serviceMesh.never contradict each other: a waypoint is a mesh feature, drop one of them" -}}
{{- end -}}
{{- if ne (include "namespace.helpers.serviceMeshEnabled" .) "true" -}}
{{- fail "serviceMesh.waypoint needs the service mesh: set serviceMesh.enabled to true or drop the waypoint" -}}
{{- end -}}
{{- if eq (include "namespace.helpers.serviceMeshDiscovery" .) "true" -}}
{{- fail "serviceMesh.waypoint and serviceMesh.discovery contradict each other: a waypoint serves pods in the ambient dataplane, drop one of them" -}}
{{- end -}}
{{- $wanted := include "namespace.helpers.namespaceName" . -}}
{{- $global := .Values.global | default dict -}}
{{- $sub := .Values.waypoint | default dict -}}
{{- $override := $sub.namespaceOverride | default $global.namespaceOverride | default "" | toString -}}
{{- $purpose := $sub.namespacePurpose | default $global.namespacePurpose | default "" | toString -}}
{{- if $override -}}
{{- if ne ($override | lower) $wanted -}}
{{- fail (printf "waypoint.namespaceOverride must be the namespace this chart creates (%q), got %q" $wanted $override) -}}
{{- end -}}
{{- else if include "namespace.helpers.namespaceOverride" . -}}
{{- fail (printf "the waypoint subchart cannot see namespace.namespaceOverride (%q): put the name in global.namespaceOverride or repeat it in waypoint.namespaceOverride" $wanted) -}}
{{- else if $purpose -}}
{{- $resolved := include "namespace.helpers.resourceName" (dict "context" . "kindShort" "ns" "name" $purpose) -}}
{{- if ne $resolved $wanted -}}
{{- fail (printf "the waypoint subchart would land in %q (from namespacePurpose %q) while this chart creates %q: put the same purpose in global.namespacePurpose or waypoint.namespacePurpose" $resolved $purpose $wanted) -}}
{{- end -}}
{{- else -}}
{{- fail (printf "the waypoint subchart cannot see namespace.name (%q): put the purpose in global.namespacePurpose or repeat it in waypoint.namespacePurpose" (include "namespace.helpers.namespacePurpose" .)) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Guard the identity and target namespace of the subnet dependency. */}}
{{- define "namespace.helpers.checkSubnet" -}}
{{- if .Values.subnet.enabled -}}
{{- if ne (include "namespace.helpers.chartEnabled" .) "true" -}}
{{- fail "subnet.enabled requires namespace enabled=true; disable subnet.enabled too" -}}
{{- end -}}
{{- $child := index .Subcharts "subnet" -}}
{{- if not $child.Values.namespaceBinding.enabled -}}
{{- fail "namespace requires subnet.namespaceBinding.enabled=true" -}}
{{- end -}}
{{- $parentIdentity := include "namespace.helpers.identity" . | fromJson -}}
{{- $childIdentity := include "subnet.helpers.identity" $child | fromJson -}}
{{- if not (deepEqual $parentIdentity $childIdentity) -}}
{{- fail "namespace and subnet identity must match: set shared tags in global.identity" -}}
{{- end -}}
{{- $wanted := include "namespace.helpers.namespaceName" . -}}
{{- $actual := include "subnet.helpers.boundNamespace" $child -}}
{{- if ne $wanted $actual -}}
{{- fail (printf "subnet would bind to %q instead of %q: use global.namespacePurpose/global.namespaceOverride or subnet.namespaceBinding overrides" $actual $wanted) -}}
{{- end -}}
{{- end -}}
{{- end -}}
