mod production { include!(concat!(env!("CARGO_MANIFEST_DIR"), "/watch_pairing.rs")); }
use rsa::{
    RsaPrivateKey, RsaPublicKey, pkcs1::EncodeRsaPublicKey,
    pkcs8::{DecodePrivateKey, DecodePublicKey, LineEnding},
    pkcs1v15::{VerifyingKey, Signature}, signature::Verifier,
};
use sha2::Sha256;
use x509_cert::{Certificate, der::{Decode, DecodePem, Encode}, ext::pkix::{BasicConstraints, KeyUsage, KeyUsages}};
fn main() {
    let device = RsaPrivateKey::new(&mut rsa::rand_core::OsRng, 2048).unwrap();
    let device_public = RsaPublicKey::from(&device);
    let pem = device_public.to_pkcs1_pem(LineEnding::LF).unwrap();
    let chain = production::generate(pem.as_bytes()).unwrap();
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
