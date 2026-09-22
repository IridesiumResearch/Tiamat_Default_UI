// SPDX-FileCopyrightText: Iridesium
// SPDX-License-Identifier: GPL-3.0-only
//
// The mod, run for real: the engine's script VM with a fake inventory and a
// recording dialog host around it.
//
// Nothing is mocked at the Lua level. The mod's files load through
// `EngineVm::load_mod`, its hooks fire through the calls the server makes,
// every tree it sends passes the engine's own checker, and the HUD script is
// drawn by the same `HudVm` a client runs. Other mods are small fixtures
// that call the exports the way Life or World would, including ones that
// break the contract, to prove the faults land on them and not here.

use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};

use serde_json::{Value, json};
use tiamat_core::{
    MaterialId,
    content::hash_bytes,
    hud::{self, Carried, Command, HeldTool, Look, State, Value as HudValue, Values},
    inventory::{Access, Shape, Stack},
    proto::DialogEvent as Wire,
    script::{
        ActionEvent, DialogEvent, EngineVm, HudLimits, HudVm, JoinEvent, LeaveEvent, ScriptVm, VmLimits,
    },
    ui::{
        self, Tree, Widget,
        host::{Access as UiAccess, ShowRequest},
    },
};

const MOD: &str = "tiamat_default_ui";
const ALICE: [u8; 32] = [1; 32];
const BOB: [u8; 32] = [2; 32];

fn mod_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods").join(MOD)
}

// --- Fakes -------------------------------------------------------------------

#[derive(Default)]
struct Bag {
    stacks: HashMap<[u8; 32], Vec<Stack>>,
    takes: Vec<(MaterialId, u32)>,
    gives: Vec<Stack>,
    fail_give: bool,
    short_take: bool,
}

/// `player:main` as the engine keeps it, consolidated: one stack per
/// material, cut and detail. `short_take` takes one unit less than asked and
/// `fail_give` refuses shaped stacks, to drive the crafter's refund paths.
#[derive(Default)]
struct Inventory(Mutex<Bag>);

impl Access for Inventory {
    fn contents(&self, player: [u8; 32], view: &str) -> Vec<Stack> {
        if view != "player:main" {
            return Vec::new();
        }
        self.0.lock().unwrap().stacks.get(&player).cloned().unwrap_or_default()
    }

    fn give(&self, player: [u8; 32], _: &str, stack: Stack) -> bool {
        let mut bag = self.0.lock().unwrap();
        bag.gives.push(stack.clone());
        if stack.shape.is_some() && bag.fail_give {
            return false;
        }
        let list = bag.stacks.entry(player).or_default();
        match list
            .iter_mut()
            .find(|s| s.material == stack.material && s.shape == stack.shape && s.detail == stack.detail)
        {
            Some(existing) => existing.units += stack.units,
            None => list.push(stack),
        }
        true
    }

    fn held(&self, _: [u8; 32]) -> Option<Stack> {
        None
    }

    fn take(
        &self,
        player: [u8; 32],
        _: &str,
        material: MaterialId,
        shape: Option<Shape>,
        detail: Option<&str>,
        units: u32,
    ) -> u32 {
        let mut bag = self.0.lock().unwrap();
        let short = bag.short_take;
        bag.takes.push((material, units));
        let Some(list) = bag.stacks.get_mut(&player) else {
            return 0;
        };
        let Some(stack) = list
            .iter_mut()
            .find(|s| s.material == material && s.shape == shape && s.detail.as_deref() == detail)
        else {
            return 0;
        };
        let got = units.min(stack.units).saturating_sub(u32::from(short));
        stack.units -= got;
        list.retain(|s| s.units > 0);
        got
    }
}

/// What the mod sent each player's HUD script with `game.set_hud`.
#[derive(Default)]
struct Huds(Mutex<HashMap<[u8; 32], Values>>);

impl hud::Access for Huds {
    fn set_hud(&self, _: &str, player: [u8; 32], values: Values) -> bool {
        self.0.lock().unwrap().insert(player, values);
        true
    }
}

#[derive(Default)]
struct Screens(Mutex<Vec<ShowRequest>>);

impl UiAccess for Screens {
    fn show(&self, request: &ShowRequest) -> bool {
        ui::check(&request.tree, ui::Limits::default()).expect("every tree the mod sends passes the engine's checker");
        self.0.lock().unwrap().push(request.clone());
        true
    }

    fn close(&self, _: &str, _: &str) -> bool {
        true
    }
}

// --- The rig -----------------------------------------------------------------

struct Rig {
    vm: EngineVm,
    screens: Arc<Screens>,
    huds: Arc<Huds>,
    inventory: Arc<Inventory>,
    granite: MaterialId,
    marble: MaterialId,
}

impl Rig {
    /// The inventory, then each `(id, source)` fixture as a mod that lists it
    /// in `optional_depends`.
    fn new(fixtures: &[(&str, &str)]) -> Self {
        let here = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let mut vm = EngineVm::create(VmLimits::default()).unwrap();
        vm.load_mod(
            "fixture",
            "game.register_block{ id = 'granite' } game.register_block{ id = 'marble' }",
            &here,
        )
        .unwrap();
        let block = |name: &str| {
            vm.registered_blocks()
                .into_iter()
                .find(|(id, _)| id == name)
                .unwrap()
                .1
        };
        let (granite, marble) = (block("fixture:granite"), block("fixture:marble"));

        let screens = Arc::new(Screens::default());
        let inventory = Arc::new(Inventory::default());
        let huds = Arc::new(Huds::default());
        vm.set_dialog_access(screens.clone());
        vm.set_inventory_access(inventory.clone());
        vm.set_hud_access(huds.clone());

        let dir = mod_dir();
        let init = std::fs::read_to_string(dir.join("init.lua")).unwrap();
        vm.load_mod(MOD, &init, &dir).expect("the inventory loads");
        for (id, source) in fixtures {
            vm.note_dependencies(id, &[MOD.to_owned()]);
            vm.load_mod(id, source, &here)
                .unwrap_or_else(|err| panic!("fixture `{id}` failed to load: {err}"));
        }
        vm.freeze().unwrap();
        assert!(vm.faulted_mods().is_empty(), "{:?}", vm.faulted_mods());
        Self { vm, screens, huds, inventory, granite, marble }
    }

    fn key(&mut self, who: [u8; 32]) {
        let _ = self.vm.action(&ActionEvent { player: who, id: format!("{MOD}:inventory"), pressed: true });
    }

    fn event(&mut self, who: [u8; 32], event: Wire) {
        let _ = self.vm.dialog_event(&DialogEvent {
            player: who,
            mod_id: MOD.into(),
            form: format!("{MOD}:inventory"),
            event,
        });
    }

    fn press(&mut self, who: [u8; 32], name: &str) {
        self.event(who, Wire::Pressed { name: name.into() });
    }

    fn join(&mut self, who: [u8; 32]) {
        let _ = self.vm.player_join(&JoinEvent { player: who, name: "someone".into() });
    }

