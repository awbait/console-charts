# ingress-gateway - usage

Чарт разворачивает ingress на базе Istio / Kubernetes Gateway API. Из
независимых секций `values.yaml` генерируются ресурсы.

| Секция                 | Что генерирует                                              | Когда использовать                          |
|------------------------|------------------------------------------------------------|---------------------------------------------|
| `gateways[]`           | `Gateway` + infrastructure `ConfigMap` на элемент          | Точка входа (Gateway API + Istio workload)  |
| `xroutes[]`            | `HTTPRoute`/`GRPCRoute`/`TLSRoute`/`TCPRoute`/`UDPRoute`    | Маршрутизация к backend-сервисам            |
| `networkPolicy`        | `NetworkPolicy` на каждый Gateway                          | L3/L4 ограничения для workload Gateway      |
| `authorizationPolicy`  | `AuthorizationPolicy` (Istio) на каждый Gateway            | L7-авторизация трафика к Gateway            |
| `oidcAuth`             | `HTTPRoute`/`ReferenceGrant`/`AuthorizationPolicy`/`RequestAuthentication` | OIDC через oauth2-proxy + Keycloak |

Связь: `xroutes[].parentRefs[].gateway` = `gateways[].name`, а `sectionName` =
`listeners[].name`.

## Конвенция именования

Имя каждого ресурса (кроме OIDC) строится так:

```
{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
```

| Часть         | Откуда                            | Ограничения                     |
|---------------|-----------------------------------|---------------------------------|
| `instanceTag` | `naming.instanceTag` (таблица 50) | DNS-формат lower-case, required |
| `clusterTag`  | `naming.clusterTag` (таблица 52)  | DNS-формат lower-case, required |
| `kindShort`   | тип ресурса (см. ниже)            | по таблице kindShort            |
| `projectTag`  | `naming.projectTag`               | 2..6 символов, DNS, required    |
| `name`        | `gateways[].name` / `xroutes[].name` | 2..6 символов, DNS, required |

`kindShort` подставляется автоматически по типу ресурса:

| Kind                  | kindShort | Kind        | kindShort |
|-----------------------|-----------|-------------|-----------|
| `Gateway`             | `igw`     | `HTTPRoute` | `hr`      |
| `ConfigMap`           | `cm`      | `GRPCRoute` | `gr`      |
| `NetworkPolicy`       | `np`      | `TLSRoute`  | `tr`      |
| `AuthorizationPolicy` | `ap`      | `TCPRoute`  | `tcr`     |
| `Secret` (TLS)        | `secret`  | `UDPRoute`  | `ur`      |

ConfigMap носит то же имя, что и Gateway, но с kindShort `cm`. Итог обрезается
до 63 символов. Примеры: `ru1-k8s1-igw-nbox-main`, `ru1-k8s1-hr-nbox-app`.

> Ресурсы OIDC (`oidcAuth`) создаются в namespace приложения / Gateway /
> oauth2-proxy и носят пользовательские имена (вне 5-частной конвенции).

---

## Quick start

```sh
helm template release-name . -f minimal-values.yaml
helm install  release-name . -f minimal-values.yaml
```

Минимальный пример (`minimal-values.yaml`) создаёт: `Gateway`, `ConfigMap`,
`NetworkPolicy`, `AuthorizationPolicy` и один `HTTPRoute`.

---

## Секции `values.yaml`

### Общие параметры

| Поле                   | Тип    | Описание                                              |
|------------------------|--------|-------------------------------------------------------|
| `naming.instanceTag`   | string | Тег инстанса (таблица 50), required, DNS              |
| `naming.clusterTag`    | string | Тег кластера (таблица 52), required, DNS              |
| `naming.projectTag`    | string | Тег проекта, required, 2..6 символов, DNS             |
| `generic.labels`       | map    | Общие labels для всех ресурсов                        |
| `generic.annotations`  | map    | Общие annotations для всех ресурсов                   |

### `gateways[]`

На каждый элемент создаётся `Gateway` и infrastructure `ConfigMap` (одно имя,
разный kindShort).

| Поле          | Обязательно | Описание                                                       |
|---------------|-------------|----------------------------------------------------------------|
| `name`        | да          | 2..6 символов; `{name}` в имени Gateway/ConfigMap, ссылка из `xroutes` |
| `enabled`     | нет (true)  | `false` → Gateway и ConfigMap не создаются                     |
| `ipAddress`   | нет         | Статический IP LoadBalancer → аннотация MetalLB в ConfigMap   |
| `hpa`         | нет         | `HorizontalPodAutoscaler` (`enabled`/`minReplicas`/`maxReplicas`/`averageUtilization`) |
| `resources`   | нет         | Resources контейнера `istio-proxy` → `ConfigMap.data.deployment` |
| `listeners[]` | да          | Список listener'ов (см. ниже)                                  |

