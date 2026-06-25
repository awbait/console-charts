# Changelog

Все заметные изменения чарта `egress-gateway` фиксируются в этом файле.

## Правила версионирования

- **MAJOR** - несовместимые изменения, требующие правок в твоём `values.yaml`.
- **MINOR** - новые возможности без поломки существующих.
- **PATCH** - исправления и улучшения, прозрачные для пользователя.

## Категории изменений

- **Added** - что появилось нового.
- **Changed** - что изменилось в поведении.
- **Deprecated** - что будет удалено в будущем.
- **Removed** - что удалено.
- **Fixed** - что исправлено.
- **Security** - изменения, влияющие на безопасность.

---

## [2.0.0] - 2026-06-25

BREAKING: структура `values.yaml` изменена. `egressGateway` теперь один объект
(а не список), секция `tlsRoutes` удалена (маршруты генерируются автоматически),
из listener убран `tlsMode`, из `vpcEgressGateway` убраны `selectors` и `replicas`.
Старый `values.yaml` придётся переписать.

### Changed
- **Один Gateway на релиз.** `egressGateway` из списка превращён в одиночный
  объект (`name` / `enabled` / `listeners[]`). В одном Gateway допускается
  больше одного listener.
- **Протокол listener - `TLS` или `HTTPS`** (по умолчанию `TLS`); валидируется.
  `tls.mode` всегда `Passthrough` и больше не настраивается (поле `tlsMode`
  удалено из values и схемы).
- **`vpcEgressGateway`** больше не принимает `selectors` и `replicas`: число
  реплик равно числу `externalIPs`, а `namespaceSelector`/`podSelector`
  подставляются шаблоном и указывают на под'ы созданного egress Gateway
  (label `gateway.networking.k8s.io/gateway-name`).
- Комментарии в `values.yaml` / `values.minimal.yaml` / `values.full.yaml`
  возвращены на русский (по `charts/CONVENTIONS.md`); в 1.0.1 они были на
  английском. Комментарии в `templates/` остаются на английском.

### Added
- **Маршруты генерируются автоматически - один на listener.** Kind берётся из
  протокола listener (`TLS` -> `TLSRoute`, `HTTPS` -> `HTTPRoute`), имя - из
  имени listener по конвенции с родителем
  (`{instanceTag}-{clusterTag}-egw-{gatewayName}-{projectTag}-{listenerName}`),
  `hostnames` - из hostname listener, единственный `backendRef` -
  `{name: hostname, port: listener.port, weight: 100}`. Route привязан к своему
  listener через `parentRefs[].sectionName`.

### Removed
- Секция `tlsRoutes[]` и её поля в `values.schema.json` - маршруты теперь
  выводятся из listener'ов, задавать их вручную не нужно.

### Fixed
- `apiVersion` маршрутов приведён к Kind: `TLSRoute` -
  `gateway.networking.k8s.io/v1alpha2`, `HTTPRoute` - `.../v1` (раньше TLSRoute
  ошибочно рендерился как `v1`).

## [1.0.1] - 2026-06-25

### Changed
- Файлы значений приведены к стандарту: `values.yaml` (минимальный дефолт, пустые секции) + `values.full.yaml` (полный reference) + `values.minimal.yaml` (рабочий пример). Прежний `minimal-values.yaml` переименован в `values.minimal.yaml`; полный reference вынесен из `values.yaml` в `values.full.yaml`.
- Комментарии в шаблонах, `values.*`, `values.schema.json` и `NOTES.txt` переведены на английский; длинные тире заменены на дефисы.

## [1.0.0] - 2026-05-29

Первый релиз чарта.

### Added
- **Конвенция именования** - имя каждого ресурса строится как
  `{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}`. Общие теги -
  в `naming` (`instanceTag`/`clusterTag`/`projectTag`), `kindShort` по типу
  ресурса (`egw`/`veg`), `name` - на каждый ресурс (2..6 символов). Все части
  валидируются (DNS-формат, длины, `kindShort ∈ {igw,egw,veg}`).
- **Egress Gateway (`egressGateway[]`)** - список шлюзов. На каждый элемент -
  `Gateway` (Gateway API, TLS Passthrough) и `ConfigMap` для waypoint operator;
  ConfigMap носит то же имя, что и Gateway.
- **ServiceEntry из listener'ов** - `ServiceEntry` генерируется автоматически
  на каждый `egressGateway[].listeners[]` (hostname/port/addresses). Отдельная
  секция `serviceEntries` не нужна.
- **TLSRoute (`tlsRoutes[]`)** - список маршрутов; `parentRefs` генерируются
  по совпадению `hostnames` с listener'ами шлюзов (Gateway указывать не нужно).
  На каждый совпавший Gateway создаётся отдельный TLSRoute. Имя - по расширенной
  конвенции с `parentGatewayName`:
  `{instanceTag}-{clusterTag}-egw-{parentGatewayName}-{projectTag}-{name}`.
- **VpcEgressGateway (`vpcEgressGateway[]`)** - ресурс kube-ovn: список шлюзов
  с externalIPs, node/namespace/pod селекторами и SNAT-политиками. `replicas`
  по умолчанию равно числу `externalIPs`.
- **Общие labels/annotations** - только глобально через `generic.*` (без
  per-resource).
- **Справочник `values.full.yaml`** со всеми параметрами и комментариями,
  **`values.minimal.yaml`** - минимальная рабочая конфигурация, и
  **`values.yaml`** - дефолт (пустые секции, ничего не создаёт).
