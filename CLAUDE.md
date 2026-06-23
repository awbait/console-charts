# CLAUDE.md - console-charts

Это **отдельный репозиторий** (`git@github.com:awbait/console-charts.git`) с
Helm-чартами платформы. Он лежит внутри рабочей папки `idp/charts/`, но имеет
свой `.git`, свою историю и свои правила. Правила репозитория `idp` (bun для
`web/`, синк `.env.example` с `config.go`, observability-конвенции, Go-код) сюда
**не относятся**. Действуют только конвенции ниже.

## Что внутри

Каждая директория верхнего уровня - самостоятельный чарт:

- `console/` - сам портал Console (Go-бэкенд `portal` на :8080, отдаёт API +
  встроенный SPA). Это деплой-артефакт основного репозитория `idp`. Его env-ключи
  (`portal.config` / `portal.secrets`) обязаны соответствовать
  `internal/config/config.go` и `.env.example` из репозитория `idp`.
- `ingress-gateway/` - Istio Gateway API (Gateway, xRoutes, NetworkPolicy,
  AuthorizationPolicy, OIDC).
- `namespace/` (`managed-namespace`) - namespace + ResourceQuota + subnet.
- `waypoint/` - Istio ambient waypoint proxy.

Чарты публикуются в Harbor и заказываются через портал; репозиторий `idp`
chart-agnostic, реальные чарты приходят отсюда (см. `docs/chart-convention.md` в
`idp`).

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

- **Conventional Commits, scope = имя чарта.** `feat(console): ...`,
  `fix(ingress-gateway): ...`, `chore(namespace): ...`. Заголовок и тело - на
  **английском** (как в последних коммитах репо). Markdown-документы внутри чартов
  (`README.md`, `CHANGELOG.md`) и комментарии в `values.yaml` - **на русском, это
  принятая здесь практика** (в отличие от исходников `idp`).
- **SemVer на каждый чарт.** При любом изменении чарта поднимай `version:` в его
  `Chart.yaml` и добавляй запись в его `CHANGELOG.md` (правила и категории -
  в шапке каждого `CHANGELOG.md`: MAJOR/MINOR/PATCH, Added/Changed/Removed/...).
  `appVersion` - версия деплоимого приложения, двигается отдельно от `version`.
- **`values.schema.json` держи в синхроне с `values.yaml`.** Где схема есть
  (`ingress-gateway`, `namespace`, `waypoint`), новые/удалённые/переименованные
  ключи правь синхронно в обоих файлах.
- **Проверка перед коммитом - твоя обязанность:** `helm lint <chart>` и
  `helm template <chart> -f <chart>/values.yaml` (для примеров - с
  `minimal-values.yaml`/`values.example.yaml`) должны проходить чисто. Если есть
  схема - рендер обязан валидироваться по ней.
- **Шаблоны - чистые:** имена ресурсов и хелперы через `_helpers.tpl`,
  `.helmignore` поддерживай актуальным. Логику внутри `templates/` не засоряй
  кириллицей (комментарии Go-стиля `{{/* ... */}}` - на английском); человекочитаемые
  пояснения для пользователя - в `README.md`/`NOTES.txt`.

## Связь с репозиторием idp

Чарт `console` - это пункт «Helm-чарт портала» из `idp/TODO.md`, уже частично
реализованный здесь. При доработке портала (новый env, новый порт, проба, и т.п.)
правки идут в оба места: код/`.env.example` в `idp` и `console/values.yaml` +
`console/templates/...` + bump версии + `CHANGELOG.md` здесь.
