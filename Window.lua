local ADDON, ns = ...
local L = ns.L

-- The window: two tabs, the route (its steps in order, each saying what to do
-- there, the one followed in gold, the ones done ticked, the distance to
-- each) and the notes (every place you kept, with its sign). A click on a row
-- follows it; its "⋯" button and its right click: a step's card (move,
-- remove, keep as a note, open its quest), a note's own card (change, follow,
-- to the route, remove). Below, the nearest inn, flight master, mailbox and
-- trainer of your class, one click to follow; at the foot, the tab's one
-- action: the route cleared, or a note left where you stand. (where you
-- stand is never a step: the arrow would say "arrived" at once)

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin

local WIDTH, ROWS = 520, 10
local LOOK_EVERY = 2 -- seconds between two distances while shown

local window, tabs, list, here, clear, nearest, kept, sorter, removeSome
local tab = "route"
local since = 0

local function Distance(place)
	local tx, ty, instance = ns.WorldOf(place.map, place.x, place.y)
	if not tx then return "" end
	local _, distance = ns.Vector(tx, ty, instance)
	return distance and L.DISTANCE:format(math.floor(distance + 0.5)) or ""
end

-- A step's sign before its words: the game's "!" (to take), "?" (to hand in), a check once done.
local DONE_SIGN = "Interface\\RaidFrame\\ReadyCheck-Ready"
local function StepName(index, step)
	local sign = step.done and DONE_SIGN or (step.kind and ns.STEP_SIGNS[step.kind])
	return (sign and ("|T" .. sign .. ":14:14|t ") or "") .. index .. ". " .. ns.StepWords(step)
end

local function Entries()
	local entries = {}
	if tab == "route" then
		local route = ns.Route()
		for index, step in ipairs(route.steps) do
			local current = index == route.current
			-- (its whole words under the mouse: a long one is cut in its row)
			local tip = { ns.StepWords(step), U.MapName(step.map) or "" }
			if step.quest and ns.CanOpenQuest() then tip[3] = L.STEP_QUEST_TIP end
			entries[#entries + 1] = { name = StepName(index, step), place = step, index = index, current = current,
				color = current and Skin.COLORS.gold or step.done and Skin.COLORS.muted or nil, tip = tip }
			-- (the way to the step followed: its legs, the one followed in gold)
			if index == route.current and route.legs then
				for at, leg in ipairs(route.legs) do
					entries[#entries + 1] = { name = ns.LegWords(leg), leg = leg, at = at, index = index, indent = 14,
						color = at == (route.leg or 1) and Skin.COLORS.gold or Skin.COLORS.soft, place = step }
				end
			end
		end
	else
		-- (in the order made, or the last used first; one not used for long greyed, never removed by itself)
		for index, note in ipairs(ns.SortedNotes()) do
			entries[#entries + 1] = { name = ns.NoteIconMarkup(note.icon) .. " " .. note.title, place = note, index = index,
				color = ns.NoteOld(note) and Skin.COLORS.muted or nil,
				tip = { note.title, U.MapName(note.map) or "", L[ns.NoteIconSpec(note.icon).word] } }
		end
	end
	return entries
end

-- A row's choices (its "⋯", its right click): a step's card, a note's own card.
local function More(entry, owner)
	if tab == "route" then return ns.StepCard(owner or window, entry.index, entry.leg) end
	local note = entry.place
	ns.NoteCard(note.map, note.x, note.y, note)
end

