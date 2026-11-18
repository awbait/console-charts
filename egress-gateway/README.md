# egress-gateway

Чарт выпускает трафик во внешние системы через один VpcEgressGateway с известными IP-адресами. В режиме mesh в каждом неймспейсе ваших сервисов создаётся свой waypoint.

## Режимы и ресурсы

| Секция | Что создаётся | Когда использовать |
|---|---|---|
| `senders.namespace` | В mesh: Gateway и ConfigMap в каждом указанном namespace | Сервисы в ambient |
| `serviceEntries` | Копия каждой включённой ServiceEntry в каждом namespace отправителей | Внешние домены в mesh |
| `networkPolicy` | Правила входа и выхода каждого waypoint и выхода отправителей к нему | Ограничение трафика в mesh |
| `authorizationPolicy` | AuthorizationPolicy на каждый локальный Gateway | Доступ только из его namespace |
| `vpcEgressGateway` | Один VpcEgressGateway и необязательный LimitRange | В обоих режимах |
| `vegNamespace` | Namespace выхода и квота | В обоих режимах |

В mesh ServiceEntry привязана к waypoint своего namespace. Все waypoint направляют внешний трафик через общий выход. Только домены из `serviceEntries` идут этим путём, остальной трафик не меняется.

В direct waypoint, ServiceEntry и политики не создаются. При `scope: subnet` выход выполняет SNAT для каждой подсети из списка `senders.subnet`. Это имена ресурсов Subnet, они не обязаны совпадать с именами namespace. Список namespace не ограничивает захват подсети: в неё могут входить и другие namespace. При `scope: label` выбираются поды из `senders.namespace` с нужной меткой.

## Куда ставится релиз

Namespace из `senders.namespace` должны существовать до установки. В mesh каждый из них должен быть подключён к ambient, допускать waypoint с уровнем Pod Security не ниже baseline и иметь свободную квоту для его реплик. Чарт не создаёт и не перенастраивает эти namespace.

Namespace выхода по умолчанию создаёт сабчарт `vegNamespace`: `{project}-{cluster}-ns-{vegNamespace.namespace.name}`. Он остаётся вне сетки (`serviceMesh.never: true`), с ролью `egress` и уровнем Pod Security privileged. Отдельный namespace для waypoint не создаётся.

## Окружение и имена

Теги задаются в `global.identity`: `instance`, `cluster`, `project`. Код проекта содержит 2..9 строчных латинских букв, цифр и дефисов.

| Окружение | instance | cluster |
|---|---|---|
| Infra-dev-ecpk | in | inf |
| dev-ecpk | id | dev |
| techsec-dev | ed | tco |
| dev-common | ed | dev |
| test-common | ed | tst |
| global | pr | gl |
| observability | pr | obs |
| techsec | pr | tcc |
| int-common | pr | cmi |
| ML | pr | ml |
| ext-common | pr | cme |

Имена ресурсов: `{instance}-{cluster}-{kindShort}-{project}-{name}`. Коды: `wp` для Gateway и его ConfigMap, `egw` для ServiceEntry, `veg` для VpcEgressGateway и LimitRange, `ap` для AuthorizationPolicy. NetworkPolicy использует форму `{instance}-{cluster}-np-{имя выхода}-{project}-{out|in|senders}`.

Имя waypoint и AuthorizationPolicy выводится из `vpcEgressGateway.name`. Например, для `vip` Gateway называется `ed-dev-wp-nbox-vip` во всех namespace отправителей. Одинаковое имя в разных namespace допустимо. Для двух выходов в одном namespace задавайте разные имена выхода и внешних сервисов.

На собственных ресурсах стоят `app=egress-gateway`, `app.kubernetes.io/instance` с именем релиза и метки `ecpk/instance`, `ecpk/cluster`, `ecpk/project`. `generic.labels` и `generic.annotations` применяются ко всем собственным ресурсам, включая waypoint. У ресурсов сабчарта namespace свои метки и настройки `generic`.

## Параметры

| Поле | Нужно указать | Назначение |
|---|---|---|
| `mode` | Нет, по умолчанию mesh | mesh или direct |
| `senders.namespace` | Да | Непустой список существующих namespace без повторов |
| `senders.subnet` | direct, scope subnet | Непустой список имён Subnet без повторов |
| `serviceEntries[].name`, `.hostname` | mesh | Имя записи и внешний домен |
| `serviceEntries[].port`, `.protocol` | Нет | По умолчанию 443 и TLS, также доступны HTTP и TCP |
| `serviceEntries[].enabled` | Нет | false исключает запись |
| `vpcEgressGateway.name` | Да, по умолчанию vip | Имя выхода, 2..9 символов |
| `vpcEgressGateway.externalIPs` | Да | Внешние адреса, по реплике выхода на адрес |
| `vpcEgressGateway.scope` | direct | subnet для подсетей или label для подов по метке |
| `vpcEgressGateway.label` | direct, scope label | Ключ метки, по умолчанию ecpk/egress, значение равно полному имени выхода |
| `gatewayScheduling` | Нет | Правила размещения подов выхода |
| `vpcEgressGateway.nodeSelector`, `.tolerations` | Нет | Заменяют одноимённые правила gatewayScheduling целиком, пустой список отключает их |
| `vpcEgressGateway.limitRange` | Нет | Ресурсы контейнеров без собственных requests и limits в namespace выхода |
| `networkPolicy.enabled` | Нет | Включает политики каждого waypoint |
| `networkPolicy.endpoints` | При включённых политиках | Разрешённые внешние адреса или CIDR и TCP-порты |
| `networkPolicy.senders` | Нет, по умолчанию true | Добавляет правило выхода подов namespace к локальному waypoint на 15008 |
| `authorizationPolicy.enabled` | Нет | Разрешает доступ к каждому waypoint только из его namespace |
| `vegNamespace.namespace.name` | Да, по умолчанию veg-vip | Назначение namespace выхода |

