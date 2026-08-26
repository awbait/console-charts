# Changelog

Все заметные изменения чарта `egress-gateway` фиксируются в этом файле.

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

## [3.0.3] - 2026-08-26

### Changed
- **Варианты списков в форме заказа подписаны словами.** «Кластер» предлагает
  «techsec-dev (tco)», а не «tco», «Инстанс» называет окружения, которые за ним
  стоят. Расшифровка кодов ушла из описания под полем в сами варианты.

## [3.0.2] - 2026-08-24

### Changed
- **Поля в форме заказа подписаны по-человечески.** Раньше подписью служило имя
  ключа: `name`, `hostname`, `protocol`. Теперь это «Имя точки», «Домен внешнего
  сервиса», «Протокол», а под полем сказано, зачем оно нужно.
- **Список listener'ов называется «Точки выхода».** Каждая точка - это один
  внешний сервис, к которому нужен доступ, и теперь так и написано.
- **Из описаний полей убраны требования к значению.** Допустимые символы и длину
  портал берёт из схемы и показывает сам по значку в конце поля.

### Removed
- **Поле `enabled` убрано из формы заказа** у гейтвея и у выхода с известного
  адреса. В `values.yaml` оно работает как раньше.
- **Определение `k8sName` из `values.schema.json`.** На него не ссылалось ни одно
  поле.

### Fixed
- **`values.full.yaml` описывает все параметры чарта.** Служебные `exportTo`,
  `location`, `resolution` и `enabled` в нём упоминались в комментариях, но
  примера значения не было.

## [3.0.1] - 2026-08-12

### Changed
- Описание чарта переписано для человека, который выбирает сервис в каталоге портала.

## [3.0.0] - 2026-08-11

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
  цифры и дефис. Имена шлюза, listener'ов и `VpcEgressGateway` остались 2..6.
- **Label `app` теперь содержит имя чарта** (`egress-gateway`), а не тег
  проекта. Тег проекта остался в `app.kubernetes.io/name`, имя релиза - в
  `app.kubernetes.io/instance`.

  **BREAKING**: если по label `app` настроены внешние выборки ресурсов, их
  нужно поправить.
- **`README.md` переписан** по общей структуре: что создаёт чарт, куда ставится
  релиз, таблица тегов окружений, labels, разбор секций и список проверок, на
  которых рендер останавливается. Команды из документа убраны.
- **`NOTES.txt`** печатает теги identity и labels, по которым находятся ресурсы
  релиза.

---

## [2.0.1] - 2026-07-09

### Changed
- Labels и annotations всех ресурсов теперь собираются одним хелпером `egress-gateway.helpers.app.metadata` (`labels:` + условный `annotations:` из `generic.*`). Раньше каждый манифест повторял этот блок вручную. Ресурс-специфичные аннотации `Gateway` (`networking.istio.io/service-type`, `istio.io/waypoint-for`) передаются в хелпер параметром.

### Fixed
- `VpcEgressGateway` теперь тоже получает `generic.annotations` - раньше на нём выводились только labels.

---

## [2.0.0] - 2026-06-25

BREAKING: структура `values.yaml` изменена. `egressGateway` теперь один объект
(а не список), секция `tlsRoutes` удалена (маршруты генерируются автоматически),
из listener убран `tlsMode`, из `vpcEgressGateway` убраны `selectors` и `replicas`.
Старый `values.yaml` придётся переписать.

### Changed
- **Один Gateway на релиз.** `egressGateway` из списка превращён в одиночный
  объект (`name` / `enabled` / `listeners[]`). В одном Gateway допускается
  больше одного listener.
- **Протокол listener - `TLS` или `HTTPS`** (по умолчанию `TLS`); валидируется.
  `tls.mode` всегда `Passthrough` и больше не настраивается (поле `tlsMode`
  удалено из values и схемы).
