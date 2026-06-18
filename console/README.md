# console - usage

Чарт разворачивает IDP Console - портал самообслуживания. Состоит из двух
компонентов:

| Компонент | Что это                                  | Порт |
|-----------|------------------------------------------|------|
| `portal`  | Go-бэкенд (`cmd/portal`)                 | 8080 |
| `web`     | nginx: отдаёт SPA и проксирует `/api`    | 80   |

Внешний трафик идёт на `web` (входная точка): статика отдаётся напрямую, а
запросы `/api` nginx проксирует на Service портала. `portal` наружу не
публикуется. Сам Ingress чарт не создаёт - вход публикуется снаружи (например
через отдельный `ingress-gateway`), маршрутизируя трафик на Service `web`.

```
   внешний вход (ingress-gateway / LB)
               |
            web (nginx) --/api--> portal --> Postgres / Redis / Keycloak / upstreams
               |
          SPA (static)
```

## Установка

```bash
helm upgrade --install console ./console \
  --namespace console --create-namespace \
  -f my-values.yaml
```

Минимально нужно задать образы, адрес и секреты:

```yaml
imageRegistry: registry.example.com

portal:
  image:
    repository: idp/console-portal
    tag: "0.1.0"
  config:
    PUBLIC_URL: https://console.example.com
    OIDC_ISSUER: https://keycloak.example.com/realms/internal
    OIDC_REDIRECT_URL: https://console.example.com/api/v1/auth/callback
    HARBOR_URL: https://harbor.example.com
    GITLAB_URL: https://gitlab.example.com
    ARGOCD_URL: https://argocd.example.com
  secrets:
    DATABASE_URL: postgres://portal:pass@postgres:5432/portal?sslmode=disable
    REDIS_URL: redis://redis:6379/0
    SESSION_SECRET: change-me
    OIDC_CLIENT_SECRET: change-me
    GITLAB_TOKEN: change-me
    ARGOCD_TOKEN: change-me

web:
  image:
    repository: idp/console-web
    tag: "0.1.0"
```

Публикацию входа (Ingress / Gateway на Service `web`) настройте отдельно -
чарт его не создаёт.

## Конфигурация

| Секция            | Что задаёт                                                        |
|-------------------|------------------------------------------------------------------|
| `imageRegistry`   | Общий префикс реестра для обоих образов                          |
| `portal.config`   | Несекретные env портала (см. `internal/config/config.go`)        |
| `portal.secrets`  | Секретные env (рендерятся в `Secret`)                            |
| `portal.existingSecret` | Использовать заранее созданный `Secret` вместо рендера     |
| `web.devAuth`     | Инъекция `X-Dev-*` в nginx (только для `AUTH_MODE=dev`)          |
| `serviceAccount`  | Создание/имя ServiceAccount                                     |

Переменные окружения портала соответствуют env-тегам `config.go`; полный список
с дефолтами - в `.env.example` репозитория idp. Пустые значения в `config`/
`secrets` не рендерятся, поэтому применяются дефолты из `config.go`.

### Зависимости

Чарт деплоит только саму консоль. Postgres, Redis, Keycloak и апстримы
(Harbor / GitLab / ArgoCD) считаются внешними - их адреса и токены задаются через
`portal.config` и `portal.secrets`.

### Режим аутентификации

- **OIDC (прод):** `portal.config.AUTH_MODE: oidc`, заполните `OIDC_*` и
  `OIDC_CLIENT_SECRET`; `web.devAuth.enabled: false`.
- **dev (демо/тест):** `portal.config.AUTH_MODE: dev`; при желании
  `web.devAuth.enabled: true`, чтобы nginx подставлял `X-Dev-Teams`/`X-Dev-Role`.

## Проверка рендера

```bash
helm lint ./console
helm template console ./console -f my-values.yaml | less
```
