local _, ns = ...
local L = ns.L

-- Places: a note (map, x, y from 0 to 1, a name) kept on the world map, and
-- the route: steps in order, the current one followed by the arrow. Kept for
-- each character. World positions (yards, by continent) are the game's own,
-- read from a map point; the player's from where they stand.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local MAX_NOTES, MAX_STEPS = 200, 40

-- This character's settings of Wanderer Maps (nil: Wanderer has none for it yet).
function ns.Settings() return W and W.Settings and W.Settings("maps") or nil end

-- The saved table, checked once (the arrow and the minimap read it ten times a second; it only changes when the
-- game loads it).
-- Tooltips ---------------------------------------------------------------------------------------------------
-- A tooltip in the kit's lines ({ title (gold), { words, r, g, b } or words, ... }) for a frame not ours to hook
-- (a map pin, a row whose side changes): the kit's own.
function ns.ShowTip(owner, lines, anchor) return Skin.ShowTip(owner, lines, anchor) end
-- A tooltip line in one of the kit's colors (text, soft, blue: a hint).
function ns.TipLine(words, role)
	local c = Skin.COLORS[role] or Skin.COLORS.text
	return { words, c[1], c[2], c[3] }
end

local checked
function ns.DB()
	if checked ~= nil and checked == WandererMapsDB then return checked end
	WandererMapsDB = type(WandererMapsDB) == "table" and WandererMapsDB or {}
	local db = WandererMapsDB
	db.notes = type(db.notes) == "table" and db.notes or {}
	db.route = type(db.route) == "table" and db.route or { steps = {}, current = 1 }
	db.route.steps = type(db.route.steps) == "table" and db.route.steps or {}
	db.route.current = math.max(1, math.floor(tonumber(db.route.current) or 1))
	if type(db.route.legs) ~= "table" then db.route.legs = nil end
	db.route.leg = math.max(1, math.floor(tonumber(db.route.leg) or 1))
	if type(db.route.planned) ~= "string" then db.route.planned = nil end
	db.hiddenSigns = type(db.hiddenSigns) == "table" and db.hiddenSigns or {}
	db.notesHidden = db.notesHidden == true or nil
	db.kept = type(db.kept) == "table" and db.kept or {}
	if db.noteSort ~= "used" then db.noteSort = nil end
	checked = db
	return db
end

-- Places in the world ---------------------------------------------------------------------------------------

-- (Wanderer's world: here x runs west and y north, as HereBeDragons counts them; the game's order swapped)
-- A map point in the world: x, y (yards) and the continent (nil: unknown).
function ns.WorldOf(map, x, y)
	local wx, wy, instance = U.MapToWorld(map, x, y)
	if not wx then return nil end
	return wy, wx, instance
end

-- A place on a map shown (x, y from 0 to 1): its own, or the one around it or inside it (nil: not on it).
function ns.OnMap(place, map)
	if place.map == map then return place.x, place.y end
	local wx, wy, instance = U.MapToWorld(place.map, place.x, place.y)
	if not wx then return nil end
	local _, x, y = U.WorldToMap(instance, wx, wy, map)
	return x, y
end

-- A dotted line's dots, by its length: one every few yards of the world, as the map's scale puts them on the
-- screen, never closer nor farther apart than a few pixels. pixels: its length on the screen; yardsPerPixel:
-- the map's scale (nil: unknown, the middle spacing). The spaces between its dots: dots at shares 0, 1/n... 1,
-- so its two ends always.
local DOT_YARDS, DOT_GAP_MIN, DOT_GAP_MAX, DOTS_MOST = 30, 7, 18, 80
function ns.DotSpaces(pixels, yardsPerPixel)
	if not (type(pixels) == "number" and pixels > 0) then return 1 end
	local gap = (type(yardsPerPixel) == "number" and yardsPerPixel > 0) and DOT_YARDS / yardsPerPixel
		or (DOT_GAP_MIN + DOT_GAP_MAX) / 2
	gap = math.max(DOT_GAP_MIN, math.min(DOT_GAP_MAX, gap))
	return math.max(1, math.min(DOTS_MOST - 1, math.floor(pixels / gap + 0.5)))
end

-- A time as a clock says it: "2:14", "1:02:30" past an hour.
function ns.Clock(seconds)
	seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
	local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
	if hours > 0 then return ("%d:%02d:%02d"):format(hours, minutes, seconds % 60) end
	return ("%d:%02d"):format(minutes, seconds % 60)
