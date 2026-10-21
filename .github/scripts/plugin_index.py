#!/usr/bin/env python3
"""Write Alakazam's plugin index.

The index is GitHub's answers to the requests Install plugins makes about an
account's Alakazam repositories: the account's repositories, and for each
Alakazam one its file tree and its latest release. Alakazam downloads them in
one go (Plugins.IndexAddress, an asset of the pre-release "plugin-index")
instead of asking GitHub's API, which answers only 60 requests an hour from
one network address without a token, and the list costs 23.

The answers are saved as GitHub gave them, under the exact addresses
Plugins.available asks, trimmed to the fields Alakazam reads, and Alakazam
reads them with the code it reads GitHub with (listFrom in Plugins.m). So
nothing is decided here: which folder is a plugin and which release asset is
its zip are decided there, once. Only what is asked mirrors it: the same
pages of repositories, and every repository named Alakazam<something>.

Usage: plugin_index.py ACCOUNT OUTPUT
Asks through the GitHub CLI (gh api), as whoever it is logged in as: the
workflow's token in the Plugin index workflow, which renews the asset every
day, and in the Manual site workflow, which keeps a copy on the Pages site
for the versions of Alakazam that read it there.
"""
import datetime
import json
import subprocess
import sys

API = "https://api.github.com/"


def ask(url):
    """GitHub's answer to URL: its status and its decoded body (None when it
    has none)."""
    run = subprocess.run(["gh", "api", "--include", url[len(API):]],
                         capture_output=True, text=True, encoding="utf-8")
    text = run.stdout.replace("\r\n", "\n")
    head, _, body = text.partition("\n\n")
    first = head.split("\n", 1)[0].split()
    if len(first) < 2 or not first[1].isdigit():
        raise RuntimeError(f"no answer from GitHub for {url}: {run.stderr.strip()}")
    status = int(first[1])
    try:
        decoded = json.loads(body) if body.strip() else None
    except json.JSONDecodeError:
        decoded = None
    return status, decoded


def trimmed(url, body):
    """BODY with only the fields Alakazam reads (Plugins.m: listFrom,
    toolsInTree, zipAsset), so the index stays small."""
    if "/users/" in url:
        return [{"name": r.get("name"), "description": r.get("description"),
                 "default_branch": r.get("default_branch")} for r in body]
    if "/git/trees/" in url:
        # toolsInTree looks for <Name>/<Name>.json beside <Name>/<Name>.m.
        return {"tree": [{"path": e["path"]} for e in body.get("tree", [])
                         if e.get("path", "").endswith((".json", ".m"))]}
    if url.endswith("/releases/latest"):
        return {"tag_name": body.get("tag_name"),
                "assets": [{"name": a.get("name"),
                            "browser_download_url": a.get("browser_download_url")}
                           for a in body.get("assets", [])]}
    return body


def main(account, output):
    responses = []

    def record(url):
        status, body = ask(url)
        if status == 200:
            body = trimmed(url, body)
        else:
            body = None
        responses.append({"url": url, "status": status, "body": body})
        return status, body

    repositories = []
    for page in range(1, 11):            # as Plugins.available pages them
        url = f"{API}users/{account}/repos?per_page=100&page={page}"
        status, batch = record(url)
        if status != 200:
            sys.exit(f"GitHub answered {status} for {url}; no index written.")
        repositories += batch
        if len(batch) < 100:
            break

    for r in repositories:
        name = r["name"] or ""
        if not name.startswith("Alakazam") or name == "Alakazam":
            continue
        api = f"{API}repos/{account}/{name}"
        record(f"{api}/git/trees/{r['default_branch'] or 'main'}?recursive=1")
        record(f"{api}/releases/latest")

    index = {
        "format": 1,
        "account": account,
        "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "responses": responses,
    }
    with open(output, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1, ensure_ascii=False)
        f.write("\n")
    held = sum(1 for r in responses if "/releases/latest" in r["url"])
    print(f"{output}: {len(responses)} answers about {held} repositories of {account}.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
