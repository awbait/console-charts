# egress-gateway — usage

Чарт разворачивает egress через Istio Waypoint / Gateway API и kube-ovn
`VpcEgressGateway`. Из независимых секций `values.yaml` генерируются ресурсы.

| Секция              | Что генерирует                                              | Когда использовать                              |
|---------------------|------------------------------------------------------------|-------------------------------------------------|
| `egressGateway[]`   | `Gateway` + `ConfigMap` на элемент; `ServiceEntry` на listener | Точка egress на базе Istio waypoint          |
| `tlsRoutes[]`       | `TLSRoute` (parentRefs генерируются)                       | Маршрут от waypoint к backend'у ServiceEntry    |
| `vpcEgressGateway[]`| `VpcEgressGateway` (kube-ovn)                              | Egress на уровне VPC (SNAT, externalIPs)        |

Связь по hostname: `listener.hostname` = `ServiceEntry.hosts` = `tlsRoutes[].hostnames`
= `backendRefs[].name`. Один listener описывает один внешний сервис.

## Конвенция именования

Имя каждого ресурса строится так:

```
{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
```

| Часть         | Откуда                          | Ограничения                     |
|---------------|---------------------------------|---------------------------------|
| `instanceTag` | `naming.instanceTag` (таблица 50) | DNS-формат lower-case, required |
| `clusterTag`  | `naming.clusterTag` (таблица 52)  | DNS-формат lower-case, required |
| `kindShort`   | тип ресурса (таблица 57)          | `igw` / `egw` / `veg`           |
| `projectTag`  | `naming.projectTag`               | 2..6 символов, DNS, required    |
| `name`        | поле `name` ресурса               | 2..6 символов, DNS, required    |

`kindShort` подставляется автоматически: `egw` — Istio Egress (Gateway,
ConfigMap, ServiceEntry, TLSRoute), `veg` — VPC Egress (VpcEgressGateway).
`igw` (Istio Ingress) в этом чарте не используется. ConfigMap носит то же имя,
что и Gateway. Итог обрезается до 63 символов.

**TLSRoute** использует расширенную конвенцию с именем родительского Gateway:

```
{instanceTag}-{clusterTag}-egw-{parentGatewayName}-{projectTag}-{name}
```

`parentGatewayName` — `name` совпавшего по hostname Gateway (2..6). На каждый
совпавший Gateway создаётся отдельный TLSRoute. Пример: `ru1-k8s1-egw-wp-nbox-rnx`.

---

## Quick start

```sh
helm template release-name . -f minimal-values.yaml
helm install  release-name . -f minimal-values.yaml
```

Минимальный пример (`minimal-values.yaml`) создаёт: ConfigMap, Gateway с одним
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

### `egressGateway[]`

Список шлюзов. На каждый элемент создаётся `Gateway` и `ConfigMap` с тем же
именем (kindShort `egw`).

| Поле          | Обязательно | Описание                                                       |
|---------------|-------------|----------------------------------------------------------------|
| `name`        | да          | 2..6 символов; `{name}` в имени Gateway/ConfigMap             |
| `enabled`     | нет (true)  | `false` → Gateway и ConfigMap не создаются                     |
| `listeners[]` | да          | Список listener'ов (см. ниже)                                  |

Каждый `listener` описывает один внешний сервис; из него генерируется listener
в Gateway **и** `ServiceEntry`:

| Поле         | Обязательно            | Описание                                                       |
|--------------|------------------------|----------------------------------------------------------------|
| `name`       | да                     | 2..6 символов; `{name}` в имени `ServiceEntry` (egw)          |
| `hostname`   | да                     | hostname / SNI; идёт в `ServiceEntry.hosts`                   |
| `port`       | да                     | Порт                                                          |
| `protocol`   | нет (`TLS`)            | Протокол                                                      |
| `tlsMode`    | нет (`Passthrough`)    | Режим TLS                                                     |
| `addresses`  | нет                    | Статические IP → `resolution STATIC` + endpoints, иначе `DNS` |
| `exportTo`   | нет (`["."]`)          | Видимость `ServiceEntry`                                      |
| `location`   | нет (`MESH_EXTERNAL`)  | Положение относительно mesh                                  |
| `resolution` | нет                    | Override резолвинга `ServiceEntry`                            |

### `tlsRoutes[]`

Список маршрутов. **`parentRefs` не указываются** — маршрут привязывается к тем
`egressGateway`, у которых есть listener с hostname из `route.hostnames`. На
**каждый** совпавший Gateway создаётся отдельный TLSRoute (имя включает
`parentGatewayName`, см. «Конвенция именования»).

`name` (req, 2..6 символов), `enabled` (default true), `hostnames[]` (req),
`rules[].backendRefs[]` (`name`/`port` — обязательны, `weight` — опционально;
`name` совпадает с host из `ServiceEntry`).

> Labels/annotations на ресурсы задаются только глобально через `generic.labels`
> и `generic.annotations` (применяются ко всем манифестам). Per-resource
> labels/annotations не поддерживаются.

### `vpcEgressGateway[]` (kube-ovn)

Захардкожены в `templates/VPCEgressGateway.yaml` (не настраиваются через values):
`vpc` (`ovn-cluster`), `externalSubnet` (`egress-vip`), `trafficPolicy`
(`Cluster`), `nodeSelector`, `policies`. Менять — в шаблоне.

Пользователь задаёт:

| Поле          | Обязательно                | Описание                                         |
|---------------|----------------------------|--------------------------------------------------|
| `name`        | да                         | 2..6 символов; `{name}` в имени ресурса (veg)    |
| `externalIPs` | да                         | Внешние IP                                       |
| `replicas`    | нет (default `len externalIPs`) | Число реплик                                |
| `selectors`   | нет                        | `namespaceSelectors[]` и `podSelectors[]`        |

---

## Валидации (при которых рендер падает)

- `naming.instanceTag`/`clusterTag` не заданы или не DNS-формат.
- `naming.projectTag` или любое `name` не 2..6 символов / не DNS-формат.
- `egressGateway[].name`, `.listeners[].name`/`hostname`/`port` не заданы.
- `tlsRoutes[].name`/`hostnames` не заданы.
- `tlsRoutes[].rules[].backendRefs[].name`/`port` не заданы.
- `tlsRoutes[].hostnames` не совпали ни с одним listener'ом (parentRefs не сгенерировать).
- `vpcEgressGateway[].name`/`externalIPs` не заданы.

---

## Запуск

```sh
helm lint .
helm template release-name . [-f my-values.yaml]
helm install  release-name . [-f my-values.yaml]
```

Полный reference всех параметров — в `values.yaml`. Минимальный пример —
в `minimal-values.yaml`.
