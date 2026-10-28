#[path = "watch_pair_wire.rs"]
mod watch_pair_wire;
use idevice::{
    Idevice, IdeviceService, IdeviceError, RsdService,
    pairing_file::PairingFile,
    provider::IdeviceProvider,
    services::{
        companion_proxy::CompanionProxy,
        lockdown::LockdownClient,
    },
};
use plist::{Dictionary, Value};

use std::{
    path::{Path, PathBuf},
    time::Duration,
    sync::atomic::{AtomicI32, Ordering},
};
macro_rules! quiet_log { ($($arg:tt)*) => {}; }

// Adapted from Rzbck/isideload (f7b9f3d), MIT; see THIRD-PARTY-NOTICES.txt.
// This personal variant is distributed under the SideStore AGPL-3.0 terms.
// SideStore personal beta: no deletion of existing apps, exact single-Watch selection.
use crate::{provider::IdeviceProviderHandle, core_device_proxy::AdapterHandle,
    rsd::RsdHandshakeHandle, rp_pairing_file::RpPairingFileHandle, run_sync_local};
use std::ffi::{CStr, c_char};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
type Report = Box<dyn std::error::Error>;
trait Context<T> { fn context(self, message: &str) -> Result<T, Report>; }
impl<T, E: std::fmt::Debug> Context<T> for Result<T, E> {
    fn context(self, message: &str) -> Result<T, Report> { self.map_err(|_| message.to_string().into()) }
}
macro_rules! bail { ($($arg:tt)*) => { return Err(format!($($arg)*).into()) }; }
macro_rules! report { ($($arg:tt)*) => { Into::<Report>::into(format!($($arg)*)) }; }
struct Bundle { bundle_dir: PathBuf }

/// Install an already-signed, locally validated Watch bundle. No Apple API mutations.
/// Provider is borrowed for this synchronous call; result never includes private data.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sidestore_watch_install(provider: *mut IdeviceProviderHandle,
    expected_watch: *const c_char, path: *const c_char, cache: *const c_char) -> i32 {
    if provider.is_null() || expected_watch.is_null() || path.is_null() || cache.is_null() { return 1; }
    let Ok(expected) = (unsafe { CStr::from_ptr(expected_watch) }).to_str() else { return 1; };
    let Ok(path) = (unsafe { CStr::from_ptr(path) }).to_str() else { return 1; };
    let Ok(cache) = (unsafe { CStr::from_ptr(cache) }).to_str() else { return 1; };
    if !valid_remote_host_id(expected) { return 1; }
    let provider = unsafe { &*(*provider).0 };
    run_sync_local(async {
        let mut transport = PhoneTransport::Tcp(provider);
        install_with_transport(&mut transport, expected, PathBuf::from(path), Path::new(cache)).await
    })
}

/// Borrow the already-authenticated RP tunnel for this synchronous call only.
/// No handles are consumed, retained or freed; IdeviceGateway remains their owner.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sidestore_watch_install_rsd(
    adapter: *mut AdapterHandle,
    handshake: *mut RsdHandshakeHandle,
    pairing: *const RpPairingFileHandle,
    expected_watch: *const c_char,
    path: *const c_char,
    cache: *const c_char,
) -> i32 {
    if adapter.is_null() || handshake.is_null() || pairing.is_null() || expected_watch.is_null() || path.is_null() || cache.is_null() { return 1; }
    let Ok(expected) = (unsafe { CStr::from_ptr(expected_watch) }).to_str() else { return 1; };
    let Ok(path) = (unsafe { CStr::from_ptr(path) }).to_str() else { return 1; };
    let Ok(cache) = (unsafe { CStr::from_ptr(cache) }).to_str() else { return 1; };
    if !valid_remote_host_id(expected) { return 1; }
    // RP supplies a persistent host identifier, not a fabricated TCP pairing record.
    // Watch Lockdown creates its own real pair record through Pair and StartSession.
    let host_id = unsafe { &(*pairing).0.identifier };
    if !valid_remote_host_id(host_id) { return 10; }
    let adapter = unsafe { &mut (*adapter).0 };
    let handshake = unsafe { &mut (*handshake).0 };
    run_sync_local(async {
        let mut transport = PhoneTransport::Remote { adapter, handshake, host_id: host_id.clone() };
        install_with_transport(&mut transport, expected, PathBuf::from(path), Path::new(cache)).await
    })
}

