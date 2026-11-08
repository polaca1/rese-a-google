"""Verify the actual public recovery download without changing source feeds."""
import hashlib, io, json, pathlib, plistlib, urllib.request, zipfile
output=pathlib.Path('build/watch-beta')
manifest=json.loads((output/'BETA-MANIFEST.json').read_text())
assert manifest['build']=='720' and manifest['version']=='0.7.1'
url='https://github.com/polaca1/rese-a-google/releases/download/sidestore-watch-beta-0.7.1-build720/SideStore-Watch-Beta-0.7.1-build720.ipa'
with urllib.request.urlopen(url,timeout=120) as response: data=response.read()
assert len(data)==manifest['size']
assert hashlib.sha256(data).hexdigest()==manifest['sha256']
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    assert archive.testzip() is None
    host=plistlib.loads(archive.read('Payload/SideStore.app/Info.plist'))
    assert host['CFBundleIdentifier']=='com.SideStore.SideStore.PabloWatch'
    assert host['CFBundleVersion']=='720'
    with zipfile.ZipFile(io.BytesIO(archive.read('Payload/SideStore.app/WatchBootstrap.ipa'))) as watch:
        assert watch.testzip() is None
        details=plistlib.loads(watch.read('Payload/SideStoreWatch.app/Info.plist'))
        assert details['WKApplication']
        assert details['CFBundleIdentifier']=='com.SideStore.SideStore.PabloWatch.watch'
        assert details['WKCompanionAppBundleIdentifier']=='com.SideStore.SideStore.PabloWatch'
        assert tuple(map(int,details['MinimumOSVersion'].split('.'))) <= (10,6,2)
proof={'manifest':manifest,'downloadURL':url,'verifiedPublicDownload':True,'sourceFeedsChanged':False,
       'physicalInstallationVerified':False,'renewalVerified':False}
(output/'PUBLIC-RECOVERY-VERIFICATION.json').write_text(json.dumps(proof,indent=2)+'\n')
print('Public recovery IPA verified:',manifest['size'],manifest['sha256'])
