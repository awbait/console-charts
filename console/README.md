# console - usage

Чарт разворачивает Console - портал самообслуживания. Основной компонент -
`portal` (Go-бэкенд, :8080), который отдаёт и API, и встроенный SPA (отдельного
web/nginx нет). Опционально включается компонент `collector` - фоновый сбор
каталога workload'ов кластера в Valkey/Redis (см. ниже).

По умолчанию Ingress чарт не создаёт - вход публикуется снаружи (например через
отдельный `ingress-gateway`), маршрутизируя трафик на Service `portal`. Вход можно
поднять и из этого чарта - опциональным сабчартом `ingress-gateway` (см. ниже).

```
   внешний вход (ingress-gateway / LB)
               |
            portal (SPA + /api) --> Postgres / Redis / Keycloak / upstreams
```

## Установка

```bash
helm upgrade --install console ./console \
  --namespace console --create-namespace \
  -f my-values.yaml
```

Минимально нужно задать образ, адрес и секреты:

```yaml
imageRegistry: ghcr.io/awbait

portal:
  image:
    repository: console/portal
    tag: "0.4.0"
  config:
    PUBLIC_URL: https://console.example.com
    OIDC_ISSUER: https://keycloak.example.com/realms/internal
    OIDC_REDIRECT_URL: https://console.example.com/api/v1/auth/callback
    HARBOR_URL: https://harbor.example.com
    GITLAB_URL: https://gitlab.example.com
    ARGOCD_URL: https://argocd.example.com
    # OCI-эндпоинт Harbor: на него манифест заказа ссылается как на источник
    # чарта, и резолвиться он должен и из портала, и из подов ArgoCD.
    CHART_REGISTRY: harbor.example.com
  secrets:
    DATABASE_URL: postgres://portal:pass@postgres:5432/portal?sslmode=disable
    REDIS_URL: redis://redis:6379/0
    SESSION_SECRET: change-me
    OIDC_CLIENT_SECRET: change-me
    GITLAB_TOKEN: change-me
    ARGOCD_TOKEN: change-me
```

Публикацию входа (Ingress / Gateway на Service `portal`) настройте отдельно -
чарт его не создаёт.

## Конфигурация

| Секция            | Что задаёт                                                        |
|-------------------|------------------------------------------------------------------|
| `imageRegistry`   | Префикс реестра для образа                                       |
| `portal.config`   | Несекретные env портала (см. `internal/config/config.go`)        |
| `portal.secrets`  | Секретные env (рендерятся в `Secret`)                            |
| `portal.existingSecret` | Использовать заранее созданный `Secret` вместо рендера     |
| `portal.metrics`  | Экспозиция Prometheus-метрик (порт + scrape-аннотации)           |
| `collector`       | Компонент-коллектор: in-cluster сбор каталога в Redis            |
| `serviceAccount`  | Создание/имя ServiceAccount портала                            |
| `ingressGateway`  | Опциональный вход сабчартом `ingress-gateway` (выкл. по умолчанию)|

Переменные окружения портала соответствуют env-тегам `config.go`; полный список
с дефолтами - в `.env.example` репозитория console. Пустые значения в `config`/
`secrets` не рендерятся, поэтому применяются дефолты из `config.go`.

Пять переменных портал требует на старте и без них не поднимается, называя
недостающие: `HARBOR_URL`, `GITLAB_URL`, `ARGOCD_URL` в `portal.config` и
`GITLAB_TOKEN`, `ARGOCD_TOKEN` в `portal.secrets`. В `values.yaml` они оставлены
пустыми намеренно.

### Обновление состояния заказов

`STATUS_UPDATE_MODE` задаёт, как портал узнаёт об изменениях, и принимает два
значения:

- `hybrid` (по умолчанию) - периодический reconcile с частотой
  `STATUS_POLL_INTERVAL` плюс входящие вебхуки GitLab и Harbor поверх. Без
  секретов вебхуков вырождается в чистый опрос, что и нужно на стенде.
- `webhook` - только вебхуки, без периодического опроса. Требует
  `GITLAB_WEBHOOK_TOKEN`: без него жизненный цикл заказа не двинется.

Отдельного режима «только опрос» нет.

