-- A small stand-in for the World of Warcraft API: just enough to run
-- Forever Bugs outside the game. Everything the tests look at is in `mock`.
-- Each test game runs this file in its own global table.

mock = {
	now = 1000,            -- GetTime()
	clock = os.time(),     -- time()
	combat = false,
	secure = true,         -- does the current ShowUIPanel/HideUIPanel call count as game code?
	shift = false,
	alt = false,
	locale = "enUS",
	stack = "",            -- what debugstack() returns
	locals = "",           -- what debuglocals() returns
	printed = {},
	sounds = {},
	missingSounds = {},    -- sound kit IDs the game data does not have
	replaced = {},         -- global function name -> addon that replaced it
	cvars = { taintLog = "0" },
	cvarLocked = false,    -- true: the game refuses SetCVar
	disabled = {},
	reloads = 0,
	frames = {},
	addons = { "!!ForeverBugs", "Baganator", "OpenMap", "Library Books", "TwoLineChat", "Blizzard_ChatFrameBase" },
	meta = {
		["!!ForeverBugs"] = { Version = "1.0.0" },
		OpenMap = { Version = "2.0" },
	},
}

local function noop() end

-----------------------------------------------------------------------
-- Frames, font strings, textures: every method exists; the ones the tests
-- care about remember what happened.

local Object = {}
local ObjectMeta = {
	__index = function(_, key)
		local method = Object[key]
		if method ~= nil then
			return method
		end
		return noop
	end,
}

local TEMPLATE_CHILDREN = {
	PortraitFrameTemplate = { CloseButton = "Button" },
	UICheckButtonTemplate = { Text = "FontString" },
	SearchBoxTemplate = { Instructions = "FontString" },
}

