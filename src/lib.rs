// SPDX-License-Identifier: MIT
//! Preserve the iPhone interface through Day's supported SwiftUI hosting piece.

use day::prelude::*;

mod native;

day::resources!();
day::day_start!(options: res::window_options(), root);

pub mod swiftui {
    include!(concat!(env!("OUT_DIR"), "/day_swiftui.rs"));
}

pub fn root() -> impl Piece {
    day::on_open_url(native::forward_url);
    if day_piece_swiftui::support() == Support::Native {
        return swiftui::ReviewNfcGoView()
            .state_key("reviewnfcgo-root")
            .id(day::id!(iphone_app))
            .grow(Dimension::Both)
            .any();
    }

    // The required website presents the iPhone app; it never asks for a password
    // or pretends a browser can write NFC.
    scroll(
        column((
            label(res::str::app_title())
                .font(Font::LargeTitle)
                .a11y(|a| a.role(Role::Heading(1)))
                .id(day::id!(site_title)),
            label(res::str::site_intro()).font(Font::Headline),
            label(res::str::site_features()).markdown(),
            label(res::str::site_availability()).secondary(),
            label(res::str::site_privacy()).markdown(),
        ))
        .spacing(Space::L)
        .padding(Space::XL)
        .max_width(700.0),
    )
    .id(day::id!(website))
    .any()
}
