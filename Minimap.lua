local _, ns = ...

-- The route on the minimap: a pin for each step (numbered, the one followed
-- in gold, the ones done faded), the leg followed as a dotted line from you to
-- its point; what is beyond the minimap's reach sits on its edge, faded. Your
-- notes within its reach (and the radius chosen), small, with their sign, as
-- the world map's filter shows them. The minimap's own zoom and
-- rotation are followed.

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

local STEP = 0.1 -- seconds between two looks
local EDGE = 8 -- pixels kept from the minimap's edge
local PIN, DOT, NOTE = 16, 4, 14
local NOTE_ALPHA = 0.8
-- The minimap's reach in yards by zoom level (the game's own values), outdoors and indoors.
local RADII = { outdoor = { 233.33, 200, 166.67, 133.33, 100, 66.67 }, indoor = { 150, 120, 90, 60, 40, 25 } }

local overlay, driver, since = nil, nil, 0
local pins, dots, notePins = {}, {}, {}
local spots = {} -- each step's world place, read once for each route
local noteSpots = setmetatable({}, { __mode = "k" }) -- each note's world place, read once
local last = {} -- what the last look was drawn for (where you stood, the minimap's turn and reach, the route's version)

local function Radius()
	local zoom = Clean(Safe(Minimap.GetZoom, Minimap)) or 0
	return (Clean(Safe(IsIndoors)) and RADII.indoor or RADII.outdoor)[zoom + 1] or RADII.outdoor[1]
end

-- Where a world point falls on the minimap: x, y from its center (pixels), and whether it is within reach. at:
-- where you stand and how the minimap turns, read once for each look ({ x, y, instance, turn, radius, half }).
local function Project(wx, wy, instance, at)
	local angle, distance = ns.VectorFrom(at.x, at.y, at.instance, wx, wy, instance)
	if not angle then return nil end
	angle = angle - at.turn
	local radius, half = at.radius, at.half
	local share = distance / radius
	local within = share <= 1
	local d = math.min(share, 1) * (half - EDGE)
	return -math.sin(angle) * d, math.cos(angle) * d, within
end

local function Pin(index)
	local pin = pins[index]
	if pin then return pin end
	pin = CreateFrame("Frame", nil, overlay)
	pin:SetSize(PIN, PIN)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetAllPoints()
	pin.number = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	pin.number:SetPoint("CENTER", pin, "CENTER", 0, 1)
	pins[index] = pin
	return pin
end

local function Dot(index)
	local dot = dots[index]
	if dot then return dot end
	dot = overlay:CreateTexture(nil, "ARTWORK")
	dot:SetSize(DOT, DOT)
	dot:SetColorTexture(1, 0.82, 0, 0.8)
	dots[index] = dot
	return dot
end

