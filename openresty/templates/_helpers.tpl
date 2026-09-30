{{/*
Chart-wide switch: root "enabled", true unless values say otherwise. Returns
"true" or "" (for if-tests). Every template of the chart hangs on it, so
enabled: false renders nothing at all.
*/}}
{{- define "openresty.helpers.chartEnabled" -}}
{{- if hasKey .Values "enabled" -}}
{{- ternary "true" "" (eq (toString .Values.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Chart name for helm.sh/chart.
*/}}
{{- define "openresty.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The identity block the release runs under, as JSON (callers fromJson it).
global.identity wins over identity when a parent sets it: a parent chart hands
its tags to every subchart through global, and the default identity this chart
ships in values.yaml must not shadow them. Parameter: the root context.
*/}}
{{- define "openresty.helpers.identity" -}}
{{- $global := (.Values.global | default dict).identity | default dict -}}
{{- if gt (len $global) 0 -}}
{{- $global | toJson -}}
{{- else -}}
{{- .Values.identity | default dict | toJson -}}
{{- end -}}
{{- end -}}

{{/*
Base application name (for labels) = identity.project.
*/}}
{{- define "openresty.helpers.app.name" -}}
{{- $identity := include "openresty.helpers.identity" . | fromJson -}}
{{- required "identity.project is required" $identity.project | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
DNS tag validation (identity.instance, identity.cluster). Parameters: .label, .value.
Returns the value in lower-case.
*/}}
{{- define "openresty.helpers.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Short DNS tag validation (identity.project, name). Parameters: .label, .value
and the optional bounds .min (default 2) and .max (default 6).
Returns the value in lower-case.
*/}}
{{- define "openresty.helpers.shortToken" -}}
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
Resource name by convention:
  {instance}-{cluster}-{kindShort}-{project}-{name}
Parameters: .context, .kindShort (dp | svc | cm), .name (2..6 characters).
The result is truncated to 63 characters. Example: ed-dev-dp-nbox-static.
The three resources of one server differ in kindShort only.
*/}}
{{- define "openresty.helpers.app.resourceName" -}}
{{- $identity := include "openresty.helpers.identity" .context | fromJson -}}
{{- $instance := include "openresty.helpers.tag" (dict "label" "identity.instance" "value" $identity.instance) -}}
{{- $cluster := include "openresty.helpers.tag" (dict "label" "identity.cluster" "value" $identity.cluster) -}}
{{- $project := include "openresty.helpers.shortToken" (dict "label" "identity.project" "value" $identity.project "max" 9) -}}
{{- $kind := required "kindShort is required" .kindShort | toString | lower -}}
{{- if not (has $kind (list "dp" "svc" "cm")) -}}
{{- fail (printf "kindShort must be one of dp, svc, cm, got %q" $kind) -}}
{{- end -}}
{{- $name := include "openresty.helpers.shortToken" (dict "label" "name" "value" .name) -}}
{{- printf "%s-%s-%s-%s-%s" $instance $cluster $kind $project $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels - stable identification of chart resources.
*/}}
{{- define "openresty.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "openresty.helpers.app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ .Chart.Name }}
{{- end -}}

{{/*
Selector labels of one server: the chart selector plus the server name as
component, so the Deployment and the Service of a server pick its pods and
nobody else's. Parameters: .context, .name (servers[].name).
*/}}
{{- define "openresty.helpers.app.serverSelectorLabels" -}}
{{ include "openresty.helpers.app.selectorLabels" .context }}
app.kubernetes.io/component: {{ include "openresty.helpers.shortToken" (dict "label" "servers[].name" "value" .name) }}
{{- end -}}