fn valid_remote_host_id(value: &str) -> bool {
    !value.is_empty() && value.len() <= 128 && value.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

enum PhoneTransport<'a> {
    Tcp(&'a dyn IdeviceProvider),
    Remote {
        adapter: &'a mut idevice::tcp::handle::AdapterHandle,
        handshake: &'a mut idevice::rsd::RsdHandshake,
        host_id: String,
    },
}
impl PhoneTransport<'_> {
    async fn companion(&mut self) -> Result<CompanionProxy, IdeviceError> {
        match self {
            Self::Tcp(provider) => CompanionProxy::connect(*provider).await,
            Self::Remote { adapter, handshake, .. } =>
                CompanionProxy::connect_rsd(&mut **adapter, &mut **handshake).await,
        }
    }
    async fn connect(&mut self, port: u16) -> Result<Idevice, IdeviceError> {
        match self {
            Self::Tcp(provider) => provider.connect(port).await,
            // Forwarded Watch ports carry the raw Watch protocol, not an RSD shim.
            Self::Remote { adapter, .. } => Ok(Idevice::new(Box::new(adapter.connect(port).await?), "SideStore Watch Beta")),
        }
    }
    async fn pairing_identity(&self) -> Result<(String, String), IdeviceError> {
        match self {
            Self::Tcp(provider) => {
                let pairing = provider.get_pairing_file().await?;
                Ok((pairing.host_id, pairing.system_buid))
            }
            Self::Remote { host_id, .. } => Ok((host_id.clone(), host_id.clone())),
        }
    }
}
async fn install_with_transport(transport: &mut PhoneTransport<'_>, expected: &str, path: PathBuf, cache: &Path) -> i32 {
    let Ok(mut proxy) = transport.companion().await else { return 2; };
    let Ok(watches) = proxy.get_device_registry().await else { return 2; };
    if watches.len() != 1 || watches[0] != expected { return 3; }
    drop(proxy);
    let stage = AtomicI32::new(4);
    let app = Bundle { bundle_dir: path };
    match install_watch_apps(transport, &[app], "SideStore Watch Beta", expected, cache, &stage, |_| {}).await {
        Ok(()) => 0,
        Err(_) => stage.load(Ordering::Relaxed),
    }
}


const WATCH_LOCKDOWN_PORT: u16 = 62078;
const WATCH_LOCKDOWN_SERVICE: &str = "com.apple.mobile.lockdownd";
const WATCH_INSTALL_PROXY_SERVICE: &str = "com.apple.mobile.installation_proxy";
const WATCH_ZIP_SERVICE: &str = "com.apple.streaming_zip_conduit";
const WATCH_FORWARD_CONNECT_ATTEMPTS: usize = 20;
const WATCH_FORWARD_CONNECT_DELAY_MS: u64 = 50;
const CENTRAL_DIRECTORY_HEADER: &[u8] = &[0x50, 0x4b, 0x01, 0x02];
const ZIP_EXTRA: &[u8] = &[
    0x55, 0x54, 0x0d, 0x00, 0x07, 0xf3, 0xa2, 0xec, 0x60, 0xf6, 0xa2, 0xec, 0x60, 0xf3,
    0xa2, 0xec, 0x60, 0x75, 0x78, 0x0b, 0x00, 0x01, 0x04, 0xf5, 0x01, 0x00, 0x00, 0x04,
    0x14, 0x00, 0x00, 0x00,
];