local function NewObject(kind, name, parent, template)
	local object = setmetatable({
		kind = kind, name = name, parent = parent,
		scripts = {}, events = {}, lines = {},
		shown = true, enabled = true, checked = false,
	}, ObjectMeta)
	for templateName in (template or ""):gmatch("[^,%s]+") do
		for key, childKind in pairs(TEMPLATE_CHILDREN[templateName] or {}) do
			object[key] = NewObject(childKind, nil, object)
		end
	end
	if name then
		_G[name] = object
	end
	mock.frames[#mock.frames + 1] = object
	return object
end

function Object:Run(script, ...)
	local fn = self.scripts[script]
	if fn then
		return fn(self, ...)
	end
end
function Object:SetScript(script, fn) self.scripts[script] = fn end
function Object:GetScript(script) return self.scripts[script] end
function Object:HookScript(script, fn)
	local old = self.scripts[script]
	self.scripts[script] = function(...)
		if old then old(...) end
		fn(...)
	end
end
function Object:Show()
	if not self.shown then
		self.shown = true
		self:Run("OnShow")
	end
end
function Object:Hide()
	if self.shown then
		self.shown = false
		self:Run("OnHide")
	end
end
function Object:SetShown(value) if value then self:Show() else self:Hide() end end
function Object:IsShown() return self.shown end
function Object:SetText(text)
	self.text = text
	if self.kind == "EditBox" then
		self:Run("OnTextChanged", false)
	end
end
function Object:GetText() return self.text end
function Object:Type(text) -- the player types into an edit box
	self.text = text
	self:Run("OnTextChanged", true)
end
function Object:Click(...) return self:Run("OnClick", ...) end
function Object:SetChecked(value) self.checked = value and true or false end
function Object:GetChecked() return self.checked end
function Object:SetEnabled(value) self.enabled = value and true or false end
function Object:Enable() self.enabled = true end
function Object:Disable() self.enabled = false end
function Object:IsEnabled() return self.enabled end
function Object:GetName() return self.name end
function Object:GetParent() return self.parent end
function Object:CreateFontString() return NewObject("FontString", nil, self) end
function Object:CreateTexture() return NewObject("Texture", nil, self) end
function Object:RegisterEvent(event) self.events[event] = true end
function Object:UnregisterEvent(event) self.events[event] = nil end
function Object:SetFocus() self.focused = true end
function Object:ClearFocus() self.focused = false end
function Object:HighlightText() self.highlighted = true end
function Object:SetFontObject(font) self.font = font end
function Object:SetVerticalScroll(value) self.scrolled = value end
function Object:AddLine(text) self.lines[#self.lines + 1] = text end
function Object:SetupMenu(generator) self.menu = generator end
function Object:GenerateMenu() -- returns the menu items, like opening the dropdown
	local root = { items = {} }
	function root:CreateRadio(text, isSelected, setSelected)
		local item = { text = text, isSelected = isSelected, setSelected = setSelected }
		self.items[#self.items + 1] = item
		return item
	end
	if self.menu then
		self.menu(self, root)
	end
	return root.items
end

function CreateFrame(kind, name, parent, template)
	return NewObject(kind, name, parent, template)
end

function mock.Fire(event, ...)
	for _, frame in ipairs(mock.frames) do
		if frame.events[event] then
			frame:Run("OnEvent", event, ...)
		end
	end
end

-- Finds created objects, e.g. mock.Find("EditBox", function(o) ... end).
function mock.Find(kind, test)
	for _, object in ipairs(mock.frames) do
		if object.kind == kind and (not test or test(object)) then
			return object
		end
	end
end

-----------------------------------------------------------------------
-- Game functions

function GetTime() return mock.now end
function time() return mock.clock end
date = os.date
function GetLocale() return mock.locale end
function GetBuildInfo() return "1.60.1", "70888", "Nov 10 2026", 16001 end
function InCombatLockdown() return mock.combat end
function IsShiftKeyDown() return mock.shift end
function IsAltKeyDown() return mock.alt end
function PlaySound(id, channel)
	mock.sounds[#mock.sounds + 1] = { id = id, channel = channel }
	return not mock.missingSounds[id] -- willPlay
end
function ReloadUI() mock.reloads = mock.reloads + 1 end
function debugstack() return mock.stack end
function debuglocals() return mock.locals end
function issecretvalue(value) return type(value) == "table" and value.secret == true end
function seterrorhandler(handler) mock.handler = handler end
function geterrorhandler() return mock.handler end
function wipe(t) for key in pairs(t) do t[key] = nil end return t end
tinsert = table.insert

function hooksecurefunc(a, b, c)
	local owner, key, hook = _G, a, b
	if type(a) == "table" then
		owner, key, hook = a, b, c
	end
	local original = owner[key]
	owner[key] = function(...)
		local results = { original(...) }
		hook(...)
		return unpack(results)
	end
end

C_AddOns = {
	GetNumAddOns = function() return #mock.addons end,
	GetAddOnInfo = function(i) return mock.addons[i] end,
	DisableAddOn = function(name) mock.disabled[#mock.disabled + 1] = name end,
	GetAddOnMetadata = function(name, field) return mock.meta[name] and mock.meta[name][field] end,
}

SOUNDKIT = { RAID_WARNING = 8959, IG_QUEST_LOG_OPEN = 844, IG_QUEST_LOG_CLOSE = 845, IG_CHARACTER_INFO_TAB = 841 }
INTERFACE_ACTION_BLOCKED = "Interface action failed because of an AddOn"
UISpecialFrames = {}
GameFontHighlightSmall, GameFontHighlight, GameFontHighlightMedium, GameFontHighlightLarge = {}, {}, {}, {}

DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) mock.printed[#mock.printed + 1] = text end }
ChatFrameUtil = { AddSystemMessage = function(text) DEFAULT_CHAT_FRAME:AddMessage(text) end }

-- Forever's ChatFrameUtilOverrides: counts refusals, prints only the first.
local refusals = 0
function DisplayInterfaceActionBlockedMessage()
	refusals = refusals + 1
	if refusals == 1 then
		ChatFrameUtil.AddSystemMessage(INTERFACE_ACTION_BLOCKED)
	end
end

-- Forever's UIParentPanelManager: in combat, calls from addon code are refused.
function ShowUIPanel(frame)
	if not frame or frame:IsShown() then return end
	if InCombatLockdown() and not mock.secure then return DisplayInterfaceActionBlockedMessage() end
	frame:Show()
end
function HideUIPanel(frame)
	if not frame or not frame:IsShown() then return end
	if InCombatLockdown() and not mock.secure then return DisplayInterfaceActionBlockedMessage() end
	frame:Hide()
end

function issecurevariable(name)
	if mock.replaced[name] then
		return false, mock.replaced[name]
	end
	return true
end

C_CVar = {
	GetCVar = function(name) return mock.cvars[name] end,
	SetCVar = function(name, value)
		if mock.cvarLocked then error("not allowed") end
		mock.cvars[name] = value
	end,
}

EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
	self.callbacks[event] = self.callbacks[event] or {}
	table.insert(self.callbacks[event], { fn = fn, owner = owner })
end
function EventRegistry:TriggerEvent(event, ...)
	for _, callback in ipairs(self.callbacks[event] or {}) do
		callback.fn(callback.owner, ...)
	end
end

function PanelTemplates_SetNumTabs(frame, count) frame.numTabs = count end
function PanelTemplates_SetTab(frame, id) frame.selectedTab = id end

Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		mock.settingsCategory = { frame = frame, name = name }
		return mock.settingsCategory
	end,
	RegisterAddOnCategory = function(category) mock.registeredCategory = category end,
}

SlashCmdList = {}
UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip")
ScriptErrorsFrame = CreateFrame("Frame", "ScriptErrorsFrame")
ScriptErrorsFrame:RegisterEvent("LUA_WARNING")

-----------------------------------------------------------------------
-- Libraries

local DBIcon = { buttons = {} }
function DBIcon:Register(name, object, db) self.buttons[name] = { object = object, db = db } end
function DBIcon:Show(name) self.buttons[name].db.hide = nil end
function DBIcon:Hide(name) self.buttons[name].db.hide = true end
function DBIcon:IsButtonCompartmentAvailable() return true end
function DBIcon:IsButtonInCompartment(name)
	local button = self.buttons[name]
	return button and button.db.showInCompartment or false
end
function DBIcon:AddButtonToCompartment(name) self.buttons[name].db.showInCompartment = true end
function DBIcon:RemoveButtonFromCompartment(name) self.buttons[name].db.showInCompartment = nil end
mock.DBIcon = DBIcon

local LDB = { objects = {} }
function LDB:NewDataObject(name, object)
	self.objects[name] = object
	mock.broker = object
	return object
end

LibStub = setmetatable({}, {
	__call = function(_, name)
		if name == "LibDataBroker-1.1" then return LDB end
		if name == "LibDBIcon-1.0" then return DBIcon end
	end,
})
