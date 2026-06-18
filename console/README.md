# console - usage

Чарт разворачивает Console - портал самообслуживания. Один компонент: `portal`
(Go-бэкенд, :8080), который отдаёт и API, и встроенный SPA. Отдельного web/nginx
нет.

Ingress чарт не создаёт - вход публикуется снаружи (например через отдельный
`ingress-gateway`), маршрутизируя трафик на Service `portal`.

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
imageRegistry: registry.example.com

portal:
  image:
    repository: console
    tag: "0.2.0"
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
| `serviceAccount`  | Создание/имя ServiceAccount                                     |

Переменные окружения портала соответствуют env-тегам `config.go`; полный список
с дефолтами - в `.env.example` репозитория console. Пустые значения в `config`/
`secrets` не рендерятся, поэтому применяются дефолты из `config.go`.

### Зависимости

Чарт деплоит только саму консоль. Postgres, Redis, Keycloak и апстримы
(Harbor / GitLab / ArgoCD) считаются внешними - их адреса и токены задаются через
`portal.config` и `portal.secrets`.

### Аутентификация

Чарт рассчитан на прод: аутентификация только через OIDC (Keycloak). Задайте
`OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_REDIRECT_URL` в `portal.config` и
`OIDC_CLIENT_SECRET` в `portal.secrets`. `AUTH_MODE` держите `oidc` (дефолт
`config.go` - `dev`, поэтому значение задаётся явно).

## Проверка рендера

```bash
helm lint ./console
helm template console ./console -f my-values.yaml | less
```
