-- Settings. The same page is built twice: as the "Settings" tab of our window
-- and in the game menu (Esc > Options > AddOns).

local _, ns = ...
local L = ns.L

local function Tooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- get/set for a plain on/off setting.
local function Setting(key)
	return function() return ns.settings[key] end,
		function(value) ns.settings[key] = value end
end

local function Checkbox(parent, anchor, label, description, get, set)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	check.Text:SetText(label)
	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		self:SetChecked(get() and true or false) -- the game may refuse a change
	end)
	check:SetScript("OnShow", function(self)
		self:SetChecked(get() and true or false)
	end)
	check:SetChecked(get() and true or false)
	Tooltip(check, label, description)
	return check
end

local function Dropdown(parent, anchor, label, build)
	local text = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
	text:SetText(label)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(220)
	dropdown:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
	dropdown:SetupMenu(build)
	return dropdown
end

function ns.BuildOptions(parent)
	local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -16)
	title:SetText(ns.TITLE .. (ns.VERSION and ns.VERSION:sub(1, 1) ~= "@" and ("  " .. ns.VERSION) or ""))

	-- Left column: switches.
	local last = Checkbox(parent, title, L.OPT_AUTO_POPUP, L.OPT_AUTO_POPUP_DESC, Setting("autoPopup"))
	last = Checkbox(parent, last, L.OPT_CHAT, L.OPT_CHAT_DESC, Setting("chatReminder"))
	last = Checkbox(parent, last, L.OPT_MINIMAP, L.OPT_MINIMAP_DESC,
		function() return not (ns.db and ns.db.minimap.hide) end,
		function(value) ns.SetMinimapShown(value) end)
	if ns.CompartmentAvailable() then
		last = Checkbox(parent, last, L.OPT_COMPARTMENT, L.OPT_COMPARTMENT_DESC, ns.IsInCompartment, ns.SetInCompartment)
	end
	last = Checkbox(parent, last, L.OPT_MUTE, L.OPT_MUTE_DESC, Setting("mute"))
	last = Checkbox(parent, last, L.OPT_MASTER, L.OPT_MASTER_DESC, Setting("masterChannel"))
	last = Checkbox(parent, last, L.OPT_ALT_WIPE, L.OPT_ALT_WIPE_DESC, Setting("altClickWipe"))
	last = Checkbox(parent, last, L.OPT_TAINTLOG, L.OPT_TAINTLOG_DESC, ns.IsTaintLogOn, ns.SetTaintLog)

	-- Right column: choices.
	local column = CreateFrame("Frame", nil, parent)
	column:SetSize(1, 1)
	column:SetPoint("TOPLEFT", parent, "TOP", -10, -30)

	local font = Dropdown(parent, column, L.OPT_FONT, function(_, root)
		for i, fontName in ipairs(ns.FONTS) do
			root:CreateRadio(L["FONT_" .. i], function() return ns.settings.fontSize == fontName end, function()
				ns.settings.fontSize = fontName
				ns.ApplyFont()
			end)
		end
	end)

	local sound = Dropdown(parent, font, L.OPT_SOUND, function(_, root)
		for _, key in ipairs(ns.SOUNDS) do
			root:CreateRadio(L["SOUND_" .. key], function() return ns.settings.sound == key end, function()
				ns.settings.sound = key
				ns.PreviewSound(key)
			end)
		end
	end)

	local listen = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	listen:SetSize(90, 22)
	listen:SetPoint("LEFT", sound, "RIGHT", 8, 0)
	listen:SetText(L.OPT_PREVIEW)
	listen:SetScript("OnClick", function() ns.PreviewSound() end)

	local language = Dropdown(parent, sound, L.OPT_LANGUAGE, function(_, root)
		for _, key in ipairs({ "auto", "enUS", "ruRU" }) do
			root:CreateRadio(L["LANG_" .. key], function() return ns.settings.language == key end, function()
				if ns.settings.language ~= key then
					ns.settings.language = key
					ns.Print(L.LANG_RELOAD)
				end
			end)
		end
	end)

	local wipeButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	wipeButton:SetSize(220, 24)
	wipeButton:SetPoint("TOPLEFT", language, "BOTTOMLEFT", 0, -24)
	wipeButton:SetText(L.WIPE_BUTTON)
	wipeButton:SetScript("OnClick", function() ns.Wipe() end)
	Tooltip(wipeButton, L.WIPE_BUTTON, L.WIPE_DESC)
end

-- Page in the game menu, created once the settings are loaded.
ns.OnLogin(function()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local page = CreateFrame("Frame")
	ns.BuildOptions(page)
	local category = Settings.RegisterCanvasLayoutCategory(page, ns.TITLE)
	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end)
