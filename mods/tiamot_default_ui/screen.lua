-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The inventory screen: who has it open, which tabs and buttons it has, and
-- the one dialog they are all drawn into.
--
-- # Tabs and buttons come from two places
--
-- This mod's own tabs (tab_items.lua, tab_shapes.lua) register with
-- `add_tab` and are trusted: their widget names are used as they are, and
-- they keep per-player state in `data`.
--
-- Another mod's tabs and buttons arrive through the exports (exports.lua),
-- and everything about them is checked, because a mistake in them must not
-- become a fault in this mod. Their build and event functions run in THEIR
-- sandbox; if one errors, the engine disables that mod, and that call and
-- every later one answers nil here. Their trees are copied, field by known field, into plain tables
-- with a bound on depth and size, and every widget name is prefixed with the tab's key, so an event
-- goes back to the tab that drew the widget and to no other. If the engine
-- still refuses a tree, the send is retried without that tab, which is then
-- dropped for everybody.

local C, T = tdi.config, tdi.theme

local M = {}

local FORM = "inventory"
local ACTION = game.mod_id .. ":inventory"

game.register_action{ id = "inventory", default_key = "KeyE", description = "Open inventory / shape crafter" }

local sessions = {}   -- uuid -> { open, tab = key, data = { [key] = table } }
local tabs = {}       -- in strip order
local by_key = {}     -- key -> tab
local by_id = {}      -- qualified id -> tab
local buttons = {}    -- in registration order: { id, label, tab = key|nil, press }
local button_ids = {}
local serial = 0

-- Registries ----------------------------------------------------------------

local function sort_tabs()
    table.sort(tabs, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)
end