/// Install already-signed embedded Watch apps directly on the paired Apple Watch.
///
/// iPhone installation can leave an embedded Watch app as a process-scoped placeholder.
/// watchOS exposes `streaming_zip_conduit`, which accepts the signed Watch `.app` directly
/// and finalizes it as an installed application. Existing applications are never removed first.
async fn install_watch_apps(
    device_provider: &mut PhoneTransport<'_>,
    watch_apps: &[Bundle],
    host_name: &str,
    expected_watch: &str,
    cache: &Path,
    stage: &AtomicI32,
    progress_callback: impl Fn(u64) + Send + Sync,
) -> Result<(), Report> {
    if watch_apps.is_empty() {
        return Ok(());
    }

    stage.store(10, Ordering::Relaxed);
    let (host_id, system_buid) = match device_provider {
        PhoneTransport::Remote { .. } => watch_host_identity(cache, expected_watch)?,
        _ => device_provider.pairing_identity().await?,
    };

    stage.store(11, Ordering::Relaxed);
    let forwarded_lockdown_port = {
        let mut companion_proxy = device_provider.companion()
            .await
            
            .context("Failed to connect to fresh Apple Watch companion proxy for lockdown forwarding")?;

        companion_proxy
            .start_forwarding_service_port(
                WATCH_LOCKDOWN_PORT,
                Some(WATCH_LOCKDOWN_SERVICE),
                None,
            )
            .await
            
            .context("Failed to forward Apple Watch lockdown")?
    };

    let result = tokio::time::timeout(Duration::from_secs(120), async {
        stage.store(12, Ordering::Relaxed);
        let watch_connection = connect_forwarded_watch_port(
            device_provider,
            forwarded_lockdown_port,
            "lockdown",
        )
        .await?;
        let mut watch_lockdown = LockdownClient::new(watch_connection);

        // Verify the forwarded endpoint before any trust request or cache use.
        stage.store(15, Ordering::Relaxed);
        verify_watch_endpoint(&mut watch_lockdown, expected_watch).await?;
        let cache_file = cache.join(format!("{expected_watch}.plist"));
        let cached = read_watch_pairing(&cache_file, expected_watch, &host_id);
        let mut paired = None;
        if let Some(record) = cached {
            stage.store(14, Ordering::Relaxed);
            match watch_lockdown.start_session(&record).await {
                Ok(legacy) => paired = Some((record, legacy)),
                Err(IdeviceError::InvalidHostID) => {
                    // Only an explicit invalid host allows a new trust request.
                    let _ = std::fs::remove_file(&cache_file);
                    watch_lockdown = reconnect_watch(device_provider, forwarded_lockdown_port, expected_watch).await?;
                }
                Err(error) => return Err(error.into()),
            }
        }
        let (watch_pairing, legacy) = if let Some(pairing) = paired { pairing } else {
            stage.store(13, Ordering::Relaxed);
            let record = pair_watch_preserving_identity(device_provider, &mut watch_lockdown,
                forwarded_lockdown_port, expected_watch, &host_id, &system_buid, host_name, cache, stage).await?;
            // Store accepted Watch credentials only in the protected app-private directory.
            // The pairing record is never a report, log or build artifact.
            let _ = save_watch_pairing(&cache_file, &record);
            stage.store(14, Ordering::Relaxed);
            let legacy = watch_lockdown.start_session(&record).await?;
            (record, legacy)
        };

        stage.store(15, Ordering::Relaxed);
        let actual = watch_lockdown.get_value(Some("UniqueDeviceID"), None).await?;
        // The registry can change during forwarding; verify the endpoint itself.
        let mut proxy = device_provider.companion().await?;
        let current = proxy.get_device_registry().await?;
        if current.len() != 1 || current[0] != expected_watch || actual.as_string() != Some(expected_watch) {
            stage.store(26, Ordering::Relaxed);
            bail!("Watch endpoint changed");
        }

        for watch_app in watch_apps {
            install_watch_app_zip_conduit(
                device_provider,
                &mut watch_lockdown,
                &watch_pairing,
                legacy,
                watch_app,
                stage,
                &progress_callback,
            )
            .await?;
        }

        Ok(())
    }).await.map_err(|_| { stage.store(30, Ordering::Relaxed); Into::<Report>::into("Watch operation timed out") }).and_then(|result| result);

    match device_provider.companion().await {
        Ok(mut companion_proxy) => {
            if let Err(e) = companion_proxy
                .stop_forwarding_service_port(WATCH_LOCKDOWN_PORT)
                .await
            {
                quiet_log!("Failed to stop Apple Watch lockdown forwarding: {e}");
            }
        }
        Err(e) => {
            quiet_log!("Failed to open fresh Apple Watch companion proxy to stop lockdown forwarding: {e}");
        }
    }

    result
}


