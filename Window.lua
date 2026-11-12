-- The window: the list on the left (newest on top), the chosen error on the
-- right, tabs for all errors / this session / previous session / settings,
-- search, addon filter and copy-ready reports.
--
-- The list has two modes: one row per error (repeats as "x8"), or "each time
-- separately", where every occurrence from the history is its own row.

local _, ns = ...
local L = ns.L

local TAB_ALL, TAB_SESSION, TAB_PREVIOUS, TAB_OPTIONS = 1, 2, 3, 4
local WIDTH, HEIGHT = 980, 520
local LIST_WIDTH = 330
local ROW_HEIGHT = 36

local window, searchBox, eachTimeBox, addonDropdown, optionsPanel
local listScroll, listChild, listBackground, detailScroll, textBox
local shownText, copyOneButton, copyAllButton, deleteButton
local rows = {}

local tab = TAB_ALL
local addonFilter        -- addon folder, "?" for unknown, nil for all
local searchText = ""
local list = {}          -- rows on screen, newest first: { key = ..., err = ..., time = ... }
local selectedKey        -- the chosen row: the error, or a history entry in "each time" mode
local selected           -- the error shown on the right
local copyMode           -- nil, "one" or "all"
local displayed = ""     -- the text box is read-only: typing restores this
local newSince = 0       -- errors with a higher id were new when the window opened

local Render

local function PlayUISound(key, fallback)
	PlaySound((SOUNDKIT and SOUNDKIT[key]) or fallback)
end

local function SessionForTab()
	if tab == TAB_SESSION then
		return ns.GetSession()
	elseif tab == TAB_PREVIOUS then
		return ns.GetSession() - 1
	end
end

local function Choose(item)
	selectedKey = item and item.key
	selected = item and item.err
end

-- The rows for the current mode, tab, filter and search. The chosen row stays
-- chosen if it is still there; else the newest row of the same error; else
-- the newest row.
local function Rebuild()
	if ns.settings.eachTime then
		list = ns.GetOccurrences(SessionForTab(), addonFilter, searchText)
	else
		list = {}
		local found = ns.GetErrors(SessionForTab(), addonFilter, searchText)
		for i = #found, 1, -1 do
			local err = found[i]
			list[#list + 1] = { key = err, err = err, time = err.time }
		end
	end
	local sameError
	for _, item in ipairs(list) do
		if item.key == selectedKey then
			Choose(item)
			return
		end
		if not sameError and item.err == selected then
			sameError = item
		end
	end
	Choose(sameError or list[1])
end

local function Tooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function Button(text, width)
	local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button:SetText(text)
	return button
end

local function Row(i)
	if rows[i] then
		return rows[i]
	end
	local row = CreateFrame("Button", nil, listChild)
	row.isErrorRow = true
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
	row.selectedTexture:SetAllPoints()
	row.selectedTexture:SetColorTexture(1, 0.82, 0, 0.18)

	row.newMark = row:CreateTexture(nil, "ARTWORK")
	row.newMark:SetSize(6, 6)
	row.newMark:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -8)
	row.newMark:SetColorTexture(1, 0.3, 0.3, 1)

	row.timeText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.timeText:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -4)
	row.timeText:SetTextColor(0.65, 0.65, 0.65)

	row.countText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.countText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)

	row.addonText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.addonText:SetPoint("LEFT", row.timeText, "RIGHT", 6, 0)
	row.addonText:SetPoint("RIGHT", row.countText, "LEFT", -6, 0)
	row.addonText:SetJustifyH("LEFT")
	row.addonText:SetWordWrap(false)

	row.messageText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.messageText:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -19)
	row.messageText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -19)
	row.messageText:SetJustifyH("LEFT")
	row.messageText:SetWordWrap(false)

	row:SetScript("OnClick", function(self)
		Choose(self.item)
		copyMode = nil
		Render(true)
	end)
	rows[i] = row
	return row
end

local function FirstLine(text)
	return (text:match("^[^\n]*"))
end