Вебхуки настраиваются парой значений на каждый апстрим: секрет в
`portal.secrets` (`GITLAB_WEBHOOK_TOKEN`, `HARBOR_WEBHOOK_SECRET`) и тот же
секрет на стороне GitLab / Harbor. Если задать ещё и `GITLAB_WEBHOOK_URL` (адрес
портала, каким его видит GitLab), портал зарегистрирует вебхук сам - на старте, на
создаваемых репозиториях и на усыновлённых из Git. `GITLAB_WEBHOOK_SCOPE`
выбирает форму регистрации: `group` (нужен GitLab Premium), `system` (нужен
админский токен), `project` (на каждом репозитории) или `auto` - самая широкая,
которую разрешает инстанс.

### Зависимости

Чарт деплоит только саму консоль. Postgres, Redis, Keycloak и апстримы
(Harbor / GitLab / ArgoCD) считаются внешними - их адреса и токены задаются через
`portal.config` и `portal.secrets`.

### Аутентификация

Аутентификация только через OIDC (Keycloak). Задайте `OIDC_ISSUER`,
`OIDC_CLIENT_ID`, `OIDC_REDIRECT_URL` в `portal.config` и `OIDC_CLIENT_SECRET` в
`portal.secrets`. `AUTH_MODE` по умолчанию `oidc` (единственный валидный режим),
значение в `config` оставлено явно для наглядности.

### Метрики

Портал отдаёт Prometheus-метрики на отдельном порту (`METRICS_PORT`, по умолчанию
2112). При `portal.metrics.enabled=true` (дефолт) порт `metrics` выводится в
`Service` и `containerPort`, а `portal.metrics.scrapeAnnotations=true` проставляет
на под `prometheus.io/scrape|port|path`. Значение `portal.metrics.port` должно
совпадать с `config.METRICS_PORT`.

### Коллектор

Компонент `collector` (`collector.enabled`, по умолчанию включён) - отдельный
Deployment: раз в `POLL_INTERVAL` обходит namespace кластера по метке
`NS_LABEL_SELECTOR`, собирает контроллеры (Deployment/StatefulSet/DaemonSet) и
пишет снимок в Valkey/Redis. Портал читает снимок из того же Redis и в Kubernetes
API сам не ходит. У коллектора нет HTTP, поэтому ни Service, ни проб нет.

Коллектору нужен read-only доступ к кластеру: чарт создаёт отдельный
`ServiceAccount` + `ClusterRole`/`ClusterRoleBinding` (`get/list/watch` на
`namespaces` и apps-контроллеры). Отключить RBAC - `collector.rbac.create=false`,
весь компонент - `collector.enabled=false`.

Задайте `collector.secrets.REDIS_URL` (тот же Valkey/Redis, что у портала) или
`collector.existingSecret` с ключом `REDIS_URL`.

```yaml
collector:
  enabled: true
  secrets:
    REDIS_URL: redis://valkey:6379/0
  config:
    NS_LABEL_SELECTOR: "idp.scan=true"
    CLUSTER_NAME: prod-eu
```

### Вход сабчартом ingress-gateway (опционально)

По умолчанию выключено (`ingressGateway.enabled=false`). При включении чарт через
сабчарт `ingress-gateway` поднимает Istio `Gateway` + `HTTPRoute` на Service
портала. Требует Istio и Gateway API CRDs в кластере.

```yaml
ingressGateway:
  enabled: true
  gateways:
    - name: main
      listeners:
        - { name: http, port: 80, protocol: HTTP, hostname: console.example.com }
  xroutes:
    - name: portal
      parentRefs: [{ gateway: main, sectionName: http }]
      hostnames: [console.example.com]
      rules:
        - matches: [{ path: { type: PathPrefix, value: / } }]
          # Имя Service портала: {release}-portal (по умолчанию console-portal).
          backendRefs: [{ name: console-portal, port: 8080 }]
```

Сабчарт вендорится локально; перед упаковкой выполните `helm dependency build`
(каталог `charts/` и `Chart.lock` в git не хранятся).

## Проверка рендера

```bash
helm lint ./console
helm template console ./console -f my-values.yaml | less
# с включённым входом:
helm template console ./console --set ingressGateway.enabled=true | less
```