fn watch_pair_rejection_kind(error: &str) -> i32 {
    match error {
        "MissingPairRecord" => 50,
        "InvalidPairRecord" => 51,
        "InvalidCertificate" => 52,
        "PairingProhibitedOverThisConnection" => 53,
        "SavePairRecordFailed" => 54,
        "PairingFailed" => 55,
        "MCChallengeRequired" => 56,
        "EscrowLocked" => 57,
        "SessionInactive" => 58,
        "InvalidResponse" => 59,
        "NoRunningSession" => 60,
        "ServiceProhibited" => 61,
        "GetProhibited" => 62,
        "MissingHostID" => 63,
        "InvalidArgument" => 64,
        "WatchPairErrorType" => 65,
        _ => 43,
    }
}
fn pairing_failure(error: &IdeviceError) -> i32 {
    match error {
        IdeviceError::UserDeniedPairing => 40,
        IdeviceError::PasswordProtected | IdeviceError::DeviceLocked => 41,
        IdeviceError::InvalidHostID => 42,
        IdeviceError::UnknownErrorType(error) => watch_pair_rejection_kind(error),
        IdeviceError::UnexpectedResponse(_) => 43,
        IdeviceError::Socket(_) | IdeviceError::NoEstablishedConnection | IdeviceError::NotEnoughBytes(_, _) => 44,
        IdeviceError::PairingDialogResponsePending => 46,
        _ => 47,
    }
}
fn retry_pair_connection(code: i32, retries: usize) -> bool { code == 44 && retries < 2 }

async fn verify_watch_endpoint(client: &mut LockdownClient, expected: &str) -> Result<(), Report> {
    let actual = client.get_value(Some("UniqueDeviceID"), None).await?;
    if actual.as_string() != Some(expected) { bail!("Watch endpoint changed"); }
    Ok(())
}

async fn reconnect_watch(transport: &mut PhoneTransport<'_>, port: u16, expected: &str) -> Result<LockdownClient, Report> {
    let connection = connect_forwarded_watch_port(transport, port, "lockdown").await?;
    let mut client = LockdownClient::new(connection);
    verify_watch_endpoint(&mut client, expected).await?;
    Ok(client)
}

async fn pair_watch_preserving_identity(
    transport: &mut PhoneTransport<'_>, client: &mut LockdownClient, port: u16,
    expected: &str, host: &str, buid: &str, name: &str, cache: &Path, stage: &AtomicI32,
) -> Result<PairingFile, Report> {
    // Build ONCE. Recreating certificates after a trust-induced disconnect loses the
    // identity the user accepted. Keep the exact request and private key across retries.
    stage.store(45, Ordering::Relaxed);
    let pending = cache.join(format!("{expected}.pending.plist"));
    let mut pairing = if let Some(record) = read_watch_pairing(&pending, expected, host) { record } else {
        let (_, mut record, private_key) = client.watch_beta_build_pair_request(host, buid, Some(name)).await?;
        record.insert("HostPrivateKey".into(), Value::Data(private_key));
        record.insert("UDID".into(), Value::String(expected.to_owned()));
        let pairing = PairingFile::from_value(&Value::Dictionary(record))?;
        // Persist BEFORE the trust request, not only after success. A relaunch must
        // present the same certificates and identity that the user already accepted.
        save_watch_pairing(&pending, &pairing)?;
        pairing
    };
    let record: Dictionary = plist::from_bytes(&pairing.clone().serialize()?)?;
    let request = watch_pair_wire::request(&record, name)?;
    let mut retries = 0;
    loop {
        stage.store(13, Ordering::Relaxed);
        let response = client.watch_beta_pair_exchange(request.clone()).await;
        match response {
            Ok(response) => {
                if let Some(bag) = response.get("EscrowBag").and_then(Value::as_data) {
                    pairing.escrow_bag = Some(bag.to_vec());
                }
                return Ok(pairing);
            }
            Err(IdeviceError::PairingDialogResponsePending) => {
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
            Err(error) => {
                let code = pairing_failure(&error);
                stage.store(code, Ordering::Relaxed);
                if !retry_pair_connection(code, retries) { return Err(error.into()); }
                retries += 1;
                tokio::time::sleep(Duration::from_secs(1)).await;
                *client = reconnect_watch(transport, port, expected).await?;
            }
        }
    }
}

fn watch_host_identity(cache: &Path, expected: &str) -> Result<(String,String), Report> {
    let path = cache.join(format!("{expected}.identity"));
    if let Ok(metadata) = std::fs::symlink_metadata(&path) {
        if !metadata.is_file() || metadata.file_type().is_symlink() || metadata.len()>128 {
            bail!("Invalid Watch identity cache");
        }
        let text = std::fs::read_to_string(&path)?;
        return watch_pair_wire::decode_identity(&text).ok_or_else(|| "Invalid Watch identity cache".into());
    }
    // A Watch Lockdown host identity is independent of the iPhone's RP identity.
    let identity = LockdownClient::watch_beta_new_host_identity();
    if !watch_pair_wire::valid_identity(&identity.0) || !watch_pair_wire::valid_identity(&identity.1) || identity.0==identity.1 {
        bail!("Invalid generated Watch identity");
    }
    let temporary = path.with_extension("identity-new");
    let mut file = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary)?;
    file.write_all(format!("{}\n{}\n", identity.0, identity.1).as_bytes())?;
    file.sync_all()?;
    std::fs::rename(&temporary, &path)?;
    Ok(identity)
}

