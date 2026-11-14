// SPDX-License-Identifier: MIT
//! FFI to native device/account services. It never creates or hosts application views.
#[cfg(target_os = "ios")]
unsafe extern "C" {
    fn review_day_revision() -> u64;
    fn review_day_state() -> *mut std::ffi::c_char;
    fn review_day_free(value: *mut std::ffi::c_char);
    fn review_day_command(value: *const std::ffi::c_char);
    fn review_day_sale_preview(value: *const std::ffi::c_char) -> *mut std::ffi::c_char;
}

pub(crate) fn revision() -> u64 {
    #[cfg(target_os = "ios")]
    // SAFETY: Day calls services on its UIKit main thread.
    unsafe {
        review_day_revision()
    }
    #[cfg(not(target_os = "ios"))]
    {
        0
    }
}

pub(crate) fn state() -> Option<serde_json::Value> {
    #[cfg(target_os = "ios")]
    unsafe {
        // SAFETY: native returns an owned NUL-terminated allocation; copy before free.
        let pointer = review_day_state();
        if pointer.is_null() {
            return None;
        }
        let bytes = std::ffi::CStr::from_ptr(pointer).to_bytes();
        let result = if bytes.len() <= 32_000_000 {
            serde_json::from_slice(bytes).ok()
        } else {
            None
        };
        review_day_free(pointer);
        result
    }
    #[cfg(not(target_os = "ios"))]
    {
        None
    }
}

pub(crate) fn command(value: &serde_json::Value) {
    #[cfg(target_os = "ios")]
    if let Ok(text) = std::ffi::CString::new(value.to_string()) {
        // SAFETY: Swift copies these bytes synchronously. Day invokes us on the UI thread.
        unsafe { review_day_command(text.as_ptr()) };
    }
    #[cfg(not(target_os = "ios"))]
    let _ = value;
}

pub(crate) fn sale_preview(rows: &serde_json::Value) -> serde_json::Value {
    #[cfg(target_os = "ios")]
    if let Ok(text) = std::ffi::CString::new(rows.to_string()) {
        // SAFETY: native copies input and returns owned UTF-8 JSON; UIKit thread only.
        unsafe {
            let pointer = review_day_sale_preview(text.as_ptr());
            if !pointer.is_null() {
                let value = serde_json::from_slice(std::ffi::CStr::from_ptr(pointer).to_bytes())
                    .unwrap_or_default();
                review_day_free(pointer);
                return value;
            }
        }
    }
    #[cfg(not(target_os = "ios"))]
    let _ = rows;
    serde_json::Value::Null
}
