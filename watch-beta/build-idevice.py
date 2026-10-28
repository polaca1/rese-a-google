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
# Add the tracked installation bridge to the exact pinned FFI source.
shutil.copyfile(root/'watch-beta/watch_install.rs', source/'ffi/src/watch_install.rs')
lib=source/'ffi/src/lib.rs'
text=lib.read_text()
if 'pub mod watch_install;' not in text: lib.write_text(text+'\npub mod watch_install;\n')

# Small pinned library extension: retain one generated identity across a trust disconnect.
# The exchange sends raw framed XML, so private pair material never reaches debug logging.
lockdown=source/'idevice/src/services/lockdown.rs'
lockdown_text=lockdown.read_text()
needle='    async fn build_pair_request('
if needle in lockdown_text:
    lockdown_text=lockdown_text.replace(needle,'    pub async fn build_pair_request(',1)
    marker='    pub async fn build_pair_request('
    exchange="""    /// Personal Watch bridge: exchange an already-generated identity without logging it.
    pub async fn watch_beta_pair_exchange(
        &mut self, request: plist::Value,
    ) -> Result<plist::Dictionary, IdeviceError> {
        let mut bytes = Vec::new();
        request.to_writer_xml(&mut bytes)?;
        let size = u32::try_from(bytes.len()).map_err(|_| IdeviceError::IntegerOverflow)?;
        self.idevice.send_raw(&size.to_be_bytes()).await?;
        self.idevice.send_raw(&bytes).await?;
        self.idevice.read_plist().await
    }

"""
    lockdown_text=lockdown_text.replace(marker,exchange+marker,1)
    lockdown.write_text(lockdown_text)
assert 'pub async fn watch_beta_pair_exchange(' in lockdown.read_text()
assert 'pub async fn build_pair_request(' in lockdown.read_text()

subprocess.run(['rustup','target','add','--toolchain','1.99.1','aarch64-apple-ios'],check=True)
environment=dict(os.environ)
environment['IPHONEOS_DEPLOYMENT_TARGET']='15.0'
environment['CARGO_PROFILE_RELEASE_LTO']='false'
environment['RUSTFLAGS']='-C embed-bitcode=no'
environment['SDKROOT']=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
subprocess.run(['cargo','+1.99.1','build','--manifest-path',str(source/'ffi/Cargo.toml'),'--locked','--release','--target','aarch64-apple-ios','--features','companion_proxy,pair'],check=True,env=environment)
# Compile the actual framing/CRC routines into a small host test executable.
rust=(root/'watch-beta/watch_install.rs').read_text()
framing=rust[rust.index('fn valid_remote_host_id('):rust.index("enum PhoneTransport")] + rust[rust.index('fn retry_pair_connection('):rust.index('async fn verify_watch_endpoint(')] + rust[rust.index('fn zip_header('):rust.index('fn insert_string(')] + rust[rust.index('fn crc32_ieee('):] + rust[rust.index('fn watch_rejection_kind('):rust.index('fn collect_files(')]
checks=work/'protocol-tests.rs'
checks.write_text(rust[rust.index('type Report ='):rust.index('macro_rules! bail')]+framing+"""
fn main() {
    assert_eq!(crc32_ieee(b"123456789"), 0xcbf43926);
    assert_eq!(crc32_ieee(b""), 0);
    let h=zip_header("Payload/Watch.app/main", 123, 0x12345678).unwrap();
    assert_eq!(&h[..4], &[0x50,0x4b,0x03,0x04]);
    assert_eq!(u32::from_le_bytes(h[14..18].try_into().unwrap()), 0x12345678);
    assert_eq!(u32::from_le_bytes(h[18..22].try_into().unwrap()), 123);
    assert!(zip_header(&"x".repeat(65536),0,0).is_err());
    assert!(valid_remote_host_id("A1B2C3D4-1234-5678-ABCD-001122334455"));
    assert!(!valid_remote_host_id(""));
    assert!(!valid_remote_host_id("BAD\\nPRIVATE"));
    assert!(!valid_remote_host_id(&"x".repeat(129)));
    assert!(retry_pair_connection(44, 0));
    assert!(retry_pair_connection(44, 1));
    assert!(!retry_pair_connection(44, 2));
    assert!(!retry_pair_connection(40, 0));
    assert!(!retry_pair_connection(41, 0));
    assert!(!retry_pair_connection(43, 0));
    assert_eq!(watch_rejection_kind("InvalidCompanionAppBundleIdentifier"), 101);
    assert_eq!(watch_rejection_kind("ApplicationVerificationFailed"), 100);
    assert_eq!(watch_rejection_kind("DeviceLocked"), 104);
    assert_eq!(watch_rejection_kind("PRIVATE_IDENTIFIER_AND_RESPONSE"), 199);
    println!("Watch wire format and allowlisted rejection diagnostics passed");
}
""".replace('fn zip_header', 'fn zip_header'))
# The stream's fixed extra field is included verbatim from the production source.
extra=rust[rust.index('const ZIP_EXTRA:'):rust.index('/// Install already-signed')]
checks.write_text(extra+checks.read_text())
subprocess.run(['rustc','+1.99.1','--edition','2024',str(checks),'-o',str(work/'protocol-tests')],check=True)
subprocess.run([str(work/'protocol-tests')],check=True)
binary=source/'target/aarch64-apple-ios/release/libidevice_ffi.a';assert binary.exists()
# Detect missing binary exports before spending time building the entire iPhone app.
sysroot=pathlib.Path(subprocess.check_output(['rustc','+1.99.1','--print','sysroot'],text=True).strip())
host=next(line.split(': ',1)[1] for line in subprocess.check_output(['rustc','+1.99.1','-vV'],text=True).splitlines() if line.startswith('host: '))
nm=sysroot/'lib/rustlib'/host/'bin/llvm-nm'
assert nm.exists(), 'Install llvm-tools-preview for the pinned Rust compiler'
names=subprocess.check_output([str(nm),'--defined-only','-g',str(binary)],text=True)
for symbol in ['_companion_proxy_connect','_companion_proxy_connect_rsd','_companion_proxy_get_device_registry','_companion_proxy_client_free','_sidestore_watch_install','_sidestore_watch_install_rsd']:
    assert any(line.split()[-1:]==[symbol] for line in names.splitlines()),'Missing required export: '+symbol