    fn leave(&mut self, who: [u8; 32]) {
        let _ = self.vm.player_leave(&LeaveEvent { player: who, name: "someone".into() });
    }

    fn sent(&self) -> usize {
        self.screens.0.lock().unwrap().len()
    }

    fn last(&self) -> Tree {
        self.screens.0.lock().unwrap().last().expect("a screen was shown").tree.clone()
    }

    fn stock(&self, who: [u8; 32], stacks: Vec<Stack>) {
        let mut bag = self.inventory.0.lock().unwrap();
        bag.stacks.insert(who, stacks);
        bag.takes.clear();
        bag.gives.clear();
        bag.fail_give = false;
        bag.short_take = false;
    }

    fn bag<T>(&self, look: impl FnOnce(&mut Bag) -> T) -> T {
        look(&mut self.inventory.0.lock().unwrap())
    }

    fn units(&self, who: [u8; 32], material: MaterialId) -> u32 {
        self.bag(|b| {
            b.stacks[&who]
                .iter()
                .filter(|s| s.material == material && s.shape.is_none() && s.detail.is_none())
                .map(|s| s.units)
                .sum()
        })
    }

    fn faults(&self) -> Vec<String> {
        self.vm.faulted_mods()
    }

    /// Alice with `units` of loose granite, the screen open on the crafter.
    fn crafter(fixtures: &[(&str, &str)], units: u32) -> Self {
        let mut rig = Self::new(fixtures);
        rig.stock(ALICE, vec![Stack::new(rig.granite, units).unwrap()]);
        rig.key(ALICE);
        rig.press(ALICE, "tab/shapes");
        rig
    }
}

// --- Reading a tree ------------------------------------------------------------

/// The `player:main` slots on screen, one-based as the mod wrote them (the
/// engine's tree holds them zero-based).
fn slots(tree: &Tree) -> Vec<u16> {
    tree.nodes
        .iter()
        .filter_map(|n| match &n.widget {
            Widget::ItemSlot { view, index } if view == "player:main" => Some(*index + 1),
            _ => None,
        })
        .collect()
}

fn slots_in(tree: &Tree, view: &str) -> usize {
    tree.nodes
        .iter()
        .filter(|n| matches!(&n.widget, Widget::ItemSlot { view: v, .. } if v == view))
        .count()
}

fn has_name(tree: &Tree, name: &str) -> bool {
    tree.nodes.iter().any(|n| n.name == name)
}

fn has_editor(tree: &Tree) -> bool {
    tree.nodes.iter().any(|n| matches!(n.widget, Widget::ShapeEditor { .. }))
}

/// The event name of the button labelled `text`.
fn button(tree: &Tree, text: &str) -> Option<String> {
    tree.nodes.iter().find_map(|n| match &n.widget {
        Widget::Button { text: t } if t == text => Some(n.name.clone()),
        _ => None,
    })
}

fn labels(tree: &Tree) -> Vec<String> {
    tree.nodes
        .iter()
        .filter_map(|n| match &n.widget {
            Widget::Label { text } => Some(text.clone()),
            _ => None,
        })
        .collect()
}

fn cells(mask: u32) -> u32 {
    mask.count_ones()
}

// --- The inventory's own behaviour ----------------------------------------------

fn layout_and_paging() {
    let mut r = Rig::new(&[]);
    r.key(ALICE);
    let s = slots(&r.last());
    assert!((1..=28).all(|i| s.contains(&i)), "page one: {s:?}");
    r.press(ALICE, "next");
    let s = slots(&r.last());
    assert!((29..=46).all(|i| s.contains(&i)), "page two: {s:?}");
    assert!(s.contains(&1) && s.contains(&9) && s.contains(&28) && !s.contains(&10));
    r.press(ALICE, "previous");
    assert!(slots(&r.last()).contains(&10));
    let mut unique = slots(&r.last());
    unique.sort_unstable();
    unique.dedup();
    assert_eq!(unique.len(), slots(&r.last()).len(), "a slot drawn twice");
    r.event(ALICE, Wire::Closed);
    r.key(ALICE);
    assert!(slots(&r.last()).contains(&10));
    // The slots and buttons wear the iron frame. The ornate frame around the
    // whole screen is the theme's, painted by the engine around the sheet, so
    // it must NOT also be in the tree: that was the frame inside a frame.
    let panel = hash_bytes(&std::fs::read(mod_dir().join("textures/ornate-panel.png")).unwrap());
    let slot = hash_bytes(&std::fs::read(mod_dir().join("textures/iron-slot.png")).unwrap());
    let tree = r.last();
    let frames: Vec<_> = tree.nodes.iter().filter_map(|n| n.style.nine_slice).collect();
    assert!(!frames.contains(&panel), "the tree draws the ornate frame the theme already puts around the sheet");
    assert!(
        !frames.is_empty() && frames.iter().all(|h| *h == slot),
        "a frame in the tree is not iron-slot.png ({})",
        hex(&slot)
    );
    for n in tree.nodes.iter().filter(|n| n.style.nine_slice.is_some()) {
        assert_eq!(n.style.background.map_or(0, |b| b[3]), 0, "a framed widget with a fill hides its frame");
    }
    assert!(
        !tree.nodes.iter().any(|n| matches!(n.widget, Widget::Scroll)),
        "the screen scrolls; it should fit its sheet"
    );
    assert!(tree.nodes.iter().any(|n| n.style.font.as_deref() == Some(DISPLAY_FONT)));
    // Hints name the text face. Left unnamed they would be drawn in the
    // theme's font, which is the display face, and read as small capitals.
    assert!(tree.nodes.iter().any(|n| n.style.font.as_deref() == Some(TEXT_FONT)));
    println!("ok  layout: quick access, two pack pages, off-hand, iron frames only, both fonts, no scroll");
}

fn empty_crafter() {
    let mut r = Rig::crafter(&[], 90);
    r.stock(ALICE, vec![]);
    r.press(ALICE, "tab/shapes");
    r.press(ALICE, "reset");
    assert!(!has_editor(&r.last()));
    println!("ok  crafter with no material shows no editor");
}

fn full_and_empty_masks_do_not_spend() {
    let mut r = Rig::crafter(&[], 90);
    r.press(ALICE, "make");
    assert!(r.bag(|b| b.takes.is_empty()));
    r.event(ALICE, Wire::Chiselled { name: "cut".into(), shape: 0 });
    r.press(ALICE, "make");
    assert!(r.bag(|b| b.takes.is_empty()));
    println!("ok  a full or empty mask spends nothing");
}

