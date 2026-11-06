#!/usr/bin/env python3
"""Render egress IPv4 regression cases (requires Helm, PyYAML and built dependencies)."""

import copy
import json
from pathlib import Path
import subprocess
import tempfile

try:
    import yaml
except ImportError as error:
    raise SystemExit("This check requires PyYAML; no packages are installed automatically.") from error


ROOT = Path(__file__).resolve().parents[1]
CHART = ROOT / "egress-gateway"
IP = "10.20.30.40"


def render(values, skip_schema=False):
    with tempfile.TemporaryDirectory(prefix="egress-ip-") as directory:
        path = Path(directory) / "values.json"
        path.write_text(json.dumps(values), encoding="utf-8")
        command = ["helm", "template", "release", str(CHART), "-f", str(path)]
        if skip_schema:
            command.append("--skip-schema-validation")
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        return result


def success(values):
    result = render(values)
    assert result.returncode == 0, result.stderr
    return [document for document in yaml.safe_load_all(result.stdout) if document]


def entries(documents):
    return [item for item in documents if item["kind"] == "ServiceEntry"]


def external_rules(documents):
    policies = [
        item for item in documents
        if item["kind"] == "NetworkPolicy" and item["metadata"]["name"].endswith("-out")
    ]
    assert len(policies) == 1
    return [
        (peer["ipBlock"]["cidr"], port["port"], port.get("protocol", "TCP"))
        for rule in policies[0]["spec"]["egress"]
        for peer in rule.get("to", []) if "ipBlock" in peer
        for port in rule.get("ports", [])
    ]


