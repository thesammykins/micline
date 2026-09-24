#!/usr/bin/env python3
"""Release boundary regressions, without credentials or network writes."""
import base64
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'

class ReleaseTests(unittest.TestCase):
    def test_versions_are_ordered_and_reject_unsafe_tags(self):
        versions = ['v0.1.0', 'v0.1.1', 'v0.2.0', 'v1.0.0']
        builds = []
        for tag in versions:
            result = subprocess.run([str(ROOT / 'release-version.py'), tag], capture_output=True, text=True, check=True)
            builds.append(int(result.stdout.split('MICLINE_BUILD_NUMBER=')[1]))
        self.assertEqual(builds, sorted(set(builds)))
        for tag in ['v0.0.0', 'v01.2.3', 'v1.1000.0', 'v1.2.3-beta', 'v1.2.3\nBAD=value', '../../bad']:
            result = subprocess.run([str(ROOT / 'release-version.py'), tag], capture_output=True)
            self.assertNotEqual(result.returncode, 0, tag)

    def test_previous_urls_survive_new_release_and_missing_assets_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / 'MicLine-0.2.0.dmg'
            archive.write_bytes(b'archive fixture')
            signature = base64.b64encode(bytes(64)).decode()
            def item(version, url, length):
                return f'<item><sparkle:version>{version}</sparkle:version><sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion><enclosure url="{url}" length="{length}" sparkle:edSignature="{signature}"/></item>'
            def feed(items):
                return f'<rss xmlns:sparkle="{NS[1:-1]}"><channel>{items}</channel></rss>'
            old_url = 'https://github.com/thesammykins/micline/releases/download/v0.1.0/MicLine-0.1.0.dmg'
            new_url = 'https://github.com/thesammykins/micline/releases/download/v0.2.0/MicLine-0.2.0.dmg'
            previous = root / 'previous.xml'
            previous.write_text(feed(item('1000', old_url, 1)))
            current = root / 'appcast.xml'
            current.write_text(feed(item('2000', new_url, archive.stat().st_size) + item('1000', old_url.replace('download/v0.1.0/', 'download/v0.2.0/'), 1)))
            notes = root / 'notes.md'
            notes.write_text('# Release\n\n## Fixes\n- Recover checks & preserve <input>.\n')
            cmd = ['python3', str(ROOT / 'prepare-release-feed.py'), str(current), str(root), 'v0.2.0', '2000', str(previous), str(notes)]
            subprocess.run(cmd, capture_output=True, check=True)
            self.assertIn("Recover checks &amp; preserve &lt;input&gt;.", ET.parse(current).findtext("./channel/item/description"))
            items = ET.parse(current).getroot().findall('./channel/item')
            self.assertEqual(items[1].find('enclosure').get('url'), old_url)
            archive.unlink()
            self.assertNotEqual(subprocess.run(cmd, capture_output=True).returncode, 0)

if __name__ == '__main__':
    unittest.main()
