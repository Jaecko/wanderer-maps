local ADDON, ns = ...
local L = ns.L

-- The atlas: the big map, in a window of ours, opened by the game's map key. The map's own pictures (those the
-- game draws), your quests and their objectives, your route, your notes, the world's places; one panel to read a
-- place instead of a pile of tooltips. Nothing of the game's own map is touched, so anything can be done here in
-- a fight too; the game's map stays one click away. This file is the canvas: the pictures, the zoom, the pan, the
-- window. What is drawn on it and the panels are in AtlasContent.lua.

local W = Wanderer
local U = W and W.Util
local Skin = W and W.Skin
local Safe, Clean = U and U.Safe, U and U.Clean

local WIDTH_MOST, HEIGHT_MOST = 1320, 820
local WIDTH_LEAST, HEIGHT_LEAST = 860, 540
local SCREEN_SHARE = 0.88
local TOP = 56
local RIGHT_COLUMN = 290
local STRIP = 44
local ZOOMS = { 1, 1.6, 2.5, 4, 6 }
local ZOOM_SPEED = 14
local DRAG_LEAST = 4 -- pixels before a press on the map is a drag
local FOLLOW_EVERY = 0.1 -- seconds between two readings of where you are
local EASTERN_KINGDOMS = 1415 -- (where nothing says where you are)
-- The other addons that are this same big map: the key stays theirs.
local SAME_JOB = { "OpenMap", "EndlessMap", "AzerothUnrolled", "Waymark", "ForeverMaps" }

local window, ui
local map, mapWide, mapTall -- the map shown, the size of its pictures
local fit, zoom, zoomGoal, anchorX, anchorY, anchorMapX, anchorMapY = 1, 1, 1, 0, 0, 0, 0
local offsetX, offsetY = 0, 0
local press -- the press under way on the map
local tiles, land
local followedAt = 0

function ns.AtlasFrame() return window end
function ns.AtlasMap() return map end
function ns.AtlasZoom() return zoom end
function ns.AtlasMapSize() return mapWide, mapTall end
function ns.AtlasScale() return math.max(fit * zoom, 0.01) end
function ns.AtlasUI() return ui end

local function Db()
	local db = ns.DB()
	db.atlas = type(db.atlas) == "table" and db.atlas or {}
	return db.atlas
end
ns.AtlasDb = Db

local function MapInfo(id)
	local info = id and Safe(C_Map.GetMapInfo, id)
	return type(info) == "table" and info or nil
end

-- The projection -----------------------------------------------------------------------------------------------

local function Scale() return math.max(fit * zoom, 0.01) end

-- A place of the map (0 to 1) -> the canvas (pixels from its top left).
function ns.AtlasProject(x, y) return offsetX + x * mapWide * Scale(), offsetY + y * mapTall * Scale() end

-- The cursor on the canvas, and on the map (nil, nil: off it).
function ns.AtlasCursor()
	local x, y = GetCursorPosition()
	local scale = ui.clip:GetEffectiveScale()
	local cx, cy = x / scale - (ui.clip:GetLeft() or 0), (ui.clip:GetTop() or 0) - y / scale
	local mx, my = (cx - offsetX) / (mapWide * Scale()), (cy - offsetY) / (mapTall * Scale())
	if mx < 0 or mx > 1 or my < 0 or my > 1 then return cx, cy, nil, nil end
	return cx, cy, mx, my
end

local function Clamp()
	local wide, tall = ui.clip:GetWidth(), ui.clip:GetHeight()
	local drawnWide, drawnTall = mapWide * Scale(), mapTall * Scale()
	if drawnWide <= wide then offsetX = (wide - drawnWide) / 2 else offsetX = math.min(0, math.max(wide - drawnWide, offsetX)) end
	if drawnTall <= tall then offsetY = (tall - drawnTall) / 2 else offsetY = math.min(0, math.max(tall - drawnTall, offsetY)) end
end

-- Everything where the zoom and the pan say.
local function Apply()
	Clamp()
	local scale = Scale()
	ui.world:SetScale(scale)
	ui.world:ClearAllPoints()
	ui.world:SetPoint("TOPLEFT", ui.clip, "TOPLEFT", offsetX / scale, -offsetY / scale)
	ns.AtlasPlacePins()