-- How far notes show on the minimap, in yards (the option; at most the minimap's own reach).
local NOTE_RADIUS = 250
function ns.NoteRadius()
	local settings = ns.Settings()
	return tonumber(settings and settings.noteRadius) or NOTE_RADIUS
end

-- Your notes within the minimap's reach and the radius chosen, as the world map's filter shows them (none on its
-- edge: only those around you).
local function Notes(at)
	local count = 0
	local reach = math.min(at.radius, ns.NoteRadius())
	for _, note in ipairs(ns.Notes()) do
		local spot = noteSpots[note]
		if not spot then
			spot = { ns.WorldOf(note.map, note.x, note.y) }
			noteSpots[note] = spot
		end
		local x, y, within
		-- (the same continent, within the radius: placed)
		if spot[1] and (spot[3] == nil or at.instance == nil or spot[3] == at.instance) and ns.NoteShown(note)
			and (spot[1] - at.x) ^ 2 + (spot[2] - at.y) ^ 2 <= reach * reach then
			x, y, within = Project(spot[1], spot[2], spot[3], at)
		end
		if x and within then
			count = count + 1
			local pin = notePins[count]
			if not pin then
				pin = CreateFrame("Frame", nil, overlay)
				pin:SetSize(NOTE, NOTE)
				pin.icon = pin:CreateTexture(nil, "ARTWORK")
				pin.icon:SetAllPoints()
				notePins[count] = pin
			end
			if pin.key ~= (note.icon or "place") then
				pin.key = note.icon or "place"
				ns.NoteIcon(pin.icon, note.icon)
			end
			pin:SetAlpha(NOTE_ALPHA)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
			pin:Show()
		end
	end
	for index = count + 1, #notePins do notePins[index]:Hide() end
end

-- Anything to show on the minimap (the option on, a step or a note): else the look sleeps.
local function Wanted()
	local settings = ns.Settings()
	return settings and settings.enabled and settings.minimap and (ns.Route().steps[1] ~= nil or ns.Notes()[1] ~= nil) or false
end

local function Look()
	local route = ns.Route()
	if not (Wanted() and Minimap:IsVisible()) then return overlay:Hide() end
	-- (where you stand, the facing and the minimap's turning read once for every point; nowhere: nothing shown)
	local px, py, here = ns.Here()
	if not px then return overlay:Hide() end
	overlay:Show()
	local turn = Clean(Safe(GetCVar, "rotateMinimap")) == "1" and (Clean(Safe(GetPlayerFacing)) or 0) or 0
	local radius, half = Radius(), Minimap:GetWidth() / 2
	-- (nothing moved and nothing changed since the last look: the pins stand where they are)
	local drawn = last
	if drawn.x == px and drawn.y == py and drawn.instance == here and drawn.turn == turn and drawn.radius == radius
		and drawn.half == half and drawn.version == ns.version then
		return
	end
	drawn.x, drawn.y, drawn.instance, drawn.turn, drawn.radius, drawn.half, drawn.version = px, py, here, turn, radius, half, ns.version
	local at = { x = px, y = py, instance = here, turn = turn, radius = radius, half = half }
	Notes(at)
	-- The steps.
	for index, step in ipairs(route.steps) do
		local pin = Pin(index)
		spots[index] = spots[index] or { ns.WorldOf(step.map, step.x, step.y) }
		local wx, wy, instance = unpack(spots[index])
		local x, y, within
		if wx then x, y, within = Project(wx, wy, instance, at) end
		if x then
			local current = index == route.current
			ns.StepIcon(pin.icon, current)
			pin.number:SetText(tostring(index))
			pin:SetAlpha(step.done and 0.35 or within and 1 or 0.55)
			pin:ClearAllPoints()
			pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
			pin:Show()
		else
			pin:Hide()
		end
	end
	for index = #route.steps + 1, #pins do pins[index]:Hide() end
	-- The leg followed: a dotted line from you to its point (the step itself when no leg).
	local leg = ns.CurrentLeg()
	local step = ns.CurrentStep()
	local wx, wy, instance
	if leg then
		wx, wy, instance = leg.wx, leg.wy, leg.instance
	elseif step and spots[route.current] then
		wx, wy, instance = unpack(spots[route.current])
	end
	local x, y
	if wx then x, y = Project(wx, wy, instance, at) end
	-- (its dots as its length asks: the minimap's reach over its pixels is its scale; its two ends always)
	local count = 0
	if x then
		local spaces = ns.DotSpaces(math.sqrt(x * x + y * y), radius / math.max(1, half - EDGE))
		for index = 0, spaces do
			local share = index / spaces
			local dot = Dot(index + 1)
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", Minimap, "CENTER", x * share, y * share)
			dot:Show()
		end
		count = spaces + 1
	end
	for index = count + 1, #dots do dots[index]:Hide() end
end

-- Drawn again (the route, the notes or the options changed); the look runs only while there is something to show.
function ns.RefreshMinimap()
	if not overlay then return end
	wipe(spots)
	for note in pairs(noteSpots) do noteSpots[note] = nil end
	for _, pin in ipairs(notePins) do pin.key = nil end
	wipe(last)
	since = STEP
	Look()
	driver:SetShown(Wanted())
end

function ns.InitMinimap()
	if not Minimap then return end
	overlay = CreateFrame("Frame", "WandererMapsMinimap", Minimap)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(Minimap:GetFrameLevel() + 5)
	-- (its own frame: the overlay hidden with the minimap is shown again by the next look)
	driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < STEP then return end
		since = 0
		Look()
	end)
	ns.OnChanged(ns.RefreshMinimap)
	ns.RefreshMinimap()
end
