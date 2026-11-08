local _, ns = ...
local L = ns.L

-- The arrow: a small frame of your own place on the screen, pointing to the
-- step followed (or to the game's own pin on the map, an option), with what
-- to do there, the distance in yards and the step's number. Gold while you
-- head for it, warm amber when it is behind you; an option lets it fade
-- while you walk straight to it. Near enough: a check, the step is reached,
-- the next one is followed, the last one ends the route. Nothing when nothing
-- is followed; a faded arrow and the zone to open on the map where the game
-- keeps your position to itself (an instance, another continent). Its right
-- click: a small card (next step, plan again, clear, the route's window).

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local STEP = 0.1 -- seconds between two looks
local ARRIVE = 12 -- yards: reached
local FAR_REACH = 70 -- yards: landed from a flight, a crossing, the stone
local WIDTH, HEIGHT, ARROW_SIZE = 200, 110, 40
local NEAR_ALPHA = 0.55
local ON_COURSE, OFF_COURSE = math.rad(20), math.rad(90) -- heading off by less: gold; by more: amber
local QUIET_AFTER, QUIET_ALPHA, QUIET_FADE = 3, 0.35, 0.4 -- seconds on course, its faded alpha, seconds to fade
local ARRIVED_FOR = 0.8 -- seconds the check is shown, a step reached
local END_CHECK, END_FADE = 1.2, 0.4 -- the last one reached: the check, then the arrow fades away
local SAME_PLACE = 5 -- yards: the game's pin and ours are one
local ENDED_NEAR = 30 -- yards: a pin left there is the place you have just reached

local arrow, since, reachedAt, arrivedUntil = nil, 0, 0, 0
local ending -- the end of the way, shown a moment: { title, at }
local ended -- where the last way ended: { map, x, y } (a pin still there is not followed again)
local quietSince, quietAlpha = nil, 1
local placed -- the game's pin set by Wanderer Maps on the point followed: { map, x, y } (kept for the next session)
local restored = false
local driver -- the look, every moment a route is followed, the arrow shown or not

-- A step in words (what to do there), else its name.
local function Words(step) return ns.StepWords and ns.StepWords(step) or step.title end

-- The arrow's two lines: what is followed (a quest's or a place's name after its sign, a leg of the way, the
-- game's pin) in gold, and under it, quieter, who or where (the NPC, the step a leg leads to, the zone).
local function Lines(followed)
	local step = followed.goal
	if followed.leg then return followed.title, step and (step.label or step.title) or "" end
	if step then
		local sign = step.kind and ns.STEP_SIGNS[step.kind]
		local head = (sign and ("|T" .. sign .. ":14:14|t ") or "") .. (step.label or step.title)
		return head, step.label and step.title or U.MapName(step.map) or ""
	end
	return followed.title, followed.map and U.MapName(followed.map) or ""
end

-- Another addon's arrow on the screen (TomTom...): ours stays hidden, the look goes on for the steps reached and
-- the game's pin. (asked of Wanderer now and then, never ten times a second)
local yieldsAt, yields = -math.huge, nil
local function Yields()
	if GetTime() - yieldsAt > 5 then
		yieldsAt = GetTime()
		yields = W.Yields and W.Yields("arrow") or nil
	end
	return yields
end

-- A guide's own arrow on the screen now (RestedXP, Zygor): ours steps aside while it shows, never two arrows.
local GUIDE_ARROWS = { "RXPG_ARROW", "ZygorGuidesViewerPointer_ArrowCtrl" }
local function GuideArrow()
	for _, name in ipairs(GUIDE_ARROWS) do
		local frame = _G[name]
		if type(frame) == "table" and frame.IsVisible and frame:IsVisible() then return true end
	end
	return false
end

-- Another arrow on the screen: TomTom (Wanderer's own list) or a guide's.
local function OtherArrow() return Yields() or GuideArrow() end

-- The game's own marker in the world (its floating pin, with the distance) on the point followed (an
-- option): moved leg by leg, taken away when nothing of yours is followed any more. The game has one pin
-- only: one set by you or by another addon (a guide's waypoint) is never moved nor taken away; Wanderer Maps
-- puts its own back only once that one is gone.
-- (the game keeps its pin's place in single precision: compared within a hair)
-- Two places of maps one (within yards): by the world when the game knows it (the game may keep its pin on
-- another map than the one it was set on), else on the same map within a hair.
local function Near(a, map, x, y, yards)
	if not (a and map and x and y) then return false end
	if a.map == map and math.abs(a.x - x) < 0.001 and math.abs(a.y - y) < 0.001 then return true end
	local ax, ay, aInstance = U.MapToWorld(a.map, a.x, a.y)
	local bx, by, bInstance = U.MapToWorld(map, x, y)
	if not (ax and bx) or aInstance ~= bInstance then return false end
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) <= yards
end
local function SamePoint(map, x, y) return Near(placed, map, x, y, SAME_PLACE) end

-- Ours remembered (the game keeps its pin from one session to the next).
local function SetPlaced(point)
	placed = point
	ns.DB().gamePin = point
end
local function Restore()
	if restored then return end
	restored = true
	local saved = ns.DB().gamePin
	if type(saved) == "table" and tonumber(saved.map) and tonumber(saved.x) and tonumber(saved.y) then placed = saved end
end

-- The game's pin now: map, x, y (nil: none).
local function GamePin()
	local point = C_Map and C_Map.GetUserWaypoint and Safe(C_Map.GetUserWaypoint)
	if type(point) ~= "table" or type(point.position) ~= "table" then return nil end
	local map, x, y = Clean(point.uiMapID), Clean(point.position.x), Clean(point.position.y)
	if not (map and x and y) then return nil end
	return map, x, y
end

-- A pin someone else set (you, another addon), not Wanderer Maps'.
function ns.ForeignPin()
	Restore()
	local map, x, y = GamePin()
	return map ~= nil and not SamePoint(map, x, y)
end

-- TomTom keeps the game's pin in step with its own waypoints: with it, Wanderer Maps never sets one (no tug of war).
local function WithTomTom()
	local addons = C_AddOns or {}
	if addons.IsAddOnLoaded then
		local ok, loaded = pcall(addons.IsAddOnLoaded, "TomTom")
		if ok and loaded then return true end
	end
	return type(_G.TomTom) == "table"
end

-- Your corpse after a death (an option): while you are a ghost, the arrow points to it before anything followed;
-- gone at resurrection, the route followed again. Never with TomTom (its own) nor another arrow, nor ours off.
-- The game says where it lies on a map: the zone where you stand, else the maps around it.
local CORPSE_REACH = 10
local function CorpseOn(map)
	local death = _G.C_DeathInfo
	if not (death and death.GetCorpseMapPosition) then return nil end
	local point = Safe(death.GetCorpseMapPosition, map)
	if type(point) ~= "table" then return nil end
	local x, y = Clean(point.x), Clean(point.y)
	if not (x and y) or (x == 0 and y == 0) then return nil end
	return x, y
end

function ns.Corpse()
	local settings = ns.Settings()
	if not (settings and settings.enabled and settings.arrow and settings.corpse) then return nil end
	if not Clean(Safe(UnitIsGhost, "player")) or WithTomTom() or OtherArrow() then return nil end
	local map = U.HereOnMap()
	for _ = 1, 4 do
		if not map or map == 0 then return nil end
		local x, y = CorpseOn(map)
		if x then return { title = L.CORPSE, map = map, x = x, y = y, corpse = true, reach = CORPSE_REACH } end
		local info = C_Map and C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, map)
		map = type(info) == "table" and Clean(info.parentMapID) or nil
	end
	return nil
end

local function PlaceGamePin(followed)
	local settings = ns.Settings()
	local wanted = settings and settings.enabled and settings.gamePin and followed and followed.step and not WithTomTom()
	-- (another's pin: left as it is, and no longer ours to take away)
	if ns.ForeignPin() then
		if placed then SetPlaced(nil) end
		return
	end
	if wanted then
		if not SamePoint(followed.map, followed.x, followed.y) and U.Pin(followed.map, followed.x, followed.y) then
			SetPlaced({ map = followed.map, x = followed.x, y = followed.y })
		end
	elseif placed then
		-- (still ours: taken away)
		local mine = GamePin() ~= nil
		SetPlaced(nil)
		if mine and C_Map.ClearUserWaypoint then Safe(C_Map.ClearUserWaypoint) end
	end
end

-- The game's pin and its arrow in the world taken away (the way's end reached there).
local function ClearGamePin()
	SetPlaced(nil)
	if C_Map and C_Map.ClearUserWaypoint then Safe(C_Map.ClearUserWaypoint) end
	local super = _G.C_SuperTrack
	if super and super.SetSuperTrackedUserWaypoint then Safe(super.SetSuperTrackedUserWaypoint, false) end
end

-- What is followed: a step of the route, else the game's own pin (an option). { title, map, x, y, step }.
function ns.Followed()
	local settings = ns.Settings()
	if not (settings and settings.enabled) then return nil end
	local step = ns.CurrentStep()
	if step then
		-- (a new way: the last end forgotten)
		ended = nil
		local leg = ns.CurrentLeg()
		if leg then
			return { title = ns.LegWords(leg), map = leg.map, x = leg.x, y = leg.y, step = true, leg = leg, goal = step,
				reach = (leg.kind == "walk" and (leg.target == "goal" and ARRIVE or ARRIVE * 2)) or FAR_REACH }
		end
		return { title = Words(step), map = step.map, x = step.x, y = step.y, step = true, goal = step, reach = ARRIVE }
	end
	-- (the game's pin is followed for the arrow only: with ours off or another shown, it is never taken away on arrival)
	if settings.followGame and settings.arrow and not OtherArrow() and C_Map and C_Map.GetUserWaypoint then
		local point = Safe(C_Map.GetUserWaypoint)
		if type(point) == "table" and point.uiMapID and type(point.position) == "table" then
			local x, y = Clean(point.position.x), Clean(point.position.y)
			-- (a pin left where the way has just ended is not followed again)
			local map = Clean(point.uiMapID)
			if x and y and not Near(ended, map, x, y, ENDED_NEAR) then return { title = L.GAME_PIN, map = map, x = x, y = y } end
		end
	end
	return nil
end

local function Reached(followed)
	if GetTime() - reachedAt < 2 then return end
	reachedAt = GetTime()
	-- A leg of the way reached (not the last): the next one, a quiet sound.
	local route = ns.Route()
	if followed.leg and route.legs and (route.leg or 1) < #route.legs then
		Skin.Play("mark")
		ns.NextLeg()
		return
	end
	if followed.step then
		local nextStep = ns.NextOpenStep and ns.NextOpenStep() or nil
		local step = ns.CurrentStep()
		-- (a step of a quest: a click on the notice opens its sheet)
		local quest = step and step.quest and ns.CanOpenQuest and ns.CanOpenQuest() and step.quest or nil
		W.Toast(nextStep and L.STEP_REACHED:format(step and Words(step) or followed.title) or L.ROUTE_DONE,
			nextStep and L.NEXT_IS:format(Words(nextStep)) or "",
			{ icon = ns.QUEST_ARROW, tone = "good", kicker = L.ADDON, kind = "mapsStep", kindName = L.STEP_REACHED_KIND,
				onClick = quest and function() ns.OpenQuest(quest) end or nil })
		Skin.Play("confirm")
		-- (the last one: the way ends here, the arrow says so a moment and goes; the game's pin with it, when it is
		-- ours: one you or another addon placed stays)
		if not nextStep then
			ending = { title = followed.title, at = GetTime() }
			ended = { map = followed.map, x = followed.x, y = followed.y }
			if placed and not ns.ForeignPin() then ClearGamePin() else SetPlaced(nil) end
		else
			arrivedUntil = GetTime() + ARRIVED_FOR
		end
		ns.NextStep()
	end
end

-- The game's own pin followed (no route), reached: the way ends there the same, its pin taken away.
local function ReachedPin(followed)
	Skin.Play("confirm")
	ending = { title = followed.title, at = GetTime() }
	ended = { map = followed.map, x = followed.x, y = followed.y }
	ClearGamePin()
end

-- From you to the point followed: the angle to turn (the arrow's rotation), the distance, in flight or not.
function ns.Bearing(followed)
	local tx, ty, instance
	if followed.leg then
		tx, ty, instance = followed.leg.wx, followed.leg.wy, followed.leg.instance
	else
		tx, ty, instance = ns.WorldOf(followed.map, followed.x, followed.y)
	end
	if not tx then return nil end
	local angle, distance = ns.Vector(tx, ty, instance)
	if not angle then return nil end
	local facing = Clean(Safe(GetPlayerFacing)) or 0
	local flying = followed.leg and followed.leg.kind == "fly" and Clean(Safe(UnitOnTaxi, "player")) and true or false
	return angle - facing, distance, flying
end

-- How far, in words: reached, so many yards, or in the air (a flight taken: the landing waited for).
function ns.DistanceWords(followed, distance, flying)
	if flying then return L.LEG_FLYING end
	if distance < (followed.reach or ARRIVE) then return L.ARRIVED end
	return L.DISTANCE_SHORT:format(math.floor(distance + 0.5))
end

-- The time of arrival after the distance ("412 yd · ~2 min"), from what the guided route counts (none: reached,
-- a corpse, the game's pin far away).
local function EtaPart(followed, distance)
	if not (followed.step and ns.StepSeconds) or distance < (followed.reach or ARRIVE) then return "" end
	local seconds = ns.StepSeconds(distance)
	return seconds and (U.SEPARATOR .. ns.EtaWords(seconds)) or ""
end

-- The step's number under it, quieter, with the whole route's time ("step 2 of 5 · ~9 min in all"), with
-- several steps.
local function StepPart(followed, distance)
	if not followed.step then return "" end
	local route = ns.Route()
	if #route.steps < 2 then return "" end
	local total = distance and ns.RouteSeconds and ns.RouteSeconds(distance)
	return L.STEP_SHORT:format(route.current, #route.steps) .. (total and (U.SEPARATOR .. L.ETA_ALL:format(ns.EtaWords(total))) or "")
end

-- Quiet when on course (an option): walking straight to it for a few seconds, the arrow fades; at once back
-- when you turn away, stop, or come near.
local function Quiet(onCourse)
	local settings = ns.Settings()
	local moving = (Clean(Safe(GetUnitSpeed, "player")) or 0) > 0
	if not (settings and settings.arrowQuiet and onCourse and moving) then
		quietSince, quietAlpha = nil, 1
	else
		quietSince = quietSince or GetTime()
		if GetTime() - quietSince >= QUIET_AFTER then
			quietAlpha = math.max(QUIET_ALPHA, quietAlpha - (1 - QUIET_ALPHA) * STEP / QUIET_FADE)
		end
	end
	arrow:SetAlpha(quietAlpha)
end

-- The arrow's color by how far off your heading is: gold on course, soft a little off, amber behind you.
local function Heading(rotation)
	local off = math.abs((rotation + math.pi) % (2 * math.pi) - math.pi)
	local c, alpha = Skin.COLORS.gold, 1
	if off > OFF_COURSE then c = Skin.COLORS.warn elseif off > ON_COURSE then c, alpha = Skin.COLORS.soft, 0.9 end
	arrow.texture:SetVertexColor(c[1], c[2], c[3])
	return off <= ON_COURSE, alpha
end

-- The way's end: the check a moment, then the arrow fades away and hides (nothing comes back until a new
-- step is followed). False when it is over.
local function End(shown)
	if not ending then return false end
	local spent = GetTime() - ending.at
	if spent >= END_CHECK + END_FADE then
		ending = nil
		arrow:SetAlpha(1)
		arrow:Hide()
		return false
	end
	arrow.title:SetText(ending.title)
	arrow.sub:SetText("")
	arrow.distance:SetText(L.ARRIVED)
	arrow.steps:SetText("")
	arrow.check:Show()
	arrow.texture:Hide()
	arrow.elsewhere = nil
	quietSince, quietAlpha = nil, 1
	arrow:SetAlpha(spent <= END_CHECK and 1 or math.max(0, 1 - (spent - END_CHECK) / END_FADE))
	arrow:SetShown(shown)
	return true
end

local function Look()
	local route = ns.Followed()
	PlaceGamePin(route)
	local settings = ns.Settings()
	local shown = settings and settings.arrow and not OtherArrow() and true or false
	-- (a ghost: the corpse first, the route left as it is underneath)
	local corpse = ns.Corpse()
	local followed = corpse or route
	if not followed then
		if End(shown) then return end
		if driver then driver:Hide() end
		return arrow:Hide()
	end
	-- (a new way followed: an end still shown is let go)
	if ending then
		ending = nil
		arrow:SetAlpha(1)
	end
	-- (the arrow itself is a choice; the look goes on for the steps reached and the pin)
	local head, sub = Lines(followed)
	arrow.title:SetText(head)
	arrow.sub:SetText(sub)
	arrow.steps:SetText(StepPart(followed))
	-- (a step just reached: a check, a moment)
	local arrived = not corpse and GetTime() < arrivedUntil
	arrow.check:SetShown(arrived)
	arrow.texture:SetShown(not arrived)
	if arrived then
		Quiet(false)
		return arrow:SetShown(shown)
	end
	local angle, distance, flying = ns.Bearing(followed)
	if not angle then
		-- (where the game keeps your place to itself: the zone of the point, a click opens its map)
		arrow.texture:SetAlpha(0.3)
		arrow.texture:SetVertexColor(Skin.COLORS.soft[1], Skin.COLORS.soft[2], Skin.COLORS.soft[3])
		local zone = followed.map and U.MapName(followed.map)
		arrow.elsewhere = zone and followed.map or nil
		arrow.distance:SetText(zone and L.ELSEWHERE_IN:format(zone) or L.UNKNOWN_HERE)
		Quiet(false)
		arrow:SetShown(shown)
		return
	end
	arrow.elsewhere = nil
	local reach = followed.reach or ARRIVE
	arrow.texture:SetRotation(angle)
	local onCourse, alpha = Heading(angle)
	local near = distance < reach * 3
	arrow.texture:SetAlpha(near and NEAR_ALPHA or alpha)
	arrow.distance:SetText(ns.DistanceWords(followed, distance, flying) .. EtaPart(followed, distance))
	arrow.steps:SetText(StepPart(followed, distance))
	Quiet(onCourse and not near and not flying)
	arrow:SetShown(shown)
	-- (the corpse reached: nothing to tick, the arrow waits for the resurrection)
	if distance < reach and not flying and not corpse then
		if followed.step then Reached(followed) else ReachedPin(followed) end
	end
end

-- The map of the point followed, opened (a click on the arrow when you are elsewhere; never in a fight).
local function OpenMap(map)
	if not map or InCombatLockdown() then return end
	local open = _G.OpenWorldMap
	if open then pcall(open, map) end
end

local function Create()
	arrow = CreateFrame("Frame", "WandererMapsArrow", UIParent)
	arrow:SetSize(WIDTH, HEIGHT)
	arrow:SetFrameStrata("MEDIUM")
	arrow:SetClampedToScreen(true)
	arrow:EnableMouse(true)
	arrow:SetMovable(true)
	arrow:RegisterForDrag("LeftButton")
	arrow:SetScript("OnMouseDown", function(self) self.dragged = false end)
	arrow:SetScript("OnDragStart", function(self)
		self.dragged = true
		self:StartMoving()
	end)
	arrow:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint(1)
		ns.DB().arrow = { point, x, y }
	end)
	arrow:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then return ns.ArrowCard() end
		if button == "LeftButton" and not self.dragged and self.elsewhere then OpenMap(self.elsewhere) end
	end)
	-- Moved with every other piece in Wanderer's placing mode too, its place kept here as before.
	if W.Placeable then
		W.Placeable({ key = "mapsArrow", label = function() return L.ARROW_PLACE end, frame = arrow,
			load = function() return ns.DB().arrow end, save = function(spot) ns.DB().arrow = spot end,
			enabled = function()
				local settings = ns.Settings()
				return settings and settings.enabled and settings.arrow and true or false
			end,
			default = { "TOP", "TOP", 0, -140 } })
	end
	local saved = ns.DB().arrow
	-- (placed by Wanderer; an older one: here, the same place)
	if not (W.PlaceApply and W.PlaceApply("mapsArrow", arrow)) then
		if type(saved) == "table" and saved[1] then
			arrow:SetPoint(saved[1], UIParent, saved[1], saved[2], saved[3])
		else
			arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
		end
	end
	if arrow.SetIgnoreParentAlpha then arrow:SetIgnoreParentAlpha(true) end
	arrow.title = Skin.Text(arrow, "GameFontNormal", "gold")
	arrow.title:SetPoint("TOP", arrow, "TOP", 0, -2)
	arrow.title:SetWidth(WIDTH - 8)
	arrow.title:SetJustifyH("CENTER")
	if arrow.title.SetWordWrap then arrow.title:SetWordWrap(false) end
	arrow.sub = Skin.Text(arrow, "GameFontHighlightSmall", "muted")
	arrow.sub:SetPoint("TOP", arrow.title, "BOTTOM", 0, -2)
	arrow.sub:SetWidth(WIDTH - 8)
	arrow.sub:SetJustifyH("CENTER")
	if arrow.sub.SetWordWrap then arrow.sub:SetWordWrap(false) end
	arrow.texture = arrow:CreateTexture(nil, "ARTWORK")
	arrow.texture:SetSize(ARROW_SIZE, ARROW_SIZE)
	arrow.texture:SetPoint("CENTER", arrow, "CENTER", 0, -4)
	arrow.texture:SetTexture(ns.QUEST_ARROW)
	arrow.texture:SetVertexColor(Skin.COLORS.gold[1], Skin.COLORS.gold[2], Skin.COLORS.gold[3])
	arrow.check = Skin.Glyph(arrow, "check", 26)
	arrow.check:SetPoint("CENTER", arrow, "CENTER", 0, -4)
	arrow.check:SetVertexColor(Skin.COLORS.good[1], Skin.COLORS.good[2], Skin.COLORS.good[3])
	arrow.check:Hide()
	arrow.distance = Skin.Text(arrow, "GameFontHighlightSmall", "text")
	arrow.distance:SetPoint("BOTTOM", arrow, "BOTTOM", 0, 16)
	arrow.distance:SetWidth(WIDTH - 8)
	arrow.distance:SetJustifyH("CENTER")
	if arrow.distance.SetWordWrap then arrow.distance:SetWordWrap(false) end
	-- (the step's number and the whole route's time, quieter, under the distance)
	arrow.steps = Skin.Text(arrow, "GameFontHighlightSmall", "muted")
	arrow.steps:SetPoint("BOTTOM", arrow, "BOTTOM", 0, 2)
	arrow.steps:SetWidth(WIDTH - 8)
	arrow.steps:SetJustifyH("CENTER")
	if arrow.steps.SetWordWrap then arrow.steps:SetWordWrap(false) end
	-- (it says it points as the crow flies: the roads and passes are yours to find, a choice and not a fault)
	Skin.Tooltip(arrow, function(self)
		return (self.elsewhere and (L.ARROW_TIP .. "\n" .. L.ARROW_MAP_TIP) or L.ARROW_TIP) .. "\n" .. L.ARROW_CROW
	end, "ANCHOR_BOTTOM")
	driver = CreateFrame("Frame")
	driver:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < STEP then return end
		since = 0
		Look()
	end)
	arrow:Hide()
end

-- Shown or hidden as what is followed asks (the look runs while it is shown).
function ns.RefreshArrow()
	if not arrow then Create() end
	if ns.Followed() or ending or ns.Corpse() then
		-- (the way's end goes on a moment: the look runs until the arrow is gone)
		driver:Show()
		since = STEP
		Look()
	else
		PlaceGamePin(nil)
		driver:Hide()
		arrow:Hide()
	end
end

function ns.InitArrow()
	ns.RefreshArrow()
	ns.OnChanged(ns.RefreshArrow)
	local events = CreateFrame("Frame")
	-- (a death, a release, a resurrection: the corpse's arrow comes and goes)
	for _, event in ipairs({ "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
		"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
		pcall(events.RegisterEvent, events, event)
	end
	-- (back in the world: the way planned again from where you stand)
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then return ns.Replan() end
		ns.RefreshArrow()
	end)
end
