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
| `portal.externalSecret` | Наполнять `Secret` из Vault через External Secrets Operator |
| `portal.replicaCount`, `portal.autoscaling` | Сколько реплик портала держать и когда добавлять |
| `portal.metrics`  | Экспозиция Prometheus-метрик (порт + scrape-аннотации)           |
| `trustedCA`       | Корневые сертификаты внутреннего УЦ для апстримов по HTTPS        |
| `*.extraVolumes`, `*.extraVolumeMounts`, `*.extraEnv` | Произвольные тома и env компонента |
| `collector`       | Компонент-коллектор: in-cluster сбор каталога в Redis            |
| `serviceAccount`  | Создание/имя ServiceAccount портала                            |
| `ingressGateway`  | Опциональный вход сабчартом `ingress-gateway` (выкл. по умолчанию)|

Переменные окружения портала соответствуют env-тегам `config.go`; полный список
с дефолтами - в `.env.example` репозитория console. Пустые значения в `config`/
`secrets` не рендерятся, поэтому применяются дефолты из `config.go`.

### Секреты из Vault

Секреты портала можно не держать в values. Тогда `Secret`, который монтирует
Deployment, наполняет External Secrets Operator, читая значения из Vault, а чарт
хранит только адрес хранилища и то, какие пути из него брать.

Нужны две вещи в кластере: сам External Secrets Operator и `SecretStore`,
знающий дорогу в Vault. Второй создаёт чарт `secret-store` из этого же
репозитория - по умолчанию с именем `vault` в том же namespace.

Проще всего, когда все значения лежат в одном пути KV и ключи там уже названы
как переменные портала (`DATABASE_URL`, `SESSION_SECRET`, `GITLAB_TOKEN` и
остальные):

```yaml
portal:
  externalSecret:
    enabled: true
    secretStoreRef:
      name: vault
    dataFrom:
      - extract:
          key: console/portal
```

Когда имена в Vault свои, значения перечисляются по одному:

```yaml
portal:
  externalSecret:
    enabled: true
    secretStoreRef:
      name: vault
    data:
      - secretKey: GITLAB_TOKEN
        remoteRef:
          key: console/portal
          property: gitlab_token
      - secretKey: ARGOCD_TOKEN
        remoteRef:
          key: console/portal
          property: argocd_token
```

`dataFrom` и `data` можно задавать вместе: сначала берётся путь целиком, потом
добавляются отдельные значения. Поля повторяют `ExternalSecret` как есть, без
переименований, поэтому всё остальное из его документации (`template`,
`creationPolicy`, `refreshInterval`) тоже доступно. Хранилище на весь кластер
подключается через `secretStoreRef.kind: ClusterSecretStore`.

То же самое есть у коллектора - `collector.externalSecret`, с одним значением
`REDIS_URL`.

Три способа задать секреты взаимоисключающие: `secrets` (значения в values),
`existingSecret` (готовый `Secret`) и `externalSecret`. Задать последние два
вместе нельзя, и включить `externalSecret`, не указав ни `data`, ни `dataFrom`,
тоже нельзя - в обоих случаях рендер падает.

Одного оператор не делает: смена значения в Vault не перезапускает поды. `Secret`
обновится, а портал читает переменные окружения один раз, при старте, поэтому
после ротации поды надо перезапустить.

### Несколько реплик и автоскейлинг

Портал умеет работать в нескольких репликах. События, которыми живут открытые
страницы, ходят между ними через Redis, и там же лежит аренда, по которой
фоновые циклы (сверка заказов, обновление счётчиков) ведёт ровно одна реплика.

Поэтому у обеих настроек одно условие: `portal.config.CACHE=redis`. С
`CACHE=memory` каждая реплика держала бы свои сессии, не слышала бы чужих
событий и вела бы фоновые циклы сама - чарт в этом случае не рендерится и
объясняет, почему. Нужен портал 0.10.0 и новее.