fn presets_conserve_units() {
    for (preset, cost) in [("slab", 9), ("stairs", 18), ("pillar", 3)] {
        let mut r = Rig::crafter(&[], 90);
        r.press(ALICE, preset);
        r.press(ALICE, "make");
        let (take, give) = r.bag(|b| (b.takes[0], b.gives[0].clone()));
        assert_eq!(take.1, cost, "{preset}");
        let shape = give.shape.expect("a shaped stack");
        assert_eq!(give.count(), 1);
        assert_eq!(cells(shape.occupancy()) * give.count(), take.1, "{preset} created or destroyed units");
    }
    println!("ok  slab 9, stairs 18, pillar 3, and units are conserved");
}

fn stacks_are_limited() {
    let mut r = Rig::crafter(&[], 100);
    r.press(ALICE, "slab");
    r.press(ALICE, "make_stack");
    assert_eq!(r.bag(|b| (b.gives[0].count(), b.takes[0].1)), (11, 99));
    let mut r = Rig::crafter(&[], 10_000);
    r.press(ALICE, "pillar");
    r.press(ALICE, "make_stack");
    assert_eq!(r.bag(|b| b.gives[0].count()), 90);
    println!("ok  a stack is limited by material and by ITEMS_PER_STACK");
}

fn failed_transactions_refund() {
    let mut r = Rig::crafter(&[], 2);
    r.press(ALICE, "pillar");
    r.press(ALICE, "make");
    assert!(r.bag(|b| b.takes.is_empty()), "crafted with too little material");

    let mut r = Rig::crafter(&[], 90);
    r.press(ALICE, "slab");
    r.bag(|b| b.short_take = true);
    r.press(ALICE, "make");
    assert_eq!(r.bag(|b| b.gives[0].units), 8);
    assert_eq!(r.units(ALICE, r.granite), 90);

    let mut r = Rig::crafter(&[], 90);
    r.press(ALICE, "slab");
    r.bag(|b| b.fail_give = true);
    r.press(ALICE, "make");
    assert_eq!(r.bag(|b| b.gives[1].units), 9);
    assert_eq!(r.units(ALICE, r.granite), 90);
    println!("ok  short takes and failed gives return every unit");
}

fn depleted_material_is_not_replaced() {
    let mut r = Rig::crafter(&[], 9);
    let marble = r.marble;
    r.bag(|b| b.stacks.get_mut(&ALICE).unwrap().push(Stack::new(marble, 90).unwrap()));
    r.press(ALICE, "tab/shapes");
    r.press(ALICE, "slab");
    r.press(ALICE, "make");
    r.press(ALICE, "make");
    assert_eq!(r.bag(|b| b.takes.len()), 1, "the second click crafted from another material");
    assert_eq!(r.units(ALICE, marble), 90);
    // Zero-based on the wire; the mod is told 2, the marble under the placeholder.
    r.event(ALICE, Wire::Chose { name: "material".into(), index: 1 });
    r.press(ALICE, "make");
    assert_eq!(r.bag(|b| b.takes[1].0), marble);
    println!("ok  running out never switches material behind the player's back");
}

fn named_and_shaped_stacks_are_kept() {
    let mut r = Rig::crafter(&[], 90);
    let named = Stack { detail: Some("named".into()), ..Stack::new(r.granite, 100).unwrap() };
    let cut = Stack::shaped(r.marble, Shape::new(7).unwrap(), 10).unwrap();
    r.stock(ALICE, vec![named, cut]);
    r.press(ALICE, "reset");
    assert!(!has_editor(&r.last()));
    r.press(ALICE, "make");
    assert!(r.bag(|b| b.takes.is_empty()));
    println!("ok  named and already-cut stacks are never material");
}

fn players_are_isolated() {
    let mut r = Rig::crafter(&[], 90);
    r.press(ALICE, "slab");
    r.key(BOB);
    assert!(slots(&r.last()).contains(&28), "bob should see his own inventory tab");
    r.key(BOB);
    r.event(ALICE, Wire::Chiselled { name: "cut".into(), shape: 1 << 27 });
    r.press(ALICE, "make");
    assert_eq!(r.bag(|b| b.takes[0].1), 9, "an out-of-range mask was adopted");
    r.leave(ALICE);
    r.key(ALICE);
    assert!(slots(&r.last()).contains(&10), "leaving should reset to the inventory tab");
    r.event(ALICE, Wire::Closed);
    let before = r.sent();
    r.press(ALICE, "tab/shapes");
    assert_eq!(r.sent(), before, "a closed screen was redrawn");
    println!("ok  players are isolated, and leaving or closing clears state");
}

fn carving_does_not_echo() {
    let mut r = Rig::crafter(&[], 90);
    let before = r.sent();
    r.event(ALICE, Wire::Chiselled { name: "cut".into(), shape: 7 });
    assert_eq!(r.sent(), before, "a carve sent a tree back");
    r.press(ALICE, "make");
    assert_eq!(r.bag(|b| (b.gives[0].shape.map(Shape::occupancy), b.takes[0].1)), (Some(7), 3));
    println!("ok  carving never echoes a stale mask");
}

// --- Other mods -----------------------------------------------------------------

/// A well-behaved mod: a tab, a button on every tab, a button on its tab, and
/// every refusal the exports promise.
const ADDON: &str = r#"
local ui = game.exports("tiamat_default_ui")
assert(ui and ui.version == 1, "inventory exports missing")
assert(not pcall(function() ui.version = 2 end), "exports were writable")
assert(ui.tabs.items == "tiamat_default_ui:items")
assert(ui.sizes.cell > 0 and ui.widgets.row and ui.widgets.space and ui.widgets.hint, "layout exports missing")

local ok, why = ui.add_tab{ id = "unqualified", label = "X", build = function() end }
assert(ok == nil and type(why) == "string", "a bad tab id was accepted")
assert(ui.add_tab(42) == nil, "a number was accepted as a tab")
assert(ui.add_tab{ id = "addon:long", label = string.rep("x", 200), build = function() end } == nil)
assert(ui.open(7) == nil, "open accepted a non-player")
assert(ui.add_button{ id = "addon:orphan", label = "Orphan", tab = "addon:nowhere",
    on_press = function() end } == nil, "a button for a missing tab was accepted")

local worn, hello = 0, 0
assert(ui.add_tab{
    id = "addon:bag", label = "Bag",
    build = function(player)
        ui.redraw(player)   -- re-entrant: must be ignored, not recurse
        local w = ui.widgets
        return w.section("BAG", {
            w.label("worn " .. worn .. " hello " .. hello, 17, ui.theme.colours.brass),
            { type = "item_grid", view = "player:main", columns = 4, first = 1, count = 4 },
            w.button("wear", "Wear"),
            { type = "checkbox", name = "cosy", text = "Cosy", checked = worn > 0 },
        })
    end,
    on_event = function(player, event)
        if event.kind == "pressed" and event.name == "wear" then worn = worn + 1; return true end
        if event.kind == "toggled" and event.name == "cosy" then worn = 0; return true end
    end,
})
assert(ui.add_tab{ id = "addon:bag", label = "Again", build = function() end } == nil, "a duplicate id was accepted")
assert(ui.add_button{ id = "addon:hello", label = "Hello", on_press = function() hello = hello + 1 end })
assert(ui.add_button{ id = "addon:sort", label = "Sort", tab = "addon:bag",
    on_press = function() hello = hello + 10 end })