fn read_watch_pairing(path: &Path, expected: &str, host: &str) -> Option<PairingFile> {
    let metadata = std::fs::symlink_metadata(path).ok()?;
    if !metadata.is_file() || metadata.file_type().is_symlink() || metadata.len() > 1_048_576 { return None; }
    let record = PairingFile::read_from_file(path).ok()?;
    (record.udid.as_deref() == Some(expected) && record.host_id == host).then_some(record)
}
fn save_watch_pairing(path: &Path, pairing: &PairingFile) -> Result<(), Report> {
    let bytes = pairing.clone().serialize()?;
    let temporary = path.with_extension("new");
    let result = (|| -> Result<(), Report> {
        let mut file = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
        std::fs::rename(&temporary, path)?;
        Ok(())
    })();
    // No secrets are logged on failure; an accepted identity can still install this time.
    if result.is_err() { let _ = std::fs::remove_file(&temporary); }
    result
}

async fn connect_forwarded_watch_port(
    device_provider: &mut PhoneTransport<'_>,
    forwarded_port: u16,
    service: &str,
) -> Result<Idevice, Report> {
    for attempt in 1..=WATCH_FORWARD_CONNECT_ATTEMPTS {
        match device_provider.connect(forwarded_port).await {
            Ok(connection) => {
                if attempt > 1 {
                    quiet_log!(
                        "Connected to Apple Watch {} on forwarded port {} after {} attempts",
                        service, forwarded_port, attempt
                    );
                }
                return Ok(connection);
            }
            Err(error) if attempt < WATCH_FORWARD_CONNECT_ATTEMPTS => {
                quiet_log!(
                    "Apple Watch {} forwarded port {} is not ready (attempt {}/{}): {}",
                    service,
                    forwarded_port,
                    attempt,
                    WATCH_FORWARD_CONNECT_ATTEMPTS,
                    error
                );
                tokio::time::sleep(Duration::from_millis(
                    WATCH_FORWARD_CONNECT_DELAY_MS,
                ))
                .await;
            }
            Err(error) => {
                bail!(
                    "Failed to connect to Apple Watch {} on forwarded iPhone port {} after {} attempts: {}",
                    service,
                    forwarded_port,
                    WATCH_FORWARD_CONNECT_ATTEMPTS,
                    error
                );
            }
        }
    }

    unreachable!("bounded forwarded-port retry loop must return")
}
async fn install_watch_app_zip_conduit(
    device_provider: &mut PhoneTransport<'_>,
    watch_lockdown: &mut LockdownClient,
    watch_pairing: &PairingFile,
    legacy: bool,
    watch_app: &Bundle,
    stage: &AtomicI32,
    progress_callback: &(impl Fn(u64) + Send + Sync),
) -> Result<(), Report> {
    stage.store(16, Ordering::Relaxed);
    let (remote_port, ssl) = watch_lockdown
        .start_service(WATCH_ZIP_SERVICE)
        .await
        
        .context("Failed to start Apple Watch streaming_zip_conduit")?;

    stage.store(17, Ordering::Relaxed);
    let forwarded_port = {
        let mut companion_proxy = device_provider.companion()
            .await
            
            .context("Failed to connect to fresh Apple Watch companion proxy for streaming_zip_conduit forwarding")?;

        companion_proxy
            .start_forwarding_service_port(
                remote_port,
                Some(WATCH_ZIP_SERVICE),
                None,
            )
            .await
            
            .context("Failed to forward Apple Watch streaming_zip_conduit")?
    };

    let result = tokio::time::timeout(Duration::from_secs(90), async {
        stage.store(18, Ordering::Relaxed);
        let mut connection = connect_forwarded_watch_port(
            device_provider,
            forwarded_port,
            "streaming_zip_conduit",
        )
        .await?;

        if ssl {
            stage.store(19, Ordering::Relaxed);
            connection
                .start_session(watch_pairing, legacy)
                .await
                
                .context("Failed to secure Apple Watch streaming_zip_conduit connection")?;
        }

        stream_watch_app(&mut connection, watch_app, stage, progress_callback).await
    }).await.map_err(|_| { stage.store(31, Ordering::Relaxed); Into::<Report>::into("Watch transfer timed out") }).and_then(|result| result);

    match device_provider.companion().await {
        Ok(mut companion_proxy) => {
            if let Err(e) = companion_proxy.stop_forwarding_service_port(remote_port).await {
                quiet_log!("Failed to stop Apple Watch streaming_zip_conduit forwarding: {e}");
            }
        }
        Err(e) => {
            quiet_log!("Failed to open fresh Apple Watch companion proxy to stop streaming_zip_conduit forwarding: {e}");
        }
    }

    result
}

