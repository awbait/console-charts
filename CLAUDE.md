# CLAUDE.md - console-charts

Это **отдельный репозиторий** (`git@github.com:awbait/console-charts.git`) с
Helm-чартами платформы. Он лежит внутри рабочей папки `console/charts/`, но имеет
свой `.git`, свою историю и свои правила. Правила репозитория `console` (bun для
`web/`, синк `.env.example` с `config.go`, observability-конвенции, Go-код) сюда
**не относятся**. Действуют только конвенции ниже.

## Что внутри

Каждая директория верхнего уровня - самостоятельный чарт:

- `console/` - сам портал Console (Go-бэкенд `portal` на :8080, отдаёт API +
  встроенный SPA). Это деплой-артефакт основного репозитория `console`. Его env-ключи
  (`portal.config` / `portal.secrets`) обязаны соответствовать
  `internal/config/config.go` и `.env.example` из репозитория `console`.
- `ingress-gateway/` - Istio Gateway API (Gateway, xRoutes, NetworkPolicy,
  AuthorizationPolicy, OIDC).
- `egress-gateway/` - Istio waypoint-based egress (Gateway, ServiceEntry, TLSRoute)
  + kube-ovn `VpcEgressGateway`.
- `waypoint/` - Istio ambient waypoint proxy.
- `policies/` - декларативные правила доступа между сервисами: `NetworkPolicy` +
  Istio `AuthorizationPolicy`.
- `namespace/` (`managed-namespace`) - namespace + ResourceQuota + subnet.

Чарты публикуются в Harbor и заказываются через портал; репозиторий `console`
chart-agnostic, реальные чарты приходят отсюда (см. `docs/chart-convention.md` в
`console`).

## Универсальные правила (действуют и здесь)

- **Никогда не добавлять `Co-Authored-By` в коммиты.**
- **Никогда не добавлять `Generated with Claude Code` в PR/MR.**
- **Не использовать длинное тире (em dash) нигде** - ни в YAML, ни в Markdown, ни
  в коммитах, ни в ответах. Только дефис `-`, двоеточие или перестроить фразу.
  (Репозиторий уже придерживается этого.)
- **Отвечать на русском.**
- **Git-операции - через скилл `git-workflow`** (ветки, коммиты, PR/MR, релизы).
- **Удалять артефакты сборки** (`*.tgz`, `charts/`-вендоринг, `Chart.lock` - уже в
  `.gitignore`). Не оставлять упакованные чарты в рабочей директории.

## Конвенции чартов

Полный справочник по структуре и оформлению чартов - в **`CONVENTIONS.md`**:
нейминг ресурсов и реестр `kindShort`, `Chart.yaml`/SemVer, обязательный
`values.yaml`, `values.schema.json`, `_helpers.tpl`, README/CHANGELOG/NOTES,
проверка перед коммитом и исключения (`console`, `namespace`). Эти правила там и
правь - не дублируй их здесь.

Здесь - только то, что специфично для процесса репозитория:

- **Conventional Commits, scope = имя чарта.** `feat(console): ...`,
  `fix(ingress-gateway): ...`, `chore(namespace): ...`. Заголовок и тело - на
  **английском** (как в последних коммитах репо). Markdown-документы внутри чартов
  (`README.md`, `CHANGELOG.md`) и комментарии в `values.yaml` - **на русском, это
  принятая здесь практика** (в отличие от исходников основного репозитория).
- **Проверка перед коммитом - твоя обязанность** (`helm lint` / `helm template`,
  валидация рендера по схеме; конкретные команды - в `CONVENTIONS.md`). Lefthook на
  push - бэкстоп, не замена локальной проверки.

## Связь с репозиторием console

Чарт `console` - это пункт «Helm-чарт портала» из `console/TODO.md`, уже частично
реализованный здесь. При доработке портала (новый env, новый порт, проба, и т.п.)
правки идут в оба места: код/`.env.example` в `console` и `console/values.yaml` +
`console/templates/...` + bump версии + `CHANGELOG.md` здесь.
