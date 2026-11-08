local _, ns = ...
local L = ns.L

-- The ways to travel the world besides your feet, for the guided route:
-- * the flight paths: the nodes a flight master's map shows you (the ones you
--   have found), noted with their places each time one opens, kept for the
--   account; the ones this character may fly to, for this character;
-- * the boats and zeppelins: the docks the world has, where they go;
-- * your hearthstone: its inn, remembered when you bind there; counted with
--   the wait before it is ready (an option of this character: never counted).

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

local UNREACHABLE = (Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable) or 2
local HEARTHSTONE = 6948

-- The account's knowledge of the world (the nodes' places are everyone's).
function ns.Data()
	WandererMapsAccountDB = type(WandererMapsAccountDB) == "table" and WandererMapsAccountDB or {}
	local data = WandererMapsAccountDB
	data.taxi = type(data.taxi) == "table" and data.taxi or {}
	data.learned = type(data.learned) == "table" and data.learned or {}
	return data
end

-- Flight paths -----------------------------------------------------------------------------------------------

local function Known()
	local db = ns.DB()
	db.knownTaxi = type(db.knownTaxi) == "table" and db.knownTaxi or {}
	return db.knownTaxi
end

-- The flight nodes this character has found (every one its flight map shows, reachable or not); nil until a
-- flight map was seen with it.
function ns.MetTaxi()
	local db = ns.DB()
	return type(db.metTaxi) == "table" and db.metTaxi or nil
end

-- The flight master's map open: its nodes learned, the ones you may fly to noted for this character.
function ns.LearnTaxi()
	local map = Clean(Safe(GetTaxiMapID))
	if not map then return end
	local taxi, known = ns.Data().taxi, Known()
	local db = ns.DB()
	db.metTaxi = type(db.metTaxi) == "table" and db.metTaxi or {}
	local count = 0
	if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
		for _, node in ipairs(Safe(C_TaxiMap.GetAllTaxiNodes, map) or {}) do
			local id, name, position, state = Clean(node.nodeID), Clean(node.name), node.position, Clean(node.state)
			local x, y = type(position) == "table" and Clean(position.x), type(position) == "table" and Clean(position.y)
			if id and name and x and y then
				taxi[id] = { name = name, map = map, x = x, y = y }
				if state ~= UNREACHABLE then known[id] = true end
				db.metTaxi[id] = true
				count = count + 1
			end
		end
	end
	local learned = ns.Data().learned
	-- (Wanderer Maps off: noted quietly, said the first time it is on)
	local settings = ns.Settings()
	if count > 0 and not learned[map] and settings and settings.enabled then
		learned[map] = true
		W.Print(L.TAXI_LEARNED:format(U.MapName(map) or "?", count))
	end
	-- (the way planned again: the new nodes may shorten it)
	ns.Replan()
end

