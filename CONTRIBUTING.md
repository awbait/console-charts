# Как участвовать в разработке

Правила репозитория для людей и агентов собраны в одном файле:
[AGENTS.md](AGENTS.md). Устройство чарта описано в
[CONVENTIONS.md](CONVENTIONS.md), пошаговый порядок работы над чартом - в скилле
[chart-authoring](.agents/skills/chart-authoring/SKILL.md). Здесь короткий путь от
клонирования до первого PR.

## Рабочее место

Нужны Helm 3, Git и Python 3.11 или новее (скрипты в `tools/` и скиллах).
Один раз после клонирования:

```bash
go install github.com/evilmartians/lefthook@latest
lefthook install              # хук на git push: helm lint и helm template по всем чартам
```

Переводы строк закреплены в `.gitattributes`: в репозитории и в рабочей копии
LF на любой платформе, настройка `core.autocrlf` не нужна.

## Как устроена работа

1. **Задача** живёт в issue (`.github/ISSUE_TEMPLATE/`). Метки и статусы
   описаны в скилле `issue-workflow`. План одобряет и PR сливает владелец.
2. **Ветка** от `main`: `feat/42-short-description`, `fix/...`, `chore/...`,
   `docs/...`. В `main` напрямую не коммитим.
3. **Перед правкой чарта** прочитайте `CONVENTIONS.md` и README этого чарта.
   Шаблоны, `values*.yaml`, `values.schema.json`, README и CHANGELOG меняются
   согласованно, версия в `Chart.yaml` поднимается по SemVer, зависимые чарты
   обновляются при необходимости.
4. **Коммиты** по Conventional Commits, на английском, scope равен имени чарта
   (`fix(ingress-gateway): ...`); для общерепозиторных правок scope можно не
   указывать. Без упоминаний ИИ.
5. **Проверка до коммита**: `helm lint` и `helm template` по всем файлам
   значений чарта, затем `sh scripts/helm-check.sh`. Lefthook повторит это на
   push.
6. **PR** в `main` по шаблону: что было, что сделано, проверка, что не
   проверено, совместимость. Заголовок на английском в формате Conventional
   Commits. `Closes #N` закрывает issue. Один PR - одна логически связанная
   правка.

## Язык

- Описания PR, ответы в review, комментарии к issue и обсуждения на русском.
- `README.md`, `CHANGELOG.md` и комментарии в `values*.yaml` на русском.
- Комментарии в `templates/` только на английском.
- Длинное тире не используется нигде.

## Если работаете с агентом

Claude Code и Codex читают `AGENTS.md` и скиллы сами. Тексты, которые видит
пользователь портала (подписи полей схемы, `NOTES.txt`, README и CHANGELOG
чарта), пишет codex по правилу `.claude/rules/user-facing-text.md`; остальное
агент делает по общим правилам.
