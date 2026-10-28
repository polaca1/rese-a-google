import pathlib, shutil, subprocess, plistlib, zipfile
root=pathlib.Path(__file__).resolve().parents[1]
native=root/'watch-beta/native'
assets=native/'SideStoreWatch/Assets.xcassets/AppIcon.appiconset'
assets.mkdir(parents=True,exist_ok=True)
shutil.copyfile(root/'AltStore/Resources/Assets.xcassets/SideStore.imageset/1024.png',assets/'AppIcon.png')
output=root/'build/native-watch'
output.mkdir(parents=True,exist_ok=True)
log=output/'build.log'
with log.open('w') as stream:
    result=subprocess.run(['xcodebuild','-project',str(native/'SideStoreWatch.xcodeproj'),'-scheme','SideStoreWatch','-configuration','Release','-sdk','watchos','-destination','generic/platform=watchOS','-derivedDataPath',str(output/'DerivedData'),'CODE_SIGNING_ALLOWED=NO','build'],stdout=stream,stderr=subprocess.STDOUT)
if result.returncode:
    print(log.read_text()[-16000:]);raise SystemExit(result.returncode)
app=output/'DerivedData/Build/Products/Release-watchos/SideStoreWatch.app'
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['WKApplication']
assert info['WKCompanionAppBundleIdentifier']=='com.SideStore.SideStore'
assert tuple(map(int,info['MinimumOSVersion'].split('.'))) <= (10,6,2)
archs=subprocess.check_output(['xcrun','lipo','-archs',str(app/info['CFBundleExecutable'])],text=True)
assert 'arm64_32' in archs,archs
payload=output/'Payload'
payload.mkdir(exist_ok=True)
destination=payload/app.name
if destination.exists(): shutil.rmtree(destination)
shutil.copytree(app,destination)
subprocess.run(['ditto','-c','-k','--keepParent',str(payload),str(output/'WatchBootstrap.ipa')],check=True)
with zipfile.ZipFile(output/'WatchBootstrap.ipa') as archive: assert archive.testzip() is None
print('WatchOS 10 native bootstrap: device build, arm64_32, version and ZIP verified. Physical installation remains unverified.')
