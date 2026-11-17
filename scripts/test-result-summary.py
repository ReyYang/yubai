#!/usr/bin/env python3
"""Print failed names and reject incomplete, cancelled or timed-out shards."""
import json
import os
from pathlib import Path
import re
import sys


def main() -> int:
    build = Path("build")
    log = (build / "xcodebuild-test.log").read_text(errors="replace") if (build / "xcodebuild-test.log").exists() else ""
    try:
        summary = json.loads((build / "test-summary.json").read_text())
    except (OSError, ValueError):
        summary = {}
    try:
        status = int((build / "test-exit-status").read_text())
    except (OSError, ValueError):
        status = None
    selectors = json.loads(os.environ["YUBAI_TEST_SELECTORS"])
    completed = set()
    failed = set()
    for target, cls, method, outcome in re.findall(r"Test Case '-\[(\w+)\.(\w+) (\w+)\]' (passed|failed|skipped)", log):
        identifier = f"{target}/{cls}/{method}"
        completed.add(identifier)
        if outcome == "failed" or (outcome == "skipped" and target == "YubaiUITests"):
            failed.add(identifier + (" (skipped)" if outcome == "skipped" else ""))
    for failure in summary.get("testFailures", []):
        failed.add(failure.get("testIdentifierString") or failure.get("testName") or str(failure))
    missing = [item for item in selectors if item.count("/") == 2 and item not in completed]
    print(f"### {os.environ.get('YUBAI_TEST_PART', 'tests')}")
    print(f"结果：{summary.get('result', '未知')}；共 {summary.get('totalTestCount', '?')} 项，"
          f"通过 {summary.get('passedTests', '?')}，失败 {summary.get('failedTests', '?')}；退出码 {status}")
    for name in sorted(failed):
        print(f"- 失败：`{name}`")
    for name in missing:
        print(f"- 未完成：`{name}`")
    if status is None:
        print("- 未写入完成标记：任务取消、中断或未启动。")
    elif status == 124:
        print("- 分片超过 30 分钟时限。")
    valid = status == 0 and summary.get("result") == "Passed" and summary.get("totalTestCount", 0) > 0
    return 0 if valid and not failed and not missing else 1


if __name__ == "__main__":
    sys.exit(main())
