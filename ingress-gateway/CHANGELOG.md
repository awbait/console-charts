# Changelog

Все заметные изменения чарта `ingress-gateway` фиксируются в этом файле.

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

## [5.1.1] - 2026-08-26

### Changed
- **Варианты списков в форме заказа подписаны словами.** «Кластер» предлагает
  «techsec-dev (tco)», а не «tco», «Тип трафика» - «HTTP (HTTPRoute)», «Что
  делать с TLS» - «Расшифровывать на гейтвее (Terminate)». Расшифровка кодов
  ушла из описаний под полями в сами варианты.

## [5.1.0] - 2026-08-26

### Added
- **Чарт сам говорит порталу, как выглядит его заказ.** Заказ теперь просит один
  гейтвей и его слушателей, а маршруты добавляются потом, в карточке готового
  сервиса: там есть вкладки «Слушатели» и «Маршруты» и кнопки «Редактировать
  ресурсы», «Редактировать HPA» и «Редактировать IP». Раньше форма строилась по
  одной схеме значений и показывала всё сразу, включая служебные поля.
- **Маршруту не нужно повторять домен.** В карточке он выбирает слушателя, а
  hostname и ссылку на гейтвей чарт подставляет сам.

## [5.0.0] - 2026-08-25

### Added
- **Сертификат для своего домена берётся из Vault.** В разделе «Сертификаты»
  вы называете домен и путь к записи в Vault, а чарт создаёт `ExternalSecret`:
  External Secrets Operator кладёт сертификат в кластер и обновляет его сам.
  Домен любой: четвёртого и пятого уровня, и не только внутри `ecpk.test`.
  Сертификат и ключ в репозиторий заказа не попадают, в значениях едет
  только путь.
- **Одна запись сертификата на любое число точек входа.** Два listener'а на
  соседних доменах одного сертификата дают один секрет и один `ExternalSecret`.
- **У сертификата выбирается хранилище.** Сертификаты читаются через
  `SecretStore` вашего namespace. По умолчанию это `vault`, но в записи можно
  назвать другое хранилище того же namespace. Платформенные сертификаты
  называют своё хранилище сами и от выбора в заказе не зависят.

### Changed
- **Сертификат выбирается по домену, а не по совпадению подстроки.** Домен
  `*.str.idp.ecpk.test` раньше считался платформенным, потому что содержал
  `idp.ecpk.test`, и получал платформенный сертификат `*.idp.ecpk.test`,
  который его не покрывает: клиент видел чужой сертификат. Теперь звёздочка
  покрывает один уровень, ровно как в самом сертификате.
- **Домен без сертификата останавливает выкатку сразу.** Раньше чарт создавал
  пустой секрет, Gateway на него ссылался, и это выяснялось уже в кластере.
  Теперь рендер падает и называет домен, для которого нет записи.

### Removed
- **`tlsWildcards`.** Сертификат и ключ больше не передаются в значениях
  чарта: платформенные сертификаты лежат в Vault и описаны в `tls.platform`.
- **`tlsSecretName` у точки входа.** Поле принималось схемой, но ни один
  шаблон его не читал: имя секрета всегда собиралось само. Имя секрета
  собирается из `name` записи сертификата.

### Обновление с 4.x
- Заказ, где все домены платформенные, менять не нужно.
- Заказ со своим доменом дополняется записью в `tls.certificates`: `name`,
  `domain` и `path` в Vault.
- `tlsSecretName` из значений убрать, он больше не принимается схемой.
- В кластере должен стоять External Secrets Operator, а в namespace релиза -
  `SecretStore` из `tls.store` (по умолчанию с именем `vault`).

---

## [4.0.3] - 2026-08-24

### Fixed
- **Точка входа TCP или UDP больше не срывает выкатку из-за домена.** Домен,
  введённый в форме, уходил в Gateway при любом протоколе, и кластер отвечал
  `hostname must not be specified for protocols ['TCP', 'UDP']`. Теперь домен
  попадает в Gateway только для HTTP, HTTPS и TLS, а у TCP и UDP он просто не
  используется.

### Changed
- **У точки входа TCP или UDP в форме заказа больше нет поля «Домен».** Оно
  показывалось при любом протоколе, поэтому его заполняли и там, где домена не
  бывает. Теперь поле появляется только для HTTP, HTTPS и TLS, а для TCP и UDP
  портал его прячет.

---

