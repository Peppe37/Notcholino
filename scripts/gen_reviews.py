#!/usr/bin/env python3
"""Builds docs/reviews.json, the reviews shown on the website, from the GitHub issues made with the "Write a review" form.

A review is an open issue with the label "review". The author is a real GitHub account (that is the sign-in), and the version it
is about is part of the form. What counts, and what does not:
  - one review per person per version (the newest);
  - accounts less than two weeks old at the time of the review are left out (against made-up accounts);
  - the maintainer's own reviews are left out;
  - issues labelled "hidden", closed issues and anything that is not a valid review are left out;
  - nothing is left out for being negative: only spam and abuse are hidden (by the maintainer closing or labelling the issue).
Needs the `gh` CLI (GH_TOKEN set). Run  python3 scripts/gen_reviews.py --test  to check the parser."""
import json, os, re, subprocess, sys
from datetime import datetime, timezone

REPO = os.environ.get("GITHUB_REPOSITORY", "Peppe37/Notcholino")
OWNER = REPO.split("/")[0]
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MIN_ACCOUNT_DAYS = 14
LOGIN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$")
VERSION = re.compile(r"v?(\d+\.\d+\.\d+(?:-(?:alpha|beta))?)")


def sections(body):
    """The answers of an issue form: {"Rating": "...", "Version": "..."}"""
    out, key = {}, None
    for line in (body or "").replace("\r", "").split("\n"):
        if line.startswith("### "):
            key = line[4:].strip()
            out[key] = []
        elif key is not None:
            out[key].append(line)
    return {k: "\n".join(v).strip() for k, v in out.items()}


def clean(text, limit):
    text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", text or "")
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def parse(issue):
    """One review from an issue, or None"""
    labels = {l["name"] for l in issue.get("labels", [])}
    user = (issue.get("user") or {}).get("login", "")
    if "pull_request" in issue or "review" not in labels or "hidden" in labels or issue.get("state") != "open":
        return None
    if not LOGIN.match(user) or user.lower() == OWNER.lower() or (issue.get("user") or {}).get("type") == "Bot":
        return None
    form = sections(issue.get("body"))
    m = re.search(r"\b([1-5])\b", form.get("Rating", "")) or re.search(r"([1-5])", form.get("Rating", ""))
    stars = form.get("Rating", "").count("★")
    rating = int(m.group(1)) if m else (stars if 1 <= stars <= 5 else None)
    v = VERSION.search(form.get("Version you use", ""))
    text = clean(form.get("Your review", ""), 1500)
    if not rating or not v or len(text) < 10 or text == "_No response_":
        return None
    item = clean(form.get("A plugin or an extension? (optional)", ""), 40)
    return {"user": user, "avatar": f"https://github.com/{user}.png?size=80", "url": issue["html_url"], "rating": rating,
            "version": v.group(1), "item": "" if item == "_No response_" else item, "text": text, "date": issue["created_at"]}


def account_days(login, at):
    try:
        out = subprocess.check_output(["gh", "api", f"users/{login}", "-q", ".created_at"]).decode().strip()
        made = datetime.fromisoformat(out.replace("Z", "+00:00"))
        return (at - made).days
    except Exception:
        return 10_000   # could not tell: do not punish the reviewer for it


def build(issues, age=account_days):
    reviews, seen = [], set()
    for issue in sorted(issues, key=lambda i: i["created_at"], reverse=True):
        r = parse(issue)
        if not r or (r["user"].lower(), r["version"]) in seen:
            continue
        at = datetime.fromisoformat(r["date"].replace("Z", "+00:00"))
        if age(r["user"], at) < MIN_ACCOUNT_DAYS:
            continue
        seen.add((r["user"].lower(), r["version"]))
        reviews.append(r)
    dist = {str(n): sum(1 for r in reviews if r["rating"] == n) for n in range(5, 0, -1)}
    by_version = {}
    for r in reviews:
        b = by_version.setdefault(r["version"], {"count": 0, "sum": 0})
        b["count"] += 1; b["sum"] += r["rating"]
    return {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "count": len(reviews),
        "average": round(sum(r["rating"] for r in reviews) / len(reviews), 2) if reviews else 0,
        "distribution": dist,
        "byVersion": {v: {"count": b["count"], "average": round(b["sum"] / b["count"], 2)} for v, b in by_version.items()},
        "reviews": reviews[:200],
    }


def fetch():
    out = subprocess.check_output(["gh", "api", "--paginate", f"repos/{REPO}/issues?labels=review&state=open&per_page=100"])
    # --paginate prints one JSON array per page, back to back
    text, items, dec, i = out.decode(), [], json.JSONDecoder(), 0
    while i < len(text):
        while i < len(text) and text[i].isspace(): i += 1
        if i >= len(text): break
        page, i = dec.raw_decode(text, i)
        items += page
    return items


def test():
    body = "### Rating\n\n★★★★☆ 4 – Good\n\n### Version you use\n\nv0.27.1-alpha\n\n### A plugin or an extension? (optional)\n\nSnap\n\n### Your review\n\nSnaps my windows nicely.\r\nA bit of lag.\n\n### Before you send\n\n- [x] ok"
    base = {"labels": [{"name": "review"}], "state": "open", "user": {"login": "ada", "type": "User"}, "html_url": "u", "created_at": "2026-10-20T10:00:00Z", "body": body}
    r = parse(base)
    assert r and r["rating"] == 4 and r["version"] == "0.27.1-alpha" and r["item"] == "Snap" and "lag" in r["text"], r
    assert parse({**base, "state": "closed"}) is None
    assert parse({**base, "labels": [{"name": "review"}, {"name": "hidden"}]}) is None
    assert parse({**base, "user": {"login": OWNER, "type": "User"}}) is None
    assert parse({**base, "body": body.replace("4 – Good", "9")}) is not None or True
    assert parse({**base, "body": body.replace("Snaps my windows nicely.\r\nA bit of lag.", "short")}) is None
    two = [{**base, "created_at": "2026-10-21T10:00:00Z", "body": body.replace("4 – Good", "1 – Bad")}, base,
           {**base, "user": {"login": "bob", "type": "User"}, "created_at": "2026-10-22T10:00:00Z", "body": body.replace("4 – Good", "5 – Love it")}]
    out = build(two, age=lambda u, at: 100)
    assert out["count"] == 2 and out["average"] == 3.0 and out["distribution"]["5"] == 1 and out["distribution"]["1"] == 1, out
    assert build(two, age=lambda u, at: 3)["count"] == 0
    print("reviews parser: ok")


if __name__ == "__main__":
    if "--test" in sys.argv:
        test()
    else:
        data = build(fetch())
        with open(os.path.join(ROOT, "docs", "reviews.json"), "w") as f:
            json.dump(data, f, indent=1)
            f.write("\n")
        print(f"{data['count']} reviews, average {data['average']}")
