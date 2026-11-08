local _, ns = ...
local L = ns.L

-- The guided route: from where you stand to a place, the cheapest way in
-- time through what you have: your feet (as the crow flies, between two
-- points of the same continent), the flight paths you know, the boats and
-- zeppelins, your hearthstone (an option; its wait counted while it cools
-- down). A flight's time is the one your flights taught (FlightLine.lua),
-- else guessed from the distance. A way is a list of legs: walk
-- to a point, take a flight, board a boat, use the stone. Nothing of the
-- roads: the arrow points straight, you choose the path.

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

local RUN, MOUNT = 7, 14 -- yards a second
local FLIGHT_SPEED, FLIGHT_WAIT = 32, 20 -- a flight: its speed, boarding
local BOAT_WAIT = 180 -- a crossing, the wait at the dock counted
local TRAM_WAIT = 90 -- the tram
local HEARTH_CAST = 15
local STRAIGHT_FIRST = 150 -- yards: closer than this, no flight nor boat is worth it

local function WalkSpeed()
	return Clean(Safe(IsMounted)) and MOUNT or RUN
end

-- The islands no one walks off nor onto (Teldrassil, Darnassus): a walk between a node known on one and a node
-- known on a zone elsewhere is left out (the boat or a flight then). A node whose map is not a zone's (unknown, a
-- continent's) walks as before. Island(map): true, false (a zone elsewhere), nil (not known).
local ISLANDS = { [1438] = true, [1457] = true }
local ZONE_MAP = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local zoneMaps = {}
local function Island(map)
	if not map then return nil end
	if ISLANDS[map] then return true end
	if zoneMaps[map] == nil then
		local info = C_Map and C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, map)
		zoneMaps[map] = type(info) == "table" and Clean(info.mapType) == ZONE_MAP or false
	end
	if zoneMaps[map] then return false end
	return nil
end
local function Walkable(a, b)
	return a.island == nil or b.island == nil or a.island == b.island
end

local function Distance(a, b)
	local dx, dy = a.wx - b.wx, a.wy - b.wy
	return math.sqrt(dx * dx + dy * dy)
end