async fn stream_watch_app(
    connection: &mut Idevice,
    watch_app: &Bundle,
    stage: &AtomicI32,
    progress_callback: &(impl Fn(u64) + Send + Sync),
) -> Result<(), Report> {
    stage.store(20, Ordering::Relaxed);
    let app_name = watch_app
        .bundle_dir
        .file_name()
        .ok_or("Missing required value")
        .context("Watch app path has no file name")?
        .to_string_lossy()
        .to_string();

    let mut files = Vec::new();
    collect_files(&watch_app.bundle_dir, &mut files)?;
    files.sort();

    let mut entries = Vec::with_capacity(files.len());
    let mut total_uncompressed = 0u64;

    for source in files {
        let relative = source
            .strip_prefix(&watch_app.bundle_dir)
            .context("Failed to create relative Watch app path")?;
        let relative = relative.to_string_lossy().replace('\\', "/");
        let destination = format!("Payload/{app_name}/{relative}");
        let size = std::fs::metadata(&source)?.len();
        total_uncompressed = total_uncompressed.saturating_add(size);
        entries.push((source, destination));
    }

    let media_subdir = format!("PublicStaging/{app_name}.ipa");
    let mut install_options = Dictionary::new();
    insert_integer(&mut install_options, "DisableDeltaTransfer", 1);
    insert_string(
        &mut install_options,
        "InstallDeltaTypeKey",
        "InstallDeltaTypeSparseIPAFiles",
    );
    insert_integer(&mut install_options, "IsUserInitiated", 1);
    insert_string(&mut install_options, "PackageType", "Customer");
    insert_integer(&mut install_options, "PreferWifi", 1);

    let mut init_transfer = Dictionary::new();
    init_transfer.insert(
        "InstallOptionsDictionary".to_string(),
        Value::Dictionary(install_options),
    );
    insert_integer(&mut init_transfer, "InstallTransferredDirectory", 1);
    insert_string(&mut init_transfer, "MediaSubdir", media_subdir);
    insert_integer(&mut init_transfer, "UserInitiatedTransfer", 0);

    stage.store(21, Ordering::Relaxed);
    send_prefixed_plist(connection, init_transfer).await?;

    let mut metadata = Dictionary::new();
    insert_integer(&mut metadata, "StandardDirectoryPerms", 16877);
    insert_integer(&mut metadata, "StandardFilePerms", -32348);
    insert_integer(
        &mut metadata,
        "RecordCount",
        i64::try_from(entries.len() + 2).context("Too many Watch app files")?,
    );
    insert_integer(
        &mut metadata,
        "TotalUncompressedBytes",
        i64::try_from(total_uncompressed).context("Watch app is too large")?,
    );
    insert_integer(&mut metadata, "Version", 2);

    let mut metadata_bytes = Vec::new();
    Value::Dictionary(metadata).to_writer_xml(&mut metadata_bytes)?;

    send_zip_directory(connection, "META-INF/").await?;
    send_zip_file(
        connection,
        "META-INF/com.apple.ZipMetadata.plist",
        &metadata_bytes,
    )
    .await?;

    for (source, destination) in entries {
        let data = std::fs::read(&source)?;
        send_zip_file(connection, &destination, &data).await?;
    }

    connection
        .send_raw(CENTRAL_DIRECTORY_HEADER)
        .await
        ?;

    stage.store(22, Ordering::Relaxed);
    wait_for_watch_install(connection, stage, progress_callback).await
}

