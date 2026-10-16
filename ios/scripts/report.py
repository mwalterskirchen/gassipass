"""Prints the build errors, the test failures and the counts of a test run
from its result bundles, with `xcrun xcresulttool`, and not from the log,
whose format changes with the platform and with parallel testing.

    python3 report.py --build B.xcresult --tests T.xcresult --status 0 --log test.log

A bundle that is missing or cannot be read gives a note to read the log.
"""

import argparse
import json
import os
import re
import subprocess
import urllib.parse

parser = argparse.ArgumentParser()
parser.add_argument("--build", help="the result bundle with the build, if it has one of its own")
parser.add_argument("--tests", help="the result bundle with the tests, and with the build if it has none of its own")
parser.add_argument("--status", type=int, required=True, help="the exit status of the run")
parser.add_argument("--log", required=True)
arguments = parser.parse_args()


def read(bundle, *command):
    if not bundle or not os.path.exists(bundle):
        return None
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", *command, "--path", bundle], capture_output=True, text=True)
    return json.loads(result.stdout) if result.returncode == 0 else None


def place(url):
    """The file and the line of a source URL, which counts lines from 0."""
    if not url:
        return ""
    parts = urllib.parse.urlparse(url)
    line = urllib.parse.parse_qs(parts.fragment).get("StartingLineNumber", [None])[0]
    path = urllib.parse.unquote(parts.path)
    return f"{path}:{int(line) + 1}: " if line is not None else f"{path}: "


log = open(arguments.log, errors="replace").read() if os.path.exists(arguments.log) else ""

build = read(arguments.build or arguments.tests, "build-results")
errors = (build or {}).get("errors", [])
for error in errors[:30]:
    print(f"{place(error.get('sourceURL'))}error: {error.get('message', '').strip()}")
# The bundle places an error in a macro, for example #require, in the
# generated code. The log notes where that code comes from.
if any("swift-generated-sources" in error.get("sourceURL", "") for error in errors):
    origins = sorted(set(re.findall(r"(/\S+:\d+:\d+): note: expanded code originates here", log)))
    for origin in origins[:10]:
        print(f"{origin}: note: the macro above is expanded here")

summary = None if errors else read(arguments.tests, "test-results", "summary")
if summary is None:
    if arguments.status != 0 and not errors:
        print("The run has no result in its result bundle. See the log.")
else:
    failures = summary.get("testFailures", [])
    for failure in failures[:40]:
        print(f"✘ {failure.get('testIdentifierString') or failure.get('testName')}")
        for line in failure.get("failureText", "").strip().splitlines():
            print(f"  {line}")
    # When a test is over its time limit and does not stop, Xcode restarts
    # the test process. With two such tests at once, the bundle can miss one
    # of them, and only the log names it.
    if "Restarting after unexpected exit, crash, or test timeout" in log:
        failed = {failure.get("testName") for failure in failures}
        for name, at in dict.fromkeys(re.findall(
                r"✘ Test (\S+\)) recorded an issue at (\S+): Time limit was exceeded", log)):
            if name not in failed:
                print(f"✘ {name}, at {at}")
                print("  The time limit was exceeded, and Xcode restarted the test process.")
    counts = ", ".join(
        f"{summary.get(key, 0)} {name}"
        for key, name in [("passedTests", "passed"), ("failedTests", "failed"), ("skippedTests", "skipped")])
    print(f"{summary.get('result', 'Unknown')}: {counts} of {summary.get('totalTestCount', 0)} tests")