"#;

/// Tabs and buttons that break: an error in build, an error in on_press, a
/// widget the engine refuses, a tree too deep, and a tree that holds itself.
const ROGUE: &str = r#"
local ui = game.exports("tiamat_default_ui")
assert(ui.add_tab{ id = "rogue:boom", label = "Boom", build = function() error("boom") end })
assert(ui.add_button{ id = "rogue:bang", label = "Bang", on_press = function() error("bang") end })
"#;

const SLOPPY: &str = r#"
local ui = game.exports("tiamat_default_ui")
assert(ui.add_tab{ id = "sloppy:rocket", label = "Rocket",
    build = function() return { type = "rocket" } end })
assert(ui.add_tab{ id = "sloppy:deep", label = "Deep", build = function()
    local node = { type = "label", text = "bottom" }
    for _ = 1, 40 do node = { type = "container", children = { node } } end
    return node
end })
assert(ui.add_tab{ id = "sloppy:loop", label = "Loop", build = function()
    local node = { type = "container" }
    node.children = { node }
    return node
end })
"#;

fn another_mods_tab_and_buttons() {
    let mut r = Rig::new(&[("addon", ADDON)]);
    r.key(ALICE);
    let tree = r.last();
    let bag = button(&tree, "Bag").expect("the addon's tab is in the strip");
    assert!(button(&tree, "Hello").is_some(), "a button for every tab is missing on Inventory");
    assert!(button(&tree, "Sort").is_none(), "the bag's own button shows on another tab");

    // A widget from another tab arriving late does nothing.
    let before = r.sent();
    r.press(ALICE, &format!("{}/wear", bag.trim_start_matches("tab/")));
    assert_eq!(r.sent(), before, "a stale event reached a tab that is not shown");

    r.press(ALICE, &bag);
    let tree = r.last();
    let key = bag.trim_start_matches("tab/").to_owned();
    assert!(has_name(&tree, &format!("{key}/wear")), "names were not prefixed: {:?}", labels(&tree));
    assert!(labels(&tree).contains(&"worn 0 hello 0".to_owned()));
    let brass = tree.nodes.iter().find(|n| matches!(&n.widget, Widget::Label { text } if text == "worn 0 hello 0"));
    assert!(
        brass.and_then(|n| n.style.text_colour).is_some_and(|c| c[..3] == [154, 132, 92]),
        "a theme colour did not survive the round trip"
    );
    assert!(tree.nodes.iter().any(|n| matches!(n.widget, Widget::ItemGrid { .. })));

    r.press(ALICE, &format!("{key}/wear"));
    assert!(labels(&r.last()).contains(&"worn 1 hello 0".to_owned()), "{:?}", labels(&r.last()));
    r.press(ALICE, &button(&r.last(), "Sort").expect("the bag's own button"));
    r.press(ALICE, &button(&r.last(), "Hello").unwrap());
    assert!(labels(&r.last()).contains(&"worn 1 hello 11".to_owned()), "{:?}", labels(&r.last()));
    r.event(ALICE, Wire::Toggled { name: format!("{key}/cosy"), checked: false });
    assert!(labels(&r.last()).contains(&"worn 0 hello 11".to_owned()));
    assert!(r.faults().is_empty(), "{:?}", r.faults());
    println!("ok  another mod's tab, buttons, events, widgets and theme work, and bad specs are refused");
}

fn faults_land_on_the_mod_that_wrote_them() {
    let mut r = Rig::new(&[("addon", ADDON), ("rogue", ROGUE)]);
    r.key(ALICE);
    let boom = button(&r.last(), "Boom").expect("rogue's tab is listed until it fails");
    r.press(ALICE, &boom);
    let tree = r.last();
    assert!(slots(&tree).contains(&10), "a failed tab should fall back to Inventory");
    assert!(button(&tree, "Boom").is_none(), "a failed tab is still in the strip");
    assert!(r.faults().contains(&"rogue".to_owned()));
    assert!(!r.faults().contains(&MOD.to_owned()), "{:?}", r.faults());

    let mut r = Rig::new(&[("addon", ADDON), ("rogue", ROGUE)]);
    r.key(ALICE);
    let before = r.sent();
    r.press(ALICE, &button(&r.last(), "Bang").unwrap());
    assert_eq!(r.faults(), vec!["rogue".to_owned()]);
    assert!(r.sent() > before, "the screen should still redraw after a failed press");
    r.press(ALICE, &button(&r.last(), "Hello").unwrap());
    assert!(r.faults().len() == 1, "{:?}", r.faults());
    println!("ok  an error in another mod's build or on_press disables that mod, not this one");

    for label in ["Rocket", "Deep", "Loop"] {
        let mut r = Rig::new(&[("sloppy", SLOPPY)]);
        r.key(ALICE);
        let tab = button(&r.last(), label).unwrap();
        r.press(ALICE, &tab);
        let tree = r.last();
        assert!(slots(&tree).contains(&10), "{label}: should fall back to Inventory");
        assert!(button(&tree, label).is_none(), "{label}: still listed");
        assert!(r.faults().is_empty(), "{label}: {:?}", r.faults());
    }
    println!("ok  a refused, too-deep or cyclic tree drops that tab and faults nobody");
}

/// The engine's promise since 823aac3: a table handed back to the mod that
/// owns it is that mod's own table again, so `pairs` and `#` see its entries.
fn round_trip_views() {
    let mut vm = EngineVm::create(VmLimits::default()).unwrap();
    let here = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    vm.load_mod(
        "owner",
        r#"
        local list = { "a", "b", "c" }
        game.export{
            list = list,
            count = function(t)
                local n = 0
                for _ in pairs(t) do n = n + 1 end
                return n, #t, t[1]
            end,
        }"#,
        &here,
    )
    .unwrap();
    vm.note_dependencies("guest", &["owner".to_owned()]);
    vm.load_mod(
        "guest",
        r#"
        local owner = game.exports("owner")
        local once = { "x", "y" }
        local a, b, c = owner.count(once)
        local d, e, f = owner.count(owner.list)
        game.log(string.format("ROUNDTRIP once pairs=%d len=%d first=%s back pairs=%d len=%d first=%s",
            a, b, tostring(c), d, e, tostring(f)))
        game.register_block{ id = (d == 3 and e == 3) and "roundtrip_ok" or "roundtrip_empty" }
        "#,
        &here,
    )
    .unwrap();
    let blocks: Vec<_> = vm.registered_blocks().into_iter().map(|(id, _)| id).collect();
    assert!(
        blocks.contains(&"guest:roundtrip_ok".to_owned()),
        "a table handed back to its owner no longer iterates (engine regression of 823aac3)"
    );
    println!("ok  a table handed back to its owner iterates normally");
}

