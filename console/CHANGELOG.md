# Changelog

Все заметные изменения чарта `console` фиксируются в этом файле.

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

## [0.3.1] - 2026-06-25

### Changed
- Комментарии в `values.yaml`, шаблонах и `NOTES.txt` переведены на английский (в исходниках чарта - без кириллицы).

## [0.3.0] - 2026-06-23

### Changed
- Дефолт `portal.image.repository` уточнён до `console/portal` (образы публикуются
  как `{imageRegistry}/console/portal`; коллектор - `console/collector`).

### Added
- Компонент `collector` (опциональный, `collector.enabled`, по умолчанию вкл.):
  отдельный Deployment + ServiceAccount + read-only ClusterRole/Binding
  (`namespaces` + apps-контроллеры) + ConfigMap/Secret. Собирает каталог
  workload'ов кластера в Valkey/Redis, откуда читает портал. Образ -
  `console/collector`. Без Service и проб (у коллектора нет HTTP).
- Метрики Prometheus: порт `metrics` (по умолчанию 2112, `portal.metrics`)
  выведен в `containerPort` и `Service`, на под проставляются аннотации
  `prometheus.io/*` (скрейп без ServiceMonitor). Подхватывает фичу выделенного
  `/metrics`-порта из портала.
- Опциональный вход сабчартом `ingress-gateway` (Istio Gateway API), подключается
  только при `ingressGateway.enabled=true` (по умолчанию выключен). Поднимает
  Gateway + HTTPRoute на Service портала. Требует Istio + Gateway API CRDs.
- В `values.yaml` вынесены тюнинг-ключи с дефолтами из `config.go`: сессии/cookie
  (`SESSION_TTL`, `SESSION_COOKIE_NAME`, `COOKIE_SECURE`, `OIDC_POST_LOGIN_REDIRECT`),
  GitLab GitOps (`GITLAB_GITOPS_GROUP`, `GITLAB_TEAM_SUBGROUP_TEMPLATE`,
  `GITLAB_DEFAULT_BRANCH`, `GITLAB_AUTO_MERGE`), Harbor (`HARBOR_PROJECTS`),
  ArgoCD (`ARGOCD_PROJECT`, `ARGOCD_DEFAULT_CLUSTER`, `ARGOCD_APP_NAME_TEMPLATE`),
  статусы (`STATUS_UPDATE_MODE`, `STATUS_POLL_INTERVAL`) и фиче-флаги
  (`DRIFT_DETECTION_ENABLED`, `IMPORT_DISCOVERY_ENABLED`, `CATALOG_AUTODISCOVER`).

### Removed
- Из `config` убраны `HARBOR_MODE`/`GITLAB_MODE`/`ARGOCD_MODE`: деплой всегда
  `real` (это дефолт `config.go`), а `fake` - только тесты и локальная разработка.

## [0.2.1] - 2026-06-18

### Changed
- Аутентификация: `config.go` по умолчанию `AUTH_MODE=oidc` (единственный
  валидный режим). Плашка-предупреждение в NOTES убрана, README уточнён.

### Removed
- Из NOTES убран блок про port-forward / вход (вход публикуется снаружи отдельно).

## [0.2.0] - 2026-06-18

### Changed
- Один компонент вместо двух: portal теперь сам отдаёт и API, и встроенный SPA
  (бэкенд `console` собирается с SPA через `go:embed`). Соответственно `appVersion`
  поднят до `0.2.0`.

### Removed
- Компонент `web` (nginx): Deployment, Service и ConfigMap с nginx-конфигом, а
  также секция `web` в `values.yaml`. Прокси `/api` больше не нужен - вход идёт
  напрямую на Service `portal` (:8080).

## [0.1.0] - 2026-06-18

### Added
- Первый релиз чарта. Разворачивает IDP Console двумя компонентами:
  - `portal` - Go-бэкенд (Deployment + Service, :8080), конфигурация через
    ConfigMap (несекретные env) и Secret (DATABASE_URL, REDIS_URL, OIDC-секрет,
    токены апстримов); поддержка внешнего Secret через `portal.existingSecret`.
  - `web` - nginx с собранным SPA (Deployment + Service, :80); прокси `/api` на
    Service портала задаётся через ConfigMap (переопределяет образный nginx.conf).
    Это входная точка; portal наружу не публикуется. Ingress чарт не создаёт -
    вход настраивается снаружи на Service `web`.
- `ServiceAccount` (создание управляется `serviceAccount.create`).
- Проби: `portal` - `/health` (liveness) и `/ready` (readiness); `web` - `/`.
- Перекат подов при изменении конфигов через аннотации checksum.
- Аутентификация только через OIDC (чарт рассчитан на прод).