local function RenderList()
	local eachTime = ns.settings.eachTime
	listChild:SetHeight(math.max(1, #list * ROW_HEIGHT))
	for i, item in ipairs(list) do
		local err = item.err
		local row = Row(i)
		row.item, row.err = item, err
		row.timeText:SetText(ns.FormatTime(item.time))
		row.addonText:SetText(ns.Escape(err.addon or L.UNKNOWN_ADDON))
		row.countText:SetText((not eachTime and (err.counter or 1) > 1) and ("x" .. err.counter) or "")
		row.messageText:SetText(L["KIND_SHORT_" .. (err.kind or "error")] .. ": "
			.. ns.Escape(FirstLine(ns.DisplayMessage(err))))
		row.newMark:SetShown(err.id ~= nil and err.id > newSince)
		row.selectedTexture:SetShown(item.key == selectedKey)
		row:Show()
	end
	for i = #list + 1, #rows do
		rows[i].item, rows[i].err = nil, nil
		rows[i]:Hide()
	end
end

-- Each error once, in the order of the list.
local function ListedErrors()
	local errors, seen = {}, {}
	for _, item in ipairs(list) do
		if not seen[item.err] then
			seen[item.err] = true
			errors[#errors + 1] = item.err
		end
	end
	return errors
end

-- toTop: scroll the error text back to its beginning (another error is shown).
function Render(toTop)
	if not window then return end
	local isOptions = tab == TAB_OPTIONS
	PanelTemplates_SetTab(window, tab)
	optionsPanel:SetShown(isOptions)
	for _, widget in ipairs({ searchBox, eachTimeBox, addonDropdown, listScroll, listBackground, detailScroll,
		shownText, copyOneButton, copyAllButton, deleteButton }) do
		widget:SetShown(not isOptions)
	end
	if isOptions then return end
	ns.MarkAllSeen() -- the error view is on screen

	RenderList()
	shownText:SetText(L.SHOWN:format(#list))
	eachTimeBox:SetChecked(ns.settings.eachTime)

	if not selected then
		copyMode = nil
	end
	if copyMode == "all" then
		displayed = ns.Escape(ns.FormatReportMany(ListedErrors()))
	elseif copyMode == "one" then
		displayed = ns.Escape(ns.FormatReport(selected))
	elseif selected then
		displayed = ns.FormatForWindow(selected)
	else
		displayed = L.NO_ERRORS
	end
	textBox:SetText(displayed)

	copyOneButton:SetEnabled(selected ~= nil)
	copyAllButton:SetEnabled(#list > 0)
	deleteButton:SetEnabled(selected ~= nil)
	copyOneButton:SetText(copyMode == "one" and L.COPY_BACK or L.COPY_ONE)
	copyAllButton:SetText(copyMode == "all" and L.COPY_BACK or L.COPY_ALL)
	if addonDropdown.GenerateMenu then
		addonDropdown:GenerateMenu()
	end
	if toTop then
		detailScroll:SetVerticalScroll(0)
	end
	if copyMode then
		textBox:SetFocus()
		textBox:HighlightText()
	else
		textBox:ClearFocus()
	end
end

local function Refresh()
	copyMode = nil
	Rebuild()
	Render(true)
end

local function SelectTab(id)
	tab = id
	copyMode = nil
	if id ~= TAB_OPTIONS then
		Rebuild()
	end
	Render(true)
end

local function SetFilter(addon)
	addonFilter = addon
	Refresh()
end

local function BuildAddonMenu(_, root)
	root:CreateRadio(L.ALL_ADDONS, function() return addonFilter == nil end, function() SetFilter(nil) end)
	local counts = ns.CountByAddon(SessionForTab())
	local names = {}
	for name in pairs(counts) do
		names[#names + 1] = name
	end
	table.sort(names, function(a, b)
		if a == "?" then return false end
		if b == "?" then return true end
		return a:lower() < b:lower()
	end)
	for _, name in ipairs(names) do
		local label = (name == "?" and L.UNKNOWN_ADDON or name) .. " (" .. counts[name] .. ")"
		root:CreateRadio(label, function() return addonFilter == name end, function() SetFilter(name) end)
	end
end

-- The row to choose after the chosen error is deleted: the next one below
-- (or above) that belongs to another error.
local function Neighbour(gone)
	local position = 1
	for i, item in ipairs(list) do
		if item.key == selectedKey then
			position = i
			break
		end
	end
	for i = position + 1, #list do
		if list[i].err ~= gone then return list[i] end
	end
	for i = position - 1, 1, -1 do
		if list[i].err ~= gone then return list[i] end
	end
end

local function Create()
	window = CreateFrame("Frame", "ForeverBugsFrame", UIParent, "PortraitFrameTemplate")
	window:Hide()
	window:SetSize(WIDTH, HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetTitle(ns.TITLE)
	window:SetPortraitToAsset(ns.ICON)
	-- The template's close button goes through HideUIPanel, which the game
	-- refuses in combat for addon frames. Hide the window directly instead.
	window.CloseButton:SetScript("OnClick", function() window:Hide() end)
	window:SetScript("OnShow", function() PlayUISound("IG_QUEST_LOG_OPEN", 844) end)
	window:SetScript("OnHide", function()
		PlayUISound("IG_QUEST_LOG_CLOSE", 845)
		copyMode = nil
	end)
	tinsert(UISpecialFrames, "ForeverBugsFrame") -- Esc closes it

	searchBox = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
	searchBox:SetSize(260, 20)
	searchBox:SetPoint("TOPLEFT", window, "TOPLEFT", 70, -32)
	searchBox:SetAutoFocus(false)
	searchBox:SetMaxLetters(60)
	if searchBox.Instructions then
		searchBox.Instructions:SetText(L.SEARCH)
	end
	searchBox:HookScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		if text == searchText then return end
		searchText = text
		Refresh()
	end)

	eachTimeBox = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
	eachTimeBox:SetSize(24, 24)
	eachTimeBox:SetPoint("LEFT", searchBox, "RIGHT", 14, 0)
	eachTimeBox.Text:SetText(L.EACH_TIME)
	eachTimeBox:SetChecked(ns.settings.eachTime)
	eachTimeBox:SetScript("OnClick", function(self)
		ns.settings.eachTime = self:GetChecked() and true or false
		Refresh()
	end)
	Tooltip(eachTimeBox, L.EACH_TIME, L.EACH_TIME_DESC:format(ns.MAX_HISTORY_PER_ERROR, ns.MAX_HISTORY))

	addonDropdown = CreateFrame("DropdownButton", nil, window, "WowStyle1DropdownTemplate")
	addonDropdown:SetWidth(240)
	addonDropdown:SetPoint("TOPRIGHT", window, "TOPRIGHT", -14, -30)
	if addonDropdown.SetDefaultText then
		addonDropdown:SetDefaultText(L.ALL_ADDONS)
	end
	addonDropdown:SetupMenu(BuildAddonMenu)

	-- Left: the list.
	listScroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -62)
	listScroll:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, 44)
	listScroll:SetWidth(LIST_WIDTH - 24)
	listChild = CreateFrame("Frame", nil, listScroll)
	listChild:SetSize(LIST_WIDTH - 24, 1)
	listScroll:SetScrollChild(listChild)

	listBackground = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	listBackground:SetPoint("TOPLEFT", listScroll, "TOPLEFT", -2, 2)
	listBackground:SetPoint("BOTTOMRIGHT", listScroll, "BOTTOMRIGHT", 24, -2)
	listBackground:SetColorTexture(0, 0, 0, 0.3)

	-- Right: the chosen error.
	detailScroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
	detailScroll:SetPoint("TOPLEFT", window, "TOPLEFT", LIST_WIDTH + 24, -62)
	detailScroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -34, 44)

	textBox = CreateFrame("EditBox", nil, detailScroll)
	textBox:SetMultiLine(true)
	textBox:SetAutoFocus(false)
	textBox:SetMaxLetters(0)
	textBox:SetWidth(WIDTH - LIST_WIDTH - 24 - 34 - 10)
	textBox:SetFontObject(_G[ns.settings.fontSize] or GameFontHighlight)
	textBox:SetTextInsets(2, 2, 2, 2)
	textBox:SetScript("OnEscapePressed", textBox.ClearFocus)
	textBox:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(displayed) -- read-only
			if copyMode then
				self:HighlightText()
			end
		end
	end)
	detailScroll:SetScrollChild(textBox)

	-- Bottom: copy, delete, how many are shown.
	copyOneButton = Button(L.COPY_ONE, 200)
	copyOneButton:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, 12)
	copyOneButton:SetScript("OnClick", function()
		copyMode = copyMode ~= "one" and "one" or nil
		Render(true)
	end)
	Tooltip(copyOneButton, L.COPY_ONE, L.COPY_HINT)

	copyAllButton = Button(L.COPY_ALL, 220)
	copyAllButton:SetPoint("LEFT", copyOneButton, "RIGHT", 8, 0)
	copyAllButton:SetScript("OnClick", function()
		copyMode = copyMode ~= "all" and "all" or nil
		Render(true)
	end)
	Tooltip(copyAllButton, L.COPY_ALL, L.COPY_ALL_HINT:format(ns.REPORT_MAX_ERRORS))

	deleteButton = Button(L.DELETE, 170)
	deleteButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 12)
	deleteButton:SetScript("OnClick", function()
		if not selected then return end
		local gone = selected
		Choose(Neighbour(gone)) -- the neighbour takes its place
		copyMode = nil
		ns.Delete(gone)
		detailScroll:SetVerticalScroll(0)
	end)
	Tooltip(deleteButton, L.DELETE, L.DELETE_HINT)

	shownText = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	shownText:SetPoint("RIGHT", deleteButton, "LEFT", -14, 0)

	optionsPanel = CreateFrame("Frame", nil, window)
	optionsPanel:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -26)
	optionsPanel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -10, 10)
	ns.BuildOptions(optionsPanel)

	local names = { L.TAB_ALL, L.TAB_SESSION, L.TAB_PREVIOUS, L.TAB_OPTIONS }
	local previous
	for id, name in ipairs(names) do
		local button = CreateFrame("Button", "ForeverBugsFrameTab" .. id, window, "PanelTabButtonTemplate")
		button:SetID(id)
		button:SetText(name)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
		else
			button:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 12, 2)
		end
		button:SetScript("OnClick", function()
			PlayUISound("IG_CHARACTER_INFO_TAB", 841)
			SelectTab(id)
		end)
		previous = button
	end
	PanelTemplates_SetNumTabs(window, #names)
end

-----------------------------------------------------------------------
-- What the rest of the addon calls

function ns.IsWindowShown()
	return window ~= nil and window:IsShown()
end

-- err: open right on this error (from a chat link).
function ns.ShowWindow(err)
	if not window then
		Create()
	end
	local opening = not window:IsShown()
	if opening then
		newSince = ns.GetSeenId() -- what is new is marked until the window closes
	end
	copyMode = nil
	if err then
		tab = TAB_ALL
		addonFilter = nil
		searchBox:SetText("")
		searchText = ""
		selectedKey, selected = nil, err
	elseif tab == TAB_OPTIONS then
		tab = TAB_ALL
	end
	if opening and not err then
		selectedKey, selected = nil, nil -- open on the newest
	end
	Rebuild()
	window:Show()
	Render(true)
end

function ns.ToggleWindow()
	if ns.IsWindowShown() then
		window:Hide()
	else
		ns.ShowWindow()
	end
end

function ns.ShowOptions()
	if not window then
		Create()
	end
	if not window:IsShown() then
		newSince = ns.GetSeenId()
	end
	tab = TAB_OPTIONS
	window:Show()
	Render()
end

function ns.ApplyFont()
	if textBox then
		textBox:SetFontObject(_G[ns.settings.fontSize] or GameFontHighlight)
	end
end

-- New errors: if the newest row was chosen, the new newest is chosen.
ns.OnUpdate(function()
	if not ns.IsWindowShown() or tab == TAB_OPTIONS then return end
	local before = selected
	local followNewest = selectedKey == nil or (list[1] ~= nil and selectedKey == list[1].key)
	Rebuild()
	if followNewest then
		Choose(list[1])
	end
	Render(selected ~= before)
end)
