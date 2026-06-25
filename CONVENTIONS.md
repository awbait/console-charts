# Конвенции чартов console-charts

Единый справочник по структуре и оформлению Helm-чартов этого репозитория. Когда
добавляешь новый чарт или правишь существующий, держи его в этих рамках. Правила
процесса (ветки, коммиты, git-workflow, запрет длинного тире) - в `CLAUDE.md`;
здесь - как должен быть устроен сам чарт (включая SemVer, CHANGELOG и проверку
перед коммитом).

Эталон, на который равняемся: `ingress-gateway`, `egress-gateway`, `waypoint`,
`policies`. Два чарта - исключения по историческим причинам и описаны отдельно в
разделе [Исключения](#исключения): `console` (деплой-артефакт портала, компонентный
нейминг) и `namespace`/`managed-namespace` (cpaas-нейминг, доделывается).

Язык: Markdown-документы (`README.md`, `CHANGELOG.md`, этот файл) и комментарии во
**всех** файлах значений (`values.yaml`, `values.minimal.yaml`, `values.full.yaml`) -
на русском. Комментарии внутри `templates/` (Go-шаблоны `{{/* ... */}}`) - на
английском, без кириллицы.

---

## Чек-лист файлов чарта

| Файл                        | Обязателен | Назначение                                                        |
|-----------------------------|------------|-------------------------------------------------------------------|
| `Chart.yaml`                | да         | Метаданные, `version`/`appVersion`, зависимости                   |
| `values.yaml`               | да         | Минимальные дефолты, лишь бы рендер проходил (см. ниже)           |
| `values.full.yaml`          | да         | Полный reference: все параметры с описанием                       |
| `values.minimal.yaml`       | желательно | Базовый рабочий пример чарта                                      |
| `values.schema.json`        | да         | Схема для валидации и формы портала (см. ниже)                    |
| `templates/_helpers.tpl`    | да         | Имена ресурсов, labels, валидации - вся общая логика              |
| `templates/NOTES.txt`       | да         | Пост-установочная сводка                                          |
| `README.md`                 | да         | Usage: секции, конвенция имён, валидации, запуск                  |
| `CHANGELOG.md`              | да         | История версий по SemVer                                          |
| `.helmignore`               | да         | Стандартный набор игнор-паттернов                                 |

