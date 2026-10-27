"""Rebuild the pinned iPhone FFI with companion_proxy; preserve the other upstream slices."""
import hashlib, os, pathlib, shutil, subprocess, urllib.request, zipfile
root=pathlib.Path(__file__).resolve().parents[1]
target=root/'Dependencies/minimuxer/DeviceGateway/WatchBetaIDevice.xcframework'
work=root/'build/watch-ffi';work.mkdir(parents=True,exist_ok=True)
release='v0.1.68-ss-3e55c84'
url='https://github.com/SideStore/idevice/releases/download/'+release+'/idevice-xcframework-'+release+'.zip'
archive=work/'upstream.zip'
if not archive.exists(): urllib.request.urlretrieve(url, archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='445702d53942597deb4cdec2c4122d16a3f4ac124ce26cd75b68dab3dad92416'
source=work/'source'
if not source.exists(): subprocess.run(['git','clone','--depth','1','--branch',release,'https://github.com/SideStore/idevice.git',str(source)],check=True)
commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()
assert commit.startswith('3e55c84')
subprocess.run(['rustup','target','add','aarch64-apple-ios'],check=True)
environment=dict(os.environ)
environment['IPHONEOS_DEPLOYMENT_TARGET']='15.0'
environment['SDKROOT']=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
subprocess.run(['cargo','build','--manifest-path',str(source/'ffi/Cargo.toml'),'--locked','--release','--target','aarch64-apple-ios','--features','companion_proxy'],check=True,env=environment)
binary=source/'target/aarch64-apple-ios/release/libidevice_ffi.a';assert binary.exists()
# Detect missing binary exports before spending time building the entire iPhone app.
names=subprocess.check_output(['xcrun','nm','-gU',str(binary)],text=True)
for symbol in ['_companion_proxy_connect','_companion_proxy_connect_rsd','_companion_proxy_get_device_registry','_companion_proxy_client_free']:
    assert any(line.split()[-1:]==[symbol] for line in names.splitlines()),'Missing required export: '+symbol
if target.exists():shutil.rmtree(target)
with zipfile.ZipFile(archive) as z:
    z.extractall(work/'upstream')
shutil.copytree(work/'upstream/swift/IDevice.xcframework',target)
shutil.copy2(binary,target/'ios-arm64/libidevice_ffi.a')
(root/'build/watch-ffi/PROVENANCE.json').write_text(__import__('json').dumps({'repository':'https://github.com/SideStore/idevice','commit':commit,'features':'upstream defaults + companion_proxy','target':'aarch64-apple-ios','rustc':subprocess.check_output(['rustc','--version'],text=True).strip(),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest()},indent=2)+'\n')
print('Verified iPhone Watch service exports; other upstream platform slices preserved.')