-- A tab of this mod's own. `spec`: `id` (unqualified), `label`, `order`,
-- `build(player, data)` returning a widget, `on_event(player, data, event)`
-- returning whether to redraw, and optionally `fresh()` for a player's first
-- `data` and `on_enter(player, data)` when the tab is selected.
function M.add_tab(spec)
    serial = serial + 1
    local tab = {
        key = spec.id, id = game.mod_id .. ":" .. spec.id, label = spec.label,
        order = spec.order, seq = serial, build = spec.build, on_event = spec.on_event,
        fresh = spec.fresh, on_enter = spec.on_enter,
    }
    tabs[#tabs + 1], by_key[tab.key], by_id[tab.id] = tab, tab, tab
    sort_tabs()
    return tab
end

local function label_ok(text)
    return type(text) == "string" and #text > 0 and #text <= C.max_label_bytes
end

local function id_ok(id)
    return type(id) == "string" and id:match("^[%w_]+:[%w_]+$") ~= nil
end

-- Another mod's tab. Never errors: answers `true`, or `nil` and why.
function M.add_external_tab(spec)
    if type(spec) ~= "table" then return nil, "add_tab takes a table" end
    local id, label, order = spec.id, spec.label, spec.order
    if not id_ok(id) then return nil, "tab id must be qualified, like \"my_mod:wardrobe\"" end
    if by_id[id] then return nil, "a tab with id " .. id .. " already exists" end
    if not label_ok(label) then return nil, "tab label must be 1 to " .. C.max_label_bytes .. " bytes" end
    if type(spec.build) ~= "function" then return nil, "tab build must be a function" end
    if spec.on_event ~= nil and type(spec.on_event) ~= "function" then
        return nil, "tab on_event must be a function or nil"
    end
    if order ~= nil and (math.type(order) ~= "integer") then return nil, "tab order must be an integer" end
    serial = serial + 1
    local tab = {
        key = "@" .. serial, id = id, label = label, order = order or C.tab_order_default,
        seq = serial, build = spec.build, on_event = spec.on_event, external = true,
    }
    tabs[#tabs + 1], by_key[tab.key], by_id[tab.id] = tab, tab, tab
    sort_tabs()
    game.log(string.format("%s: tab %s added", game.mod_id, id))
    return true
end

-- Another mod's button. Never errors: answers `true`, or `nil` and why.
function M.add_external_button(spec)
    if type(spec) ~= "table" then return nil, "add_button takes a table" end
    local id, label, tab = spec.id, spec.label, spec.tab
    if not id_ok(id) then return nil, "button id must be qualified, like \"my_mod:wardrobe\"" end
    if button_ids[id] then return nil, "a button with id " .. id .. " already exists" end
    if not label_ok(label) then return nil, "button label must be 1 to " .. C.max_label_bytes .. " bytes" end
    if type(spec.on_press) ~= "function" then return nil, "button on_press must be a function" end
    local key
    if tab ~= nil then
        if type(tab) ~= "string" or not by_id[tab] then return nil, "button tab names no tab: " .. tostring(tab) end
        key = by_id[tab].key
    end
    buttons[#buttons + 1] = { id = id, label = label, tab = key, press = spec.on_press }
    button_ids[id] = true
    return true
end

-- Sessions ------------------------------------------------------------------

local function session(player)
    local s = sessions[player]
    if not s then
        s = { open = false, tab = tabs[1].key, data = {} }
        sessions[player] = s
    end
    return s
end

-- A built-in tab's state for one player, made on first use.
function M.data(player, tab)
    local s = session(player)
    if not s.data[tab.key] then
        s.data[tab.key] = tab.fresh and tab.fresh() or {}
    end
    return s.data[tab.key]
end

-- The selected tab, falling back to the first if it has gone.
local function current(s)
    local tab = by_key[s.tab]
    if not tab or tab.broken then
        tab = tabs[1]
        s.tab = tab.key
    end
    return tab
end

local function choose(player, s, tab)
    if s.tab == tab.key then return end
    s.tab = tab.key
    if tab.on_enter then tab.on_enter(player, M.data(player, tab)) end
end

-- Another mod's tree ----------------------------------------------------------

-- The fields a widget and a style may have (see Tiamot.Widget in the stubs).
-- Another mod's tree is copied by these names, not with `pairs`, so only what
-- the engine documents reaches `update_dialog`, and lists are walked by index
-- to the first gap, so every copy is bounded.
local WIDGET_FIELDS = {
    "type", "name", "grow", "size", "cross_size", "direction", "gap", "padding", "align",
    "text", "initial", "placeholder", "checked", "min", "max", "value", "selected",
    "view", "index", "columns", "first", "count", "permille", "shape", "material",
}
local STYLE_COLOURS = { "background", "border", "text_colour" }
local MAX_OPTIONS = 256

local function scalar(value)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    return nil
end

-- Scalars at 1, 2, 3... up to `most`, stopping at the first gap.
local function list(value, most)
    if type(value) ~= "table" then return nil end
    local out = {}
    for i = 1, most do
        local item = scalar(value[i])
        if item == nil then break end
        out[i] = item
    end
    return out
end

local function style(value)
    if type(value) ~= "table" then return nil end
    local out = { font = scalar(value.font), text_size = scalar(value.text_size) }
    for _, key in ipairs(STYLE_COLOURS) do
        out[key] = list(value[key], 4)
    end
    out.nine_slice = list(value.nine_slice, 32)
    return out
end

-- Rebuilds another mod's widget as plain tables this mod owns, prefixing
-- every name. Answers nil for anything that is not a widget or goes past the
-- bounds, which includes a tree that contains itself.
local function rebuild(node, prefix, depth, count)
    if type(node) ~= "table" or depth > C.max_tree_depth then return nil end
    count.n = count.n + 1
    if count.n > C.max_tree_nodes then return nil end
    local out = {}
    for _, key in ipairs(WIDGET_FIELDS) do
        out[key] = scalar(node[key])
    end
    if type(out.type) ~= "string" then return nil end
    if type(out.name) == "string" then out.name = prefix .. out.name end
    out.style = style(node.style)
    out.options = list(node.options, MAX_OPTIONS)
    out.hash = list(node.hash, 32)
    local children = node.children
    if children ~= nil then
        if type(children) ~= "table" then return nil end
        out.children = {}
        local i = 1
        while children[i] ~= nil do   -- bounded: every child counts toward max_tree_nodes
            local child = rebuild(children[i], prefix, depth + 1, count)
            if child == nil then return nil end
            out.children[i] = child
            i = i + 1
        end
    end
    return out
end

-- `rebuild` under pcall: reading another mod's table can run its metamethods,
-- and an error in one of those must not become this mod's fault.
local function adopt(tree, prefix)
    local ok, result = pcall(rebuild, tree, prefix, 1, { n = 0 })
    return ok and result or nil
end

local function drop(tab, why)
    tab.broken = true
    game.log(string.format("%s: tab %s dropped: %s", game.mod_id, tab.id, why))
end

-- The screen ------------------------------------------------------------------

-- The tabs, left to right. Nothing else goes in the strip, so every pixel of
-- it is for tabs: at 800x600 it holds the built-in two and three or four more.
local function strip(s)
    local row = {}
    for _, tab in ipairs(tabs) do
        if not tab.broken then
            row[#row + 1] = T.tab_button("tab/" .. tab.key, tab.label, s.tab == tab.key)
        end
    end
    row[#row + 1] = T.space(1)
    return T.row(row, C.tab_height)
end

-- The header: the name on the left, and the buttons other mods put on every
-- tab at the right end.
local function header()
    local row = { T.label("T I A M O T", 16, T.colours.brass), T.space(1) }
    for n, b in ipairs(buttons) do
        if b.tab == nil then row[#row + 1] = T.button("button/" .. n, b.label, false, 15) end
    end
    local line = T.row(row, C.header_height)
    line.align = "center"
    return line
end

-- The buttons another mod put on one tab, as a row along its bottom, or nil.
local function tab_buttons(key)
    local row = {}
    for n, b in ipairs(buttons) do
        if b.tab == key then row[#row + 1] = T.button("button/" .. n, b.label) end
    end
    if #row == 0 then return nil end
    row[#row + 1] = T.space(1)
    return T.row(row, C.row_height)
end

local function body(player, tab)
    if not tab.external then
        return tab.build(player, M.data(player, tab))
    end
    local tree = adopt(tab.build(player), tab.key .. "/")
    if tree == nil then
        drop(tab, "its build answered no widget, or one past the limits")
    end
    return tree
end

-- # The screen fits its sheet; nothing scrolls
--
-- The header and the tab strip have fixed heights. The body starts at zero
-- and grows into everything left, so it is exactly the room the window has.
-- A tab's content fills the body the same way; if it wants more than there
-- is, the engine shrinks it proportionally rather than letting it run off.
local function screen(player, s)
    local tab = current(s)
    local content = body(player, tab)
    if content == nil then
        tab = current(s)   -- the broken tab is gone; this is the first tab
        content = body(player, tab)
    end
    content.size, content.grow = 0, 1
    local inner = { content }
    inner[#inner + 1] = tab_buttons(tab.key)
    local main = T.box("column", inner, 8)
    main.size, main.grow = 0, 1

    return T.frame({ header(), strip(s), main })
end

-- Whether a tree is being built. Another mod's build may call `redraw` or
-- `open` through the exports; sending from inside a send would build that
-- tab again, and again, so those calls do nothing until the tree is done.
local drawing = false

-- Shows or updates the dialog. If the engine refuses the tree while another
-- mod's tab is selected, that tab is dropped and the send tried once more;
-- a refusal of this mod's own tree is this mod's bug, and is raised.
local function send(player, s, first)
    if drawing then return s.open end
    local call = first and game.show_dialog or game.update_dialog
    drawing = true
    local built, tree = pcall(screen, player, s)
    drawing = false
    if not built then error(tree, 0) end
    local ok, shown = pcall(call, { player = player, form = FORM, tree = tree })
    if ok then return shown end
    local tab = current(s)
    if not tab.external then error(shown, 0) end
    drop(tab, "the engine refused its tree: " .. tostring(shown))
    drawing = true
    tree = screen(player, s)
    drawing = false
    return call{ player = player, form = FORM, tree = tree }
end

-- Opening and closing ---------------------------------------------------------

-- Opens the screen, on tab `key` if given, or updates it if already open.
function M.open(player, key)
    local s = session(player)
    local tab = key and by_key[key]
    if tab and not tab.broken then choose(player, s, tab) end
    if s.open then
        send(player, s, false)
    else
        s.open = send(player, s, true) == true
    end
    return s.open
end

function M.close(player)
    local s = sessions[player]
    if s and s.open then
        game.close_dialog{ player = player, form = FORM }
        s.open = false
    end
end

function M.redraw(player)
    local s = sessions[player]
    if s and s.open then send(player, s, false) end
end

function M.is_open(player)
    local s = sessions[player]
    return s ~= nil and s.open
end

function M.tab_id(player)
    local s = sessions[player]
    return s and current(s).id or nil
end

function M.key_of(id)
    local tab = by_id[id]
    return tab and tab.key or nil
end

-- Events --------------------------------------------------------------------

-- What another mod's tab is told: the event's own fields, with the widget
-- name as that tab wrote it.
local function event_for(event, name)
    return { player = event.player, kind = event.kind, name = name, text = event.text,
        checked = event.checked, value = event.value, index = event.index, view = event.view,
        click = event.click, shape = event.shape }
end

tdi.on_action(ACTION, function(event)
    if not event.pressed then return end
    if M.is_open(event.player) then
        M.close(event.player)
    else
        M.open(event.player)
    end
end)

tdi.on_dialog(FORM, function(event)
    local player = event.player
    local s = sessions[player]
    if not s or not s.open then return end
    if event.kind == "closed" then
        s.open = false
        return
    end
    local name = event.name

    if event.kind == "pressed" and name then
        local key = name:match("^tab/(.+)$")
        if key then
            local tab = by_key[key]
            if tab and not tab.broken then
                choose(player, s, tab)
                M.redraw(player)
            end
            return
        end
        local n = name:match("^button/(%d+)$")
        if n then
            local b = buttons[tonumber(n)]
            -- A tab's button pressed after its tab was left is a stale click.
            if b and (b.tab == nil or b.tab == s.tab) then
                b.press(player)
                M.redraw(player)
            end
            return
        end
    end

    local tab = current(s)
    if tab.external then
        local own = name
        if name then
            local prefix = tab.key .. "/"
            if name:sub(1, #prefix) ~= prefix then return end   -- from a tab no longer shown
            own = name:sub(#prefix + 1)
        end
        if tab.on_event and tab.on_event(player, event_for(event, own)) == true then
            M.redraw(player)
        end
    elseif tab.on_event(player, M.data(player, tab), event) then
        M.redraw(player)
    end
end)

tdi.on_leave(function(event)
    sessions[event.player] = nil
end)

return M