# Link the actual service functions with the selected iPhone SDK before the full app build.
probe=work/'link-probe.c'
probe.write_text('extern void sidestore_watch_install(void);\nextern void sidestore_watch_install_rsd(void);\nextern void companion_proxy_connect(void);\nextern void companion_proxy_connect_rsd(void);\nextern void companion_proxy_get_device_registry(void);\nextern void companion_proxy_client_free(void);\ntypedef void (*Fn)(void);\nFn volatile symbols[] = {sidestore_watch_install, sidestore_watch_install_rsd, companion_proxy_connect, companion_proxy_connect_rsd, companion_proxy_get_device_registry, companion_proxy_client_free};\nint main(void) { return symbols[0] == 0; }\n')
subprocess.run(['xcrun','clang','-target','arm64-apple-ios15.0','-isysroot',environment['SDKROOT'],str(probe),str(binary),'-framework','Security','-framework','CoreFoundation','-framework','SystemConfiguration','-framework','CFNetwork','-liconv','-lresolv','-lz','-lc++','-o',str(work/'link-probe')],check=True)
print('Native iPhone SDK link probe passed for all native Watch service exports.')
if target.exists():shutil.rmtree(target)
with zipfile.ZipFile(archive) as z:
    z.extractall(work/'upstream')
shutil.copytree(work/'upstream/swift/IDevice.xcframework',target)
shutil.copy2(binary,target/'ios-arm64/libidevice_ffi.a')
header=target/'ios-arm64/Headers/idevice.h'
if not header.exists(): header=next((target/'ios-arm64').rglob('*.h'))
header.write_text(header.read_text()+'\nint32_t sidestore_watch_install(struct IdeviceProviderHandle *provider, const char *watch, const char *path, const char *cache);\n')
header.write_text(header.read_text()+'\nint32_t sidestore_watch_install_rsd(struct AdapterHandle *adapter, struct RsdHandshakeHandle *handshake, const struct RpPairingFileHandle *pairing, const char *watch, const char *path, const char *cache);\n')
(root/'build/watch-ffi/PROVENANCE.json').write_text(__import__('json').dumps({'repository':'https://github.com/SideStore/idevice','commit':commit,'features':'upstream defaults + companion_proxy + pair','lto':False,'embedBitcode':False,'target':'aarch64-apple-ios','rustc':subprocess.check_output(['rustc','+1.99.1','--version'],text=True).strip(),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest()},indent=2)+'\n')
print('Verified iPhone Watch service exports; other upstream platform slices preserved.')
