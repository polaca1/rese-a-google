// The Day external-piece adapter follows the documented Daybrite renderer pattern.
// Copyright © The Daybrite Project and reviewNfcGo contributors
// SPDX-License-Identifier: MPL-2.0
//! A MapKit control in the Day tree; no UIHostingController or SwiftUI application views.
use day::prelude::*;
use serde_json::Value;

pub(crate) fn map(state: Signal<Value>) -> AnyPiece {
    if support() == Support::Native {
        return AppleMap { state }.any();
    }
    // Only the non-device design preview uses this placeholder; production web is informational.
    label(crate::res::str::map_on_iphone())
        .secondary()
        .align(TextAlign::Center)
        .any()
}
fn support() -> Support {
    if cfg!(all(target_os = "ios", feature = "uikit")) {
        Support::Native
    } else {
        Support::Unsupported
    }
}
#[derive(Clone, Debug, PartialEq)]
struct MapProps {
    revision: u64,
}
#[derive(Clone, Debug, PartialEq)]
enum MapPatch {
    Refresh,
}
struct AppleMap {
    state: Signal<Value>,
}
impl day_core::Piece for AppleMap {
    fn build(self, cx: &mut day_core::BuildCx) -> day_core::RNode {
        let revision = crate::native::revision();
        let node = cx.leaf(
            "reviewnfcgo.mapkit",
            &MapProps { revision },
            day_core::Flex {
                grow_w: true,
                grow_h: true,
                ..Default::default()
            },
        );
        day_reactive::bind_seeded(
            revision,
            move || {
                let _ = self.state.get();
                crate::native::revision()
            },
            move |_| {
                day_core::with_tree(|tree| tree.patch(node, Box::new(MapPatch::Refresh), false));
            },
        );
        node
    }
}
#[cfg(all(target_os = "ios", feature = "uikit"))]
mod ios {
    use super::*;
    use day_spec::NodeId;
    use day_toolkit_uikit::Uikit;
    use objc2::rc::Retained;
    use objc2_ui_kit::UIView;
    use std::ffi::c_void;
    unsafe extern "C" {
        fn review_day_map_make() -> *mut c_void;
        fn review_day_map_refresh(view: *mut c_void);
    }
    fn make(_: &mut Uikit, _: &MapProps, _: NodeId) -> Retained<UIView> {
        // SAFETY: the UIKit renderer runs on the UI thread; Swift returns a +1 retained UIView.
        unsafe { Retained::from_raw(review_day_map_make().cast::<UIView>()) }
            .expect("MapKit native Day control")
    }
    fn update(_: &mut Uikit, view: &Retained<UIView>, _: &MapPatch) {
        // SAFETY: renderer owns this view; update borrows it on the same UI thread.
        unsafe { review_day_map_refresh((&**view as *const UIView).cast_mut().cast::<c_void>()) };
    }
    day_pieces::renderer!(day_toolkit_uikit::RENDERERS,Uikit,
        kind: "reviewnfcgo.mapkit", props: MapProps, patch: MapPatch, make: make, update: update,
        measure: day_pieces::fill_measure);
}
