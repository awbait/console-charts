#!/usr/bin/env python3
"""Render DestinationRule regression cases using Helm and the Python standard library."""

import copy
import json
from pathlib import Path
import re
import subprocess
import unittest


REPO = Path(__file__).resolve().parent.parent
BASE_VALUES = {
    "identity": {"instance": "ed", "cluster": "dev", "project": "nbox"},
    "gateways": [{
        "name": "main",
        "listeners": [{
            "name": "http", "protocol": "HTTP", "port": 80,
            "hostname": "example.test.ru",
        }],
    }],
}


class DestinationRuleTests(unittest.TestCase):
    def render(self, settings, *, separate_routes=False, skip_schema=False):
        values = copy.deepcopy(BASE_VALUES)
        routes = []
        for index, setting in enumerate(settings):
            rule = {"backendRefs": [{"name": "app", "port": 80, **setting}]}
            if separate_routes or not routes:
                routes.append({
                    "name": f"app{index}", "kind": "HTTPRoute",
                    "parentRefs": [{"gateway": "main", "sectionName": "http"}],
                    "rules": [rule],
                })
            else:
                routes[0]["rules"].append(rule)
        values["xroutes"] = routes
        command = ["helm", "template", "release", "ingress-gateway", "-f", "-"]
        if skip_schema:
            command.append("--skip-schema-validation")
        return subprocess.run(
            command, cwd=REPO, input=json.dumps(values),
            text=True, encoding="utf-8", capture_output=True, check=False,
        )

    def destination_rule(self, settings):
        result = self.render(settings)
        self.assertEqual(result.returncode, 0, result.stderr)
        documents = [
            doc for doc in re.split(r"^---\s*$", result.stdout, flags=re.MULTILINE)
            if re.search(r"^kind: DestinationRule$", doc, flags=re.MULTILINE)
        ]
        self.assertEqual(len(documents), 1, result.stdout)
        return documents[0]

    def test_omitted_and_explicit_ttl_conflict(self):
        for ttl in ("0s", "3600s"):
            implicit = {"sessionAffinity": {"cookieName": "route"}}
            explicit = {"sessionAffinity": {"cookieName": "route", "ttl": ttl}}
            for settings in ([implicit, explicit], [explicit, implicit]):
                for separate_routes in (False, True):
                    for skip_schema in (False, True):
                        with self.subTest(ttl=ttl, settings=settings,
                                          separate_routes=separate_routes,
                                          skip_schema=skip_schema):
                            result = self.render(
                                settings, separate_routes=separate_routes,
                                skip_schema=skip_schema,
                            )
                            self.assertNotEqual(result.returncode, 0)
                            self.assertIn("omitted and explicit ttl", result.stderr)

    def test_matching_affinity_merges(self):
        for ttl in (None, "0s", "3600s"):
            affinity = {"cookieName": "route"}
            if ttl is not None:
                affinity["ttl"] = ttl
            with self.subTest(ttl=ttl):
                document = self.destination_rule([
                    {"sessionAffinity": affinity}, {"sessionAffinity": affinity},
                ])
                if ttl is None:
                    self.assertNotRegex(document, r"\bttl:")
                else:
                    self.assertIn(f'ttl: "{ttl}"', document)

    def test_h2_and_unconfigured_references_can_merge(self):
        for affinity in ({"cookieName": "route"}, {"cookieName": "route", "ttl": "0s"}):
            settings = [
                {"sessionAffinity": affinity},
                {"h2UpgradePolicy": "DO_NOT_UPGRADE"},
                {"sessionAffinity": {}}, {},
            ]
            for ordered in (settings, list(reversed(settings))):
                with self.subTest(settings=ordered):
                    document = self.destination_rule(ordered)
                    self.assertIn('h2UpgradePolicy: "DO_NOT_UPGRADE"', document)
                    self.assertIn('name: "route"', document)
                    self.assertEqual(bool(re.search(r"\bttl:", document)), "ttl" in affinity)

    def test_different_explicit_settings_conflict(self):
        for field, first, second in (
            ("ttl", "0s", "3600s"), ("cookieName", "route", "other"),
        ):
            with self.subTest(field=field):
                result = self.render([
                    {"sessionAffinity": {"cookieName": "route", field: first}},
                    {"sessionAffinity": {"cookieName": "route", field: second}},
                ])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("disagrees with an earlier", result.stderr)

    def test_absent_or_empty_settings_render_no_rule(self):
        for settings in ([{}], [{"sessionAffinity": {}}]):
            with self.subTest(settings=settings):
                result = self.render(settings)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("kind: DestinationRule", result.stdout)


if __name__ == "__main__":
    unittest.main()