Фиксированное число реплик:

```yaml
portal:
  replicaCount: 3
  config:
    CACHE: redis
```

Или автоскейлер, который добавляет их сам:

```yaml
portal:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
  config:
    CACHE: redis
```

При включённом `autoscaling` поле `replicas` из Deployment убирается: число
реплик принадлежит автоскейлеру, и оставленное поле Helm возвращал бы обратно на
каждом `upgrade`. HPA считает загрузку долей от `resources.requests`, поэтому
метрика без соответствующего request рендер тоже роняет.

Коллектор не масштабируется: он каждый цикл переписывает снимок целиком, и
вторая реплика просто во второй раз обходит Kubernetes API.

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

Оба компонента идут с заданными `resources`, поэтому поды получают QoS
Burstable, планировщик резервирует под них место, и в namespace с ResourceQuota
релиз ставится без правок:

| Компонент   | requests            | limits              |
|-------------|---------------------|---------------------|
| `portal`    | 100m / 256Mi        | 1 / 512Mi           |
| `collector` | 50m / 64Mi          | 200m / 256Mi        |

Это отправная точка для небольшой установки, а не измеренная норма. Портал
держит пул соединений к Postgres, отдаёт SPA из памяти образа и кэширует
прочитанные чарты Harbor, поэтому под большой каталог поднимайте сначала память.
Коллектор просыпается раз в `POLL_INTERVAL` и между обходами почти простаивает;
его память растёт с числом контроллеров в кластере. Понаблюдайте за подами и
подгоните значения под себя - `resources: {}` снимает их совсем.

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
  # Обязателен: из него собираются имена ресурсов гейтвея и labels ecpk/*.
  identity:
    instance: ed
    cluster: dev
    project: cnsl
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

Пример поднимает вход по HTTP. Если гейтвей должен расшифровывать TLS
(`tlsMode: Terminate`), сабчарту нужна запись в `ingressGateway.tls.certificates`
с путём к сертификату в Vault - сертификаты в значениях он больше не принимает.
Подробности - в `charts/ingress-gateway/README.md`.

Сабчарт вендорится локально; перед упаковкой выполните `helm dependency build`
(каталог `charts/` и `Chart.lock` в git не хранятся).

## Валидации

Часть сочетаний значений чарт не рендерит вовсе, а падает с объяснением: молча
поставить сломанный релиз хуже, чем не поставить его совсем.

| Когда падает | Что поправить |
|---|---|
| `portal.autoscaling.enabled` или `portal.replicaCount` больше 1, а `portal.config.CACHE` не `redis` | Поставить `CACHE: redis`: без общего Redis реплики не видят сессий и событий друг друга и ведут фоновые циклы каждая сама |
| `portal.autoscaling.minReplicas` меньше 1 | Минимум - одна реплика |
| `portal.autoscaling.maxReplicas` меньше `minReplicas` | Поправить границы |
| Включён `autoscaling` без `targetCPUUtilizationPercentage` и `targetMemoryUtilizationPercentage` | Задать хотя бы одну метрику: без метрики автоскейлер ничего не делает |
| Метрика CPU или памяти задана, а соответствующего `portal.resources.requests` нет | Задать request: HPA считает загрузку долей от него |
| Заданы одновременно `existingSecret` и `externalSecret.enabled` (портал или коллектор) | Оставить один способ |
| Включён `externalSecret` без `data` и без `dataFrom` | Указать, что читать из Vault: иначе оператор создаст пустой Secret |
| Включён `externalSecret` без `secretStoreRef.name` | Назвать `SecretStore` |
| `goRuntime.memLimitPercent` больше нуля, а лимит памяти записан так, что чарт не может его разобрать | Поправить лимит или поставить `memLimitPercent: 0` |

## Проверка рендера

```bash
helm lint ./console
helm template console ./console -f my-values.yaml | less
# с включённым входом:
helm template console ./console --set ingressGateway.enabled=true | less
```
