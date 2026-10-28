mod wire { include!(concat!(env!("CARGO_MANIFEST_DIR"), "/watch_pair_wire.rs")); }
mod production { include!(concat!(env!("CARGO_MANIFEST_DIR"), "/watch_pairing.rs")); }
use rsa::{
    RsaPrivateKey, RsaPublicKey, pkcs1::EncodeRsaPublicKey,
    pkcs8::{DecodePrivateKey, DecodePublicKey, LineEnding},
    pkcs1v15::{VerifyingKey, Signature}, signature::Verifier,
};
use sha2::Sha256;
use x509_cert::{Certificate, der::{Decode, DecodePem, Encode}, ext::pkix::{BasicConstraints, KeyUsage, KeyUsages}};
fn main() {
    let (host, buid) = production::new_host_identity();
    assert!(wire::valid_identity(&host) && wire::valid_identity(&buid));
    assert_ne!(host, buid);
    assert_eq!(host.as_bytes()[14], b'4');
    assert!([b'8',b'9',b'A',b'B'].contains(&host.as_bytes()[19]));
    assert_eq!(wire::decode_identity(&format!("{host}\n{buid}\n")), Some((host.clone(),buid.clone())));
    assert!(wire::decode_identity(&format!("{host}\n{host}\n")).is_none());
    assert!(wire::decode_identity("PRIVATE\nDATA").is_none());
    let device = RsaPrivateKey::new(&mut rsa::rand_core::OsRng, 2048).unwrap();
    let device_public = RsaPublicKey::from(&device);
    let pem = device_public.to_pkcs1_pem(LineEnding::LF).unwrap();
    let chain = production::generate(pem.as_bytes()).unwrap();
    let mut record = plist::Dictionary::new();
    record.insert("HostID".into(), plist::Value::String(host));
    record.insert("SystemBUID".into(), plist::Value::String(buid));
    record.insert("RootCertificate".into(), plist::Value::Data(chain.root_certificate.clone()));
    record.insert("HostCertificate".into(), plist::Value::Data(chain.host_certificate.clone()));
    record.insert("DeviceCertificate".into(), plist::Value::Data(chain.device_certificate.clone()));
    record.insert("RootPrivateKey".into(), plist::Value::Data(chain.root_private_key.clone()));
    record.insert("HostPrivateKey".into(), plist::Value::Data(chain.host_private_key.clone()));
    record.insert("UDID".into(), plist::Value::String("PRIVATE-TEST-DEVICE".into()));
    let request = wire::request(&record, "SideStore Watch").unwrap();
    let mut xml = Vec::new(); request.to_writer_xml(&mut xml).unwrap();
    let decoded: plist::Value = plist::from_bytes(&xml).unwrap();
    let public = decoded.as_dictionary().unwrap()["PairRecord"].as_dictionary().unwrap();
    assert_eq!(public.len(),5);
    for key in ["RootCertificate","HostCertificate","DeviceCertificate"] { assert_eq!(public[key].as_data(),record[key].as_data()); }
    assert!(!public.contains_key("RootPrivateKey") && !public.contains_key("HostPrivateKey") && !public.contains_key("UDID"));
    assert!(!String::from_utf8(xml).unwrap().contains("PRIVATE-TEST-DEVICE"));
    // Replaying a persisted candidate preserves the exact trusted certificate bytes.
    let mut saved = Vec::new(); plist::Value::Dictionary(record.clone()).to_writer_xml(&mut saved).unwrap();
    let restored: plist::Dictionary = plist::from_bytes(&saved).unwrap();
    assert_eq!(wire::request(&restored,"SideStore Watch").unwrap(),request);
    let mut malformed = record.clone();
    malformed.insert("DeviceCertificate".into(),plist::Value::Array(vec![]));
    assert!(wire::request(&malformed,"SideStore Watch").is_err());
    let root = Certificate::from_pem(&chain.root_certificate).unwrap();
    let host = Certificate::from_pem(&chain.host_certificate).unwrap();
    let watch = Certificate::from_pem(&chain.device_certificate).unwrap();
    let root_key = RsaPrivateKey::from_pkcs8_pem(std::str::from_utf8(&chain.root_private_key).unwrap()).unwrap();
    let host_key = RsaPrivateKey::from_pkcs8_pem(std::str::from_utf8(&chain.host_private_key).unwrap()).unwrap();
    let root_public = RsaPublicKey::from_public_key_der(&root.tbs_certificate.subject_public_key_info.to_der().unwrap()).unwrap();
    let host_public = RsaPublicKey::from_public_key_der(&host.tbs_certificate.subject_public_key_info.to_der().unwrap()).unwrap();
    let watch_public = RsaPublicKey::from_public_key_der(&watch.tbs_certificate.subject_public_key_info.to_der().unwrap()).unwrap();
    assert_eq!(root_public, RsaPublicKey::from(&root_key));
    assert_eq!(host_public, RsaPublicKey::from(&host_key));
    assert_eq!(watch_public, device_public);
    assert_ne!(root_public, host_public);
    let verifier = VerifyingKey::<Sha256>::new(root_public);
    for (cert, ca) in [(&root, true), (&host, false), (&watch, false)] {
        assert!(cert.tbs_certificate.subject.is_empty());
        assert_eq!(cert.tbs_certificate.issuer, root.tbs_certificate.subject);
        let sig = Signature::try_from(cert.signature.raw_bytes()).unwrap();
        verifier.verify(&cert.tbs_certificate.to_der().unwrap(), &sig).unwrap();
        let extensions = cert.tbs_certificate.extensions.as_ref().unwrap();
        let basic = extensions.iter().find(|x| x.extn_id.to_string()=="2.5.29.19").unwrap();
        assert!(basic.critical);
        assert_eq!(BasicConstraints::from_der(basic.extn_value.as_bytes()).unwrap().ca, ca);
        if !ca {
            let usage = extensions.iter().find(|x| x.extn_id.to_string()=="2.5.29.15").unwrap();
            assert!(usage.critical);
            assert_eq!(KeyUsage::from_der(usage.extn_value.as_bytes()).unwrap().0,
                KeyUsages::DigitalSignature | KeyUsages::KeyEncipherment);
        }
    }
    assert!(watch.tbs_certificate.extensions.as_ref().unwrap().iter().any(|x| x.extn_id.to_string()=="2.5.29.14"));
    assert!(!host.tbs_certificate.extensions.as_ref().unwrap().iter().any(|x| x.extn_id.to_string()=="2.5.29.14"));
    // Wrong signer/key and modified data must not validate.
    let sig = Signature::try_from(watch.signature.raw_bytes()).unwrap();
    let mut tampered = watch.tbs_certificate.to_der().unwrap(); tampered[10] ^= 1;
    assert!(verifier.verify(&tampered, &sig).is_err());
    assert!(VerifyingKey::<Sha256>::new(host_public).verify(&watch.tbs_certificate.to_der().unwrap(), &sig).is_err());
    assert!(production::generate(b"not a device public key").is_err());
    println!("Watch certificate chain: root/leaf constraints, signatures, key bindings and negative cases passed.");
}
