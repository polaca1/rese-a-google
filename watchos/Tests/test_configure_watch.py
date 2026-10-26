import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

path = pathlib.Path(__file__).resolve().parents[1] / 'Scripts/configure-watch.py'
spec = importlib.util.spec_from_file_location('configure_watch', path)
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)

class WatchConfigurationTests(unittest.TestCase):
    def test_real_side_store_identifier_not_guessed(self):
        actual = 'com.pablo.resenagoogle.20261004.ABCDEF1234'
        data = {'result': {'apps': [{'bundleIdentifier': 'other.app', 'name': 'Other'},
                                    {'bundleIdentifier': actual, 'name': 'reviewNfcGo'}]}}
        self.assertEqual(config.choose_bundle(data), actual)

    def test_ambiguous_or_missing_app_rejected(self):
        for apps in [[], [{'bundleIdentifier': 'one.app', 'name': 'reviewNfcGo'},
                          {'bundleIdentifier': 'two.app', 'name': 'reviewNfcGo'}]]:
            with self.assertRaises(ValueError):
                config.choose_bundle({'result': {'apps': apps}})

    def test_companion_and_watch_ids_updated_together(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root / 'reviewNfcGoWatch.xcodeproj').mkdir()
            (root / 'reviewNfcGoWatch').mkdir()
            project = root / 'reviewNfcGoWatch.xcodeproj/project.pbxproj'
            project.write_text('PRODUCT_BUNDLE_IDENTIFIER = old.watch;\nPRODUCT_BUNDLE_IDENTIFIER = old.watch;')
            info = root / 'reviewNfcGoWatch/Info.plist'
            info.write_bytes(plistlib.dumps({'WKApplication': True, 'CFBundleVersion': '38'}))
            config.configure(root, 'actual.phone.app')
            self.assertEqual(project.read_text().count('actual.phone.app.watch;'), 2)
            values = plistlib.loads(info.read_bytes())
            self.assertEqual(values['WKCompanionAppBundleIdentifier'], 'actual.phone.app')
            self.assertEqual(values['CFBundleVersion'], '38')

    def test_invalid_id_never_modifies_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            for value in ['bad; value', '$(COMMAND)', '../parent', '', 'a'*240]:
                with self.assertRaises(ValueError):
                    config.configure(root, value)
            self.assertEqual(list(root.iterdir()), [])

if __name__ == '__main__':
    unittest.main()