-- The flight nodes this character may fly to: { id, name, map, x, y, wx, wy, instance }.
function ns.KnownTaxi()
	local list = {}
	local known = Known()
	for id, node in pairs(ns.Data().taxi) do
		if known[id] then
			local wx, wy, where = ns.WorldOf(node.map, node.x, node.y)
			if wx then
				list[#list + 1] = { id = id, name = node.name, map = node.map, x = node.x, y = node.y, wx = wx, wy = wy, instance = where }
			end
		end
	end
	return list
end

-- Boats and zeppelins ----------------------------------------------------------------------------------------
-- The docks as the original world has them (the game's maps of the zones; a map the game lacks is left out).
-- side: who may board without a fight (nil: everyone). A dock: { map, x, y (0 to 1), area } or { map, world = { continent,
-- x, y }, area } (where the map changed since the original world); area: its name, in your language.

-- (the maps of the original world: Wetlands 1437, Dustwallow 1445, Darkshore 1439, Teldrassil 1438, Stranglethorn 1434,
-- the Barrens 1413, Durotar 1411, Tirisfal 1420)
ns.BOATS = {
	{ kind = "boat", side = "Alliance", a = { 1437, 0.054, 0.638, area = 150 }, b = { 1445, 0.716, 0.566, area = 513 } },
	{ kind = "boat", side = "Alliance", a = { 1437, 0.047, 0.573, area = 150 }, b = { 1439, 0.324, 0.437, area = 442 } },
	{ kind = "boat", side = "Alliance", a = { 1439, 0.327, 0.405, area = 442 }, b = { 1438, 0.553, 0.933, area = 702 } },
	{ kind = "boat", a = { 1434, 0.256, 0.731, area = 35 }, b = { 1413, 0.639, 0.386, area = 392 } },
	{ kind = "zeppelin", side = "Horde", a = { 1411, 0.514, 0.125, area = 1637 }, b = { 1420, 0.619, 0.591, area = 1497 } },
	{ kind = "zeppelin", side = "Horde", a = { 1411, 0.507, 0.141, area = 1637 }, b = { 1434, 0.319, 0.291, area = 117 } },
	{ kind = "zeppelin", side = "Horde", a = { 1420, 0.600, 0.586, area = 1497 }, b = { 1434, 0.320, 0.273, area = 117 } },
	-- (the Deeprun Tram: its two doors in the world, Stormwind 1453 and Ironforge 1455; Forever redrew Stormwind's map,
	-- the game places them on it)
	{ kind = "tram", side = "Alliance", a = { 1453, world = { 0, -8346.5, 514.0 }, area = 1519 },
		b = { 1455, world = { 0, -4840.3, -1330.5 }, area = 1537 } },
}

-- The docks you may board at: { kind, from = { map, x, y, name, wx, wy, instance }, to = {...} }, both ways.
function ns.Crossings()
	local list = {}
	local settings = ns.Settings()
	if not (settings and settings.boats) then return list end
	local side = Clean(Safe(UnitFactionGroup, "player"))
	local function Dock(spec)
		local x, y = spec[2], spec[3]
		if spec.world then
			local _, mx, my = U.WorldToMap(spec.world[1], spec.world[2], spec.world[3], spec[1])
			x, y = mx, my
		end
		local wx, wy, instance = ns.WorldOf(spec[1], x, y)
		if not wx then return nil end
		return { map = spec[1], x = x, y = y, name = U.AreaName(spec.area) or "", wx = wx, wy = wy, instance = instance }
	end
	for _, line in ipairs(ns.BOATS) do
		if not line.side or line.side == side then
			local a, b = Dock(line.a), Dock(line.b)
			if a and b then
				list[#list + 1] = { kind = line.kind, from = a, to = b }
				list[#list + 1] = { kind = line.kind, from = b, to = a }
			end
		end
	end
	return list
end

-- The hearthstone -------------------------------------------------------------------------------------------

-- Bound somewhere: the inn remembered (where you stand).
local function NoteHearth()
	local map, x, y = U.HereOnMap()
	if not map then return end
	ns.DB().hearth = { map = map, x = x, y = y, name = Clean(Safe(GetBindLocation)) or U.MapName(map, x, y) }
end

-- Your hearthstone in your bags and its inn known: { map, x, y, name, wx, wy, instance, wait (seconds before it
-- is ready, 0: now) }, else nil. The route counts its wait: still cooling down, it is taken only when it still
-- comes first.
function ns.Hearth()
	local hearth = ns.DB().hearth
	if type(hearth) ~= "table" or not hearth.map then return nil end
	if U.ItemCount(HEARTHSTONE) == 0 then return nil end
	local start, duration = Safe((C_Container and C_Container.GetItemCooldown) or GetItemCooldown, HEARTHSTONE)
	start, duration = Clean(start) or 0, Clean(duration) or 0
	local wait = (start > 0 and duration > 0) and math.max(0, start + duration - GetTime()) or 0
	local wx, wy, instance = ns.WorldOf(hearth.map, hearth.x, hearth.y)
	if not wx then return nil end
	return { map = hearth.map, x = hearth.x, y = hearth.y, name = hearth.name or L.KIND_HEARTH, wx = wx, wy = wy,
		instance = instance, wait = wait }
end

function ns.InitTransport()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "TAXIMAP_OPENED", "HEARTHSTONE_BOUND" }) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", function(_, event)
		if event == "TAXIMAP_OPENED" then return ns.LearnTaxi() end
		NoteHearth()
	end)
end
