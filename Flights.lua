local _, ns = ...
local L = ns.L

-- The flight masters of the world, from the game's own table of flight nodes (the ones a character can find,
-- each with its side), and a quiet word about one you have not found yet (an option, off): once per flight
-- master and per character, in its zone or near it. A click on the notice follows it.
-- What this character has found is what its flight map showed (Transport.lua); before it ever opened one,
-- only a young character is thought to know none.

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

local NEAR = 150 -- yards: a flight master this near is told even from another zone
local LOOK_EVERY = 5 -- seconds between two looks around, while the option is on
local YOUNG = 10 -- a character of this level or less who never opened a flight map knows none yet
local MICRO = (Enum and Enum.UIMapType and Enum.UIMapType.Micro) or 5
ns.FLIGHT_ICON = "Interface\\Icons\\Ability_Mount_Gryphon_01"

-- { node id, continent, x, y (the world's, as the game's tables count them), side (nil: both) }
-- (from forever-db2 TaxiNodes: the nodes a character can find, on the two continents)
ns.FLIGHT_MASTERS = {
	{ 2, 0, -8832.8, 478.6, "Alliance" }, -- Stormwind, Elwynn
	{ 4, 0, -10628.9, 1036.7, "Alliance" }, -- Sentinel Hill, Westfall
	{ 5, 0, -9429.1, -2231.4, "Alliance" }, -- Lakeshire, Redridge
	{ 6, 0, -4821.8, -1155.4, "Alliance" }, -- Ironforge, Dun Morogh
	{ 7, 0, -3792.3, -783.3, "Alliance" }, -- Menethil Harbor, Wetlands
	{ 8, 0, -5421.9, -2930.0, "Alliance" }, -- Thelsamar, Loch Modan
	{ 10, 0, 478.9, 1536.6, "Horde" }, -- The Sepulcher, Silverpine Forest
	{ 11, 0, 1568.6, 268.0, "Horde" }, -- Undercity, Tirisfal
	{ 12, 0, -10515.5, -1261.7, "Alliance" }, -- Darkshire, Duskwood
	{ 13, 0, -0.1, -859.9, "Horde" }, -- Tarren Mill, Hillsbrad
	{ 14, 0, -711.5, -515.5, "Alliance" }, -- Southshore, Hillsbrad
	{ 16, 0, -1240.5, -2515.1, "Alliance" }, -- Refuge Pointe, Arathi
	{ 17, 0, -916.3, -3496.9, "Horde" }, -- Hammerfall, Arathi
	{ 18, 0, -14444.3, 509.6, "Horde" }, -- Booty Bay, Stranglethorn
	{ 19, 0, -14473.0, 464.1, "Alliance" }, -- Booty Bay, Stranglethorn
	{ 20, 0, -12414.2, 146.3, "Horde" }, -- Grom'gol, Stranglethorn
	{ 21, 0, -6634.0, -2180.1, "Horde" }, -- Kargath, Badlands
	{ 22, 1, -1197.2, 29.7, "Horde" }, -- Thunder Bluff, Mulgore
	{ 23, 1, 1677.6, -4315.7, "Horde" }, -- Orgrimmar, Durotar
	-- (node 24, "Generic, World target for Zeppelin Paths", left out: no flight master stands there)
	{ 25, 1, -441.8, -2596.1, "Horde" }, -- Crossroads, The Barrens
	{ 26, 1, 6341.4, 557.7, "Alliance" }, -- Auberdine, Darkshore
	{ 27, 1, 8643.6, 841.0, "Alliance" }, -- Rut'theran Village, Teldrassil
	{ 28, 1, 2827.3, -289.2, "Alliance" }, -- Astranaar, Ashenvale
	{ 29, 1, 966.6, 1040.3, "Horde" }, -- Sun Rock Retreat, Stonetalon Mountains
	{ 30, 1, -5407.7, -2414.3, "Horde" }, -- Freewind Post, Thousand Needles
	{ 31, 1, -4491.9, -775.9, "Alliance" }, -- Thalanaar, Feralas
	{ 32, 1, -3825.4, -4516.6, "Alliance" }, -- Theramore, Dustwallow Marsh
	{ 33, 1, 2681.1, 1461.7, "Alliance" }, -- Stonetalon Peak, Stonetalon Mountains
	{ 37, 1, 139.2, 1325.8, "Alliance" }, -- Nijel's Point, Desolace
	{ 38, 1, -1767.6, 3263.9, "Horde" }, -- Shadowprey Village, Desolace
	{ 39, 1, -7224.0, -3734.6, "Alliance" }, -- Gadgetzan, Tanaris
	{ 40, 1, -7048.9, -3780.4, "Horde" }, -- Gadgetzan, Tanaris
	{ 41, 1, -4373.8, 3338.6, "Alliance" }, -- Feathermoon, Feralas
	{ 42, 1, -4419.9, 199.3, "Horde" }, -- Camp Mojache, Feralas
	{ 43, 0, 283.7, -2002.8, "Alliance" }, -- Aerie Peak, The Hinterlands
	{ 44, 1, 3661.5, -4390.4, "Horde" }, -- Valormok, Azshara
	{ 45, 0, -11112.3, -3435.7, "Alliance" }, -- Nethergarde Keep, Blasted Lands
	{ 48, 1, 5068.4, -337.2, "Horde" }, -- Bloodvenom Post, Felwood
	{ 49, 1, 7458.5, -2487.2, "Alliance" }, -- Moonglade
	{ 52, 1, 6799.2, -4742.4, "Alliance" }, -- Everlook, Winterspring
	{ 53, 1, 6813.1, -4611.1, "Horde" }, -- Everlook, Winterspring
	{ 55, 1, -3147.4, -2842.2, "Horde" }, -- Brackenwall Village, Dustwallow Marsh
	{ 56, 0, -10457.0, -3279.3, "Horde" }, -- Stonard, Swamp of Sorrows
	{ 58, 1, 3374.7, 997.0, "Horde" }, -- Zoram'gar Outpost, Ashenvale
	{ 61, 1, 2302.4, -2524.6, "Horde" }, -- Splintertree Post, Ashenvale
	{ 64, 1, 2722.0, -3880.6, "Alliance" }, -- Talrendis Point, Azshara
	{ 65, 1, 6205.9, -1949.6, "Alliance" }, -- Talonbranch Glade, Felwood
	{ 66, 0, 931.3, -1430.1, "Alliance" }, -- Chillwind Camp, Western Plaguelands
	{ 67, 0, 2271.1, -5340.8, "Alliance" }, -- Light's Hope Chapel, Eastern Plaguelands
	{ 68, 0, 2327.4, -5286.9, "Horde" }, -- Light's Hope Chapel, Eastern Plaguelands
	{ 69, 1, 7470.4, -2123.4, "Horde" }, -- Moonglade
	{ 70, 0, -7504.0, -2187.5, "Horde" }, -- Flame Crest, Burning Steppes
	{ 71, 0, -8364.6, -2738.4, "Alliance" }, -- Morgan's Vigil, Burning Steppes
	{ 72, 1, -6811.4, 836.7, "Horde" }, -- Cenarion Hold, Silithus
	{ 73, 1, -6761.8, 772.0, "Alliance" }, -- Cenarion Hold, Silithus
	{ 74, 0, -6552.6, -1168.3, "Alliance" }, -- Thorium Point, Searing Gorge
	{ 75, 0, -6554.9, -1100.1, "Horde" }, -- Thorium Point, Searing Gorge
	{ 76, 0, -635.3, -4720.5, "Horde" }, -- Revantusk Village, The Hinterlands
	{ 77, 1, -2380.7, -1882.7, "Horde" }, -- Camp Taurajo, The Barrens
	{ 79, 1, -6113.8, -1142.7 }, -- Marshal's Refuge, Un'Goro Crater
	{ 80, 1, -894.6, -3773.0 }, -- Ratchet, The Barrens
	{ 559, 1, 5283.2, -3306.7 }, -- Summit of Eternity, Mount Hyjal
	{ 3203, 0, -7923.7, -4783.0, "Horde" }, -- Rog'mar, Riverglades
	{ 3205, 0, -4375.7, 864.8, "Alliance" }, -- Tidegear Coast, Dun Morogh
	{ 3242, 1, 4393.5, -2836.4 }, -- Tainted Foothills, Mount Hyjal
	{ 3274, 0, -8157.2, -5724.7, "Horde" }, -- Powderfuse Port, Riverglades
	{ 3275, 0, -8180.0, -5616.3, "Alliance" }, -- Powderfuse Port, Riverglades
	{ 3276, 0, -9104.1, -4830.5, "Alliance" }, -- Farholde Keep, Riverglades
}