## [4.0.2] - 2026-08-24

### Changed
- **Поля в форме заказа подписаны по-человечески.** Раньше подписью служило имя
  ключа: `name`, `hostname`, `tlsMode`, `backendRefs`. Теперь это «Имя гейтвея»,
  «Домен», «Что делать с TLS», «Сервисы назначения», а под полем сказано, зачем
  оно нужно.
- **Список listener'ов называется «Точки входа», список маршрутов - «Маршруты».**
  У маршрута выбирается «Тип трафика», а описание расшифровывает, какой тип для
  чего.
- **Из описаний полей убраны требования к значению.** Допустимые символы, длину
  и диапазон портал берёт из схемы и показывает сам по значку в конце поля.
- **Названия из Gateway API оставлены как есть.** `Path`, `Headers`, `CORS`,
  `URLRewrite` и остальные - это то, что вы найдёте в документации, переписаны
  только пояснения к ним.

### Removed
- **Определение `labelSelectorRequirement` из `values.schema.json`.** На него не
  ссылалось ни одно поле.

### Fixed
- **`values.full.yaml` описывает все параметры чарта.** Раньше в нём не было
  примеров для условий по заголовкам и параметрам адреса, для перенаправления,
  подмены адреса и CORS, для `certificateRefs` и для правила по диапазону
  адресов в `networkPolicy`.
- **Схема больше не обещает того, чего чарт не делает.** `allowedRoutes.namespaces`
  принимается, но шаблон всегда пишет `from: Same`: маршрут привязывается только
  из namespace гейтвея. Теперь так и написано в описании поля.

## [4.0.1] - 2026-08-12

### Changed
- Описание чарта переписано для человека, который выбирает сервис в каталоге портала.

## [4.0.0] - 2026-08-11

### Added
- **Labels `ecpk/instance`, `ecpk/cluster`, `ecpk/project`** на всех ресурсах
  чарта. Значения берутся из блока `identity` (label выводится только для
  заполненного поля) и приводятся к нижнему регистру, то есть совпадают с тем,
  что попало в имя ресурса. Так ресурсы отбираются по окружению и проекту без
  разбора имени.
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
  цифры и дефис. Имена Gateway и маршрутов остались 2..6 символов.
- **Label `app` теперь содержит имя чарта** (`ingress-gateway`), а не тег
  проекта. Тег проекта остался в `app.kubernetes.io/name`, имя релиза - в
  `app.kubernetes.io/instance`.

  **BREAKING**: если по label `app` настроены внешние выборки ресурсов, их
  нужно поправить.
- **Service шлюза создаётся как single-stack IPv4**: в патч Service добавлены
  `ipFamilies: [IPv4]` и `ipFamilyPolicy: SingleStack`, чтобы в кластерах с
  двойным стеком шлюзу не выдавался адрес IPv6.
- **Комментарии в `values.yaml`, `values.minimal.yaml` и `values.full.yaml`
  переведены на русский** и приведены в соответствие с текущей конвенцией имён.
- **`README.md` переписан** по общей структуре: что создаёт чарт, куда ставится
  релиз, таблица тегов окружений, labels, разбор секций и список проверок, на
  которых рендер останавливается. Команды из документа убраны.
- **`NOTES.txt`**: вместо команды `kubectl` печатаются теги identity и labels,
  по которым ресурсы релиза находятся в кластере.

---

## [3.3.2] - 2026-07-09

### Changed
- Labels и annotations всех ресурсов теперь собираются одним хелпером `ingress-gateway.helpers.app.metadata` (`labels:` + условный `annotations:` из `generic.*`). Раньше каждый манифест повторял этот блок вручную. Стандартный рендер семантически не меняется (убраны только пустые строки).

### Fixed
- Ресурсы OIDC (`HTTPRoute`, `ReferenceGrant`, `AuthorizationPolicy`, `RequestAuthentication`) теперь тоже получают `generic.annotations` - раньше на них выводились только labels.

---

## [3.3.1] - 2026-06-25

### Changed
- Файлы значений приведены к стандарту: `values.example.yaml` переименован в `values.full.yaml`, `minimal-values.yaml` - в `values.minimal.yaml` (`values.yaml` уже был минимальным дефолтом).
- Комментарии в шаблонах, `values.*`, `values.schema.json` и `NOTES.txt` переведены на английский; длинные тире заменены на дефисы.

## [3.3.0] - 2026-06-24