def main():
    base = yaml.safe_load((CHART / "values.minimal.yaml").read_text(encoding="utf-8"))
    dns = success(base)
    assert len(entries(dns)) == 1
    original = entries(dns)[0]
    assert original["spec"]["hosts"] == ["repository.solution.test"]
    assert original["spec"]["resolution"] == "DNS"
    assert "addresses" not in original["spec"] and "endpoints" not in original["spec"]
    assert external_rules(dns) == [("10.40.20.50/32", 443, "TCP")]

    for hostname in ("123.example.org", "1.2.3.example"):
        case = copy.deepcopy(base)
        case["serviceEntries"][0]["hostname"] = hostname
        service = entries(success(case))[0]["spec"]
        assert service["resolution"] == "DNS" and service["hosts"] == [hostname]
        assert "addresses" not in service and "endpoints" not in service

    ipv4 = copy.deepcopy(base)
    ipv4["serviceEntries"] = [{"name": "vm", "hostname": IP, "port": 22, "protocol": "TCP"}]
    ipv4["networkPolicy"]["endpoints"] = []
    static_documents = success(ipv4)
    static_entries = entries(static_documents)
    assert len(static_entries) == 1
    static = static_entries[0]
    assert static["spec"]["resolution"] == "STATIC"
    assert static["spec"]["addresses"] == [IP]
    assert static["spec"]["endpoints"] == [{"address": IP}]
    assert static["spec"]["ports"] == [{"name": "tcp", "number": 22, "protocol": "TCP"}]
    assert static["spec"]["hosts"][0] != IP
    assert static["metadata"]["labels"]["istio.io/use-waypoint"] == original["metadata"]["labels"]["istio.io/use-waypoint"]
    assert static["spec"]["exportTo"] == original["spec"]["exportTo"]
    assert external_rules(static_documents) == [(IP + "/32", 22, "TCP")]

    for address in ("1.0.0.1", "255.255.255.254"):
        case = copy.deepcopy(ipv4)
        case["serviceEntries"][0]["hostname"] = address
        service = entries(success(case))[0]["spec"]
        assert service["resolution"] == "STATIC"
        assert service["addresses"] == [address]
        assert service["endpoints"] == [{"address": address}]

    for protocol in ("TCP", "HTTP", "TLS", None):
        case = copy.deepcopy(ipv4)
        if protocol is None:
            del case["serviceEntries"][0]["protocol"]
        else:
            case["serviceEntries"][0]["protocol"] = protocol
        documents = success(case)
        expected_protocol = protocol or "TLS"
        assert entries(documents)[0]["spec"]["ports"][0]["protocol"] == expected_protocol
        assert entries(documents)[0]["spec"]["resolution"] == "STATIC"
        assert external_rules(documents) == [(IP + "/32", 22, "TCP")]

    mixed = copy.deepcopy(ipv4)
    mixed["serviceEntries"] += base["serviceEntries"]
    mixed["networkPolicy"]["endpoints"] = [
        {"address": IP, "port": 22},
        {"address": IP + "/32", "port": 22},
        {"address": IP, "port": 2222},
        {"address": "10.40.0.0/16", "port": 443},
    ]
    mixed_documents = success(mixed)
    assert len(entries(mixed_documents)) == 2
    assert sorted(external_rules(mixed_documents)) == sorted([
        (IP + "/32", 22, "TCP"), (IP + "/32", 2222, "TCP"), ("10.40.0.0/16", 443, "TCP"),
    ])

    disabled = copy.deepcopy(base)
    disabled["serviceEntries"].append({
        "name": "off", "hostname": IP, "port": 22, "protocol": "TCP", "enabled": False,
    })
    disabled_documents = success(disabled)
    assert len(entries(disabled_documents)) == 1
    assert external_rules(disabled_documents) == external_rules(dns)

    copies = copy.deepcopy(ipv4)
    copies["senders"]["additionalNamespaces"] = ["nbox-dev-ns-other"]
    waypoint = copies["waypointNamespace"]["waypoint"]["waypoints"][0]
    waypoint["allowedNamespaces"].append("nbox-dev-ns-other")
    copied_entries = entries(success(copies))
    assert {item["metadata"]["namespace"] for item in copied_entries} == {
        base["senders"]["namespace"], "nbox-dev-ns-other",
    }
    assert all(item["spec"] == static["spec"] for item in copied_entries)
    for item in copied_entries:
        for key in ("istio.io/use-waypoint", "istio.io/use-waypoint-namespace"):
            assert item["metadata"]["labels"][key] == static["metadata"]["labels"][key]

    local = yaml.safe_load((CHART / "values.mesh-senders.yaml").read_text(encoding="utf-8"))
    local["serviceEntries"] = ipv4["serviceEntries"]
    local["networkPolicy"]["endpoints"] = []
    local_entry = entries(success(local))[0]
    assert local_entry["metadata"]["namespace"] == local["senders"]["namespace"]
    assert local_entry["metadata"]["labels"]["istio.io/use-waypoint-namespace"] == local["senders"]["namespace"]

    invalid_entries = {
        "removed ip key": [{"name": "vm", "hostname": "vm.example.org", "ip": IP, "protocol": "TCP"}],
        "old ip-only syntax": [{"name": "vm", "ip": IP, "protocol": "TCP"}],
        "missing hostname": [{"name": "vm", "protocol": "TCP"}],
        "empty hostname": [{"name": "vm", "hostname": "", "protocol": "TCP"}],
        "numeric hostname": [{"name": "vm", "hostname": 1234, "protocol": "TCP"}],
        "null hostname": [{"name": "vm", "hostname": None, "protocol": "TCP"}],
        "list hostname": [{"name": "vm", "hostname": [IP], "protocol": "TCP"}],
        "invalid IPv4": [{"name": "vm", "hostname": "256.1.2.3", "protocol": "TCP"}],
        "short numeric dotted": [{"name": "vm", "hostname": "10.20.30", "protocol": "TCP"}],
        "long numeric dotted": [{"name": "vm", "hostname": "10.20.30.40.50", "protocol": "TCP"}],
        "unspecified IPv4": [{"name": "vm", "hostname": "0.0.0.0", "protocol": "TCP"}],
        "CIDR": [{"name": "vm", "hostname": IP + "/32", "protocol": "TCP"}],
        "IPv6": [{"name": "vm", "hostname": "2001:db8::1", "protocol": "TCP"}],
        "leading zero": [{"name": "vm", "hostname": "010.20.30.40", "protocol": "TCP"}],
        "unsupported protocol": [{"name": "vm", "hostname": IP, "protocol": "UDP"}],
        "generated hostname collision": [
            {"name": "vm", "hostname": IP, "protocol": "TCP"},
            {"name": "dns", "hostname": static["spec"]["hosts"][0]},
        ],
        "duplicate IP": [
            {"name": "vm", "hostname": IP, "port": 22, "protocol": "TCP"},
            {"name": "vm2", "hostname": IP, "port": 2222, "protocol": "TCP"},
        ],
    }
    count = 0
    for label, case_entries in invalid_entries.items():
        case = copy.deepcopy(ipv4)
        case["serviceEntries"] = case_entries
        for skip_schema in (False, True):
            result = render(case, skip_schema)
            assert result.returncode != 0, f"Accepted {label}, skip_schema={skip_schema}"
            assert "serviceEntries" in result.stderr, result.stderr
            count += 1

    empty = copy.deepcopy(base)
    empty["networkPolicy"]["endpoints"] = []
    for case in (empty, {**empty, "serviceEntries": disabled["serviceEntries"]}):
        result = render(case)
        assert result.returncode != 0 and "networkPolicy" in result.stderr, result.stderr
    print(f"egress static IP: 14 positive scenarios, {count + 2} negative renders passed")


if __name__ == "__main__":
    main()
