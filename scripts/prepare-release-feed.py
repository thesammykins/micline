#!/usr/bin/env python3
"""Fail before publication if Sparkle omitted or misaddressed the new update."""
import base64
import html
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse
import xml.etree.ElementTree as ET

ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
# Sparkle's writer creates literal sparkle:* elements, so retain that prefix.
ET.register_namespace('sparkle', ns[1:-1])
if len(sys.argv) == 3 and sys.argv[1] == '--normalize':
    # Call only on a local working copy AFTER verifying the downloaded signature.
    # This discards the old signature; the resulting feed must be signed again.
    ET.parse(sys.argv[2]).write(sys.argv[2], encoding='utf-8', xml_declaration=True)
    sys.exit(0)
feed, directory, tag, build, previous = sys.argv[1:6]
notes = Path(sys.argv[6]) if len(sys.argv) == 7 else None
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
if notes is not None:
    # Release notes deliberately use only headings, paragraphs and bullet lines.
    # Escape author text before embedding HTML in RSS; no remote notes page needed.
    paragraphs = []
    for line in notes.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith('# '):
            continue
        if line.startswith('## '):
            paragraphs.append('<h3>' + html.escape(line[3:]) + '</h3>')
        elif line.startswith('- '):
            paragraphs.append('<p>• ' + html.escape(line[2:]) + '</p>')
        else:
            paragraphs.append('<p>' + html.escape(line) + '</p>')
    if not paragraphs:
        sys.exit('Release notes must describe user-facing changes')
    description = item.find('description')
    if description is None:
        description = ET.SubElement(item, 'description')
    description.text = '\n'.join(paragraphs)

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