async fn wait_for_watch_install(
    connection: &mut Idevice,
    stage: &AtomicI32,
    progress_callback: &(impl Fn(u64) + Send + Sync),
) -> Result<(), Report> {
    loop {
        let response = read_prefixed_plist(connection).await?;

        if response.contains_key("Error") || response.get("InstallProgressDict").and_then(Value::as_dictionary).is_some_and(|p| p.contains_key("Error")) {
            let error = response.get("Error").or_else(|| response.get("InstallProgressDict")
                .and_then(Value::as_dictionary).and_then(|p| p.get("Error"))).and_then(Value::as_string).unwrap_or("");
            stage.store(watch_rejection_kind(error), Ordering::Relaxed);
            bail!("Watch rejected installation");
        }
        if response
            .get("Status")
            .and_then(Value::as_string)
            .is_some_and(|status| status == "DataComplete")
        {
            progress_callback(100);
            quiet_log!("Apple Watch installation completed");
            return Ok(());
        }

        stage.store(24, Ordering::Relaxed);
        let progress = response
            .get("InstallProgressDict")
            .and_then(Value::as_dictionary)
            .ok_or_else(|| report!("Unexpected Apple Watch install response: {response:?}"))?;

        if let Some(error) = progress.get("Error").and_then(Value::as_string) {
            let description = progress
                .get("ErrorDescription")
                .and_then(Value::as_string)
                .unwrap_or("No ErrorDescription returned by watchOS");
            bail!("Apple Watch installation failed: {error}: {description}");
        }

        stage.store(22, Ordering::Relaxed);
        let percent = progress
            .get("PercentComplete")
            .and_then(Value::as_unsigned_integer)
            .unwrap_or(0);
        let status = progress
            .get("Status")
            .and_then(Value::as_string)
            .unwrap_or("Unknown");

        quiet_log!("Installing Apple Watch app: {percent}% {status}");
        progress_callback(percent);
    }
}

// Only fixed categories leave the native bridge; never a raw Watch response.
fn watch_rejection_kind(error: &str) -> i32 {
    match error {
        "ApplicationVerificationFailed" => 100,
        "InvalidCompanionAppBundleIdentifier" => 101,
        "MismatchedApplicationIdentifierEntitlement" => 102,
        "InvalidProvisioningProfile" | "ProfileNotValid" => 103,
        "DeviceLocked" => 104,
        "UnsupportedOSVersion" | "DeviceOSVersionTooLow" => 105,
        "MaximumAppsLimitReached" => 106,
        "BundleVerificationFailed" => 107,
        "MissingApplicationIdentifierEntitlement" => 108,
        "PackageInspectionFailed" => 109,
        "InstallProhibited" => 110,
        "InsufficientStorage" | "DiskSpaceExceeded" => 111,
        "ApplicationAlreadyInstalled" => 112,
        _ => 199,
    }
}