### Changed
- Демо-домен заменён с `*.ecpk.ru` на `*.ecpk.test` (зарезервированный тестовый
  TLD) во всех местах: логике авто-подбора wildcard TLS-секретов
  (`_helpers.tpl`, `secret.yaml`), `values.schema.json`, `README.md` и примерах.
  Авто-секрет теперь срабатывает на `*.idp.ecpk.test` / `*.edp.ecpk.test`. Если
  использовались хосты `*.ecpk.ru`, задайте `tlsSecretName`/`certificateRefs`
  явно или поправьте hostname.
- Обезличены демо-данные в примерах: hostname `gtw-test2.example.test`, namespace
  `demo-core-test`, OIDC-группа `demo_dev_core_admin`. Майнтейнер в `Chart.yaml`
  заменён на `platform-team`. На рендер не влияет.

---

## [3.2.5] - 2026-06-23

### Added
- Совместимость с использованием как сабчарта: в корень `values.schema.json`
  добавлены опциональные `global` (Helm инжектит его в любой сабчарт) и `enabled`
  (флаг `condition` родительского чарта). Оба скрыты в форме и не используются
  шаблонами. Схема остаётся `additionalProperties: false`; на рендер не влияет.
  Нужно, чтобы `console` мог подключать этот чарт сабчартом.

## [3.2.4] - 2026-06-11

### Changed
- `xroutes[].enabled`, `xroutes[].hostnames` и `xroutes[].parentRefs[].gateway` помечены `ui:widget: hidden` в `values.schema.json`: при единственном Gateway чарт сам создаёт Route при отсутствии `enabled`, выводит `hostnames` из listener'ов по `sectionName` и подставляет имя Gateway в `parentRefs[].gateway`, поэтому в форме эти поля не показываются. На рендер не влияет.

## [3.2.3] - 2026-06-09

### Removed
- Временное тестовое поле `testField` (добавлялось в 3.2.2 для проверки обновления).

## [3.2.2] - 2026-06-09

### Added
- Временное тестовое поле `testField` (string) в `values.yaml` и `values.schema.json` - для проверки обновления версии/схемы. Ни на что не влияет.

## [3.2.1] - 2026-06-09

### Added
- Иконка чарта (`icon` в `Chart.yaml`, data URI) - показывается в каталоге портала.

### Changed
- В `maintainers` добавлен `bolotovma`.

## [3.2.0] - 2026-06-08

### Changed
- Обновлена `values.schema.json`.

## [3.1.0] - 2026-06-01

Доработка: авто-секреты TLS, упрощения для одного Gateway, восстановление схемы.

### Added
- **Авто-генерация TLS-секретов** - для listener'а с `tlsMode: Terminate`
  (`HTTPS`/`TLS`) по `hostname` создаётся `Secret` `type: kubernetes.io/tls`:
  `*.idp.ecpk.test` → `…-secret-…-idptls`, `*edp.ecpk.test` → `…-secret-…-edptls`,
  прочие hostname → секрет не создаётся (нужен `tlsSecretName`/`certificateRefs`).
  Имя - по конвенции (kindShort `secret`); дубли по имени схлопываются;
  `certificateRefs` listener'а проставляются автоматически. `tls.crt`/`tls.key`
  пустые - заполняются пользователем.
