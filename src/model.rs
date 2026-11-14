// SPDX-License-Identifier: MIT
use crate::{Section, native};
use day::prelude::*;
use serde_json::{Value, json};

#[derive(Observable, Clone, Default)]
pub(crate) struct SaleLine {
    #[obs(key)]
    pub id: u64,
    pub product: String,
    pub name: String,
    pub kind: String,
    pub stock: i32,
    pub selected: bool,
    pub quantity: i32,
    pub price: String,
}

#[derive(Clone, Copy)]
pub(crate) struct Session {
    pub data: Signal<Value>,
    pub cart: Store<Keyed<SaleLine>>,
    pub tab: Signal<Section>,
    pub page: Signal<String>,
    pub history: Signal<Vec<String>>,
    pub submitted_page: Signal<String>,
    pub page_owner: Signal<Section>,
    pub selected: Signal<String>,
    pub query: Signal<String>,
    pub pending: Signal<String>,
    pub close_on_success: Signal<bool>,
    pub sequence: Signal<u64>,
    pub nfc_seen: Signal<String>,
}
impl Ambient for Session {
    fn create() -> Self {
        Self {
            data: Signal::new(initial_state()),
            cart: Store::new(Keyed::default()),
            tab: Signal::new(Section::Home),
            page: Signal::new(String::new()),
            history: Signal::new(Vec::new()),
            submitted_page: Signal::new(String::new()),
            page_owner: Signal::new(Section::Home),
            selected: Signal::new(String::new()),
            query: Signal::new(String::new()),
            pending: Signal::new(String::new()),
            close_on_success: Signal::new(false),
            sequence: Signal::new(0),
            nfc_seen: Signal::new(String::new()),
        }
    }
}
impl Session {
    pub fn clear_cart(self) {
        for key in self.cart.keys() {
            self.cart.remove(key);
        }
    }
    pub fn prepare_cart(self) {
        let initially_empty = self.cart.keys().is_empty();
        let products = self.rows("products");
        for key in self.cart.keys() {
            let line = self.cart.elem(key);
            if !products.iter().any(|p| {
                text(p, "id") == line.product().peek() && p["stock"].as_i64().unwrap_or(0) > 0
            }) {
                self.cart.remove(key);
            }
        }
        for p in products
            .iter()
            .filter(|p| p["stock"].as_i64().unwrap_or(0) > 0)
        {
            let product = text(p, "id");
            if let Some(key) = self
                .cart
                .keys()
                .into_iter()
                .find(|key| self.cart.elem(*key).product().peek() == product)
            {
                let line = self.cart.elem(key);
                line.name().update(|name| *name = text(p, "name"));
                line.stock()
                    .update(|stock| *stock = p["stock"].as_i64().unwrap_or(0).min(100_000) as i32);
                continue;
            }
            self.cart.push(SaleLine {
                id: self.cart.next_key(),
                product,
                name: text(p, "name"),
                kind: text(p, "kind"),
                stock: p["stock"].as_i64().unwrap_or(0).min(100_000) as i32,
                selected: initially_empty && p["defaultSelected"].as_bool().unwrap_or(false),
                quantity: 1,
                price: text(p, "defaultPrice"),
            });
        }
    }
    pub fn cart_has_card(self) -> bool {
        self.cart.keys().iter().any(|k| {
            let l = self.cart.elem(*k);
            l.selected().read() && l.kind().read() == "nfcCard"
        })
    }
    pub fn cart_rows(self) -> Vec<Value> {
        self.cart.keys().into_iter().filter_map(|k|{let l=self.cart.elem(k);if !l.selected().read(){return None;}Some(json!({"product":l.product().read(),"quantity":l.quantity().read().to_string(),"price":l.price().read()}))}).collect()
    }
    pub fn cart_total(self) -> Option<i64> {
        if cfg!(target_os = "ios") {
            return native::sale_preview(&json!(self.cart_rows()))["total"].as_i64();
        }
        let card = self.cart_has_card();
        let mut sum = 0_i64;
        let mut count = 0;
        for k in self.cart.keys() {
            let l = self.cart.elem(k);
            if !l.selected().read() {
                continue;
            }
            count += 1;
            let cents = if card && l.kind().read() == "stand" {
                0
            } else {
                parse_price(&l.price().read())?
            };
            let qty = i64::from(l.quantity().read());
            if qty < 1 {
                return None;
            }
            sum = sum.checked_add(cents.checked_mul(qty)?)?;
        }
        if count == 0 || sum <= 0 {
            None
        } else {
            Some(sum)
        }
    }
    pub fn start(self) {
        let handle = day::task(async move {
            let mut seen = u64::MAX;
            loop {
                let revision = native::revision();
                if revision != seen
                    && let Some(value) = native::state()
                {
                    seen = revision;
                    self.apply(value);
                }
                day::sleep(300).await;
            }
        });
        Scope::current().on_cleanup(move || handle.abort());
    }
    fn apply(self, value: Value) {
        let changed_owner = value["user"]["email"] != self.data.peek()["user"]["email"];
        if changed_owner {
            self.clear_cart();
            self.history.set(Vec::new());
            self.selected.set(String::new());
            self.page.set(String::new());
            self.pending.set(String::new());
            self.nfc_seen.set(String::new());
        }
        let finished = !self.pending.peek().is_empty()
            && value["completed"].as_str() == Some(&self.pending.peek());
        let success = finished && value["succeeded"].as_bool() == Some(true);
        let should_close = success
            && self.close_on_success.peek()
            && self.submitted_page.peek()
                == format!("{}|{}", self.page.peek(), self.selected.peek());
        let prepared = text(&value, "preparedRecord");
        let route = text(&value, "routeRecord");
        let token = text(&value, "nfcPromptToken");
        let prompt = text(&value, "salePrompt");
        self.data.set(value);
        if finished {
            self.pending.set(String::new());
        }
        if should_close {
            let was_sale = self.page.peek() == "sale";
            self.back();
            if was_sale {
                self.clear_cart();
            }
        }
        if success && !prepared.is_empty() {
            self.selected.set(prepared);
            self.open("reminder");
        }
        if self.ready() && !route.is_empty() {
            if self.rows("records").iter().any(|r| text(r, "id") == route) {
                self.open_record(route);
            }
            self.command("consumeRoute");
        }
        if self.ready() && !token.is_empty() && self.nfc_seen.peek() != token {
            self.nfc_seen.set(token);
            self.selected.set(prompt);
            self.tab.set(Section::Money);
            self.page_owner.set(Section::Money);
            self.history.set(vec![String::new()]);
            self.page.set("nfc-question".to_owned());
        }
    }
    pub fn send(self, action: &str, values: Value, rows: Value, close: bool) {
        if ["dismissKeyboard", "openURL", "consumeRoute", "clearError"].contains(&action) {
            native::command(
                &json!({"action": action, "request": "control", "values": values, "rows": rows}),
            );
            return;
        }
        if self.busy() {
            return;
        }
        let n = self.sequence.peek() + 1;
        self.sequence.set(n);
        #[cfg(not(target_os = "ios"))]
        {
            let _ = close;
            let mut data = self.data.peek();
            data["error"] = json!(crate::res::str::device_only_action().format());
            self.data.set(data);
        }
        #[cfg(target_os = "ios")]
        {
            let id = format!("ui-{n}");
            self.pending.set(id.clone());
            self.close_on_success.set(close);
            self.submitted_page
                .set(format!("{}|{}", self.page.peek(), self.selected.peek()));
            native::command(&json!({"action":action,"request":id,"values":values,"rows":rows}));
        }
    }
    pub fn command(self, action: &str) {
        self.send(action, json!({}), json!([]), false);
    }
    pub fn text(self, key: &str) -> String {
        self.data.get()[key].as_str().unwrap_or("").to_owned()
    }
    pub fn rows(self, key: &str) -> Vec<Value> {
        self.data.get()[key].as_array().cloned().unwrap_or_default()
    }
    pub fn ready(self) -> bool {
        self.data.get()["ready"].as_bool().unwrap_or(false)
    }
    pub fn busy(self) -> bool {
        self.data.get()["busy"].as_bool().unwrap_or(false) || !self.pending.get().is_empty()
    }
    pub fn open(self, page: &str) {
        self.command("clearError");
        if page == "sale" {
            self.clear_cart();
        }
        let mut history = self.history.peek();
        history.push(self.page.peek());
        self.history.set(history);
        self.page_owner.set(self.tab.peek());
        self.page.set(page.to_owned());
    }
    pub fn back(self) {
        self.command("clearError");
        let mut history = self.history.peek();
        let previous = history.pop().unwrap_or_default();
        self.history.set(history);
        self.page.set(previous);
    }
    pub fn open_record(self, id: String) {
        self.history.set(vec![String::new()]);
        self.page_owner.set(Section::Places);
        self.selected.set(id);
        self.tab.set(Section::Places);
        self.page.set("record".to_owned());
    }
    pub fn record(self) -> Value {
        self.rows("records")
            .into_iter()
            .find(|r| r["id"].as_str() == Some(&self.selected.get()))
            .unwrap_or(Value::Null)
    }
}
pub(crate) fn text(value: &Value, key: &str) -> String {
    value[key].as_str().unwrap_or("").to_owned()
}
pub(crate) fn money(cents: i64) -> String {
    let n = cents.unsigned_abs();
    format!(
        "{}{},{:02} €",
        if cents < 0 { "−" } else { "" },
        n / 100,
        n % 100
    )
}

