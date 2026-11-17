#!/usr/bin/env python3
"""Report actual diagnostic job conclusions without changing the merge result."""
from http.client import HTTPException
import json
import os
import sys
from urllib.request import Request, urlopen


def workflow_jobs() -> list[dict]:
    # Include older attempts so a partial rerun retains successful, unrepeated jobs.
    endpoint = (f"{os.environ['GITHUB_API_URL']}/repos/{os.environ['GITHUB_REPOSITORY']}"
                f"/actions/runs/{os.environ['GITHUB_RUN_ID']}/jobs?filter=all&per_page=100")
    jobs = []
    page = 1
    while True:
        request = Request(endpoint + f"&page={page}", headers={
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer " + os.environ["GH_TOKEN"],
        })
        with urlopen(request, timeout=20) as response:
            data = json.load(response)
        jobs.extend(data["jobs"])
        if page * 100 >= data["total_count"]:
            return jobs
        page += 1


def summary(parts: list[str], jobs: list[dict]) -> str:
    latest = {}
    for job in sorted(jobs, key=lambda job: job["id"]):
        if job["name"] in parts:
            latest[job["name"]] = job
    failed = 0
    incomplete = 0
    details = []
    for part in parts:
        job = latest.get(part, {})
        result = job.get("conclusion")
        if result == "success":
            continue
        if result in ("failure", "timed_out", "startup_failure", "action_required", "stale"):
            failed += 1
        else:
            incomplete += 1
        label = f"`{part}`"
        if job.get("html_url"):
            label = f"[{label}]({job['html_url']})"
        details.append(f"- {label}: {result or 'not completed / missing'}")
    headline = f"non-blocking diagnostics: {failed} failed"
    if incomplete:
        headline += f"; {incomplete} cancelled, skipped or incomplete"
    return "\n".join([headline, "", *details]) + "\n"


def main() -> None:
    try:
        rows = [] if os.environ["MODE"] == "gallery" else json.loads(os.environ["DIAGNOSTIC_MATRIX"])["include"]
        parts = [row["part"] for row in rows]
        print(summary(parts, workflow_jobs() if parts else []), end="")
    except (OSError, ValueError, KeyError, TypeError, HTTPException) as error:
        # Reporting diagnostics must not turn their API/reporting failure into a gate.
        print(f"non-blocking diagnostics: count unavailable (jobs: {os.environ.get('DIAGNOSTICS_RESULT', 'unknown')})")
        print(f"::warning::Unable to read non-blocking diagnostic job results: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()
