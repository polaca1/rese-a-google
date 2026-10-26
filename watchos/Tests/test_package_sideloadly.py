import importlib.util
import pathlib
import plistlib
import tempfile
import unittest
import zipfile
p = pathlib.Path(__file__).resolve().parents[1] / 'Scripts/package-sideloadly.py'
s = importlib.util.spec_from_file_location('package_sideloadly',p);module = importlib.util.module_from_spec(s);s.loader.exec_module(module)
class PackagingTests(unittest.TestCase):
    def fixtures(self, root, version='7.3.0', companion='com.pablo.resenagoogle.20261004'):
        phone=root/'phone.ipa';watch=root/'watch.zip'
        a={'CFBundleIdentifier':'com.pablo.resenagoogle.20261004','CFBundleShortVersionString':'7.3.0','CFBundleVersion':'39'}
        b={'CFBundleIdentifier':'com.pablo.resenagoogle.20261004.watch','CFBundleShortVersionString':version,'CFBundleVersion':'39','WKApplication':True,'WKCompanionAppBundleIdentifier':companion,'CFBundleExecutable':'Watch'}
        with zipfile.ZipFile(phone,'w') as z:z.writestr(module.PHONE+'Info.plist',plistlib.dumps(a));z.writestr(module.PHONE+'Original','phone-bytes')
        with zipfile.ZipFile(watch,'w') as z:z.writestr(module.WATCH+'Info.plist',plistlib.dumps(b));z.writestr(module.WATCH+'Watch','watch-bytes')
        return phone,watch
    def test_embed_without_modifying_original_phone(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d);phone,watch=self.fixtures(root);before=phone.read_bytes();output=root/'combined.ipa';r=module.package(phone,watch,output)
            self.assertEqual(phone.read_bytes(),before);self.assertTrue(r['signingRequired'])
            with zipfile.ZipFile(output) as z:self.assertEqual(z.read(module.PHONE+'Watch/'+module.WATCH+'Watch'),b'watch-bytes');self.assertEqual(z.read(module.PHONE+'Original'),b'phone-bytes')
    def test_wrong_version_and_companion_rejected(self):
        for version,companion in [('7.2.0',module.PHONE),('7.3.0','other.app')]:
            with tempfile.TemporaryDirectory() as d:
                root=pathlib.Path(d);phone,watch=self.fixtures(root,version,companion)
                with self.assertRaises(ValueError):module.package(phone,watch,root/'out.ipa')
                self.assertFalse((root/'out.ipa').exists())
    def test_no_replacement_of_original_or_existing_output(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d);phone,watch=self.fixtures(root)
            with self.assertRaises(ValueError):module.package(phone,watch,phone)
            out=root/'out.ipa';out.write_bytes(b'existing')
            with self.assertRaises(ValueError):module.package(phone,watch,out)
            self.assertEqual(out.read_bytes(),b'existing')
    def test_zip_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d);phone,watch=self.fixtures(root)
            with zipfile.ZipFile(watch,'a') as z:z.writestr('../outside','bad')
            with self.assertRaises(ValueError):module.package(phone,watch,root/'out.ipa')
if __name__=='__main__':unittest.main()
