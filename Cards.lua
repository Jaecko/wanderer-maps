local _, ns = ...
local L = ns.L

-- The small cards of Wanderer Maps, opened where you click (never in the
-- middle of the screen), all made of Wanderer's own card (Skin.Card, the
-- Bags mark card's look): the note card (Alt+click on the world map, a note's
-- pin, a note's row): its name, eight signs to choose from (keys 1 to 8, Alt
-- with them while the name is typed), save, follow or put on the route; the
-- arrow's card (its right click): the next step, plan again, clear, the
-- route's window (keys 1 to 4), the step's quest; a step's card of choices
-- (its "⋯", its right click). Closed by Escape, a choice, or a click
-- elsewhere.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local NOTE_WIDTH = 266 -- the note card's content: four tiles of the kit's card

-- The note card --------------------------------------------------------------------------------------------

local note -- the card, made at its first use

local FillNote

local function ChooseIcon(index)
	local icon = ns.NOTE_ICONS[index]
	if not (icon and note and note:IsShown()) then return end
	note.sign = icon.key
	FillNote()
	note.input:SetFocus()
end

-- Saved as the card says: a new note, or the note changed; then followed, or a step of the route instead.
local function SaveNote(how)
	local card = note
	if not card then return end
	local title = (card.input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if title == "" then title = card.placeName end
	local place = card.note
	if how == "route" then
		local step = ns.AddStep(card.map, card.x, card.y, title)
		if step then
			if place then ns.TouchNote(place) end
			W.Print(L.ADDED_STEP:format(step.title))
		end
	elseif place then
		place.title = title
		place.icon = card.sign ~= "place" and card.sign or nil
		ns.TouchNote(place)
		ns.Changed()
	else
		place = ns.AddNote(card.map, card.x, card.y, title, card.sign)
		if place then W.Print(L.ADDED_NOTE:format(place.title)) end
	end
	Skin.Play("confirm")
	card:Hide()
	if how == "follow" and place then ns.GoTo(place) end
end

local function MakeNoteCard()
	note = Skin.Card("WandererMapsNoteCard")
	note.onHide = function(self) self.input:ClearFocus() end
	-- Its name: the place's, chosen to be typed over; Enter saves (Shift: and follows; Ctrl: a step instead).
	note.box = CreateFrame("Frame", nil, note)
	note.box:SetSize(NOTE_WIDTH, 24)
	note.input = Skin.CreateInput(note.box, nil, 40, {
		hint = L.NOTE_NAME_HINT,
		onEnter = function()
			if note.here then return SaveNote() end
			SaveNote(IsShiftKeyDown() and "follow" or IsControlKeyDown() and "route" or nil)
		end,
		onEscape = function() note:Hide() end,
	})
	note.input:SetPoint("TOPLEFT")
	note.input:SetSize(NOTE_WIDTH, 24)
	-- (its keys under the name, on as many lines as each language needs)
	note.keysLine = Skin.Text(note.box, "GameTooltipTextSmall", "muted")
	note.keysLine:SetPoint("TOPLEFT", note.input, "BOTTOMLEFT", 0, -6)
	note.keysLine:SetWidth(NOTE_WIDTH)
	note.keysLine:SetJustifyH("LEFT")
	if note.keysLine.SetWordWrap then note.keysLine:SetWordWrap(true) end
	note.keysLine:SetText(L.NOTE_KEYS)
	note.box:SetHeight(24 + 6 + U.Measure(note.keysLine, "GetStringHeight", 24))
	-- (Alt+1 to 8: a sign, while the name is typed)
	note.input:HookScript("OnKeyDown", function(_, key)
		if not IsAltKeyDown() then return end
		local index = tonumber(type(key) == "string" and (key:match("^NUMPAD(%d)$") or key) or "")
		if index and ns.NOTE_ICONS[index] then
			Skin.Play("mark")
			ChooseIcon(index)
		end
	end)
end

-- Its words, its eight signs (the one chosen in gold), its actions (Remove when a note is changed).
function FillNote()
	local card = note
	local tiles = {}
	for index, icon in ipairs(ns.NOTE_ICONS) do
		tiles[index] = { sign = ns.NoteIconSign(icon.key), label = L[icon.word], tip = L[icon.word .. "_TIP"],
			on = icon.key == card.sign, stay = true, run = function() ChooseIcon(index) end }
	end
	local rows = { { text = L.NOTE_SAVE, main = true, run = function() SaveNote() end } }
	-- (a note where you stand: nothing to follow there now; the keys line says only what works)
	card.here = ns.IsHere(card.map, card.x, card.y)
	if not card.here then
		rows[2] = { text = L.NOTE_FOLLOW, run = function() SaveNote("follow") end }
		rows[3] = { text = L.NOTE_ROUTE, run = function() SaveNote("route") end }
	end
	card.keysLine:SetText(card.here and L.NOTE_KEYS_HERE or L.NOTE_KEYS)
	card.box:SetHeight(24 + 6 + U.Measure(card.keysLine, "GetStringHeight", 24))
	if card.note then
		rows[#rows + 1] = { text = L.REMOVE, role = "bad", run = function()
			local place = card.note
			card:Hide()
			if place then ns.RemoveNote(place) end
		end }
	end
	local zone = U.MapName(card.map) or ""
	local where = ((zone ~= "" and zone ~= card.placeTitle) and (zone .. U.SEPARATOR) or "") .. ("%.1f, %.1f"):format(card.x * 100, card.y * 100)
	card:Fill({ title = card.placeTitle, now = (card.note and L.NOTE_EDIT or L.NOTE_NEW) .. U.SEPARATOR .. where, body = card.box,
		bodyHeight = note.box:GetHeight(), tiles = tiles, perRow = 4, minWidth = NOTE_WIDTH, rows = rows })
end

-- The note card for a place of a map (x, y from 0 to 1), at the mouse: a new note, or the note given (changed).
function ns.NoteCard(map, x, y, place)
	if not (map and x and y) then return false end
	if not note then MakeNoteCard() end
	local name = U.MapName(map, x, y) or ""
	note.map, note.x, note.y, note.note = map, x, y, place
	note.placeName = name ~= "" and name or L.UNKNOWN_HERE
	note.sign = place and place.icon or "place"
	note.placeTitle = place and place.title or note.placeName
	note.input:SetText(note.placeTitle)
	FillNote()
	note:Present(nil)
	note.input:SetFocus()
	note.input:HighlightText()
	return true
end

-- The arrow's card ------------------------------------------------------------------------------------------

local arrowCard

-- Its tiles: what can be done with the route (keys 1 to 4, as every card of Wanderer).
local ARROW_TILES = {
	{ word = "NEXT", tip = "CARD_NEXT_TIP", sign = { glyph = "chevron" }, run = function() ns.NextStep() end, route = true },
	{ word = "RECOMPUTE_SHORT", tip = "CARD_REPLAN_TIP", sign = { glyph = "reload" }, run = function() ns.Replan() end, route = true },
	{ word = "CLEAR_SHORT", tip = "CARD_CLEAR_TIP", sign = { glyph = "close" }, run = function() ns.ClearAsked() end, route = true },
	{ word = "ROUTE_WINDOW", tip = "CARD_WINDOW_TIP", sign = { file = "Interface\\Icons\\INV_Misc_Map_01", coords = { 0.08, 0.92, 0.08, 0.92 } },
		run = function() ns.Toggle() end },
}

-- The arrow's card at the mouse: the step followed named, the tiles (those of the route dimmed without one), its
-- quest one click away when it is one of Wanderer Quests.
function ns.ArrowCard()
	arrowCard = arrowCard or Skin.Card("WandererMapsArrowCard")
	local route = ns.Route()
	local step = ns.CurrentStep()
	local tiles = {}
	for index, spec in ipairs(ARROW_TILES) do
		-- (the next step only when there is one: the last one is ended by Clear)
		local none = spec.route and not step or (spec.word == "NEXT" and not ns.NextOpenStep())
		tiles[index] = { sign = spec.sign, label = L[spec.word], tip = L[spec.tip], disabled = none, run = spec.run }
	end
	local rows
	if step and step.quest and ns.CanOpenQuest() then
		local quest = step.quest
		rows = { { text = L.OPEN_QUEST, main = true, run = function() ns.OpenQuest(quest) end } }
	end
	arrowCard:Fill({ title = step and ns.StepWords(step) or L.NO_STEP,
		now = step and #route.steps > 1 and L.STEP_OF:format(route.current, #route.steps) or nil, tiles = tiles, rows = rows })
	arrowCard:Present(nil)
end

-- A step's card --------------------------------------------------------------------------------------------

-- A step's choices (the window's "⋯" and right click, a step pin's right click): go there, its quest, move it,
-- keep it as a note, remove it. A leg of the way: plan it again. Each choice only while the step is still there.
function ns.StepCard(owner, index, leg)
	local route = ns.Route()
	local step = route.steps[index]
	if not step then return end
	if leg then
		return Skin.ActionCard(owner, { title = ns.LegWords(leg), atCursor = true, width = 280,
			rows = { { text = L.RECOMPUTE, glyph = "reload", onClick = function() ns.Replan() end } } })
	end
	local function Still(fn) return function() if ns.Route().steps[index] == step then fn() end end end
	-- (Go there only for a step not followed already: the one followed is where the arrow points)
	local rows = {}
	if index ~= route.current or step.done then
		rows[1] = { text = L.GO_THERE, glyph = "chevron", onClick = Still(function() ns.FollowStep(index) end) }
	end
	if step.quest and ns.CanOpenQuest() then
		rows[#rows + 1] = { text = L.OPEN_QUEST, glyph = "grid", hint = L.OPEN_QUEST_DESC, onClick = function() ns.OpenQuest(step.quest) end }
	end
	if index > 1 then rows[#rows + 1] = { text = L.MOVE_UP, glyph = "up", onClick = Still(function() ns.MoveStep(index, -1) end) } end
	if index < #route.steps then
		rows[#rows + 1] = { text = L.MOVE_DOWN, glyph = "down", onClick = Still(function() ns.MoveStep(index, 1) end) }
	end
	rows[#rows + 1] = { text = L.ACT_TO_NOTE, glyph = "star", onClick = Still(function()
		local kept = ns.AddNote(step.map, step.x, step.y, step.title)
		if kept then W.Print(L.ADDED_NOTE:format(kept.title)) end
	end) }
	rows[#rows + 1] = { text = L.REMOVE, glyph = "close", role = "bad", onClick = Still(function() ns.RemoveStep(index) end) }
	Skin.ActionCard(owner, { title = ns.StepWords(step), atCursor = true, width = 280, rows = rows })
end

-- The notes' filter card ------------------------------------------------------------------------------------
-- From the world map's button: a tile for each sign (lit: shown; a click hides or shows that sign), the main
-- button hides every note or shows them again. The minimap follows the same choice. Kept for each character.

local filterCard

local function FillFilter()
	local card = filterCard
	local counts, total, shown = {}, 0, 0
	for _, each in ipairs(ns.Notes()) do
		local key = each.icon or "place"
		counts[key] = (counts[key] or 0) + 1
		total = total + 1
		if ns.NoteShown(each) then shown = shown + 1 end
	end
	local hidden = ns.NotesHidden()
	local tiles = {}
	for index, icon in ipairs(ns.NOTE_ICONS) do
		local key = icon.key
		tiles[index] = { sign = ns.NoteIconSign(key), label = L[icon.word], tip = L.FILTER_SIGN_TIP:format(counts[key] or 0),
			on = not ns.SignHidden(key), disabled = hidden, stay = true, run = function()
				ns.SetSignHidden(key, not ns.SignHidden(key))
				if card:IsShown() then FillFilter() end
			end }
	end
	card:Fill({ title = L.FILTER_TITLE, now = L.FILTER_NOW:format(shown, total), tiles = tiles, perRow = 4, minWidth = NOTE_WIDTH,
		rows = { { text = hidden and L.NOTES_SHOW or L.NOTES_HIDE, main = true, run = function() ns.SetNotesHidden(not hidden) end } } })
end

function ns.FilterCard(owner)
	filterCard = filterCard or Skin.Card("WandererMapsFilterCard")
	FillFilter()
	filterCard:Present(owner)
end

-- Notes removed by sign or by zone (the notes' tab): a card of what can go, how many each; asked first.
local ZONES_SHOWN = 12
function ns.RemoveNotesCard(owner)
	local signs, zones = ns.NoteGroups()
	local rows = {}
	for _, entry in ipairs(signs) do
		local key, count = entry.key, entry.count
		rows[#rows + 1] = { text = L.REMOVE_SIGN:format(ns.NoteIconMarkup(key) .. " " .. L[ns.NoteIconSpec(key).word]), right = tostring(count),
			role = "bad", onClick = function() ns.RemoveNotesAsked("sign", key, count) end }
	end
	-- (the zones holding most notes, when there are many)
	table.sort(zones, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	for index = 1, math.min(#zones, ZONES_SHOWN) do
		local map, count = zones[index].map, zones[index].count
		rows[#rows + 1] = { text = L.REMOVE_ZONE:format(zones[index].name), right = tostring(count), role = "bad",
			onClick = function() ns.RemoveNotesAsked("zone", map, count) end }
	end
	if not rows[1] then return nil end
	return Skin.ActionCard(owner, { title = L.REMOVE_NOTES, atCursor = true, width = 300, rows = rows, foot = L.REMOVE_NOTES_FOOT })
end

-- Routes kept (the route's tab): keep the one followed under a name, load one in its place, rename, remove.
local function KeptCard(owner, index)
	local kept = ns.KeptRoutes()[index]
	if not kept then return end
	local function Still(fn) return function() if ns.KeptRoutes()[index] == kept then fn() end end end
	Skin.ActionCard(owner, { title = kept.name, atCursor = true, width = 280, rows = {
		{ text = L.KEPT_LOAD, glyph = "chevron", onClick = Still(function() ns.LoadKeptAsked(index) end) },
		{ text = L.KEPT_RENAME, glyph = "reload", onClick = Still(function()
			Skin.AskText(L.KEPT_RENAME_ASK, kept.name, function(name) ns.RenameKept(index, name) end, ns.KEPT_LETTERS)
		end) },
		{ text = L.REMOVE, glyph = "close", role = "bad", onClick = Still(function()
			Skin.Ask(L.KEPT_REMOVE_ASK:format(kept.name), function() if ns.KeptRoutes()[index] == kept then ns.RemoveKept(index) end end)
		end) },
	} })
end

function ns.KeptRoutesCard(owner)
	local steps = ns.Route().steps
	local rows = {}
	if steps[1] then
		rows[1] = { text = L.KEEP_ROUTE, glyph = "plus", hint = L.KEEP_ROUTE_DESC, onClick = function()
			Skin.AskText(L.KEEP_ROUTE_ASK, U.MapName(steps[1].map) or "", function(name)
				local kept = ns.KeepRoute(name)
				if kept then W.Print(L.KEPT_DONE:format(kept.name, #kept.steps)) end
			end, ns.KEPT_LETTERS)
		end }
	end
	for index, kept in ipairs(ns.KeptRoutes()) do
		rows[#rows + 1] = { text = kept.name, glyph = "grid", right = L.KEPT_STEPS:format(#(kept.steps or {})),
			onClick = function() KeptCard(owner, index) end }
	end
	return Skin.ActionCard(owner, { title = L.KEPT_TITLE, atCursor = true, width = 300, rows = rows,
		foot = not ns.KeptRoutes()[1] and L.KEPT_NONE or nil })
end

-- Wanderer Quests' sheet of a quest, when it is there.
function ns.CanOpenQuest()
	local quests = _G.WandererQuests
	return type(quests) == "table" and type(quests.Reveal) == "function"
end
function ns.OpenQuest(id)
	if id and ns.CanOpenQuest() then _G.WandererQuests.Reveal(id) end
end