/// The engine's promise since 823aac3: a callback from a mod that has been
/// disabled answers nil and runs nothing, so its tab is dropped at the next
/// build and its button does nothing.
const LINGER: &str = r#"
local ui = game.exports("tiamat_default_ui")
local presses = 0
assert(ui.add_tab{ id = "linger:tab", label = "Linger",
    build = function() return ui.widgets.label("presses " .. presses) end })
assert(ui.add_button{ id = "linger:press", label = "Press", on_press = function()
    presses = presses + 1
    if presses == 1 then error("first press faults") end
end })
"#;

fn disabled_callbacks() {
    let mut r = Rig::new(&[("linger", LINGER)]);
    r.key(ALICE);
    r.press(ALICE, &button(&r.last(), "Press").unwrap());
    assert_eq!(r.faults(), vec!["linger".to_owned()]);
    r.press(ALICE, &button(&r.last(), "Press").unwrap());
    r.press(ALICE, &button(&r.last(), "Linger").unwrap());
    let tree = r.last();
    assert!(!labels(&tree).contains(&"presses 2".to_owned()), "a disabled mod's callback ran (engine regression of 823aac3)");
    assert!(button(&tree, "Linger").is_none() && slots(&tree).contains(&10), "a disabled mod's tab was not dropped");
    assert!(!r.faults().contains(&MOD.to_owned()));
    println!("ok  a disabled mod's callbacks stop, and its tab is dropped");
}

// --- Fitting the sheet --------------------------------------------------------------
//
// The screen must fit the engine's sheet at every window size without
// scrolling. The sheet is the client's `panel::size` — three quarters of the
// window's height at 4:3 — less its bar and margins, and the tree is laid
// into exactly that room by the engine's own `layout`. So this lays each
// screen out at real window sizes with the real layout and checks the result:
// nothing outside its parent, no slot too small to use or badly out of square,
// and no text wider than the box it is drawn in.

/// Leaf sizes as the client measures them (`client::dialog`), with text
/// estimated from the font. The widths per character are the WORST measured
/// over this mod's own strings with Pillow: Cinzel Decorative Bold reaches
/// 0.83 em (its lowercase is small capitals), a monospace face 0.63, and
/// Spectral, the text face, 0.46. Anything but the display font is held to
/// the monospace figure, which leaves Spectral room for another mod's lines
/// heavier in capitals, and the client's own face is narrower still, so a
/// pass here is a pass in the window.
struct Ruler;

const DISPLAY_FONT: &str = "tiamat_default_ui:display";
const TEXT_FONT: &str = "tiamat_default_ui:text";

fn text_size(text: &str, style: &ui::Style) -> (i32, i32) {
    let size = f32::from(style.text_size.unwrap_or(14));
    let per = if style.font.as_deref() == Some(DISPLAY_FONT) { 0.84 } else { 0.63 };
    let chars = text.chars().count() as f32;
    ((chars * size * per).ceil() as i32, (size * 1.3).ceil() as i32)
}

impl ui::Measure for Ruler {
    fn natural(&self, widget: &Widget, style: &ui::Style) -> (i32, i32) {
        match widget {
            Widget::Label { text } => text_size(text, style),
            Widget::Button { text } => {
                let (w, h) = text_size(text, style);
                (w + 16, h + 8)
            }
            Widget::Checkbox { text, .. } => {
                let (w, h) = text_size(text, style);
                (w + 24, h.max(16))
            }
            Widget::Dropdown { options, selected } => {
                let text = options.get(usize::from(*selected)).map_or("", String::as_str);
                let (w, h) = text_size(text, style);
                (w + 32, h + 8)
            }
            Widget::ItemSlot { .. } => (36, 36),
            Widget::ItemGrid { columns, count, .. } => {
                let (columns, count) = (i32::from(*columns).max(1), i32::from(*count));
                (columns * 36, ((count + columns - 1) / columns).max(1) * 36)
            }
            Widget::ShapeEditor { .. } => (192, 192),
            Widget::Image { .. } => (64, 64),
            Widget::Progress { .. } => (120, 12),
            Widget::Slider { .. } => (160, 20),
            Widget::TextInput { .. } => (160, 26),
            _ => (0, 0),
        }
    }
}

/// The room a screen gets in a window `w` by `h` points: the client's
/// `panel::size_clear_of` with this mod's HUD reserve (converted from the
/// HUD's 1080-tall canvas as `panel::reserve_points` does), less the sheet's
/// margins and its bar with Close on it. A framed sheet's margin is the
/// client's `FRAME_BORDER`, 18 points a side where egui's own is 6, so a
/// themed sheet has 24 fewer each way than a plain one.
fn room(w: f32, h: f32) -> (i32, i32) {
    let reserve = (HUD_RESERVE / 1080.0 * h).clamp(0.0, h / 2.0);
    let height = (h * 0.75).min(h - reserve).max(120.0);
    let width = (height * 4.0 / 3.0).min(w * 0.9).max(160.0);
    let height = (width * 3.0 / 4.0).min(height).max(120.0);
    ((width - 16.0 - FRAMED) as i32, (height - 48.0 - FRAMED) as i32)
}

/// What a themed sheet's frame takes from each dimension beyond egui's own
/// margin: `2 * (FRAME_BORDER - 6)`. This mod declares a frame, so every
/// sheet it draws is framed.
const FRAMED: f32 = 24.0;

/// config.lua's `hud_reserve`, checked against what the mod registers in
/// `the_look_is_declared`.
const HUD_RESERVE: f32 = 138.0;

const WINDOWS: [(f32, f32); 5] = [(800.0, 600.0), (1024.0, 768.0), (1280.0, 720.0), (1366.0, 768.0), (1920.0, 1080.0)];

/// Every problem with `tree` laid into `area`, as sentences.
fn misfits(tree: &Tree, area: (i32, i32)) -> Vec<String> {
    let laid = ui::layout(tree, ui::Rect::new(0, 0, area.0, area.1), &Ruler);
    let mut found = Vec::new();
    walk_fit(tree, 0, &laid, None, &mut found);
    found
}

