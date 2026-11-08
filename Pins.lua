local _, ns = ...
local L = ns.L

-- The pins on the world map: your notes (with their sign) and the steps
-- of the route (numbered), with the route as a dotted line between them
-- (from you to the step followed, then on), drawn by the game's own map
-- engine (a data provider), so they follow its zoom and its maps. Alt+click
-- on the map: the note card there. One grammar for every pin: a click, the
-- main thing (a note: its card to change, follow, put on the route or remove;
-- a step: followed); Ctrl+click: to the route (a note); Shift+click: a map
-- link in the chat's box; right click: its card. A pin takes both buttons: a
-- right click on it never reaches the map (which would zoom out).

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local TEMPLATE = "WandererMapsPinTemplate"
local ROUTE_TEMPLATE = "WandererMapsRouteTemplate"
local DOT = 5 -- a dot of the route, in pixels of the screen
local LOOK_EVERY = 0.5 -- seconds between two looks at where you stand, the map open

-- The pin ---------------------------------------------------------------------------------------------------

WandererMapsPinMixin = CreateFromMixins(MapCanvasPinMixin or {})

function WandererMapsPinMixin:OnLoad()
	if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.3) end
	if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
	self:TakeButtons()
end

-- Both buttons are the pin's: the map engine lets the right one through to the map by default (its zoom out).
function WandererMapsPinMixin:TakeButtons()
	if self.EnableMouse then self:EnableMouse(true) end
	if self.SetMouseClickEnabled then self:SetMouseClickEnabled(true) end
	if self.SetPassThroughButtons and not InCombatLockdown() then pcall(self.SetPassThroughButtons, self) end