{{/*
Identity labels: ecpk/instance, ecpk/cluster, ecpk/project.
Each label is rendered only when the matching identity.* value is set, so a
partially filled identity block never produces an empty label value. Values are
lower-cased, exactly as they go into the resource name.
*/}}
{{- define "openresty.helpers.identityLabels" -}}
{{- $identity := include "openresty.helpers.identity" . | fromJson -}}
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
{{- define "openresty.helpers.app.labels" -}}
{{ include "openresty.helpers.app.selectorLabels" . }}
helm.sh/chart: {{ include "openresty.helpers.app.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- include "openresty.helpers.identityLabels" . }}
{{- with (.Values.generic | default dict).labels }}
{{ include "openresty.helpers.tplvalues.render" (dict "value" . "context" $) }}
{{- end }}
{{- end -}}

{{/*
Common annotations (generic.annotations). Empty -> outputs nothing.
*/}}
{{- define "openresty.helpers.app.genericAnnotations" -}}
{{- with (.Values.generic | default dict).annotations -}}
{{ include "openresty.helpers.tplvalues.render" (dict "value" . "context" $) }}
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
*/}}
{{- define "openresty.helpers.app.metadata" -}}
{{- $ctx := .context -}}
labels:
  {{- include "openresty.helpers.app.labels" $ctx | nindent 2 }}
  {{- with .labels }}
  {{- include "openresty.helpers.tplvalues.render" (dict "value" . "context" $ctx) | nindent 2 }}
  {{- end }}
{{- $generic := include "openresty.helpers.app.genericAnnotations" $ctx | trim -}}
{{- $extra := "" -}}
{{- with .annotations }}{{- $extra = include "openresty.helpers.tplvalues.render" (dict "value" . "context" $ctx) | trim -}}{{- end -}}
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
{{- define "openresty.helpers.app.enabled" -}}
{{- $entity := . | default dict -}}
{{- if hasKey $entity "enabled" -}}
{{- ternary "true" "" (eq (toString $entity.enabled | lower) "true") -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Container image reference: [registry/]repository:tag. The tag falls back to
appVersion, which is the OpenResty version the chart was built against.
Parameter: the root context.
*/}}
{{- define "openresty.helpers.app.image" -}}
{{- $image := .Values.image | default dict -}}
{{- $repository := required "image.repository is required" $image.repository | toString -}}
{{- $tag := $image.tag | default .Chart.AppVersion | toString -}}
{{- with $image.registry -}}{{- printf "%s/" (toString .) -}}{{- end -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}

{{/*
A value as an nginx double-quoted string, so that nginx reads back exactly the
text the values hold. The config parser of nginx turns \\ into \, \" into ",
\n into a newline and \t into a tab, so every backslash is doubled and the
quote, newline, return and tab are spelled as escapes. Parameter: the text.
The result carries no quotes of its own.
*/}}
{{- define "openresty.helpers.app.nginxString" -}}
{{- . | toString | replace "\\" "\\\\" | replace "\"" "\\\"" | replace "\r" "\\r" | replace "\n" "\\n" | replace "\t" "\\t" -}}
{{- end -}}

{{/*
Like nginxString, for directives whose argument nginx evaluates as a script
(return, add_header): a dollar there starts a variable, and nginx has no escape
for it, so it is spelled through the $dollar variable the http block defines.
Parameter: the text.
*/}}
{{- define "openresty.helpers.app.nginxScriptString" -}}
{{- include "openresty.helpers.app.nginxString" . | replace "$" "${dollar}" -}}
{{- end -}}

{{/*
What a location does: "response", "lua" or "proxyPass". Exactly one of the
three must be set; the render stops otherwise, because a location with two
handlers would silently serve one of them and one with none would 404.
Parameters: .location, .label (for messages).
*/}}
{{- define "openresty.helpers.app.locationKind" -}}
{{- $kinds := list -}}
{{- if hasKey .location "response" -}}{{- $kinds = append $kinds "response" -}}{{- end -}}
{{- if hasKey .location "lua" -}}{{- $kinds = append $kinds "lua" -}}{{- end -}}
{{- if hasKey .location "proxyPass" -}}{{- $kinds = append $kinds "proxyPass" -}}{{- end -}}
{{- if ne (len $kinds) 1 -}}
{{- fail (printf "%s must set exactly one of response, lua or proxyPass, got %d of them" .label (len $kinds)) -}}
{{- end -}}
{{- index $kinds 0 -}}
{{- end -}}

{{/*
The nginx "location" line for a path and its match rule. exact -> "= path",
prefix -> "path", regex -> "~ \"regex\"". The path of an exact or prefix
location must start with a slash and hold no whitespace, quotes or braces:
those would end the directive early or open a block. A regex is quoted and
escaped as a whole, so anything goes inside it.
Parameters: .location, .label.
*/}}
{{- define "openresty.helpers.app.locationLine" -}}
{{- $path := required (printf "%s.path is required" .label) .location.path | toString -}}
{{- $match := .location.match | default "exact" | toString | lower -}}
{{- if not (has $match (list "exact" "prefix" "regex")) -}}
{{- fail (printf "%s.match must be exact, prefix or regex, got %q" .label $match) -}}
{{- end -}}
{{- if eq $match "regex" -}}
{{- printf "location ~ \"%s\"" (include "openresty.helpers.app.nginxString" $path) -}}
{{- else -}}
{{- if not (regexMatch "^/[^\\s\"'{};]*$" $path) -}}
{{- fail (printf "%s.path must start with / and hold no whitespace, quotes, braces or semicolons, got %q" .label $path) -}}
{{- end -}}
{{- if and (eq $match "exact") (eq $path "/healthz") -}}
{{- fail (printf "%s.path /healthz is taken: the server answers its health checks there" .label) -}}
{{- end -}}
{{- if eq $match "exact" -}}
{{- printf "location = %s" $path -}}
{{- else -}}
{{- printf "location %s" $path -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
The body of one location block. Parameters: .location, .label.
*/}}
{{- define "openresty.helpers.app.locationBody" -}}
{{- $kind := include "openresty.helpers.app.locationKind" (dict "location" .location "label" .label) -}}
{{- if eq $kind "response" -}}
{{- $response := .location.response | default dict -}}
{{- $status := $response.status | default 200 | toString -}}
{{- if not (regexMatch "^[1-5][0-9][0-9]$" $status) -}}
{{- fail (printf "%s.response.status must be an HTTP status code from 100 to 599, got %q" .label $status) -}}
{{- end -}}
{{- $contentType := $response.contentType | default "text/plain" | toString -}}
{{- if not (regexMatch "^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+(;[ ]?[A-Za-z0-9._-]+=[A-Za-z0-9._-]+)*$" $contentType) -}}
{{- fail (printf "%s.response.contentType must be a media type such as application/json, got %q" .label $contentType) -}}
{{- end -}}
{{- /* An empty types table keeps the extension of the path from choosing the type: default_type then applies to every answer of the location. */ -}}
types { }
default_type {{ $contentType }};
{{- range $name, $value := $response.headers | default dict }}
{{- if not (regexMatch "^[A-Za-z0-9-]+$" $name) }}
{{- fail (printf "%s.response.headers holds a header name that is not one, got %q" $.label $name) }}
{{- end }}
add_header {{ $name }} "{{ include "openresty.helpers.app.nginxScriptString" $value }}" always;
{{- end }}
return {{ $status }} "{{ include "openresty.helpers.app.nginxScriptString" ($response.body | default "") }}";
{{- else if eq $kind "lua" -}}
{{- $lua := .location.lua | toString -}}
{{- if not (trim $lua) -}}
{{- fail (printf "%s.lua is empty" .label) -}}
{{- end -}}
content_by_lua_block {
{{ $lua | trimSuffix "\n" | indent 4 }}
}
{{- else -}}
{{- $target := .location.proxyPass | toString -}}
{{- if not (regexMatch "^https?://[^\\s\"'{};$]+$" $target) -}}
{{- fail (printf "%s.proxyPass must be an http:// or https:// address without spaces, quotes, braces or variables, got %q" .label $target) -}}
{{- end -}}
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_pass {{ $target }};
{{- end -}}
{{- end -}}

{{/*
The whole nginx.conf of one server. It replaces the file of the image, so
everything the server needs is here: temporary paths under /tmp and the pid
there too, because the root filesystem of the container is read-only and the
process is not root; logs to the standard streams; a resolver, because a Lua
handler resolves names through nginx, not through the system; and the $dollar
variable static bodies use to spell a dollar sign. The /healthz location
answers the probes of the pod and is reserved. Parameters: .server, .index,
.context.
*/}}
{{- define "openresty.helpers.app.nginxConf" -}}
{{- $server := .server -}}
{{- $label := printf "servers[%d]" (.index | int) -}}
{{- $dns := .context.Values.dns | default dict -}}
{{- $resolver := required "dns.resolver is required" $dns.resolver | toString -}}
{{- if not (regexMatch "^[A-Za-z0-9.:_-]+( [A-Za-z0-9.:_-]+)*$" $resolver) -}}
{{- fail (printf "dns.resolver must be one or more addresses separated by spaces, got %q" $resolver) -}}
{{- end -}}
{{- if not $server.locations -}}
{{- fail (printf "%s.locations must hold at least one location" $label) -}}
{{- end -}}
worker_processes auto;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    access_log /dev/stdout;
    server_tokens off;

    client_body_temp_path /tmp/client_body;
    proxy_temp_path /tmp/proxy;
    fastcgi_temp_path /tmp/fastcgi;
    uwsgi_temp_path /tmp/uwsgi;
    scgi_temp_path /tmp/scgi;

    resolver {{ $resolver }} valid=30s ipv6=off;

    geo $dollar {
        default "$";
    }

    server {
        listen 8080;
        server_name _;

        location = /healthz {
            types { }
            default_type text/plain;
            return 200 "ok\n";
        }
{{- range $index, $location := $server.locations }}
{{- $locationLabel := printf "%s.locations[%d]" $label $index }}

        {{ include "openresty.helpers.app.locationLine" (dict "location" $location "label" $locationLabel) }} {
            {{- include "openresty.helpers.app.locationBody" (dict "location" $location "label" $locationLabel) | nindent 12 }}
        }
{{- end }}
    }
}
{{- end -}}

{{/*
Generic rendering of templated values. Parameters: .value, .context.
*/}}
{{- define "openresty.helpers.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