pub(crate) fn parse_price(value: &str) -> Option<i64> {
    let value = value.trim().replace(',', ".");
    if value.is_empty() || value.starts_with('-') {
        return None;
    }
    let mut parts = value.split('.');
    let whole = parts.next()?;
    let fraction = parts.next().unwrap_or("");
    if parts.next().is_some()
        || fraction.len() > 2
        || !whole.chars().all(|c| c.is_ascii_digit())
        || !fraction.chars().all(|c| c.is_ascii_digit())
    {
        return None;
    }
    let major = if whole.is_empty() {
        0
    } else {
        whole.parse::<i64>().ok()?
    };
    let minor = match fraction.len() {
        0 => 0,
        1 => fraction.parse::<i64>().ok()? * 10,
        _ => fraction.parse::<i64>().ok()?,
    };
    major.checked_mul(100)?.checked_add(minor)
}

fn initial_state() -> Value {
    #[cfg(all(feature = "verification", not(target_os = "ios")))]
    {
        serde_json::from_str(include_str!("../fixtures/day-ui.json"))
            .expect("checked synthetic UI fixture")
    }
    #[cfg(any(not(feature = "verification"), target_os = "ios"))]
    {
        native::state().unwrap_or_else(|| json!({}))
    }
}

#[cfg(test)]
mod tests {
    use super::money;
    #[test]
    fn amounts_keep_cents_and_negative_balances() {
        assert_eq!(money(3000), "30,00 €");
        assert_eq!(money(-1), "−0,01 €");
        assert_eq!(money(0), "0,00 €");
    }
}
