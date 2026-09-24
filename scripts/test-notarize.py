"""Exercise the acceptance gate without credentials or Apple submissions."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().with_name("notarize.sh")


class NotarizationGateTests(unittest.TestCase):
    def run_gate(self, status="Accepted", issues=None, submit_exit=0, malformed=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "MicLine.zip"
            archive.write_bytes(b"fixture")
            submission = {"data": {"id": "fixture-id", "attributes": {"status": status}}}
            (root / "submission.json").write_text("invalid" if malformed else json.dumps(submission))
            (root / "log.json").write_text(json.dumps({"status": status, "issues": issues}))
            asc = root / "asc"
            asc.write_text('''#!/bin/sh
if [ "$2" = submit ]; then
    cat "$FIXTURE_ROOT/submission.json"
    exit "$FIXTURE_EXIT"
fi
printf '%s' '{"data":{"attributes":{"developerLogUrl":"https://example.invalid/log"}}}'
''')
            curl = root / "curl"
            curl.write_text('''#!/bin/sh
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then
        cp "$FIXTURE_ROOT/log.json" "$2"
        exit
    fi
    shift
done
exit 1
''')
            asc.chmod(0o755)
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       ASC_PROFILE="fixture-only", FIXTURE_ROOT=str(root),
                       FIXTURE_EXIT=str(submit_exit))
            return subprocess.run([str(SCRIPT), str(archive), str(root / "evidence")],
                                  env=env, capture_output=True, text=True)

    def test_accepts_clean_log(self):
        self.assertEqual(self.run_gate().returncode, 0)

    def test_rejects_invalid_submission(self):
        self.assertNotEqual(self.run_gate(status="Invalid", submit_exit=1).returncode, 0)

    def test_rejects_pending_submission(self):
        self.assertNotEqual(self.run_gate(status="In Progress").returncode, 0)

    def test_rejects_logged_issues_even_when_accepted(self):
        self.assertNotEqual(self.run_gate(issues=[{"severity": "warning"}]).returncode, 0)

    def test_rejects_transport_failure_even_with_accepted_output(self):
        self.assertNotEqual(self.run_gate(submit_exit=1).returncode, 0)

    def test_rejects_malformed_output(self):
        self.assertNotEqual(self.run_gate(malformed=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