end
-- (the engine's own check would let the right button through again)
function WandererMapsPinMixin:CheckMouseButtonPassthrough() self:TakeButtons() end

-- A note far out (a continent's map): a small dot without its sign; many of one zone: one pin with their count.
local DOT_SIZE, GROUP_SIZE = 14, 24
local function Small(self, data)
	local group = data.kind == "group"
	local size = group and GROUP_SIZE or DOT_SIZE
	self:SetSize(size, size)
	self.icon:SetSize(size, size)
	self.icon:ClearAllPoints()
	if group then
		self.icon:SetPoint("BOTTOM", self, "CENTER", 0, -4)
		ns.NoteIcon(self.icon, nil)
		self.number:SetText(tostring(data.count))
	else
		self.icon:SetPoint("CENTER", self, "CENTER", 0, 0)
		self.icon.wandererGold = nil
		self.icon:SetRotation(0)
		Skin.SetGlyph(self.icon, "dot")
		local c = Skin.COLORS.gold
		self.icon:SetVertexColor(c[1], c[2], c[3])
		self.number:SetText("")
	end
	self.icon:SetAlpha(1)
	self.number:SetTextColor(1, 1, 1)
	self:TakeButtons()
end

-- data: { kind = "note" | "step" | "dot" | "group", place, x, y (on the map shown), index (a step's number), current;
-- a group: zone, count }
function WandererMapsPinMixin:OnAcquired(data)
	self.data = data
	self:SetPosition(data.x, data.y)
	if data.kind == "dot" or data.kind == "group" then return Small(self, data) end
	self.icon:ClearAllPoints()
	self.icon:SetPoint("BOTTOM", self, "CENTER", 0, -4)
	local step = data.kind == "step"
	-- (a pin's tip on the very point: the icon stands on the frame's center)
	self:SetSize(step and 26 or 20, step and 26 or 20)
	self.icon:SetSize(step and 26 or 20, step and 26 or 20)
	-- (a step in gold, a note with its sign; the step followed stands out by its light, one done fades)
	if step then ns.StepIcon(self.icon, true) else ns.NoteIcon(self.icon, data.place.icon) end
	self.icon:SetAlpha(step and (data.place.done and 0.4 or not data.current and 0.75) or 1)
	self.number:SetText(step and tostring(data.index) or "")
	self.number:SetTextColor(1, 1, 1)
	self:TakeButtons()
end

function WandererMapsPinMixin:OnMouseEnter()
	local data = self.data
	if not data then return end
	if data.kind == "group" then
		return ns.ShowTip(self, { U.MapName(data.zone) or "", ns.TipLine(L.GROUP_COUNT:format(data.count)),
			ns.TipLine(L.GROUP_TIP, "blue") })
	end
	local lines = { data.kind == "step" and ns.StepWords(data.place) or data.place.title }
	if data.kind == "step" then
		lines[2] = ns.TipLine(L.STEP_OF:format(data.index, #ns.Route().steps))
	else
		lines[2] = ns.TipLine(U.MapName(data.place.map) or "")
		if data.place.icon then lines[3] = ns.TipLine(L[ns.NoteIconSpec(data.place.icon).word] or "", "soft") end
	end
	lines[#lines + 1] = ns.TipLine(data.kind == "step" and L.PIN_TIP or L.NOTE_PIN_TIP, "blue")
	ns.ShowTip(self, lines)
end

function WandererMapsPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

-- A click on a pin (whichever way the engine passes it on: once).
local lastClick = 0
function WandererMapsPinMixin:OnMouseClickAction(button)
	local data = self.data
	if not data or GetTime() - lastClick < 0.05 then return end
	lastClick = GetTime()
	-- (many notes of a zone: its map, where they show one by one)
	if data.kind == "group" then
		Skin.Play("click")
		if WorldMapFrame and WorldMapFrame.SetMapID and not InCombatLockdown() then pcall(WorldMapFrame.SetMapID, WorldMapFrame, data.zone) end
		return
	end
	local place = data.place
	if button == "LeftButton" and IsShiftKeyDown() then return ns.ChatLink(place.map, place.x, place.y, place.title) end
	local step = data.kind == "step"
	if button == "LeftButton" and IsControlKeyDown() then
		if step then return end
		local added = ns.AddStep(place.map, place.x, place.y, place.title)
		if added then
			ns.TouchNote(place)
			W.Print(L.ADDED_STEP:format(added.title))
		end
		return
	end
	-- (a note: its card where you clicked, to change, follow, put on the route or remove)
	if not step then
		Skin.Play("click")
		return ns.NoteCard(place.map, place.x, place.y, place)
	end
	if button == "RightButton" then return ns.StepCard(self, data.index) end
	Skin.Play("click")
	ns.FollowStep(data.index)
end
function WandererMapsPinMixin:OnMouseUp(button, upInside)
	if upInside == false then return end
	self:OnMouseClickAction(button)
end
function WandererMapsPinMixin:OnClick(button) self:OnMouseClickAction(button) end

-- The route's line -------------------------------------------------------------------------------------------
-- One pin over the whole map: dots from you to the step followed, then from step to step (those not done), as
-- many as each stretch's length asks at the map's zoom (as on the minimap), never the mouse's.

_G.WandererMapsRoutePinMixin = CreateFromMixins and CreateFromMixins(MapCanvasPinMixin or {}) or {}
local Route = _G.WandererMapsRoutePinMixin

function Route:OnLoad()
	if self.SetIgnoreGlobalPinScale then self:SetIgnoreGlobalPinScale(true) end
	if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
	self.dots = self.dots or {}
end

function Route:OnAcquired(points)
	self.points = points
	self.dots = self.dots or {}
	self:SetPosition(0.5, 0.5)
	self:OnCanvasSizeChanged()
	self.since = 0
	self:SetScript("OnUpdate", self.Look)
end

function Route:OnReleased()
	self:SetScript("OnUpdate", nil)
	for _, dot in ipairs(self.dots or {}) do dot:Hide() end
end

function Route:OnCanvasSizeChanged()
	local map = self:GetMap()
	if not map then return end
	self:SetSize(map:DenormalizeHorizontalSize(1), map:DenormalizeVerticalSize(1))
	self:Draw()
end
function Route:OnCanvasScaleChanged() self:Draw() end

-- Where you stand on the map shown (0 to 1), nil when elsewhere.
local function YouOn(map)
	local wx, wy, instance = U.Here()
	if not wx then return nil end
	local _, x, y = U.WorldToMap(instance, wx, wy, map)
	if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
	return nil
end

-- Your place looked at again now and then (you walk with the map open).
function Route:Look(elapsed)
	self.since = (self.since or 0) + elapsed
	if self.since < LOOK_EVERY then return end
	self.since = 0
	self:Draw()
end

function Route:Draw()
	local points, map = self.points, self:GetMap()
	if not (points and map) then return end
	local width, height = self:GetWidth() or 0, self:GetHeight() or 0
	if width <= 0 or height <= 0 then return end
	-- (on the screen: this pin's own units to pixels, so the dots keep their size at every zoom)
	local toScreen = (self:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
	local size = DOT / toScreen
	local mapID = map:GetMapID()
	local ax, ay = U.MapToWorld(mapID, 0, 0)
	local bx, by = U.MapToWorld(mapID, 1, 0)
	local mapYards = ax and bx and math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) or nil
	local yardsPerPixel = mapYards and mapYards / (width * toScreen) or nil
	local list = {}
	local youX, youY = YouOn(mapID)
	if youX and points[1] and points[1].current then list[1] = { youX, youY } end
	for _, point in ipairs(points) do list[#list + 1] = point end
	local count = 0
	for index = 1, #list - 1 do
		local a, b = list[index], list[index + 1]
		local dx, dy = (b[1] - a[1]) * width, (b[2] - a[2]) * height
		local spaces = ns.DotSpaces(math.sqrt(dx * dx + dy * dy) * toScreen, yardsPerPixel)
		-- (the ends are the pins: the dots between them)
		for at = 1, spaces - 1 do
			count = count + 1
			local dot = self.dots[count]
			if not dot then
				dot = self:CreateTexture(nil, "ARTWORK")
				dot:SetColorTexture(1, 0.82, 0, 0.85)
				self.dots[count] = dot
			end
			local share = at / spaces
			dot:SetSize(size, size)
			dot:ClearAllPoints()
			dot:SetPoint("CENTER", self, "TOPLEFT", (a[1] + (b[1] - a[1]) * share) * width, -(a[2] + (b[2] - a[2]) * share) * height)
			dot:Show()
		end
	end
	for index = count + 1, #self.dots do self.dots[index]:Hide() end
end

-- The notes' pins ------------------------------------------------------------------------------------------
-- Those the filter shows (by sign, or none). On a zone's map, each with its sign; on a continent's (or the
-- world's), small dots, and a zone holding GROUP_AT or more of them: one pin with their count, a click opens it.

local GROUP_AT = 5
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2

-- A map seen from far out: a continent's or wider.
function ns.FarMap(map)
	local info = C_Map and C_Map.GetMapInfo and Safe(C_Map.GetMapInfo, map)
	local kind = type(info) == "table" and Clean(info.mapType)
	return type(kind) == "number" and kind <= CONTINENT or false
end

-- The pins' data for the notes on a map: { kind = "note" | "dot" | "group", place, x, y, zone, count }.
function ns.NotePins(map)
	local pins = {}
	local far = ns.FarMap(map)
	local groups, order = {}, {}
	for _, note in ipairs(ns.Notes()) do
		if ns.NoteShown(note) then
			local x, y = ns.OnMap(note, map)
			if x and not far then
				pins[#pins + 1] = { kind = "note", place = note, x = x, y = y }
			elseif x then
				-- (by the zone it was left on; one left on this very map stays a dot)
				local key = note.map ~= map and note.map or 0
				if not groups[key] then
					groups[key] = {}
					order[#order + 1] = key
				end
				table.insert(groups[key], { kind = "dot", place = note, x = x, y = y })
			end
		end
	end
	for _, key in ipairs(order) do
		local list = groups[key]
		if key ~= 0 and #list >= GROUP_AT then
			local sx, sy = 0, 0
			for _, dot in ipairs(list) do sx, sy = sx + dot.x, sy + dot.y end
			pins[#pins + 1] = { kind = "group", zone = key, count = #list, x = sx / #list, y = sy / #list, place = list[1].place }
		else
			for _, dot in ipairs(list) do pins[#pins + 1] = dot end
		end
	end
	return pins
end

-- The notes' button on the world map: its card filters them by sign or hides them all (the minimap the same).
-- Shown while there are notes, Wanderer Maps on.
local mapButton
function ns.RefreshMapButton()
	if not WorldMapFrame then return end
	local settings = ns.Settings()
	local wanted = settings and settings.enabled and ns.Notes()[1] ~= nil
	if not mapButton then
		if not wanted then return end
		local holder = WorldMapFrame.ScrollContainer or WorldMapFrame
		mapButton = Skin.SmallButton(WorldMapFrame, "", function(self) ns.FilterCard(self) end, L.FILTER_TIP, 22)
		mapButton:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -8)
		mapButton:SetFrameStrata(WorldMapFrame:GetFrameStrata())
		mapButton:SetFrameLevel(math.min(9000, (holder:GetFrameLevel() or 1) + 1500))
	end
	local hidden = ns.NotesHidden()
	local some = false
	for _, icon in ipairs(ns.NOTE_ICONS) do some = some or ns.SignHidden(icon.key) end
	local sign = (hidden or some) and Skin.GlyphText("eyeoff", hidden and "muted" or "gold", 14) or ns.NoteIconMarkup(nil, 14)
	mapButton:SetLabel(sign .. " " .. (hidden and L.FILTER_HIDDEN or L.FILTER_BUTTON))
	mapButton:SetShown(wanted and true or false)
end

-- The provider ----------------------------------------------------------------------------------------------

local provider

local function Provider()
	if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return provider end
	provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
		self:GetMap():RemoveAllPinsByTemplate(ROUTE_TEMPLATE)
	end
	function provider:RefreshAllData()
		self:RemoveAllData()
		if InCombatLockdown() then return U.AfterFight("pins", ns.RefreshPins) end
		ns.RefreshMapButton()
		local settings = ns.Settings()
		if not (settings and settings.enabled) then return end
		local map = self:GetMap():GetMapID()
		-- (a place of a zone shows on its continent too, and the other way; far out, small)
		for _, pin in ipairs(ns.NotePins(map)) do self:GetMap():AcquirePin(TEMPLATE, pin) end
		local route = ns.Route()
		local line = {}
		for index, step in ipairs(route.steps) do
			local x, y = ns.OnMap(step, map)
			if x then
				local current = index == route.current
				self:GetMap():AcquirePin(TEMPLATE, { kind = "step", place = step, x = x, y = y, index = index, current = current })
				-- (the line: from the step followed on, the ones done left out)
				if index >= route.current and not step.done then line[#line + 1] = { x, y, current = current } end
			end
		end
		if line[1] and (line[2] or line[1].current) then self:GetMap():AcquirePin(ROUTE_TEMPLATE, line) end
	end
	WorldMapFrame:AddDataProvider(provider)
	return provider
end

function ns.RefreshPins()
	local made = Provider()
	if made and WorldMapFrame:IsShown() then made:RefreshAllData() end
end

-- Alt+click on the map: the note card there (its name, its sign). Through the map's own click handlers, before
-- them: the click is taken, the map neither zooms nor sets its pin.
local function NoteAt(map, x, y)
	local settings = ns.Settings()
	if not (settings and settings.enabled) or not (map and x and y) then return false end
	return ns.NoteCard(map, x, y)
end

local function OnCanvasClick(canvas, button, x, y)
	if button ~= "LeftButton" or not IsAltKeyDown() then return false end
	return NoteAt(Clean(Safe(canvas.GetMapID, canvas)), Clean(x), Clean(y))
end

function ns.InitPins()
	if not WorldMapFrame then return end
	Provider()
	WorldMapFrame:AddCanvasClickHandler(OnCanvasClick, 100)
	ns.OnChanged(ns.RefreshPins)
end
