// SPDX-License-Identifier: MIT
//! Application screens and navigation are native Day pieces, with no hosted SwiftUI view.
use day::prelude::*;
mod mapkit;
mod model;
mod native;
mod pages;
mod workspace;
day::resources!();
day::day_start!(options: res::window_options(), root);
day::routes! { pub(crate) enum Section { Places=>"places", Money=>"money", Alerts=>"alerts", Home=>"home", Profile=>"profile" } }

pub fn root() -> impl Piece {
    model::Session::scoped(|session| {
        session.start();
        day::on_open_url(move |url| {
            if url
                .split_once(':')
                .is_some_and(|(s, _)| s.eq_ignore_ascii_case("reviewnfcgo"))
            {
                session.send(
                    "openURL",
                    serde_json::json!({"url":url}),
                    serde_json::json!([]),
                    false,
                );
                true
            } else {
                false
            }
        });
        pages::root(session)
    })
}
