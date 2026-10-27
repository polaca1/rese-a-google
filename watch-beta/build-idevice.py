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
subprocess.run(['rustup','target','add','--toolchain','1.99.1','aarch64-apple-ios'],check=True)
environment=dict(os.environ)
environment['IPHONEOS_DEPLOYMENT_TARGET']='15.0'
environment['CARGO_PROFILE_RELEASE_LTO']='false'
environment['RUSTFLAGS']='-C embed-bitcode=no'
environment['SDKROOT']=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
subprocess.run(['cargo','+1.99.1','build','--manifest-path',str(source/'ffi/Cargo.toml'),'--locked','--release','--target','aarch64-apple-ios','--features','companion_proxy'],check=True,env=environment)
binary=source/'target/aarch64-apple-ios/release/libidevice_ffi.a';assert binary.exists()
# Detect missing binary exports before spending time building the entire iPhone app.
sysroot=pathlib.Path(subprocess.check_output(['rustc','+1.99.1','--print','sysroot'],text=True).strip())
host=next(line.split(': ',1)[1] for line in subprocess.check_output(['rustc','+1.99.1','-vV'],text=True).splitlines() if line.startswith('host: '))
nm=sysroot/'lib/rustlib'/host/'bin/llvm-nm'
assert nm.exists(), 'Install llvm-tools-preview for the pinned Rust compiler'
names=subprocess.check_output([str(nm),'--defined-only','-g',str(binary)],text=True)
for symbol in ['_companion_proxy_connect','_companion_proxy_connect_rsd','_companion_proxy_get_device_registry','_companion_proxy_client_free']:
    assert any(line.split()[-1:]==[symbol] for line in names.splitlines()),'Missing required export: '+symbol
# Link the actual service functions with the selected iPhone SDK before the full app build.
probe=work/'link-probe.c'
probe.write_text('extern void companion_proxy_connect(void);\nextern void companion_proxy_connect_rsd(void);\nextern void companion_proxy_get_device_registry(void);\nextern void companion_proxy_client_free(void);\ntypedef void (*Fn)(void);\nFn volatile symbols[] = {companion_proxy_connect, companion_proxy_connect_rsd, companion_proxy_get_device_registry, companion_proxy_client_free};\nint main(void) { return symbols[0] == 0; }\n')
subprocess.run(['xcrun','clang','-target','arm64-apple-ios15.0','-isysroot',environment['SDKROOT'],str(probe),str(binary),'-framework','Security','-framework','CoreFoundation','-framework','SystemConfiguration','-framework','CFNetwork','-liconv','-lresolv','-lz','-lc++','-o',str(work/'link-probe')],check=True)
print('Native iPhone SDK link probe passed for all four Watch service exports.')
if target.exists():shutil.rmtree(target)
with zipfile.ZipFile(archive) as z:
    z.extractall(work/'upstream')
shutil.copytree(work/'upstream/swift/IDevice.xcframework',target)
shutil.copy2(binary,target/'ios-arm64/libidevice_ffi.a')
(root/'build/watch-ffi/PROVENANCE.json').write_text(__import__('json').dumps({'repository':'https://github.com/SideStore/idevice','commit':commit,'features':'upstream defaults + companion_proxy','lto':False,'embedBitcode':False,'target':'aarch64-apple-ios','rustc':subprocess.check_output(['rustc','+1.99.1','--version'],text=True).strip(),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest()},indent=2)+'\n')
print('Verified iPhone Watch service exports; other upstream platform slices preserved.')