- **Упрощения при единственном Gateway** - в `xroutes[]` можно опускать
  `parentRefs[].gateway` (подставляется имя единственного Gateway) и `hostnames`
  (берутся из listener'ов по `parentRefs[].sectionName`).
- **`kindShort: secret`** - добавлен код типа ресурса для `Secret`.

### Changed
- **`values.schema.json` восстановлен и адаптирован** под структуру `naming.*`:
  убраны `instanceTag`/`clusterTag`/`projectTag`/`nameOverride`/`releasePrefix`/
  `gatewayWorkloadSelectorLabels` и per-resource `labels`/`annotations`; добавлен
  объект `naming` (required), `Gateway`/`Route` `name` - `shortToken` (2..6).
  Поле `ipAddress` скрыто (`ui:widget: hidden`). `parentRefs[].gateway` и
  `hostnames` сделаны необязательными; снято требование `tlsSecretName` для
  Terminate-listener'ов (возможен авто-секрет).

### Fixed
- **`enabled: false` теперь учитывается** - переключатели (`gateways[]`,
  `xroutes[]`, `networkPolicy`, `authorizationPolicy`) использовали
  `| default true`, из-за чего явный `false` игнорировался. Введён helper
  `ingress-gateway.helpers.app.enabled`.

---

## [3.0.0] - 2026-06-01

Приведение чарта к единому стандарту (как `egress-gateway` и `policies`).
**BREAKING**: изменены конвенция именования и структура `values.yaml`.

### Added
- **Конвенция именования** - имя каждого ресурса строится как
  `{instanceTag}-{clusterTag}-{kindShort}-{projectTag}-{name}`. Общие теги - в
  блоке `naming` (`instanceTag`/`clusterTag`/`projectTag`), `kindShort` по типу
  ресурса (`igw`/`cm`/`np`/`ap`/`hr`/`gr`/`tr`/`tcr`/`ur`), `name` - на каждый
  Gateway/Route. Все части валидируются (DNS-формат, длины 2..6, известный kind).
- **`NOTES.txt`** - пост-установочная сводка по созданным ресурсам.
- **`.helmignore`** - стандартный набор игнор-паттернов.

### Changed
- **Структура `naming`** - теги перенесены из top-level `instanceTag`/
  `clusterTag`/`projectTag` в блок `naming.*`; теперь все три **обязательны**.
- **Хелперы объединены** - `templates/helpers/app.tpl` и `tplvalues.tpl`
  заменены одним `templates/_helpers.tpl` с префиксом `ingress-gateway.helpers.*`.
- **Имя чарта** - `Chart.yaml name` изменён с `gateway` на `ingress-gateway`,
  добавлен `appVersion`.
- **Workload selector для NetworkPolicy/AuthorizationPolicy** - выбор по label
  `gateway.networking.k8s.io/gateway-name` (= полное имя Gateway), как его
  проставляет Istio Gateway controller. Раньше - кастомный `gateway-name` с
  логическим именем.
- **Комментарии в шаблонах** - добавлены header-блоки в стиле `egress-gateway`/
  `policies`; убраны inline-комментарии из тел манифестов.

### Removed
- **Per-resource labels/annotations** - `gateways[].labels`/`.annotations` и
  `xroutes[].labels`/`.annotations` больше не поддерживаются. Используйте
  глобальные `generic.labels`/`generic.annotations`.
- **`nameOverride`, `releasePrefix`** и legacy-хелпер `fullname` (короткий
  fallback-формат имени) удалены: теги теперь обязательны.
- **`gatewayWorkloadSelectorLabels`** - пользовательские selector labels удалены
  (selector выводится из имени Gateway).
- **`values.schema.json`** - удалён (структура `values.yaml` изменилась;
  стандартные чарты схему не используют). Может быть добавлен заново под новую
  структуру в фазе доработки.

### Notes
- Имена `gateways[].name` и `xroutes[].name` теперь ограничены 2..6 символами -
  длинные имена из прежних примеров укорочены в `values.yaml`/`minimal-values.yaml`.
- Поведение `authorizationPolicy` (ALLOW 0.0.0.0/0) и `oidcAuth` (пользовательские
  имена) сохранено; их доработка - следующий шаг.

---

## [0.2.0] - 2026-05-29

Релиз с доработками конфигурации автоматически создаваемого Istio Gateway
Deployment и упрощением шаблонов чарта.

### Added
- **Настройка HPA для Gateway Deployment** - секция `hpa` для каждого gateway,
  HPA через инфраструктурную `ConfigMap`.
- **Настройка ресурсов Gateway Deployment** - секция `resources` для контейнера
  `istio-proxy` через `ConfigMap.data.deployment`.

### Changed
- **Повторяющиеся проверки перенесены в helpers** - единая логика `enabled`.

---

## [0.1.0] - 2026-05-28

Первый релиз чарта.

### Added
- **Gateway API resources** - `Gateway`, `HTTPRoute`/`TLSRoute`/`TCPRoute`/
  `UDPRoute`, `ReferenceGrant`, infrastructure `ConfigMap`.
- **Настройка Service через ConfigMap** - `LoadBalancer`,
  `allocateLoadBalancerNodePorts`, `externalTrafficPolicy`, удаление порта 15021.
- **Поддержка статического IP** - `ipAddress` → `metallb.io/loadBalancerIPs`.
- **AuthorizationPolicy** и **NetworkPolicy** для workload gateway.
- **Reference `values.yaml`** и **`minimal-values.yaml`**.