`listener`: `name` (sectionName в parentRefs; длина не ограничена 2..6),
`port`/`protocol` (req; `HTTP`/`HTTPS`/`TCP`/`UDP`/`TLS`), `hostname`
(обязателен для `HTTPS`/`TLS`), `tlsMode` (`Terminate` для HTTPS,
`Passthrough` для TLS - по умолчанию), `tlsSecretName`/`certificateRefs`
(для `Terminate`; см. авто-секреты ниже), `allowedRoutes`.

#### TLS-секреты (auto)

Для listener'а с `tlsMode: Terminate` (протоколы `HTTPS`/`TLS`) секрет с
сертификатом создаётся автоматически по `hostname`:

| hostname           | Имя секрета (kindShort `secret`)                       |
|--------------------|--------------------------------------------------------|
| `*.idp.ecpk.test`    | `{instanceTag}-{clusterTag}-secret-{projectTag}-idptls` |
| `*edp.ecpk.test`     | `{instanceTag}-{clusterTag}-secret-{projectTag}-edptls` |
| прочие             | секрет не создаётся → нужен `tlsSecretName`/`certificateRefs` |

Секрет рендерится как `type: kubernetes.io/tls` с пустыми `tls.crt`/`tls.key` -
сертификат и ключ (base64) подставляете сами. Несколько listener'ов с одним
паттерном (`*.idp.ecpk.test`, `auth.idp.ecpk.test`, …) дают **один** секрет.

### `xroutes[]`

| Поле          | Обязательно | Описание                                                       |
|---------------|-------------|----------------------------------------------------------------|
| `name`        | да          | 2..6 символов; `{name}` в имени Route                          |
| `enabled`     | нет (true)  | `false` → Route не создаётся                                   |
| `kind`        | нет (`HTTPRoute`) | `HTTPRoute`/`GRPCRoute`/`TLSRoute`/`TCPRoute`/`UDPRoute`; `apiVersion` выбирается автоматически |
| `parentRefs[]`| да          | `gateway` (= `gateways[].name`) + `sectionName` (= `listener.name`) |
| `hostnames[]` | для HTTP/GRPC/TLS | Hostname'ы (для TLS - SNI)                              |
| `rules[]`     | да          | `matches`/`filters` только для HTTP/GRPC; `backendRefs` обязательны (`name`/`port`, опц. `namespace`/`weight`) |

**Упрощения при единственном включённом Gateway:**
- `parentRefs[].gateway` можно опустить - подставится имя этого Gateway (при
  нескольких Gateway поле обязательно).
- `hostnames` можно опустить - берутся из listener'ов, на которые ссылается
  route через `parentRefs[].sectionName` (для HTTP/GRPC/TLS).

### `networkPolicy`

`enabled` (default true). На каждый включённый Gateway создаётся `NetworkPolicy`.
Workload выбирается по label `gateway.networking.k8s.io/gateway-name` = полное
имя Gateway. Ingress по умолчанию разрешён на служебные порты Istio
(80/443/15020/15021/15090). `egress` задаётся пользователем и **обязателен** при
`enabled: true`.

### `authorizationPolicy`

`enabled` (default true). На каждый включённый Gateway создаётся
`AuthorizationPolicy` (Istio), по умолчанию `ALLOW` для `0.0.0.0/0`. Тонкая
настройка правил - в фазе доработки.

### `oidcAuth`

`enabled` (default false). При включении создаются `HTTPRoute` для `/oauth2`,
`ReferenceGrant`, две `AuthorizationPolicy` (CUSTOM ext_authz и проверка групп)
и `RequestAuthentication`. Имена - пользовательские. Обязательны `application`,
`gateway`, `groupsPolicy.allowedGroups`, `keycloak.{issuer,jwksUri}`.

> Labels/annotations на ресурсы задаются только глобально через `generic.labels`
> и `generic.annotations`. Per-resource labels/annotations не поддерживаются.

---

## Валидации (при которых рендер падает)

- `naming.instanceTag`/`clusterTag` не заданы или не DNS-формат.
- `naming.projectTag` или любое `gateways[].name`/`xroutes[].name` не 2..6
  символов / не DNS-формат.
- `gateways[].name`, `.listeners[].port`/`protocol` не заданы.
- `listener` с `protocol: HTTPS`/`TLS` без `hostname`; `tlsMode: Terminate` без
  `tlsSecretName`/`certificateRefs`.
- `xroutes[].name`/`parentRefs`/`rules` не заданы.
- `xroutes[].kind` вне `HTTPRoute`/`GRPCRoute`/`TLSRoute`/`TCPRoute`/`UDPRoute`.
- `matches`/`filters` заданы для TLS/TCP/UDP Route.
- `rules[].backendRefs[].name`/`port` не заданы.
- `networkPolicy.enabled=true`, но `networkPolicy.egress` не задан.

---

## Запуск

```sh
helm lint .
helm template release-name . [-f my-values.yaml]
helm install  release-name . [-f my-values.yaml]
```

Полный reference всех параметров - в `values.yaml`. Минимальный пример -
в `minimal-values.yaml`.
