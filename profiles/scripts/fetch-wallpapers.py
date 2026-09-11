#!/usr/bin/env python3
"""Download a 4K rotation-pool wallpaper set from wallhaven into
~/Pictures/wallpapers (skips existing files). Re-run to top up the pool."""
import os
import sys
import urllib.parse
import urllib.request

QUERIES = ["nature landscape", "mountain lake", "colorful abstract", "aurora night"]
PER_QUERY = 2
MIN_W = 3840

BASE = os.path.expanduser("~/Pictures/wallpapers")
os.makedirs(BASE, exist_ok=True)


def get(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json_load(r)


import json


def json_load(r):
    return json.load(r)


def download(url: str, fn: str) -> bool:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r, open(fn, "wb") as f:
        f.write(r.read())
    return True


def main() -> int:
    fetched = 0
    for q in QUERIES:
        params = urllib.parse.urlencode({
            "q": q, "categories": "111", "purity": "100",
            "atleast": "3840x2160", "sorting": "random",
        })
        try:
            data = get("https://wallhaven.cc/api/v1/search?" + params).get("data", [])
        except Exception as e:
            print(f"query '{q}' failed: {e}")
            continue
        for w in data:
            if fetched >= PER_QUERY * len(QUERIES):
                break
            path = w.get("path", "")
            if not path:
                continue
            fn = os.path.join(BASE, os.path.basename(path))
            if os.path.exists(fn):
                continue
            try:
                download(path, fn)
                fetched += 1
                print(f"  {w.get('resolution')} {fn}")
            except Exception as e:
                print(f"  download {path} failed: {e}")
        if fetched >= PER_QUERY * len(QUERIES):
            break
    print(f"done: {fetched} wallpaper(s) in {BASE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