fn walk_fit(tree: &Tree, at: usize, laid: &ui::Laid, parent: Option<ui::Rect>, found: &mut Vec<String>) {
    let node = &tree.nodes[at];
    let r = laid.rect;
    let what = || match &node.widget {
        Widget::Label { text } | Widget::Button { text } => format!("{text:?}"),
        other => format!("{other:?}").split_whitespace().next().unwrap_or("?").to_owned(),
    };
    if let Some(p) = parent
        && (r.x < p.x || r.y < p.y || r.x + r.w > p.x + p.w || r.y + r.h > p.y + p.h)
    {
        found.push(format!("{} spills out of its parent: {r:?} in {p:?}", what()));
    }
    match &node.widget {
        Widget::Scroll => found.push("a scroll box".into()),
        Widget::ItemSlot { index, .. } => {
            if r.w.min(r.h) < 36 {
                found.push(format!("slot {} is {}x{}, too small to use", index + 1, r.w, r.h));
            }
            let ratio = r.w as f32 / r.h.max(1) as f32;
            if !(0.8..=1.25).contains(&ratio) {
                found.push(format!("slot {} is {}x{}, out of square", index + 1, r.w, r.h));
            }
        }
        Widget::Label { text } | Widget::Button { text } if !text.is_empty() => {
            let (w, h) = text_size(text, &node.style);
            let pad = if matches!(node.widget, Widget::Button { .. }) { 8 } else { 0 };
            if w + pad > r.w {
                found.push(format!("{} needs {} across and has {}", what(), w + pad, r.w));
            }
            if h > r.h + 4 {
                found.push(format!("{} needs {} down and has {}", what(), h, r.h));
            }
        }
        Widget::Dropdown { options, selected } => {
            let text = options.get(usize::from(*selected)).map_or("", String::as_str);
            let (w, _) = text_size(text, &node.style);
            if w + 32 > r.w {
                found.push(format!("dropdown {text:?} needs {} across and has {}", w + 32, r.w));
            }
        }
        _ => {}
    }
    let first = node.children.first as usize;
    for (n, child) in laid.children.iter().enumerate() {
        walk_fit(tree, first + n, child, Some(r), found);
    }
}

/// The README's wardrobe example, nearly word for word: what a mod following
/// the "Your tab must fit" advice builds.
const WARDROBE: &str = r#"
game.register_view{ id = "worn", slots = 4 }
local ui = game.exports("tiamat_default_ui")
local w, sizes = ui.widgets, ui.sizes
assert(ui.add_tab{
    id = "wardrobe:wardrobe",
    label = "Wardrobe",
    build = function(player)
        local worn = {}
        for index = 1, 4 do
            worn[index] = w.slot("wardrobe:worn", index)
        end
        worn[5] = w.space(1)
        return w.box("column", {
            w.section("WORN", { w.row(worn, sizes.cell, sizes.cell_gap) }),
            w.hint("Clothing keeps you warm, or cool."),
            w.space(1),
            w.row({ w.wide_button("strip", "Take everything off") }, sizes.row),
        })
    end,
})
assert(ui.add_button{ id = "wardrobe:sleep", label = "Sleep", on_press = function() end })
"#;

/// The `[theme]` the engine's own screens wear, read and validated the way the
/// engine reads it, and the HUD reserve that keeps sheets off the hotbar.
fn the_look_is_declared() {
    let dir = mod_dir();
    let manifest = tiamat_core::modload::ModManifest::load(&dir).expect("mod.toml loads and validates");
    let theme = manifest.theme.expect("mod.toml declares a [theme]");
    for (what, file) in [
        ("font", &theme.font),
        ("text_font", &theme.text_font),
        ("sheet", &theme.sheet),
        ("button", &theme.button),
    ] {
        let file = file.as_deref().unwrap_or_else(|| panic!("the theme names no {what}"));
        assert!(dir.join(file).is_file(), "the theme's {what} is not a file: {file}");
    }
    assert_eq!(theme.sheet.as_deref(), Some("textures/ornate-panel.png"));
    // Chat and the engine's prose in the face hints are drawn in, not Cinzel.
    assert_eq!(theme.text_font.as_deref(), Some("fonts/Spectral-Regular.ttf"));
    let c = &theme.colours;
    for (what, colour) in [
        ("text", &c.text),
        ("heading", &c.heading),
        ("background", &c.background),
        ("button", &c.button),
        ("accent", &c.accent),
    ] {
        assert!(colour.is_some(), "the theme leaves {what} to the client");
    }

    let r = Rig::new(&[]);
    let scripts = r.vm.registered_hud_scripts();
    let ours = scripts.iter().find(|s| s.mod_id == MOD).expect("the hotbar script is registered");
    assert_eq!(f32::from(ours.reserve), HUD_RESERVE, "hud_reserve in config.lua and the harness disagree");
    println!("ok  the theme validates and names every part, and the hotbar reserves {} px", ours.reserve);
}

fn screens_fit_without_scrolling() {
    let mut trees: Vec<(&str, Tree)> = Vec::new();
    let mut r = Rig::new(&[("addon", ADDON), ("wardrobe", WARDROBE)]);
    r.stock(ALICE, vec![Stack::new(r.granite, 124).unwrap(), Stack::new(r.marble, 270).unwrap()]);
    r.key(ALICE);
    trees.push(("inventory", r.last()));
    let wardrobe = button(&r.last(), "Wardrobe").expect("the README's wardrobe tab");
    r.press(ALICE, &wardrobe);
    assert!(
        slots_in(&r.last(), "wardrobe:worn") == 4,
        "the README's wardrobe tab should show four worn slots"
    );
    trees.push(("the README's wardrobe tab", r.last()));
    r.press(ALICE, "tab/items");
    r.press(ALICE, "next");
    trees.push(("inventory, page two", r.last()));
    r.press(ALICE, "tab/shapes");
    r.press(ALICE, "stairs");
    trees.push(("crafter", r.last()));
    let bag = button(&r.last(), "Bag").unwrap();
    r.press(ALICE, &bag);
    trees.push(("another mod's tab", r.last()));
    r.stock(ALICE, vec![]);
    r.press(ALICE, "tab/shapes");
    trees.push(("crafter, no material", r.last()));

    let mut failed = Vec::new();
    for (w, h) in WINDOWS {
        let area = room(w, h);
        for (name, tree) in &trees {
            for problem in misfits(tree, area) {
                failed.push(format!("{w}x{h} ({}x{} room), {name}: {problem}", area.0, area.1));
            }
        }
    }
    assert!(failed.is_empty(), "screens that do not fit:\n  {}", failed.join("\n  "));
    println!("ok  every screen fits its sheet without scrolling at 800x600 to 1920x1080");
}

/// Where node `want` of `tree` was laid, found by walking the tree and its
/// layout together the way `walk_fit` does.
fn rect_of(tree: &Tree, at: usize, laid: &ui::Laid, want: usize) -> Option<ui::Rect> {
    if at == want {
        return Some(laid.rect);
    }
    let first = tree.nodes[at].children.first as usize;
    laid.children.iter().enumerate().find_map(|(n, child)| rect_of(tree, first + n, child, want))
}

/// Every line `crafting.lua` can answer, read from its source so a new one is
/// covered without being listed here, and the longest a craft can report: a
/// full stack of the most expensive shape.
fn craft_messages() -> Vec<String> {
    let source = std::fs::read_to_string(mod_dir().join("crafting.lua")).unwrap();
    let mut found: Vec<String> = source
        .lines()
        .filter_map(|line| line.trim().strip_prefix("return \"").or_else(|| line.split("then return \"").nth(1)))
        .filter_map(|rest| rest.split('"').next())
        .map(str::to_owned)
        .collect();
    let most = game_items_per_stack();
    found.push(format!("Crafted {most}  /  {} units used", most * 26));
    assert!(found.len() >= 7, "expected crafting.lua's messages, found {found:?}");
    found
}