- **`vpcEgressGateway`** больше не принимает `selectors` и `replicas`: число
  реплик равно числу `externalIPs`, а `namespaceSelector`/`podSelector`
  подставляются шаблоном и указывают на под'ы созданного egress Gateway
  (label `gateway.networking.k8s.io/gateway-name`).
- Комментарии в `values.yaml` / `values.minimal.yaml` / `values.full.yaml`
  возвращены на русский (по `charts/CONVENTIONS.md`); в 1.0.1 они были на
  английском. Комментарии в `templates/` остаются на английском.

### Added
- **Маршруты генерируются автоматически - один на listener.** Kind берётся из
  протокола listener (`TLS` -> `TLSRoute`, `HTTPS` -> `HTTPRoute`), имя - из
  имени listener по конвенции с родителем
  (`{instanceTag}-{clusterTag}-egw-{gatewayName}-{projectTag}-{listenerName}`),
  `hostnames` - из hostname listener, единственный `backendRef` -
  `{name: hostname, port: listener.port, weight: 100}`. Route привязан к своему
  listener через `parentRefs[].sectionName`.

### Removed
- Секция `tlsRoutes[]` и её поля в `values.schema.json` - маршруты теперь
  выводятся из listener'ов, задавать их вручную не нужно.

### Fixed
- `apiVersion` маршрутов приведён к Kind: `TLSRoute` -
  `gateway.networking.k8s.io/v1alpha2`, `HTTPRoute` - `.../v1` (раньше TLSRoute
  ошибочно рендерился как `v1`).

## [1.0.1] - 2026-06-25

### Changed
- Файлы значений приведены к стандарту: `values.yaml` (минимальный дефолт, пустые секции) + `values.full.yaml` (полный reference) + `values.minimal.yaml` (рабочий пример). Прежний `minimal-values.yaml` переименован в `values.minimal.yaml`; полный reference вынесен из `values.yaml` в `values.full.yaml`.
- Комментарии в шаблонах, `values.*`, `values.schema.json` и `NOTES.txt` переведены на английский; длинные тире заменены на дефисы.

## [1.0.0] - 2026-05-29

Первый релиз чарта.

### Added
- **Конвенция именования** - имя каждого ресурса строится как
  `{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}`. Общие теги -
  в `naming` (`instanceTag`/`clusterTag`/`projectTag`), `kindShort` по типу
  ресурса (`egw`/`veg`), `name` - на каждый ресурс (2..6 символов). Все части
  валидируются (DNS-формат, длины, `kindShort ∈ {igw,egw,veg}`).
- **Egress Gateway (`egressGateway[]`)** - список шлюзов. На каждый элемент -
  `Gateway` (Gateway API, TLS Passthrough) и `ConfigMap` для waypoint operator;
  ConfigMap носит то же имя, что и Gateway.
- **ServiceEntry из listener'ов** - `ServiceEntry` генерируется автоматически
  на каждый `egressGateway[].listeners[]` (hostname/port/addresses). Отдельная
  секция `serviceEntries` не нужна.
- **TLSRoute (`tlsRoutes[]`)** - список маршрутов; `parentRefs` генерируются
  по совпадению `hostnames` с listener'ами шлюзов (Gateway указывать не нужно).
  На каждый совпавший Gateway создаётся отдельный TLSRoute. Имя - по расширенной
  конвенции с `parentGatewayName`:
  `{instanceTag}-{clusterTag}-egw-{parentGatewayName}-{projectTag}-{name}`.
- **VpcEgressGateway (`vpcEgressGateway[]`)** - ресурс kube-ovn: список шлюзов
  с externalIPs, node/namespace/pod селекторами и SNAT-политиками. `replicas`
  по умолчанию равно числу `externalIPs`.
- **Общие labels/annotations** - только глобально через `generic.*` (без
  per-resource).
- **Справочник `values.full.yaml`** со всеми параметрами и комментариями,
  **`values.minimal.yaml`** - минимальная рабочая конфигурация, и
  **`values.yaml`** - дефолт (пустые секции, ничего не создаёт).
