# Changelog

Все заметные изменения чарта `egress-gateway` фиксируются в этом файле.

## Правила версионирования

- **MAJOR** — несовместимые изменения, требующие правок в твоём `values.yaml`.
- **MINOR** — новые возможности без поломки существующих.
- **PATCH** — исправления и улучшения, прозрачные для пользователя.

## Категории изменений

- **Added** — что появилось нового.
- **Changed** — что изменилось в поведении.
- **Deprecated** — что будет удалено в будущем.
- **Removed** — что удалено.
- **Fixed** — что исправлено.
- **Security** — изменения, влияющие на безопасность.

---

## [1.0.0] — 2026-05-29

Первый релиз чарта.

### Added
- **Конвенция именования** — имя каждого ресурса строится как
  `{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}`. Общие теги —
  в `naming` (`instanceTag`/`clusterTag`/`projectTag`), `kindShort` по типу
  ресурса (`egw`/`veg`), `name` — на каждый ресурс (2..6 символов). Все части
  валидируются (DNS-формат, длины, `kindShort ∈ {igw,egw,veg}`).
- **Egress Gateway (`egressGateway[]`)** — список шлюзов. На каждый элемент —
  `Gateway` (Gateway API, TLS Passthrough) и `ConfigMap` для waypoint operator;
  ConfigMap носит то же имя, что и Gateway.
- **ServiceEntry из listener'ов** — `ServiceEntry` генерируется автоматически
  на каждый `egressGateway[].listeners[]` (hostname/port/addresses). Отдельная
  секция `serviceEntries` не нужна.
- **TLSRoute (`tlsRoutes[]`)** — список маршрутов; `parentRefs` генерируются
  по совпадению `hostnames` с listener'ами шлюзов (Gateway указывать не нужно).
  На каждый совпавший Gateway создаётся отдельный TLSRoute. Имя — по расширенной
  конвенции с `parentGatewayName`:
  `{instanceTag}-{clusterTag}-egw-{parentGatewayName}-{projectTag}-{name}`.
- **VpcEgressGateway (`vpcEgressGateway[]`)** — ресурс kube-ovn: список шлюзов
  с externalIPs, node/namespace/pod селекторами и SNAT-политиками. `replicas`
  по умолчанию равно числу `externalIPs`.
- **Общие labels/annotations** — только глобально через `generic.*` (без
  per-resource).
- **Reference `values.yaml`** со всеми параметрами и комментариями и
  **`minimal-values.yaml`** — минимальная рабочая конфигурация.
