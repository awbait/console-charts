# egress-gateway - usage

Чарт разворачивает egress через Istio Waypoint / Gateway API и kube-ovn
`VpcEgressGateway`. Из секций `values.yaml` генерируются ресурсы.

| Секция              | Что генерирует                                                              | Когда использовать                       |
|---------------------|-----------------------------------------------------------------------------|------------------------------------------|
| `egressGateway`     | один `Gateway` + `ConfigMap`; на каждый listener - `ServiceEntry` и `Route` | Точка egress на базе Istio waypoint      |
| `vpcEgressGateway[]`| `VpcEgressGateway` (kube-ovn)                                                | Egress на уровне VPC (SNAT, externalIPs) |

На релиз создаётся **один** `Gateway`, но в нём может быть несколько listener'ов.
Каждый listener - это один внешний сервис: из него выводятся listener в Gateway,
`ServiceEntry` и один `Route`. `VpcEgressGateway` сам нацеливается на под'ы этого
Gateway (см. ниже).

Связь по hostname: `listener.hostname` = `ServiceEntry.hosts` = `Route.hostnames`
= `Route.backendRefs[].name`.

## Конвенция именования

Имя каждого ресурса строится так:

```
{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
```

| Часть         | Откуда                            | Ограничения                     |
|---------------|-----------------------------------|---------------------------------|
| `instanceTag` | `naming.instanceTag` (таблица 50) | DNS-формат lower-case, required |
| `clusterTag`  | `naming.clusterTag` (таблица 52)  | DNS-формат lower-case, required |
| `kindShort`   | тип ресурса (таблица 57)          | `egw` / `veg`                   |
| `projectTag`  | `naming.projectTag`               | 2..6 символов, DNS, required    |
| `name`        | поле `name` ресурса               | 2..6 символов, DNS, required    |

`kindShort` подставляется автоматически: `egw` - Istio Egress (Gateway,
ConfigMap, ServiceEntry, TLSRoute/HTTPRoute), `veg` - VPC Egress
(VpcEgressGateway). ConfigMap носит то же имя, что и Gateway. Итог обрезается до
63 символов.

**Route** использует расширенную конвенцию с именем родительского Gateway и
именем listener:

```
{instanceTag}-{clusterTag}-egw-{gatewayName}-{projectTag}-{listenerName}
```

Пример: `ru1-k8s1-egw-wp-nbox-nx`.

---

## Quick start

```sh
helm template release-name . -f values.minimal.yaml
helm install  release-name . -f values.minimal.yaml
```

Минимальный пример (`values.minimal.yaml`) создаёт: ConfigMap, Gateway с одним
TLS listener, один ServiceEntry, один TLSRoute и один VpcEgressGateway.

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

### `egressGateway`

Один шлюз на релиз. Создаётся `Gateway` и `ConfigMap` с тем же именем
(kindShort `egw`).

| Поле          | Обязательно | Описание                                                       |
|---------------|-------------|----------------------------------------------------------------|
| `name`        | да          | 2..6 символов; `{name}` в имени Gateway/ConfigMap             |
| `enabled`     | нет (true)  | `false` -> ничего из этой секции не создаётся                  |
| `listeners[]` | да          | Минимум один listener (см. ниже)                               |

Каждый `listener` описывает один внешний сервис. Из него генерируются listener в
Gateway, `ServiceEntry` **и** один `Route`:

| Поле         | Обязательно            | Описание                                                       |
|--------------|------------------------|----------------------------------------------------------------|
| `name`       | да                     | 2..6 символов; `{name}` в имени `ServiceEntry` и `Route`      |
| `hostname`   | да                     | hostname / SNI; идёт в `ServiceEntry.hosts` и backend маршрута |
| `port`       | да                     | Порт listener, ServiceEntry и backend маршрута                |
| `protocol`   | нет (`TLS`)            | `TLS` или `HTTPS`; задаёт Kind маршрута (см. ниже)            |
| `addresses`  | нет                    | Статические IP -> `resolution STATIC` + endpoints, иначе `DNS` |
| `exportTo`   | нет (`["."]`)          | Видимость `ServiceEntry`                                      |
| `location`   | нет (`MESH_EXTERNAL`)  | Положение относительно mesh                                  |
| `resolution` | нет                    | Override резолвинга `ServiceEntry`                            |

`tls.mode` на listener **всегда** `Passthrough` (не настраивается).

#### Маршруты (генерируются автоматически)

На каждый listener создаётся ровно один `Route`. Вручную задавать маршруты не
нужно - всё выводится из listener:

- **Kind** - из протокола: `TLS` -> `TLSRoute`, `HTTPS` -> `HTTPRoute`.
- **Имя** - из имени listener по конвенции с родителем (см. выше).
- **hostnames** - hostname listener'а.
- **backendRefs** - один backend: `name` = hostname, `port` = `listener.port`,
  `weight` = `100`.
- Маршрут привязан к своему listener через `parentRefs[].sectionName`.

> Labels/annotations на ресурсы задаются только глобально через `generic.labels`
> и `generic.annotations`. Per-resource labels/annotations не поддерживаются.

### `vpcEgressGateway[]` (kube-ovn)

Захардкожены в `templates/VPCEgressGateway.yaml` (не настраиваются через values):
`vpc` (`ovn-cluster`), `externalSubnet` (`egress-vip`), `trafficPolicy`
(`Cluster`), `nodeSelector`, `policies`. Менять - в шаблоне.

Выводятся автоматически (не задаются в values):

- `replicas` = число `externalIPs`;
- `selectors` - `namespaceSelector` + `podSelector` указывают на созданный egress
  Gateway: namespace релиза и под'ы waypoint этого Gateway (label
  `gateway.networking.k8s.io/gateway-name`).

Пользователь задаёт:

| Поле          | Обязательно | Описание                                         |
|---------------|-------------|--------------------------------------------------|
| `name`        | да          | 2..6 символов; `{name}` в имени ресурса (veg)    |
| `enabled`     | нет (true)  | `false` -> ресурс не создаётся                    |
| `externalIPs` | да          | Внешние IP (число реплик = число IP)             |

Секция требует включённого `egressGateway` (селекторы нацелены на его под'ы).

---

## Валидации (при которых рендер падает)

- `naming.instanceTag`/`clusterTag` не заданы или не DNS-формат.
- `naming.projectTag` или любое `name` не 2..6 символов / не DNS-формат.
- `egressGateway.name` не задан, или `listeners` пуст.
- `egressGateway.listeners[].name`/`hostname`/`port` не заданы.
- `egressGateway.listeners[].protocol` не `TLS` и не `HTTPS`.
- `vpcEgressGateway[].name`/`externalIPs` не заданы.
- `vpcEgressGateway` задан, но `egressGateway` выключен или без `name`.

---

## Запуск

```sh
helm lint .
helm template release-name . [-f my-values.yaml]
helm install  release-name . [-f my-values.yaml]
```

Полный reference всех параметров - в `values.full.yaml`. Минимальный пример -
в `values.minimal.yaml`. `values.yaml` - дефолт (без `egressGateway`, ничего не создаёт).