Все стандартные чарты (`ingress-gateway`, `egress-gateway`, `waypoint`,
`policies`, `namespace`) переведены на трёхфайловую схему значений
`values.yaml` + `values.minimal.yaml` + `values.full.yaml` (см. раздел
[Файлы значений](#файлы-значений)). Остаточные пробелы: у `policies` нет
`NOTES.txt` и `.helmignore`. Новый чарт заводи сразу с полным набором.

---

## Chart.yaml

```yaml
apiVersion: v2
name: <chart-name>          # совпадает с именем директории и scope в коммитах
description: <одна строка>
type: application
version: "1.2.3"            # SemVer чарта; двигается при любом изменении чарта
appVersion: "1.2.3"        # версия деплоимого приложения; двигается отдельно
```

- `name` = имя директории = scope в Conventional Commits (`feat(<name>): ...`).
  Исключение: директория `namespace/`, а `name: managed-namespace`.
- `version` - версия **чарта** (SemVer), `appVersion` - версия **приложения**.
  Они независимы: правка только шаблонов двигает `version`, новый образ портала -
  `appVersion`. У чартов без отдельного приложения (`namespace`, `policies`)
  `appVersion` может отсутствовать.
- `icon` (опц.) - data URI с PNG, показывается в каталоге портала
  (см. `ingress-gateway`).
- `dependencies` - только для составных чартов. Пример - `console` подключает
  `ingress-gateway` сабчартом по `condition` (`ingressGateway.enabled`) с alias.
  Для сабчартов схема корня должна допускать `global` и `enabled` (см. раздел про
  `values.schema.json`).

---

## Конвенция именования ресурсов

Имя каждого создаваемого ресурса строится по 5-частной схеме:

```
{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}
```

| Часть         | Откуда                  | Ограничения                            |
|---------------|-------------------------|----------------------------------------|
| `instanceTag` | `naming.instanceTag`    | DNS-формат lower-case, required        |
| `clusterTag`  | `naming.clusterTag`     | DNS-формат lower-case, required        |
| `kindShort`   | тип ресурса (реестр ниже) | из реестра kindShort                 |
| `projectTag`  | `naming.projectTag`     | 2..6 символов, DNS, required           |
| `name`        | поле `name` элемента    | 2..6 символов, DNS, required           |

`instanceTag`/`clusterTag` валидируются хелпером `tag`, `projectTag`/`name` -
хелпером `shortToken` (см. `_helpers.tpl`). Итоговое имя обрезается до 63 символов
(`trunc 63 | trimSuffix "-"`). Пример: `ru1-k8s1-igw-nbox-main`.

### Расширенная форма с родителем

Когда дочерний ресурс привязан к родительскому (например, `TLSRoute` к своему
`Gateway` в `egress-gateway`), в имя добавляется тег родителя:

```
{instanceTag}-{clusterTag}-{kindShort}-{parentName}-{projectTag}-{name}
```

Пример: `ru1-k8s1-egw-wp-nbox-rnx`.

### Реестр kindShort

`kindShort` подставляется шаблоном по типу ресурса. Сводный реестр по всем чартам:

| kindShort | Kind                     | Чарт(ы)                    |
|-----------|--------------------------|----------------------------|
| `igw`     | `Gateway` (ingress)      | ingress-gateway            |
| `egw`     | `Gateway` egress (+ его `ConfigMap`/`ServiceEntry`/`TLSRoute`) | egress-gateway |
| `wp`      | `Gateway` (istio-waypoint) | waypoint                 |
| `veg`     | `VpcEgressGateway`       | egress-gateway             |
| `cm`      | `ConfigMap`              | ingress-gateway            |
| `np`      | `NetworkPolicy`          | ingress-gateway, policies  |
| `ap`      | `AuthorizationPolicy`    | ingress-gateway, policies  |
| `hr`      | `HTTPRoute`              | ingress-gateway            |
| `gr`      | `GRPCRoute`              | ingress-gateway            |
| `tr`      | `TLSRoute`               | ingress-gateway            |
| `tcr`     | `TCPRoute`               | ingress-gateway            |
| `ur`      | `UDPRoute`               | ingress-gateway            |
| `secret`  | `Secret` (TLS)           | ingress-gateway            |

Правила реестра:

- **Код уникален на Kind, но привязка к Kind - в пределах чарта.** Один чарт сам
  решает, какие из своих ресурсов как кодирует. Так, в `ingress-gateway` у
  `ConfigMap` свой код `cm`, а в `egress-gateway` `ConfigMap`/`ServiceEntry`/
  `TLSRoute` наследуют код `egw` своего Gateway (один логический объект - egress).
- **Новый Kind - новый код в реестр.** Заводя ресурс нового типа, добавь короткий
  код сюда и провалидируй его в хелпере `fullname`/`resourceName` своего чарта
  (список разрешённых kindShort там захардкожен и падает на неизвестном).
- **Уникальность имени** обеспечивается парой `(namespace, kind)` - `name` элемента
  обязан быть уникален в этих рамках.

> Ресурсы вне 5-частной схемы (OIDC в `ingress-gateway`, RBAC, и т.п.) носят
> пользовательские имена. Это допустимо, но должно быть явно отмечено в README
> чарта.

---

## `_helpers.tpl`

Вся общая логика (имена, labels, валидации) живёт в `_helpers.tpl`. Тела манифестов
в `templates/*.yaml` остаются тонкими: вызывают хелперы, не дублируют логику.

**Префикс хелперов** - `<chart>.helpers.*` (например `egress-gateway.helpers.app.labels`).
Так имена не конфликтуют при использовании чарта сабчартом. Комментарии к
`define` - короткий header-блок на английском.

Стандартный набор (есть в `ingress-gateway`/`egress-gateway`/`waypoint`):

| Хелпер                          | Назначение                                                        |
|---------------------------------|-------------------------------------------------------------------|
| `*.app.chart`                   | значение label `helm.sh/chart` (`{name}-{version}`)               |
| `*.app.name`                    | базовое имя приложения (= `projectTag`) для labels                |
| `*.tag`                         | валидация DNS-тега (`instanceTag`/`clusterTag`), возврат lower-case |
| `*.shortToken`                  | валидация 2..6-символьного DNS-тега (`projectTag`/`name`)         |
| `*.app.fullname` / `*.app.resourceName` | сборка имени ресурса по 5-частной схеме                  |
| `*.app.selectorLabels`          | стабильные selector labels                                        |
| `*.app.labels`                  | selector + chart/managed-by/version + `generic.labels`           |
| `*.app.genericAnnotations`      | `generic.annotations` (пусто -> ничего не выводит)               |
| `*.app.enabled`                 | резолв флага `enabled` (явный `false` уважается, default `true`)  |
| `*.tplvalues.render`            | универсальный рендеринг шаблонных значений (`tpl`)                |

### Валидация во время рендера

Невалидный ввод обязан ронять `helm template` с понятным сообщением, а не молча
рендерить кривой манифест. Канон - в `tag`/`shortToken`:

```gotemplate
{{- $value := required (printf "%s is required" .label) .value | toString | lower -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $value) -}}
{{- fail (printf "%s must be DNS-like lowercase, got %q" .label $value) -}}
{{- end -}}
```

Используй `required` для обязательных полей и `fail` для нарушенных инвариантов
(длина, формат, неизвестный enum/kindShort). Все условия падения перечисли в
разделе «Валидации» README.

### Стандартные labels

Selector labels (стабильны, не меняются между релизами):

```yaml
app.kubernetes.io/name: {{ include "<chart>.helpers.app.name" . }}   # = projectTag
app.kubernetes.io/instance: {{ .Release.Name }}
app: {{ include "<chart>.helpers.app.name" . }}
```

Полный набор labels = selector + `helm.sh/chart` + `app.kubernetes.io/managed-by`
(`.Release.Service`) + `app.kubernetes.io/version` (если задан `appVersion`) +
пользовательские `generic.labels`.

---

## Общие параметры управляемых сервисов

Эти параметры одинаковы во всех стандартных чартах - заводи их в новом чарте с
теми же именами и семантикой.

### `naming` (required)

```yaml
naming:
  instanceTag: ru1     # тег инстанса (таблица 50), required, DNS lower-case
  clusterTag: k8s1     # тег кластера (таблица 52), required, DNS lower-case
  projectTag: nbox     # тег проекта, required, 2..6 символов, DNS
```

Задаётся один раз на релиз, участвует в имени каждого ресурса.

### `generic` (опц.)

```yaml
generic:
  labels: {}           # общие labels на ВСЕ ресурсы чарта
  annotations: {}       # общие annotations на ВСЕ ресурсы чарта
```

Labels/annotations задаются **только глобально** через `generic.*`. Per-resource
labels/annotations намеренно не поддерживаются (унификация). В форме портала
`generic` обычно скрыт (`ui:widget: hidden`).

### Списки сущностей и `enabled`

Ресурсы описываются списками однотипных элементов (`gateways[]`, `xroutes[]`,
`waypoints[]`, `policies[]`, ...). Каждый элемент:

- имеет `name` (2..6 символов, DNS) - подставляется в `{name}` имени ресурса;
- имеет `enabled` (default `true`); `false` -> элемент целиком пропускается.
  Резолв - через хелпер `*.app.enabled`, чтобы явный `false` не терялся за
  `| default true`.

### `defaults` (опц.)

Для значений по умолчанию, общих для секции (см. `policies`: `trustDomain`,
`namespaceLabelKey`, `protocol`). Переопределяются per-element там, где это
осмысленно.

---

## `values.schema.json`

Схема - источник правды для валидации значений на стороне портала и для генерации
формы заказа. Держи её **в синхроне с параметрами чарта** (полный набор -
в `values.full.yaml`): новый/удалённый/переименованный ключ правится синхронно
со схемой в одном изменении. Дефолтный `values.yaml` тоже обязан валидироваться
по схеме.

Каркас:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://example.com/<chart>/values.schema.json",
  "title": "<Chart> Helm chart values",
  "description": "<editor-oriented описание>",
  "type": "object",
  "additionalProperties": false,
  "propertyOrder": ["naming", "generic", "..."],
  "required": ["naming"],
  "properties": { "...": { "$ref": "#/definitions/..." } },
  "definitions": { "...": {} }
}
```

Правила:

- **`draft-07`**, `additionalProperties: false` на корне и во вложенных объектах -
  чтобы опечатки в ключах ловились схемой.
- **Переиспользуй `definitions` + `$ref`**, не дублируй структуры инлайн.
- **`propertyOrder`** задаёт порядок полей в форме портала; держи `naming` первым.
- **`required`** - как минимум `naming`. Внутри - обязательные поля элементов.
- **`title`/`description`** - человекочитаемые, описания на русском (их видит
  пользователь в форме).
- **`ui:widget: "hidden"`** - скрыть поле из формы, оставив в схеме: для
  служебных (`generic`, `global`, `enabled`) и для тех, что чарт выводит сам
  (см. в `ingress-gateway`: `xroutes[].enabled`/`hostnames`/`parentRefs[].gateway`).
- **`defaultSnippets`** - готовые заготовки элементов списка для редактора
  (label + body). Удобны для `gateways[]`/`xroutes[]` и т.п.
- **`shortToken`-поля** (`projectTag`, `name`) ограничивай в схеме по длине/паттерну
  под ту же 2..6 DNS-валидацию, что и в шаблоне, - чтобы форма не давала отправить
  заведомо невалидное.
- **Совместимость с сабчартом**: если чарт может подключаться сабчартом, добавь в
  корень опциональные `global` (Helm инжектит его в любой сабчарт) и `enabled`
  (флаг `condition` родителя), оба `ui:widget: hidden`, не используются шаблонами.
  `additionalProperties: false` при этом сохраняется.

---

## Файлы значений

Три файла с разной ролью:

- **`values.yaml`** (обязателен) - минимальные дефолты, достаточные лишь для того,
  чтобы `helm template`/деплой проходил без ошибок. Он не обязан описывать
  осмысленный деплой - задача только в валидном рендере. Файл **всегда** лежит в
  корне и не может отсутствовать: Helm ожидает дефолтный `values.yaml`, в том числе
  при подключении чарта сабчартом (на этом уже спотыкался `ingress-gateway`).
- **`values.minimal.yaml`** (желательно) - базовое наполнение, дающее реально
  рабочий вариант чарта: минимальный набор, который можно задеплоить как стартовую
  точку.
- **`values.full.yaml`** (обязателен) - полный reference: все возможные параметры
  чарта с комментариями и описанием (на русском). Это документация значений.

Дефолты `values.yaml` должны давать валидный рендер либо явно падать с понятным
сообщением через `required`/`fail`, а не молчаливо ломаться. Полный список
параметров держи в `values.full.yaml`, не подменяя им `values.yaml`.

---

## README.md

Документ для **пользователя** - обычного человека, который хочет развернуть сервис,
а не для разработчика чарта. Пиши простым языком и по делу: что это, что получится
после установки, как развернуть, какие поля заполнить. Избегай тяжёлых технических
описаний и внутренней механики - глубокий reference (все параметры, логика рендера)
живёт в `values.full.yaml` и `values.schema.json`, а не здесь. Цель README - чтобы
человек без контекста смог заказать/развернуть сервис.

Структура (см. `ingress-gateway`, `egress-gateway`, `waypoint`):

1. **Заголовок и одно-два предложения** - что чарт разворачивает.
2. **Таблица секций** - `Секция | Что генерирует | Когда использовать`. Сразу
   после неё - как секции связаны между собой (по `name`/`hostname`/`parentRefs`).
3. **Конвенция именования** - 5-частная схема, таблица частей, какие kindShort
   использует чарт, примеры имён, явная пометка про ресурсы вне схемы.
4. **Quick start** - `helm template`/`install` с `values.minimal.yaml` и что он
   создаёт.
5. **Секции параметров** - подразделы на каждую секцию с таблицами полей
   (`Поле | Обязательно | Описание`), начиная с «Общие параметры» (`naming`,
   `generic`).
6. **Валидации** - список условий, при которых рендер падает (зеркало `fail`/
   `required` в шаблонах).
7. **Запуск** - `helm lint`/`template`/`install`; ссылка на `values.full.yaml` как
   полный reference и на `values.minimal.yaml` как рабочий пример.

---

## CHANGELOG.md

Каждое изменение чарта - запись в его `CHANGELOG.md` и bump `version` в
`Chart.yaml`. Шапка фиксированная (см. любой существующий `CHANGELOG.md`):

```markdown
# Changelog

Все заметные изменения чарта `<chart>` фиксируются в этом файле.

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
```

Записи версий - сверху вниз от новой к старой:

```markdown
## [3.2.5] - 2026-06-23

### Added
- Короткое и конкретное описание изменения и зачем оно.
```

- Формат заголовка записи: `## [версия] - YYYY-MM-DD` (дефис, не длинное тире).
- Группируй пункты по категориям выше. Для крупного релиза можно дать абзац-резюме
  под заголовком версии, затем категории.
- BREAKING-изменения (MAJOR) помечай явно и описывай, что поправить в `values.yaml`.

---

## NOTES.txt

Пост-установочная сводка (печатается после `helm install`/`upgrade`). Что в ней:

- первая строка - что и куда развёрнуто (`<chart> ({{ .Chart.Version }})` в
  namespace `{{ .Release.Namespace }}`) и напоминание про конвенцию имён;
- перечень фактически созданных ресурсов (с учётом `enabled`) с их итоговыми
  именами - для проверки и для дальнейших действий;
- при необходимости - краткая текстовая подсказка по следующему шагу (например,
  как привязать namespace к waypoint).

**В `NOTES.txt` не пишем shell/`kubectl`-команды.** Никаких блоков вида
`Check:\n  kubectl ...` или примеров `helm`/`kubectl`. Только текстовая сводка:
что развёрнуто, перечень созданных ресурсов с именами и при необходимости
короткая словесная подсказка по следующему шагу.

Текст здесь виден пользователю - он может быть на русском.

---

## Проверка перед коммитом

Обязательна локально (lefthook на push - бэкстоп, не замена):

```sh
helm lint <chart>
helm template release <chart>                                # дефолтный values.yaml
helm template release <chart> -f <chart>/values.minimal.yaml
helm template release <chart> -f <chart>/values.full.yaml
```

Рендер обязан проходить чисто и валидироваться по `values.schema.json`. Упакованные
чарты (`*.tgz`), вендоринг `charts/` и `Chart.lock` - не коммить (они в
`.gitignore`).

---

## Исключения

Два чарта не следуют стандарту целиком - не копируй их как образец:

- **`console`** - деплой-артефакт портала. Компонентный нейминг
  (`{release}-portal`, `{release}-collector`) вместо 5-частной схемы; хелперы
  `console.*`; есть `Deployment`/`Service`/`ServiceAccount`/RBAC.
  `values.schema.json` пока отсутствует. Связь его env-ключей с `config.go`/
  `.env.example` основного репозитория описана в `CLAUDE.md`.
- **`namespace`/`managed-namespace`** - cpaas-нейминг (labels `cpaas.io/*`,
  `app.cpaas.io/name`; хелперы `managed-ns.*`), нет `naming`-блока, `NOTES.txt`,
  README и `.helmignore`. Чарт в процессе доработки (RBAC, Istio-лейблы,
  deny-default NetworkPolicy, параметризация `creator`) - см. `idp/TODO.md`.

Кроме того, в `policies` префикс хелперов - `security-policies.*` (исторически),
а не `policies.helpers.*`. Для новых чартов используй `<chart>.helpers.*`.
