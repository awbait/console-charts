# Changelog

Все заметные изменения чарта `waypoint` фиксируются в этом файле.

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

## [2.0.1] - 2026-08-12

### Changed
- Описание чарта переписано для человека, который выбирает сервис в каталоге портала.

## [2.0.0] - 2026-08-11

### Added
- **Labels `ecpk/instance`, `ecpk/cluster`, `ecpk/project`** на всех ресурсах
  чарта. Значения берутся из блока `identity` (label выводится только для
  заполненного поля) и приводятся к нижнему регистру, то есть совпадают с тем,
  что попало в имя ресурса.
- **Список допустимых значений `identity.instance` и `identity.cluster` в
  `values.schema.json`**: теги окружений заданы перечислением, в форме портала
  поле стало выбором из списка вместо свободного ввода.

### Changed
- **Блок `naming` переименован в `identity`**: `naming.instanceTag` ->
  `identity.instance`, `naming.clusterTag` -> `identity.cluster`,
  `naming.projectTag` -> `identity.project`. Смысл полей не изменился.

  **BREAKING**: секцию `naming` в своих values нужно переименовать, иначе
  рендер упадёт на отсутствующих обязательных полях.
- **`identity.project` - до 9 символов** (было 2..6): строчные латинские буквы,
  цифры и дефис. Имена waypoint'ов остались 2..6 символов.
- **Label `app` теперь содержит имя чарта** (`waypoint`), а не тег проекта. Тег
  проекта остался в `app.kubernetes.io/name`, имя релиза - в
  `app.kubernetes.io/instance`.

  **BREAKING**: если по label `app` настроены внешние выборки ресурсов, их
  нужно поправить.
- **Комментарии в файлах значений переведены на русский** и приведены в
  соответствие с текущей конвенцией имён.
- **`README.md` переписан** по общей структуре: что создаёт чарт, куда ставится
  релиз, таблица тегов окружений, labels, разбор секции и список проверок, на
  которых рендер останавливается. Команды из документа убраны.
- **`NOTES.txt`**: вместо команды `kubectl` печатаются теги identity, имя метки
  для привязки namespace и labels релиза. Добавлена строка для случая, когда
  список waypoint'ов пуст.

---

## [1.0.2] - 2026-07-09

### Changed
- Labels и annotations всех ресурсов теперь собираются одним хелпером `waypoint.helpers.app.metadata` (`labels:` + условный `annotations:` из `generic.*`). Раньше каждый манифест повторял этот блок вручную, из-за чего аннотации легко было забыть на новом ресурсе. Поведение не меняется (значение `istio.io/waypoint-for` теперь выводится без кавычек - тот же YAML-скаляр).

---

## [1.0.1] - 2026-06-25

### Changed
- Файлы значений приведены к стандарту: `values.yaml` (минимальный дефолт, пустые секции) + `values.full.yaml` (полный reference) + `values.minimal.yaml` (рабочий пример). Прежний `minimal-values.yaml` переименован в `values.minimal.yaml`; полный reference вынесен из `values.yaml` в `values.full.yaml`.
- Комментарии в шаблонах, `values.*`, `values.schema.json` и `NOTES.txt` переведены на английский; длинные тире заменены на дефисы.

## [1.0.0] - 2026-06-01

Приведение чарта к единому стандарту (как `egress-gateway`/`ingress-gateway`/
`policies`). **BREAKING**: изменены конвенция именования и структура `values.yaml`.

### Added
- **Конвенция именования** - имя ресурса строится как
  `{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}`. Общие теги - в
  блоке `naming` (`instanceTag`/`clusterTag`/`projectTag`), `kindShort` = `wp`,
  `name` - на каждый waypoint (2..6 символов). Все части валидируются.
- **`waypoints[]`** - список waypoint'ов (раньше - единственный `waypoint`).
  На каждый элемент создаётся `Gateway` класса `istio-waypoint`; поле `for`
  (`service`/`workload`/`all`) валидируется.
- **`values.schema.json`** - editor-oriented схема (как у остальных чартов).
- **`NOTES.txt`**, **`README.md`**, **`CHANGELOG.md`**, **`.helmignore`**,
  **`minimal-values.yaml`**.

### Changed
- **Хелперы** - `templates/helpers.tpl` → `templates/_helpers.tpl` с префиксом
  `waypoint.helpers.*` и стандартным набором (`tag`/`shortToken`/`resourceName`/
  `labels`/`genericAnnotations`/`enabled`/`for`/`tplvalues.render`).
- **Имя чарта** - добавлен `appVersion`; версия → 1.0.0.
- **Комментарии в шаблоне** - добавлен header-блок в стиле остальных чартов.

### Removed
- **`nameOverride`/`fullnameOverride`** и legacy-хелперы имени - теги теперь
  обязательны, имя строится по конвенции.
- **Per-resource и top-level labels/annotations** (`labels`/`annotations`,
  `waypoint.labels`/`waypoint.annotations`) - используйте `generic.*`.

### Fixed
- **`enabled: false` учитывается корректно** - через helper
  `waypoint.helpers.app.enabled` (без `| default true`-footgun).

---

## [0.1.0] - 2026-05-28

Первый релиз чарта.

### Added
- **Waypoint Gateway** - `Gateway` класса `istio-waypoint` (HBONE/15008) с
  `istio.io/waypoint-for` (`service`/`workload`/`all`).
