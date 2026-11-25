#!/usr/bin/env python3
"""Self-tests for the AFC-626 cron-monitor rules in scripts/sentry-ci-report.py.

Stdlib only, no network: send_envelope is replaced with a recorder.
Run with `python3 scripts/test-sentry-ci-report.py`.
"""

import importlib.util
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "sentry_ci_report", ROOT / "scripts" / "sentry-ci-report.py")
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)

DSN = "https://abc123@o1.ingest.example.test/42"


def run_reporter(workflow_name, conclusion, event="schedule", branch="main"):
    sent = []
    env = {
        "SENTRY_FLEET_DSN": DSN,
        "WORKFLOW_NAME": workflow_name,
        "WORKFLOW_CONCLUSION": conclusion,
        "WORKFLOW_EVENT": event,
        "WORKFLOW_BRANCH": branch,
        "WORKFLOW_ACTOR": "agent",
        "WORKFLOW_RUN_URL": "https://example.test/run/1",
        "WORKFLOW_RUN_ID": "1",
    }
    with mock.patch.object(
        reporter, "send_envelope", lambda url, auth, item_type, payload: sent.append((item_type, payload))
    ), mock.patch.dict(os.environ, env, clear=False):
        rc = reporter.main()
    return rc, sent


class UnmonitoredScheduleTests(unittest.TestCase):
    def test_auto_merge_sweep_is_unmonitored_not_mapped(self):
        self.assertIn("Auto-merge PRs", reporter.UNMONITORED_SCHEDULES)
        self.assertNotIn("auto-merge prs", reporter._CRON_SCHEDULES_FOLDED)

    def test_unmonitored_names_are_real_workflows(self):
        names = reporter.discover_workflow_names()
        self.assertIsNotNone(names)
        for name in reporter.UNMONITORED_SCHEDULES:
            self.assertIn(name, names)

    def test_scheduled_sweep_sends_no_checkin_and_no_drift_event(self):
        rc, sent = run_reporter("Auto-merge PRs", "success")
        self.assertEqual(rc, 0)
        self.assertEqual(sent, [])

    def test_failed_sweep_still_raises_its_error_event(self):
        rc, sent = run_reporter("Auto-merge PRs", "failure")
        self.assertEqual(rc, 0)
        self.assertEqual([item_type for item_type, _ in sent], ["event"])
        self.assertEqual(sent[0][1]["fingerprint"], ["ci-failure", reporter.APP, "Auto-merge PRs"])

    def test_an_unlisted_unmapped_schedule_still_raises_drift(self):
        rc, sent = run_reporter("Some new scheduled job", "success")
        self.assertEqual(rc, 0)
        self.assertEqual(len(sent), 1)
        self.assertIn("unmapped-schedule", sent[0][1]["fingerprint"])


class FailureThresholdTests(unittest.TestCase):
    def test_catch_up_needs_three_misses_in_a_row(self):
        config = reporter.monitor_config_for("Vercel production catch-up", "41 * * * *")
        self.assertEqual(config["failure_issue_threshold"], 3)
        self.assertEqual(config["recovery_threshold"], 1)
        self.assertEqual(config["checkin_margin"], 75)
        self.assertEqual(config["max_runtime"], 45)

    def test_weekly_monitor_keeps_sentry_defaults(self):
        config = reporter.monitor_config_for("Simple Icons liveness", "17 14 * * 1")
        self.assertNotIn("failure_issue_threshold", config)
        self.assertNotIn("recovery_threshold", config)
        self.assertEqual(config["checkin_margin"], 15)
        self.assertEqual(config["max_runtime"], 60)

    def test_scheduled_catch_up_checkin_carries_the_threshold(self):
        rc, sent = run_reporter("Vercel production catch-up", "success")
        self.assertEqual(rc, 0)
        checkins = [payload for item_type, payload in sent if item_type == "check_in"]
        self.assertEqual(len(checkins), 1)
        self.assertEqual(checkins[0]["status"], "ok")
        self.assertEqual(checkins[0]["monitor_slug"], f"ci-{reporter.APP}-vercel-production-catch-up")
        self.assertEqual(checkins[0]["monitor_config"]["failure_issue_threshold"], 3)


if __name__ == "__main__":
    unittest.main()
