{{/*
Имя чарта для helm.sh/chart.
*/}}
{{- define "ingress-gateway.helpers.app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Базовое имя приложения (для labels) = projectTag.
*/}}
{{- define "ingress-gateway.helpers.app.name" -}}
{{- required "naming.projectTag is required" (.Values.naming | default dict).projectTag | toString | lower | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Валидация DNS-тега (instanceTag, clusterTag). Параметры: .label, .value.
Возвращает значение в lower-case.
*/}}
{{- define "ingress-gateway.helpers.tag" -}}
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
Валидация короткого 2..6-символьного DNS-тега (projectTag, name).
Параметры: .label, .value. Возвращает значение в lower-case.
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
Короткий код типа ресурса (kindShort) по k8s kind. Параметр: kind (строка).
Допустимые: igw (Gateway), cm (ConfigMap), ap (AuthorizationPolicy),
np (NetworkPolicy), hr (HTTPRoute), gr (GRPCRoute), tr (TLSRoute),
tcr (TCPRoute), ur (UDPRoute), secret (Secret). Неизвестный kind → fail.
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
Имя TLS-секрета для listener по hostname (tlsMode: Terminate). Параметры: .hostname, .context.
Имя ВСЕГДА генерируется автоматически (пользователь не задаёт tlsSecretName):
  содержит "idp.ecpk.ru" → {instanceTag}-{clusterTag}-secret-{projectTag}-idptls (предзаданный wildcard-cert)
  содержит "edp.ecpk.ru" → {instanceTag}-{clusterTag}-secret-{projectTag}-edptls (предзаданный wildcard-cert)
  иначе                  → {instanceTag}-{clusterTag}-secret-{projectTag}-tls   (пустой секрет / change me)
*/}}
{{- define "ingress-gateway.helpers.app.tlsSecretName" -}}
{{- $hostname := .hostname | default "" | toString | lower -}}
{{- $token := "tls" -}}
{{- if contains "idp.ecpk.ru" $hostname -}}{{- $token = "idptls" -}}
{{- else if contains "edp.ecpk.ru" $hostname -}}{{- $token = "edptls" -}}
{{- end -}}
{{- include "ingress-gateway.helpers.app.resourceName" (dict "kind" "Secret" "name" $token "context" .context) -}}
{{- end -}}

{{/*
Имя ресурса по конвенции:
  {instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
Параметры: .context, .kind (k8s kind), .name (2..6 символов).
kindShort выводится из .kind (см. ingress-gateway.helpers.app.kindShort).
Итог обрезается до 63 символов.
Примеры: ru1-k8s1-igw-nbox-main, ru1-k8s1-hr-nbox-app.
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
Selector labels — стабильная идентификация ресурсов чарта.
*/}}
{{- define "ingress-gateway.helpers.app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ingress-gateway.helpers.app.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app: {{ include "ingress-gateway.helpers.app.name" . | quote }}
{{- end -}}

{{/*
Стандартные labels: selector + chart/managed-by/version + generic.labels.
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
Общие annotations (generic.annotations). Пусто → ничего не выводит.
*/}}
{{- define "ingress-gateway.helpers.app.genericAnnotations" -}}
{{- range $k, $v := (.Values.generic | default dict).annotations }}
{{ $k }}: {{ tpl (toString $v) $ | quote }}
{{- end }}
{{- end -}}

{{/*
Признак включённости сущности (enabled). Параметр: entity (map).
Корректно учитывает явный enabled: false (в отличие от `| default true`).
enabled отсутствует → "true"; enabled: false → "" (выключено); иначе по значению.
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
matchLabels для выбора workload Gateway в NetworkPolicy/AuthorizationPolicy.
Istio Gateway controller проставляет pod'ам label
gateway.networking.k8s.io/gateway-name = metadata.name Gateway.
Параметры: .gatewayResourceName (полное имя Gateway).
*/}}
{{- define "ingress-gateway.helpers.app.gatewayWorkloadSelectorLabels" -}}
gateway.networking.k8s.io/gateway-name: {{ required "gatewayResourceName is required" .gatewayResourceName | quote }}
{{- end -}}

{{/*
Canonical kind для xRoute. Параметры: .kind, .name.
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
apiVersion для xRoute по kind. apiVersion намеренно не берётся из values.
Параметры: .kind (canonical), .name.
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
Универсальный рендеринг шаблонных значений. Параметры: .value, .context.
*/}}
{{- define "ingress-gateway.helpers.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}
