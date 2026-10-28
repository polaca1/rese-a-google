import hashlib, json, pathlib, plistlib, shutil, subprocess, sys, zipfile, tempfile
app = pathlib.Path(sys.argv[1]); output = pathlib.Path(sys.argv[2]); output.mkdir(parents=True, exist_ok=True)
info = plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.SideStore.SideStore'
assert info['CFBundleShortVersionString'] == '0.7.1'
assert info['CFBundleDisplayName'] == 'SideStore β'
assert info['CFBundleVersion'] == '714'
payload=output/'Payload';payload.mkdir(exist_ok=True);target=payload/app.name
shutil.copytree(app,target,dirs_exist_ok=True)
bootstrap = pathlib.Path(__file__).resolve().parents[1]/'build/native-watch/WatchBootstrap.ipa'
assert bootstrap.exists(), 'Native Watch payload must be built before packaging'
shutil.copyfile(bootstrap, target/'WatchBootstrap.ipa')
shutil.copyfile(pathlib.Path(__file__).parent/'THIRD-PARTY-NOTICES.txt',target/'WatchInstaller-LICENSE.txt')
# Preserve the embedded SideBackup helper's app-group entitlement, as upstream's
# fakesign-sidebackup does. The helper is an IPA resource, not an embedded .app.
helper = target/'SideBackup.ipa'
assert helper.exists(), 'Missing original SideBackup helper'
with tempfile.TemporaryDirectory() as directory:
    temporary = pathlib.Path(directory)
    with zipfile.ZipFile(helper) as archive:
        assert archive.testzip() is None
        for entry in archive.infolist():
            relative = pathlib.PurePosixPath(entry.filename)
            assert not relative.is_absolute() and '..' not in relative.parts
            assert not ((entry.external_attr >> 16) & 0o170000) == 0o120000
        archive.extractall(temporary)
    helpers = list((temporary/'Payload').glob('*.app')); assert len(helpers) == 1
    details = plistlib.loads((helpers[0]/'Info.plist').read_bytes())
    assert details['CFBundleIdentifier'] == 'com.SideStore.SideStore.SideBackup'
    template = temporary/'helper-entitlements.plist'
    template.write_bytes(plistlib.dumps({'com.apple.security.application-groups':['group.com.SideStore.SideStore']}))
    subprocess.run(['codesign','--force','--sign','-','--entitlements',str(template),str(helpers[0])],check=True)
    verification = subprocess.run(['codesign','-d','--entitlements',':-',str(helpers[0])],capture_output=True,check=True).stdout
    assert plistlib.loads(verification)['com.apple.security.application-groups'] == ['group.com.SideStore.SideStore']
    helper.unlink()
    subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(temporary/'Payload'),str(helper)],check=True)
    with zipfile.ZipFile(helper) as archive: assert archive.testzip() is None

# Ad-hoc entitlements are templates for the installer, not a device-valid signature.
for bundle in sorted([*target.rglob('*.appex'), *target.rglob('*.app'), target], key=lambda p: len(p.parts),reverse=True):
    details=plistlib.loads((bundle/'Info.plist').read_bytes())
    ent=output/'template.plist';ent.write_bytes(plistlib.dumps({'application-identifier':'XYZ0123456.'+details['CFBundleIdentifier'],'com.apple.developer.team-identifier':'XYZ0123456','com.apple.security.application-groups':['group.com.SideStore.SideStore'],'get-task-allow':True}))
    subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ent),str(bundle)],check=True)
ipa=output/'SideStore-Watch-Beta-0.7.1-build714.ipa'
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(payload),str(ipa)],check=True)
with zipfile.ZipFile(ipa) as z: assert z.testzip() is None
sha=hashlib.sha256(ipa.read_bytes()).hexdigest()
(output/'SHA256SUMS').write_text(sha+'  '+ipa.name+'\n')
(output/'BETA-MANIFEST.json').write_text(json.dumps({'version':'0.7.1','build':'714','sha256':sha,'size':ipa.stat().st_size,'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'stage':'automatic-embedded-watch-and-native-bootstrap','signingRequired':True,'physicalWatchDetectionVerified':False,'physicalWatchInstallationVerified':False,'renewalVerified':False,'nativeWatchStoreIncluded':False,'nativeWatchBootstrapIncluded':True,'watchMinimumOS':'10.0','reusesExistingSideStoreIdentity':True,'createsNewAppIDs':False},indent=2)+'\n')
shutil.rmtree(payload);(output/'template.plist').unlink()
print('IPA packaged:',ipa.name,sha)
