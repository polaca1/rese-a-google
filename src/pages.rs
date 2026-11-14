// SPDX-License-Identifier: MIT
use crate::model::SaleLineFields;
use crate::{
    Section,
    model::{Session, money, text},
    res,
};
use base64::Engine as _;
use day::prelude::*;

use serde_json::{Value, json};

pub(crate) fn root(s: Session) -> impl Piece {
    if !cfg!(target_os = "ios") && !cfg!(feature = "verification") {
        return scroll(
            column((
                label(res::str::app_title()).font(Font::LargeTitle),
                label(res::str::site_intro()),
                label(res::str::site_features()),
                label(res::str::site_availability()),
                label(res::str::site_privacy()).markdown(),
            ))
            .spacing(Space::L)
            .padding(Space::XL),
        )
        .any();
    }
    switch(
        move || s.ready(),
        move |ready| {
            if *ready {
                workspace(s).any()
            } else {
                auth(s).any()
            }
        },
    )
    .id(day::id!(application))
    .any()
}
fn workspace(s: Session) -> impl Piece {
    nav(s.tab)
        .style(NavStyle::Tabs)
        .items((
            item(Section::Places, res::str::tab_places())
                .icon(res::vectors::tab_places)
                .page(move || content(s, Section::Places)),
            item(Section::Money, res::str::tab_money())
                .icon(res::vectors::tab_money)
                .page(move || content(s, Section::Money)),
            item(Section::Alerts, res::str::tab_alerts())
                .icon(res::vectors::tab_alerts)
                .page(move || content(s, Section::Alerts)),
            item(Section::Home, res::str::tab_home())
                .icon(res::vectors::tab_home)
                .page(move || content(s, Section::Home)),
            item(Section::Profile, res::str::tab_profile())
                .icon(res::vectors::tab_profile)
                .page(move || content(s, Section::Profile)),
        ))
        .id(day::id!(main_tabs))
}
fn content(s: Session, tab: Section) -> impl Piece {
    switch(
        move || {
            let page = if s.page_owner.get() == tab {
                s.page.get()
            } else {
                String::new()
            };
            let record = if ["record", "edit", "reminder", "sale"].contains(&page.as_str()) {
                s.selected.get()
            } else {
                String::new()
            };
            (page, record)
        },
        move |(page, _)| match page.as_str() {
            "nfc-question" => nfc_question(s).any(),
            "record" => record(s).any(),
            "edit" => edit_record(s).any(),
            "sale" => sale(s).any(),
            "expense" => expense(s, false).any(),
            "product" => expense(s, true).any(),
            "inventory" => inventory(s).any(),
            "product-detail" => product_detail(s).any(),
            "stock" => stock(s).any(),
            "transaction" => transaction(s).any(),
            "tracking" => tracking(s).any(),
            "profits" => profits(s).any(),
            "activity" | "today" | "clients" | "goals" | "analytics" | "route" | "quotes"
            | "quote-editor" | "quote-detail" | "levels" => crate::workspace::page(s, page),
            "reminder" => reminder(s).any(),
            "password" => password(s).any(),
            _ => match tab {
                Section::Places => places(s).any(),
                Section::Money => wallet(s).any(),
                Section::Alerts => alerts(s).any(),
                Section::Home => home(s).any(),
                Section::Profile => profile(s).any(),
            },
        },
    )
}
pub(crate) fn error(s: Session) -> impl Piece {
    column((
        when(
            move || !s.text("error").is_empty(),
            move || label(move || s.text("error")).color(Color::hex(0xFF453A)),
        ),
        when(
            move || !s.text("saveProblem").is_empty(),
            move || {
                section((
                    label(move || s.text("saveProblem")),
                    button(res::str::retry()).action(move || s.command("sync")),
                    when(
                        move || s.data.get()["conflict"].as_bool() == Some(true),
                        move || {
                            column((
                                button(res::str::keep_remote()).action(move || {
                                    s.send(
                                        "resolveCloud",
                                        json!({"remote":"true"}),
                                        json!([]),
                                        false,
                                    )
                                }),
                                button(res::str::keep_local()).action(move || {
                                    s.send(
                                        "resolveCloud",
                                        json!({"remote":"false"}),
                                        json!([]),
                                        false,
                                    )
                                }),
                            ))
                        },
                    ),
                ))
            },
        ),
    ))
}
fn heading(title: LocalizedText) -> impl Piece {
    label(title)
        .font(Font::LargeTitle)
        .a11y(|a| a.role(Role::Heading(1)))
}
pub(crate) fn back(s: Session, title: LocalizedText) -> impl Piece {
    row((
        button(res::str::back())
            .icon(Symbol::Back)
            .action(move || s.back()),
        label(title).font(Font::Headline),
        spacer(),
        button(res::str::done()).action(move || s.command("dismissKeyboard")),
    ))
}
fn auth(s: Session) -> impl Piece {
    let name = Signal::new(String::new());
    let email = Signal::new(String::new());
    let pass = Signal::new(String::new());
    let create = Signal::new(false);
    scroll(
        column((
            row((
                image(move || {
                    day::ImageSource::Named(
                        if day::dark_mode() {
                            res::images::brand_dark
                        } else {
                            res::images::brand
                        }
                        .as_str()
                        .to_owned(),
                    )
                })
                .frame(58.0, 58.0)
                .decorative(),
                column((
                    heading(res::str::app_title()),
                    label(res::str::tagline()).secondary(),
                )),
            ))
            .spacing(Space::M),
            label(move || {
                if create.get() {
                    res::str::create_account()
                } else {
                    res::str::sign_in()
                }
            })
            .font(Font::Headline),
            label(res::str::sign_in_description()).secondary(),
            form((section((
                when(
                    move || create.get(),
                    move || labeled(res::str::name(), text_field(name).id(day::id!(auth_name))),
                ),
                labeled(
                    res::str::email(),
                    text_field(email)
                        .input_purpose(day_spec::InputPurpose::Email)
                        .id(day::id!(auth_email)),
                ),
                labeled(
                    res::str::password(),
                    secure_field(pass)
                        .input_purpose(day_spec::InputPurpose::Password)
                        .id(day::id!(auth_password)),
                ),
            )),)),
            error(s),
            button(move || {
                if create.get() {
                    res::str::create_account()
                } else {
                    res::str::enter()
                }
            })
            .prominent()
            .grow(Dimension::Width)
            .enabled(move || {
                !s.busy()
                    && !email.get().trim().is_empty()
                    && !pass.get().is_empty()
                    && (!create.get() || !name.get().trim().is_empty())
            })
            .action(move || {
                s.send(
                    if create.peek() { "register" } else { "login" },
                    json!({"name":name.peek(),"email":email.peek(),"password":pass.peek()}),
                    json!([]),
                    false,
                );
                pass.set(String::new());
            })
            .id(day::id!(auth_submit)),
            link(
                res::str::forgot_password(),
                "https://polaca1.github.io/rese-a-google/reset-password.html",
            ),
            button(res::str::google())
                .image(res::images::google)
                .bordered()
                .grow(Dimension::Width)
                .enabled(move || !s.busy())
                .action(move || s.command("google"))
                .id(day::id!(auth_google)),
            label(res::str::account_linking()).secondary(),
            button(move || {
                if create.get() {
                    res::str::have_account()
                } else {
                    res::str::create_account()
                }
            })
            .action(move || {
                create.set(!create.peek());
                pass.set(String::new());
            }),
        ))
        .spacing(Space::L)
        .padding(Space::XL),
    )
    .id(day::id!(auth_screen))
}
fn places(s: Session) -> impl Piece {
    scroll(
        column((
            heading(res::str::tab_places()),
            text_field(s.query)
                .placeholder(res::str::search_saved())
                .id(day::id!(places_search)),
            each(
                items(
                    move || {
                        let q = s.query.get().to_lowercase();
                        s.rows("records")
                            .into_iter()
                            .filter(|r| text(&r["place"], "name").to_lowercase().contains(&q))
                            .collect::<Vec<_>>()
                    },
                    |r: &Value| text(r, "id"),
                ),
                move |slot| {
                    section((
                        button(move || text(&slot.get()["place"], "name"))
                            .action(move || s.open_record(text(&slot.get(), "id"))),
                        label(move || text(&slot.get()["place"], "address")).secondary(),
                        label(move || text(&slot.get(), "stage")),
                    ))
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
    .id(day::id!(places_screen))
}
fn wallet(s: Session) -> impl Piece {
    scroll(
        column((
            row((
                heading(res::str::tab_money()),
                spacer(),
                button(res::str::register_expense())
                    .icon(Symbol::Add)
                    .icon_only()
                    .bordered()
                    .action(move || s.open("expense")),
            )),
            section((
                label(res::str::available_balance()).secondary(),
                label(move || money(s.data.get()["balanceCents"].as_i64().unwrap_or(0)))
                    .font(Font::System(42.0))
                    .bold()
                    .id(day::id!(balance)),
                row((
                    column((
                        label(res::str::income()).secondary(),
                        label(move || money(s.data.get()["incomeCents"].as_i64().unwrap_or(0)))
                            .color(Color::hex(0x30D158)),
                    )),
                    spacer(),
                    column((
                        label(res::str::expenses()).secondary(),
                        label(move || money(s.data.get()["expenseCents"].as_i64().unwrap_or(0)))
                            .color(Color::hex(0xFF9F0A)),
                    )),
                )),
                label(res::str::balance_hint()).secondary(),
            )),
            section((
                button(res::str::register_sale())
                    .icon(Symbol::Add)
                    .action(move || s.open("sale")),
                button(res::str::activity_goals()).action(move || s.open("activity")),
                button(res::str::register_expense())
                    .icon(Symbol::Add)
                    .action(move || s.open("expense")),
                button(res::str::profits()).action(move || s.open("profits")),
                button(res::str::inventory()).action(move || s.open("inventory")),
                when(
                    move || !s.text("undoTitle").is_empty(),
                    move || {
                        button(move || s.text("undoTitle"))
                            .icon(Symbol::Undo)
                            .action(move || s.command("undo"))
                    },
                ),
            )),
            label(res::str::history()).font(Font::Headline),
            each(
                items(move || s.rows("transactions"), |r: &Value| text(r, "id")),
                move |slot| {
                    section((
                        row((
                            button(move || text(&slot.get(), "title")).action(move || {
                                s.selected_transaction.set(text(&slot.get(), "id"));
                                s.open("transaction");
                            }),
                            spacer(),
                            label(move || money(slot.get()["cents"].as_i64().unwrap_or(0))),
                        )),
                        label(move || text(&slot.get(), "paymentMethod")).secondary(),
                    ))
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
    .id(day::id!(money_screen))
}
fn alerts(s: Session) -> impl Piece {
    scroll(
        column((
            heading(res::str::tab_alerts()),
            each(
                items(
                    move || {
                        s.rows("records")
                            .into_iter()
                            .filter(|r| r["reminderDate"].as_f64().unwrap_or(0.0) > 0.0)
                            .collect::<Vec<_>>()
                    },
                    |r: &Value| text(r, "id"),
                ),
                move |slot| {
                    section((
                        button(move || text(&slot.get()["place"], "name"))
                            .action(move || s.open_record(text(&slot.get(), "id"))),
                        label(move || text(&slot.get(), "reminderLabel")).secondary(),
                    ))
                },
            ),
            label(res::str::history()).font(Font::Headline),
            each(
                items(move || s.rows("alerts"), |r: &Value| text(r, "id")),
                move |slot| {
                    section((
                        label(move || text(&slot.get(), "title")),
                        label(move || text(&slot.get(), "body")).secondary(),
                    ))
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
    .id(day::id!(alerts_screen))
}
fn home(s: Session) -> impl Piece {
    let query = Signal::new(String::new());
    scroll(
        column((
            row((
                column((
                    label(move || {
                        res::str::greeting(
                            text(&s.data.get()["user"], "name")
                                .split_whitespace()
                                .next()
                                .unwrap_or("")
                                .to_owned(),
                        )
                    })
                    .font(Font::Headline),
                    label(res::str::review_caption()).secondary(),
                )),
                spacer(),
                avatar(s, 42.0),
            )),
            row((
                text_field(query)
                    .placeholder(res::str::search_place())
                    .id(day::id!(place_query)),
                button(res::str::search())
                    .icon(Symbol::Search)
                    .action(move || {
                        s.send("search", json!({"query":query.peek()}), json!([]), false)
                    }),
            )),
            crate::mapkit::map(s.data)
                .height(330.0)
                .grow(Dimension::Width)
                .corner_radius(22.0)
                .id(day::id!(home_map)),
            row((
                label(move || s.text("locationStatus")).secondary(),
                spacer(),
                button(res::str::my_location())
                    .icon(Symbol::Location)
                    .enabled(move || !s.busy())
                    .action(move || s.command("locate"))
                    .id(day::id!(locate)),
            )),
            each(
                items(
                    move || {
                        let a = s.rows("choices");
                        if a.is_empty() {
                            s.rows("searchResults")
                        } else {
                            a
                        }
                    },
                    |p: &Value| text(p, "id"),
                ),
                move |slot| {
                    section((
                        button(move || text(&slot.get(), "name")).action(move || {
                            s.send(
                                "choose",
                                json!({"place":text(&slot.get(),"id")}),
                                json!([]),
                                false,
                            )
                        }),
                        label(move || text(&slot.get(), "address")).secondary(),
                    ))
                },
            ),
            keyed(
                move || {
                    s.data.get()["selectedPlace"]["id"]
                        .as_str()
                        .map(str::to_owned)
                },
                move |_| {
                    section((
                        label(move || text(&s.data.get()["selectedPlace"], "name"))
                            .font(Font::Headline),
                        label(move || text(&s.data.get()["selectedPlace"], "address")).secondary(),
                        button(res::str::write_nfc())
                            .prominent()
                            .grow(Dimension::Width)
                            .enabled(move || !s.busy())
                            .action(move || s.command("writeSelectedNFC")),
                        button(res::str::copy_review_link())
                            .bordered()
                            .grow(Dimension::Width)
                            .enabled(move || !s.busy())
                            .action(move || s.command("copySelectedLink")),
                        button(res::str::return_later())
                            .bordered()
                            .grow(Dimension::Width)
                            .enabled(move || !s.busy())
                            .action(move || s.command("prepareReminder")),
                    ))
                },
            ),
            when(
                move || !s.text("locationError").is_empty(),
                move || label(move || s.text("locationError")).color(Color::hex(0xFF453A)),
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
    .id(day::id!(home_screen))
}
fn profile(s: Session) -> impl Piece {
    scroll(
        column((
            heading(res::str::tab_profile()),
            section((
                row((
                    avatar(s, 64.0),
                    column((
                        label(move || text(&s.data.get()["user"], "name")).font(Font::Headline),
                        label(move || text(&s.data.get()["user"], "email")).secondary(),
                    )),
                ))
                .spacing(Space::M),
                button(res::str::profile_photo()).action(move || s.command("photo")),
                button(res::str::remove_photo()).action(move || s.command("removePhoto")),
            )),
            section((
                labeled(
                    res::str::saved_places(),
                    label(move || s.rows("records").len().to_string()),
                ),
                labeled(
                    res::str::balance(),
                    label(move || money(s.data.get()["balanceCents"].as_i64().unwrap_or(0))),
                ),
                labeled(
                    res::str::sold_cards(),
                    label(move || s.data.get()["cardsSold"].as_i64().unwrap_or(0).to_string()),
                ),
            ))
            .title(res::str::summary()),
            section((
                button(res::str::link_google())
                    .image(res::images::google)
                    .action(move || s.command("google")),
                button(res::str::change_password()).action(move || s.open("password")),
                button(res::str::sign_out()).action(move || {
                    day::task(async move {
                        let confirm_needed = s.data.peek()["signOutNeedsConfirmation"]
                            .as_bool()
                            .unwrap_or(false);
                        if !confirm_needed
                            || confirm(res::str::confirm_sign_out())
                                .message(res::str::confirm_sign_out_body())
                                .confirm_label(res::str::sign_out_anyway())
                                .cancel_label(res::str::stay())
                                .destructive()
                                .present()
                                .await
                        {
                            s.command("logout");
                        }
                    });
                }),
            )),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
    .id(day::id!(profile_screen))
}
fn record(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::business()),
            label(move || text(&s.record()["place"], "name")).font(Font::LargeTitle),
            label(move || text(&s.record()["place"], "address")).secondary(),
            section((
                button(res::str::write_nfc()).action(move || {
                    s.send(
                        "writeNFC",
                        json!({"record":s.selected.peek()}),
                        json!([]),
                        false,
                    )
                }),
                button(res::str::register_sale()).action(move || s.open("sale")),
                button(res::str::tracking()).action(move || s.open("tracking")),
                button(res::str::client_quotes()).action(move || s.open("quotes")),
                button(res::str::directions()).action(move || {
                    s.send(
                        "directions",
                        json!({"record":s.selected.peek()}),
                        json!([]),
                        false,
                    )
                }),
                button(res::str::edit()).action(move || s.open("edit")),
                button(res::str::reminder()).action(move || s.open("reminder")),
            )),
            section((
                label(move || text(&s.record(), "notes")),
                label(move || text(&s.record(), "contactName")),
                label(move || text(&s.record(), "contactPhone")),
                label(move || text(&s.record(), "contactEmail")),
            )),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn edit_record(s: Session) -> impl Piece {
    let r = s.record();
    let notes = Signal::new(text(&r, "notes"));
    let name = Signal::new(text(&r, "contactName"));
    let email = Signal::new(text(&r, "contactEmail"));
    let phone = Signal::new(text(&r, "contactPhone"));
    scroll(column((back(s,res::str::edit()),form((section((labeled(res::str::contact_name(),text_field(name)),labeled(res::str::email(),text_field(email)),labeled(res::str::phone(),text_field(phone)),labeled(res::str::notes(),text_area(notes)))),)),
        button(res::str::save()).prominent().enabled(move||!s.busy()).action(move||s.send("editRecord",json!({"record":s.selected.peek(),"notes":notes.peek(),"contactName":name.peek(),"contactEmail":email.peek(),"contactPhone":phone.peek()}),json!([]),true)),error(s),
    )).spacing(Space::L).padding(Space::L))
}
fn sale(s: Session) -> impl Piece {
    s.prepare_cart();
    let business = Signal::new(s.selected.peek());
    let payment = Signal::new("Efectivo".to_owned());
    let body = form((
        section((labeled(
            res::str::business(),
            picker(business, move || {
                std::iter::once((String::new(), res::str::select_business().format()))
                    .chain(
                        s.rows("records")
                            .iter()
                            .map(|r| (text(r, "id"), text(&r["place"], "name"))),
                    )
                    .collect::<Vec<_>>()
            }),
        ),))
        .title(res::str::customer()),
        section((
            each(s.cart.rows(move || s.cart.keys()), move |line| {
                column((
                    row((
                        column((
                            label(move || line.name().read()).font(Font::Headline),
                            label(move || res::str::stock_count(i64::from(line.stock().read())))
                                .secondary(),
                        )),
                        spacer(),
                        toggle(line.selected()).a11y(move |a| a.label(line.name().read())),
                    )),
                    when(
                        move || line.selected().read(),
                        move || {
                            column((
                                labeled(
                                    res::str::quantity(),
                                    stepper(
                                        line.quantity().map(
                                            |v: &i32| f64::from(*v),
                                            |v: &f64| v.round() as i32,
                                        ),
                                    )
                                    .range(1.0..=f64::from(line.stock().peek().clamp(1, 100_000))),
                                ),
                                switch(
                                    move || s.cart_has_card() && line.kind().read() == "stand",
                                    move |free| {
                                        if *free {
                                            labeled(
                                                res::str::included_with_cards(),
                                                label(res::str::free()).color(Color::hex(0x30D158)),
                                            )
                                            .any()
                                        } else {
                                            labeled(
                                                res::str::unit_price(),
                                                text_field(line.price())
                                                    .input_purpose(day_spec::InputPurpose::Decimal)
                                                    .on_submit(move || {
                                                        s.command("dismissKeyboard")
                                                    }),
                                            )
                                            .any()
                                        }
                                    },
                                ),
                            ))
                            .spacing(Space::M)
                        },
                    ),
                ))
                .spacing(Space::M)
                .padding(Space::M)
            }),
            button(res::str::add_stock()).action(move || s.open("inventory")),
        ))
        .title(res::str::what_sold())
        .footer(res::str::stand_policy()),
        section((
            labeled(
                res::str::payment(),
                picker(
                    payment,
                    vec![
                        "Efectivo".to_owned(),
                        "Tarjeta".to_owned(),
                        "Bizum".to_owned(),
                        "Transferencia".to_owned(),
                        "Otro".to_owned(),
                    ]
                    .into_iter()
                    .map(|p| (p.clone(), p))
                    .collect::<Vec<_>>(),
                ),
            ),
            labeled(
                res::str::total(),
                label(move || {
                    s.cart_total()
                        .map(money)
                        .unwrap_or_else(|| res::str::check_prices().format())
                }),
            ),
            keyed(
                move || crate::native::sale_preview(&json!(s.cart_rows()))["profit"].as_i64(),
                |profit| labeled(res::str::profit(), label(money(*profit))),
            ),
        ))
        .title(res::str::collection()),
    ));
    column((
        back(s, res::str::new_sale()).padding(Space::L),
        scroll(body).grow(Dimension::Both),
        error(s).padding(Space::S),
        row((
            button(res::str::done()).action(move || s.command("dismissKeyboard")),
            button(res::str::save_sale())
                .prominent()
                .grow(Dimension::Width)
                .enabled(move || {
                    !s.busy() && !business.get().is_empty() && s.cart_total().is_some_and(|v| v > 0)
                })
                .action(move || {
                    s.send(
                        "sale",
                        json!({"record":business.peek(),"payment":payment.peek()}),
                        json!(s.cart_rows()),
                        true,
                    )
                })
                .id(day::id!(save_sale)),
        ))
        .padding(Space::M),
    ))
    .grow(Dimension::Both)
}
fn expense(s: Session, new_product: bool) -> impl Piece {
    let name = Signal::new(String::new());
    let amount = Signal::new(String::new());
    let quantity = Signal::new("1".to_owned());
    let product = Signal::new(
        if s.history.peek().last().map(String::as_str) == Some("product-detail") {
            s.selected_product.peek()
        } else {
            String::new()
        },
    );
    let kind = Signal::new("nfcCard".to_owned());
    let notes = Signal::new(String::new());
    let fields = section((
        labeled(res::str::name(), text_field(name)),
        labeled(res::str::amount(), text_field(amount)),
        labeled(res::str::quantity(), text_field(quantity)),
        when(
            move || !new_product,
            move || {
                labeled(
                    res::str::product(),
                    picker(product, move || {
                        s.rows("products")
                            .iter()
                            .map(|p| (text(p, "id"), text(p, "name")))
                            .collect::<Vec<_>>()
                    }),
                )
            },
        ),
        when(
            move || new_product,
            move || {
                labeled(
                    res::str::kind(),
                    picker(
                        kind,
                        vec![
                            ("nfcCard".to_owned(), res::str::nfc_card()),
                            ("stand".to_owned(), res::str::stand()),
                            ("accessory".to_owned(), res::str::accessory()),
                            ("custom".to_owned(), res::str::custom_product()),
                        ],
                    ),
                )
            },
        ),
        labeled(res::str::notes(), text_area(notes)),
    ));
    scroll(column((
        back(s,if new_product{res::str::new_product()}else{res::str::register_expense()}),
        form((fields,)),
        button(res::str::save()).prominent().enabled(move||!s.busy()).action(move||s.send(
            if new_product{"product"}else{"expense"},
            json!({"name":name.peek(),"amount":amount.peek(),"quantity":quantity.peek(),"product":product.peek(),"kind":kind.peek(),"notes":notes.peek()}),json!([]),true)),
        error(s),
    )).spacing(Space::L).padding(Space::L))
}
fn inventory(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::inventory()),
            button(res::str::new_product())
                .icon(Symbol::Add)
                .action(move || s.open("product")),
            each(
                items(move || s.rows("products"), |p: &Value| text(p, "id")),
                move |slot| {
                    section((
                        button(move || text(&slot.get(), "name")).action(move || {
                            s.selected_product.set(text(&slot.get(), "id"));
                            s.open("product-detail");
                        }),
                        label(move || {
                            res::str::stock_count(slot.get()["stock"].as_i64().unwrap_or(0))
                        }),
                    ))
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn local_picker(value: &str) -> (DayDate, DayTime) {
    let (d, t) = value.split_once(' ').unwrap_or(("", ""));
    let mut parts = t.split(':');
    let time = parts
        .next()
        .and_then(|h| h.parse().ok())
        .zip(parts.next().and_then(|m| m.parse().ok()))
        .and_then(|(h, m)| DayTime::new(h, m, 0))
        .unwrap_or_else(|| DayTime::new(10, 0, 0).unwrap());
    (DayDate::parse_iso(d).unwrap_or_else(DayDate::today), time)
}
fn picker_text(date: DayDate, time: DayTime) -> String {
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}",
        date.year, date.month, date.day, time.hour, time.minute
    )
}
fn reminder(s: Session) -> impl Piece {
    let r = s.record();
    let (d, t) = local_picker(&text(&r, "visitLocal"));
    let (nd, nt) = local_picker(&text(&r, "noticeLocal"));
    let date = Signal::new(d);
    let time = Signal::new(t);
    let notice_date = Signal::new(nd);
    let notice_time = Signal::new(nt);
    let note = Signal::new(text(&r, "notes"));
    scroll(column((back(s,res::str::reminder()),form((section((
        labeled(res::str::visit_date(),date_picker(date)),
        labeled(res::str::visit_time(),time_picker(time)),
        labeled(res::str::notice_date(),date_picker(notice_date)),
        labeled(res::str::notice_time(),time_picker(notice_time)),
        labeled(res::str::notes(),text_area(note)),
    )).footer(res::str::notice_hint()),)),
        button(res::str::save()).prominent().enabled(move||!s.busy()).action(move||s.send("reminder",json!({"record":s.selected.peek(),"visit":picker_text(date.peek(),time.peek()),"notification":picker_text(notice_date.peek(),notice_time.peek()),"notes":note.peek()}),json!([]),true)),error(s),
    )).spacing(Space::L).padding(Space::L))
}

fn password(s: Session) -> impl Piece {
    let value = Signal::new(String::new());
    scroll(
        column((
            back(s, res::str::change_password()),
            section((labeled(res::str::new_password(), secure_field(value)),)),
            button(res::str::save())
                .enabled(move || !s.busy() && value.get().len() >= 8)
                .action(move || {
                    s.send(
                        "password",
                        json!({"password":value.peek()}),
                        json!([]),
                        true,
                    );
                    value.set(String::new());
                }),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}

fn nfc_question(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::nfc_question()),
            label(res::str::nfc_question_body()),
            button(res::str::yes_sold()).prominent().action(move || {
                s.command("finishNFC");
                s.open("sale");
            }),
            button(res::str::no_sale())
                .action(move || s.send("finishNFC", json!({}), json!([]), true)),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::XL),
    )
}

fn avatar(s: Session, size: f64) -> impl Piece {
    switch(
        move || !s.text("photo").is_empty(),
        move |has_photo| {
            if *has_photo {
                image(move || {
                    day::ImageSource::Bytes(std::sync::Arc::new(
                        base64::engine::general_purpose::STANDARD
                            .decode(s.text("photo"))
                            .unwrap_or_default(),
                    ))
                })
                .frame(size, size)
                .corner_radius(size / 2.0)
                .any()
            } else {
                vector(res::vectors::tab_profile)
                    .template()
                    .frame(size, size)
                    .decorative()
                    .any()
            }
        },
    )
}

fn product_value(s: Session) -> Value {
    s.rows("products")
        .into_iter()
        .find(|p| text(p, "id") == s.selected_product.get())
        .unwrap_or(Value::Null)
}
fn product_detail(s: Session) -> impl Piece {
    let minimum = Signal::new(
        product_value(s)["minimumStock"]
            .as_i64()
            .unwrap_or(5)
            .to_string(),
    );
    scroll(
        column((
            back(s, res::str::product()),
            section((
                label(move || text(&product_value(s), "name")).font(Font::Headline),
                labeled(
                    res::str::available_stock(),
                    label(move || product_value(s)["stock"].as_i64().unwrap_or(0).to_string()),
                ),
                labeled(
                    res::str::purchased_units(),
                    label(move || {
                        product_value(s)["purchased"]
                            .as_i64()
                            .unwrap_or(0)
                            .to_string()
                    }),
                ),
                labeled(
                    res::str::sold_cards(),
                    label(move || product_value(s)["sold"].as_i64().unwrap_or(0).to_string()),
                ),
                labeled(
                    res::str::spent(),
                    label(move || money(product_value(s)["spentCents"].as_i64().unwrap_or(0))),
                ),
            )),
            section((
                button(res::str::new_purchase()).action(move || s.open("expense")),
                button(res::str::adjust_stock()).action(move || s.open("stock")),
                labeled(
                    res::str::minimum_stock(),
                    text_field(minimum).input_purpose(day_spec::InputPurpose::Number),
                ),
                button(res::str::save_minimum())
                    .enabled(move || {
                        !s.busy() && minimum.get().parse::<u32>().is_ok_and(|v| v <= 100_000)
                    })
                    .action(move || {
                        s.send(
                            "minimumStock",
                            json!({"product":s.selected_product.peek(),"quantity":minimum.peek()}),
                            json!([]),
                            false,
                        )
                    }),
            )),
            label(res::str::product_movements()).font(Font::Headline),
            each(
                items(
                    move || {
                        s.rows("transactions")
                            .into_iter()
                            .filter(|t| text(t, "productID") == s.selected_product.get())
                            .collect::<Vec<_>>()
                    },
                    |t: &Value| text(t, "id"),
                ),
                move |slot| {
                    button(move || text(&slot.get(), "title")).action(move || {
                        s.selected_transaction.set(text(&slot.get(), "id"));
                        s.open("transaction");
                    })
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn stock(s: Session) -> impl Piece {
    let quantity = Signal::new(product_value(s)["stock"].as_i64().unwrap_or(0).to_string());
    let reason = Signal::new(String::new());
    column((
        back(s, res::str::adjust_stock()),
        form((section((
            labeled(res::str::current_stock(), label(move || product_value(s)["stock"].as_i64().unwrap_or(0).to_string())),
            labeled(res::str::actual_stock(), text_field(quantity).input_purpose(day_spec::InputPurpose::Number)),
            labeled(res::str::adjustment_reason(), text_area(reason)),
        )).footer(res::str::adjustment_hint()),)),
        button(res::str::save()).prominent().enabled(move || !s.busy() && !reason.get().trim().is_empty() && quantity.get().parse::<i64>().is_ok_and(|q| (0..=100_000).contains(&q) && q != product_value(s)["stock"].as_i64().unwrap_or(0)))
            .action(move || s.send("stock",json!({"product":s.selected_product.peek(),"quantity":quantity.peek(),"notes":reason.peek()}),json!([]),true)),
        error(s),
    )).spacing(Space::L).padding(Space::L)
}
fn transaction_value(s: Session) -> Value {
    s.rows("transactions")
        .into_iter()
        .find(|t| text(t, "id") == s.selected_transaction.get())
        .unwrap_or(Value::Null)
}
fn transaction(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::transaction()),
            section((
                label(move || text(&transaction_value(s), "title")).font(Font::Headline),
                label(move || money(transaction_value(s)["cents"].as_i64().unwrap_or(0)))
                    .font(Font::LargeTitle),
                label(move || text(&transaction_value(s), "paymentMethod")),
                label(move || text(&transaction_value(s), "merchant")),
                label(move || text(&transaction_value(s), "notes")),
            )),
            when(
                move || !text(&transaction_value(s), "businessID").is_empty(),
                move || {
                    button(res::str::open_business())
                        .action(move || s.open_record(text(&transaction_value(s), "businessID")))
                },
            ),
            when(
                move || text(&transaction_value(s), "kind") == "expense",
                move || {
                    button(res::str::reverse_expense())
                        .enabled(move || !s.busy())
                        .action(move || {
                            day::task(async move {
                                if confirm(res::str::confirm_reverse())
                                    .message(res::str::reverse_hint())
                                    .confirm_label(res::str::reverse_expense())
                                    .cancel_label(res::str::back())
                                    .destructive()
                                    .present()
                                    .await
                                {
                                    s.send(
                                        "reverseExpense",
                                        json!({"transaction":s.selected_transaction.peek()}),
                                        json!([]),
                                        false,
                                    );
                                }
                            });
                        })
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn tracking(s: Session) -> impl Piece {
    let stage = Signal::new(text(&s.record(), "stage"));
    let note = Signal::new(String::new());
    scroll(column((
        back(s,res::str::tracking()),
        label(move || text(&s.record()["place"],"name")).font(Font::Headline),
        section((
            labeled(res::str::status(), picker(stage,vec!["Pendiente".to_owned(),"Interesado".to_owned(),"Volver".to_owned(),"Vendido".to_owned()].into_iter().map(|v|(v.clone(),v)).collect::<Vec<_>>())),
            labeled(res::str::add_timeline_note(), text_area(note)),
            button(res::str::save_tracking()).enabled(move || !s.busy()).action(move || s.send("tracking",json!({"record":s.selected.peek(),"stage":stage.peek(),"notes":note.peek(),"visited":"false"}),json!([]),true)),
            button(res::str::mark_visited()).enabled(move || !s.busy()).action(move || s.send("tracking",json!({"record":s.selected.peek(),"stage":stage.peek(),"notes":note.peek(),"visited":"true"}),json!([]),true)),
            button(res::str::reminder()).action(move || s.open("reminder")),
        )),
        labeled(res::str::income(),label(move || money(s.record()["incomeCents"].as_i64().unwrap_or(0)))),
        label(res::str::history()).font(Font::Headline),
        each(items(move || s.record()["followUp"].as_array().cloned().unwrap_or_default(), |e:&Value|text(e,"id")), move |slot| section((label(move || text(&slot.get(),"text")),))),
        error(s),
    )).spacing(Space::L).padding(Space::L))
}
pub(crate) fn profits(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::profits()),
            label(res::str::profit_hint()).secondary(),
            each(
                items(
                    move || {
                        s.rows("records")
                            .into_iter()
                            .filter(|r| r["incomeCents"].as_i64().unwrap_or(0) > 0)
                            .collect::<Vec<_>>()
                    },
                    |r: &Value| text(r, "id"),
                ),
                move |slot| {
                    section((
                        button(move || text(&slot.get()["place"], "name"))
                            .action(move || s.open_record(text(&slot.get(), "id"))),
                        labeled(
                            res::str::income(),
                            label(move || money(slot.get()["incomeCents"].as_i64().unwrap_or(0))),
                        ),
                        labeled(
                            res::str::profit(),
                            label(move || {
                                slot.get()["profitCents"]
                                    .as_i64()
                                    .map(money)
                                    .unwrap_or_else(|| res::str::unknown_cost().format())
                            }),
                        ),
                    ))
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
