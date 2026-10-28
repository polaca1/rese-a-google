// Watch-only Lockdown certificate chain. Does not alter iPhone pairing or app signing.
// Wire conventions checked against libimobiledevice and pymobiledevice3/ca.py.
use rsa::{
    RsaPrivateKey, RsaPublicKey, pkcs1::DecodeRsaPublicKey,
    pkcs1v15::{SigningKey, Signature},
    pkcs8::{EncodePrivateKey, LineEnding, SubjectPublicKeyInfo},
    signature::{Signer, SignatureEncoding},
};
use sha2::Sha256;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use x509_cert::{
    Certificate, certificate::{TbsCertificate, Version},
    der::{Encode, EncodePem, referenced::OwnedToRef, asn1::{BitString, GeneralizedTime, UtcTime}},
    ext::{AsExtension, pkix::{BasicConstraints, KeyUsage, KeyUsages, SubjectKeyIdentifier}},
    name::Name, serial_number::SerialNumber, time::{Time, Validity},
    spki::DynSignatureAlgorithmIdentifier,
};
type Error = Box<dyn std::error::Error>;
pub(crate) struct WatchPairingCertificates {
    pub root_certificate: Vec<u8>,
    pub root_private_key: Vec<u8>,
    pub host_certificate: Vec<u8>,
    pub host_private_key: Vec<u8>,
    pub device_certificate: Vec<u8>,
}
fn certificate_time(duration: Duration) -> Result<Time, Error> {
    match UtcTime::from_unix_duration(duration) {
        Ok(time) => Ok(Time::UtcTime(time)),
        Err(_) => Ok(Time::GeneralTime(GeneralizedTime::from_unix_duration(duration)?)),
    }
}
fn certificate(
    signer_key: &RsaPrivateKey, public_key: &RsaPublicKey,
    is_root: bool, device_ski: bool, validity: Validity,
) -> Result<Vec<u8>, Error> {
    let signer = SigningKey::<Sha256>::new(signer_key.clone());
    let algorithm = signer.signature_algorithm_identifier()?;
    let subject = Name::default();
    let public_key = SubjectPublicKeyInfo::from_key(public_key.clone())?;
    let mut extensions = Vec::new();
    let mut basic = BasicConstraints { ca: is_root, path_len_constraint: None }
        .to_extension(&subject, &extensions)?;
    basic.critical = true;
    extensions.push(basic);
    if !is_root {
        let mut usage = KeyUsage(KeyUsages::DigitalSignature | KeyUsages::KeyEncipherment)
            .to_extension(&subject, &extensions)?;
        usage.critical = true;
        extensions.push(usage);
    }
    if device_ski {
        let mut ski = SubjectKeyIdentifier::try_from(public_key.owned_to_ref())?
            .to_extension(&subject, &extensions)?;
        ski.critical = false;
        extensions.push(ski);
    }
    let tbs = TbsCertificate {
        version: Version::V3, serial_number: SerialNumber::new(&[1])?,
        signature: algorithm.clone(), issuer: subject.clone(), validity,
        subject, subject_public_key_info: public_key,
        issuer_unique_id: None, subject_unique_id: None, extensions: Some(extensions),
    };
    let signature: Signature = signer.sign(&tbs.to_der()?);
    let cert = Certificate {
        tbs_certificate: tbs, signature_algorithm: algorithm,
        signature: BitString::from_bytes(signature.to_bytes().as_ref())?,
    };
    Ok(cert.to_pem(LineEnding::LF)?.into_bytes())
}
pub(crate) fn generate(device_public_key: &[u8]) -> Result<WatchPairingCertificates, Error> {
    let device = RsaPublicKey::from_pkcs1_pem(std::str::from_utf8(device_public_key)?)?;
    let mut rng = rsa::rand_core::OsRng;
    let root = RsaPrivateKey::new(&mut rng, 2048)?;
    let host = RsaPrivateKey::new(&mut rng, 2048)?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?;
    // Same one-minute backdating used by the reference implementation.
    let validity = Validity {
        not_before: certificate_time(now.saturating_sub(Duration::from_secs(60)))?,
        not_after: certificate_time(now + Duration::from_secs(365 * 10 * 24 * 60 * 60))?,
    };
    Ok(WatchPairingCertificates {
        root_certificate: certificate(&root, &RsaPublicKey::from(&root), true, false, validity)?,
        host_certificate: certificate(&root, &RsaPublicKey::from(&host), false, false, validity)?,
        device_certificate: certificate(&root, &device, false, true, validity)?,
        root_private_key: root.to_pkcs8_pem(LineEnding::LF)?.as_bytes().to_vec(),
        host_private_key: host.to_pkcs8_pem(LineEnding::LF)?.as_bytes().to_vec(),
    })
}

pub(crate) fn new_host_identity() -> (String, String) {
    use rsa::rand_core::RngCore;
    fn uuid() -> String {
        let mut bytes = [0u8;16];
        rsa::rand_core::OsRng.fill_bytes(&mut bytes);
        bytes[6]=(bytes[6]&0x0F)|0x40;
        bytes[8]=(bytes[8]&0x3F)|0x80;
        let value: String = bytes.iter().map(|b| format!("{b:02X}")).collect();
        format!("{}-{}-{}-{}-{}", &value[..8], &value[8..12], &value[12..16], &value[16..20], &value[20..])
    }
    (uuid(), uuid())
}
