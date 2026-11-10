local _, ns = ...
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

-- The controller's cursor on the map (below): its place on the canvas, and whether it is what the controller is using.
local padOn, padX, padY = false, 0, 0

-- The projection -----------------------------------------------------------------------------------------------

local function Scale() return math.max(fit * zoom, 0.01) end

-- A place of the map (0 to 1) -> the canvas (pixels from its top left).
function ns.AtlasProject(x, y) return offsetX + x * mapWide * Scale(), offsetY + y * mapTall * Scale() end

-- The cursor on the canvas, and on the map (nil, nil: off it).
function ns.AtlasCursor()
	local cx, cy
	if padOn then
		cx, cy = padX, padY
	else
		local x, y = GetCursorPosition()
		local scale = ui.clip:GetEffectiveScale()
		cx, cy = x / scale - (ui.clip:GetLeft() or 0), (ui.clip:GetTop() or 0) - y / scale
	end
	local mx, my = (cx - offsetX) / (mapWide * Scale()), (cy - offsetY) / (mapTall * Scale())
	if mx < 0 or mx > 1 or my < 0 or my > 1 then return cx, cy, nil, nil end
	return cx, cy, mx, my
end

-- Whether that cursor is the controller's now.
function ns.AtlasPadCursor() return padOn end

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
	local before = map
	map = id
	while not DrawTiles() do
		-- (a place with no picture of its own, a dungeon's inside: the map around it)
		local info = MapInfo(map)
		local parent = info and Clean(info.parentMapID)
		if not (parent and parent ~= 0 and MapInfo(parent)) then
			-- (nothing to show all the way up: the map shown stays)
			map = before
			if map then DrawTiles() end
			return false
		end
		map = parent
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

-- The controller on the map, as on the game's: the left stick moves a cursor drawn with two lines, the map follows at
-- its edges, the right stick zooms toward it, the bottom button acts where it stands. The left stick is taken as the
-- game's own cursor takes it, on a frame of ours (the character does not walk meanwhile); nothing of the game's cursor
-- is touched (its state belongs to the game, written from here it would block it). In the walking mode, nothing: the
-- map is there to walk with.
local PAD_SPEED, PAD_DEAD, PAD_EDGE, PAD_PAN, PAD_REACH = 620, 0.18, 36, 520, 16
local padPin, padLook
local stickX, stickY = 0, 0

local function PadFeel(pin)
	if pin == padPin then return end
	local leaving = padPin
	padPin = pin
	if leaving and leaving:GetScript("OnLeave") then leaving:GetScript("OnLeave")(leaving) end
	if pin and pin:GetScript("OnEnter") then pin:GetScript("OnEnter")(pin) end
end

local function PadLeave()
	if padOn then ui.overCanvas = false end
	padOn = false
	PadFeel(nil)
end

local function PadLook()
	if padLook then return padLook end
	padLook = CreateFrame("Frame", nil, ui.clip)
	padLook:Hide()
	padLook:SetAllPoints()
	padLook:SetScript("OnShow", function(self)
		if self.EnableGamePadStick then self:EnableGamePadStick(true) end
		-- (the controller's own icons when the game has them, else the words)
		local keys = Skin.PadKeys and Skin.PadKeys({ { "PADLSTICKAXIS", "MAP" }, { "PADRSTICKAXIS", "ZOOM" }, { "PAD1", "CHOOSE" },
			{ "PAD3", "NOTE" } })
		if self.hint then self.hint:SetText(keys or L.ATLAS_PAD_HINT) end
	end)
	padLook:SetScript("OnHide", function(self)
		if self.EnableGamePadStick then self:EnableGamePadStick(false) end
		stickX, stickY = 0, 0
	end)
	-- (true: left to the game, the right stick; false: taken)
	pcall(padLook.SetScript, padLook, "OnGamePadStick", function(_, stick, x, y)
		if stick ~= "Left" then return true end
		stickX, stickY = x, y
		return false
	end)
	padLook:SetFrameLevel(ui.overlay:GetFrameLevel() + 20)
	local function Line()
		local line = padLook:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(1, 0.82, 0, 0.55)
		return line
	end
	padLook.across, padLook.down = Line(), Line()
	padLook.across:SetHeight(1)
	padLook.down:SetWidth(1)
	padLook.dot = padLook:CreateTexture(nil, "OVERLAY", nil, 1)
	padLook.dot:SetSize(7, 7)
	padLook.dot:SetColorTexture(1, 0.82, 0, 1)
	padLook.hint = Skin.Text(padLook, "GameFontHighlight", "text")
	padLook.hint:SetPoint("BOTTOMLEFT", 8, 8)
	padLook.hint:SetText(L.ATLAS_PAD_HINT)
	padLook.hint:SetShadowOffset(1, -1)
	padLook.hint:SetShadowColor(0, 0, 0, 1)
	return padLook
end

local function PadPinUnder()
	local left, top = ui.clip:GetLeft(), ui.clip:GetTop()
	if not (left and top) then return nil end
	local best, bestDistance = nil, PAD_REACH ^ 2
	for _, pin in ipairs(ui.pins) do
		if pin:IsShown() and pin.data then
			local x, y = pin:GetCenter()
			if x then
				local distance = (x - left - padX) ^ 2 + (top - y - padY) ^ 2
				if distance < bestDistance then best, bestDistance = pin, distance end
			end
		end
	end
	return best
end

local function PadMove(elapsed)
	local holds = Skin.PadHolds and Skin.PadHolds(window) and not Db().walk
	if not holds then
		if padLook then padLook:Hide() end
		return PadLeave()
	end
	local look = PadLook()
	look:Show()
	local wide, tall = ui.clip:GetWidth(), ui.clip:GetHeight()
	if padX <= 0 and padY <= 0 then padX, padY = wide / 2, tall / 2 end
	local x, y = stickX, stickY
	if math.abs(x) > PAD_DEAD or math.abs(y) > PAD_DEAD then
		if not padOn and Skin.PadRefreshHint then
			padOn = true
			Skin.PadRefreshHint()
		end
		padOn, ui.overCanvas = true, true
		padX = math.max(0, math.min(wide, padX + x * PAD_SPEED * elapsed))
		padY = math.max(0, math.min(tall, padY - y * PAD_SPEED * elapsed))
		local panX = (padX < PAD_EDGE and x < 0 or padX > wide - PAD_EDGE and x > 0) and -x or 0
		local panY = (padY < PAD_EDGE and y > 0 or padY > tall - PAD_EDGE and y < 0) and y or 0
		if panX ~= 0 or panY ~= 0 then
			offsetX, offsetY = offsetX + panX * PAD_PAN * elapsed, offsetY + panY * PAD_PAN * elapsed
			Apply()
		end
	end
	look.across:ClearAllPoints()
	look.across:SetPoint("LEFT", ui.clip, "TOPLEFT", 0, -padY)
	look.across:SetPoint("RIGHT", ui.clip, "TOPRIGHT", 0, -padY)
	look.down:ClearAllPoints()
	look.down:SetPoint("TOP", ui.clip, "TOPLEFT", padX, 0)
	look.down:SetPoint("BOTTOM", ui.clip, "BOTTOMLEFT", padX, 0)
	look.dot:ClearAllPoints()
	look.dot:SetPoint("CENTER", ui.clip, "TOPLEFT", padX, -padY)
	PadFeel(padOn and PadPinUnder() or nil)
end

-- The bottom button where the cursor stands, the top one as a right click, the right stick's zoom: only while the
-- stick is what is being used (the cross goes back to the list).
local function PadClick()
	if not padOn then return false end
	if padPin then
		padPin:Click("LeftButton")
		return true
	end
	PressDown(nil, "LeftButton")
	PressUp(nil, "LeftButton")
	return true
end

local function PadRight()
	if not padOn then return false end
	if padPin then
		padPin:Click("RightButton")
		return true
	end
	PressDown(nil, "RightButton")
	PressUp(nil, "RightButton")
	return true
end

local function PadNote()
	if not padOn then return false end
	local _, _, x, y = ns.AtlasCursor()
	if x then ns.NoteCard(map, x, y) end
	return true
end

local function PadWheel(delta)
	if not padOn then return false end
	Notch(delta > 0 and 1 or -1, padX, padY)
	return true
end

local function Tick(_, elapsed)
	Animate(elapsed)
	PressMove()
	PadMove(elapsed)
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
	-- (a controller: the map has its cursor, the cross stays for the list and the buttons)
	clip.padIgnored = true
	if Skin.PadHolds then
		-- (the left button: a note where the cursor stands, as Alt + click)
		Skin.PadWindow(window, { click = PadClick, right = PadRight, wheel = PadWheel, alt = PadNote,
			hasAlt = function() return padOn end, onNavigate = PadLeave })
	end
	window:SetScript("OnUpdate", Tick)
	ns.AtlasBuildContent(window, margin, TOP, RIGHT_COLUMN, STRIP)
	-- (its size is yours: a corner to pull)
	window:SetResizable(true)
	if window.SetResizeBounds then window:SetResizeBounds(WIDTH_LEAST, HEIGHT_LEAST, WIDTH_MOST + 500, HEIGHT_MOST + 300) end
	local grip = Skin.GlyphButton(window, "move", 12, L.ATLAS_RESIZE, function() end)
	grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
	grip.padIgnored = true -- (dragged: a mouse's)
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
		PadLeave()
		Db().map = map
	end)
end

-- Opens it on a map (none: where you are), at a place of it if given.
function ns.AtlasShow(id, x, y)
	if not window then Create() end
	local wasShown = window:IsShown()
	window:Show()
	local goal = id or (not wasShown and WhereYouAre()) or map or WhereYouAre()
	local drawn = goal and (goal ~= map or not wasShown) and ns.AtlasSetMap(goal)
	-- (no map at all yet, where you are has none: never a canvas without one)
	if not map then drawn = ns.AtlasSetMap(EASTERN_KINGDOMS) end
	Relayout()
	if x and y then ns.AtlasFocus(x, y, ZOOMS[3]) end
	-- (a new map has just read its pins: only its zones follow the size just given)
	if drawn and not (x and y) then ns.AtlasDrawZones() else ns.AtlasRefresh() end
end

-- The land drawn again (explored while the atlas is open), the zoom and the pan left as they are.
function ns.AtlasDrawLand()
	if window and map then DrawTiles() end
end

-- A key pressed: the map, or the journal of your quests beside it. The same key again closes it; the other one
-- only changes what the panel shows, as the game's two keys do on its one window.
function ns.AtlasToggle(view)
	view = view or "map"
	if window and window:IsShown() then
		if ns.AtlasPanelView() == view then return window:Hide() end
		return ns.AtlasSetPanel(view)
	end
	ns.AtlasShow()
	ns.AtlasSetPanel(view)
end

-- To the game's own map (it stays one click away; never in a fight, the game refuses it there).
function ns.AtlasToGameMap()
	if InCombatLockdown() then return W.Print(L.ATLAS_NOT_IN_FIGHT) end
	if window then window:Hide() end
	-- (a controller: the game's map is never asked for from here, it blocks the game's own actions. Already open behind
	-- this window, it is simply seen again; closed, the button is the game's own key, padBinding.)
	if U.UsingPad() then return end
	if ToggleWorldMap then pcall(ToggleWorldMap) end
end

-- The game's map key opens the atlas: for this session only, your key bindings stay as they are, and the key goes
-- back by itself when this is off.
local keyOwner, takenKeys
local TAKEN_KEYS = { TOGGLEWORLDMAP = "WANDERERMAPS_ATLAS", TOGGLEQUESTLOG = "WANDERERMAPS_JOURNAL" }
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
	local keys, words = {}, {}
	if settings and settings.enabled and settings.atlas and GetBindingKey and not SameJob() then
		for game, ours in pairs(TAKEN_KEYS) do
			for _, key in ipairs({ GetBindingKey(game) }) do
				keys[key] = ours
				words[#words + 1] = key .. "=" .. ours
			end
		end
	end
	table.sort(words)
	local now = table.concat(words, ",")
	if now == (takenKeys or "") then return end
	takenKeys = now
	keyOwner = keyOwner or CreateFrame("Frame")
	Safe(ClearOverrideBindings, keyOwner)
	for key, ours in pairs(keys) do Safe(SetOverrideBinding, keyOwner, false, key, ours) end
end

BINDING_NAME_WANDERERMAPS_ATLAS = L.ATLAS
BINDING_NAME_WANDERERMAPS_JOURNAL = L.ATLAS_TAB_JOURNAL
local function PressKey(view)
	local settings = ns.Settings()
	if settings and settings.enabled then ns.AtlasToggle(view) end
end
function WandererMaps_Atlas() PressKey("map") end
function WandererMaps_Journal() PressKey("journal") end

-- The way to the atlas from the game's map: the controller's wheel opens that map, and the map key can't be heard
-- there. With a mouse the game's map gives way; with a controller it stays behind: closed from here, the game's
-- controller state would be written by an addon, and the game would then block its own actions.
local function FromGameMap()
	local id = WorldMapFrame.GetMapID and Clean(Safe(WorldMapFrame.GetMapID, WorldMapFrame))
	if not U.UsingPad() and not InCombatLockdown() and ToggleWorldMap then pcall(ToggleWorldMap) end
	ns.AtlasShow(id)
	ns.AtlasSetPanel("map")
end

local gameMapButton
local function RefreshGameMapButton()
	if not gameMapButton then return end
	local settings = ns.Settings()
	gameMapButton:SetShown(settings and settings.enabled and settings.atlas and not SameJob() and true or false)
end

-- (made once at login, never while the game's map is open: the controller interface watches what is made in it)
local function CreateGameMapButton()
	if gameMapButton or not WorldMapFrame then return end
	local holder = type(WorldMapFrame.ScrollContainer) == "table" and WorldMapFrame.ScrollContainer or WorldMapFrame
	gameMapButton = Skin.SmallButton(WorldMapFrame, L.ATLAS, FromGameMap, L.ATLAS_BUTTON_DESC, 22)
	gameMapButton:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 8, 8)
	gameMapButton:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	gameMapButton:SetFrameLevel(math.min(9000, (holder:GetFrameLevel() or 1) + 1500))
	ns.atlasGameMapButton = gameMapButton
	RefreshGameMapButton()
end

function ns.InitAtlas()
	CreateGameMapButton()
	-- (a controller asking for the game's map by its own key, from the atlas: the atlas gives way)
	if WorldMapFrame and WorldMapFrame.HookScript then
		WorldMapFrame:HookScript("OnShow", function()
			if U.UsingPad() and window and window:IsShown() then window:Hide() end
		end)
	end
	-- (the controller's wheel: the atlas in front of the game's map, when it takes the map's key)
	local kit = _G.Wanderer and _G.Wanderer.Skin
	if kit and kit.PadStandIn then
		kit.PadStandIn({ micro = _G.QuestLogMicroButton, binding = "TOGGLEWORLDMAP",
			wanted = function()
				local settings = ns.Settings()
				return settings and settings.enabled and settings.atlas and not SameJob()
			end,
			game = function() return _G.WorldMapFrame end,
			open = function()
				ns.AtlasShow()
				ns.AtlasSetPanel("map")
			end,
			window = function() return window end })
	end
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD" }) do events:RegisterEvent(event) end
	events:SetScript("OnEvent", function() ns.AtlasPlaceKey() end)
	ns.OnChanged(function()
		RefreshGameMapButton()
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
