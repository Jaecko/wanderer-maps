local _, ns = ...
local L = ns.L

-- The flight under way: the way chosen at the flight master (where you take off, each stop, where you land),
-- then, while you fly, the destination's name over a slim line: where you took off and the time left under the
-- name, a small dot for each stop between, your dot moving along. (While it is shown, Wanderer's own travel card
-- leaves it the destination: the fade and the camera stay Wanderer's.) Times come from your own flights: each stretch between two stops, timed as
-- you fly it, the last few kept for the account (the world's, not a character's), their middle one used.
-- Before, a guess from the distance (marked "~"), refined by where you are along the way. The flight map's
-- tooltips say the time too. Shown on flights only (an option, on); moved in Wanderer's placing mode.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local SPEED = 32 -- yards a second, a flight's
local WINDING = 1.12 -- a flight's way is longer than the straight line between its stops
local UNKNOWN_HOP = 60 -- seconds guessed for a stretch whose ends are not placed
local KEEP = 5 -- flights kept for each stretch
local SHORTEST, LONGEST = 5, 1800 -- seconds: a stretch timed outside these is not kept
local PASS_NEAR = 70 -- yards: a stop flown over
local PASS_AWAY = 15 -- yards beyond the closest: the stop is behind
local GUESS_FROM = 0.12 -- share of a stretch flown before its time is guessed from your pace
local BOARD_WAIT = 10 -- seconds a chosen flight waits for the take off
local RESTORE_FOR = 1800 -- seconds: a flight taken up again after a reload
local STEP = 0.1 -- seconds between two looks
local GLIDE = 3 -- your dot catches up with its place (share of the gap a second)
local WIDTH, HEIGHT, SIDE = 320, 66, 16
local LINE_Y = -52
local DOT_END, DOT_STOP, DOT_YOU = 9, 7, 12

local bar, driver
local pending -- the way chosen at the flight master, waiting for the take off: { stops, at }
local flight -- the flight under way (see Board)
local since = 0

local function Shown()
	local settings = ns.Settings()
	return settings and settings.enabled and settings.flightLine and true or false
end

-- Times learned --------------------------------------------------------------------------------------------

local function Times()
	local data = ns.Data()
	data.flightTimes = type(data.flightTimes) == "table" and data.flightTimes or {}
	return data.flightTimes
end

-- A stretch's key: from one flight node to the next (each way its own: the paths differ).
function ns.HopKey(from, to)
	if not (from and to) then return nil end
	return tostring(from) .. ">" .. tostring(to)
end

-- The seconds a stretch takes, as your flights said (the middle one of the last few), nil before.
function ns.HopSeconds(from, to)
	local key = ns.HopKey(from, to)
	local list = key and Times()[key]
	if type(list) ~= "table" then return nil end
	local sorted = {}
	for _, seconds in ipairs(list) do
		if type(seconds) == "number" then sorted[#sorted + 1] = seconds end
	end
	local count = #sorted
	if count == 0 then return nil end
	table.sort(sorted)
	if count % 2 == 1 then return sorted[(count + 1) / 2] end
	return (sorted[count / 2] + sorted[count / 2 + 1]) / 2
end

-- A stretch flown: its time kept (the oldest let go past a few). True when kept.
function ns.LearnHop(from, to, seconds)
	local key = ns.HopKey(from, to)
	if not key or type(seconds) ~= "number" or seconds < SHORTEST or seconds > LONGEST then return false end
	local times = Times()
	local list = type(times[key]) == "table" and times[key] or {}
	list[#list + 1] = math.floor(seconds + 0.5)
	while #list > KEEP do table.remove(list, 1) end
	times[key] = list
	return true
end

-- The way -------------------------------------------------------------------------------------------------

local masters -- node id -> its line of ns.FLIGHT_MASTERS
-- A flight node in the world: x, y, continent (Wanderer Maps' world), nil when unknown.
local function NodePlace(id)
	if not id then return nil end
	if not masters then
		masters = {}
		for _, node in ipairs(ns.FLIGHT_MASTERS or {}) do masters[node[1]] = node end
	end
	local node = masters[id]
	if node then return node[4], node[3], node[2] end
	local known = ns.Data().taxi[id]
	if type(known) == "table" and known.map then return ns.WorldOf(known.map, known.x, known.y) end
	return nil
end

local function Stop(slot, idOf)
	local full = slot and Clean(Safe(TaxiNodeName, slot))
	local id = slot and idOf[slot]
	local wx, wy, instance = NodePlace(id)
	return { id = id, name = full and full:gsub(",.*$", "") or "?", full = full, wx = wx, wy = wy, instance = instance }
end

-- The way to a node of the flight master's map (its slot): its stops, from here to there.
function ns.ReadFlight(slot)
	local idOf = {}
	local map = Clean(Safe(GetTaxiMapID))
	if map and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
		for _, node in ipairs(Safe(C_TaxiMap.GetAllTaxiNodes, map) or {}) do
			local at, id = type(node) == "table" and Clean(node.slotIndex), type(node) == "table" and Clean(node.nodeID)
			if at and id then idOf[at] = id end
		end
	end
	local stops = {}
	local hops = Clean(Safe(GetNumRoutes, slot)) or 0
	if hops > 0 then
		stops[1] = Stop(Clean(Safe(TaxiGetNodeSlot, slot, 1, true)), idOf)
		for hop = 1, hops do stops[hop + 1] = Stop(Clean(Safe(TaxiGetNodeSlot, slot, hop, false)), idOf) end
	else
		-- (the game says nothing of the way: from the node you stand at, straight)
		local here
		for index = 1, Clean(Safe(NumTaxiNodes)) or 0 do
			if Clean(Safe(TaxiNodeGetType, index)) == "CURRENT" then here = index end
		end
		stops = { Stop(here, idOf), Stop(slot, idOf) }
	end
	return stops
end

local function Distance(a, b)
	if not (a.wx and b.wx) or a.instance ~= b.instance then return nil end
	return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
end

-- A flight's plan from its stops: each stretch { seconds, learned }, where each stop falls along the line
-- (0 to 1), the whole time, and whether some of it is guessed.
function ns.FlightPlan(stops)
	local hops, at, total, guessed = {}, { 0 }, 0, false
	for index = 1, #stops - 1 do
		local a, b = stops[index], stops[index + 1]
		local seconds = ns.HopSeconds(a.id, b.id)
		local learned = seconds ~= nil
		if not learned then
			local length = Distance(a, b)
			seconds = length and length * WINDING / SPEED or UNKNOWN_HOP
			guessed = true
		end
		hops[index] = { seconds = math.max(1, seconds), learned = learned }
		total = total + hops[index].seconds
	end
	local sum = 0
	for index, hop in ipairs(hops) do
		sum = sum + hop.seconds
		at[index + 1] = total > 0 and sum / total or 1
	end
	return { hops = hops, at = at, total = total, guessed = guessed }
end

-- The flight -------------------------------------------------------------------------------------------------

local function Keep()
	if not flight then
		ns.DB().flight = nil
		return
	end
	-- (kept for this character through a reload: its start in the world's time)
	ns.DB().flight = { stops = flight.stops, start = time() - (GetTime() - flight.start), hop = flight.hop,
		hopStart = flight.hopStart, passed = flight.passed }
end

-- On the way: the stops, their plan, from the take off (elapsed: seconds flown already, after a reload).
local function Board(stops, elapsed, kept)
	if not (type(stops) == "table" and #stops >= 2) then return end
	local plan = ns.FlightPlan(stops)
	elapsed = elapsed or 0
	flight = { stops = stops, plan = plan, start = GetTime() - elapsed, hop = 1, hopStart = 0, passed = { 0 }, shown = 0 }
	if kept then
		flight.hop = math.max(1, math.min(#stops - 1, tonumber(kept.hop) or 1))
		flight.hopStart = tonumber(kept.hopStart) or 0
		flight.passed = type(kept.passed) == "table" and kept.passed or { 0 }
	end
	Keep()
end

-- Where the flight stands now (elapsed seconds, your place): the share of the line flown, the seconds left,
-- whether they are guessed, the seconds to the next stop. Passing a stop moves the flight to its next stretch.
function ns.FollowFlight(state, elapsed, px, py, here)
	local stops, plan = state.stops, state.plan
	local last = #stops - 1
	-- A stop flown over: the closest you came, once you are going away from it.
	local hop = state.hop
	local ahead = stops[hop + 1]
	if hop < last then
		if px and ahead.wx and (here == nil or here == ahead.instance) then
			local distance = math.sqrt((px - ahead.wx) ^ 2 + (py - ahead.wy) ^ 2)
			if distance <= PASS_NEAR and (not state.near or distance < state.near.distance) then
				state.near = { distance = distance, at = elapsed }
			end
			if state.near and distance > state.near.distance + PASS_AWAY then
				state.passed[hop + 1] = state.near.at
				state.hop, state.hopStart, state.near = hop + 1, state.near.at, nil
				state.changed = true
			end
		else
			-- (your place or the stop's unknown: the stops passed by the plan's time, never learned)
			local done = state.hopStart + plan.hops[hop].seconds
			if elapsed >= done then
				state.hop, state.hopStart = hop + 1, done
				state.changed = true
			end
		end
		-- (a stop never seen close: far beyond its time, passed all the same, not learned)
		if state.hop == hop and elapsed - state.hopStart > plan.hops[hop].seconds * 2 + 30 then
			state.passed[hop + 1] = nil
			state.hop, state.hopStart, state.near = hop + 1, elapsed, nil
			state.changed = true
		end
	end
	hop = state.hop
	local from, to, stretch = stops[hop], stops[hop + 1], plan.hops[hop]
	local into = math.max(0, elapsed - state.hopStart)
	-- Your share of this stretch by your place: you projected on the straight line between its stops.
	local share
	if px and from.wx and to.wx and (here == nil or here == to.instance) then
		local dx, dy = to.wx - from.wx, to.wy - from.wy
		local length = dx * dx + dy * dy
		if length > 0 then share = math.max(0, math.min(1, ((px - from.wx) * dx + (py - from.wy) * dy) / length)) end
	end
	local nextLeft, guessed
	if stretch.learned then
		nextLeft = math.max(0, stretch.seconds - into)
	elseif share and share >= GUESS_FROM and into > 0 then
		nextLeft, guessed = into * (1 - share) / share, true
	else
		nextLeft, guessed = math.max(0, stretch.seconds - into), true
	end
	local left = nextLeft
	for index = hop + 1, last do
		left = left + plan.hops[index].seconds
		guessed = guessed or not plan.hops[index].learned
	end
	-- Your dot: learned, by the time; guessed, by your place (by the time without one).
	local within = (stretch.learned or not share) and math.min(1, into / stretch.seconds) or share
	local where = plan.at[hop] + (plan.at[hop + 1] - plan.at[hop]) * within
	return where, left, guessed and true or false, nextLeft
end

-- Landed: each stretch whose two ends were seen, learned.
local function Land()
	local done = flight
	flight = nil
	Keep()
	if bar then bar:Hide() end
	if not done then return end
	local elapsed = GetTime() - done.start
	local stops = done.stops
	done.passed[#stops] = elapsed
	for index = 1, #stops - 1 do
		local a, b = done.passed[index], done.passed[index + 1]
		if a and b then ns.LearnHop(stops[index].id, stops[index + 1].id, b - a) end
	end
end

-- Coming down early (the game's "land at the next stop"): the way ends at the next stop.
local function LandEarly()
	if not flight then return end
	local stops = {}
	for index = 1, flight.hop + 1 do stops[index] = flight.stops[index] end
	flight.stops, flight.plan = stops, ns.FlightPlan(stops)
	flight.shown = math.min(flight.shown, flight.plan.at[flight.hop])
	Keep()
	if bar and bar:IsShown() then bar:Lay() end
end

-- The line on the screen ----------------------------------------------------------------------------------

local function Dot(size, layer)
	local dot = Skin.Glyph(bar, "dot", size, layer or "ARTWORK")
	return dot
end

local function Paint(dot, passed)
	local c = passed and Skin.COLORS.gold or Skin.COLORS.muted
	dot:SetVertexColor(c[1], c[2], c[3])
end

local function Span() return WIDTH - SIDE * 2 end

-- The line laid for the flight: its ends' names, a dot for each stop where it falls.
local function Lay(self)
	if not flight then return end
	local stops, plan = flight.stops, flight.plan
	self.from:SetText(stops[1].name)
	self.to:SetText(stops[#stops].name)
	self.stops = self.stops or {}
	for index = 2, #stops - 1 do
		local dot = self.stops[index] or Dot(DOT_STOP)
		self.stops[index] = dot
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", self, "TOPLEFT", SIDE + Span() * plan.at[index], LINE_Y)
		dot:Show()
	end
	for index, dot in pairs(self.stops) do
		if index < 2 or index > #stops - 1 then dot:Hide() end
	end
	self.drawnTime = nil
end

local function Draw(self, elapsedFrame)
	if not flight then return end
	local px, py, here = ns.Here()
	local where, left, guessed = ns.FollowFlight(flight, GetTime() - flight.start, px, py, here)
	if flight.changed then
		flight.changed = nil
		Keep()
	end
	-- (never backwards; it glides to its place)
	if where > flight.shown then
		flight.shown = flight.shown + (where - flight.shown) * math.min(1, GLIDE * (elapsedFrame or STEP))
		if where - flight.shown < 0.002 then flight.shown = where end
	end
	local x = SIDE + Span() * flight.shown
	self.you:ClearAllPoints()
	self.you:SetPoint("CENTER", self, "TOPLEFT", x, LINE_Y)
	self.flown:SetWidth(math.max(1, x - SIDE))
	for index, dot in pairs(self.stops or {}) do
		if dot:IsShown() then Paint(dot, flight.plan.at[index] <= flight.shown + 0.001) end
	end
	Paint(self.landing, flight.shown >= 0.999)
	local words = ns.Clock(left)
	if guessed then words = "~" .. words end
	if words ~= self.drawnTime then
		self.drawnTime = words
		self.time:SetText(words)
	end
end

-- The bar's tooltip (the kit's): where to, from where, the next stop, the time left (guessed: said).
local function TipLines()
	if not flight then return nil end
	local stops = flight.stops
	local px, py, here = ns.Here()
	local _, left, guessed, nextLeft = ns.FollowFlight(flight, GetTime() - flight.start, px, py, here)
	local lines = { stops[#stops].full or stops[#stops].name, ns.TipLine(L.FLIGHT_FROM:format(stops[1].full or stops[1].name)) }
	local ahead = stops[flight.hop + 1]
	if flight.hop + 1 < #stops then
		lines[#lines + 1] = ns.TipLine(L.FLIGHT_NEXT:format(ahead.name, (guessed and "~" or "") .. ns.Clock(nextLeft)))
	end
	lines[#lines + 1] = ns.TipLine(L.FLIGHT_TIME:format((guessed and "~" or "") .. ns.Clock(left)))
	if guessed then lines[#lines + 1] = ns.TipLine(L.FLIGHT_GUESSED, "blue") end
	return lines
end

local function Create()
	bar = Skin.CreateWindow("WandererMapsFlight", "MEDIUM", nil, true)
	bar:SetSize(WIDTH, HEIGHT)
	bar:SetClampedToScreen(true)
	bar:EnableMouse(true)
	if W.Placeable then
		W.Placeable({ key = "mapsFlight", label = function() return L.FLIGHT_LINE_PLACE end, frame = bar,
			scale = function() return Skin.Scale() end, default = { "TOP", "TOP", 0, -236 }, enabled = Shown })
	end
	if not (W.PlaceApply and W.PlaceApply("mapsFlight", bar)) then bar:SetPoint("TOP", UIParent, "TOP", 0, -236) end
	-- The destination, its title; under it, where you took off (left) and the time left (right).
	bar.to = Skin.Text(bar, "GameFontNormalLarge", "gold")
	bar.to:SetPoint("TOP", bar, "TOP", 0, -8)
	bar.to:SetWidth(WIDTH - SIDE * 2)
	bar.to:SetJustifyH("CENTER")
	bar.from = Skin.Text(bar, "GameTooltipTextSmall", "soft")
	bar.from:SetPoint("TOPLEFT", bar, "TOPLEFT", SIDE - 4, -32)
	bar.from:SetWidth(Span() - 70)
	bar.from:SetJustifyH("LEFT")
	for _, text in ipairs({ bar.from, bar.to }) do
		if text.SetWordWrap then text:SetWordWrap(false) end
	end
	bar.time = Skin.Text(bar, "GameTooltipTextSmall", "text")
	bar.time:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -(SIDE - 4), -32)
	bar.time:SetJustifyH("RIGHT")
	-- The line: thin, the part flown brighter.
	local line = bar:CreateTexture(nil, "BORDER")
	line:SetColorTexture(1, 0.82, 0, 0.18)
	line:SetHeight(1)
	line:SetPoint("LEFT", bar, "TOPLEFT", SIDE, LINE_Y)
	line:SetPoint("RIGHT", bar, "TOPRIGHT", -SIDE, LINE_Y)
	bar.flown = bar:CreateTexture(nil, "ARTWORK", nil, -1)
	bar.flown:SetColorTexture(1, 0.82, 0, 0.6)
	bar.flown:SetHeight(2)
	bar.flown:SetPoint("LEFT", bar, "TOPLEFT", SIDE, LINE_Y)
	bar.takeoff = Dot(DOT_END)
	bar.takeoff:SetPoint("CENTER", bar, "TOPLEFT", SIDE, LINE_Y)
	Paint(bar.takeoff, true)
	bar.landing = Dot(DOT_END)
	bar.landing:SetPoint("CENTER", bar, "TOPRIGHT", -SIDE, LINE_Y)
	bar.you = Dot(DOT_YOU, "OVERLAY")
	Paint(bar.you, true)
	bar.Lay = Lay
	Skin.Tooltip(bar, TipLines, "ANCHOR_BOTTOM")
	bar:HookScript("OnShow", function(self)
		self:SetScale(Skin.Scale())
		Skin.FadeIn(self)
		self:Lay()
		Draw(self, 1)
	end)
end

-- Shown while a flight is under way (the option on), hidden otherwise.
local function ShowBar()
	if not (flight and Shown()) then
		if bar then bar:Hide() end
		return
	end
	if not bar then Create() end
	if bar:IsShown() then bar:Lay() else bar:Show() end
end

-- The look: a flight waited for, followed, landed.
local function Look(_, elapsed)
	since = since + elapsed
	if since < STEP then return end
	local frame = since
	since = 0
	local onTaxi = Clean(Safe(UnitOnTaxi, "player"))
	if flight then
		if not onTaxi then return Land() end
		if bar and bar:IsShown() then Draw(bar, frame) end
	elseif pending then
		if onTaxi then
			local stops = pending.stops
			pending = nil
			Board(stops)
			ShowBar()
		elseif GetTime() - pending.at > BOARD_WAIT then
			pending = nil
		end
	end
	if not (flight or pending) then driver:Hide() end
end

local function Wake()
	since = STEP
	driver:Show()
end

-- Chosen at the flight master: the way read now, while its map is open.
local function OnTakeTaxi(slot)
	local settings = ns.Settings()
	if not (settings and settings.enabled) then return end
	local stops = ns.ReadFlight(slot)
	if #stops < 2 then return end
	pending = { stops = stops, at = GetTime() }
	Wake()
end

-- Back in the world: a flight kept from before a reload taken up again (still flying), else let go.
local function Resume()
	if flight then return end
	local kept = ns.DB().flight
	if not Clean(Safe(UnitOnTaxi, "player")) then
		ns.DB().flight = nil
		return
	end
	if type(kept) ~= "table" or type(kept.stops) ~= "table" or not tonumber(kept.start) then return end
	local elapsed = time() - kept.start
	if elapsed < 0 or elapsed > RESTORE_FOR then return end
	Board(kept.stops, elapsed, kept)
	ShowBar()
	Wake()
end

-- The flight map's tooltips: the time to the node under the mouse.
local function AddMapTime(slot)
	if not (Shown() and slot) or Clean(Safe(TaxiNodeGetType, slot)) ~= "REACHABLE" then return end
	local stops = ns.ReadFlight(slot)
	if #stops < 2 then return end
	local plan = ns.FlightPlan(stops)
	local c = Skin.COLORS.text
	GameTooltip:AddLine(L.FLIGHT_TIME:format((plan.guessed and "~" or "") .. ns.Clock(plan.total)), c[1], c[2], c[3])
	GameTooltip:Show()
end

local mapHooked = false
local function HookFlightMap()
	local mixin = _G.FlightMap_FlightPointPinMixin
	if mapHooked or not (mixin and mixin.OnMouseEnter) then return end
	mapHooked = true
	hooksecurefunc(mixin, "OnMouseEnter", function(pin)
		local data = type(pin) == "table" and pin.taxiNodeData
		if type(data) == "table" then AddMapTime(Clean(data.slotIndex)) end
	end)
end

-- The option changed: shown or hidden now.
function ns.RefreshFlightLine() ShowBar() end

-- (tests: the flight under way)
function ns.FlightNow() return flight end

function ns.InitFlightLine()
	driver = CreateFrame("Frame")
	driver:Hide()
	driver:SetScript("OnUpdate", Look)
	if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", OnTakeTaxi) end
	if TaxiRequestEarlyLanding then hooksecurefunc("TaxiRequestEarlyLanding", LandEarly) end
	if TaxiNodeOnButtonEnter then
		hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
			if type(button) == "table" and button.GetID then AddMapTime(Clean(Safe(button.GetID, button))) end
		end)
	end
	HookFlightMap()
	local events = CreateFrame("Frame")
	-- (the flight map loaded later: heard until it is hooked, then no more)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_LOST", not mapHooked and "ADDON_LOADED" or nil }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(self, event, name)
		if event == "ADDON_LOADED" then
			if name == "Blizzard_FlightMap" then HookFlightMap() end
			if mapHooked then self:UnregisterEvent("ADDON_LOADED") end
		elseif event == "PLAYER_ENTERING_WORLD" then
			Resume()
		elseif pending then
			Wake()
		end
	end)
end