end
ns.AtlasApply = Apply

local function FitToCanvas()
	local wide, tall = ui.clip:GetWidth(), ui.clip:GetHeight()
	if not (mapWide and wide and wide > 0 and tall > 0) then return end
	fit = math.min(wide / mapWide, tall / mapTall)
end

-- The pictures ---------------------------------------------------------------------------------------------------

local function DrawTiles()
	tiles:ReleaseAll()
	land:ReleaseAll()
	-- (the game's own ground under its pictures: they are see-through in places)
	local groundAtlas = C_Map.GetMapArtBackgroundAtlas and Clean(Safe(C_Map.GetMapArtBackgroundAtlas, map))
	ui.backdrop:SetShown(groundAtlas ~= nil and U.HasAtlas(groundAtlas))
	if ui.backdrop:IsShown() then ui.backdrop:SetAtlas(groundAtlas) end
	local layers = Safe(C_Map.GetMapArtLayers, map)
	local layer = type(layers) == "table" and layers[1]
	if not layer then return false end
	local layerWide, layerTall = Clean(layer.layerWidth), Clean(layer.layerHeight)
	local tileWide, tileTall = Clean(layer.tileWidth), Clean(layer.tileHeight)
	if not (layerWide and layerTall and tileWide and tileTall) then return false end
	mapWide, mapTall = layerWide, layerTall
	ui.world:SetSize(mapWide, mapTall)
	local files = Safe(C_Map.GetMapArtLayerTextures, map, 1)
	local columns, rows = math.ceil(layerWide / tileWide), math.ceil(layerTall / tileTall)
	for row = 1, rows do
		for column = 1, columns do
			local file = type(files) == "table" and Clean(files[(row - 1) * columns + column])
			if file then
				local tile = tiles:Acquire()
				tile:SetSize(tileWide, tileTall)
				tile:ClearAllPoints()
				tile:SetPoint("TOPLEFT", ui.world, "TOPLEFT", (column - 1) * tileWide, -(row - 1) * tileTall)
				tile:SetTexture(file, nil, nil, "TRILINEAR")
				tile:Show()
			end
		end
	end
	-- What you explored, and the land of a continent's zones.
	local target = { width = mapWide, height = mapTall, Acquire = function()
		local texture = land:Acquire()
		texture:ClearAllPoints()
		return texture
	end }
	local info = MapInfo(map)
	local kind = info and Clean(info.mapType)
	if ns.WORLD_PIECES and ns.WORLD_PIECES[map] then
		ns.DrawLand(target, map, kind, true)
	else
		ns.DrawExplored(target, map)
		if Enum and Enum.UIMapType and kind == Enum.UIMapType.Continent then ns.DrawLand(target, map, kind, false) end
	end
	return true
end

-- Zoom and pan -------------------------------------------------------------------------------------------------

local function ZoomToward(goal, cx, cy)
	zoomGoal = math.max(ZOOMS[1], math.min(ZOOMS[#ZOOMS], goal))
	anchorX, anchorY = cx, cy
	local scale = Scale()
	anchorMapX, anchorMapY = (cx - offsetX) / scale, (cy - offsetY) / scale
end

-- One notch in or out, toward what is under the mouse.
local function Notch(direction, cx, cy)
	local index = 1
	for at, value in ipairs(ZOOMS) do
		if value <= zoomGoal + 0.01 then index = at end
	end
	if not cx then cx, cy = ui.clip:GetWidth() / 2, ui.clip:GetHeight() / 2 end
	ZoomToward(ZOOMS[math.max(1, math.min(#ZOOMS, index + direction))], cx, cy)
end
ns.AtlasNotch = Notch

-- The whole map again: always one click away; already whole, the map around it.
function ns.AtlasReset()
	if zoomGoal <= ZOOMS[1] then return ns.AtlasUp() end
	ZoomToward(ZOOMS[1], ui.clip:GetWidth() / 2, ui.clip:GetHeight() / 2)
end

-- A place brought to the middle, at this zoom or closer.
function ns.AtlasFocus(x, y, least)
	if least and zoomGoal < least then zoomGoal = least end
	zoom = zoomGoal
	offsetX = ui.clip:GetWidth() / 2 - x * mapWide * Scale()
	offsetY = ui.clip:GetHeight() / 2 - y * mapTall * Scale()
	Apply()
end

local function Animate(elapsed)
	if math.abs(zoom - zoomGoal) < 0.004 then
		if zoom ~= zoomGoal then
			zoom = zoomGoal
			offsetX, offsetY = anchorX - anchorMapX * Scale(), anchorY - anchorMapY * Scale()
			Apply()
			ns.AtlasDrawPins()
			ns.AtlasDrawZones()
		end
		return
	end
	zoom = zoom + (zoomGoal - zoom) * math.min(1, elapsed * ZOOM_SPEED)
	offsetX, offsetY = anchorX - anchorMapX * Scale(), anchorY - anchorMapY * Scale()
	Apply()
end

-- The map shown ---------------------------------------------------------------------------------------------------

function ns.AtlasSetMap(id)
	if not id or not MapInfo(id) then return false end
	map = id
	if not DrawTiles() then
		-- (a place with no picture of its own, a dungeon's inside: the map around it)
		local info = MapInfo(id)
		local parent = info and Clean(info.parentMapID)
		if parent and parent ~= 0 then return ns.AtlasSetMap(parent) end
		return false
	end
	FitToCanvas()
	zoom, zoomGoal = ZOOMS[1], ZOOMS[1]
	offsetX, offsetY = 0, 0
	Apply()
	ns.AtlasMapChanged()
	return true
end

-- Up to the map around this one (a continent, the world).
function ns.AtlasUp()
	local info = MapInfo(map)
	local parent = info and Clean(info.parentMapID)
	if parent and parent ~= 0 and MapInfo(parent) then ns.AtlasSetMap(parent) end
end

-- The map where you are (the zone, else what is around it).
local function WhereYouAre()
	local here = Clean(Safe(C_Map.GetBestMapForUnit, "player"))
	return here or Db().map or EASTERN_KINGDOMS
end

local function Relayout()
	if not (ui and map) then return end
	local walking = Db().walk and true or false
	ui.side:SetShown(not walking)
	ui.card:SetShown(not walking)
	ui.clip:ClearAllPoints()
	ui.clip:SetPoint("TOPLEFT", window, "TOPLEFT", ui.margin, -TOP)
	ui.clip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -ui.margin - (walking and 0 or RIGHT_COLUMN + 10), ui.margin + STRIP)
	window:SetAlpha(walking and 0.82 or 1)
	FitToCanvas()
	Apply()
	ns.AtlasFitLegend()
end
ns.AtlasRelayout = Relayout

function ns.AtlasWalk()
	Db().walk = not Db().walk or nil
	Skin.Play("click")
	Relayout()
	ns.AtlasDrawHeader()
end

-- The mouse on the map ---------------------------------------------------------------------------------------------

local function ChildAt(x, y)
	local info = Safe(C_Map.GetMapInfoAtPosition, map, x, y)
	local child = type(info) == "table" and Clean(info.mapID)
	if child and child ~= map then return child, Clean(info.name) end
	return nil
end
ns.AtlasChildAt = ChildAt

local function PressDown(_, button)
	if button ~= "LeftButton" and button ~= "RightButton" then return end
	local cx, cy = ns.AtlasCursor()
	press = { button = button, cx = cx, cy = cy, ox = offsetX, oy = offsetY }
end

local function PressUp(_, button)
	local done = press
	press = nil
	if not done or done.moved or done.button ~= button then return end
	local _, _, mx, my = ns.AtlasCursor()
	if mx then ns.AtlasClick(button, mx, my) end
end

local function PressMove()
	if not press or press.button ~= "LeftButton" then return end
	local cx, cy = ns.AtlasCursor()
	if not press.moved and math.abs(cx - press.cx) + math.abs(cy - press.cy) < DRAG_LEAST then return end
	press.moved = true
	offsetX, offsetY = press.ox + cx - press.cx, press.oy + cy - press.cy
	Apply()
end

local function Tick(_, elapsed)
	Animate(elapsed)
	PressMove()
	followedAt = followedAt + elapsed
	if followedAt >= FOLLOW_EVERY then
		followedAt = 0
		ns.AtlasFollow()
	end
end

-- The window ------------------------------------------------------------------------------------------------------

local function StartingSize()
	local db = Db()
	local screenWide, screenTall = UIParent:GetWidth(), UIParent:GetHeight()
	local wide = db.w or math.min(WIDTH_MOST, screenWide * SCREEN_SHARE)
	local tall = db.h or math.min(HEIGHT_MOST, screenTall * SCREEN_SHARE)
	return math.max(WIDTH_LEAST, wide), math.max(HEIGHT_LEAST, tall)
end

local function Create()
	window = Skin.CreateWindow("WandererMapsAtlas", "MEDIUM")
	window:SetSize(StartingSize())
	window:Hide()
	Skin.Sounds(window, Skin.SOUNDS.open, Skin.SOUNDS.close)
	Skin.Dress(window, { "CENTER", UIParent, "CENTER", 0, 10 }, "mapsAtlasPos")
	local _, title, margin = Skin.Header(window, "Wanderer", L.ATLAS, { settings = "ext:maps" })
	ui = { margin = margin, title = title, pins = {}, rows = {} }
	local clip = CreateFrame("Frame", nil, window)
	clip:SetClipsChildren(true)
	clip:EnableMouse(true)
	clip:EnableMouseWheel(true)
	ui.clip = clip
	local ground = clip:CreateTexture(nil, "BACKGROUND", nil, -8)
	ground:SetAllPoints()
	ground:SetColorTexture(0.04, 0.07, 0.11, 1)
	Skin.Edges(clip, 1, 0.82, 0, 0.16)
	ui.world = CreateFrame("Frame", nil, clip)
	ui.world:SetSize(1, 1)
	ui.overlay = CreateFrame("Frame", nil, clip)
	ui.overlay:SetAllPoints()
	ui.overlay:SetFrameLevel(ui.world:GetFrameLevel() + 10)
	ui.backdrop = ui.world:CreateTexture(nil, "BACKGROUND", nil, -7)
	ui.backdrop:SetAllPoints()
	tiles = CreateTexturePool(ui.world, "BACKGROUND", 0)
	land = CreateTexturePool(ui.world, "BORDER", 0)
	clip:SetScript("OnMouseDown", PressDown)
	clip:SetScript("OnMouseUp", PressUp)
	clip:SetScript("OnMouseWheel", function(_, delta)
		local cx, cy = ns.AtlasCursor()
		Notch(delta > 0 and 1 or -1, cx, cy)
	end)
	clip:SetScript("OnEnter", function() ui.overCanvas = true end)
	clip:SetScript("OnLeave", function() ui.overCanvas = false end)
	window:SetScript("OnUpdate", Tick)
	ns.AtlasBuildContent(window, margin, TOP, RIGHT_COLUMN, STRIP)
	-- (its size is yours: a corner to pull)
	window:SetResizable(true)
	if window.SetResizeBounds then window:SetResizeBounds(WIDTH_LEAST, HEIGHT_LEAST, WIDTH_MOST + 500, HEIGHT_MOST + 300) end
	local grip = Skin.GlyphButton(window, "move", 12, L.ATLAS_RESIZE, function() end)
	grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
	grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		window:StopMovingOrSizing()
		Db().w, Db().h = window:GetWidth(), window:GetHeight()
		Relayout()
	end)
	window:HookScript("OnSizeChanged", function() Relayout() end)
	window:HookScript("OnShow", function() ns.AtlasListen(true) end)
	window:HookScript("OnHide", function()
		ns.AtlasListen(false)
		press = nil
		Db().map = map
	end)
end

-- Opens it on a map (none: where you are), at a place of it if given.
function ns.AtlasShow(id, x, y)
	if not window then Create() end
	local wasShown = window:IsShown()
	window:Show()
	local goal = id or (not wasShown and WhereYouAre()) or map or WhereYouAre()
	if goal and (goal ~= map or not wasShown) then ns.AtlasSetMap(goal) end
	Relayout()
	if x and y then ns.AtlasFocus(x, y, ZOOMS[3]) end
	ns.AtlasRefresh()
end

function ns.AtlasToggle()
	if window and window:IsShown() then return window:Hide() end
	ns.AtlasShow()
end

-- To the game's own map (it stays one click away; never in a fight, the game refuses it there).
function ns.AtlasToGameMap()
	if InCombatLockdown() then return W.Print(L.ATLAS_NOT_IN_FIGHT) end
	if window then window:Hide() end
	if ToggleWorldMap then pcall(ToggleWorldMap) end
end

-- The game's map key opens the atlas: for this session only, your key bindings stay as they are, and the key goes
-- back by itself when this is off.
local keyOwner, takenKeys
local function SameJob()
	local api = C_AddOns and C_AddOns.IsAddOnLoaded
	for _, name in ipairs(SAME_JOB) do
		if api and Clean(Safe(api, name)) then return true end
	end
	return false
end

function ns.AtlasPlaceKey()
	if InCombatLockdown() then return U.AfterFight("mapsAtlasKey", ns.AtlasPlaceKey) end
	local settings = ns.Settings()
	local keys = {}
	if settings and settings.enabled and settings.atlas and GetBindingKey and not SameJob() then keys = { GetBindingKey("TOGGLEWORLDMAP") } end
	local words = table.concat(keys, ",")
	if words == (takenKeys or "") then return end
	takenKeys = words
	keyOwner = keyOwner or CreateFrame("Frame")
	Safe(ClearOverrideBindings, keyOwner)
	for _, key in ipairs(keys) do Safe(SetOverrideBinding, keyOwner, false, key, "WANDERERMAPS_ATLAS") end
end

BINDING_NAME_WANDERERMAPS_ATLAS = L.ATLAS
function WandererMaps_Atlas()
	local settings = ns.Settings()
	if settings and settings.enabled then ns.AtlasToggle() end
end

function ns.InitAtlas()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD" }) do events:RegisterEvent(event) end
	events:SetScript("OnEvent", function() ns.AtlasPlaceKey() end)
	ns.OnChanged(function()
		ns.AtlasPlaceKey()
		local settings = ns.Settings()
		if window and window:IsShown() then
			if settings and settings.enabled then ns.AtlasRefresh() else window:Hide() end
		end
	end)
end

-- The diagnostic: what this client really gives the atlas (/wmaps atlas), in the saved variables.
function ns.AtlasDump()
	local here = Clean(Safe(C_Map.GetBestMapForUnit, "player"))
	local out = { time = time(), here = here, fight = InCombatLockdown() and true or false, map = map, zoom = zoom, api = {} }
	for _, name in ipairs({ "GetMapArtLayers", "GetMapArtLayerTextures", "GetMapInfoAtPosition", "GetMapChildrenInfo", "GetPlayerMapPosition", "GetMapRectOnMap" }) do
		out.api[name] = C_Map[name] ~= nil
	end
	out.questsOnMap = C_QuestLog and C_QuestLog.GetQuestsOnMap ~= nil or false
	out.position = here and Clean(Safe(C_Map.GetPlayerMapPosition, here, "player")) ~= nil or false
	out.facing = Clean(Safe(GetPlayerFacing)) ~= nil
	local layers = here and Safe(C_Map.GetMapArtLayers, here)
	local layer = type(layers) == "table" and layers[1]
	if layer then out.layer = { wide = Clean(layer.layerWidth), tall = Clean(layer.layerHeight), tile = Clean(layer.tileWidth) } end
	local files = here and Safe(C_Map.GetMapArtLayerTextures, here, 1)
	out.files = type(files) == "table" and #files or 0
	ns.AtlasDumpContent(out)
	ns.DB().atlasDump = out
	return out
end

ns.ATLAS_ADDON = ADDON
