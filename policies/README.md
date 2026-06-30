# policies - usage

Чарт декларативно описывает правила доступа между сервисами в Kubernetes и Istio.
Из независимых секций `values.yaml` генерируются `NetworkPolicy` (L3/L4) и
`AuthorizationPolicy` (Istio, L7).

| Секция       | Что генерирует                                                        | Когда использовать                                   |
|--------------|----------------------------------------------------------------------|------------------------------------------------------|
| `policies[]` | `NetworkPolicy` + `AuthorizationPolicy` с авто-зеркалированием egress | Полное описание связи source <-> target (NP и AP)    |
| `netpol[]`   | только `NetworkPolicy`, без зеркал                                    | Тонкий L3/L4-контроль или `ipBlock` без Istio AP     |
| `authzpol[]` | только `AuthorizationPolicy`                                          | L7 (`when`, кастомные principals) или NP заданы иначе |

`policies[]` - основная секция: один блок описывает workload (owner) и его связи.
Каждое egress-правило, помимо записи в owner-манифестах, **зеркалится** в namespace
получателя (ingress `NetworkPolicy` + mirror `AuthorizationPolicy` с principal
owner-а). Несколько egress-правил с одним target namespace мерджатся в один
зеркальный манифест (порты объединяются).

## Конвенция именования

Имя каждого ресурса строится так:

```
{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
```

| Часть         | Откуда                            | Ограничения                     |
|---------------|-----------------------------------|---------------------------------|
| `instanceTag` | `naming.instanceTag` (таблица 50) | DNS-формат lower-case, required |
| `clusterTag`  | `naming.clusterTag` (таблица 52)  | DNS-формат lower-case, required |
| `kindShort`   | тип ресурса                       | `np` / `ap`                     |
| `projectTag`  | `naming.projectTag`               | 2..6 символов, DNS, required    |
| `name`        | `policy.name` элемента секции     | 2..6 символов, DNS, required    |

`kindShort`: `np` - `NetworkPolicy`, `ap` - `AuthorizationPolicy`. Итог обрезается
до 63 символов. Имя должно быть уникально в пределах `(namespace, kind)`.

---

## Quick start

```sh
helm template release-name . -f values.yaml
helm install  release-name . -f values.yaml
```

Reference `values.yaml` описывает по одному примеру на каждую секцию: связку
`policies[]` (netbox owner + ingress/egress), отдельный `netpol[]` и два
`authzpol[]`.

---

## Секции `values.yaml`

### Общие параметры

| Поле                       | Тип    | Описание                                                        |
|----------------------------|--------|-----------------------------------------------------------------|
| `naming.instanceTag`       | string | Тег инстанса (таблица 50), required, DNS                        |
| `naming.clusterTag`        | string | Тег кластера (таблица 52), required, DNS                        |
| `naming.projectTag`        | string | Тег проекта, required, 2..6 символов, DNS                       |
| `defaults.trustDomain`     | string | Istio trust domain для principal (`cluster.local`)             |
| `defaults.namespaceLabelKey` | string | Label-ключ namespace для `namespaceSelector` (`kubernetes.io/metadata.name`) |
| `defaults.protocol`        | string | Протокол по умолчанию для портов NP (`TCP`)                     |

`defaults.*` переопределяются per-port/per-rule там, где это осмысленно
(например `ports: [{ port: 53, protocol: UDP }]`).

### `policies[]`

Один блок описывает owner-workload и его ingress/egress. На запись создаётся до 4
манифестов: `np`+`ap` в namespace релиза (`.Release.Namespace`) и зеркала
`np`(ingress)+`ap` в каждом target namespace из egress-правил.

| Поле             | Обязательно                    | Описание                                                       |
|------------------|--------------------------------|----------------------------------------------------------------|
| `name`           | да                             | 2..6 символов, DNS; `{name}` в имени ресурсов                  |
| `enabled`        | нет (true)                     | `false` -> вся policy пропускается                            |
| `serviceAccount` | при наличии egress             | SA owner-а; идёт в principal зеркальных AP                      |
| `selector`       | да                             | Pod selector owner-а (podSelector в NP, selector в AP)         |
| `ingress[]`      | нет                            | Кому разрешено ходить В owner (`from` + `ports`)               |
| `egress[]`       | нет                            | Куда owner может ходить (`to` + `ports`); зеркалится в target   |

Owner-ресурсы создаются в namespace релиза - ставь чарт в namespace целевого
workload.

Формы `from`/`to`: `namespace + selector` (+ опц. `serviceAccount` для AP
principal), `ipBlock`, либо raw `namespaceSelector`/`podSelector` (advanced).
Порты: `{ port: 8080 }` (протокол из `defaults.protocol`) или
`{ port: 8080, protocol: TCP }`.

> `peer.serviceAccount` в **egress** запрещён - рендер упадёт. SA отправителя
> берётся из `policy.serviceAccount` owner-а.

### `netpol[]`

Только `NetworkPolicy`, без AP и без зеркал. Для L3/L4-only или `ipBlock`.

| Поле        | Обязательно | Описание                                                       |
|-------------|-------------|----------------------------------------------------------------|
| `name`      | да          | 2..6 символов, DNS; имя ресурса (`np`)                         |
| `enabled`   | нет (true)  | `false` -> ресурс не создаётся                                |
| `selector`  | нет         | podSelector; пустой -> политика на все pod в ns               |
| `ingress[]` | нет         | Список `{ from: [...], ports: [...] }`                         |
| `egress[]`  | нет         | Список `{ to: [...], ports: [...] }`                           |

### `authzpol[]`

Только `AuthorizationPolicy`. Для L7-правил Istio или когда NP заданы иначе.

| Поле        | Обязательно | Описание                                                       |
|-------------|-------------|----------------------------------------------------------------|
| `name`      | да          | 2..6 символов, DNS; имя ресурса (`ap`)                         |
| `enabled`   | нет (true)  | `false` -> ресурс не создаётся                                |
| `action`    | нет (ALLOW) | `ALLOW` / `DENY` / `AUDIT` / `CUSTOM`                          |
| `selector`  | нет         | Кому применяется; опущен -> ко всем workload в ns             |
| `rules[]`   | да          | Правила `from` / `ports` / `when`                              |

Формы `from`: `serviceAccounts` (-> principals), `principals` (raw), `ipBlocks`,
`namespaces`. В `when` сейчас поддерживается `sourceNamespaces`.

---

## Валидации (при которых рендер падает)

- `naming.instanceTag`/`clusterTag` не заданы или не DNS-формат.
- `naming.projectTag` или любое `policy.name` не 2..6 символов / не DNS-формат.
- `policy.selector` не задан (`policies[]`).
- egress-правило без `policy.serviceAccount` owner-а.
- `peer.serviceAccount` указан в egress-правиле.

---

## Запуск

```sh
helm lint .
helm template release-name . [-f my-values.yaml]
helm install  release-name . [-f my-values.yaml]
```

Полный reference всех параметров - в `values.yaml`.
