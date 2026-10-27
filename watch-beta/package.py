import hashlib, json, pathlib, plistlib, shutil, subprocess, sys, zipfile
app = pathlib.Path(sys.argv[1]); output = pathlib.Path(sys.argv[2]); output.mkdir(parents=True, exist_ok=True)
info = plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.SideStore.SideStore'
assert info['CFBundleShortVersionString'] == '0.7.0'
assert info['CFBundleDisplayName'] == 'SideStore β'
assert info['CFBundleVersion'] == '701'
payload=output/'Payload';payload.mkdir(exist_ok=True);target=payload/app.name
shutil.copytree(app,target,dirs_exist_ok=True)
# Ad-hoc entitlements are templates for the installer, not a device-valid signature.
for bundle in sorted([*target.rglob('*.appex'), *target.rglob('*.app'), target], key=lambda p: len(p.parts),reverse=True):
    details=plistlib.loads((bundle/'Info.plist').read_bytes())
    ent=output/'template.plist';ent.write_bytes(plistlib.dumps({'application-identifier':'XYZ0123456.'+details['CFBundleIdentifier'],'com.apple.developer.team-identifier':'XYZ0123456','com.apple.security.application-groups':['group.com.SideStore.SideStore'],'get-task-allow':True}))
    subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ent),str(bundle)],check=True)
ipa=output/'SideStore-Watch-Beta-0.7.0-build701.ipa'
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(payload),str(ipa)],check=True)
with zipfile.ZipFile(ipa) as z: assert z.testzip() is None
sha=hashlib.sha256(ipa.read_bytes()).hexdigest()
(output/'SHA256SUMS').write_text(sha+'  '+ipa.name+'\n')
(output/'BETA-MANIFEST.json').write_text(json.dumps({'version':'0.7.0','build':'701','sha256':sha,'size':ipa.stat().st_size,'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'stage':'iphone-watch-detection-and-profile-probe','signingRequired':True,'physicalWatchDetectionVerified':False,'physicalWatchInstallationVerified':False,'renewalVerified':False,'nativeWatchStoreIncluded':False,'reusesExistingSideStoreIdentity':True,'createsNewAppIDs':False},indent=2)+'\n')
shutil.rmtree(payload);(output/'template.plist').unlink()
print('IPA packaged:',ipa.name,sha)
