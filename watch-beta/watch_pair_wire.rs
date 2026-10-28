use plist::{Dictionary, Value};
type Error = Box<dyn std::error::Error>;
pub(crate) fn valid_identity(value: &str) -> bool {
    value.len() == 36 && value.bytes().enumerate().all(|(i,b)|
        if [8,13,18,23].contains(&i) { b == b'-' }
        else { b.is_ascii_digit() || (b'A'..=b'F').contains(&b) })
}
pub(crate) fn decode_identity(value: &str) -> Option<(String,String)> {
    let lines: Vec<_> = value.lines().collect();
    if lines.len()!=2 || !valid_identity(lines[0]) || !valid_identity(lines[1]) || lines[0]==lines[1] { return None; }
    Some((lines[0].to_owned(),lines[1].to_owned()))
}
/// Explicit wire types and an allowlist keep local private material off the wire.
pub(crate) fn request(record: &Dictionary, name: &str) -> Result<Value, Error> {
    let mut public = Dictionary::new();
    for key in ["DeviceCertificate", "HostCertificate", "RootCertificate"] {
        let data = record.get(key).and_then(Value::as_data).filter(|d| !d.is_empty() && d.len()<=1_048_576)
            .ok_or("Invalid Watch certificate field")?;
        public.insert(key.into(), Value::Data(data.to_vec()));
    }
    for key in ["HostID","SystemBUID"] {
        let value = record.get(key).and_then(Value::as_string).filter(|s| !s.is_empty() && s.len()<=128)
            .ok_or("Invalid Watch identity field")?;
        public.insert(key.into(), Value::String(value.to_owned()));
    }
    let mut options = Dictionary::new();
    options.insert("ExtendedPairingErrors".into(), Value::Boolean(true));
    let mut request = Dictionary::new();
    request.insert("Label".into(), Value::String("SideStore Watch".into()));
    request.insert("Request".into(), Value::String("Pair".into()));
    request.insert("HostName".into(), Value::String(name.to_owned()));
    request.insert("ProtocolVersion".into(), Value::String("2".into()));
    request.insert("PairRecord".into(), Value::Dictionary(public));
    request.insert("PairingOptions".into(), Value::Dictionary(options));
    Ok(Value::Dictionary(request))
}