-- The nearest services: a button for each kind known on your continent, in a row, as many as the row holds (none:
-- a word on them).
local function DrawNearest()
	local last
	-- (its width as laid out; before the first layout, the window's)
	local width = nearest:GetWidth() or 0
	local room = (width > 0 and width or nearest.full) - U.Measure(nearest.label, "GetStringWidth", 60) - 6
	for _, kind in ipairs(ns.NEAREST_ORDER) do
		local button = nearest.buttons[kind]
		button.place, button.distance = ns.NearestService(kind)
		button:ClearAllPoints()
		local fits = button.place ~= nil and room >= button:GetWidth()
		if fits then
			button:SetPoint("LEFT", last or nearest.label, "RIGHT", last and 4 or 6, 0)
			room = room - button:GetWidth() - 4
			last = button
		end
		button:SetShown(fits)
	end
	nearest.empty:SetShown(last == nil)
end

local function Draw()
	if not (window and window:IsShown()) then return end
	DrawNearest()
	local entries = Entries()
	local offset = list:Clamp(#entries)
	for index, row in ipairs(list.rows) do
		local entry = entries[offset + index]
		-- (the "⋯" under the mouse, as every row of Wanderer)
		if not row.menu then row.menu = Skin.RowMore(row, function(owner) if owner.entry then More(owner.entry, owner) end end) end
		if entry and entry.leg then
			row:Fill(entry, false, { place = ns.LegKind(entry.leg), distance = "" })
		elseif entry then
			row:Fill(entry, entry.current, { place = U.MapName(entry.place.map) or "", distance = Distance(entry.place) })
		else
			row:Fill(nil)
		end
	end
	list.empty:SetText(tab == "route" and L.ROUTE_EMPTY or L.NOTES_EMPTY)
	list.empty:SetShown(#entries == 0)
	clear:SetShown(tab == "route" and #entries > 0)
	here:SetShown(tab == "notes")
	kept:SetShown(tab == "route")
	sorter:SetLabel(ns.DB().noteSort == "used" and L.SORT_USED or L.SORT_ADDED)
	sorter:SetShown(tab == "notes" and #entries > 1)
	removeSome:SetShown(tab == "notes" and #entries > 0)
	tabs:SetBadge("route", #ns.Route().steps, "gold")
	tabs:SetBadge("notes", #ns.Notes(), "grey")
end

local function ShowTab(key)
	tab = key
	tabs:Select(key)
	list.offset = 0
	Draw()
end

-- A note where you stand (the notes' tab, the key): the note card there, its name and its sign to choose.
local function NoteHere()
	local map, x, y = U.HereOnMap()
	if not map then return W.Print(L.HERE_UNKNOWN) end
	ns.NoteCard(map, x, y)
end

local function Create()
	window = Skin.CreateWindow("WandererMapsWindow", "MEDIUM")
	Skin.Sounds(window, Skin.SOUNDS.open, Skin.SOUNDS.close)
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 40 }, "mapsPos")
	local _, title, margin = Skin.Header(window, "Wanderer", L.TITLE, { settings = "ext:maps" })
	tabs = Skin.Tabs(window, { { "route", L.TAB_ROUTE }, { "notes", L.TAB_NOTES } }, ShowTab)
	tabs:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0)
	tabs:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	list = Skin.Table(window, {
		width = WIDTH - margin * 2, rows = ROWS, icon = false, nameTitle = L.COL_PLACE,
		columns = {
			{ key = "place", title = L.COL_ZONE, width = 130, justify = "LEFT" },
			{ key = "distance", title = L.COL_DISTANCE, width = 80 },
			-- (room for the "⋯" under the mouse, at the row's end)
			{ key = "pad", title = "", width = Skin.ROW_MORE },
		},
		onClick = function(entry, mouse)
			if mouse == "RightButton" then
				for _, row in ipairs(list.rows) do
					if row.entry == entry then return More(entry, row) end
				end
				return More(entry)
			end
			if entry.leg then return end
			if tab == "route" then ns.FollowStep(entry.index) else ns.GoTo(entry.place) end
		end,
		onDraw = Draw,
	})
	list:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -10)
	-- (the foot: one action for the tab shown, in the same place)
	here = Skin.Button(window, L.HERE, NoteHere)
	here:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	Skin.Tooltip(here, L.HERE_DESC)
	clear = Skin.Button(window, L.CLEAR, function() ns.ClearAsked() end)
	clear:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin)
	-- (on the right of the foot: the routes kept; the notes' order and their removal by sign or zone)
	kept = Skin.Button(window, L.KEPT_TITLE, function(self) ns.KeptRoutesCard(self) end)
	kept:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	Skin.Tooltip(kept, L.KEPT_DESC)
	removeSome = Skin.Button(window, L.REMOVE_NOTES, function(self) ns.RemoveNotesCard(self) end)
	removeSome:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -margin, margin)
	Skin.Tooltip(removeSome, L.REMOVE_NOTES_DESC)
	sorter = Skin.SmallButton(window, L.SORT_ADDED, function()
		local db = ns.DB()
		db.noteSort = db.noteSort ~= "used" and "used" or nil
		list.offset = 0
		Draw()
	end, L.SORT_TIP, here:GetHeight())
	sorter:SetPoint("RIGHT", removeSome, "LEFT", -8, 0)
	nearest = CreateFrame("Frame", nil, window)
	nearest:SetHeight(20)
	nearest.full = WIDTH - margin * 2
	nearest:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", margin, margin + here:GetHeight() + 8)
	nearest:SetPoint("RIGHT", window, "RIGHT", -margin, 0)
	nearest.label = Skin.Text(nearest, "GameTooltipTextSmall", "muted")
	nearest.label:SetPoint("LEFT")
	nearest.label:SetText(L.NEAREST)
	nearest.empty = Skin.Text(nearest, "GameTooltipTextSmall", "muted")
	nearest.empty:SetPoint("LEFT", nearest.label, "RIGHT", 6, 0)
	nearest.empty:SetPoint("RIGHT", nearest, "RIGHT", 0, 0)
	nearest.empty:SetJustifyH("LEFT")
	if nearest.empty.SetWordWrap then nearest.empty:SetWordWrap(false) end
	nearest.empty:SetText(L.NEAREST_NONE)
	nearest.buttons = {}
	for _, kind in ipairs(ns.NEAREST_ORDER) do
		local spec = ns.SERVICE_KINDS[kind]
		local button = Skin.SmallButton(nearest, "|T" .. spec.file .. ":14:14|t " .. L[spec.word], function(self)
			if self.place then ns.GoTo(self.place) end
		end, function(self)
			if not self.place then return nil end
			return { self.place.title, (U.MapName(self.place.map) or "") .. U.SEPARATOR .. L.DISTANCE:format(math.floor(self.distance + 0.5)),
				ns.TipLine(L.SERVICE_PIN_TIP, "blue") }
		end, 20)
		button:Fit()
		button:Hide()
		nearest.buttons[kind] = button
	end
	-- (its foot full of buttons: the "?" in the heading)
	Skin.Help(window, L.HELP_TIP .. "\n" .. L.HELP_GPS, "HEADING")
	window:SetSize(WIDTH, margin * 2 + 30 + 30 + 10 + list:GetHeight() + 12 + 28 + 30)
	window:HookScript("OnShow", function(self)
		self:SetScale(Skin.FitScale(self))
		tabs:Layout()
		ShowTab(tab)
	end)
	window:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < LOOK_EVERY then return end
		since = 0
		Draw()
	end)
	Skin.Get(window):Layout()
end

-- Maps off: said, no window (a route drawn with nothing behind it reads as a bug); an open window can still be closed.
local function Off()
	local settings = ns.Settings()
	if settings and settings.enabled then return false end
	W.Print(L.EXT_TURNED_OFF:format(L.ADDON))
	return true
end

function ns.Toggle()
	if window and window:IsShown() then return window:Hide() end
	if Off() then return end
	if not window then Create() end
	window:Show()
end

function ns.Open()
	if Off() then return end
	if not window then Create() end
	window:Show()
end

-- Init -----------------------------------------------------------------------------------------------------

BINDING_HEADER_WANDERERMAPS = "Wanderer Maps"
BINDING_NAME_WANDERERMAPS_TOGGLE = L.BINDING_TOGGLE
BINDING_NAME_WANDERERMAPS_HERE = L.BINDING_HERE
-- (the keys do nothing until Wanderer Maps is set up: an older Wanderer leaves it asleep)
function WandererMaps_Toggle() if ns.ready then ns.Toggle() end end
-- (Wanderer Maps off: said, no note card)
function WandererMaps_Here() if ns.ready and not Off() then NoteHere() end end

-- A quest taken or handed in (Wanderer Quests' steps): its steps ticked, quietly (Shift held: left as they are).
local function QuestDone(event, ...)
	if U.IsSkipping and U.IsSkipping() then return end
	local first, second = ...
	local id = tonumber(second) or tonumber(first)
	if event == "QUEST_TURNED_IN" then
		ns.TickQuest(tonumber(first), { take = true, objective = true, handin = true })
	elseif id then
		ns.TickQuest(id, { take = true })
	end
end

function ns.Init()
	if not (W and W.RegisterExtension) then return end
	-- (API 15: the kit's "⋯" and cards, its progress lines, the screen-fitted scale, Util.AfterFight)
	if (W.API or 1) < 16 then return W.Print(L.NEEDS_WANDERER) end
	W.RegisterExtension({
		key = "maps",
		addon = ADDON,
		slash = "/wmaps",
		title = L.ADDON,
		news = L.NEWS_LINES,
		defaults = { enabled = true, followGame = true, gps = true, boats = true, gamePin = true, minimap = true, arrow = true, arrowQuiet = false,
			world = true, unexplored = true, explored = true, zoneFacts = true, services = false, flightNotice = false,
			hearth = false, flightLine = true, corpse = true, noteRadius = 250 },
		ranges = { ["maps.noteRadius"] = { 25, 250, 25 } },
		-- (the flight line names the destination: Wanderer's travel card leaves it the title, keeps the fade and the camera)
		takes = { flightCard = function()
			local settings = ns.Settings()
			return settings and settings.enabled and settings.flightLine and true or false
		end },
		launcher = { label = L.TITLE, open = function() ns.Toggle() end },
		refresh = function()
			ns.RefreshFlightNotice()
			ns.RefreshFlightLine()
			ns.Replan()
		end,
		-- (the suite's rule: a master switch first where something runs without the window (here the arrow, the
		-- pins, the flight line), then the window's Open; what guides you on the way; the route, the world map, the flights)
		options = function(o)
			local enabled = o.Checkbox("maps", "enabled", L.ENABLE, L.ENABLE_DESC, ns.Changed)
			local on = o.IsOn("maps", "enabled")
			local function Check(key, label, desc, refresh) return o.Under(o.Checkbox("maps", key, label, desc, refresh), enabled, on) end
			o.Under(o.Button(L.TITLE, L.OPEN, L.OPEN_DESC, function()
				o.CloseSettings()
				ns.Open()
			end), enabled, on)

			o.Header(L.SECTION_GUIDANCE)
			-- (the arrow and what it follows; another addon's arrow there: ours left to it)
			local arrowRow = Check("arrow", L.ARROW_OPTION, L.ARROW_OPTION_DESC, ns.Changed)
			o.Yield(arrowRow, "arrow")
			local arrowOn = o.IsOn("maps", "arrow")
			o.Under(o.Checkbox("maps", "arrowQuiet", L.ARROW_QUIET, L.ARROW_QUIET_DESC), arrowRow, arrowOn)
			o.Under(o.Checkbox("maps", "followGame", L.FOLLOW_GAME, L.FOLLOW_GAME_DESC, ns.Changed), arrowRow, arrowOn)
			o.Under(o.Checkbox("maps", "corpse", L.CORPSE_OPTION, L.CORPSE_OPTION_DESC, ns.RefreshArrow), arrowRow, arrowOn)
			Check("gamePin", L.GAME_PIN_OPTION, L.GAME_PIN_OPTION_DESC, ns.Changed)
			local minimapRow = Check("minimap", L.MINIMAP, L.MINIMAP_DESC, ns.Changed)
			if o.Slider then
				o.Under(o.Slider("MAPS_NOTE_RADIUS", L.NOTE_RADIUS, "maps.noteRadius", L.DISTANCE, ns.RefreshMinimap), minimapRow,
					o.IsOn("maps", "minimap"))
			end

			-- (boats and the hearthstone only matter to the guided route)
			o.Header(L.SECTION_ROUTE)
			local gps = Check("gps", L.GPS, L.GPS_DESC, ns.Replan)
			local gpsOn = o.IsOn("maps", "gps")
			o.Under(o.Checkbox("maps", "boats", L.BOATS, L.BOATS_DESC, ns.Replan), gps, gpsOn)
			o.Under(o.Checkbox("maps", "hearth", L.HEARTH_OPTION, L.HEARTH_OPTION_DESC, ns.Replan), gps, gpsOn)

			o.Header(L.SECTION_WORLD_MAP)
			Check("world", L.WORLD_OPTION, L.WORLD_OPTION_DESC, ns.RefreshWorld)
			Check("unexplored", L.UNEXPLORED_OPTION, L.UNEXPLORED_OPTION_DESC, ns.RefreshWorld)
			Check("explored", L.EXPLORED_OPTION, L.EXPLORED_OPTION_DESC, ns.RefreshWorld)
			Check("zoneFacts", L.ZONE_FACTS_OPTION, L.ZONE_FACTS_OPTION_DESC, ns.RefreshWorld)
			Check("services", L.SERVICES_OPTION, L.SERVICES_OPTION_DESC, ns.RefreshServices)

			o.Header(L.SECTION_FLIGHTS)
			Check("flightLine", L.FLIGHT_LINE_OPTION, L.FLIGHT_LINE_OPTION_DESC, ns.RefreshFlightLine)
			Check("flightNotice", L.FLIGHT_NOTICE_OPTION, L.FLIGHT_NOTICE_OPTION_DESC, ns.RefreshFlightNotice)
		end,
	})
	SLASH_WANDERERMAPS1 = "/wmaps"
	SlashCmdList.WANDERERMAPS = function() ns.Toggle() end
	ns.OnChanged(Draw)
	ns.InitTransport()
	ns.InitPins()
	ns.InitServices()
	ns.InitFlights()
	ns.InitFlightLine()
	ns.InitWorld()
	ns.InitArrow()
	ns.InitMinimap()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED" }) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", function(_, event, ...) QuestDone(event, ...) end)
	-- For the other addons (Wanderer Quests...): a place to go to (asked first when it would let a route of
	-- several steps go: true all the same), a step more (false and why: "full", "here", "off", each said), a note, a map
	-- link in the chat's box. Each place may say why it goes there: info { kind "take" / "handin" / "objective",
	-- quest, label }.
	-- (Wanderer Maps turned off: no route behind nothing shown; the way is the game's own pin, a step is refused and said)
	local function On()
		local settings = ns.Settings()
		return settings and settings.enabled and true or false
	end
	_G.WandererMaps = {
		Go = function(map, x, y, title, info)
			if not On() then return U.Pin(map, x, y) and true or false end
			return ns.GoTo({ map = map, x = x, y = y, title = title }, info)
		end,
		AddStep = function(map, x, y, title, info)
			if not On() then
				W.Print(L.EXT_TURNED_OFF:format(L.ADDON))
				return false, "off"
			end
			local step, why = ns.AddStep(map, x, y, title, info)
			return step ~= nil, why
		end,
		AddNote = function(map, x, y, title, icon) return ns.AddNote(map, x, y, title, icon) ~= nil end,
		ChatLink = function(map, x, y, title) return ns.ChatLink(map, x, y, title) end,
		Clear = function() ns.ClearRoute() end,
		Toggle = function() ns.Toggle() end,
		-- A whole route from places ({ { map, x, y, title } }), ordered from where you stand, each the nearest
		-- from the last (a sensible tour); a route already there is asked about first. How many steps it made
		-- (-1: asked, or Wanderer Maps off and said).
		-- (Wanderer Maps off: no route made behind nothing shown, said; -1 as when asked)
		Route = function(places)
			if not On() then
				W.Print(L.EXT_TURNED_OFF:format(L.ADDON))
				return -1
			end
			return ns.RouteFrom(places)
		end,
		Steps = function() return #ns.Route().steps end,
	}
	ns.ready = true
end

if W and W.WhenLoaded then W.WhenLoaded(ADDON, ns.Init) elseif W and W.Print then W.Print(L.NEEDS_WANDERER) end