fn collect_files(dir: &Path, files: &mut Vec<PathBuf>) -> Result<(), Report> {
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let metadata = std::fs::metadata(&path)?;

        if metadata.is_dir() {
            collect_files(&path, files)?;
        } else if metadata.is_file() {
            files.push(path);
        }
    }

    Ok(())
}

async fn send_prefixed_plist(
    connection: &mut Idevice,
    dictionary: Dictionary,
) -> Result<(), Report> {
    let mut payload = Vec::new();
    Value::Dictionary(dictionary).to_writer_xml(&mut payload)?;
    let payload_len = u32::try_from(payload.len()).context("Watch plist is too large")?;

    let mut frame = Vec::with_capacity(payload.len() + 4);
    frame.extend_from_slice(&payload_len.to_be_bytes());
    frame.extend_from_slice(&payload);

    connection
        .send_raw(&frame)
        .await
        ?;
    Ok(())
}

async fn read_prefixed_plist(connection: &mut Idevice) -> Result<Dictionary, Report> {
    let len = connection
        .read_raw(4)
        .await
        ?;
    let payload_len = u32::from_be_bytes([len[0], len[1], len[2], len[3]]) as usize;
    if payload_len == 0 || payload_len > 1_048_576 { bail!("Invalid Watch response length"); }
    let payload = connection
        .read_raw(payload_len)
        .await
        ?;
    let value: Value = plist::from_bytes(&payload)?;

    match value {
        Value::Dictionary(dictionary) => Ok(dictionary),
        other => bail!("Expected dictionary plist from Apple Watch, got {other:?}"),
    }
}

async fn send_zip_directory(connection: &mut Idevice, name: &str) -> Result<(), Report> {
    let header = zip_header(name, 0, 0)?;
    connection
        .send_raw(&header)
        .await
        ?;
    Ok(())
}

async fn send_zip_file(connection: &mut Idevice, name: &str, data: &[u8]) -> Result<(), Report> {
    let size = u32::try_from(data.len()).context("Watch app file is too large")?;
    let header = zip_header(name, size, crc32_ieee(data))?;

    connection
        .send_raw(&header)
        .await
        ?;
    connection
        .send_raw(data)
        .await
        ?;
    Ok(())
}

fn zip_header(name: &str, size: u32, crc32: u32) -> Result<Vec<u8>, Report> {
    let name_bytes = name.as_bytes();
    let name_len = u16::try_from(name_bytes.len()).context("Watch zip path is too long")?;
    let extra_len = u16::try_from(ZIP_EXTRA.len()).context("Watch zip extra data is too large")?;

    let mut header = Vec::with_capacity(30 + name_bytes.len() + ZIP_EXTRA.len());
    push_u32_le(&mut header, 0x04034b50);
    push_u16_le(&mut header, 20);
    push_u16_le(&mut header, 0);
    push_u16_le(&mut header, 0);
    push_u16_le(&mut header, 0xbdef);
    push_u16_le(&mut header, 0x52ec);
    push_u32_le(&mut header, crc32);
    push_u32_le(&mut header, size);
    push_u32_le(&mut header, size);
    push_u16_le(&mut header, name_len);
    push_u16_le(&mut header, extra_len);
    header.extend_from_slice(name_bytes);
    header.extend_from_slice(ZIP_EXTRA);
    Ok(header)
}

fn push_u16_le(buffer: &mut Vec<u8>, value: u16) {
    buffer.extend_from_slice(&value.to_le_bytes());
}

fn push_u32_le(buffer: &mut Vec<u8>, value: u32) {
    buffer.extend_from_slice(&value.to_le_bytes());
}

fn insert_string(dictionary: &mut Dictionary, key: &str, value: impl Into<String>) {
    dictionary.insert(key.to_string(), Value::String(value.into()));
}

fn insert_integer(dictionary: &mut Dictionary, key: &str, value: i64) {
    dictionary.insert(key.to_string(), Value::Integer(value.into()));
}

fn crc32_ieee(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;

    for byte in data {
        crc ^= u32::from(*byte);
        for _ in 0..8 {
            let mask = (crc & 1).wrapping_neg();
            crc = (crc >> 1) ^ (0xedb8_8320 & mask);
        }
    }

    !crc
}
