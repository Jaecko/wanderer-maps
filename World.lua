local _, ns = ...

-- The world in one piece (options, on): on a continent's map, every zone's own land drawn where it lies,
-- its pieces as sharp as on the zone's map, so the continent reads as one map instead of a picture with
-- zones on it; the land you have not explored yet, softened. On a zone's map, its land you have not
-- explored yet, softened too, where the game leaves blank parchment.
--
-- The pieces are the game's own (WorldData.lua, from its tables); drawn by the map's own engine (a data
-- provider and one pin, as the game draws what you have explored), so its zoom, its pins and its clicks stay
-- as they are: nothing of the game's map is moved or replaced. A zone whose pieces the game changed since
-- (a patch) shows only what the game itself says you have explored there.
-- Beside the zone's name in the map's bar (options): how many of its areas you have explored ("explored
-- 12 / 18"), from the same pieces; and the zone's facts the game never says on Forever: its levels, in the
-- color of their difficulty for you, and the fishing skill its waters ask, when you fish (Wanderer's world data).

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

local TEMPLATE = "WandererMapsWorldTemplate"
local UNKNOWN_COLOR = { 0.78, 0.72, 0.6 } -- the land not explored yet: dimmer, warmer, without color
local UNKNOWN_ALPHA = 0.7

local provider
local count -- the words beside the zone's name


local function MapType(map)
	local info = map and Safe(C_Map.GetMapInfo, map)
	return info and Clean(info.mapType), info and Clean(info.parentMapID)
end

-- The pieces you have explored in a zone, by their first picture; nil when the game's pieces of that zone
-- are not those of the data (the data is then not used there).
local function Explored(zone, pieces)
	local seen, known = {}, {}
	for _, piece in ipairs(pieces) do known[piece[5]] = true end
	local list = Safe(C_MapExplorationInfo.GetExploredMapTextures, zone)
	for _, info in ipairs(type(list) == "table" and list or {}) do
		local first = info.fileDataIDs and Clean(info.fileDataIDs[1])
		if first then
			if not known[first] then return nil end
			seen[first] = true
		end
	end
	return seen
end

-- How many areas of a zone you have explored: explored, all (nil: the game's pieces are not the data's).
function ns.ExploredCount(zone)
	local pieces = ns.WORLD_PIECES and ns.WORLD_PIECES[zone]
	local explored = pieces and Explored(zone, pieces)
	if not explored then return nil end
	local seen, all, counted = 0, 0, {}
	for _, piece in ipairs(pieces) do
		local first = piece[5]
		if first and not counted[first] then
			counted[first] = true
			all = all + 1
			if explored[first] then seen = seen + 1 end
		end
	end
	if all == 0 then return nil end
	return seen, all
end

-- The words beside the zone's name: after the last name of the map's bar (where the game names the map shown).
local function CountText()
	if count then return count end
	local bar = WorldMapFrame and WorldMapFrame.NavBar
	if not bar then return nil end
	count = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	count:SetTextColor(0.78, 0.72, 0.6)
	count:SetShadowOffset(1, -1)
	count:SetShadowColor(0, 0, 0, 0.9)
	return count
end

local FISHING_LINE = 356 -- (the fishing skill's line)
local GOOD, MIDDLE, LOW = { 0.25, 0.75, 0.25 }, { 1, 0.82, 0 }, { 1, 0.1, 0.1 }

-- Your fishing skill (nil: you do not fish).
local function FishingSkill()
	for _, profession in ipairs(U.Professions()) do
		if profession.line == FISHING_LINE then return profession.rank end
	end
	return nil
end

-- A zone's facts, in words: its levels in the color of their difficulty for you (the quest log's own colors:
-- yours inside the range, the nearer end's outside it), its fishing in yours (red: nothing bites yet, yellow:
-- some get away, green: none); nil when there is nothing to say.
function ns.ZoneFacts(map)
	local levels = W.ZoneLevels and W.ZoneLevels(map, true)
	if type(levels) ~= "table" then return nil end
	local parts = {}
	if levels.low and levels.high then
		local level = Clean(Safe(UnitLevel, "player")) or levels.low
		local r, g, b = W.QuestLevelColor(math.max(levels.low, math.min(levels.high, level)))
		local range = levels.low == levels.high and tostring(levels.low) or (levels.low .. "-" .. levels.high)
		parts[#parts + 1] = ns.L.ZONE_LEVELS:format(U.Colorize(range, r, g, b))
	end
	local skill = levels.fishLow and FishingSkill()
	if skill then
		local color = skill >= levels.fishHigh and GOOD or skill >= levels.fishLow and MIDDLE or LOW
		parts[#parts + 1] = ns.L.ZONE_FISHING:format(U.Colorize(levels.fishLow .. "-" .. levels.fishHigh, color[1], color[2], color[3]))
	end
	if not parts[1] then return nil end
	return table.concat(parts, U.SEPARATOR)
end

local function ShowCount(map, kind)
	local text = CountText()
	if not text then return end
	local settings = ns.Settings()
	local types = Enum and Enum.UIMapType
	local parts = {}
	if settings and settings.enabled and types and kind == types.Zone then
		parts[#parts + 1] = settings.zoneFacts and ns.ZoneFacts(map) or nil
		local seen, all
		if settings.explored then seen, all = ns.ExploredCount(map) end
		if seen then parts[#parts + 1] = ns.L.EXPLORED_COUNT:format(seen, all) end
	end
	if not parts[1] then return text:Hide() end
	local bar = WorldMapFrame.NavBar
	local list = type(bar.navList) == "table" and bar.navList
	local last = list and list[#list]
	text:ClearAllPoints()
	if last and last.IsShown and last:IsShown() then
		text:SetPoint("LEFT", last, "RIGHT", 10, 0)
	else
		text:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
	end
	text:SetText(table.concat(parts, U.SEPARATOR))
	text:Show()
end

-- The pin: one, over the whole map, holding the pictures -----------------------------------------------------

WandererMapsWorldPinMixin = CreateFromMixins(MapCanvasPinMixin or {})

function WandererMapsWorldPinMixin:OnLoad()
	self:SetIgnoreGlobalPinScale(true)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_EXPLORATION")
	self:Pool()
end

function WandererMapsWorldPinMixin:OnAcquired()
	self:SetPosition(0.5, 0.5)
	self:OnCanvasSizeChanged()
	self:RefreshAlpha()
end

-- As see-through as the map is (the game's own setting, while you move).
function WandererMapsWorldPinMixin:RefreshAlpha()
	local map = self:GetMap()
	self:SetAlpha(map.GetGlobalAlpha and map:GetGlobalAlpha() or 1)
end

function WandererMapsWorldPinMixin:OnCanvasSizeChanged()
	local map = self:GetMap()
	self:SetSize(map:DenormalizeHorizontalSize(1), map:DenormalizeVerticalSize(1))
end

-- Its pictures' pool, made at its first need (OnLoad may come after the game's pool first resets it).
function WandererMapsWorldPinMixin:Pool()
	self.pool = self.pool or CreateTexturePool(self, "ARTWORK", -1)
	return self.pool
end

-- (the game's pool may reset a pin it has just made, before its OnLoad: nothing to let go yet)
function WandererMapsWorldPinMixin:OnReleased()
	if self.pool then self.pool:ReleaseAll() end
end

-- One piece of a zone, its pictures laid as the game lays them (tiles of the layer's size, the last ones
-- cut to the piece), placed at (left, top) and grown by (scaleX, scaleY), on the canvas.
function WandererMapsWorldPinMixin:DrawPiece(piece, left, top, scaleX, scaleY, tileWidth, tileHeight, unknown)
	local width, height = piece[3], piece[4]
	local wide, tall = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
	local canvas = self:GetMap()
	for row = 1, tall do
		local pixelsTall, fileTall = tileHeight, tileHeight
		if row == tall then
			pixelsTall = height % tileHeight
			if pixelsTall == 0 then pixelsTall = tileHeight end
			fileTall = 16
			while fileTall < pixelsTall do fileTall = fileTall * 2 end
		end
		for column = 1, wide do
			local file = piece[4 + (row - 1) * wide + column]
			if file then
				local pixelsWide, fileWide = tileWidth, tileWidth
				if column == wide then
					pixelsWide = width % tileWidth
					if pixelsWide == 0 then pixelsWide = tileWidth end
					fileWide = 16
					while fileWide < pixelsWide do fileWide = fileWide * 2 end
				end
				local texture = self:Pool():Acquire()
				if not texture.wandererMasked then
					canvas:AddMaskableTexture(texture)
					texture.wandererMasked = true
				end
				texture:SetSize(pixelsWide * scaleX, pixelsTall * scaleY)
				texture:SetTexCoord(0, pixelsWide / fileWide, 0, pixelsTall / fileTall)
				texture:SetPoint("TOPLEFT", left + (piece[1] + tileWidth * (column - 1)) * scaleX,
					-(top + (piece[2] + tileHeight * (row - 1)) * scaleY))
				texture:SetTexture(file, nil, nil, "TRILINEAR")
				texture:SetDesaturated(unknown)
				if unknown then
					texture:SetVertexColor(UNKNOWN_COLOR[1], UNKNOWN_COLOR[2], UNKNOWN_COLOR[3], UNKNOWN_ALPHA)
				else
					texture:SetVertexColor(1, 1, 1, 1)
				end
				texture:Show()
			end
		end
	end
end

-- A zone's pieces on the map shown: all of them on its continent, those not explored yet on its own map.
function WandererMapsWorldPinMixin:DrawZone(zone, map, own)
	local pieces = ns.WORLD_PIECES[zone]
	local settings = ns.Settings()
	local explored = Explored(zone, pieces)
	local layers = Safe(C_Map.GetMapArtLayers, zone)
	local layer = type(layers) == "table" and layers[1]
	if not (explored and layer and Clean(layer.layerWidth) and Clean(layer.tileWidth)) then return end
	local left, top, scaleX, scaleY = 0, 0, 1, 1
	if not own then
		local x0, x1, y0, y1 = Safe(C_Map.GetMapRectOnMap, zone, map)
		x0, x1, y0, y1 = Clean(x0), Clean(x1), Clean(y0), Clean(y1)
		if not (x0 and x1 and y0 and y1) or x1 <= x0 or y1 <= y0 then return end
		local width, height = self:GetMap():DenormalizeHorizontalSize(1), self:GetMap():DenormalizeVerticalSize(1)
		left, top = x0 * width, y0 * height
		scaleX, scaleY = (x1 - x0) * width / layer.layerWidth, (y1 - y0) * height / layer.layerHeight
	end
	for _, piece in ipairs(pieces) do
		local unknown = not explored[piece[5]]
		-- (on its own map, the game draws the explored ones; elsewhere, the unexplored ones only when asked)
		if (own and unknown) or (not own and (not unknown or settings.unexplored)) then
			self:DrawPiece(piece, left, top, scaleX, scaleY, layer.tileWidth, layer.tileHeight, unknown)
		end
	end
end

function WandererMapsWorldPinMixin:Refresh()
	self:Pool():ReleaseAll()
	local settings = ns.Settings()
	local map = Clean(self:GetMap():GetMapID())
	local kind = MapType(map)
	-- (the words beside the zone's name need no pieces)
	ShowCount(map, kind)
	if not (settings and settings.enabled and ns.WORLD_PIECES) then return end
	local types = Enum and Enum.UIMapType
	if not (map and types) then return end
	if kind == types.Continent and settings.world then
		for zone in pairs(ns.WORLD_PIECES) do
			local _, parent = MapType(zone)
			if parent == map then self:DrawZone(zone, map, false) end
		end
	elseif kind == types.Zone and settings.unexplored and ns.WORLD_PIECES[map] then
		self:DrawZone(map, map, true)
	end
end

-- The provider --------------------------------------------------------------------------------------------

local function Provider()
	if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return provider end
	provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:OnAdded(canvas)
		MapCanvasDataProviderMixin.OnAdded(self, canvas)
		self.pin = canvas:AcquirePin(TEMPLATE)
	end
	function provider:OnRemoved(canvas)
		canvas:RemoveAllPinsByTemplate(TEMPLATE)
		MapCanvasDataProviderMixin.OnRemoved(self, canvas)
	end
	function provider:OnShow() self:RegisterEvent("MAP_EXPLORATION_UPDATED") end
	function provider:OnHide() self:UnregisterEvent("MAP_EXPLORATION_UPDATED") end
	function provider:OnEvent() self:RefreshAllData() end
	function provider:OnGlobalAlphaChanged() if self.pin then self.pin:RefreshAlpha() end end
	function provider:RemoveAllData() if self.pin then self.pin:Pool():ReleaseAll() end end
	function provider:RefreshAllData()
		if not self.pin then return end
		-- (in a fight: the pieces put away, drawn again after it)
		if InCombatLockdown() then
			self:RemoveAllData()
			return U.AfterFight("world", ns.RefreshWorld)
		end
		self.pin:Refresh()
	end
	WorldMapFrame:AddDataProvider(provider)
	return provider
end

function ns.RefreshWorld()
	local made = Provider()
	if made and WorldMapFrame:IsShown() then made:RefreshAllData() end
end

function ns.InitWorld()
	if not (WorldMapFrame and C_Map and C_MapExplorationInfo and CreateTexturePool) then return end
	Provider()
	ns.OnChanged(ns.RefreshWorld)
end
