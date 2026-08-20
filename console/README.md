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
| `trustedCA`       | Корневые сертификаты внутреннего УЦ для апстримов по HTTPS        |
| `*.extraVolumes`, `*.extraVolumeMounts`, `*.extraEnv` | Произвольные тома и env компонента |
| `collector`       | Компонент-коллектор: in-cluster сбор каталога в Redis            |
| `serviceAccount`  | Создание/имя ServiceAccount портала                            |
| `ingressGateway`  | Опциональный вход сабчартом `ingress-gateway` (выкл. по умолчанию)|

Переменные окружения портала соответствуют env-тегам `config.go`; полный список
с дефолтами - в `.env.example` репозитория console. Пустые значения в `config`/
`secrets` не рендерятся, поэтому применяются дефолты из `config.go`.

### Зависимости

Чарт деплоит только саму консоль. Postgres, Redis, Keycloak и апстримы
(Harbor / GitLab / ArgoCD) считаются внешними - их адреса и токены задаются через
`portal.config` и `portal.secrets`.

### Самоподписанные сертификаты

Портал ходит в Keycloak, Argo CD, GitLab и Harbor по HTTPS и проверяет их
сертификаты по списку публичных корней в образе. Если апстримы выпущены
внутренним удостоверяющим центром, портал упадёт на старте с ошибкой вида
`x509: certificate signed by unknown authority`. Отдайте ему корневой сертификат
этого центра.

Готовыми ConfigMap, сколько бы их ни было:

```yaml
trustedCA:
  existingConfigMaps:
    - internal-ca
    - keycloak-ca
```

Из Secret, если сертификат уже лежит там. Берите только публичную часть -
`tls.crt`; в `keys` слева ключ секрета, справа имя файла в каталоге:

```yaml
trustedCA:
  existingSecrets:
    - name: keycloak-tls
      keys:
        tls.crt: keycloak-ca.crt
```

Приватный ключ (`tls.key`) порталу не нужен и монтировать его не стоит: портал
проверяет чужие сертификаты, а свой никому не предъявляет. Тот же `keys`
работает и для ConfigMap, когда из объекта нужен не весь набор ключей.

Или прямо значениями, тогда ConfigMap создаст чарт. Ключ - имя файла, значение -
PEM, сертификатов может быть сколько угодно:

```yaml
trustedCA:
  certs:
    internal-root.crt: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
    keycloak-ca.crt: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
```

Поля можно задавать вместе: том собирается как `projected`, и всё из
`existingConfigMaps`, `existingSecrets` и `certs` попадает в один каталог
`/etc/ssl/certs/extra`.
Имена файлов при этом должны различаться: два источника с одинаковым ключом
kubelet смонтировать не даст, и под не запустится. Сертификаты добавляются к
публичным корням через `SSL_CERT_DIR`, поэтому доверие к публичным центрам
сохраняется. Те же сертификаты получает и `collector`.

Список корней читается один раз при первом обращении, так что подмена
сертификата в ConfigMap подхватится только после перезапуска подов. При
`trustedCA.certs` чарт перезапускает их сам, при `existingConfigMaps` и
`existingSecrets` перезапуск за вами.

Ошибки `certificate is valid for ...` или `certificate relies on legacy Common
Name field` этим не лечатся: у сертификата апстрима нет SAN на то имя, которым
вы его зовёте, и его нужно перевыпустить.

Отдельно стоит Harbor: у него есть `portal.config.HARBOR_INSECURE_TLS`, который
проверку просто отключает. Это ручка для стендов - на проде задавайте
`trustedCA`.

### Свои тома и переменные

Когда компоненту нужно что-то, чего чарт не описывает, у портала и коллектора
есть `extraVolumes`, `extraVolumeMounts` и `extraEnv`. Пишутся как в манифесте
пода и добавляются к тому, что чарт создаёт сам:

```yaml
portal:
  extraVolumes:
    - name: custom-config
      configMap:
        name: custom-config
  extraVolumeMounts:
    - name: custom-config
      mountPath: /etc/console
      readOnly: true
  # env берёт верх над одноимённым ключом из config/secrets
  extraEnv:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: postgres-app
          key: uri
```

### Ресурсы и рантайм Go

`portal.resources` и `collector.resources` по умолчанию пустые: без них поды
получают QoS BestEffort, и в namespace с ResourceQuota просто не создадутся.
Рабочая отправная точка:

```yaml
portal:
  resources:
    requests: {cpu: 100m, memory: 256Mi}
    limits: {cpu: "1", memory: 512Mi}

collector:
  resources:
    requests: {cpu: 50m, memory: 64Mi}
    limits: {cpu: 200m, memory: 256Mi}
```

По заданным лимитам чарт сам настраивает рантайм Go, отдельно для портала и
коллектора:

| Переменная   | Откуда                                    | Ключ                            |
|--------------|-------------------------------------------|---------------------------------|
| `GOMAXPROCS` | лимит CPU, округление вверх до ядра        | `goRuntime.maxProcsFromLimits`  |
| `GOMEMLIMIT` | доля лимита памяти, по умолчанию 90%       | `goRuntime.memLimitPercent`     |

Без `GOMAXPROCS` Go считает себя по числу ядер ноды и на маленьком лимите теряет
время в троттлинге. `GOMEMLIMIT` - мягкий предел: у этой границы сборщик мусора
работает чаще и отдаёт память раньше, чем ядро убьёт контейнер по OOM. Значение
считает чарт, потому что downward API умеет только подставить лимит целиком, а
100% лимита как раз и приводит к тому, от чего эта переменная защищает.

При `limits.memory: 512Mi` получается `GOMEMLIMIT=460MiB`. Обе переменные
появляются только у того компонента, которому задан соответствующий лимит.
`maxProcsFromLimits: false` и `memLimitPercent: 0` отключают их, а перекрыть
своим значением можно через `extraEnv`.

### Аутентификация

Аутентификация только через OIDC (Keycloak). Задайте `OIDC_ISSUER`,
`OIDC_CLIENT_ID`, `OIDC_REDIRECT_URL` в `portal.config` и `OIDC_CLIENT_SECRET` в
`portal.secrets`. `AUTH_MODE` по умолчанию `oidc` (единственный валидный режим),
значение в `config` оставлено явно для наглядности.

### Доступ к Argo CD

Портал читает состояние своих приложений в Argo CD и запускает их синхронизацию.
Ходит он туда не от имени человека, а под отдельным аккаунтом Argo CD, поэтому
вход пользователей через Keycloak на это не влияет.

Аккаунт заводится в `argocd-cm`:

```yaml
data:
  accounts.console: apiKey
```

Права - в `argocd-rbac-cm`. Порталу хватает двух действий в своём проекте,
чтения и синхронизации:

```yaml
data:
  policy.csv: |
    p, role:console, applications, get,  portal-managed/*, allow
    p, role:console, applications, sync, portal-managed/*, allow
    g, console, role:console
```

Долгоживущий токен этого аккаунта кладётся в `portal.secrets.ARGOCD_TOKEN`.
Портал читает его один раз при старте, так что смена токена требует перезапуска.

`portal-managed` в правилах - проект, в котором лежат приложения портала. Он
должен совпадать с `portal.config.ARGOCD_PROJECT`: это значение портал
подставляет в `spec.project` манифестов, которые коммитит в Git. Разойдутся -
приложения окажутся вне выданных прав, и синхронизация будет отбита.

Шире права не нужны. Если их меньше, симптом получается обманчивый: отказ на
чтение портал считает за отсутствующее приложение, и заказ выглядит удалённым,
а не сломанным.

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
