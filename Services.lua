local _, ns = ...
local L = ns.L

-- The services of the towns: inns, flight masters, mailboxes, banks, auction houses and your class's trainers.
-- Learned as you meet them (a mailbox opened, a banker, an auctioneer, a trainer, an innkeeper spoken to:
-- where you stand then), kept for the account as the world's knowledge, with the side that met them; the flight
-- masters from the game's own table (Flights.lua). Shown as small pins on the maps of the zones and towns (an
-- option, off), in the game's own marks; the nearest of each in the window, one click to follow.

local W = Wanderer
local U = W and W.Util
local Safe, Clean = U and U.Safe, U and U.Clean

local TEMPLATE = "WandererMapsServiceTemplate"
local SAME = 20 -- yards: a service met again this near is the same one
local KEPT = 300 -- services kept of each kind at most (the oldest go)
local BINDER_ICON = 132052 -- (the innkeeper's line of a conversation, "make this inn your home")
local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
local MICRO = (Enum and Enum.UIMapType and Enum.UIMapType.Micro) or 5

-- Each kind: its words, its mark (the game's own: the minimap's tracking marks).
ns.SERVICE_KINDS = {
	inn = { word = "SERVICE_INN", atlas = "Innkeeper", file = "Interface\\Minimap\\Tracking\\Innkeeper" },
	flight = { word = "SERVICE_FLIGHT", atlas = "FlightMaster", file = "Interface\\Minimap\\Tracking\\FlightMaster" },
	mail = { word = "SERVICE_MAIL", atlas = "Mailbox", file = "Interface\\Minimap\\Tracking\\Mailbox" },
	bank = { word = "SERVICE_BANK", atlas = "Banker", file = "Interface\\Minimap\\Tracking\\Banker" },
	auction = { word = "SERVICE_AUCTION", atlas = "Auctioneer", file = "Interface\\Minimap\\Tracking\\Auctioneer" },
	trainer = { word = "SERVICE_TRAINER", atlas = "Class", file = "Interface\\Minimap\\Tracking\\Class" },
}
ns.SERVICE_ORDER = { "inn", "flight", "mail", "bank", "auction", "trainer" }
-- (the window's "nearest" line: the four errands of every town)
ns.NEAREST_ORDER = { "inn", "flight", "mail", "trainer" }

-- The services met, for the account: { kind, map, x, y, side, class (a trainer's), name, seen }.
local function Met()
	local data = ns.Data()
	data.services = type(data.services) == "table" and data.services or {}
	return data.services
end

local function MyClass() return Clean(select(2, Safe(UnitClass, "player"))) end

-- A service met where you stand (an NPC's name with it), kept or brought up to date.
function ns.LearnService(kind, name, class)
	if not ns.SERVICE_KINDS[kind] then return nil end
	local map, x, y = U.HereOnMap()
	if not map then return nil end
	local wx, wy, instance = ns.WorldOf(map, x, y)
	if not wx then return nil end
	local side = Clean(Safe(UnitFactionGroup, "player"))
	local list = Met()
	local count, oldest = 0, nil
	for index, place in ipairs(list) do
		if place.kind == kind then
			count = count + 1
			if not oldest or (place.seen or 0) < (list[oldest].seen or 0) then oldest = index end
			local px, py, there = ns.WorldOf(place.map, place.x, place.y)
			if px and there == instance and place.class == class and math.sqrt((px - wx) ^ 2 + (py - wy) ^ 2) <= SAME then
				place.map, place.x, place.y, place.side, place.seen = map, x, y, side, time()
				place.name = name or place.name
				ns.Changed()
				return place
			end
		end
	end
	if count >= KEPT and oldest then table.remove(list, oldest) end
	local place = { kind = kind, map = map, x = x, y = y, side = side, class = class, name = name, seen = time() }
	list[#list + 1] = place
	ns.Changed()
	return place
end

-- The services of a kind for you (your side's; a trainer of your class): { kind, map, x, y, title, wx, wy,
-- instance }.
function ns.Services(kind)
	local list = {}
	if kind == "flight" then
		for _, master in ipairs(ns.FlightMasters and ns.FlightMasters() or {}) do
			master.kind = "flight"
			list[#list + 1] = master
		end
		return list
	end
	local side, class = Clean(Safe(UnitFactionGroup, "player")), MyClass()
	local word = L[ns.SERVICE_KINDS[kind].word]
	for _, place in ipairs(Met()) do
		if place.kind == kind and (not place.side or place.side == side) and (kind ~= "trainer" or place.class == class) then
			local wx, wy, instance = ns.WorldOf(place.map, place.x, place.y)
			if wx then
				list[#list + 1] = { kind = kind, map = place.map, x = place.x, y = place.y, title = place.name or word,
					wx = wx, wy = wy, instance = instance }
			end
		end
	end
	return list
end

-- The nearest of a kind on your continent: the place and its distance in yards (nil: none known).
function ns.NearestService(kind)
	local px, py, here = ns.Here()
	if not px then return nil end
	local best, bestDistance
	for _, place in ipairs(ns.Services(kind)) do
		if place.instance == here then
			local distance = math.sqrt((place.wx - px) ^ 2 + (place.wy - py) ^ 2)
			if not best or distance < bestDistance then best, bestDistance = place, distance end
		end
	end
	return best, bestDistance
end

-- A mark of a kind on a texture (the game's atlas, else its file).
function ns.ServiceIcon(texture, kind)
	local spec = ns.SERVICE_KINDS[kind]
	if not spec then return end
	if U.HasAtlas(spec.atlas) then texture:SetAtlas(spec.atlas) else texture:SetTexture(spec.file) end
end

-- Learning, from the game's own moments -----------------------------------------------------------------

local function NpcName() return Clean(Safe(UnitName, "npc")) end

-- An innkeeper: the conversation offers to make the inn your home.
local function IsInnkeeper()
	local options = C_GossipInfo and C_GossipInfo.GetOptions and Safe(C_GossipInfo.GetOptions)
	for _, option in ipairs(type(options) == "table" and options or {}) do
		if Clean(option.icon) == BINDER_ICON or Clean(option.type) == "binder" then return true end
	end
	return false
end

-- A trainer of your class (not a craft's): its own class is yours.
local function IsClassTrainer()
	if Clean(Safe(IsTradeskillTrainer)) then return false end
	local class = Clean(select(2, Safe(UnitClass, "npc")))
	return class ~= nil and class == MyClass()
end

local LEARN = {
	MAIL_SHOW = function() ns.LearnService("mail") end,
	BANKFRAME_OPENED = function() ns.LearnService("bank", NpcName()) end,
	AUCTION_HOUSE_SHOW = function() ns.LearnService("auction", NpcName()) end,
	TRAINER_SHOW = function() if IsClassTrainer() then ns.LearnService("trainer", NpcName(), MyClass()) end end,
	GOSSIP_SHOW = function() if IsInnkeeper() then ns.LearnService("inn", NpcName()) end end,
	HEARTHSTONE_BOUND = function() ns.LearnService("inn") end,
}

-- The pins on the world map ---------------------------------------------------------------------------

WandererMapsServicePinMixin = CreateFromMixins(MapCanvasPinMixin or {})

function WandererMapsServicePinMixin:OnLoad()
	if self.SetScalingLimits then self:SetScalingLimits(1, 0.8, 1.2) end
	if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
end

-- data: { place, x, y (on the map shown) }
function WandererMapsServicePinMixin:OnAcquired(data)
	self.data = data
	self:SetPosition(data.x, data.y)
	ns.ServiceIcon(self.icon, data.place.kind)
end

function WandererMapsServicePinMixin:OnMouseEnter()
	local place = self.data and self.data.place
	if not place then return end
	local word = L[ns.SERVICE_KINDS[place.kind].word]
	local lines = { word }
	if place.title and place.title ~= word then lines[2] = ns.TipLine(place.title) end
	lines[#lines + 1] = ns.TipLine(L.SERVICE_PIN_TIP, "blue")
	ns.ShowTip(self, lines)
end

function WandererMapsServicePinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function WandererMapsServicePinMixin:OnMouseUp(button, upInside)
	local place = self.data and self.data.place
	if not place or upInside == false or button ~= "LeftButton" then return end
	W.Skin.Play("click")
	ns.GoTo(place)
end

local provider

-- A zone's or a town's map: the services shown there (never on a continent).
local function ShowsServices(map)
	local info = map and Safe(C_Map.GetMapInfo, map)
	local kind = type(info) == "table" and Clean(info.mapType)
	return kind == ZONE or kind == MICRO
end

local function Provider()
	if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return provider end
	provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
	end
	function provider:RefreshAllData()
		self:RemoveAllData()
		local settings = ns.Settings()
		if not (settings and settings.enabled and settings.services) then return end
		if InCombatLockdown() then return U.AfterFight("services", ns.RefreshServices) end
		local map = Clean(self:GetMap():GetMapID())
		if not ShowsServices(map) then return end
		for _, kind in ipairs(ns.SERVICE_ORDER) do
			for _, place in ipairs(ns.Services(kind)) do
				local x, y = ns.OnMap(place, map)
				if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
					self:GetMap():AcquirePin(TEMPLATE, { place = place, x = x, y = y })
				end
			end
		end
	end
	WorldMapFrame:AddDataProvider(provider)
	return provider
end

function ns.RefreshServices()
	local made = Provider()
	if made and WorldMapFrame:IsShown() then made:RefreshAllData() end
end

function ns.InitServices()
	local events = CreateFrame("Frame")
	for event in pairs(LEARN) do pcall(events.RegisterEvent, events, event) end
	events:SetScript("OnEvent", function(_, event) LEARN[event]() end)
	if not WorldMapFrame then return end
	Provider()
	ns.OnChanged(ns.RefreshServices)
end
