// SPDX-License-Identifier: MIT
//! Existing activity, goals, route and quotation screens, using Day pieces.
use crate::{
    Section,
    model::{Session, money, parse_price, text},
    pages::{back, error},
    res,
};
use day::prelude::*;
use serde_json::{Value, json};

pub(crate) fn page(s: Session, name: &str) -> AnyPiece {
    match name {
        "today" => today(s).any(),
        "clients" => clients(s).any(),
        "goals" => goals(s).any(),
        "analytics" => analytics(s).any(),
        "route" => route(s).any(),
        "quotes" => quotes(s).any(),
        "quote-editor" => quote_editor(s).any(),
        "quote-detail" => quote_detail(s).any(),
        "levels" => levels(s).any(),
        _ => hub(s).any(),
    }
}
fn data(s: Session, key: &str) -> Value {
    s.data.get()["workspace"][key].clone()
}
fn rows(s: Session, key: &str) -> Vec<Value> {
    data(s, key).as_array().cloned().unwrap_or_default()
}
fn link(s: Session, title: LocalizedText, target: &'static str) -> impl Piece {
    button(title).action(move || s.open(target))
}
fn hub(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::activity()),
            section((
                link(s, res::str::today(), "today"),
                link(s, res::str::quotes(), "quotes"),
                link(s, res::str::stock_levels(), "levels"),
                link(s, res::str::register_sale(), "sale"),
                link(s, res::str::client_follow_up(), "clients"),
                link(s, res::str::daily_route(), "route"),
            ))
            .title(res::str::your_activity()),
            section((
                link(s, res::str::analytics(), "analytics"),
                link(s, res::str::weekly_goals(), "goals"),
                link(s, res::str::sales_profit(), "profits"),
            ))
            .title(res::str::results()),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn record_links(s: Session, which: &'static str) -> impl Piece {
    each(
        items(
            move || {
                let ids = data(s, "today")[which]
                    .as_array()
                    .cloned()
                    .unwrap_or_default();
                s.rows("records")
                    .into_iter()
                    .filter(|r| ids.iter().any(|id| id.as_str() == r["id"].as_str()))
                    .collect::<Vec<_>>()
            },
            |r: &Value| text(r, "id"),
        ),
        move |slot| {
            button(move || text(&slot.get()["place"], "name"))
                .action(move || s.open_record(text(&slot.get(), "id")))
        },
    )
}
fn today(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::today()),
            section((
                button(res::str::find_write_nfc()).action(move || {
                    s.tab.set(Section::Home);
                }),
                labeled(
                    res::str::today_sales(),
                    label(move || money(data(s, "today")["salesCents"].as_i64().unwrap_or(0))),
                ),
                link(s, res::str::register_sale(), "sale"),
                link(s, res::str::quotes(), "quotes"),
            )),
            section((
                goal(s, "cards", "cards", res::str::cards()),
                link(s, res::str::view_goals(), "goals"),
            ))
            .title(res::str::week_goal()),
            section((
                record_links(s, "visits"),
                link(s, res::str::organize_route(), "route"),
            ))
            .title(res::str::today_visits()),
            section((
                record_links(s, "followUps"),
                link(s, res::str::all_clients(), "clients"),
            ))
            .title(res::str::pending_clients()),
            link(s, res::str::stock_levels(), "levels"),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn clients(s: Session) -> impl Piece {
    let query = Signal::new(String::new());
    let stage = Signal::new(String::new());
    scroll(
        column((
            back(s, res::str::client_follow_up()),
            text_field(query).placeholder(res::str::search_saved()),
            picker(
                stage,
                vec![
                    (String::new(), res::str::all().format()),
                    ("Pendiente".to_owned(), "Pendiente".to_owned()),
                    ("Interesado".to_owned(), "Interesado".to_owned()),
                    ("Volver".to_owned(), "Volver".to_owned()),
                    ("Vendido".to_owned(), "Vendido".to_owned()),
                ],
            ),
            each(
                items(
                    move || {
                        s.rows("records")
                            .into_iter()
                            .filter(|r| {
                                let q = query.get().to_lowercase();
                                let t = stage.get();
                                (t.is_empty() || text(r, "stage") == t)
                                    && text(&r["place"], "name").to_lowercase().contains(&q)
                            })
                            .collect::<Vec<_>>()
                    },
                    |r: &Value| text(r, "id"),
                ),
                move |slot| {
                    section((
                        button(move || text(&slot.get()["place"], "name"))
                            .action(move || s.open_record(text(&slot.get(), "id"))),
                        label(move || text(&slot.get(), "stage")).secondary(),
                    ))
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn goal(
    s: Session,
    actual: &'static str,
    target: &'static str,
    title: LocalizedText,
) -> impl Piece {
    column((
        labeled(
            title,
            label(move || {
                format!(
                    "{} / {}",
                    data(s, "weekly")[actual].as_i64().unwrap_or(0),
                    data(s, "goals")[target].as_i64().unwrap_or(1)
                )
            }),
        ),
        progress(move || {
            (data(s, "weekly")[actual].as_f64().unwrap_or(0.0)
                / data(s, "goals")[target].as_f64().unwrap_or(1.0).max(1.0))
            .clamp(0.0, 1.0)
        }),
    ))
}
fn view_date(s: Session) -> impl Piece {
    let date = Signal::new(
        DayDate::parse_iso(&text(&s.data.peek()["workspace"], "day"))
            .unwrap_or_else(DayDate::today),
    );
    day_reactive::watch(
        move || date.get(),
        move |d, _| {
            s.send(
                "workspaceDate",
                json!({"date":format!("{:04}-{:02}-{:02}",d.year,d.month,d.day)}),
                json!([]),
                false,
            );
        },
    );
    date_picker(date)
}
fn chart(s: Session, monthly: bool) -> impl Piece {
    use day_piece_charts::{LegendPosition, Stacking, bar, chart, value};
    chart(move || {
        let input = if monthly {
            rows(s, "monthly")
        } else {
            data(s, "weekly")["days"]
                .as_array()
                .cloned()
                .unwrap_or_default()
        };
        input
            .iter()
            .flat_map(|d| {
                let x = if monthly {
                    text(d, "month")
                } else {
                    text(d, "day")
                };
                let other = if monthly { "expense" } else { "profit" };
                [
                    ("income", res::str::income().format(), Color::hex(0x0A84FF)),
                    (
                        other,
                        if monthly {
                            res::str::expenses().format()
                        } else {
                            res::str::profit().format()
                        },
                        if monthly {
                            Color::hex(0xFF9F0A)
                        } else {
                            Color::hex(0x30D158)
                        },
                    ),
                ]
                .into_iter()
                .map(move |(key, name, color)| {
                    bar(
                        value("day", x.clone()),
                        value("amount", d[key].as_f64().unwrap_or(0.0) / 100.0),
                    )
                    .stacking(Stacking::Unstacked)
                    .by_series(value("series", name.clone()))
                    .by_position(value("series", name))
                    .foreground(color)
                })
            })
            .collect()
    })
    .series_colors(move |index, _| {
        if index == 0 {
            Color::hex(0x0A84FF)
        } else if monthly {
            Color::hex(0xFF9F0A)
        } else {
            Color::hex(0x30D158)
        }
    })
    .legend(LegendPosition::Bottom)
    .height(220.0)
    .grow(Dimension::Width)
}
fn goals(s: Session) -> impl Piece {
    let g = data(s, "goals");
    let cards = Signal::new(g["cards"].as_f64().unwrap_or(25.0));
    let visits = Signal::new(g["visits"].as_f64().unwrap_or(10.0));
    let profit = Signal::new(format!(
        "{:.2}",
        g["profitCents"].as_f64().unwrap_or(10000.0) / 100.0
    ));
    scroll(column((back(s,res::str::weekly_goals()),
        section((labeled(res::str::week_of(),view_date(s)),goal(s,"cards","cards",res::str::cards()),goal(s,"visits","visits",res::str::visited_businesses()),
            labeled(res::str::profit(),label(move||format!("{} / {}",money(data(s,"weekly")["profit"].as_i64().unwrap_or(0)),money(data(s,"goals")["profitCents"].as_i64().unwrap_or(0))))),
            when(move||data(s,"weekly")["unknownCosts"].as_bool().unwrap_or(false),||label(res::str::partial_profit()).secondary()),
        )).title(res::str::this_week()),
        section((chart(s,false),)).title(res::str::daily_income_profit()),
        section((labeled(res::str::cards(),stepper(cards).range(1.0..=100_000.0)),labeled(res::str::visited_businesses(),stepper(visits).range(1.0..=100_000.0)),labeled(res::str::weekly_profit(),text_field(profit).input_purpose(day_spec::InputPurpose::Decimal)),
            button(res::str::save_goals()).enabled(move||!s.busy()).action(move||s.send("goals",json!({"cards":format!("{:.0}",cards.peek()),"visits":format!("{:.0}",visits.peek()),"profit":profit.peek()}),json!([]),false)),
        )).title(res::str::your_goals()).footer(res::str::goals_hint()),error(s),
    )).spacing(Space::L).padding(Space::L))
}
fn analytics(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::analytics()),
            section((
                labeled(res::str::month(), view_date(s)),
                chart(s, true),
                labeled(
                    res::str::income_current(),
                    label(move || {
                        money(
                            rows(s, "monthly")
                                .get(1)
                                .and_then(|v| v["income"].as_i64())
                                .unwrap_or(0),
                        )
                    }),
                ),
                labeled(
                    res::str::income_previous(),
                    label(move || {
                        money(
                            rows(s, "monthly")
                                .first()
                                .and_then(|v| v["income"].as_i64())
                                .unwrap_or(0),
                        )
                    }),
                ),
                labeled(
                    res::str::income_change(),
                    label(move || {
                        let m = rows(s, "monthly");
                        money(
                            m.get(1).and_then(|v| v["income"].as_i64()).unwrap_or(0)
                                - m.first().and_then(|v| v["income"].as_i64()).unwrap_or(0),
                        )
                    }),
                ),
            ))
            .title(res::str::compare_months()),
            label(res::str::product_results()).font(Font::Headline),
            each(
                items(move || rows(s, "performance"), |p: &Value| text(p, "id")),
                move |slot| {
                    section((
                        label(move || text(&slot.get(), "name")).font(Font::Headline),
                        labeled(
                            res::str::income(),
                            label(move || money(slot.get()["revenue"].as_i64().unwrap_or(0))),
                        ),
                        labeled(
                            res::str::profit(),
                            label(move || {
                                slot.get()["profit"]
                                    .as_i64()
                                    .map(money)
                                    .unwrap_or_else(|| res::str::unknown_cost().format())
                            }),
                        ),
                    ))
                },
            ),
            label(res::str::clients_profit()).font(Font::Headline),
            each(
                items(
                    move || {
                        let mut r = s.rows("records");
                        r.sort_by_key(|r| {
                            std::cmp::Reverse(r["profitCents"].as_i64().unwrap_or(i64::MIN))
                        });
                        r
                    },
                    |r: &Value| text(r, "id"),
                ),
                move |slot| {
                    button(move || text(&slot.get()["place"], "name"))
                        .action(move || s.open_record(text(&slot.get(), "id")))
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn route(s: Session) -> impl Piece {
    let date = Signal::new(
        DayDate::parse_iso(&text(&s.data.peek()["workspace"], "routeDay"))
            .unwrap_or_else(DayDate::today),
    );
    let walking = Signal::new(
        s.data.peek()["workspace"]["routeWalking"]
            .as_bool()
            .unwrap_or(true),
    );
    day_reactive::watch(
        move || (date.get(), walking.get()),
        move |(d, w), _| {
            s.send("routeDate",json!({"date":format!("{:04}-{:02}-{:02}",d.year,d.month,d.day),"walking":w.to_string()}),json!([]),false);
        },
    );
    scroll(
        column((
            back(s, res::str::daily_route()),
            section((
                date_picker(date),
                button(res::str::order_location()).action(move || s.command("routeLocate")),
                labeled(res::str::walking(), toggle(walking)),
            ))
            .footer(res::str::route_hint()),
            section((each(
                items(move || rows(s, "routeLegs"), |l: &Value| text(l, "id")),
                move |slot| {
                    button(move || {
                        res::str::route_leg(res::str::RouteLeg {
                            start: slot.get()["start"].as_i64().unwrap_or(1),
                            end: slot.get()["end"].as_i64().unwrap_or(1),
                        })
                    })
                    .action(move || {
                        s.send(
                            "externalURL",
                            json!({"url":text(&slot.get(),"url")}),
                            json!([]),
                            false,
                        )
                    })
                },
            ),))
            .title(res::str::open_route()),
            each(
                items(move || rows(s, "routes"), |r: &Value| text(r, "id")),
                move |slot| {
                    section((
                        button(move || text(&slot.get(), "name"))
                            .action(move || s.open_record(text(&slot.get(), "id"))),
                        label(move || text(&slot.get(), "time")),
                        label(move || text(&slot.get(), "address")).secondary(),
                        label(move || text(&slot.get(), "distance")).secondary(),
                        button(res::str::directions()).action(move || {
                            s.send(
                                "directions",
                                json!({"record":text(&slot.get(),"id")}),
                                json!([]),
                                false,
                            )
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
fn levels(s: Session) -> impl Piece {
    scroll(
        column((
            back(s, res::str::stock_levels()),
            each(
                items(move || s.rows("products"), |p: &Value| text(p, "id")),
                move |slot| {
                    section((
                        button(move || text(&slot.get(), "name")).action(move || {
                            s.selected_product.set(text(&slot.get(), "id"));
                            s.open("product-detail");
                        }),
                        label(move || {
                            res::str::stock_minimum(res::str::StockMinimum {
                                count: slot.get()["stock"].as_i64().unwrap_or(0),
                                minimum: slot.get()["minimumStock"].as_i64().unwrap_or(5),
                            })
                        })
                        .secondary(),
                    ))
                },
            ),
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}
fn quote(s: Session) -> Value {
    rows(s, "quotes")
        .into_iter()
        .find(|q| text(q, "id") == s.selected_quote.get())
        .unwrap_or(Value::Null)
}
fn quotes(s: Session) -> impl Piece {
    let client = if s.history.peek().last().map(String::as_str) == Some("record") {
        s.selected.peek()
    } else {
        String::new()
    };
    scroll(
        column((
            back(s, res::str::quotes()),
            link(s, res::str::new_quote(), "quote-editor"),
            each(
                items(
                    move || {
                        rows(s, "quotes")
                            .into_iter()
                            .filter(|q| client.is_empty() || text(q, "businessID") == client)
                            .collect::<Vec<_>>()
                    },
                    |q: &Value| text(q, "id"),
                ),
                move |slot| {
                    section((
                        button(move || {
                            format!(
                                "{} · {}",
                                text(&slot.get(), "number"),
                                text(&slot.get(), "businessName")
                            )
                        })
                        .action(move || {
                            s.selected_quote.set(text(&slot.get(), "id"));
                            s.open("quote-detail");
                        }),
                        label(move || {
                            format!(
                                "{} · {}",
                                money(slot.get()["totalCents"].as_i64().unwrap_or(0)),
                                text(&slot.get(), "status")
                            )
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
fn quote_subtotal(lines: &[Value]) -> Option<i64> {
    lines.iter().try_fold(0i64, |sum, item| {
        let unit = parse_price(&text(item, "price"))?;
        let quantity = text(item, "quantity").parse::<i64>().ok()?;
        if unit > 1_000_000_000 || !(1..=100_000).contains(&quantity) {
            return None;
        }
        let total = sum.checked_add(unit.checked_mul(quantity)?)?;
        (total <= 1_000_000_000).then_some(total)
    })
}
fn quote_sum(lines: Signal<Vec<Value>>) -> Option<i64> {
    quote_subtotal(&lines.get())
}

fn quote_editor(s: Session) -> impl Piece {
    let business = Signal::new(
        if s.history
            .peek()
            .iter()
            .any(|p| ["record", "tracking"].contains(&p.as_str()))
        {
            s.selected.peek()
        } else {
            String::new()
        },
    );
    let product = Signal::new(String::new());
    let quantity = Signal::new(1.0);
    let price = Signal::new(String::new());
    let lines = Signal::new(Vec::<Value>::new());
    let discount = Signal::new(0.0);
    let validity = Signal::new(30.0);
    let notes = Signal::new(String::new());
    scroll(column((back(s,res::str::new_quote()),form((
        section((labeled(res::str::business(),picker(business,move||std::iter::once((String::new(),res::str::select_business().format())).chain(s.rows("records").iter().map(|r|(text(r,"id"),text(&r["place"],"name")))).collect::<Vec<_>>())),)),
        section((picker(product,move||std::iter::once((String::new(),res::str::select_product().format())).chain(s.rows("products").iter().map(|p|(text(p,"id"),text(p,"name")))).collect::<Vec<_>>()),labeled(res::str::quantity(),stepper(quantity).range(1.0..=100_000.0)),labeled(res::str::unit_price(),text_field(price).input_purpose(day_spec::InputPurpose::Decimal)),
            button(res::str::new_product()).enabled(move||!product.get().is_empty()&&lines.get().len()<20&&parse_price(&price.get()).is_some_and(|v|v<=1_000_000_000)&&!lines.get().iter().any(|p|text(p,"product")==product.get())).action(move||{let mut draft=lines.peek();let id=product.peek();let name=s.rows("products").iter().find(|p|text(p,"id")==id).map(|p|text(p,"name")).unwrap_or_default();draft.push(json!({"product":id,"name":name,"quantity":format!("{:.0}",quantity.peek()),"price":price.peek()}));lines.set(draft);product.set(String::new());quantity.set(1.0);}),
            each(items(move||lines.get(),|p:&Value|text(p,"product")),move|slot|row((label(move||format!("{} × {}",text(&slot.get(),"quantity"),text(&slot.get(),"name"))),spacer(),button(res::str::remove_product()).action(move||{let id=text(&slot.get(),"product");lines.set(lines.peek().into_iter().filter(|p|text(p,"product")!=id).collect());})))),
        )).title(res::str::products()).footer(res::str::quote_stock_hint()),
        section((labeled(res::str::discount(),stepper(discount).range(0.0..=100.0)),labeled(res::str::validity(),stepper(validity).range(1.0..=365.0)),labeled(res::str::quote_notes(),text_area(notes)),labeled(res::str::total(),label(move||{let subtotal=quote_sum(lines).unwrap_or(0);money(subtotal-(subtotal*discount.get().clamp(0.0,100.0).round() as i64+50)/100)})),
            button(res::str::save_quote()).prominent().enabled(move||!s.busy()&&!business.get().is_empty()&&quote_sum(lines).is_some_and(|v|v>0)&&!lines.get().is_empty()).action(move||{let draft=lines.peek().iter().map(|p|json!({"product":text(p,"product"),"quantity":text(p,"quantity"),"price":text(p,"price")})).collect::<Vec<_>>();s.send("quote",json!({"record":business.peek(),"discount":format!("{:.0}",discount.peek()),"validity":format!("{:.0}",validity.peek()),"notes":notes.peek()}),json!(draft),true);}),
        )).title(res::str::conditions()),
    )),error(s))).spacing(Space::L).padding(Space::L))
}
fn quote_detail(s: Session) -> impl Piece {
    let payment = Signal::new("Transferencia".to_owned());
    let summary = section((
        label(move || text(&quote(s), "businessName")).font(Font::Headline),
        labeled(res::str::quote(), label(move || text(&quote(s), "number"))),
        labeled(res::str::status(), label(move || text(&quote(s), "status"))),
        labeled(
            res::str::valid_until(),
            label(move || text(&quote(s), "expiryLabel")),
        ),
        each(
            items(
                move || quote(s)["items"].as_array().cloned().unwrap_or_default(),
                |p: &Value| text(p, "productID"),
            ),
            move |slot| {
                labeled(
                    move || {
                        format!(
                            "{} × {}",
                            slot.get()["quantity"],
                            text(&slot.get(), "title")
                        )
                    },
                    label(move || {
                        money(
                            slot.get()["quantity"].as_i64().unwrap_or(0)
                                * slot.get()["unitPriceCents"].as_i64().unwrap_or(0),
                        )
                    }),
                )
            },
        ),
        labeled(
            res::str::total(),
            label(move || money(quote(s)["totalCents"].as_i64().unwrap_or(0))),
        ),
        label(move || text(&quote(s), "notes")),
    ));
    let sharing = section((
        button(res::str::prepare_pdf())
            .enabled(move || !s.busy())
            .action(move || {
                s.send(
                    "quotePDF",
                    json!({"quote":s.selected_quote.peek()}),
                    json!([]),
                    false,
                )
            }),
        when(
            move || quote(s)["saleID"].is_null(),
            move || {
                column((
                    button(res::str::mark_sent())
                        .enabled(move || !s.busy())
                        .action(move || {
                            s.send(
                                "quoteStatus",
                                json!({"quote":s.selected_quote.peek(),"status":"Enviado"}),
                                json!([]),
                                false,
                            )
                        }),
                    button(res::str::mark_declined())
                        .enabled(move || !s.busy())
                        .action(move || {
                            s.send(
                                "quoteStatus",
                                json!({"quote":s.selected_quote.peek(),"status":"Rechazado"}),
                                json!([]),
                                false,
                            )
                        }),
                ))
            },
        ),
    ));
    let conversion = when(
        move || quote(s)["canConvert"].as_bool().unwrap_or(false),
        move || {
            section((
            labeled(res::str::payment(), picker(payment, ["Efectivo","Tarjeta","Bizum","Transferencia","Otro"].into_iter().map(|p|(p.to_owned(),p.to_owned())).collect::<Vec<_>>())),
            button(res::str::convert_sale()).prominent().enabled(move || !s.busy()).action(move || {
                day::task(async move {
                    if confirm(res::str::confirm_quote_sale()).confirm_label(res::str::register_sale()).cancel_label(res::str::back()).present().await {
                        s.send("convertQuote",json!({"quote":s.selected_quote.peek(),"payment":payment.peek()}),json!([]),false);
                    }
                });
            }),
        ))
        },
    );
    scroll(
        column((
            back(s, res::str::quote()),
            summary,
            sharing,
            conversion,
            error(s),
        ))
        .spacing(Space::L)
        .padding(Space::L),
    )
}

#[cfg(test)]
mod tests {
    use super::quote_subtotal;
    use serde_json::json;
    #[test]
    fn quotation_preview_preserves_cents_and_rejects_excessive_values() {
        assert_eq!(
            quote_subtotal(&[
                json!({"price":"0,33","quantity":"3"}),
                json!({"price":"0.01","quantity":"2"})
            ]),
            Some(101)
        );
        assert_eq!(
            quote_subtotal(&[json!({"price":"10000000","quantity":"1"})]),
            Some(1_000_000_000)
        );
        assert_eq!(
            quote_subtotal(&[json!({"price":"10000000","quantity":"2"})]),
            None
        );
        assert_eq!(
            quote_subtotal(&[json!({"price":"999999999999999999999","quantity":"100000"})]),
            None
        );
        assert_eq!(
            quote_subtotal(&[json!({"price":"15","quantity":"-1"})]),
            None
        );
    }
}