fn game_items_per_stack() -> u32 {
    tiamat_core::inventory::ITEMS_PER_STACK
}

/// The crafter's result line does not wrap, so every message it can show must
/// fit the width the crafter gives it, at every window size. They are
/// sentences, so they are in the text face.
fn craft_messages_fit() {
    let mut r = Rig::crafter(&[], 90);
    r.press(ALICE, "stairs");
    r.press(ALICE, "make");
    let tree = r.last();
    let at = tree
        .nodes
        .iter()
        .position(|n| matches!(&n.widget, Widget::Label { text } if text.starts_with("Crafted")))
        .expect("a craft reports itself");
    let style = &tree.nodes[at].style;
    assert_eq!(style.font.as_deref(), Some(TEXT_FONT), "the result line is a sentence");
    let mut failed = Vec::new();
    for (w, h) in WINDOWS {
        let area = room(w, h);
        let laid = ui::layout(&tree, ui::Rect::new(0, 0, area.0, area.1), &Ruler);
        let room = rect_of(&tree, 0, &laid, at).expect("the result line was laid out").w;
        for message in craft_messages() {
            let needs = text_size(&message, style).0;
            if needs > room {
                failed.push(format!("{w}x{h}: {message:?} needs {needs} across and has {room}"));
            }
        }
    }
    assert!(failed.is_empty(), "craft messages that do not fit:
  {}", failed.join("
  "));
    println!("ok  every craft message fits the crafter at 800x600 to 1920x1080");
}

// --- The preview's data -----------------------------------------------------------
//
// The trees this run built, written out for tools/render_preview.py to draw.
// The picture comes from the same trees the engine's checker passed, so there
// is no second copy of the mod's layout anywhere, and nothing to keep in step.

fn colour(value: Option<[u8; 4]>) -> Value {
    value.map_or(Value::Null, |c| json!(c))
}

/// One node and its children, as nested JSON, each with the rectangle the
/// engine's layout gave it.
fn node_json(tree: &Tree, at: usize, laid: &ui::Laid) -> Value {
    let node = &tree.nodes[at];
    let r = laid.rect;
    let mut out = json!({
        "rect": [r.x, r.y, r.w, r.h],
        "name": node.name,
        "grow": node.grow,
        "size": node.size,
        "cross_size": node.cross_size,
        "style": {
            "background": colour(node.style.background),
            "border": colour(node.style.border),
            "text_colour": colour(node.style.text_colour),
            "text_size": node.style.text_size,
            "font": node.style.font,
            "nine_slice": node.style.nine_slice.as_ref().map(hex),
        },
    });
    let object = out.as_object_mut().unwrap();
    let mut kind = |name: &str| object.insert("type".into(), json!(name));
    match &node.widget {
        Widget::Container { direction, gap, padding, align } => {
            kind("container");
            object.insert("direction".into(), json!(format!("{direction:?}").to_lowercase()));
            object.insert("gap".into(), json!(gap));
            object.insert("padding".into(), json!(padding));
            object.insert("align".into(), json!(format!("{align:?}").to_lowercase()));
        }
        Widget::Label { text } => {
            kind("label");
            object.insert("text".into(), json!(text));
        }
        Widget::Button { text } => {
            kind("button");
            object.insert("text".into(), json!(text));
        }
        Widget::Checkbox { text, checked } => {
            kind("checkbox");
            object.insert("text".into(), json!(text));
            object.insert("checked".into(), json!(checked));
        }
        Widget::Dropdown { options, selected } => {
            kind("dropdown");
            object.insert("options".into(), json!(options));
            object.insert("selected".into(), json!(selected + 1));
        }
        Widget::ItemSlot { view, index } => {
            kind("item_slot");
            object.insert("view".into(), json!(view));
            object.insert("index".into(), json!(index + 1));
        }
        Widget::ItemGrid { view, columns, first, count } => {
            kind("item_grid");
            object.insert("view".into(), json!(view));
            object.insert("columns".into(), json!(columns));
            object.insert("first".into(), json!(first + 1));
            object.insert("count".into(), json!(count));
        }
        Widget::ShapeEditor { shape, material } => {
            kind("shape_editor");
            object.insert("shape".into(), json!(shape));
            object.insert("material".into(), json!(material));
        }
        Widget::Scroll => {
            kind("scroll");
        }
        Widget::Spacer => {
            kind("spacer");
        }
        other => {
            kind(&format!("{other:?}").split_whitespace().next().unwrap_or("widget").to_lowercase());
        }
    }
    let first = tree.nodes[at].children.first as usize;
    let kids: Vec<Value> = laid
        .children
        .iter()
        .enumerate()
        .map(|(n, child)| node_json(tree, first + n, child))
        .collect();
    out.as_object_mut().unwrap().insert("children".into(), json!(kids));
    out
}

/// The hotbar's draw commands, as the HUD script issued them.
fn hud_json(source: &str) -> Value {
    let stone = MaterialId(3);
    let loose = |units, name: &str| Carried {
        material: stone,
        name: name.into(),
        units,
        shape: 0,
        detail: None,
    };
    let mut state = State::default();
    state.selected = 2;
    state.carried = vec![None; 9];
    state.carried[0] = Some(loose(124, "Granite"));
    state.carried[1] = Some(loose(270, "Marble"));
    state.carried[2] = Some(Carried { shape: 7, units: 24, ..loose(0, "Granite") });
    state.offhand = Some(loose(27, "Marble"));
    state.tool = Some(HeldTool { id: "chisel".into(), name: "Chisel".into(), brush: String::new() });
    state.looking_at = Some(Look { cell: [0, 0, 0], material: stone, name: "Granite".into() });
    state.values.insert(MOD.into(), Values::from([("slot_frame".into(), HudValue::Text(hotbar_frame().0))]));
    let mut hud = HudVm::new(HudLimits::default()).unwrap();
    hud.load(MOD, source).unwrap();
    assert!(hud.draw(&state).is_empty());
    hud.with_frame(|frame| {
        let commands: Vec<Value> = frame
            .commands()
            .iter()
            .map(|command| match command {
                Command::Rect { x, y, w, h, colour: c, .. } => {
                    json!({ "kind": "rect", "x": x, "y": y, "w": w, "h": h, "colour": c })
                }
                Command::Text { x, y, text, size, colour: c, .. } => {
                    json!({ "kind": "text", "x": x, "y": y, "text": text, "size": size, "colour": c })
                }
                Command::Image { x, y, w, h, hash, .. } => {
                    json!({ "kind": "image", "x": x, "y": y, "w": w, "h": h, "hash": hex(hash) })
                }
                Command::Icon { x, y, size, shape, .. } => {
                    json!({ "kind": "icon", "x": x, "y": y, "size": size, "shape": shape })
                }
                other => json!({ "kind": format!("{other:?}") }),
            })
            .collect();
        json!(commands)
    })
    .unwrap()
}

/// Both tabs and the hotbar, with the files their hashes stand for.
fn write_preview() {
    let dir = mod_dir();
    let mut r = Rig::new(&[]);
    r.stock(
        ALICE,
        vec![Stack::new(r.granite, 124).unwrap(), Stack::new(r.marble, 270).unwrap()],
    );
    r.key(ALICE);
    let inventory = r.last();
    r.press(ALICE, "tab/shapes");
    r.press(ALICE, "stairs");
    let crafter = r.last();
    // Both tabs laid out by the engine at a mid-size and a small window.
    let screens: Vec<Value> = [(1280.0, 720.0), (800.0, 600.0)]
        .into_iter()
        .map(|(w, h)| {
            let area = room(w, h);
            let lay = |tree: &Tree| {
                let laid = ui::layout(tree, ui::Rect::new(0, 0, area.0, area.1), &Ruler);
                node_json(tree, 0, &laid)
            };
            json!({ "window": [w, h], "room": [area.0, area.1],
                "inventory": lay(&inventory), "crafter": lay(&crafter) })
        })
        .collect();

    // Paths are relative to the repository root, so the file travels.
    let mut textures = serde_json::Map::new();
    for entry in std::fs::read_dir(dir.join("textures")).unwrap() {
        let path = entry.unwrap().path();
        let hash = hex(&hash_bytes(&std::fs::read(&path).unwrap()));
        let name = path.file_name().unwrap().to_string_lossy().into_owned();
        textures.insert(hash, json!(format!("mods/{MOD}/textures/{name}")));
    }
    let hud = hud_json(&std::fs::read_to_string(dir.join("hud.lua")).unwrap());
    let out = json!({
        "note": "written by tests/native; draw it with tools/render_preview.py",
        "fonts": {
            DISPLAY_FONT: format!("mods/{MOD}/fonts/CinzelDecorative-Bold.ttf"),
            TEXT_FONT: format!("mods/{MOD}/fonts/Spectral-Regular.ttf"),
        },
        "textures": textures,
        "screens": screens,
        "hud": hud,
    });
    let target = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target");
    std::fs::create_dir_all(&target).unwrap();
    let at = target.join("preview.json");
    std::fs::write(&at, serde_json::to_string_pretty(&out).unwrap()).unwrap();
    println!("ok  wrote {} for tools/render_preview.py", at.display());
}

// --- The HUD ---------------------------------------------------------------------

fn hex(hash: &[u8; 32]) -> String {
    hash.iter().map(|b| format!("{b:02x}")).collect()
}

/// The hash the mod sends its HUD script on join, and the file it stands for.
///
/// Nothing is pasted by hand any more: `register_picture` answers this, so the
/// check is that what reaches the script is the hash of the shipped PNG, and
/// that the picture is registered — without which no client fetches the bytes
/// and every slot draws the "not arrived" box.
fn hotbar_frame() -> (String, [u8; 32]) {
    let mut r = Rig::new(&[]);
    let registered: Vec<String> = r.vm.registered_pictures().into_iter().map(|p| p.id).collect();
    assert!(
        registered.contains(&format!("{MOD}:hotbar_slot")),
        "the hotbar's picture is not registered, so no client would fetch it: {registered:?}"
    );
    r.join(ALICE);
    let values = r.huds.0.lock().unwrap().get(&ALICE).cloned().expect("the join sends the HUD its values");
    let Some(HudValue::Text(hash)) = values.get("slot_frame").cloned() else {
        panic!("the HUD was not sent slot_frame: {values:?}");
    };
    let file = hash_bytes(&std::fs::read(mod_dir().join("textures/hotbar-slot.png")).unwrap());
    assert_eq!(hash, hex(&file), "the hash sent to the HUD is not hotbar-slot.png's");
    (hash, file)
}

fn hud_check() {
    let dir = mod_dir();
    let source = std::fs::read_to_string(dir.join("hud.lua")).unwrap();
    let (hash, frame) = hotbar_frame();
    let stone = MaterialId(3);
    let loose = |units| Carried { material: stone, name: "Granite".into(), units, shape: 0, detail: None };
    for selected in 0..9 {
        let mut state = State::default();
        state.selected = selected;
        state.carried = vec![None; 9];
        state.carried[0] = Some(loose(40));
        state.carried[8] = Some(Carried { shape: 7, units: 270, ..loose(0) });
        state.offhand = Some(loose(54));
        state.tool = Some(HeldTool { id: "t".into(), name: "é".repeat(100), brush: String::new() });
        state.looking_at = Some(Look { cell: [0, 0, 0], material: stone, name: "Granite".into() });
        state.values.insert(MOD.into(), Values::from([("slot_frame".into(), HudValue::Text(hash.clone()))]));
        let mut hud = HudVm::new(HudLimits::default()).unwrap();
        hud.load(MOD, &source).expect("hud.lua loads");
        let faults = hud.draw(&state);
        assert!(faults.is_empty(), "hud faults with slot {selected} selected: {faults:?}");
        hud.with_frame(|f| {
            let icons = f.commands().iter().filter(|c| matches!(c, Command::Icon { .. })).count();
            assert_eq!(icons, 3, "a hole in the hotbar hid slot nine or the off-hand");
            for c in f.commands() {
                if let Command::Image { hash: drawn, .. } = c {
                    assert_eq!(*drawn, frame, "the hotbar drew a picture that is not its slot frame");
                }
                if let Command::Text { text, .. } = c {
                    assert!(text.len() <= 64, "an untrimmed line: {} bytes", text.len());
                }
            }
        })
        .unwrap();
    }
    // Before the value lands, the slots are rectangles rather than magenta.
    let mut bare = HudVm::new(HudLimits::default()).unwrap();
    bare.load(MOD, &source).unwrap();
    let mut state = State::default();
    state.carried = vec![None; 9];
    assert!(bare.draw(&state).is_empty(), "the hotbar faults with no values sent");
    bare.with_frame(|f| {
        assert!(
            !f.commands().iter().any(|c| matches!(c, Command::Image { .. })),
            "the hotbar asked for a picture before it had been told which"
        );
    })
    .unwrap();
    println!("ok  hud: registered picture, hash sent on join, drawn slots, UTF-8 trimming, nine selections");
}

fn main() {
    layout_and_paging();
    empty_crafter();
    full_and_empty_masks_do_not_spend();
    presets_conserve_units();
    stacks_are_limited();
    failed_transactions_refund();
    depleted_material_is_not_replaced();
    named_and_shaped_stacks_are_kept();
    players_are_isolated();
    carving_does_not_echo();
    another_mods_tab_and_buttons();
    faults_land_on_the_mod_that_wrote_them();
    round_trip_views();
    disabled_callbacks();
    the_look_is_declared();
    screens_fit_without_scrolling();
    craft_messages_fit();
    hud_check();
    write_preview();
    println!("PASS");
}
