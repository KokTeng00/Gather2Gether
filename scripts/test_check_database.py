"""Exercise registry failures without Docker, network access or actual delays."""

import io
import subprocess
import unittest
from unittest.mock import patch

import check_database


class PrepareImageTests(unittest.TestCase):
    def setUp(self):
        self.images = check_database.POSTGRES_IMAGES
        self.log = io.StringIO()
        self.calls = []
        self.pull_results = []
        self.cached = set()
        self.run_patch = patch.object(check_database.subprocess, "run", self.docker)
        self.run_patch.start()
        self.addCleanup(self.run_patch.stop)
        self.sleep_patch = patch.object(check_database.time, "sleep")
        self.sleep = self.sleep_patch.start()
        self.addCleanup(self.sleep_patch.stop)

    def docker(self, command, **kwargs):
        if command[1:3] == ["image", "inspect"]:
            return subprocess.CompletedProcess(command, 0 if command[-1] in self.cached else 1)
        self.assertEqual(command[:2], ["docker", "pull"])
        self.calls.append(command[-1])
        self.assertGreater(kwargs["timeout"], 0)
        self.assertLessEqual(kwargs["timeout"], 180)
        result = self.pull_results.pop(0)
        if isinstance(result, Exception):
            raise result
        return subprocess.CompletedProcess(command, result)

    def test_cached_mirror_needs_no_network(self):
        self.cached.add(self.images[1])
        self.assertEqual(check_database.prepare_image(self.images, self.log), self.images[1])
        self.assertEqual(self.calls, [])

    def test_registry_failure_uses_same_digest_from_other_official_source(self):
        self.pull_results = [1, 0]
        self.assertEqual(check_database.prepare_image(self.images, self.log), self.images[1])
        self.assertEqual(self.calls, list(self.images))
        self.assertEqual(len({image.split("@")[1] for image in self.calls}), 1)

    def test_timeout_can_recover_from_other_source(self):
        self.pull_results = [subprocess.TimeoutExpired("docker pull", 180), 0]
        self.assertEqual(check_database.prepare_image(self.images, self.log), self.images[1])

    def test_transient_failure_gets_one_retry(self):
        self.pull_results = [1, 1, 0]
        self.assertEqual(check_database.prepare_image(self.images, self.log), self.images[0])
        self.sleep.assert_called_once_with(5)

    def test_unavailable_registries_fail_instead_of_skipping_database_tests(self):
        self.pull_results = [1, 1, 1, 1]
        with self.assertRaisesRegex(RuntimeError, "Could not download"):
            check_database.prepare_image(self.images, self.log)
        self.assertEqual(self.calls, list(self.images) * 2)

    def test_overall_time_budget_stops_more_pulls(self):
        self.pull_results = [1]
        with patch.object(check_database.time, "monotonic", side_effect=[0, 0, 301, 301, 301]):
            with self.assertRaisesRegex(RuntimeError, "Could not download"):
                check_database.prepare_image(self.images, self.log)
        self.assertEqual(self.calls, [self.images[0]])


if __name__ == "__main__":
    unittest.main()
