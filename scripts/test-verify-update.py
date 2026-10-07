import copy
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('verify_update', Path(__file__).with_name('verify-update.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FeedMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.release = Path(self.temp.name)
        self.plist = self.release / 'work/Nook.app/Contents/Info.plist'
        self.plist.parent.mkdir(parents=True)
        self.info = dict(CFBundleIdentifier='dev.nathanlanger.Nook', CFBundleVersion='8',
                         CFBundleShortVersionString='0.1.7', LSMinimumSystemVersion='27.0',
                         SUFeedURL='https://example.com/nook/appcast.xml',
                         SUPublicEDKey='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
                         SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True)
        self.write_info(self.info)
        self.feed = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>8</sparkle:version><sparkle:shortVersionString>0.1.7</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion>
<enclosure url="https://example.com/nook/versions/v0.1.7/Nook-0.1.7-arm64.dmg" length="3"
sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="/>
</item></channel></rss>'''
        self.feed_path = self.release / 'appcast.xml'
        self.feed_path.write_text(self.feed)
        for name in ['Nook-0.1.7-arm64.dmg', 'Nook-0.1.7-arm64.zip', 'SHA256SUMS.txt']:
            (self.release / name).write_bytes(b'abc')

    def write_info(self, info):
        self.plist.write_bytes(plistlib.dumps(info))

    def test_matching_metadata(self):
        manifest = module.verify(self.release)
        self.assertEqual(manifest['build'], 8)
        self.assertEqual(len(manifest['files']), 4)

    def test_wrong_build_size_host_and_minimum_os_are_rejected(self):
        for old, new in [('>8<', '>9<'), ('length="3"', 'length="4"'),
                         ('https://example.com/nook/versions', 'https://unrelated.example/versions'),
                         ('>27.0<', '>26.0<')]:
            with self.subTest(new=new):
                self.feed_path.write_text(self.feed.replace(old, new))
                with self.assertRaises(AssertionError):
                    module.verify(self.release)

    def test_insecure_feed_configuration_is_rejected(self):
        for value in ['http://example.com/nook/appcast.xml', 'https://user:secret@example.com/appcast.xml',
                      'https://example.com/appcast.xml?key=secret']:
            with self.subTest(value=value):
                info = copy.copy(self.info)
                info['SUFeedURL'] = value
                self.write_info(info)
                with self.assertRaises(AssertionError):
                    module.verify(self.release)

    def test_external_entity_and_duplicate_update_are_rejected(self):
        for feed in ['<!DOCTYPE rss [<!ENTITY file SYSTEM "file:///etc/passwd">]>' + self.feed,
                     self.feed.replace('</channel>', '<item/></channel>')]:
            self.feed_path.write_text(feed)
            with self.assertRaises(AssertionError):
                module.verify(self.release)


if __name__ == '__main__':
    unittest.main()
