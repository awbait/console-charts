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

## [0.6.0] - 2026-08-20

### Added
- `trustedCA.existingSecrets` - корневой сертификат можно взять из Secret, а не
  только из ConfigMap: он часто уже лежит там рядом с TLS-хозяйством апстрима.
  В `keys` слева ключ объекта, справа имя файла в каталоге, поэтому из
  TLS-секрета берётся только публичная часть (`tls.crt`); приватный ключ порталу
  не нужен и в под не попадает. Тот же `keys` работает и для
  `trustedCA.existingConfigMaps`, если из объекта нужен не весь набор ключей.
- `GOMAXPROCS` и `GOMEMLIMIT` проставляются сами по лимитам контейнера, отдельно
  порталу и коллектору. Без первого рантайм Go считает себя по числу ядер ноды и
  на маленьком лимите CPU теряет время в троттлинге; второй - мягкий предел
  памяти, у которого сборщик мусора работает чаще и отдаёт память раньше, чем
  ядро убьёт контейнер по OOM. Значение GOMEMLIMIT считает чарт (90% лимита по
  умолчанию, `goRuntime.memLimitPercent`), потому что downward API умеет
  подставить только лимит целиком. Обе переменные появляются лишь у компонента с
  соответствующим лимитом; выключаются `goRuntime.maxProcsFromLimits: false` и
  `goRuntime.memLimitPercent: 0`, перекрываются через `extraEnv`.

## [0.5.0] - 2026-08-20

### Added
- `trustedCA` - корневые сертификаты внутреннего удостоверяющего центра. Портал
  проверяет сертификаты Keycloak, Argo CD, GitLab и Harbor по списку публичных
  корней из образа, и за самоподписанным сертификатом падал на старте с
  `x509: certificate signed by unknown authority`. Теперь сертификаты берутся из
  готовых ConfigMap (`trustedCA.existingConfigMaps`, список) или прямо из значений
  (`trustedCA.certs`, ключ - имя файла), и то и другое сразу. Всё складывается
  в один projected-том, монтируется порталу и коллектору в `/etc/ssl/certs/extra`
  и добавляется к публичным корням через `SSL_CERT_DIR`, не заменяя их.
- `portal.extraVolumes`, `portal.extraVolumeMounts`, `portal.extraEnv` и те же
  ключи у `collector`: произвольные тома и переменные окружения, когда нужного
  нет в `config`/`secrets`. Раньше такое приходилось дописывать патчем поверх
  релиза, и патч слетал на следующем `helm upgrade`.

## [0.4.1] - 2026-08-19

### Added
- README: раздел «Доступ к Argo CD». Портал ходит в Argo CD под отдельным
  аккаунтом, которому нужны права на чтение и синхронизацию приложений своего
  проекта, а проект в этих правах должен совпадать с
  `portal.config.ARGOCD_PROJECT`.

## [0.4.0] - 2026-08-18

### Fixed
- `portal.config.STATUS_UPDATE_MODE` по умолчанию был `polling` - такого режима в
  портале нет с версии, где появились вебхуки, и портал с этим значением отказывался
  стартовать. Теперь `hybrid`: периодический reconcile плюс вебхуки поверх. Второе
  допустимое значение - `webhook`. Если вы переопределяли этот ключ значением
  `polling`, замените его на `hybrid`.

### Added
- В `portal.config` добавлены переменные, которые портал читает, а чарт не описывал:
  `CHART_REGISTRY` (OCI-эндпоинт Harbor, на который манифест заказа ссылается как на
  источник чарта), `GITLAB_WEBHOOK_URL` и `GITLAB_WEBHOOK_SCOPE` (портал сам
  регистрирует свой вебхук в GitLab), `GRAFANA_URL`, `OIDC_POST_LOGOUT_REDIRECT`,
  `RBAC_TEAM_GROUP_REGEX`, `HARBOR_INSECURE_TLS`, `HARBOR_TIMEOUT`, `GITLAB_TIMEOUT`,
  `DATABASE_MAX_CONNS`.
- В `portal.secrets` добавлены `GITLAB_WEBHOOK_TOKEN` и `HARBOR_WEBHOOK_SECRET`.

### Changed
- `appVersion` поднят до `0.4.0`: тег образа портала по умолчанию брался из него и
  указывал на сборку двух релизов назад.
- Обязательные переменные (`HARBOR_URL`, `GITLAB_URL`, `ARGOCD_URL`, `GITLAB_TOKEN`,
  `ARGOCD_TOKEN`) помечены в `values.yaml` как обязательные: без них портал не
  стартует и называет недостающие сам.
- Комментарии в `values.yaml` переведены на русский - как в остальных чартах
  репозитория.

## [0.3.3] - 2026-08-12

### Changed
- Описание чарта переписано для человека, который выбирает сервис в каталоге портала.
- Подчарт `ingress-gateway` подтянут до 4.0.1.

## [0.3.2] - 2026-08-11

### Changed
- Опциональный вход через сабчарт `ingress-gateway` переведён на его версию
  `4.0.0`: блок значений `ingressGateway.naming` переименован в
  `ingressGateway.identity` (`instance`/`cluster`/`project`), теги окружения в
  примере заменены на допустимые. Если вход включён (`ingressGateway.enabled`),
  этот блок в своих values нужно переименовать.

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
