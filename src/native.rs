// SPDX-License-Identifier: MIT
//! Delivery of Day's cold/warm URL events to the unchanged SwiftUI router.

#[cfg(target_os = "ios")]
unsafe extern "C" {
    fn reviewnfcgo_open_url(value: *const std::ffi::c_char);
}

fn is_app_url(value: &str) -> bool {
    !value.contains('\0')
        && value
            .split_once(':')
            .is_some_and(|(scheme, _)| scheme.eq_ignore_ascii_case("reviewnfcgo"))
}

pub(crate) fn forward_url(value: &str) -> bool {
    if !is_app_url(value) {
        return false;
    }
    #[cfg(target_os = "ios")]
    {
        let Ok(value) = std::ffi::CString::new(value) else {
            return false;
        };
        // SAFETY: Day invokes this callback on the UI thread. Swift copies the
        // valid, NUL-terminated bytes before this CString is dropped.
        unsafe { reviewnfcgo_open_url(value.as_ptr()) };
        return true;
    }
    #[cfg(not(target_os = "ios"))]
    false
}

#[cfg(test)]
mod tests {
    use super::is_app_url;

    #[test]
    fn preserve_complete_business_links() {
        assert!(is_app_url("reviewnfcgo://business/abc?section=money"));
        assert!(is_app_url("ReviewNfcGo://business/abc"));
    }

    #[test]
    fn decline_other_apps_and_truncated_c_strings() {
        for url in [
            "https://example.com/reviewnfcgo://business/abc",
            "reviewnfcgo-malicious://business/abc",
            "reviewnfcgo://business/abc\0?hidden=value",
            "javascript:reviewnfcgo://business/abc",
            "reviewnfcgo",
        ] {
            assert!(!is_app_url(url));
        }
    }
}
