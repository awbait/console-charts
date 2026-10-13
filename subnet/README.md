# Subnet

Чарт управляет одной подсетью kube-ovn на релиз, независимо от чарта namespace.
Namespace и квоты он не создаёт. Для нескольких подсетей используйте несколько релизов.
В кластере должна быть установлена CRD `subnets.kubeovn.io` и контроллер kube-ovn.

## Использование

Зарезервируйте диапазон адресов и заполните `values.minimal.yaml`. Включите
`enabled: true`. Имя ресурса: `{identity.project}-{identity.cluster}-subnet-{subnet.name}`,
например `demo-dev-subnet-app`. `global.identity`, если задан, имеет приоритет
над `identity`. Не меняйте имя и identity существующей подсети при редактировании.

## Параметры

| Поле в subnet | Назначение |
|---|---|
| cidrBlock | IPv4 диапазон подсети, маска /16../30 |
| natOutgoing | NAT исходящего трафика |
| excludeIPs | Адреса или диапазоны `10.24.8.2..10.24.8.4`; поле CRD `excludeIps` |
| gatewayType | `distributed` или `centralized` |
| private | Изоляция подсети средствами kube-ovn |
| allowSubnets | Дополнительные разрешённые IPv4 диапазоны |
| namespaces | Полные имена существующих namespace; пустой список убирает явные привязки |
| gatewayNodes | Для centralized: список узлов через запятую, например `node-a,node-b`; поле CRD `gatewayNode`, скрыто в форме |

В values используется `allowSubnets`, как в CRD и чарте namespace. Поля
`allowedSubnets` нет. Диапазон `172.30.0.0/15` захардкожен в шаблоне и присутствует
даже при пустом allowSubnets. Повторы этого диапазона не выводятся.

Шлюз вычисляется как первый адрес после адреса сети. Он всегда добавляется
шаблоном в `excludeIps`; `excludeIPs` задаёт дополнительные исключения.
`default: false`, `protocol: IPv4`, `enableEcmp: false` заданы прямо в values.yaml
и зафиксированы схемой. Как в актуальном namespace, тип шлюза по умолчанию distributed.
`private: true`, `natOutgoing: false`. Общие метки и аннотации задаются в `generic`.
Subnet получает annotation Argo CD sync-wave `-2` и labels по образцу namespace.

Полный справочник: `values.full.yaml`. Схема формы: `values.schema.json`.
`view.schema.json` содержит заказ и действие «Настроить подсеть». Его нужно
вставить в конструкторе сервиса Console: портал не импортирует этот файл из пакета
автоматически. Отдельного блока defaults нет, значения заданы в values.yaml.

## Валидации

- Неизвестные поля отвергаются схемой; обязательные поля должны быть заполнены.
- Имя назначения: DNS, 2..12 символов; проект: DNS, 2..9 символов; кластер: DNS.
- Полное имя ресурса не превышает 63 символов, без молчаливой обрезки.
- cidrBlock: IPv4, маска /16../30, адрес должен совпадать с началом сети.
- excludeIPs: IPv4 адреса или упорядоченные диапазоны внутри cidrBlock.
- allowSubnets: IPv4 CIDR, маска /0../32; списки не допускают повторов.
- namespaces: DNS имена длиной до 63 символов, без повторов.
- gatewayType допускает distributed или centralized. Для centralized обязателен gatewayNodes.
- Служебные default, protocol и enableEcmp имеют фиксированные значения.
- Устаревший global.enable=false отвергается: используйте enabled=false.

Проверки CIDR и диапазонов выполняются также шаблоном. Чарт не проверяет наличие
namespace или узлов в кластере и пересечение с другими подсетями.
