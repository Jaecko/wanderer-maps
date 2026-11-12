local _, ns = ...
local L = ns.L

-- What the atlas shows: your quests and their objectives first, your route, your notes, the world's places; the
-- detail follows the zoom. The panel at its side reads one place at a time; on the left, one search and what is
-- shown; below, the route. Canvas and window: Atlas.lua.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
-- (the family's gold: its accents)
local GOLD = Skin and Skin.COLORS.gold
-- (a controller in hand: the tips say its buttons, not the mouse's)
local function UsingPad() return U.UsingPad and U.UsingPad() or false end
local Safe, Clean = U and U.Safe, U and U.Clean

local PIN = 22
local NEAR, CLOSE = 1.6, 2.5 -- the zooms where the small places, then their names, come
local MAX_RESULTS, MAX_QUEST_ROWS, MAX_STEPS = 7, 11, 9
local SEARCH_WIDTH, LEGEND_HEIGHT, LEGEND_GAP = 250, 26, 14
local TABS_HEIGHT = 34
-- (the kit's row heights and tints when this Wanderer has them; read raw: an older one simply has none)
local KIT_ROW = Skin and rawget(Skin, "ROW")
local JOURNAL_ROW = KIT_ROW and KIT_ROW.compact or 24
local QUEST_ROW = KIT_ROW and KIT_ROW.normal or 34 -- (a quest of the panel: its step)
local HOVER, CHOSEN = Skin and rawget(Skin, "HOVER") or 0.05, Skin and rawget(Skin, "CHOSEN") or 0.1
local MAX_REWARDS, REWARD_SIZE = 7, 28
local QUEST_TEXT_LINES = 9
local HEADER_LEFT = 118 -- (the map's name, after the window's title)
local DOT_GAP = 12
local GRID_WIDE = 333 -- the zones' grid: cells across a map
local ZONE_REACH, ZONE_LEVEL = 16, 0.31 -- how far a pack of creatures counts (cells), the height where a zone stops
local ZONE_COLOR = { 0.25, 0.55, 1 } -- the blue of the game's own quest areas
local ZONE_FILL, ZONE_FILL_CHOSEN = 0.2, 0.36 -- the blue inside the zones
-- A creature's habitat (Wanderer Bestiary): the same soft zones, in the red of enemies, a clear red edge.
local HABITAT_COLOR, HABITAT_EDGE = { 0.86, 0.24, 0.2 }, { 1, 0.5, 0.42 }
local HABITAT_FILL = 0.24
local LINE_STEP = 3 -- the outlines: cells between two points
local LINE_WIDTH, LINE_WIDTH_CHOSEN = 1.2, 2.2 -- pixels on the screen
local LINE_ALPHA, LINE_ALPHA_OTHER = 0.85, 0.35 -- (one quest chosen: the outlines of the others step back)
-- A square's corners inside a zone (1 top left, 2 top right, 4 bottom right, 8 bottom left) -> the sides its outline joins.
local CONTOURS = { { "LT" }, { "TR" }, { "LR" }, { "RB" }, { "LT", "RB" }, { "TB" }, { "LB" }, { "LB" }, { "TB" }, { "TR", "LB" }, { "RB" }, { "LR" }, { "TR" }, { "LT" } }
local COMPLETE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
local OBJECTIVE_ICON = "Interface\\GossipFrame\\IncompleteQuestIcon"
local GIVER_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local DOOR_ICON, RAID_ICON = "Interface\\Icons\\INV_Misc_Key_13", "Interface\\Icons\\INV_Misc_Head_Dragon_01"
local BOAT_ICON = "Interface\\Icons\\INV_Misc_Anchor"
local POI_ICON = "Interface\\Minimap\\POIIcons"
local ARROW_ICON = "Interface\\Minimap\\MinimapArrow"
local YOU_SIZE, YOU_RING, YOU_RING_STEPS = 30, 19, 28

-- What can be shown, in the panel's order: { key, word, icon, on by itself }.
local LAYERS = {
	{ "quests", "ATLAS_QUESTS", OBJECTIVE_ICON, true },
	{ "givers", "ATLAS_GIVERS", GIVER_ICON, false },
	{ "route", "ATLAS_ROUTE", "Interface\\Icons\\INV_Misc_Map_01", true },
	{ "notes", "ATLAS_NOTES", "Interface\\Icons\\INV_Misc_Note_01", true },
	{ "travel", "ATLAS_TRAVEL", "Interface\\Minimap\\Tracking\\FlightMaster", true },
	{ "doors", "ATLAS_DOORS", DOOR_ICON, true },
	{ "services", "ATLAS_SERVICES", "Interface\\Minimap\\Tracking\\Innkeeper", true },
	{ "poi", "ATLAS_POI", "Interface\\Icons\\INV_Misc_Flag_01", true },
}

local ui
local DrawJournal, QuestText, DrawRewards, Pushable
local pins, chosen, query = {}, nil, ""
local index -- the search's places
local arc = {} -- the line shown while a dock is under the mouse
local zones -- where your quests' objectives lie: { wide, tall, cells = { cell -> { quest = true } }, quests = { quest -> { title, words } } }
local hoveredZone -- the quests of the zone under the mouse
local panelView = "map" -- what the panel shows when nothing is chosen: "map" (this map) or "journal" (all your quests)
local journalOffset = 0

local function Shown(key)
	local db = ns.AtlasDb()
	db.layers = type(db.layers) == "table" and db.layers or {}
	if db.layers[key] ~= nil then return db.layers[key] end
	for _, layer in ipairs(LAYERS) do
		if layer[1] == key then return layer[4] end
	end
	return false
end

local function InBounds(x, y) return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 end

local function OnThisMap(place, map)
	local x, y = ns.OnMap(place, map)
	if InBounds(x, y) then return x, y end
end

local function Far(map) return ns.FarMap(map) end

local function QuestTitle(id)
	local api = C_QuestLog and C_QuestLog.GetTitleForQuestID
	return api and Clean(Safe(api, id)) or nil
end

-- (the game names a quest long after it left your log: your log says)
local function QuestInLog(id)
	local api = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
	if not api then return QuestTitle(id) ~= nil end
	return Clean(Safe(api, id)) ~= nil
end

local function QuestDone(id)
	local api = C_QuestLog and C_QuestLog.IsComplete
	return api and Clean(Safe(api, id)) and true or false
end

local function Objectives(id)
	local api = C_QuestLog and C_QuestLog.GetQuestObjectives
	local list = api and Safe(api, id)
	local out = {}
	for _, item in ipairs(type(list) == "table" and list or {}) do
		local text = Clean(item.text)
		if text and text ~= "" then out[#out + 1] = { text = text, done = Clean(item.finished) and true or false } end
	end
	return out
end

-- Your quests on a map: { id, title, x, y, done }.
local function QuestsOn(map)
	local api = C_QuestLog and C_QuestLog.GetQuestsOnMap
	local list = api and Safe(api, map)
	local out = {}
	for _, item in ipairs(type(list) == "table" and list or {}) do
		local id, x, y = Clean(item.questID), Clean(item.x), Clean(item.y)
		local title = id and QuestTitle(id)
		if title and InBounds(x, y) then out[#out + 1] = { id = id, title = title, x = x, y = y, done = QuestDone(id) } end
	end
	return out
end

-- What goes on this map --------------------------------------------------------------------------------------

local function Add(list, data) list[#list + 1] = data end

-- A creature's habitat (Wanderer Bestiary): { id, title, list = { { map, points } } }, drawn as soft dots on its
-- maps until the atlas closes or another one is asked for.
local habitat

function ns.AtlasHabitat(id, title, list)
	habitat = id and { id = id, title = title, list = list or {} } or nil
	if ui then
		ns.AtlasRefresh()
	end
end

-- Its points on this map, as the marks the zones are made of (nil: none here, the map as usual).
local function HabitatMarks(map)
	if not habitat then return nil end
	local marks
	for _, part in ipairs(habitat.list) do
		if part.map == map then
			for _, point in ipairs(part.points) do
				marks = marks or {}
				marks[#marks + 1] = { kind = "habitat", quest = "habitat", title = habitat.title, x = point[1], y = point[2] }
			end
		end
	end
	return marks
end

-- Its habitat on the map shown: then the map is given to it alone (your choice of layers comes back with it gone).
local function HabitatHere()
	local map = ns.AtlasMap()
	return map ~= nil and HabitatMarks(map) ~= nil
end
ns.AtlasHabitatHere = HabitatHere

-- The creatures your quests ask for on this map (their ids, a few): their cards in Wanderer Bestiary.
local HUNTED_MOST = 4
local hunted = {}
local function Bestiary()
	local found = _G.WandererBestiary
	return type(found) == "table" and found.Show and found or nil
end

-- Your quests: where the creatures and objects they ask for stand, who takes them back; a quest the data does not
-- know, or where the data has nothing on this map, keeps the one mark the game gives it. Never an empty map.
local function AddQuests(list, map)
	if not Shown("quests") then return end
	local quests = _G.WandererQuests
	local marks = type(quests) == "table" and quests.Objectives and quests.Objectives(map) or {}
	local marked, seen = {}, {}
	wipe(hunted)
	local huntedSeen = {}
	for _, mark in ipairs(marks) do
		if mark.unit and not huntedSeen[mark.unit] and #hunted < HUNTED_MOST then
			huntedSeen[mark.unit] = true
			hunted[#hunted + 1] = mark.unit
		end
	end
	for _, mark in ipairs(marks) do
		marked[mark.quest] = marked[mark.quest] or mark
		-- (who takes it back is one person: a mark; what it asks for is a zone)
		if mark.kind == "turnin" then
			Add(list, { kind = "objective", quest = mark.quest, x = mark.x, y = mark.y, title = mark.title, file = COMPLETE_ICON, level = 35,
				tip = { mark.name or mark.title, { mark.title, GOLD[1], GOLD[2], GOLD[3] }, ns.TipLine(L.ATLAS_QUEST_DONE, "blue") } })
		end
	end
	ns.AtlasReadZones(marks)
	for _, quest in ipairs(QuestsOn(map)) do
		seen[quest.id] = true
		-- (a quest with marks: its line in the panel only)
		Add(list, { kind = "quest", quest = quest.id, x = quest.x, y = quest.y, title = quest.title, done = quest.done, hidden = marked[quest.id] ~= nil,
			file = quest.done and COMPLETE_ICON or OBJECTIVE_ICON, level = 40, tip = { quest.title, ns.TipLine(quest.done and L.ATLAS_QUEST_DONE or L.ATLAS_QUEST_OPEN, "blue") } })
	end
	-- (one the game does not place here but the data does: its line in the panel too)
	for id, mark in pairs(marked) do
		if not seen[id] then
			Add(list, { kind = "quest", quest = id, x = mark.x, y = mark.y, title = mark.title, done = QuestDone(id), hidden = true, file = QuestDone(id) and COMPLETE_ICON or OBJECTIVE_ICON, level = 40 })
		end
	end
end

local function AddGivers(list, map)
	local quests = _G.WandererQuests
	if not (Shown("givers") and type(quests) == "table" and quests.Givers) or Far(map) then return end
	for _, giver in ipairs(quests.Givers(map) or {}) do
		Add(list, { kind = "giver", x = giver.x, y = giver.y, title = giver.name, file = GIVER_ICON, level = 30, quest = giver.quest, lines = giver.titles,
			tip = { giver.name, ns.TipLine(L.ATLAS_GIVER_TIP:format(giver.count or 1), "blue") } })
	end
end

local function AddRoute(list, map)
	if not Shown("route") then return end
	local route = ns.Route()
	for number, step in ipairs(route.steps) do
		local x, y = OnThisMap(step, map)
		if x then
			Add(list, { kind = "step", index = number, place = step, x = x, y = y, title = step.title, step = true, current = number == route.current,
				faded = step.done, level = 60, tip = { step.title, ns.TipLine(UsingPad() and L.ATLAS_STEP_PIN_TIP_PAD or L.ATLAS_STEP_TIP, "blue") } })
		end
	end
end

local function AddNotes(list, map)
	if not Shown("notes") then return end
	for _, note in ipairs(ns.NotePins(map)) do
		if note.kind == "group" then
			Add(list, { kind = "group", zone = note.zone, x = note.x, y = note.y, title = L.ATLAS_NOTES_HERE:format(note.count), count = note.count, level = 25,
				file = "Interface\\Icons\\INV_Misc_Note_01", tip = { L.ATLAS_NOTES_HERE:format(note.count), ns.TipLine(L.ATLAS_OPEN_ZONE, "blue") } })
		else
			Add(list, { kind = "note", place = note.place, x = note.x, y = note.y, title = note.place.title, note = note.place, level = 50, tip = { note.place.title } })
		end
	end
end

local function AddTravel(list, map)
	if not Shown("travel") then return end
	local known = {}
	for _, node in ipairs(ns.KnownTaxi()) do known[node.id] = true end
	for _, master in ipairs(ns.Services("flight")) do
		local x, y = OnThisMap(master, map)
		if x then
			local learned = known[master.id] and true or false
			Add(list, { kind = "flight", place = master, x = x, y = y, title = master.title, service = "flight", faded = not learned, known = learned, level = 20,
				tip = { master.title, ns.TipLine(learned and L.ATLAS_FLIGHT_KNOWN or L.ATLAS_FLIGHT_UNKNOWN, learned and "good" or "muted") } })
		end
	end
	if Far(map) then return end
	for _, crossing in ipairs(ns.Crossings()) do
		local x, y = OnThisMap(crossing.from, map)
		if x then
			local dx, dy = ns.OnMap(crossing.to, map)
			Add(list, { kind = "dock", place = crossing.from, x = x, y = y, toX = dx, toY = dy, title = crossing.from.name, file = BOAT_ICON, to = crossing.to, level = 15,
				tip = { crossing.from.name, ns.TipLine(L.ATLAS_DOCK_TO:format(crossing.to.name or "?"), "blue") } })
		end
	end
end

local function AddDoors(list, map)
	local quests = _G.WandererQuests
	if not (Shown("doors") and type(quests) == "table" and quests.Entrances) then return end
	for _, door in ipairs(quests.Entrances() or {}) do
		local x, y = OnThisMap(door, map)
		if x then
			Add(list, { kind = "door", place = door, x = x, y = y, title = door.name, file = door.raid and RAID_ICON or DOOR_ICON, raid = door.raid, level = 20, round = true,
				tip = { door.name, ns.TipLine(door.raid and L.ATLAS_RAID or L.ATLAS_DUNGEON, "muted") } })
		end
	end
end

local function AddServices(list, map)
	if not Shown("services") or Far(map) then return end
	for _, kind in ipairs(ns.SERVICE_ORDER) do
		if kind ~= "flight" then
			for _, place in ipairs(ns.Services(kind)) do
				local x, y = OnThisMap(place, map)
				if x then Add(list, { kind = "service", place = place, x = x, y = y, title = place.title, service = kind, least = NEAR, level = 10, tip = { place.title } }) end
			end
		end
	end
end

local function AddPoi(list, map)
	local api = C_AreaPoiInfo
	if not (Shown("poi") and api and api.GetAreaPOIForMap and api.GetAreaPOIInfo) then return end
	local ids = Safe(api.GetAreaPOIForMap, map)
	for _, id in ipairs(type(ids) == "table" and ids or {}) do
		local info = Safe(api.GetAreaPOIInfo, map, Clean(id))
		local position = type(info) == "table" and info.position
		local name = position and Clean(info.name)
		local x, y = position and Clean(position.x), position and Clean(position.y)
		if name and InBounds(x, y) then
			Add(list, { kind = "poi", place = { map = map, x = x, y = y, title = name }, x = x, y = y, title = name, atlas = Clean(info.atlasName), textureIndex = Clean(info.textureIndex), level = 12,
				about = Clean(info.description), tip = { name, Clean(info.description) } })
		end
	end
end

local function Collect(map)
	local list = {}
	zones = nil
	-- (a creature's habitat here: its zones alone, in red)
	local marks = HabitatMarks(map)
	if marks then
		ns.AtlasReadZones(marks)
		if zones then zones.habitat = true end
		return list
	end
	AddPoi(list, map)
	AddServices(list, map)
	AddDoors(list, map)
	AddTravel(list, map)
	AddGivers(list, map)
	AddNotes(list, map)
	AddQuests(list, map)
	AddRoute(list, map)
	return list
end

-- The pins ---------------------------------------------------------------------------------------------------------

-- The quest you follow now: the one pinned in front of Wanderer Quests' list, else the game's own focus.
local function PinnedQuest()
	local quests = _G.WandererQuests
	local id = type(quests) == "table" and quests.InFront and quests.InFront()
	if not id and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then id = Clean(Safe(C_SuperTrack.GetSuperTrackedQuestID)) end
	return type(id) == "number" and id > 0 and id or nil
end

-- The quest you follow stays chosen on its map whenever nothing else is: it stands out among the rest, and follows
-- when you pin another one. Your own choice on the map comes first; let go by you (the panel's cross, a tab, a
-- click beside), nothing comes back until the atlas opens again or shows another map.
local letGo = false -- you let the choice go
local autoChosen = false -- the choice made here is the quest you follow, not yours
function ns.AtlasOfferPinned() letGo = false end

-- The quest you follow chosen (or followed when you pin another one): true when the choice changed.
local function KeepPinned()
	if letGo or (chosen and not autoChosen) then return false end
	local id = PinnedQuest()
	if chosen and chosen.quest == id then return false end
	local found
	if id then
		for _, data in ipairs(pins) do
			if data.kind == "quest" and data.quest == id then found = data end
		end
	end
	if found == chosen then return false end
	chosen, autoChosen = found, found ~= nil
	return true
end

-- A quest chosen on the map is the one you follow: in front of Wanderer Quests' list, else the game's own focus.
local function FollowQuest(id)
	local quests = _G.WandererQuests
	if type(quests) == "table" and quests.Front then return quests.Front(id) end
	if C_SuperTrack then Safe(C_SuperTrack.SetSuperTrackedQuestID, id) end
end

-- A quest chosen by you (not the one kept chosen for you): its sheet, Wanderer Quests', opens beside the atlas.
local sheetAsked, onSheet = false, nil
local function Quests() local quests = _G.WandererQuests return type(quests) == "table" and quests or nil end
local function HideSheet()
	if not onSheet then return end
	onSheet = nil
	local quests = Quests()
	if quests and quests.HideSheet then quests.HideSheet(ns.AtlasFrame()) end
end
ns.AtlasHideSheet = HideSheet

local function ChoosePlace(data)
	chosen, autoChosen = data, false
	sheetAsked = data.kind == "quest"
	Skin.Play("click")
	if data.kind == "quest" then FollowQuest(data.quest) end
	ns.AtlasDrawPanel()
	ns.AtlasDrawZones()
	ns.AtlasDrawPins()
end

-- A mark of a quest chooses the quest.
local function QuestOf(data)
	for _, other in ipairs(pins) do
		if other.kind == "quest" and other.quest == data.quest then return other end
	end
end

local function PinClick(self, button)
	local data = self.data
	if not data then return end
	-- (a right click goes back to the map around, as on the game's map; your own steps and notes keep their card)
	if button == "RightButton" and data.kind ~= "step" and data.kind ~= "note" then return ns.AtlasUp() end
	if data.kind == "objective" then
		local quest = QuestOf(data)
		if quest then ChoosePlace(quest) end
		return
	end
	if data.kind == "group" then return ns.AtlasSetMap(data.zone) end
	if button == "RightButton" then return ns.AtlasPlaceCard(data, self) end
	if IsShiftKeyDown() and data.place then return ns.ChatLink(data.place.map, data.place.x, data.place.y, data.title) end
	if IsControlKeyDown() and data.place then return ns.AddStep(data.place.map, data.place.x, data.place.y, data.title) end
	ChoosePlace(data)
end

local function DrawArc(data)
	for _, dot in ipairs(arc) do dot:Hide() end
	if not (data and data.toX and InBounds(data.toX, data.toY)) then return end
	local ax, ay = ns.AtlasProject(data.x, data.y)
	local bx, by = ns.AtlasProject(data.toX, data.toY)
	local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
	local count = math.min(60, math.floor(length / DOT_GAP))
	for at = 1, count do
		local share = at / (count + 1)
		local dot = arc[at]
		if not dot then
			dot = ui.overlay:CreateTexture(nil, "ARTWORK")
			dot:SetColorTexture(Skin.COLORS.blue[1], Skin.COLORS.blue[2], Skin.COLORS.blue[3], 0.9)
			dot:SetSize(3, 3)
			arc[at] = dot
		end
		-- (a bow, not a straight stroke: it goes over the water)
		local bow = math.sin(share * math.pi) * length * 0.14
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", ui.overlay, "TOPLEFT", ax + (bx - ax) * share, -(ay + (by - ay) * share - bow))
		dot:Show()
	end
end

-- The place chosen: a thin gold ring over a dark hairline, as the ring around you (read on light and dark parts of
-- a map alike, quiet as the rest of the atlas). One for the map, set on the chosen pin.
local RING_RADIUS, RING_STEPS = PIN / 2 + 6, 28
local ringOn -- the pin it circles, found while the pins are drawn
local function ChosenRing()
	if not ui.chosenRing then
		local ring = CreateFrame("Frame", nil, ui.overlay)
		ring:SetSize(1, 1)
		for _, stroke in ipairs({ { 2.6, 0, 0, 0, 0.5, 1 }, { 1.2, GOLD[1], GOLD[2], GOLD[3], 1, 2 } }) do
			for at = 1, RING_STEPS do
				local from, to = (at - 1) / RING_STEPS * 2 * math.pi, at / RING_STEPS * 2 * math.pi
				local line = ring:CreateLine(nil, "ARTWORK", nil, stroke[6])
				line:SetThickness(stroke[1])
				line:SetColorTexture(stroke[2], stroke[3], stroke[4], stroke[5])
				line:SetStartPoint("CENTER", ring, math.cos(from) * RING_RADIUS, math.sin(from) * RING_RADIUS)
				line:SetEndPoint("CENTER", ring, math.cos(to) * RING_RADIUS, math.sin(to) * RING_RADIUS)
			end
		end
		ui.chosenRing = ring
	end
	local ring = ui.chosenRing
	if ringOn then
		ring:ClearAllPoints()
		ring:SetPoint("CENTER", ringOn, "CENTER")
		ring:SetFrameLevel(ringOn:GetFrameLevel() + 1)
		ring:Show()
	else
		ring:Hide()
	end
end

local function NewPin()
	local pin = CreateFrame("Button", nil, ui.overlay)
	pin:SetSize(PIN, PIN)
	pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetAllPoints()
	pin.number = Skin.Text(pin, "GameFontNormalSmall", "text")
	pin.number:SetPoint("CENTER", 0, 3)
	pin.label = Skin.Text(pin, "GameTooltipTextSmall", "text")
	pin.label:SetPoint("LEFT", pin, "RIGHT", 2, 0)
	-- (a soft glow behind the place chosen; its thin gold ring is drawn once for the whole map: ChosenRing)
	pin.halo = pin:CreateTexture(nil, "BORDER")
	pin.halo:SetPoint("CENTER")
	pin.halo:SetSize(PIN + 12, PIN + 12)
	pin.halo:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22)
	Skin.RoundMask(pin, pin.halo)
	pin:SetScript("OnClick", PinClick)
	pin:SetScript("OnEnter", function(self)
		local data = self.data
		if data and data.tip then ns.ShowTip(self, data.tip, "ANCHOR_RIGHT") end
		DrawArc(data)
	end)
	pin:SetScript("OnLeave", function()
		GameTooltip:Hide()
		DrawArc(nil)
	end)
	return pin
end

local function Dress(pin, data)
	local icon = pin.icon

	icon:SetTexCoord(0, 1, 0, 1)
	icon:SetDesaturated(false)
	icon:SetVertexColor(1, 1, 1, 1)
	if data.step then
		icon.wandererGold = nil
		ns.StepIcon(icon, data.current)
	elseif data.note then
		ns.NoteIcon(icon, data.note.icon)
	elseif data.service then
		ns.ServiceIcon(icon, data.service)
	elseif data.atlas and U.HasAtlas(data.atlas) then
		icon:SetAtlas(data.atlas)
	elseif data.textureIndex and data.kind == "poi" and GetPOITextureCoords then
		icon:SetTexture(POI_ICON)
		icon:SetTexCoord(GetPOITextureCoords(data.textureIndex))
	else
		icon:SetTexture(data.file or POI_ICON)
		if data.file and data.file:find("Icons\\") then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	end
	if data.faded then icon:SetDesaturated(true) end
	-- (one quest chosen: its marks stand out, the others step back)
	local other = data.kind == "objective" and chosen ~= nil and chosen.quest ~= nil and chosen.quest ~= data.quest
	pin:SetAlpha(data.faded and 0.65 or other and 0.35 or 1)
	pin.number:SetText(data.step and data.index or data.count or "")
	local isChosen = chosen ~= nil and chosen.kind == data.kind and chosen.title == data.title
	pin.halo:SetShown(isChosen)
	if isChosen then ringOn = pin end
end

local function Wanted(data, zoom)
	if data.hidden then return false end
	if data.least and zoom < data.least then return false end
	return true
end

-- Where you stand on the map shown (kept by ns.AtlasFollow), the route's line starts there.
local youAt

-- The routes's dots: from you to your next step when you are on this map, then between the steps of this map.
local function DrawRouteDots()
	ui.dots = ui.dots or {}
	local used = 0
	local map = ns.AtlasMap()
	local route = ns.Route()
	-- (a creature's habitat shown: the map is its alone)
	if HabitatHere() then map = nil end
	local last = youAt and { ns.AtlasProject(youAt[1], youAt[2]) } or nil
	if map and Shown("route") then
		for number, step in ipairs(route.steps) do
			local open = number >= route.current and not step.done
			local x, y
			if open then x, y = OnThisMap(step, map) end
			if open and not x then
				-- (a step on another map: the line stops there)
				last = nil
			elseif open then
				local px, py = ns.AtlasProject(x, y)
				if last then
					local length = math.sqrt((px - last[1]) ^ 2 + (py - last[2]) ^ 2)
					local count = math.min(90, math.floor(length / DOT_GAP))
					for at = 1, count do
						used = used + 1
						local dot = ui.dots[used]
						if not dot then
							dot = ui.overlay:CreateTexture(nil, "ARTWORK")
							dot:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
							dot:SetSize(4, 4)
							ui.dots[used] = dot
						end
						local share = at / (count + 1)
						dot:ClearAllPoints()
						dot:SetPoint("CENTER", ui.overlay, "TOPLEFT", last[1] + (px - last[1]) * share, -(last[2] + (py - last[2]) * share))
						dot:Show()
					end
				end
				last = { px, py }
			end
		end
	end
	for at = used + 1, #ui.dots do ui.dots[at]:Hide() end
end

-- Every pin where the canvas says (a pan or a zoom: nothing is read again).
function ns.AtlasPlacePins()
	if not ui then return end
	local zoom = ns.AtlasZoom()
	for _, pin in ipairs(ui.pins) do
		if pin.data and pin:IsShown() then
			local x, y = ns.AtlasProject(pin.data.x, pin.data.y)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", ui.overlay, "TOPLEFT", x, -y)
			pin.label:SetShown(zoom >= CLOSE and not pin.data.step and pin.data.kind ~= "group" and pin.data.kind ~= "objective")
		end
	end
	DrawRouteDots()
	ns.AtlasPlaceZones()
	ns.AtlasMoveMarks()
end

-- The pins of this map, drawn again.
function ns.AtlasDrawPins()
	if not ui then return end
	if KeepPinned() then
		ns.AtlasDrawPanel()
		ns.AtlasDrawZones()
	end
	ringOn = nil
	local map = ns.AtlasMap()
	local zoom = ns.AtlasZoom()
	local list = pins
	table.sort(list, function(a, b) return a.level < b.level end)
	local used = 0
	for _, data in ipairs(list) do
		if Wanted(data, zoom) then
			used = used + 1
			local pin = ui.pins[used]
			if not pin then
				pin = NewPin()
				ui.pins[used] = pin
			end
			pin.data = data
			pin:SetFrameLevel(ui.overlay:GetFrameLevel() + 2 + data.level)
			Dress(pin, data)
			pin.label:SetText(data.title or "")
			pin:Show()
		end
	end
	ChosenRing()
	for at = used + 1, #ui.pins do
		ui.pins[at]:Hide()
		ui.pins[at].data = nil
	end
	if map then ns.AtlasPlacePins() end
end

local function ReadPins()
	local map = ns.AtlasMap()
	pins = map and Collect(map) or {}
end

-- The zones' names on a continent --------------------------------------------------------------------------------

local function ZoneLabels(map)
	ui.zones = ui.zones or {}
	local used = 0
	local info = Enum and Enum.UIMapType and Safe(C_Map.GetMapChildrenInfo, map, Enum.UIMapType.Zone)
	for _, child in ipairs(type(info) == "table" and info or {}) do
		local id, name = Clean(child.mapID), Clean(child.name)
		local x0, x1, y0, y1 = Safe(C_Map.GetMapRectOnMap, id, map)
		x0, x1, y0, y1 = Clean(x0), Clean(x1), Clean(y0), Clean(y1)
		if id and name and x0 and x1 and y0 and y1 then
			used = used + 1
			local label = ui.zones[used]
			if not label then
				label = Skin.Text(ui.overlay, "GameFontHighlight", "text")
				ui.zones[used] = label
			end
			label.x, label.y = (x0 + x1) / 2, (y0 + y1) / 2
			label:SetText(name)
			label:Show()
		end
	end
	for at = used + 1, #ui.zones do
		ui.zones[at]:Hide()
		ui.zones[at].x = nil
	end
end

function ns.AtlasPlaceZones()
	for _, label in ipairs(ui.zones or {}) do
		if label.x then
			local x, y = ns.AtlasProject(label.x, label.y)
			label:ClearAllPoints()
			label:SetPoint("CENTER", ui.overlay, "TOPLEFT", x, -y)
		end
	end
end

-- Where your quests' objectives lie: zones around the packs of what they ask for ---------------------------------
-- The blue is one even color, in strips of a fine grid side by side; over it each quest has its own thin outline,
-- so each zone reads apart from the others, even where they overlap.

-- Each pack raises a soft hill; hills close together melt into one; a zone is what stands above a level. The outline
-- follows that level between the grid's points, so it is a curve and not a staircase.
local lastZones -- (nothing is worked out again while your quests have not moved)

function ns.AtlasReadZones(marks)
	local mapWide, mapTall = ns.AtlasMapSize()
	if not mapWide then return end
	local words = { mapWide, mapTall }
	for _, mark in ipairs(marks) do
		if mark.kind ~= "turnin" then words[#words + 1] = mark.quest .. "," .. mark.x .. "," .. mark.y .. "," .. tostring(mark.words) end
	end
	local signature = table.concat(words, ";")
	if lastZones and lastZones.signature == signature then
		zones = lastZones
		return
	end
	local wide, tall = GRID_WIDE, math.max(1, math.floor(GRID_WIDE * mapTall / mapWide + 0.5))
	local cells, quests, fields = {}, {}, {}
	local reachSquared = ZONE_REACH * ZONE_REACH
	for _, mark in ipairs(marks) do
		if mark.kind ~= "turnin" then
			local info = quests[mark.quest] or { title = mark.title, words = {}, said = {} }
			quests[mark.quest] = info
			local word = mark.words or mark.name
			if word and not info.said[word] and #info.words < 3 then
				info.said[word] = true
				info.words[#info.words + 1] = word
			end
			local field = fields[mark.quest] or {}
			fields[mark.quest] = field
			local px, py = mark.x * wide, mark.y * tall
			for y = math.max(0, math.floor(py - ZONE_REACH)), math.min(tall - 1, math.ceil(py + ZONE_REACH)) do
				for x = math.max(0, math.floor(px - ZONE_REACH)), math.min(wide - 1, math.ceil(px + ZONE_REACH)) do
					local squared = (x - px) ^ 2 + (y - py) ^ 2
					if squared < reachSquared then
						local key = y * wide + x
						local rise = 1 - squared / reachSquared
						field[key] = (field[key] or 0) + rise * rise
					end
				end
			end
		end
	end
	for quest, field in pairs(fields) do
		for key, height in pairs(field) do
			if height >= ZONE_LEVEL then
				local owners = cells[key] or {}
				cells[key] = owners
				owners[quest] = true
			end
		end
	end
	if next(quests) then
		zones = { wide = wide, tall = tall, cells = cells, quests = quests, fields = fields, signature = signature }
		lastZones = zones
	end
end

local function ZoneOwners(x, y)
	return zones and zones.cells[math.floor(y * zones.tall) * zones.wide + math.floor(x * zones.wide)] or nil
end

local function DrawFill(picked)
	ui.zonePool:ReleaseAll()
	local mapWide, mapTall = ns.AtlasMapSize()
	local cellWide, cellTall = mapWide / zones.wide, mapTall / zones.tall
	local cells, wide = zones.cells, zones.wide
	for y = 0, zones.tall - 1 do
		local runState, runFrom = 0, 0
		for x = 0, wide do
			local owners = x < wide and cells[y * wide + x]
			local state = owners and (picked and owners[picked] and 2 or 1) or 0
			if state ~= runState then
				if runState > 0 then
					local strip = ui.zonePool:Acquire()
					if zones.habitat then
						strip:SetColorTexture(HABITAT_COLOR[1], HABITAT_COLOR[2], HABITAT_COLOR[3], HABITAT_FILL)
					else
						strip:SetColorTexture(ZONE_COLOR[1], ZONE_COLOR[2], ZONE_COLOR[3], runState == 2 and ZONE_FILL_CHOSEN or ZONE_FILL)
					end
					if strip.SetSnapToPixelGrid then
						strip:SetSnapToPixelGrid(false)
						strip:SetTexelSnappingBias(0)
					end
					strip:ClearAllPoints()
					strip:SetSize((x - runFrom) * cellWide, cellTall)
					strip:SetPoint("TOPLEFT", ui.world, "TOPLEFT", runFrom * cellWide, -y * cellTall)
					strip:Show()
				end
				runState, runFrom = state, x
			end
		end
	end
end

-- One outline, one quest: where its zone stops, wherever the others stand.
local function DrawOutline(quest, used, picked)
	local mapWide, mapTall = ns.AtlasMapSize()
	local cellWide, cellTall = mapWide / zones.wide, mapTall / zones.tall
	local field, wide, tall = zones.fields[quest], zones.wide, zones.tall
	local function Height(x, y)
		if x < 0 or y < 0 or x >= wide or y >= tall then return 0 end
		return field[y * wide + x] or 0
	end
	-- (where the level is crossed between two heights: 0 to 1)
	local function Cross(from, to) return (ZONE_LEVEL - from) / (to - from) end
	local isChosen = picked == quest
	local thickness = (isChosen and LINE_WIDTH_CHOSEN or LINE_WIDTH) / ns.AtlasScale()
	local alpha = (picked and not isChosen) and LINE_ALPHA_OTHER or LINE_ALPHA
	if isChosen then alpha = 1 end
	local step = LINE_STEP
	for y = -step, tall, step do
		for x = -step, wide, step do
			local a, b, c, d = Height(x, y), Height(x + step, y), Height(x + step, y + step), Height(x, y + step)
			local case = (a >= ZONE_LEVEL and 1 or 0) + (b >= ZONE_LEVEL and 2 or 0) + (c >= ZONE_LEVEL and 4 or 0) + (d >= ZONE_LEVEL and 8 or 0)
			local pairsHere = CONTOURS[case]
			if pairsHere then
				local sides = {
					L = { x, y + step * Cross(a, d) }, T = { x + step * Cross(a, b), y },
					R = { x + step, y + step * Cross(b, c) }, B = { x + step * Cross(d, c), y + step },
				}
				for _, pair in ipairs(pairsHere) do
					used = used + 1
					local line = ui.zoneLines[used]
					if not line then
						line = ui.world:CreateLine(nil, "ARTWORK", nil, 3)
						ui.zoneLines[used] = line
					end
					local from, to = sides[pair:sub(1, 1)], sides[pair:sub(2, 2)]
					if zones.habitat then
						line:SetColorTexture(HABITAT_EDGE[1], HABITAT_EDGE[2], HABITAT_EDGE[3], 0.9)
					else
						line:SetColorTexture(ZONE_COLOR[1] + 0.25, ZONE_COLOR[2] + 0.25, 1, alpha)
					end
					line:SetThickness(thickness)
					line:SetStartPoint("TOPLEFT", ui.world, (from[1] + 0.5) * cellWide, -(from[2] + 0.5) * cellTall)
					line:SetEndPoint("TOPLEFT", ui.world, (to[1] + 0.5) * cellWide, -(to[2] + 0.5) * cellTall)
					line:Show()
				end
			end
		end
	end
	return used
end

local zonesDrawn -- what is drawn now: nothing is redone when nothing changed
function ns.AtlasDrawZones()
	if not ui then return end
	if not zones then
		zonesDrawn = nil
		ui.zonePool:ReleaseAll()
		for _, line in ipairs(ui.zoneLines) do line:Hide() end
		return
	end
	local picked = not zones.habitat and chosen and chosen.quest or nil
	local now = zones.signature .. ":" .. tostring(picked) .. ":" .. math.floor(ns.AtlasScale() * 100)
	if now == zonesDrawn then return end
	zonesDrawn = now
	DrawFill(picked)
	local used = 0
	for quest in pairs(zones.quests) do
		if quest ~= picked then used = DrawOutline(quest, used, picked) end
	end
	if picked and zones.quests[picked] then used = DrawOutline(picked, used, picked) end
	for at = used + 1, #ui.zoneLines do ui.zoneLines[at]:Hide() end
end

-- A zone under the mouse says whose it is.
local function SortedOwners(owners)
	local ids = {}
	for id in pairs(owners) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end

function ns.AtlasHoverZone(x, y)
	local owners = x and ZoneOwners(x, y)
	if not owners then
		if hoveredZone then
			hoveredZone = nil
			if GameTooltip:GetOwner() == ui.clip then GameTooltip:Hide() end
		end
		return
	end
	if owners.habitat then
		if hoveredZone == "habitat" then return end
		hoveredZone = "habitat"
		local info = zones.quests.habitat
		ns.ShowTip(ui.clip, { { info.title, Skin.COLORS.bad[1], Skin.COLORS.bad[2], Skin.COLORS.bad[3] }, ns.TipLine(L.ATLAS_HABITAT_TIP, "muted") },
			ns.AtlasPadCursor() and "ANCHOR_RIGHT" or "ANCHOR_CURSOR")
		return
	end
	local ids = SortedOwners(owners)
	local key = table.concat(ids, ",")
	if key == hoveredZone then return end
	hoveredZone = key
	local lines = {}
	for _, id in ipairs(ids) do
		local info = zones.quests[id]
		lines[#lines + 1] = { info.title, GOLD[1], GOLD[2], GOLD[3] }
		for _, word in ipairs(info.words) do lines[#lines + 1] = word end
	end
	lines[#lines + 1] = ns.TipLine(L.ATLAS_QUEST_OPEN, "blue")
	-- (the controller's cursor is not the mouse's: beside the map)
	ns.ShowTip(ui.clip, lines, ns.AtlasPadCursor() and "ANCHOR_RIGHT" or "ANCHOR_CURSOR")
end

-- The zone under the mouse, lit (the game's own picture for it).
function ns.AtlasHighlight(map, x, y)
	local glow = ui.glow
	if not map or not C_Map.GetMapHighlightInfoAtPosition then return glow:Hide() end
	local file, _, percentX, percentY, wide, tall, left, top = Safe(C_Map.GetMapHighlightInfoAtPosition, map, x, y)
	file, percentX, percentY, wide, tall, left, top = Clean(file), Clean(percentX), Clean(percentY), Clean(wide), Clean(tall), Clean(left), Clean(top)
	if not (file and file ~= 0 and percentX and wide and left and wide > 0) then return glow:Hide() end
	local mapWide, mapTall = ui.world:GetWidth(), ui.world:GetHeight()
	glow:SetTexture(file)
	glow:SetTexCoord(0, percentX, 0, percentY)
	glow:SetSize(wide * mapWide, tall * mapTall)
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", ui.world, "TOPLEFT", left * mapWide, -top * mapTall)
	glow:Show()
end

-- You, your group, your corpse --------------------------------------------------------------------------------------

local function PlaceMark(mark, x, y)
	mark.mapX, mark.mapY = x, y
	local cx, cy = ns.AtlasProject(x, y)
	mark:ClearAllPoints()
	mark:SetPoint("CENTER", ui.overlay, "TOPLEFT", cx, -cy)
	mark:Show()
end

-- The marks where the canvas says (a pan or a zoom: where everyone stands is not read again).
function ns.AtlasMoveMarks()
	for _, mark in ipairs(ui.marks or {}) do
		if mark.mapX and mark:IsShown() then PlaceMark(mark, mark.mapX, mark.mapY) end
	end
end

local function Position(unit, map)
	local position = Safe(C_Map.GetPlayerMapPosition, map, unit)
	if not position or U.IsSecret(position) then return nil end
	local x, y = Safe(position.GetXY, position)
	x, y = Clean(x), Clean(y)
	if InBounds(x, y) and (x ~= 0 or y ~= 0) then return x, y end
end

-- One of your group on the atlas (the at-th shown), made the first time it is needed.
local MEMBER_SIZE, MEMBER_FILL = 14, 10
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function Disc(member, size, layer)
	local texture = member:CreateTexture(nil, "OVERLAY", nil, layer)
	texture:SetSize(size, size)
	texture:SetPoint("CENTER")
	texture:SetColorTexture(1, 1, 1, 1)
	local mask = member:CreateMaskTexture()
	mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return texture
end
function ns.AtlasMember(at)
	local member = ui.party[at]
	if member then return member end
	member = CreateFrame("Frame", nil, ui.memberHolder)
	member:SetSize(MEMBER_SIZE, MEMBER_SIZE)
	member.edge = Disc(member, MEMBER_SIZE, 1)
	member.edge:SetVertexColor(0.05, 0.04, 0.03, 0.9)
	member.fill = Disc(member, MEMBER_FILL, 2)
	-- (its name under the mouse; the map still takes the clicks and the drags)
	member:EnableMouse(true)
	if member.SetMouseClickEnabled then member:SetMouseClickEnabled(false) end
	member:SetScript("OnEnter", function(self)
		local name = self.unit and Clean(Safe(UnitName, self.unit))
		if not name then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(name, self.fill:GetVertexColor())
		GameTooltip:Show()
	end)
	member:SetScript("OnLeave", function() GameTooltip:Hide() end)
	member:Hide()
	ui.party[at] = member
	ui.marks[#ui.marks + 1] = member
	return member
end

function ns.AtlasFollow()
	if not (ui and ui.you) then return end
	local map = ns.AtlasMap()
	if not map then return end
	local x, y = Position("player", map)
	-- (the route's line follows you: drawn again once you have moved a little)
	local moved = (x and not youAt) or (not x and youAt) or (x and (math.abs(x - youAt[1]) + math.abs(y - youAt[2]) > 0.002))
	if moved then
		youAt = x and { x, y } or nil
		DrawRouteDots()
	end
	if x then
		PlaceMark(ui.you, x, y)
		local facing = Clean(Safe(GetPlayerFacing))
		if facing then ui.you:SetRotation(facing) end
	else
		ui.you:Hide()
	end
	ui.youRing:SetShown(x ~= nil)
	-- Your group: each one a disc in the colour of their class (a raid: everyone in it).
	local units = {}
	if Clean(Safe(IsInRaid)) then
		for at = 1, math.min(40, Clean(Safe(GetNumGroupMembers)) or 0) do
			local unit = "raid" .. at
			if not Clean(Safe(UnitIsUnit, unit, "player")) then units[#units + 1] = unit end
		end
	else
		for at = 1, math.min(4, Clean(Safe(GetNumSubgroupMembers)) or 0) do units[#units + 1] = "party" .. at end
	end
	local shown = 0
	for _, unit in ipairs(units) do
		local px, py = Position(unit, map)
		if px then
			shown = shown + 1
			local member = ns.AtlasMember(shown)
			member.unit = unit
			local r, g, b = U.ClassColor(select(2, Safe(UnitClass, unit)))
			member.fill:SetVertexColor(r or 1, g or 1, b or 1)
			PlaceMark(member, px, py)
		end
	end
	for at = shown + 1, #ui.party do
		ui.party[at].unit = nil
		ui.party[at]:Hide()
	end
	local corpse = C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and Safe(C_DeathInfo.GetCorpseMapPosition, map)
	local cx, cy
	if corpse and not U.IsSecret(corpse) then
		cx, cy = Safe(corpse.GetXY, corpse)
		cx, cy = Clean(cx), Clean(cy)
	end
	if InBounds(cx, cy) and (cx ~= 0 or cy ~= 0) then PlaceMark(ui.corpse, cx, cy) else ui.corpse:Hide() end
	-- Under the mouse: the zone, lit as the game lights it, and where.
	if ui.overCanvas and ui.coords then
		local _, _, mx, my = ns.AtlasCursor()
		if mx then
			local _, name = ns.AtlasChildAt(mx, my)
			ui.coords:SetText((name and name .. "   " or "") .. ("%.1f  %.1f"):format(mx * 100, my * 100))
			ns.AtlasHighlight(map, mx, my)
			ns.AtlasHoverZone(mx, my)
		else
			ui.coords:SetText("")
			ns.AtlasHighlight()
			ns.AtlasHoverZone()
		end
	else
		ns.AtlasHighlight()
		ns.AtlasHoverZone()
	end
end

-- Clicks on the map -------------------------------------------------------------------------------------------------

-- A step of your route or a note of yours taken away (its card, or the panel's button).
function ns.AtlasRemove(data)
	if not data then return end
	if data.kind == "step" and data.index then
		ns.RemoveStep(data.index)
	elseif data.kind == "note" and data.note then
		ns.RemoveNote(data.note)
	else
		return
	end
	Skin.Play("click")
	if chosen == data then chosen = nil end
	ns.AtlasRefresh()
end

-- pin: the place clicked; with a controller the card opens beside it (the mouse is not where the cursor is).
function ns.AtlasPlaceCard(data, pin)
	local place = data.place
	local title = data.title
	local rows = {
		{ text = L.ATLAS_GO, glyph = "chevron", onClick = function() if place then ns.GoTo(place) end end },
		{ text = L.ATLAS_ADD_STEP, glyph = "plus", onClick = function() if place then ns.AddStep(place.map, place.x, place.y, title) end end },
		{ text = L.ATLAS_NOTE, glyph = "star", onClick = function() if place then ns.NoteCard(place.map, place.x, place.y, data.note) end end },
	}
	-- (your own step or note: a way to take it away; added at the end, a list with a hole in it would stop there)
	if data.kind == "step" then rows[#rows + 1] = { text = L.ATLAS_REMOVE_STEP, glyph = "close", onClick = function() ns.AtlasRemove(data) end } end
	if data.kind == "note" then rows[#rows + 1] = { text = L.ATLAS_REMOVE_NOTE, glyph = "close", onClick = function() ns.AtlasRemove(data) end } end
	local beside = pin ~= nil and U.UsingPad and U.UsingPad()
	Skin.ActionCard(beside and pin or nil, { atCursor = not beside, title = title, rows = rows })
end

-- As on the game's own map: a left click opens the map under the mouse, a right click goes back to the one around.
-- Alt+click: a note (or a way there, from its card), as Wanderer Maps does on the game's map.
function ns.AtlasClick(button, x, y)
	local map = ns.AtlasMap()
	if button == "RightButton" then return ns.AtlasUp() end
	if IsAltKeyDown() then return ns.NoteCard(map, x, y) end
	local child = ns.AtlasChildAt(x, y)
	if child then return ns.AtlasSetMap(child) end
	-- (a zone of a quest: that quest; several there: the next one, click after click)
	local owners = ZoneOwners(x, y)
	-- (a creature's habitat: its card beside the atlas)
	if owners and owners.habitat then
		local bestiary = _G.WandererBestiary
		if habitat and type(bestiary) == "table" and bestiary.Show then bestiary.Show(habitat.id, ns.AtlasFrame()) end
		return
	end
	if owners then
		local ids = SortedOwners(owners)
		local pick = ids[1]
		for at, id in ipairs(ids) do
			if chosen and chosen.quest == id then pick = ids[at + 1] or ids[1] end
		end
		local quest = QuestOf({ quest = pick })
		if quest then return ChoosePlace(quest) end
	end
	if chosen then
		chosen, letGo = nil, true
		ns.AtlasDrawPanel()
		ns.AtlasDrawZones()
		ns.AtlasDrawPins()
	end
end

-- The panel: one place at a time ----------------------------------------------------------------------------------

local function ClearPanel()
	for _, row in ipairs(ui.rows) do row:Hide() end
	ui.objectives:SetText("")
	ui.about:SetText("")
	ui.chip:Set(nil)
	ui.chip2:Set(nil)
	for _, button in ipairs({ ui.goButton, ui.addButton, ui.noteButton, ui.removeButton, ui.openButton, ui.backButton, ui.shareButton, ui.abandonButton, ui.rewards, ui.journal }) do button:Hide() end
end

-- Followed in your objectives list (the game's own watch list, Wanderer Quests' list too): a box to tick, as in the
-- game's quest log.
local function Watched(id)
	local log = C_QuestLog
	return id ~= nil and log ~= nil and log.GetQuestWatchType ~= nil and Clean(Safe(log.GetQuestWatchType, id)) ~= nil
end

local function SetWatched(id, on)
	local log = C_QuestLog
	if not (id and log) then return end
	if on and log.AddQuestWatch then
		Safe(log.AddQuestWatch, id)
	elseif not on and log.RemoveQuestWatch then
		Safe(log.RemoveQuestWatch, id)
	end
end

local function WatchBox(row, idOf)
	local box = Skin.Check(row, "", function() return Watched(idOf()) end, function(on) SetWatched(idOf(), on) end, L.ATLAS_WATCH_TIP)
	box:SetPoint("LEFT", 4, 0)
	return box
end

-- A quest row's look: the quest chosen (its sheet beside) in a gold tint with a thin gold line on its left.
local function Paint(row, hover)
	if row.selected then
		row.ground:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], CHOSEN + (hover and HOVER or 0))
	else
		row.ground:SetColorTexture(1, 1, 1, 0.035 + (hover and HOVER or 0))
	end
	if row.line then row.line:SetShown(row.selected and true or false) end
end

local function SelectLine(row)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetWidth(2)
	row.line:SetPoint("TOPLEFT")
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
	row.line:Hide()
end

-- Quests shown on Wanderer Quests' sheet (it is there, and knows them): the panel keeps its list.
local noSheet = {}
local function OnSheets(id)
	local quests = Quests()
	return quests ~= nil and quests.Sheet ~= nil and not noSheet[id]
end

local function ChosenQuest() return chosen and chosen.kind == "quest" and chosen.quest or nil end

local function QuestRow(index_)
	local row = ui.rows[index_]
	if row then return row end
	row = CreateFrame("Button", nil, ui.card)
	row:SetHeight(QUEST_ROW - 2)
	row:SetPoint("TOPLEFT", ui.listTop, "BOTTOMLEFT", 0, -(index_ - 1) * QUEST_ROW)
	row:SetPoint("TOPRIGHT", ui.listTop, "BOTTOMRIGHT", 0, -(index_ - 1) * QUEST_ROW)
	row.ground = row:CreateTexture(nil, "BACKGROUND")
	row.ground:SetAllPoints()
	row.ground:SetColorTexture(1, 1, 1, 0.035)
	row.watch = WatchBox(row, function() return row.data and row.data.quest end)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", row.watch.box, "RIGHT", 6, 0)
	row.text = Skin.Text(row, "GameTooltipTextSmall", "text")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	SelectLine(row)
	row:SetScript("OnEnter", function(self)
		Paint(self, true)
		if self.data and self.data.kind == "creature" then Skin.ShowTip(self, { self.data.title, L.ATLAS_BESTIARY_TIP }) end
	end)
	row:SetScript("OnLeave", function(self)
		Paint(self, false)
		GameTooltip:Hide()
	end)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- (the top button: its right click, the quest's card; a creature has none, set as it is drawn)
	row.padRight, row.padRightWord = true, L.PAD_PLACE
	row:SetScript("OnClick", function(self, button)
		local data = self.data
		if not data then return end
		-- (a creature your quests ask for: its card in Wanderer Bestiary, beside the atlas; again: closed)
		if data.kind == "creature" then
			local bestiary = Bestiary()
			if not bestiary then return end
			Skin.Play("click")
			if bestiary.Shown(ns.AtlasFrame()) == data.unit then
				bestiary.Hide(ns.AtlasFrame())
				ns.AtlasHabitat(nil)
			else
				bestiary.Show(data.unit, ns.AtlasFrame())
				if bestiary.Habitat then ns.AtlasHabitat(data.unit, data.title, bestiary.Habitat(data.unit)) end
			end
			return ns.AtlasDrawPanel()
		end
		if button == "RightButton" then return ns.AtlasQuestCard(data.quest, data.title, data, self) end
		ChoosePlace(data)
		ns.AtlasFocus(data.x, data.y)
	end)
	ui.rows[index_] = row
	return row
end

local function DrawOverview()
	local map = ns.AtlasMap()
	if HabitatHere() then
		ui.kicker:SetText(U.Upper(L.ATLAS_HABITAT))
		ui.placeTitle:SetText(habitat.title or "")
		ui.placeTitle:SetTextColor(Skin.COLORS.bad[1], Skin.COLORS.bad[2], Skin.COLORS.bad[3])
		ui.about:SetText(L.ATLAS_HABITAT_ABOUT)
		ui.backButton:Show()
		return
	end
	local info = map and Safe(C_Map.GetMapInfo, map)
	ui.kicker:SetText(U.Upper(L.ATLAS_ON_THIS_MAP))
	ui.placeTitle:SetText(type(info) == "table" and Clean(info.name) or "")
	ui.placeTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	ui.about:SetText(map and not Far(map) and ns.ZoneFacts(map) or "")
	local shown = 0
	for _, data in ipairs(pins) do
		if data.kind == "quest" and shown < MAX_QUEST_ROWS then
			shown = shown + 1
			local row = QuestRow(shown)
			row.data = data
			row.padRight = true -- (the top button: its right click, the quest's card)
			row.selected = data.quest ~= nil and data.quest == ChosenQuest()
			Paint(row, false)
			row.watch:Show()
			row.watch:Refresh()
			row.icon:SetTexCoord(0, 1, 0, 1)
			row.icon:SetTexture(data.file)
			row.text:SetText(data.title)
			row:Show()
		end
	end
	-- Below, the creatures they ask for here (with Wanderer Bestiary): a click opens their card beside.
	local bestiary = Bestiary()
	local open = bestiary and bestiary.Shown(ns.AtlasFrame())
	for _, unit in ipairs(bestiary and hunted or {}) do
		if shown < MAX_QUEST_ROWS and bestiary.Known(unit) then
			shown = shown + 1
			local row = QuestRow(shown)
			row.data = { kind = "creature", unit = unit, title = bestiary.Name(unit) }
			row.padRight = false -- (either click opens its card: no top button)
			row.selected = open == unit
			Paint(row, false)
			row.watch:Hide()
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			if not bestiary.Portrait(row.icon, unit) then row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
			row.text:SetText(row.data.title)
			row:Show()
		end
	end
	if shown == 0 then ui.objectives:SetText(L.ATLAS_NO_QUEST) end
end

-- The journal: every quest of yours, by zone, as the game's list has them --------------------------------------------

local function QuestMapOf(id)
	local map = GetQuestUiMapID and Clean(Safe(GetQuestUiMapID, id))
	if map and map ~= 0 then return map end
	local quests = _G.WandererQuests
	return type(quests) == "table" and quests.QuestMap and quests.QuestMap(id) or nil
end

local function OpenJournalQuest(entry)
	local map = QuestMapOf(entry.id)
	if map and map ~= ns.AtlasMap() then ns.AtlasSetMap(map) end
	local data = QuestOf({ quest = entry.id }) or { kind = "quest", quest = entry.id, title = entry.title, done = QuestDone(entry.id), noPlace = true }
	ChoosePlace(data)
	if not data.noPlace then ns.AtlasFocus(data.x, data.y) end
end

-- A quest of your log shown from another addon (Wanderer Quests' list): its map, the quest chosen there, without
-- changing which quest you follow.
function ns.AtlasOpenQuest(id, title)
	if not (ui and id) then return end
	local map = QuestMapOf(id)
	if map and map ~= ns.AtlasMap() then ns.AtlasSetMap(map) end
	chosen = QuestOf({ quest = id }) or { kind = "quest", quest = id, title = title or QuestTitle(id) or "", done = QuestDone(id),
		noPlace = true }
	sheetAsked = true
	Skin.Play("click")
	ns.AtlasDrawPanel()
	ns.AtlasDrawZones()
	ns.AtlasDrawPins()
	if not chosen.noPlace then ns.AtlasFocus(chosen.x, chosen.y) end
end

local function JournalEntries()
	local out, log = {}, C_QuestLog
	if not (log and log.GetNumQuestLogEntries and log.GetInfo) then return out end
	for at = 1, Clean(Safe(log.GetNumQuestLogEntries)) or 0 do
		local info = Safe(log.GetInfo, at)
		if type(info) == "table" and not Clean(info.isHidden) then
			local title = Clean(info.title)
			if Clean(info.isHeader) then
				out[#out + 1] = { header = title }
			elseif title and Clean(info.questID) then
				out[#out + 1] = { id = Clean(info.questID), title = title, level = Clean(info.level) }
			end
		end
	end
	return out
end

local function JournalRow(at)
	local row = ui.journalRows[at]
	if row then return row end
	row = CreateFrame("Button", nil, ui.journal)
	row:SetHeight(JOURNAL_ROW - 1)
	row:SetPoint("TOPLEFT", 0, -(at - 1) * JOURNAL_ROW)
	row:SetPoint("TOPRIGHT", -Skin.SCROLL_WIDTH - 2, -(at - 1) * JOURNAL_ROW)
	row.ground = row:CreateTexture(nil, "BACKGROUND")
	row.ground:SetAllPoints()
	row.watch = WatchBox(row, function() return row.entry and row.entry.id end)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", row.watch.box, "RIGHT", 5, 0)
	row.count = Skin.Text(row, "GameTooltipTextSmall", "muted")
	row.count:SetPoint("RIGHT", -4, 0)
	row.text = Skin.Text(row, "GameTooltipTextSmall", "text")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
	row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	SelectLine(row)
	row:SetScript("OnEnter", function(self) if self.entry and self.entry.id then Paint(self, true) end end)
	row:SetScript("OnLeave", function(self) if self.entry and self.entry.id then Paint(self, false) end end)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.padRight, row.padRightWord = true, L.PAD_PLACE -- (the top button: its right click, the quest's card)
	row:SetScript("OnClick", function(self, button)
		local entry = self.entry
		if not (entry and entry.id) then return end
		if button == "RightButton" then return ns.AtlasQuestCard(entry.id, entry.title, QuestOf({ quest = entry.id }), self) end
		OpenJournalQuest(entry)
	end)
	ui.journalRows[at] = row
	return row
end

function DrawJournal()
	ui.journal:Show()
	ui.kicker:SetText("")
	ui.placeTitle:SetText("")
	local entries = JournalEntries()
	local room = ui.card:GetHeight() - TABS_HEIGHT
	local fits = math.max(1, math.floor(room / JOURNAL_ROW))
	journalOffset = math.max(0, math.min(journalOffset, #entries - fits))
	for at = 1, math.max(fits, #ui.journalRows) do
		local entry = at <= fits and entries[journalOffset + at] or nil
		local row = (entry or ui.journalRows[at]) and JournalRow(at)
		if row then
			row.entry = entry
			row:SetShown(entry ~= nil)
			-- (a zone's title has no box)
			row.watch:SetShown(entry ~= nil and entry.id ~= nil)
			row.padRight = entry ~= nil and entry.id ~= nil -- (a zone's title has no card)
			if entry and entry.id then row.watch:Refresh() end
			row.selected = entry ~= nil and entry.id ~= nil and entry.id == ChosenQuest()
			row.line:SetShown(row.selected)
			if entry and entry.header then
				row.icon:Hide()
				row.ground:SetColorTexture(1, 1, 1, 0)
				row.text:SetText(Skin.Colorize(U.Upper(entry.header or ""), "kicker"))
				row.text:SetTextColor(1, 1, 1)
				row.count:SetText("")
			elseif entry then
				local done = QuestDone(entry.id)
				row.icon:Show()
				row.icon:SetTexture(done and COMPLETE_ICON or OBJECTIVE_ICON)
				Paint(row, false)
				row.text:SetText(entry.level and ("[" .. entry.level .. "] " .. entry.title) or entry.title)
				if entry.level then row.text:SetTextColor(W.QuestLevelColor(entry.level)) else row.text:SetTextColor(Skin.COLORS.text[1], Skin.COLORS.text[2], Skin.COLORS.text[3]) end
				local total, finished = 0, 0
				for _, item in ipairs(Objectives(entry.id)) do
					total = total + 1
					if item.done then finished = finished + 1 end
				end
				row.count:SetText(total > 0 and (finished .. "/" .. total) or "")
			end
		end
	end
	ui.journalScroll:Set(#entries, fits, journalOffset)
	ui.journalEmpty:SetShown(entries[1] == nil)
end

-- What a quest says and gives (the game answers for the quest selected in its log: put back after) ----------------------

local function WithSelected(id, read)
	local log = C_QuestLog
	if not (log and log.SetSelectedQuest and log.GetSelectedQuest) then return read() end
	local before = Clean(Safe(log.GetSelectedQuest))
	if before ~= id then Safe(log.SetSelectedQuest, id) end
	local one, two = read()
	if before ~= id then Safe(log.SetSelectedQuest, before or 0) end
	return one, two
end

function QuestText(id)
	local log = C_QuestLog
	local logIndex = log and log.GetLogIndexForQuestID and Clean(Safe(log.GetLogIndexForQuestID, id))
	if not (logIndex and logIndex > 0 and GetQuestLogQuestText) then return "" end
	return Clean(WithSelected(id, function() return (Safe(GetQuestLogQuestText, logIndex)) end)) or ""
end

local function RewardIcon(at)
	local icon = ui.rewardIcons[at]
	if icon then return icon end
	icon = Skin.Icon(ui.rewards, REWARD_SIZE)
	icon:SetPoint("LEFT", (at - 1) * (REWARD_SIZE + 4), 0)
	icon:EnableMouse(true)
	icon.padTip = true -- (a controller stops on it to read it)
	Skin.ItemTooltip(icon, function(self) return self.item end)
	ui.rewardIcons[at] = icon
	return icon
end

function DrawRewards(id)
	local list = {}
	local money = WithSelected(id, function()
		local function Read(name, texture, _, quality, _, item)
			if Clean(item) then list[#list + 1] = { item = Clean(item), texture = Clean(texture) or name, quality = Clean(quality) } end
		end
		for at = 1, Clean(Safe(GetNumQuestLogRewards, id)) or 0 do Read(Safe(GetQuestLogRewardInfo, at, id)) end
		for at = 1, Clean(Safe(GetNumQuestLogChoices, id, false)) or 0 do Read(Safe(GetQuestLogChoiceInfo, at)) end
		return Clean(Safe(GetQuestLogRewardMoney, id)) or 0
	end)
	for at = 1, MAX_REWARDS do
		local reward = list[at]
		local icon = (reward or ui.rewardIcons[at]) and RewardIcon(at)
		if icon then
			icon:SetShown(reward ~= nil)
			if reward then
				icon.item = reward.item
				icon:Set(reward.texture, reward.quality)
			end
		end
	end
	ui.rewardMoney:SetText(money > 0 and U.Coins(money) or "")
	ui.rewards:SetShown(list[1] ~= nil or money > 0)
end

function Pushable(id)
	local log = C_QuestLog
	local allowed = log and log.IsPushableQuest and Clean(Safe(log.IsPushableQuest, id))
	return allowed and Clean(Safe(IsInGroup)) and true or false
end

local function ShareQuest(id)
	local ok = pcall(function()
		C_QuestLog.SetSelectedQuest(id)
		QuestLogPushQuest()
	end)
	if not ok then W.Print(L.ATLAS_REFUSED) end
end

local function AbandonQuest(id, title)
	Skin.Ask(L.ATLAS_ABANDON_ASK:format(title), function()
		local ok = pcall(function()
			C_QuestLog.SetSelectedQuest(id)
			C_QuestLog.SetAbandonQuest()
			C_QuestLog.AbandonQuest()
		end)
		if not ok then return W.Print(L.ATLAS_REFUSED) end
		chosen = nil
		ns.AtlasDrawPanel()
	end)
end

-- A quest of the list, right click (the top button with a controller): where it is, share it, give it up.
function ns.AtlasQuestCard(id, title, data, row)
	if not id then return end
	local rows = {}
	if data and not data.noPlace and data.x then
		local place = { map = ns.AtlasMap(), x = data.x, y = data.y, title = title }
		rows[#rows + 1] = { text = L.ATLAS_GO, glyph = "chevron", onClick = function() ns.GoTo(place) end }
	end
	local quests = Quests()
	if quests and quests.Reveal then
		rows[#rows + 1] = { text = L.ATLAS_OPEN_QUEST, glyph = "chevron", onClick = function() quests.Reveal(id) end }
	end
	if Pushable(id) then rows[#rows + 1] = { text = L.ATLAS_SHARE, glyph = "plus", onClick = function() ShareQuest(id) end } end
	rows[#rows + 1] = { text = L.ATLAS_ABANDON, glyph = "close", onClick = function() AbandonQuest(id, title or "") end }
	local beside = row ~= nil and U.UsingPad and U.UsingPad()
	Skin.ActionCard(beside and row or nil, { atCursor = not beside, title = title, rows = rows })
end

local function DrawChosen()
	local data = chosen
	ui.backButton:Show()
	ui.kicker:SetText(U.Upper(L["ATLAS_KIND_" .. data.kind:upper()] or ""))
	ui.placeTitle:SetText(data.title or "")
	ui.placeTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	local place = data.place
	if data.kind == "quest" then
		ui.chip:Set(data.done and L.ATLAS_QUEST_READY or L.ATLAS_QUEST_RUNNING, data.done and "green" or "gold")
		local lines = {}
		for _, item in ipairs(Objectives(data.quest)) do
			lines[#lines + 1] = Skin.Colorize(item.text, item.done and "good" or "text")
		end
		ui.about:SetText(table.concat(lines, "\n"))
		ui.objectives:SetText(QuestText(data.quest))
		DrawRewards(data.quest)
		if not data.noPlace then place = { map = ns.AtlasMap(), x = data.x, y = data.y, title = data.title } end
		local quests = _G.WandererQuests
		ui.openButton:SetShown(type(quests) == "table" and quests.Reveal ~= nil)
		ui.shareButton:Show()
		ui.shareButton:SetEnabled(Pushable(data.quest))
		ui.abandonButton:Show()
	elseif data.kind == "giver" then
		ui.objectives:SetText(table.concat(data.lines or {}, "\n"))
		place = { map = ns.AtlasMap(), x = data.x, y = data.y, title = data.title }
		local quests = _G.WandererQuests
		ui.openButton:SetShown(data.quest ~= nil and type(quests) == "table" and quests.Reveal ~= nil)
	elseif data.kind == "flight" then
		ui.chip:Set(data.known and L.ATLAS_FLIGHT_KNOWN or L.ATLAS_FLIGHT_UNKNOWN, data.known and "green" or "grey")
	elseif data.kind == "dock" then
		ui.about:SetText(L.ATLAS_DOCK_TO:format(data.to.name or "?"))
	elseif data.kind == "door" then
		ui.chip:Set(data.raid and L.ATLAS_RAID or L.ATLAS_DUNGEON, "blue")
	elseif data.kind == "poi" then
		ui.about:SetText(data.about or "")
	elseif data.kind == "step" then
		ui.chip:Set(L.ATLAS_STEP_NUMBER:format(data.index), "gold")
		if data.faded then ui.chip2:Set(L.ATLAS_STEP_DONE, "grey") end
	elseif data.kind == "note" then
		ui.chip:Set(L.ATLAS_KEPT, "green")
	end
	ui.current = place
	if place then
		ui.goButton:Show()
		ui.addButton:Show()
		ui.noteButton:Show()
	end
	-- (your own step or note: it can be taken away from here too)
	if data.kind == "step" or data.kind == "note" then
		ui.removeButton:SetLabel(data.kind == "step" and L.ATLAS_REMOVE_STEP or L.ATLAS_REMOVE_NOTE)
		ui.removeButton:Show()
	end
end

function ns.AtlasDrawPanel()
	if not ui then return end
	ClearPanel()
	ui.tabs:Select(panelView)
	-- (a creature's habitat shown: the panel is about it)
	if HabitatHere() then return DrawOverview() end
	-- (the sheet closed by its own cross, or taken by Quests' window: its words come back here)
	local quests = onSheet and Quests()
	if quests and quests.SheetQuest and quests.SheetQuest(ns.AtlasFrame()) ~= onSheet then onSheet = nil end
	-- (another quest chosen, or none: the sheet beside goes; it opens again on a quest you choose)
	if not (chosen and chosen.kind == "quest" and (sheetAsked or chosen.quest == onSheet)) then HideSheet() end
	-- (a quest you choose: all it says and gives on Wanderer Quests' sheet beside, the list kept here with the quest
	-- lit in it; without that sheet, all of it here)
	if sheetAsked then
		sheetAsked = false
		local wanted = ChosenQuest()
		local open = wanted and OnSheets(wanted) and Quests().Sheet(wanted, ns.AtlasFrame())
		-- (a quest Wanderer Quests does not know: all of it here)
		if wanted and not open then noSheet[wanted] = true end
		onSheet = open and wanted or nil
	end
	if chosen and not (chosen.kind == "quest" and OnSheets(chosen.quest)) then
		DrawChosen()
	elseif panelView == "journal" then
		DrawJournal()
	else
		DrawOverview()
	end
end

function ns.AtlasPanelView() return panelView end
-- byYou: a tab clicked (the choice let go); else the atlas opening on a view (the quest you follow kept chosen).
function ns.AtlasSetPanel(view, byYou)
	panelView, chosen, journalOffset = view, nil, 0
	-- (the journal asked for, by its key or its tab: the journal shows, nothing chosen over it)
	if byYou or view ~= "map" then letGo = true else KeepPinned() end
	ns.AtlasDrawPanel()
	ns.AtlasDrawZones()
	ns.AtlasDrawPins()
end

-- The search --------------------------------------------------------------------------------------------------------

local function Index()
	if index then return index end
	index = {}
	local types = Enum and Enum.UIMapType
	for _, continent in ipairs({ 1414, 1415 }) do
		local info = Safe(C_Map.GetMapInfo, continent)
		if type(info) == "table" and Clean(info.name) then index[#index + 1] = { name = Clean(info.name), map = continent } end
		local children = types and Safe(C_Map.GetMapChildrenInfo, continent, types.Zone, true)
		for _, child in ipairs(type(children) == "table" and children or {}) do
			if Clean(child.name) then index[#index + 1] = { name = Clean(child.name), map = Clean(child.mapID) } end
		end
	end
	for _, master in ipairs(ns.Services("flight")) do index[#index + 1] = { name = master.title, map = master.map, x = master.x, y = master.y } end
	local quests = _G.WandererQuests
	if type(quests) == "table" and quests.Entrances then
		for _, door in ipairs(quests.Entrances() or {}) do index[#index + 1] = { name = door.name, map = door.map, x = door.x, y = door.y } end
	end
	return index
end

local function Results()
	local out = {}
	if query == "" then return out end
	local folded = U.Fold(query)
	for _, note in ipairs(ns.Notes()) do
		if U.Matches(note.title or "", query, folded) then out[#out + 1] = { name = note.title, map = note.map, x = note.x, y = note.y } end
	end
	for _, place in ipairs(Index()) do
		if #out >= MAX_RESULTS then break end
		if U.Matches(place.name, query, folded) then out[#out + 1] = place end
	end
	return out
end

local function DrawResults()
	local list = Results()
	ui.results = ui.results or {}
	for at = 1, MAX_RESULTS do
		local place = list[at]
		local row = ui.results[at]
		if place and not row then
			row = Skin.SmallButton(ui.side, "", function(self) ns.AtlasShow(self.place.map, self.place.x, self.place.y) end, nil, 22)
			row:SetPoint("TOPLEFT", ui.search, "BOTTOMLEFT", 0, -2 - (at - 1) * 23)
			ui.results[at] = row
		end
		if row then
			row:SetShown(place ~= nil)
			if place then
				row.place = place
				row:SetLabel(place.name)
				row:SetWidth(SEARCH_WIDTH)
			end
		end
	end
end

-- What is shown --------------------------------------------------------------------------------------------------------

local function DrawLayers()
	for _, button in ipairs(ui.layers) do
		local on = Shown(button.key)
		button.icon:SetDesaturated(not on)
		button.icon:SetAlpha(on and 1 or 0.5)
		local c = Skin.COLORS[on and "text" or "muted"]
		button.word:SetTextColor(c[1], c[2], c[3])
	end
end

-- The legend, one small line along the bottom of the map: an icon and a word, a click to show or hide. Too narrow
-- for the words: the icons alone (the word under the mouse).
local function BuildLayers(side)
	local band = CreateFrame("Frame", nil, side)
	band:SetPoint("BOTTOMLEFT")
	band:SetPoint("BOTTOMRIGHT")
	band:SetHeight(LEGEND_HEIGHT)
	band:EnableMouse(true)
	local ground = band:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(0.05, 0.08, 0.13, 0.82)
	ui.legend = band
	ui.layers = {}
	for at, layer in ipairs(LAYERS) do
		local button = CreateFrame("Button", nil, band)
		button.key = layer[1]
		button:SetHeight(LEGEND_HEIGHT)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetSize(16, 16)
		button.icon:SetPoint("LEFT")
		button.icon:SetTexture(layer[3])
		if layer[3]:find("Icons\\") then button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		button.word = Skin.Text(button, "GameTooltipTextSmall", "text")
		button.word:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
		button.word:SetText(L[layer[2]])
		button:SetScript("OnClick", function(self)
			local db = ns.AtlasDb()
			Shown(self.key)
			db.layers[self.key] = not Shown(self.key)
			Skin.Play("click")
			ns.AtlasRefresh()
		end)
		Skin.Tooltip(button, L[layer[2]], "ANCHOR_TOP")
		ui.layers[at] = button
	end
end

function ns.AtlasFitLegend()
	if not (ui and ui.layers) then return end
	local room = ui.legend:GetWidth()
	if not room or room <= 0 then room = ui.clip:GetWidth() end
	local widths, total = {}, 0
	for at, button in ipairs(ui.layers) do
		widths[at] = 16 + 4 + U.Measure(button.word, "GetStringWidth", 60)
		total = total + widths[at] + LEGEND_GAP
	end
	local words = total + LEGEND_GAP <= room
	local previous
	for at, button in ipairs(ui.layers) do
		button.word:SetShown(words)
		button:SetWidth(words and widths[at] or 16)
		button:ClearAllPoints()
		if previous then button:SetPoint("LEFT", previous, "RIGHT", LEGEND_GAP, 0) else button:SetPoint("LEFT", ui.legend, "LEFT", LEGEND_GAP, 0) end
		previous = button
	end
end

-- The route, along the bottom -------------------------------------------------------------------------------------------

-- (cut by letters: never inside an accented one)
local function Short(words, most)
	local letters = 0
	for at in words:gmatch("()[^\128-\191]") do
		letters = letters + 1
		if letters > most then return words:sub(1, at - 1) .. ".." end
	end
	return words
end

local function DrawStrip()
	local route = ns.Route()
	ui.stepRows = ui.stepRows or {}
	local previous
	for at = 1, MAX_STEPS do
		local step = route.steps[at]
		local row = ui.stepRows[at]
		if step and not row then
			row = Skin.SmallButton(ui.strip, "", function(self, button)
				if button == "RightButton" then return ns.RemoveStep(self.index) end
				ns.AtlasShow(self.step.map, self.step.x, self.step.y)
			end, function() return UsingPad() and L.ATLAS_STEP_TIP_PAD or L.ATLAS_STEP_TIP end, 26)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row.padRight, row.padRightWord = true, L.PAD_REMOVE -- (the top button: its right click, the step taken off)
			ui.stepRows[at] = row
		end
		if row then
			row:SetShown(step ~= nil)
			if step then
				row.step, row.index = step, at
				row:SetLabel((at == route.current and Skin.Colorize(at, "gold") or at) .. "  " .. Short(step.title, 22))
				row:SetAlpha(step.done and 0.55 or 1)
				row:ClearAllPoints()
				if previous then row:SetPoint("LEFT", previous, "RIGHT", 5, 0) else row:SetPoint("LEFT", ui.stripTitle, "RIGHT", 10, 0) end
				previous = row
			end
		end
	end
	local any = route.steps[1] ~= nil
	ui.stripEmpty:SetText(UsingPad() and L.ATLAS_ROUTE_EMPTY_PAD or L.ATLAS_ROUTE_EMPTY)
	ui.stripEmpty:SetShown(not any)
	ui.stripClear:SetShown(any)
end

-- Building, refreshing --------------------------------------------------------------------------------------------------

function ns.AtlasDrawHeader()
	local map = ns.AtlasMap()
	local info = map and Safe(C_Map.GetMapInfo, map)
	ui.mapName:SetText(type(info) == "table" and Clean(info.name) or "")
	local parent = type(info) == "table" and Clean(info.parentMapID)
	ui.upButton:SetShown(parent ~= nil and parent ~= 0)
	ui.walkButton:SetLabel(Skin.Colorize(L.ATLAS_WALK, ns.AtlasDb().walk and "gold" or "text"))
end

function ns.AtlasRefresh()
	if not ui then return end
	ReadPins()
	if chosen and chosen.kind == "quest" and not QuestInLog(chosen.quest) then chosen = nil end
	ns.AtlasDrawPins()
	ns.AtlasDrawPanel()
	ns.AtlasDrawZones()
	DrawLayers()
	DrawStrip()
	DrawResults()
	ns.AtlasDrawHeader()
end

function ns.AtlasMapChanged()
	chosen, autoChosen, letGo = nil, false, false
	local map = ns.AtlasMap()
	if not ui then return end
	if Far(map) then ZoneLabels(map) else
		for _, label in ipairs(ui.zones or {}) do
			label:Hide()
			label.x = nil
		end
	end
	ns.AtlasRefresh()
	ns.AtlasFollow()
end

local listening
local refreshSoon
function ns.AtlasListen(on)
	if not listening then
		listening = CreateFrame("Frame")
		refreshSoon = U.Debounce(0.15, function()
			local window = ns.AtlasFrame()
			if window and window:IsShown() then ns.AtlasRefresh() end
		end)
		listening:SetScript("OnEvent", function(_, event)
			if event == "MAP_EXPLORATION_UPDATED" then ns.AtlasDrawLand() end
			refreshSoon()
		end)
	end
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "MAP_EXPLORATION_UPDATED" }) do
		if on then pcall(listening.RegisterEvent, listening, event) else pcall(listening.UnregisterEvent, listening, event) end
	end
end

local function Button(parent, word, tip, run)
	return Skin.SmallButton(parent, word, run, tip)
end

function ns.AtlasBuildContent(window, margin, top, rightWidth, strip)
	ui = ns.AtlasUI()
	ui.zonePool = CreateTexturePool(ui.world, "ARTWORK", 1)
	ui.zoneLines = {}
	-- The heading: where you are looking, one way up, the quiet actions.
	ui.upButton = Skin.GlyphButton(window, "back", 14, L.ATLAS_UP, function() ns.AtlasUp() end)
	ui.upButton:SetPoint("TOPLEFT", window, "TOPLEFT", margin + HEADER_LEFT, -margin - 8)
	ui.mapName = Skin.Text(window, "GameTooltipHeaderText", "gold")
	ui.mapName:SetPoint("LEFT", ui.upButton, "RIGHT", 6, 0)
	local gameMap = Button(window, L.ATLAS_GAME_MAP, L.ATLAS_GAME_MAP_DESC, function() ns.AtlasToGameMap() end)
	gameMap:SetPoint("TOPRIGHT", window, "TOPRIGHT", -62, -8)
	gameMap.padBinding = function()
		local map = _G.WorldMapFrame
		return not (map and map:IsShown()) and "TOGGLEWORLDMAP" or nil
	end
	ui.walkButton = Button(window, L.ATLAS_WALK, L.ATLAS_WALK_DESC, function() ns.AtlasWalk() end)
	ui.walkButton:SetPoint("RIGHT", gameMap, "LEFT", -6, 0)
	local routes = Button(window, L.ATLAS_ROUTE_WINDOW, L.ATLAS_ROUTE_WINDOW_DESC, function() ns.Toggle() end)
	routes:SetPoint("RIGHT", ui.walkButton, "LEFT", -6, 0)

	-- Over the map: one search at the top, the legend along the bottom (what lets the clicks through to the map).
	-- (the window's, over the map: what the controller's cross reaches, the map itself left out of it)
	local side = CreateFrame("Frame", nil, window)
	side:SetAllPoints(ui.clip)
	side:SetFrameLevel(ui.overlay:GetFrameLevel() + 90)
	ui.side = side
	ui.search = Skin.CreateInput(side, nil, 40, { hint = L.ATLAS_SEARCH, onChange = function(input, typed)
		if not typed then return end
		query = input:GetText() or ""
		DrawResults()
	end })
	ui.search:SetPoint("TOPLEFT", 8, -8)
	ui.search:SetWidth(SEARCH_WIDTH)
	BuildLayers(side)

	-- On the right: one place at a time.
	local card = CreateFrame("Frame", nil, window)
	card:SetPoint("TOPRIGHT", window, "TOPRIGHT", -margin, -top)
	card:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin + strip)
	card:SetWidth(rightWidth)
	ui.card = card
	ui.kicker = Skin.Text(card, "GameTooltipTextSmall", "kicker")
	ui.tabs = Skin.Tabs(card, { { "map", L.ATLAS_TAB_MAP }, { "journal", L.ATLAS_TAB_JOURNAL } }, function(view) ns.AtlasSetPanel(view, true) end)
	ui.tabs:SetPoint("TOPLEFT", 0, 0)
	ui.kicker:SetPoint("TOPLEFT", 0, -TABS_HEIGHT - 2)
	ui.kicker:SetWidth(rightWidth - 30)
	ui.kicker:SetJustifyH("LEFT")
	ui.backButton = Skin.GlyphButton(card, "close", 12, L.ATLAS_BACK, function()
		-- (a creature's habitat: gone, the map back as you had it)
		if HabitatHere() then return ns.AtlasHabitat(nil) end
		chosen, letGo = nil, true
		ns.AtlasDrawPanel()
		ns.AtlasDrawZones()
		ns.AtlasDrawPins()
	end)
	ui.backButton:SetPoint("TOPRIGHT", 0, -TABS_HEIGHT)
	ui.placeTitle = Skin.Text(card, "GameTooltipHeaderText", "gold")
	ui.placeTitle:SetPoint("TOPLEFT", ui.kicker, "BOTTOMLEFT", 0, -4)
	ui.placeTitle:SetWidth(rightWidth)
	ui.placeTitle:SetJustifyH("LEFT")
	ui.chip, ui.chip2 = Skin.Chip(card), Skin.Chip(card)
	ui.chip:SetPoint("TOPLEFT", ui.placeTitle, "BOTTOMLEFT", 0, -6)
	ui.chip2:SetPoint("LEFT", ui.chip, "RIGHT", 5, 0)
	ui.about = Skin.Text(card, "GameTooltipTextSmall", "soft")
	ui.about:SetPoint("TOPLEFT", ui.placeTitle, "BOTTOMLEFT", 0, -27)
	ui.about:SetWidth(rightWidth)
	ui.about:SetJustifyH("LEFT")
	ui.objectives = Skin.Text(card, "GameTooltipTextSmall", "text")
	ui.objectives:SetPoint("TOPLEFT", ui.about, "BOTTOMLEFT", 0, -6)
	ui.objectives:SetWidth(rightWidth)
	ui.objectives:SetJustifyH("LEFT")
	if ui.objectives.SetMaxLines then ui.objectives:SetMaxLines(QUEST_TEXT_LINES) end
	ui.rewards = CreateFrame("Frame", nil, card)
	ui.rewards:SetPoint("BOTTOMLEFT", 0, 104)
	ui.rewards:SetPoint("BOTTOMRIGHT", 0, 104)
	ui.rewards:SetHeight(REWARD_SIZE)
	ui.rewardIcons = {}
	ui.rewardMoney = Skin.Text(ui.rewards, "GameTooltipTextSmall", "text")
	ui.rewardMoney:SetPoint("RIGHT")
	-- The journal: over the panel's place, with its own scroll.
	ui.journal = CreateFrame("Frame", nil, card)
	ui.journal:SetPoint("TOPLEFT", 0, -TABS_HEIGHT)
	ui.journal:SetPoint("BOTTOMRIGHT")
	ui.journal:EnableMouseWheel(true)
	ui.journal:SetScript("OnMouseWheel", function(_, delta)
		journalOffset = journalOffset - delta * 2
		ns.AtlasDrawPanel()
	end)
	ui.journalRows = {}
	ui.journalScroll = Skin.ScrollBar(ui.journal, function(value)
		journalOffset = math.floor(value + 0.5)
		ns.AtlasDrawPanel()
	end)
	ui.journalScroll:SetPoint("TOPRIGHT")
	ui.journalScroll:SetPoint("BOTTOMRIGHT")
	ui.journalEmpty = Skin.Text(ui.journal, "GameTooltipText", "muted")
	ui.journalEmpty:SetPoint("TOP", 0, -30)
	ui.journalEmpty:SetText(L.ATLAS_JOURNAL_EMPTY)
	ui.listTop = CreateFrame("Frame", nil, card)
	ui.listTop:SetHeight(1)
	ui.listTop:SetPoint("TOPLEFT", ui.placeTitle, "BOTTOMLEFT", 0, -52)
	ui.listTop:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
	ui.goButton = Skin.Button(card, L.ATLAS_GO, function() if ui.current then ns.GoTo(ui.current) end end, "main")
	ui.goButton:SetPoint("BOTTOMLEFT", 0, 62)
	ui.goButton:SetWidth(rightWidth)
	ui.addButton = Skin.SmallButton(card, L.ATLAS_ADD_STEP, function()
		if ui.current then ns.AddStep(ui.current.map, ui.current.x, ui.current.y, ui.current.title) end
	end, L.ATLAS_ADD_STEP_DESC)
	ui.addButton:SetPoint("BOTTOMLEFT", 0, 34)
	ui.noteButton = Skin.SmallButton(card, L.ATLAS_NOTE, function()
		if ui.current then ns.NoteCard(ui.current.map, ui.current.x, ui.current.y, chosen and chosen.note) end
	end, L.ATLAS_NOTE_DESC)
	ui.noteButton:SetPoint("LEFT", ui.addButton, "RIGHT", 6, 0)
	ui.removeButton = Skin.SmallButton(card, L.ATLAS_REMOVE_STEP, function() ns.AtlasRemove(chosen) end)
	ui.removeButton:SetPoint("LEFT", ui.noteButton, "RIGHT", 6, 0)
	ui.removeButton:Hide()
	ui.openButton = Skin.SmallButton(card, L.ATLAS_OPEN_QUEST, function()
		local quests = _G.WandererQuests
		if chosen and chosen.quest and type(quests) == "table" and quests.Reveal then quests.Reveal(chosen.quest) end
	end, L.ATLAS_OPEN_QUEST_DESC)
	ui.openButton:SetPoint("BOTTOMLEFT", 0, 6)
	ui.shareButton = Skin.SmallButton(card, L.ATLAS_SHARE, function()
		if chosen and chosen.quest then ShareQuest(chosen.quest) end
	end, L.ATLAS_SHARE_DESC)
	ui.shareButton:SetPoint("LEFT", ui.openButton, "RIGHT", 6, 0)
	ui.abandonButton = Skin.SmallButton(card, L.ATLAS_ABANDON, function()
		if chosen and chosen.quest then AbandonQuest(chosen.quest, chosen.title) end
	end, L.ATLAS_ABANDON_DESC)
	ui.abandonButton:SetPoint("BOTTOMRIGHT", 0, 6)

	-- Below: the route.
	ui.strip = CreateFrame("Frame", nil, window)
	ui.strip:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	ui.strip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin - 14, margin)
	ui.strip:SetHeight(strip - 8)
	ui.stripTitle = Skin.Caps(ui.strip, L.ATLAS_ROUTE, "kicker")
	ui.stripTitle:SetPoint("LEFT")
	ui.stripEmpty = Skin.Text(ui.strip, "GameTooltipTextSmall", "muted")
	ui.stripEmpty:SetPoint("LEFT", ui.stripTitle, "RIGHT", 12, 0)
	ui.stripEmpty:SetText(L.ATLAS_ROUTE_EMPTY)
	ui.stripClear = Skin.SmallButton(ui.strip, L.ATLAS_CLEAR, function() ns.ClearAsked() end)
	ui.stripClear:SetPoint("RIGHT")

	-- On the map: the zoom, where the mouse is.
	local zoomBox = CreateFrame("Frame", nil, window)
	zoomBox:SetSize(78, 26)
	zoomBox:SetPoint("TOPRIGHT", ui.clip, "TOPRIGHT", -6, -6)
	zoomBox:SetFrameLevel(ui.overlay:GetFrameLevel() + 90)
	local plus = Skin.GlyphButton(zoomBox, "plus", 14, L.ATLAS_ZOOM_IN, function() ns.AtlasNotch(1) end)
	plus:SetPoint("LEFT")
	local minus = Skin.GlyphButton(zoomBox, "down", 14, L.ATLAS_ZOOM_OUT, function() ns.AtlasNotch(-1) end)
	minus:SetPoint("LEFT", plus, "RIGHT", 2, 0)
	local whole = Skin.GlyphButton(zoomBox, "home", 14, L.ATLAS_ZOOM_ALL, function() ns.AtlasReset() end)
	whole:SetPoint("LEFT", minus, "RIGHT", 2, 0)
	local foot = CreateFrame("Frame", nil, ui.clip)
	foot:SetPoint("BOTTOMLEFT", 8, LEGEND_HEIGHT + 3)
	foot:SetPoint("BOTTOMRIGHT", -8, LEGEND_HEIGHT + 3)
	foot:SetHeight(16)
	foot:SetFrameLevel(ui.overlay:GetFrameLevel() + 90)
	ui.coords = Skin.Text(foot, "GameTooltipTextSmall", "text")
	ui.coords:SetPoint("LEFT")
	local help = Skin.Help(window, L.ATLAS_HELP, "HEADING")
	-- (a controller: its own keys, not the mouse's)
	if help then help:HookScript("OnEnter", function(self) if UsingPad() then Skin.ShowTip(self, L.ATLAS_HELP_PAD, "ANCHOR_BOTTOM") end end) end

	ui.glow = ui.world:CreateTexture(nil, "ARTWORK", nil, 2)
	ui.glow:SetBlendMode("ADD")
	ui.glow:SetAlpha(0.45)
	ui.glow:Hide()

	-- You, your group, your corpse: over everything.
	-- (above the pins, under the search and the legend)
	local marks = CreateFrame("Frame", nil, ui.overlay)
	marks:SetAllPoints()
	marks:SetFrameLevel(ui.overlay:GetFrameLevel() + 80)
	ui.you = marks:CreateTexture(nil, "OVERLAY", nil, 3)
	ui.you:SetSize(YOU_SIZE, YOU_SIZE)
	ui.you:SetTexture(ARROW_ICON)
	-- You, at a glance: one thin golden circle around the arrow, a darker line under it for any map behind.
	ui.youRing = CreateFrame("Frame", nil, marks)
	ui.youRing:SetAllPoints()
	for _, stroke in ipairs({ { 3, 0, 0, 0, 0.55, 1 }, { 1.4, GOLD[1], GOLD[2], GOLD[3], 1, 2 } }) do
		for at = 1, YOU_RING_STEPS do
			local from, to = (at - 1) / YOU_RING_STEPS * 2 * math.pi, at / YOU_RING_STEPS * 2 * math.pi
			local line = ui.youRing:CreateLine(nil, "ARTWORK", nil, stroke[6])
			line:SetThickness(stroke[1])
			line:SetColorTexture(stroke[2], stroke[3], stroke[4], stroke[5])
			line:SetStartPoint("CENTER", ui.you, math.cos(from) * YOU_RING, math.sin(from) * YOU_RING)
			line:SetEndPoint("CENTER", ui.you, math.cos(to) * YOU_RING, math.sin(to) * YOU_RING)
		end
	end
	-- The group: made as they come (a raid has up to 39 others), each a disc in its class colour on a dark edge,
	-- its name under the mouse.
	ui.party = {}
	ui.memberHolder = marks
	ui.corpse = marks:CreateTexture(nil, "OVERLAY")
	ui.corpse:SetSize(22, 22)
	ui.corpse:SetTexture("Interface\\Minimap\\POIIcons")
	if GetPOITextureCoords then ui.corpse:SetTexCoord(GetPOITextureCoords(57)) end
	ui.corpse:Hide()
	ui.marks = { ui.you, ui.corpse }
	for at = 1, 4 do ns.AtlasMember(at) end
end

function ns.AtlasDumpContent(out)
	out.pins = #pins
	out.zones = zones and true or false
	local map = ns.AtlasMap()
	out.questsShown = map and #QuestsOn(map) or 0
end