local places = {} -- node id -> its place on its zone's map ({ map, x, y }), or false (none)

-- The zone a map belongs to (a part of a city or a cave: the zone around it).
local function ZoneOf(map)
	for _ = 1, 4 do
		local info = map and Safe(C_Map.GetMapInfo, map)
		local kind, parent = type(info) == "table" and Clean(info.mapType), type(info) == "table" and Clean(info.parentMapID)
		if not (kind and kind >= MICRO and parent and parent > 0) then return map end
		map = parent
	end
	return map
end

-- A flight master's place on the map of its zone: map, x, y (nil: the game does not place it).
local function Place(node)
	local place = places[node[1]]
	if place == nil then
		local map, x, y = U.WorldToMap(node[2], node[3], node[4])
		place = map and { map = ZoneOf(map), x = x, y = y } or false
		-- (on the zone's own map when the point was found on a part of it)
		if place and place.map ~= map then
			local _, zx, zy = U.WorldToMap(node[2], node[3], node[4], place.map)
			if zx then place.x, place.y = zx, zy else place.map = map end
		end
		places[node[1]] = place
	end
	if not place then return nil end
	return place.map, place.x, place.y
end

-- A flight master's name: the one the flight map gave (any of your characters), else its zone's.
local function Name(node, map)
	local known = ns.Data().taxi[node[1]]
	return type(known) == "table" and known.name or U.MapName(map) or L.KIND_FLY
end

-- The flight masters of your side: { id, name, map, x, y, wx, wy, instance } (the world's x and y as Wanderer
-- Maps counts them).
function ns.FlightMasters()
	local list = {}
	local side = Clean(Safe(UnitFactionGroup, "player"))
	for _, node in ipairs(ns.FLIGHT_MASTERS) do
		if not node[5] or node[5] == side then
			local map, x, y = Place(node)
			if map then
				local name = Name(node, map)
				list[#list + 1] = { id = node[1], name = name, map = map, x = x, y = y, title = name,
					wx = node[4], wy = node[3], instance = node[2] }
			end
		end
	end
	return list
end

-- The flight nodes this character has found (nil: not known; a young character: none).
local function Met()
	local met = ns.MetTaxi()
	if met then return met end
	local db = ns.DB()
	if type(db.knownTaxi) == "table" and next(db.knownTaxi) then return db.knownTaxi end
	if (Clean(Safe(UnitLevel, "player")) or YOUNG + 1) <= YOUNG then return {} end
	return nil
end

-- Told once per flight master and per character.
local function Told()
	local db = ns.DB()
	db.flightTold = type(db.flightTold) == "table" and db.flightTold or {}
	return db.flightTold
end

-- A look around: the nearest flight master of your side you have not found, in your zone or near you, told.
function ns.LookForFlightMasters()
	local settings = ns.Settings()
	if not (settings and settings.enabled and settings.flightNotice) then return end
	if InCombatLockdown() or Clean(Safe(UnitOnTaxi, "player")) then return end
	local px, py, here = ns.Here()
	local met = px and Met()
	if not met then return end
	local current = C_Map and Clean(Safe(C_Map.GetBestMapForUnit, "player"))
	local zone = current and ZoneOf(current)
	local told = Told()
	local side = Clean(Safe(UnitFactionGroup, "player"))
	-- (the table read as it is, every few seconds: no list made, the name asked for the one told only)
	local nearest, bestDistance, bestMap, bestX, bestY
	for _, node in ipairs(ns.FLIGHT_MASTERS) do
		local id = node[1]
		if node[2] == here and (not node[5] or node[5] == side) and not met[id] and not told[id] then
			local distance = math.sqrt((node[4] - px) ^ 2 + (node[3] - py) ^ 2)
			if not nearest or distance < bestDistance then
				local map, x, y = Place(node)
				if map and (distance <= NEAR or map == zone) then
					nearest, bestDistance, bestMap, bestX, bestY = node, distance, map, x, y
				end
			end
		end
	end
	if not nearest then return end
	local name = Name(nearest, bestMap)
	local best = { id = nearest[1], name = name, title = name, map = bestMap, x = bestX, y = bestY }
	told[best.id] = time()
	W.Toast(L.FLIGHT_UNKNOWN, L.FLIGHT_UNKNOWN_AT:format(best.name, math.floor(bestDistance + 0.5)), {
		kicker = L.ADDON, icon = ns.FLIGHT_ICON, tone = "blue", wait = 120, kind = "mapsFlight",
		onClick = function() ns.GoTo(best) end, hint = L.FLIGHT_FOLLOW_HINT,
		-- (found while the notice waited, after a fight, or the notices turned off meanwhile: nothing to say any more)
		still = function()
			local now = ns.Settings()
			if not (now and now.enabled and now.flightNotice) then return false end
			local found = ns.MetTaxi()
			return not (found and found[best.id])
		end,
	})
end

local ticker
function ns.RefreshFlightNotice()
	local settings = ns.Settings()
	local on = settings and settings.enabled and settings.flightNotice
	if on and not ticker and C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(LOOK_EVERY, ns.LookForFlightMasters)
	elseif not on and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

function ns.InitFlights()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", ns.LookForFlightMasters)
	ns.RefreshFlightNotice()
end