Waypoint не имеет пользовательских настроек. Для каждого зафиксированы: обработка сервисов, HBONE 15008, ClusterIP, приём привязок только своего namespace, HPA от 2 до 5 реплик с целью CPU 80%. На реплику запрашиваются 100m CPU и 128Mi памяти, лимиты составляют 2000m CPU и 1024Mi. Суммарная потребность растёт с числом namespace.

При включённых сетевых правилах каждому waypoint разрешён выход к istiod на 15012, DNS в kube-system на 1053 по TCP/UDP и к указанным endpoints. Вход на 15008 разрешён из его namespace. Правило `senders` дополняет существующие политики платформы, а не заменяет их.

Namespace выхода использует дефолтную подсеть `ovn-default`. Собственная Subnet не создаётся, её параметры в этом чарте не настраиваются. Включение `vegNamespace.subnet.enabled` запрещено. В кластере `ovn-default` должна быть дефолтной подсетью VPC `ovn-cluster`, а namespace выхода не должен быть привязан к другой Subnet. Для подов VpcEgressGateway также зафиксировано `spec.internalSubnet: ovn-default`. Внешние IP используют отдельную `spec.externalSubnet: egress-vip`.

## Когда рендер останавливается

- Не задан global.identity, указан identity в корне или неверны теги и имена ресурсов.
- mode отличается от mesh и direct.
- senders.namespace не является непустым списком допустимых имён namespace или содержит повторы.
- Namespace отправителей совпадает с namespace выхода.
- Переданы удалённые waypointNamespace, waypoint, senders.additionalNamespaces или senders.additionalSubnets.
- Не задано имя выхода, список внешних IP пуст или не задано назначение namespace выхода.
- Namespace выхода выключен, его роль отличается от egress или serviceMesh.never не равен true.
- Заданы настройки собственной подсети namespace выхода или включено её создание через vegNamespace.subnet.enabled.
- Задано переопределение имени namespace через global.namespaceOverride или vegNamespace.namespace.namespaceOverride.
- В mesh нет включённых внешних сервисов, у них отсутствуют имя или домен, повторяется имя или домен, неверны порт или протокол.
- В direct переданы serviceEntries или включены networkPolicy либо authorizationPolicy.
- В direct неверен scope, для scope subnet не указана Subnet, имена подсетей неверны или повторяются, для scope label неверен ключ метки.
- При включённых сетевых правилах отсутствуют endpoints или обязательные адрес и порт.

Схема дополнительно проверяет типы, диапазоны и неизвестные поля. Сабчарт namespace проверяет свои квоты и параметры подсети.

## Файлы чарта

`values.yaml` содержит дефолты без данных заказа. Для рендера добавьте теги, namespace отправителей, внешние IP и, в mesh, внешние сервисы. `values.minimal.yaml` показывает mesh с одним namespace, `values.mesh-senders.yaml` с двумя, `values.direct.yaml` показывает SNAT по подсети. `values.full.yaml` содержит полный пример параметров. `values.schema.json` задаёт проверку и форму, `view.schema.json` описывает её представление.

## Переход с 9.x

**BREAKING:** преобразуйте senders.namespace из строки в список и перенесите в него все значения senders.additionalNamespaces. Удалите waypointNamespace целиком и global.namespacePurpose. Настройки waypoint больше не принимаются. Преобразуйте senders.subnet в список и добавьте в него все значения senders.additionalSubnets. Удалите senders.additionalSubnets. Имена подсетей и поведение SNAT сохраняются. Замените `vpcEgressGateway.scope: namespace` на `scope: subnet`. Удалите прежние параметры `vegNamespace.subnet`: собственная подсеть namespace выхода больше не создаётся.

При обновлении старого mesh-релиза прежний отдельный namespace waypoint и его ресурсы перестают входить в релиз. Новые waypoint появляются в namespace отправителей, их имена выводятся из имени выхода. Сначала проверьте квоты, сетевые политики и содержимое старого служебного namespace: обновление может удалить управляемый релизом namespace вместе с оставшимися объектами. Безопасный переход и трафик нужно проверить на стенде до обновления рабочего релиза.
