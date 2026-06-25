# waypoint - usage

Чарт разворачивает Istio ambient **waypoint proxy** - `Gateway` (Gateway API,
класс `istio-waypoint`) с listener'ом mesh-трафика (HBONE, порт 15008).

| Секция         | Что генерирует                          | Когда использовать                       |
|----------------|-----------------------------------------|------------------------------------------|
| `waypoints[]`  | `Gateway` (класс `istio-waypoint`) на элемент | Waypoint-перехват L7 в ambient mesh |

Pod'ы/сервисы/namespace привязываются к waypoint через label
`istio.io/use-waypoint: <имя Gateway>`.

## Конвенция именования

Имя каждого ресурса строится так:

```
{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
```

| Часть         | Откуда                            | Ограничения                     |
|---------------|-----------------------------------|---------------------------------|
| `instanceTag` | `naming.instanceTag` (таблица 50) | DNS-формат lower-case, required |
| `clusterTag`  | `naming.clusterTag` (таблица 52)  | DNS-формат lower-case, required |
| `kindShort`   | тип ресурса                       | `wp` (waypoint Gateway)         |
| `projectTag`  | `naming.projectTag`               | 2..6 символов, DNS, required    |
| `name`        | `waypoints[].name`                | 2..6 символов, DNS, required    |

Пример: `ru1-k8s1-wp-nbox-mesh`. Итог обрезается до 63 символов.

---

## Quick start

```sh
helm template release-name . -f minimal-values.yaml
helm install  release-name . -f minimal-values.yaml
```

Минимальный пример (`minimal-values.yaml`) создаёт один `Gateway` класса
`istio-waypoint`.

После установки привяжите namespace (или workload) к waypoint:

```sh
kubectl label ns <namespace> istio.io/use-waypoint=ru1-k8s1-wp-nbox-mesh
```

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

### `waypoints[]`

На каждый элемент создаётся `Gateway` класса `istio-waypoint`.

| Поле      | Обязательно | Описание                                                       |
|-----------|-------------|----------------------------------------------------------------|
| `name`    | да          | 2..6 символов; `{name}` в имени Gateway                        |
| `enabled` | нет (true)  | `false` → Gateway не создаётся                                 |
| `for`     | нет (`service`) | `istio.io/waypoint-for`: `service` / `workload` / `all`    |

> Labels/annotations задаются только глобально через `generic.labels` и
> `generic.annotations`. Per-resource labels/annotations не поддерживаются.

---

## Валидации (при которых рендер падает)

- `naming.instanceTag`/`clusterTag` не заданы или не DNS-формат.
- `naming.projectTag` или любое `waypoints[].name` не 2..6 символов / не DNS.
- `waypoints[].for` вне `service`/`workload`/`all`.

---

## Запуск

```sh
helm lint .
helm template release-name . [-f my-values.yaml]
helm install  release-name . [-f my-values.yaml]
```

Полный reference всех параметров - в `values.yaml`. Минимальный пример -
в `minimal-values.yaml`.
