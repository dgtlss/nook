"""Validate signed-feed metadata against the exact packaged application.

Archive and feed cryptographic checks run separately using Sparkle's own tool.
Never resolve XML external entities or use release metadata as shell commands.
"""
import base64
import hashlib
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def verify(release):
    with (release / 'work/Nook.app/Contents/Info.plist').open('rb') as source:
        info = plistlib.load(source)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    assert re.fullmatch(r'\d+\.\d+\.\d+', version), 'Invalid release version'
    assert re.fullmatch(r'[1-9]\d*', build), 'Build must be a positive integer'
    assert info['CFBundleIdentifier'] == 'dev.nathanlanger.Nook'
    assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32
    assert info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction']
    feed_url = info['SUFeedURL']
    parsed = urlparse(feed_url)
    assert parsed.scheme == 'https' and parsed.netloc and not parsed.username and not parsed.password
    assert not parsed.query and not parsed.fragment and parsed.path.endswith('/appcast.xml')
    feed = (release / 'appcast.xml').read_bytes()
    assert len(feed) < 1024 * 1024 and b'<!DOCTYPE' not in feed.upper() and b'<!ENTITY' not in feed.upper()
    root = ET.fromstring(feed)
    items = root.findall('./channel/item')
    assert len(items) == 1, 'Expected one full update in the generated feed'
    item = items[0]
    assert item.findtext(SPARKLE + 'version') == build, 'Feed build differs from app'
    assert item.findtext(SPARKLE + 'shortVersionString') == version, 'Feed version differs from app'
    assert item.findtext(SPARKLE + 'minimumSystemVersion') == info['LSMinimumSystemVersion']
    enclosures = item.findall('enclosure')
    assert len(enclosures) == 1, 'Expected one full DMG enclosure'
    enclosure = enclosures[0]
    filename = f'Nook-{version}-arm64.dmg'
    archive = release / filename
    expected_url = f'{feed_url.rsplit("/", 1)[0]}/versions/v{version}/{filename}'
    assert enclosure.attrib['url'] == expected_url, 'Enclosure does not point to this release'
    assert int(enclosure.attrib['length']) == archive.stat().st_size, 'Enclosure size mismatch'
    signature = enclosure.attrib[SPARKLE + 'edSignature']
    assert len(base64.b64decode(signature, validate=True)) == 64, 'Missing archive signature'
    files = []
    for name in [filename, f'Nook-{version}-arm64.zip', 'SHA256SUMS.txt', 'appcast.xml']:
        path = release / name
        files.append({'name': name, 'size': path.stat().st_size,
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return dict(version=version, build=int(build), feedURL=feed_url, publicKey=info['SUPublicEDKey'],
                archiveSignature=signature, files=files)


if __name__ == '__main__':
    try:
        print(json.dumps(verify(Path(sys.argv[1]).resolve()), indent=2))
    except (AssertionError, KeyError, ValueError, OSError, ET.ParseError) as error:
        sys.exit(f'Update verification failed: {error}')
