#!/usr/bin/env python3
"""
Generate a minimal Sparkle-compatible appcast XML from GitHub releases.

Usage:
  python3 scripts/generate_appcast.py --output docs/appcast.xml

Requires GITHUB_REPOSITORY (owner/repo) and a GITHUB_TOKEN in env for private repos.
"""
import argparse
import os
import sys
import json
import urllib.request
import urllib.error
import xml.sax.saxutils as sax
from datetime import datetime


def iso_to_rfc2822(iso):
    # Example iso: 2024-02-05T12:34:56Z
    dt = datetime.fromisoformat(iso.replace('Z', '+00:00'))
    return dt.strftime('%a, %d %b %Y %H:%M:%S %z')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    repo = os.environ.get('GITHUB_REPOSITORY')
    token = os.environ.get('GITHUB_TOKEN')
    if not repo:
        print('GITHUB_REPOSITORY not set', file=sys.stderr)
        sys.exit(2)

    headers = {'Accept': 'application/vnd.github+json'}
    if token:
        headers['Authorization'] = f'token {token}'

    api = f'https://api.github.com/repos/{repo}/releases'
    req = urllib.request.Request(api, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            releases = json.load(resp)
    except urllib.error.HTTPError as e:
        print(f'Failed to fetch releases (HTTP): {e}', file=sys.stderr)
        sys.exit(3)
    except urllib.error.URLError as e:
        print(f'Failed to fetch releases (network): {e}', file=sys.stderr)
        sys.exit(3)
    except json.JSONDecodeError as e:
        print(f'Failed to parse GitHub API response as JSON: {e}', file=sys.stderr)
        sys.exit(4)

    items = []
    for rel in releases:
        tag = rel.get('tag_name')
        title = rel.get('name') or tag
        notes_url = rel.get('html_url')
        pub = rel.get('published_at') or rel.get('created_at')
        assets = rel.get('assets', [])
        # Choose a single preferred asset per release to avoid duplicate entries.
        # Preference order: .zip, .dmg, .pkg
        preferred = None
        preferred_prio = None
        ext_priority = {'.zip': 0, '.dmg': 1, '.pkg': 2}
        for a in assets:
            name = (a.get('name') or '').lower()
            for ext, prio in ext_priority.items():
                if name.endswith(ext):
                    if preferred is None or prio < preferred_prio:
                        preferred = a
                        preferred_prio = prio
                    break

        if not preferred:
            continue

        download_url = preferred.get('browser_download_url')
        size = preferred.get('size', 0)
        version = tag.lstrip('v') if tag else ''
        items.append({
            'title': title,
            'notes': notes_url,
            'pubDate': iso_to_rfc2822(pub) if pub else '',
            'url': download_url,
            'length': str(size),
            'version': version,
        })

    # Build XML
    repo_url = f'https://github.com/{repo}'
    xml = ['<?xml version="1.0" encoding="utf-8"?>',
           '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">',
           '<channel>',
           f'<title>{sax.escape(repo)} updates</title>',
           f'<link>{sax.escape(repo_url)}</link>',
           '<description>App updates generated from GitHub Releases</description>',
           '<!-- WARNING: This generated appcast does NOT include Sparkle signatures.\n                 Do NOT use unsigned updates in production.\n                 Sign your update archives with EdDSA (Ed25519) and include sparkle:edSignature attributes in the enclosure elements. -->']

    for it in items:
        xml.append('<item>')
        xml.append(f'<title>{sax.escape(it["title"])}</title>')
        xml.append(f'<sparkle:releaseNotesLink>{sax.escape(it["notes"])}</sparkle:releaseNotesLink>')
        xml.append(f'<pubDate>{sax.escape(it["pubDate"])}</pubDate>')
        xml.append(f'<enclosure url="{sax.escape(it["url"])}" sparkle:version="{sax.escape(it["version"])}" sparkle:shortVersionString="{sax.escape(it["version"])}" length="{sax.escape(it["length"])}" type="application/octet-stream" />')
        xml.append('</item>')

    xml.append('</channel>')
    xml.append('</rss>')

    outdir = os.path.dirname(args.output)
    if outdir and not os.path.exists(outdir):
        os.makedirs(outdir, exist_ok=True)

    with open(args.output, 'w', encoding='utf-8') as f:
        f.write('\n'.join(xml))

    print('Wrote', args.output)


if __name__ == '__main__':
    main()