end

-- A pin's icon: the game's map pin (gold: the one followed, or a step on the world map), else the quest
-- arrow. Set only when it changes (the minimap's pins are looked at ten times a second).
local ATLAS = { plain = "Waypoint-MapPin-Untracked", gold = "Waypoint-MapPin-Tracked" }
ns.QUEST_ARROW = "Interface\\Minimap\\Minimap-QuestArrow"
local hasAtlas
function ns.StepIcon(texture, gold)
	gold = gold and true or false
	if texture.wandererGold == gold then return end
	texture.wandererGold = gold
	if hasAtlas == nil then hasAtlas = U.HasAtlas(ATLAS.plain) and true or false end
	if not hasAtlas then
		texture:SetTexture(ns.QUEST_ARROW)
		texture:SetTexCoord(0, 1, 0, 1)
		return texture:SetVertexColor(Skin.COLORS.gold[1], Skin.COLORS.gold[2], Skin.COLORS.gold[3])
	end
	texture:SetAtlas(gold and ATLAS.gold or ATLAS.plain)
	texture:SetVertexColor(1, 1, 1)
	texture:SetRotation(0)
end

-- A note's signs, chosen on its card (keys 1 to 8): the plain mark, then the game's own icons. A square icon is
-- cropped of its frame; the meeting flag is your side's.
ns.NOTE_ICONS = {
	{ key = "place", atlas = ATLAS.plain, word = "ICON_PLACE" },
	{ key = "star", file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", word = "ICON_STAR" },
	{ key = "treasure", file = "Interface\\Icons\\INV_Box_01", crop = true, word = "ICON_TREASURE" },
	{ key = "herb", file = "Interface\\Icons\\INV_Misc_Flower_02", crop = true, word = "ICON_HERB" },
	{ key = "ore", file = "Interface\\Icons\\INV_Ore_Copper_01", crop = true, word = "ICON_ORE" },
	{ key = "danger", file = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", word = "ICON_DANGER" },
	{ key = "meeting", file = "Interface\\Icons\\INV_BannerPVP_02", horde = "Interface\\Icons\\INV_BannerPVP_01", crop = true, word = "ICON_MEETING" },
	{ key = "question", file = "Interface\\Icons\\INV_Misc_QuestionMark", crop = true, word = "ICON_QUESTION" },
}
local iconOf = {}
for index, icon in ipairs(ns.NOTE_ICONS) do
	icon.index = index
	iconOf[icon.key] = icon
end
function ns.NoteIconSpec(key) return iconOf[key] or ns.NOTE_ICONS[1] end

-- A sign's file: the meeting flag of your side.
local function IconFile(icon)
	local horde = icon.horde and U.Clean(U.Safe(UnitFactionGroup, "player")) == "Horde"
	return horde and icon.horde or icon.file
end

-- A note's sign on a texture (the plain mark when none was chosen).
function ns.NoteIcon(texture, key)
	local icon = ns.NoteIconSpec(key)
	texture.wandererGold = nil -- (a step's icon set after this one is set again)
	texture:SetRotation(0)
	texture:SetVertexColor(1, 1, 1)
	if icon.atlas then
		if hasAtlas == nil then hasAtlas = U.HasAtlas(ATLAS.plain) and true or false end
		if hasAtlas then return texture:SetAtlas(icon.atlas) end
		texture:SetTexture(ns.QUEST_ARROW)
		texture:SetTexCoord(0, 1, 0, 1)
		return texture:SetVertexColor(Skin.COLORS.gold[1], Skin.COLORS.gold[2], Skin.COLORS.gold[3])
	end
	texture:SetTexture(IconFile(icon))
	if icon.crop then texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) else texture:SetTexCoord(0, 1, 0, 1) end
end

-- A note's sign as a tile of Wanderer's cards shows one ({ atlas } or { file, coords }).
function ns.NoteIconSign(key)
	local icon = ns.NoteIconSpec(key)
	if icon.atlas then
		if hasAtlas == nil then hasAtlas = U.HasAtlas(ATLAS.plain) and true or false end
		return hasAtlas and { atlas = icon.atlas } or { file = ns.QUEST_ARROW }
	end
	return { file = IconFile(icon), coords = icon.crop and { 0.08, 0.92, 0.08, 0.92 } or nil }
end

-- A note's sign inside words (a tooltip, a row).
function ns.NoteIconMarkup(key, size)
	local icon = ns.NoteIconSpec(key)
	size = size or 14
	if icon.atlas then return CreateAtlasMarkup and CreateAtlasMarkup(icon.atlas, size, size) or "" end
	local file = IconFile(icon)
	if icon.crop then return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(file, size, size) end
	return ("|T%s:%d:%d|t"):format(file, size, size)
end

-- A place as a map link in the chat's box (never sent: the player sends it or not); false when no box opens. Its
-- name and zone after it, in words (the game's link shows no place).
function ns.ChatLink(map, x, y, title)
	map, x, y = tonumber(map), tonumber(x), tonumber(y)
	if not (map and x and y) then return false end
	local link = ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(map, math.floor(x * 10000 + 0.5), math.floor(y * 10000 + 0.5),
		_G.MAP_PIN_HYPERLINK or L.MAP_LINK)
	return U.ChatInsert(link .. ns.LinkWords(map, title))
end

-- The words after a map link: " Forge (Burning Steppes)", the zone alone when the name is the zone's.
function ns.LinkWords(map, title)
	local zone = U.MapName(map) or ""
	title = type(title) == "string" and title or ""
	if title ~= "" and zone ~= "" and title ~= zone then return " " .. L.LINK_PLACE:format(title, zone) end
	local words = title ~= "" and title or zone
	return words ~= "" and (" " .. words) or ""
end

-- Where you stand in the world (nil inside an instance, where the game keeps it to itself).
function ns.Here()
	local wx, wy, instance = U.Here()
	if not wx then return nil end
	return wy, wx, instance
end

-- From you to a world point: the angle to turn (counter-clockwise, as the game's facing) and the distance in
-- yards; nil on another continent or unknown.
function ns.Vector(tx, ty, instance)
	local px, py, here = ns.Here()
	return ns.VectorFrom(px, py, here, tx, ty, instance)
end

-- The same from a place already read (px, py, here: ns.Here()'s), for many points at once.
function ns.VectorFrom(px, py, here, tx, ty, instance)
	if not (px and tx) or (here and instance and here ~= instance) then return nil end
	local dx, dy = tx - px, ty - py
	local angle = math.atan2(-dx, dy)
	if angle > 0 then angle = 2 * math.pi - angle else angle = -angle end
	return angle, math.sqrt(dx * dx + dy * dy)
end

-- A place where you already stand (within HERE_REACH yards): never a place to go to (the arrow would say "arrived"
-- at once and the route would end). False when either place is unknown.
local HERE_REACH = 15
function ns.IsHere(map, x, y)
	local tx, ty, instance = ns.WorldOf(map, x, y)
	if not tx then return false end
	local px, py, here = ns.Here()
	if not px or (here and instance and here ~= instance) then return false end
	return math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2) <= HERE_REACH
end

-- What a step goes there for (Wanderer Quests says it): a quest to take, to hand in, an objective of it.
local KINDS = { take = true, handin = true, objective = true }

-- A place as kept: { map, x, y, title }; a step also why (info: { kind, quest, label }), a note its sign.
local function Place(map, x, y, title, info)
	map, x, y = tonumber(map), tonumber(x), tonumber(y)
	if not (map and x and y) then return nil end
	title = type(title) == "string" and title ~= "" and title or U.MapName(map, x, y) or L.UNKNOWN_HERE
	local place = { map = map, x = x, y = y, title = title, time = time() }
	if type(info) == "table" then
		if KINDS[info.kind] then place.kind = info.kind end
		place.quest = tonumber(info.quest)
		if type(info.label) == "string" and info.label ~= "" then place.label = info.label end
		if type(info.icon) == "string" then place.icon = info.icon end
	end
	return place
end

-- A step's sign before its words (the window, the arrow): the game's "!" (to take), "?" (to hand in, an objective).
ns.STEP_SIGNS = { take = "Interface\\GossipFrame\\AvailableQuestIcon", handin = "Interface\\GossipFrame\\ActiveQuestIcon",
	objective = "Interface\\GossipFrame\\ActiveQuestIcon" }

-- A step in words: what to do there and where ("Hand in: The Collector (Marshal Dughan)"), else its name.
function ns.StepWords(step)
	local words = step.kind and step.label and L["STEP_" .. step.kind:upper()]
	if words then return words:format(step.label, step.title) end
	return step.title
end

-- Notes ----------------------------------------------------------------------------------------------------

function ns.Notes() return ns.DB().notes end

-- A note kept: its name, its sign (one of ns.NOTE_ICONS; none: the plain mark). Notes full: refused and said,
-- never an old one thrown away (nil, "full").
function ns.AddNote(map, x, y, title, icon)
	local note = Place(map, x, y, title)
	if not note then return nil end
	if type(icon) == "string" and icon ~= "place" then note.icon = icon end
	local notes = ns.Notes()
	if #notes >= MAX_NOTES then
		W.Print(L.NOTES_FULL_WHY:format(MAX_NOTES))
		return nil, "full"
	end
	notes[#notes + 1] = note
	ns.Changed()
	return note
end

function ns.RemoveNote(note)
	local notes = ns.Notes()
	for index = #notes, 1, -1 do
		if notes[index] == note then table.remove(notes, index) end
	end
	ns.Changed()
end

-- A note used (followed, put on the route, changed): remembered, for the list sorted by last use.
function ns.TouchNote(place)
	for _, note in ipairs(ns.Notes()) do
		if note == place then
			note.used = time()
			return true
		end
	end
	return false
end

-- When a note was last used (never: when it was made).
function ns.NoteUsed(note) return tonumber(note.used) or tonumber(note.time) or 0 end

-- A note not used for long (a month): greyed in the list, never removed by itself.
local OLD_NOTE = 30 * 24 * 3600
function ns.NoteOld(note) return time() - ns.NoteUsed(note) > OLD_NOTE end

-- The notes as the list shows them: in the order kept, or the last used first (db.noteSort "used").
function ns.SortedNotes()
	local list = {}
	for index, note in ipairs(ns.Notes()) do list[index] = note end
	if ns.DB().noteSort == "used" then
		local order = {}
		for index, note in ipairs(list) do order[note] = index end
		table.sort(list, function(a, b)
			local ua, ub = ns.NoteUsed(a), ns.NoteUsed(b)
			if ua ~= ub then return ua > ub end
			return order[a] < order[b]
		end)
	end
	return list
end

-- Notes shown or not (the world map's filter, the minimap following it): all hidden, or some signs.
function ns.NotesHidden() return ns.DB().notesHidden == true end
function ns.SetNotesHidden(hidden)
	ns.DB().notesHidden = hidden and true or nil
	ns.Changed()
end
function ns.SignHidden(key) return ns.DB().hiddenSigns[key or "place"] == true end
function ns.SetSignHidden(key, hidden)
	ns.DB().hiddenSigns[key or "place"] = hidden and true or nil
	ns.Changed()
end
function ns.NoteShown(note) return not ns.NotesHidden() and not ns.SignHidden(note.icon) end

-- The notes counted by sign and by zone: { { key, count } } in the signs' order, { { map, count, name } } by name.
function ns.NoteGroups()
	local bySign, byZone = {}, {}
	for _, note in ipairs(ns.Notes()) do
		local key = note.icon or "place"
		bySign[key] = (bySign[key] or 0) + 1
		byZone[note.map] = (byZone[note.map] or 0) + 1
	end
	local signs, zones = {}, {}
	for _, icon in ipairs(ns.NOTE_ICONS) do
		if bySign[icon.key] then signs[#signs + 1] = { key = icon.key, count = bySign[icon.key] } end
	end
	for map, count in pairs(byZone) do zones[#zones + 1] = { map = map, count = count, name = U.MapName(map) or tostring(map) } end
	table.sort(zones, function(a, b) return a.name < b.name end)
	return signs, zones
end

-- Every note of a sign ("sign", key) or of a zone ("zone", map) removed. How many.
function ns.RemoveNotesOf(kind, value)
	local notes, removed = ns.Notes(), 0
	for index = #notes, 1, -1 do
		local note = notes[index]
		if (kind == "sign" and (note.icon or "place") == value) or (kind == "zone" and note.map == value) then
			table.remove(notes, index)
			removed = removed + 1
		end
	end
	if removed > 0 then ns.Changed() end
	return removed
end

-- The same after Wanderer's question (how many, of what): never without a word.
function ns.RemoveNotesAsked(kind, value, count)
	local what = kind == "sign" and L[ns.NoteIconSpec(value).word] or U.MapName(value) or tostring(value)
	local question = kind == "sign" and L.NOTES_REMOVE_SIGN_ASK or L.NOTES_REMOVE_ZONE_ASK
	return Skin.Ask(question:format(count, what), function()
		W.Print(L.NOTES_REMOVED:format(ns.RemoveNotesOf(kind, value)))
	end)
end

-- The route -------------------------------------------------------------------------------------------------

function ns.Route() return ns.DB().route end

-- The step followed now (nil: none).
function ns.CurrentStep()
	local route = ns.Route()
	return route.steps[route.current]
end

-- The guided route to the step followed: its legs (walk, fly, boat, hearth), planned from where you stand;
-- nil when your feet alone do (the arrow points straight). Kept with the route; the leg followed is route.leg.
function ns.PlanLegs()
	local route = ns.Route()
	local step = ns.CurrentStep()
	local settings = ns.Settings()
	route.legs, route.leg = nil, 1
	if step and settings and settings.gps then
		local wx, wy, instance = ns.WorldOf(step.map, step.x, step.y)
		if wx then
			route.legs = ns.Plan({ wx = wx, wy = wy, instance = instance, map = step.map, x = step.x, y = step.y, title = step.title })
		end
	end
	route.planned = step and (step.map .. ":" .. step.x .. ":" .. step.y) or nil
end

-- The leg followed now (nil: none, the step itself is followed).
function ns.CurrentLeg()
	local route = ns.Route()
	local step = ns.CurrentStep()
	if not step then return nil end
	-- (another step than the one planned for: planned again)
	local key = step.map .. ":" .. step.x .. ":" .. step.y
	if route.planned ~= key then ns.PlanLegs() end
	return route.legs and route.legs[route.leg or 1] or nil
end

-- The leg reached: the next one; the last one reached, the step is.
function ns.NextLeg()
	local route = ns.Route()
	if not route.legs then return ns.NextStep() end
	route.leg = (route.leg or 1) + 1
	if route.leg > #route.legs then return ns.NextStep() end
	ns.Changed()
end

-- The way planned again from where you stand (lost, or the world changed).
function ns.Replan()
	ns.PlanLegs()
	ns.Changed()
end

-- A step more at the end of the route (info: why it goes there, see Place). The route full: refused and said
-- (nil, "full"); a step that would be followed at once where you already stand: refused and said (nil, "here").
function ns.AddStep(map, x, y, title, info)
	local step = Place(map, x, y, title, info)
	if not step then return nil end
	local route = ns.Route()
	if #route.steps >= MAX_STEPS then
		W.Print(L.ROUTE_FULL:format(MAX_STEPS))
		return nil, "full"
	end
	local followedNow = not route.steps[route.current] or route.steps[route.current].done
	if followedNow and ns.IsHere(step.map, step.x, step.y) then
		W.Print(L.ALREADY_HERE:format(step.title))
		return nil, "here"
	end
	route.steps[#route.steps + 1] = step
	if not route.steps[route.current] or route.steps[route.current].done then
		route.current = #route.steps
		ns.PlanLegs()
	end
	ns.Changed()
	return step
end

-- One place to go to: the route is this step alone.
function ns.Go(map, x, y, title, info)
	local step = Place(map, x, y, title, info)
	if not step then return nil end
	local route = ns.Route()
	route.steps, route.current = { step }, 1
	ns.PlanLegs()
	ns.Changed()
	return step
end

-- A place followed ({ map, x, y, title } and why: info, else the place's own kind, quest, label): a route of
-- several steps is not thrown away without a word. The one way in for every click (the window, the cards, the
-- map, the other addons). False when it is no place.
function ns.GoTo(place, info)
	if not (type(place) == "table" and tonumber(place.map) and tonumber(place.x) and tonumber(place.y)) then return false end
	-- (where you already stand: nothing to follow, said)
	if ns.IsHere(tonumber(place.map), tonumber(place.x), tonumber(place.y)) then
		W.Print(L.ALREADY_HERE:format(place.title or U.MapName(place.map) or L.UNKNOWN_HERE))
		return true
	end
	ns.TouchNote(place)
	local steps = #ns.Route().steps
	local function Go() ns.Go(place.map, place.x, place.y, place.title, info or place) end
	if steps > 1 then Skin.Ask(L.ROUTE_REPLACE:format(steps), Go) else Go() end
	return true
end

-- A step followed (one done already: followed again all the same).
function ns.FollowStep(index)
	local route = ns.Route()
	if route.steps[index] then
		route.steps[index].done = nil
		route.current = index
		ns.PlanLegs()
		ns.Changed()
	end
end

-- The first step after this one not done yet (nil: none).
local function NextOpen(route, from)
	for index = from + 1, #route.steps do
		if not route.steps[index].done then return index end
	end
	return nil
end

-- The step reached: the next one not done followed; the last one reached ends the route.
function ns.NextStep()
	local route = ns.Route()
	local nextIndex = NextOpen(route, route.current)
	if nextIndex then
		route.current = nextIndex
	else
		route.steps, route.current = {}, 1
	end
	ns.PlanLegs()
	ns.Changed()
end

-- The next step not done after the one followed (nil: none), for the words "Next: ...".
function ns.NextOpenStep()
	local route = ns.Route()
	local nextIndex = NextOpen(route, route.current)
	return nextIndex and route.steps[nextIndex] or nil
end

-- A quest taken or handed in: its steps for that (kinds: { take = true... }) ticked, quietly; the one followed
-- among them: the next one not done is followed, or the route ends. How many were ticked.
function ns.TickQuest(questID, kinds)
	questID = tonumber(questID)
	if not questID then return 0 end
	local route = ns.Route()
	local ticked = 0
	for _, step in ipairs(route.steps) do
		if step.quest == questID and kinds[step.kind] and not step.done then
			step.done = true
			ticked = ticked + 1
		end
	end
	if ticked == 0 then return 0 end
	local current = route.steps[route.current]
	if current and current.done then
		local nextIndex = NextOpen(route, route.current) or NextOpen(route, 0)
		if nextIndex then route.current = nextIndex else route.steps, route.current = {}, 1 end
		ns.PlanLegs()
	end
	ns.Changed()
	return ticked
end

function ns.MoveStep(index, by)
	local steps = ns.Route().steps
	local other = index + by
	if not (steps[index] and steps[other]) then return end
	steps[index], steps[other] = steps[other], steps[index]
	local route = ns.Route()
	if route.current == index then route.current = other elseif route.current == other then route.current = index end
	ns.PlanLegs()
	ns.Changed()
end

function ns.RemoveStep(index)
	local route = ns.Route()
	if not route.steps[index] then return end
	table.remove(route.steps, index)
	if route.current > index then route.current = route.current - 1 end
	route.current = math.max(1, math.min(route.current, #route.steps))
	if route.steps[1] then ns.PlanLegs() else route.legs, route.leg, route.planned = nil, 1, nil end
	ns.Changed()
end

function ns.ClearRoute()
	local route = ns.Route()
	route.steps, route.current, route.legs, route.leg, route.planned = {}, 1, nil, 1, nil
	ns.Changed()
end

-- The route cleared by a click (the window, the arrow's card): asked first when it has several steps.
function ns.ClearAsked()
	local steps = #ns.Route().steps
	if steps > 1 then Skin.Ask(L.ROUTE_CLEAR_ASK:format(steps), ns.ClearRoute) else ns.ClearRoute() end
end

-- A tour: the places ordered from where you stand, each the nearest from the last, as the route. The count made.
function ns.RouteFrom(places)
	if type(places) ~= "table" then return 0 end
	local steps = #ns.Route().steps
	if steps > 1 and not ns.routeAsked then
		-- (a route of several steps is not thrown away without a word; the tour made once agreed)
		Skin.Ask(L.ROUTE_REPLACE:format(steps), function()
			ns.routeAsked = true
			ns.RouteFrom(places)
			ns.routeAsked = nil
		end)
		return -1
	end
	local left = {}
	for _, place in ipairs(places) do
		local wx, wy, instance = ns.WorldOf(place.map, place.x, place.y)
		if wx then left[#left + 1] = { place = place, wx = wx, wy = wy, instance = instance } end
	end
	if not left[1] then return 0 end
	local route = ns.Route()
	route.steps, route.current, route.legs, route.planned = {}, 1, nil, nil
	local px, py, here = ns.Here()
	local at = px and { wx = px, wy = py, instance = here } or left[1]
	while left[1] and #route.steps < MAX_STEPS do
		local best, bestIndex = math.huge, 1
		for index, entry in ipairs(left) do
			-- (another continent: far; the same: as the crow flies)
			local d = entry.instance == at.instance and math.sqrt((entry.wx - at.wx) ^ 2 + (entry.wy - at.wy) ^ 2) or 1e9
			if d < best then best, bestIndex = d, index end
		end
		local chosen = table.remove(left, bestIndex)
		local step = Place(chosen.place.map, chosen.place.x, chosen.place.y, chosen.place.title, chosen.place)
		if step then route.steps[#route.steps + 1] = step end
		at = chosen
	end
	ns.PlanLegs()
	ns.Changed()
	W.Print(L.ROUTE_MADE:format(#route.steps))
	return #route.steps
end

-- Routes kept -----------------------------------------------------------------------------------------------
-- The route as it is, kept under a name (a round of herbs, of mailboxes...), loaded again later in place of the
-- one followed. Ten at most, for each character.

local MAX_KEPT, NAME_LETTERS = 10, 40
ns.KEPT_LETTERS = NAME_LETTERS

function ns.KeptRoutes() return ns.DB().kept end

-- A step as kept: where and why, never whether it was done.
local function StepCopy(step)
	return { map = step.map, x = step.x, y = step.y, title = step.title, kind = step.kind, quest = step.quest, label = step.label,
		icon = step.icon, time = step.time }
end

-- (cut by letters, as the box counts them: never inside an accented one)
local function Trim(name)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	local letters = 0
	for at in name:gmatch("()[^\128-\191]") do
		letters = letters + 1
		if letters > NAME_LETTERS then return (name:sub(1, at - 1):gsub("%s+$", "")) end
	end
	return name
end

-- The route followed kept under a name (the same name: kept again in its place). The one kept, or nil and why:
-- "empty" (no step), "name" (no name), "full" (said).
function ns.KeepRoute(name)
	local steps = ns.Route().steps
	if not steps[1] then return nil, "empty" end
	name = Trim(name)
	if name == "" then return nil, "name" end
	local kept = ns.KeptRoutes()
	local copy = { name = name, steps = {}, time = time() }
	for index, step in ipairs(steps) do copy.steps[index] = StepCopy(step) end
	for index, other in ipairs(kept) do
		if other.name == name then
			kept[index] = copy
			ns.Changed()
			return copy
		end
	end
	if #kept >= MAX_KEPT then
		W.Print(L.KEPT_FULL:format(MAX_KEPT))
		return nil, "full"
	end
	kept[#kept + 1] = copy
	ns.Changed()
	return copy
end

-- A kept route followed in place of the route (its first step followed). False when there is none.
function ns.LoadKept(index)
	local kept = ns.KeptRoutes()[index]
	if not (kept and type(kept.steps) == "table" and kept.steps[1]) then return false end
	local route = ns.Route()
	route.steps, route.current, route.legs, route.leg, route.planned = {}, 1, nil, 1, nil
	for at, step in ipairs(kept.steps) do route.steps[at] = StepCopy(step) end
	ns.PlanLegs()
	ns.Changed()
	W.Print(L.KEPT_LOADED:format(kept.name, #route.steps))
	return true
end

-- The same from a click: a route followed now is let go only once agreed.
function ns.LoadKeptAsked(index)
	local kept = ns.KeptRoutes()[index]
	if not kept then return false end
	local steps = #ns.Route().steps
	if steps > 0 then
		Skin.Ask(L.KEPT_LOAD_ASK:format(kept.name, steps), function() ns.LoadKept(index) end)
		return true
	end
	return ns.LoadKept(index)
end

-- A kept route named again (an empty name or one already taken: left as it was, said). True when renamed.
function ns.RenameKept(index, name)
	local kept = ns.KeptRoutes()
	name = Trim(name)
	if not kept[index] or name == "" then return false end
	for at, other in ipairs(kept) do
		if at ~= index and other.name == name then
			W.Print(L.KEPT_NAME_TAKEN:format(name))
			return false
		end
	end
	kept[index].name = name
	ns.Changed()
	return true
end

function ns.RemoveKept(index)
	local kept = ns.KeptRoutes()
	if not kept[index] then return false end
	table.remove(kept, index)
	ns.Changed()
	return true
end

-- What changed: the map's pins, the arrow and the window drawn again. (made with the first listener, never at
-- loading: an older Wanderer has no signals, and then nothing listens)
local changed
function ns.OnChanged(fn)
	changed = changed or U.Signal()
	changed.On(fn)
end
function ns.Changed(...)
	-- (a count of changes: what is worked out from the route is kept until the next one)
	ns.version = (ns.version or 0) + 1
	if changed then changed.Fire(...) end
end
