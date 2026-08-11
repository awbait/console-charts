# Changelog

Все заметные изменения чарта `namespace` (раньше `managed-namespace`)
фиксируются в этом файле.

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

## [3.0.0] - 2026-08-11

### Changed
- **Чарт переименован из `managed-namespace` в `namespace`** - как называется
  его директория и как он называется в каталоге портала. Ресурсы, значения и
  поведение не изменились, но имя чарта попадает в label `app` (был
  `app: managed-namespace`, стал `app: namespace`) и в `helm.sh/chart`.

  **BREAKING**: чарт публикуется и подключается под новым именем, а выборки
  ресурсов по прежнему значению label `app` нужно поправить.
- Префикс шаблонов-хелперов приведён к имени чарта: `managed-ns.*` ->
  `namespace.helpers.*`. На рендер не влияет.

---

## [2.0.0] - 2026-08-11

### Added
- **Блок `identity` (`instance`/`cluster`/`project`)** - теги окружения и
  проекта. В имена ресурсов они не входят (их формат задаёт платформа), но
  проставляются на все ресурсы чарта как labels `ecpk/instance`,
  `ecpk/cluster`, `ecpk/project`. Теги окружений заданы в схеме перечислением,
  в форме портала это выбор из списка.

  **BREAKING**: блок обязателен, в существующие values его нужно добавить.
- **Label `app` с именем чарта** (`app: managed-namespace`) на всех ресурсах -
  по нему находятся ресурсы чарта независимо от имени релиза.

### Changed
- **Комментарии в файлах значений переведены на русский.**
- **`README.md` переписан** по общей структуре: что создаёт чарт, теги
  окружения, labels, разбор секций и список проверок, на которых рендер
  останавливается. Команды из документа убраны.
- **`NOTES.txt`** печатает теги identity, проставленные на ресурсы.

---

## [1.4.0] - 2026-07-09

### Added
- **Блок `generic` (`labels`/`annotations`)** - общие labels и annotations на все
  ресурсы чарта (`Namespace`, `ResourceQuota`, `Subnet`). Собираются единым
  хелпером `managed-ns.metadata` (`labels:` + условный `annotations:`);
  `generic.labels` дополнительно вливаются в `managed-ns.labels`. Добавлены в
  `values.full.yaml` и `values.schema.json` (в форме портала секция скрыта).

### Changed
- `ResourceQuota` и `Subnet` теперь тоже несут стандартные labels чарта
  (`managed-ns.labels`) и `generic.*` - раньше у них не было ни labels, ни
  annotations.

---

## [1.3.1] - 2026-06-25

### Changed
- Комментарии в `values.yaml`/`values.full.yaml`/`values.minimal.yaml`, `values.schema.json` и `NOTES.txt` переведены на английский (в исходниках чарта - без кириллицы).

## [1.3.0] - 2026-06-24

### Added
- **`namespace.role`** - роль namespace со списком значений `ingress` / `egress`
  / `other` (ограничено в схеме). При выборе на Namespace ставится лейбл
  `namespace-role`. Поле опционально: без значения лейбл не ставится.

### Changed
- Дефолт `namespace.displayName` сменён с `Managed by ECPK` на `Managed namespace`
  (убрано вендорное упоминание).

---

## [1.2.0] - 2026-06-24

### Added
- **`serviceMesh.enabled`** (default `false`) - при включении на Namespace
  проставляются Istio-лейблы `istio-discovery: enabled` и
  `istio.io/dataplane-mode: ambient`, а также аннотация
  `networking.k8s.io/enable-netpol: "true"`. Включается на уровне контура
  (скрыто в форме портала). По умолчанию поведение не меняется.

---

## [1.1.0] - 2026-06-24

### Added
- **`namespace.creator`** - annotation `cpaas.io/creator` вынесена в значение
  (default `lk`), раньше была захардкожена в `templates/namespace.yaml`. Поле
  скрыто в форме портала (`ui:widget: hidden`); при заказе из консоли
  подставляется `console`. Поведение по умолчанию не меняется.

---

## [1.0.0] - 2026-06-24

Первый релиз чарта, приведённый к общему стандарту репозитория.

### Added
- **Namespace** - создаётся managed-namespace (cpaas/Alauda) с labels/annotations
  (`cpaas.io/*`, `app.cpaas.io/name`), отображаемым именем и пользовательскими
  `annotations`/`labels`.
- **ResourceQuota** - лимиты и запросы CPU/памяти, число подов и квоты на блочные
  хранилища по StorageClass.
- **Subnet (kube-ovn)** - опциональная выделенная подсеть: IP шлюза вычисляется из
  `cidrBlock`, подсеть изолированная (private), привязана к одному Namespace.
- **`values.schema.json`** - валидация значений и форма заказа в портале.
- **Документация и стандартные файлы** - `README.md`, `CHANGELOG.md`,
  `templates/NOTES.txt`, `.helmignore`; раскладка значений
  `values.yaml`/`values.minimal.yaml`/`values.full.yaml`.

### Changed
- Человекочитаемые пояснения вынесены из `templates/subnet.yaml` (где они
  протекали в отрендеренные манифесты) в `values.full.yaml` и `README.md`.