-- The nodes of the graph: you, the goal, the flight nodes, the docks, your inn; each with its world place.
local function Nodes(goal)
	local px, py, here = ns.Here()
	if not px then return nil end
	local nodes = { { kind = "start", wx = px, wy = py, instance = here, name = "", map = (U.HereOnMap()) } }
	nodes[2] = { kind = "goal", wx = goal.wx, wy = goal.wy, instance = goal.instance, name = goal.title, map = goal.map, x = goal.x, y = goal.y }
	for _, node in ipairs(ns.KnownTaxi()) do
		node.kind = "taxi"
		nodes[#nodes + 1] = node
	end
	-- (each dock once, with where it sails to)
	local docks = {}
	local function Dock(dock)
		local key = dock.map .. ":" .. dock.x .. ":" .. dock.y
		if not docks[key] then
			docks[key] = { kind = "dock", wx = dock.wx, wy = dock.wy, instance = dock.instance, name = dock.name, map = dock.map, x = dock.x, y = dock.y, links = {} }
			nodes[#nodes + 1] = docks[key]
		end
		return docks[key]
	end
	for _, crossing in ipairs(ns.Crossings()) do
		local from, to = Dock(crossing.from), Dock(crossing.to)
		from.links[#from.links + 1] = { to = to, kind = crossing.kind }
	end
	-- (the stone left out of the routes: this character's choice)
	local settings = ns.Settings()
	local hearth = not (settings and settings.hearth == false) and ns.Hearth()
	if hearth then
		hearth.kind = "hearth"
		nodes[#nodes + 1] = hearth
	end
	for _, node in ipairs(nodes) do node.island = Island(node.map) end
	return nodes
end

-- The edges out of a node: { to = index, cost, kind } (no walk off an island).
local function Edges(nodes, from)
	local list = {}
	local a = nodes[from]
	local speed = WalkSpeed()
	for index, b in ipairs(nodes) do
		if index ~= from and b.kind ~= "start" and b.kind ~= "hearth" and a.instance == b.instance then
			if Walkable(a, b) then list[#list + 1] = { to = index, cost = Distance(a, b) / speed, kind = "walk" } end
			if a.kind == "taxi" and b.kind == "taxi" then
				local learned = ns.HopSeconds and ns.HopSeconds(a.id, b.id)
				list[#list + 1] = { to = index, cost = FLIGHT_WAIT + (learned or Distance(a, b) / FLIGHT_SPEED), kind = "fly" }
			end
		end
	end
	if a.kind == "dock" then
		for _, link in ipairs(a.links) do
			for index, b in ipairs(nodes) do
				if b == link.to then list[#list + 1] = { to = index, cost = link.kind == "tram" and TRAM_WAIT or BOAT_WAIT, kind = link.kind } end
			end
		end
	end
	if a.kind == "start" then
		for index, b in ipairs(nodes) do
			if b.kind == "hearth" then list[#list + 1] = { to = index, cost = HEARTH_CAST + (b.wait or 0), kind = "hearth" } end
		end
	end
	return list
end

-- The cheapest way: the legs to the goal, or nil (no way known: as the crow flies then).
function ns.Plan(goal)
	local nodes = Nodes(goal)
	if not nodes then return nil end
	local start, target = nodes[1], nodes[2]
	-- (close by on the same continent: your feet)
	if start.instance == target.instance and Distance(start, target) < STRAIGHT_FIRST then return nil end
	local best, via, done = {}, {}, {}
	for index in ipairs(nodes) do best[index] = math.huge end
	best[1] = 0
	for _ = 1, #nodes do
		local current, lowest = nil, math.huge
		for index, cost in ipairs(best) do
			if not done[index] and cost < lowest then current, lowest = index, cost end
		end
		if not current or current == 2 then break end
		done[current] = true
		for _, edge in ipairs(Edges(nodes, current)) do
			local cost = lowest + edge.cost
			if cost < best[edge.to] then
				best[edge.to] = cost
				via[edge.to] = { from = current, kind = edge.kind }
			end
		end
	end
	if best[2] == math.huge then return nil end
	-- Back from the goal: the legs, one for each stretch.
	local legs, at = {}, 2
	while via[at] do
		local step = via[at]
		local node = nodes[at]
		local leg = { kind = step.kind, map = node.map, x = node.x, y = node.y, wx = node.wx, wy = node.wy, instance = node.instance,
			name = node.name, target = node.kind, cost = best[at] - best[step.from] }
		-- (the stone still cooling down: when it is ready, as the plan was made)
		if step.kind == "hearth" and (node.wait or 0) > 0 then leg.readyAt = GetTime() + node.wait end
		table.insert(legs, 1, leg)
		at = step.from
	end
	-- (a walk to the goal straight from the start: no way worth saying)
	if #legs == 1 and legs[1].kind == "walk" then return nil end
	return legs
end

-- The words of a leg: what to do, where.
function ns.LegWords(leg)
	if leg.kind == "fly" then return L.LEG_FLY:format(leg.name) end
	if leg.kind == "boat" then return L.LEG_BOAT:format(leg.name) end
	if leg.kind == "zeppelin" then return L.LEG_ZEPPELIN:format(leg.name) end
	if leg.kind == "tram" then return L.LEG_TRAM:format(leg.name) end
	if leg.kind == "hearth" then
		local wait = leg.readyAt and leg.readyAt - GetTime() or 0
		if wait >= 1 then return L.LEG_HEARTH_WAIT:format(leg.name, ns.Clock(wait)) end
		return L.LEG_HEARTH:format(leg.name)
	end
	if leg.target == "taxi" then return L.LEG_WALK_FM:format(leg.name) end
	if leg.target == "dock" then return L.LEG_DOCK:format(leg.name) end
	return L.LEG_WALK:format(leg.name)
end

function ns.LegKind(leg)
	return L["KIND_" .. leg.kind:upper()] or leg.kind
end

-- Time of arrival --------------------------------------------------------------------------------------------
-- How long until there, in seconds, from what the plan counted: a walk at your pace (mounted or not), the
-- flights, crossings and the stone as their legs cost. Always a guess, said with "~".

-- A leg's seconds: a walk from its distance now (nil: as planned), the stone from its wait now.
local function LegSeconds(leg, distance)
	if leg.kind == "walk" and distance then return distance / WalkSpeed() end
	-- (in the air: what is left of the flight)
	if leg.kind == "fly" and distance and Clean(Safe(UnitOnTaxi, "player")) then return distance / FLIGHT_SPEED end
	if leg.kind == "hearth" and leg.readyAt then return HEARTH_CAST + math.max(0, leg.readyAt - GetTime()) end
	return tonumber(leg.cost) or 0
end

-- To the step followed, from the distance to the point the arrow shows (a leg's or the step's): the leg followed,
-- then the legs after it. Nil when the distance is unknown.
function ns.StepSeconds(distance)
	if not distance then return nil end
	local route = ns.Route()
	local legs = route.legs
	if not legs then return distance / WalkSpeed() end
	local seconds = 0
	for index = route.leg or 1, #legs do
		seconds = seconds + LegSeconds(legs[index], index == (route.leg or 1) and distance or nil)
	end
	return seconds
end

-- From the step followed to the route's end, step to step on foot (nil: a step on another continent, no guess).
-- Its yards kept until the route changes (ns.version); the seconds at your pace now (mounted or not).
local rest = { version = -1 }
local function RestSeconds()
	local route = ns.Route()
	if not (rest.version == ns.version and rest.steps == route.steps and rest.current == route.current) then
		local yards, last = 0, route.steps[route.current]
		local lx, ly, linstance
		if last then lx, ly, linstance = ns.WorldOf(last.map, last.x, last.y) end
		for index = route.current + 1, #route.steps do
			local step = route.steps[index]
			if not step.done then
				local wx, wy, instance = ns.WorldOf(step.map, step.x, step.y)
				if not (wx and lx) or instance ~= linstance then
					yards = nil
					break
				end
				yards = yards + math.sqrt((wx - lx) ^ 2 + (wy - ly) ^ 2)
				lx, ly, linstance = wx, wy, instance
			end
		end
		rest.version, rest.steps, rest.current, rest.yards = ns.version, route.steps, route.current, yards
	end
	return rest.yards and rest.yards / WalkSpeed() or nil
end

-- To the route's end: the step followed and the steps after it (nil: unknown).
function ns.RouteSeconds(distance)
	local first = ns.StepSeconds(distance)
	local after = first and RestSeconds()
	return after and first + after or nil
end

-- A time of arrival in words: "~2 min", "~1 h 05" (a minute at least).
function ns.EtaWords(seconds)
	local minutes = math.max(1, math.floor((tonumber(seconds) or 0) / 60 + 0.5))
	if minutes >= 60 then return L.ETA_HOURS:format(math.floor(minutes / 60), minutes % 60) end
	return L.ETA_MINUTES:format(minutes)
end
