# Changelog

Все заметные изменения чарта `policies` фиксируются в этом файле.

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

## [Unreleased]

### Added
- **`README.md`** - usage-документ чарта: секции (`policies[]`/`netpol[]`/
  `authzpol[]`), конвенция именования, таблицы полей, валидации, запуск.
- **Блок `generic` (`labels`/`annotations`)** - общие labels и annotations на все
  генерируемые `NetworkPolicy`/`AuthorizationPolicy`. Собираются единым хелпером
  `security-policies.metadata` (`labels:` + условный `annotations:`); `generic.labels`
  дополнительно вливаются в `security-policies.labels`. Добавлены в `values.full.yaml`
  и `values.schema.json` (в форме портала секция скрыта).

### Changed
- **Namespace владельца - всегда `.Release.Namespace`.** Поля `namespace` у
  `policies[]`, `netpol[]`, `authzpol[]` убраны: owner-ресурсы создаются в
  namespace релиза, поэтому чарт нужно ставить в namespace целевого workload.
  Namespace в `ingress.from[]` / `egress.to[]` (peer'ы и зеркала egress)
  сохранены - это другие namespace.
- **`portEntry` в схеме упрощён.** Убран `oneOf` (число | объект); оставлена
  объектная форма с раздельными полями `port` (обязательное) и `protocol`
  (опционально, fallback на `defaults.protocol`), как `networkPolicyPort` в
  `ingress-gateway`. Скалярная форма `ports: [8080]` больше не валидна по схеме.
- **Конвенция именования ресурсов** - имя строится как
  `{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}` (было `{name}-{np|ap}`).
  Общие теги - в новом блоке `naming` (`instanceTag`/`clusterTag`/`projectTag`),
  `kindShort` по типу ресурса (`np`/`ap`), `name` - это `policy.name` (2..6).
  Все части валидируются (DNS-формат, длины, `kindShort ∈ {np,ap}`).

  **BREAKING**: имена всех генерируемых `NetworkPolicy`/`AuthorizationPolicy`
  меняются; требуется заполнить секцию `naming` в `values.yaml`.
- Файлы значений приведены к стандарту: `values.yaml` (минимальный дефолт,
  пустые секции) + `values.full.yaml` (полный reference) + `values.minimal.yaml`
  (рабочий пример). Прежний `minimal-values.yaml` переименован в
  `values.minimal.yaml`; полный reference вынесен из `values.yaml` в
  `values.full.yaml`.
- Комментарии в `_helpers.tpl`, `values.*`, `values.schema.json` и описание
  в `Chart.yaml` переведены на английский; длинные тире заменены на дефисы.

---

## [0.1.0] - 2026-05-28

Первый релиз чарта.

### Added
- **Универсальные политики (`policies[]`)** - одно описание задаёт связь между
  сервисами. Из одной записи генерируются `NetworkPolicy` и `AuthorizationPolicy`
  как у источника, так и у получателя egress трафика. Несколько egress правил
  с одним получателем автоматически объединяются.
- **Только `NetworkPolicy` (`netpol[]`)** - для случаев, когда нужен только
  сетевой уровень. Поддерживаются peer'ы по namespace + label, по ipBlock
  (включая исключения), а также ingress и egress правила.
- **Только `AuthorizationPolicy` (`authzpol[]`)** - для L7-сценариев Istio:
  правила по ServiceAccount, principal, namespace, ipBlock, ограничение по
  `sourceNamespaces`.
- **Защита от ошибок в описании политик**: чарт не позволит выкатить правило,
  которое случайно разрешит трафик откуда угодно, и подскажет, какое поле
  заполнено некорректно.
- **Reference `values.yaml`** со всеми доступными параметрами и комментариями.
- **`minimal-values.yaml`** - минимальная рабочая конфигурация для быстрого
  старта.
