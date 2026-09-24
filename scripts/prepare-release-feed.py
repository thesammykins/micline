#!/usr/bin/env python3
"""Fail before publication if Sparkle omitted or misaddressed the new update."""
import base64
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse
import xml.etree.ElementTree as ET

feed, directory, tag, build, previous = sys.argv[1:]
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
tree = ET.parse(feed)
root = tree.getroot()
channel = root.find('channel')
if channel is None:
    sys.exit('Missing appcast channel')
if previous:
    old_items = {item.findtext(ns + 'version'): item for item in ET.parse(previous).getroot().findall('./channel/item')}
    for index, item in enumerate(list(channel)):
        version = item.findtext(ns + 'version')
        if item.tag == 'item' and version != build and version in old_items:
            channel.remove(item)
            channel.insert(index, old_items[version])
items = [item for item in root.findall('./channel/item') if item.findtext(ns + 'version') == build]
if len(items) != 1:
    sys.exit('Expected exactly one feed item for this build')
item = items[0]
if item.findtext(ns + 'minimumSystemVersion') != '27.0':
    sys.exit('Unexpected minimum system version')
full = item.find('enclosure')
if full is None:
    sys.exit('Missing full archive fallback')
for enclosure in [full, *item.findall(f'{ns}deltas/enclosure')]:
    url = enclosure.get('url', '')
    prefix = f'https://github.com/thesammykins/micline/releases/download/{tag}/'
    if not url.startswith(prefix):
        sys.exit('Unexpected release asset URL')
    name = unquote(urlparse(url).path.rsplit('/', 1)[-1])
    if '/' in name or '\\' in name or name in ('', '.', '..'):
        sys.exit('Invalid asset name')
    path = Path(directory) / name
    if not path.is_file() or str(path.stat().st_size) != enclosure.get('length'):
        sys.exit('Missing asset or incorrect length')
    try:
        signature = base64.b64decode(enclosure.get(ns + 'edSignature', ''), validate=True)
    except ValueError:
        sys.exit('Invalid asset signature')
    if len(signature) != 64:
        sys.exit('Missing asset signature')
print('Validated signed full archive and available delta metadata')

# Signing follows this serialization; never modify the feed afterward.
tree.write(feed, encoding="utf-8", xml_declaration=True)
