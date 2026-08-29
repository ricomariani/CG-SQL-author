#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import sys

expected_plan_count = None
if len(sys.argv) == 3 and sys.argv[1] == "--query-plan-count":
    expected_plan_count = int(sys.argv[2])
elif len(sys.argv) != 1:
    raise SystemExit(f"usage: {sys.argv[0]} [--query-plan-count count]")

data = json.load(sys.stdin)

if expected_plan_count is not None:
    if not isinstance(data, dict) or not isinstance(data.get("alerts"), dict):
        raise SystemExit("query plan report has invalid or missing alerts")

    plans = data.get("plans")
    if not isinstance(plans, list) or len(plans) != expected_plan_count:
        raise SystemExit(f"query plan report does not contain {expected_plan_count} plans")

    expected_ids = list(range(1, expected_plan_count + 1))
    if [plan.get("id") for plan in plans if isinstance(plan, dict)] != expected_ids:
        raise SystemExit("query plan report has missing, duplicate, or invalid plan IDs")

    for plan in plans:
        if (
            not isinstance(plan.get("query"), str)
            or not plan["query"]
            or not isinstance(plan.get("stats"), dict)
            or not isinstance(plan.get("plan"), str)
            or not plan["plan"].startswith("QUERY PLAN")
        ):
            raise SystemExit(f"query plan report has invalid plan {plan['id']}")

json_data = json.dumps(data, indent=2)
print(json_data)
