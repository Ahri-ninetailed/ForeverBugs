-- The window: the list on the left (newest on top), the chosen error on the
-- right, tabs for all errors / this session / previous session / settings,
-- search, addon filter and copy-ready reports: "Copy list" under the list
-- takes every error in it, "Copy this error" under the text takes that one,
-- and both open a small copy window with the text selected for Ctrl+C.
--
-- The list has two modes: one row per error (repeats as "x8"), or the
-- timeline (the "eachTime" setting), where every occurrence from the history
-- is a row, newest first, and repeats of an error in the same second are one
-- row with a count. The timeline shows how errors follow each other.
--
-- Rows are picked like files in Windows: a click picks one row, Ctrl-click
-- adds or removes a row, Shift-click picks the range from the last clicked
-- row, Ctrl+Shift-click adds that range. "Copy" and "Delete" then work on the
-- picked rows; the right side shows the row clicked last.

local _, ns = ...
local L = ns.L

local TAB_ALL, TAB_SESSION, TAB_PREVIOUS, TAB_OPTIONS = 1, 2, 3, 4
local WIDTH, HEIGHT = 980, 520
local LIST_WIDTH = 330
local ROW_HEIGHT = 36

local window, searchBox, eachTimeBox, addonDropdown, optionsPanel
local listScroll, listChild, listBackground, detailScroll, textBox
local copyOneButton, copyListButton, deleteButton
local copyFrame          -- the small window with a text to copy, made on first use
local rows = {}

local tab = TAB_ALL
local addonFilter        -- addon folder, "?" for unknown, nil for all
local searchText = ""
local list = {}          -- rows on screen, newest first: { key = ..., err = ..., time = ... }
local selectedKey        -- the chosen row: the error, or a history entry in "each time" mode
local selected           -- the error shown on the right
local copied = false     -- Ctrl+C was pressed since the copy window opened
local copyToken = 0      -- changes every time the copy window opens
local displayed = ""     -- the text box is read-only: typing restores this
local newSince = 0       -- errors with a higher id were new when the window opened
local marked = {}        -- keys of the picked rows; the chosen row is always one of them
local anchorKey          -- where a Shift-click range starts: the row clicked last without Shift
local listErrors, listIncluded = 0, 0 -- errors in the list, and how many of them "Copy list" takes in full

local Render, HideCopy

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

-- Show this row on the right; the other picked rows stay picked.
local function Focus(item)
	selectedKey = item and item.key
	selected = item and item.err
	if item then
		marked[item.key] = true
	end
end

-- Pick only this row.
local function Choose(item)
	wipe(marked)
	Focus(item)
	anchorKey = selectedKey
end

-- The picked rows, in the order of the list.
local function MarkedRows()
	local picked = {}
	for _, item in ipairs(list) do
		if marked[item.key] then
			picked[#picked + 1] = item
		end
	end
	return picked
end

-- Each error of these rows once, in their order.
local function RowsErrors(items)
	local errors, seen = {}, {}
	for _, item in ipairs(items) do
		if not seen[item.err] then
			seen[item.err] = true
			errors[#errors + 1] = item.err
		end
	end
	return errors
end

-- Keys of the rows from one row to another, both included.
local function RangeKeys(fromKey, toKey)
	local from, to
	for i, item in ipairs(list) do
		if item.key == fromKey then from = i end
		if item.key == toKey then to = i end
	end
	if not from or not to then
		return { toKey }
	end
	local keys = {}
	for i = math.min(from, to), math.max(from, to) do
		keys[#keys + 1] = list[i].key
	end
	return keys
end

-- A click on a row, with Ctrl and Shift working like in Windows.
local function ClickRow(item)
	local ctrl = (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
	local shift = IsShiftKeyDown and IsShiftKeyDown()
	if shift and anchorKey ~= nil then
		if not ctrl then
			wipe(marked)
		end
		for _, key in ipairs(RangeKeys(anchorKey, item.key)) do
			marked[key] = true
		end
		Focus(item)
	elseif ctrl then
		if marked[item.key] and #MarkedRows() > 1 then
			marked[item.key] = nil -- unpick it; the right side moves to another picked row
			if selectedKey == item.key then
				Focus(MarkedRows()[1])
			end
		else
			Focus(item)
		end
		anchorKey = item.key
	else
		Choose(item)
	end
end

-- The rows for the current mode, tab, filter and search. The chosen row stays
-- chosen if it is still there, with the other picked rows that are; else the
-- newest row of the same error; else the newest row.
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
	local present = {}
	for _, item in ipairs(list) do
		present[item.key] = true
	end
	for key in pairs(marked) do
		if not present[key] then
			marked[key] = nil
		end
	end
	if anchorKey ~= nil and not present[anchorKey] then
		anchorKey = nil
	end
	local sameError
	for _, item in ipairs(list) do
		if item.key == selectedKey then
			Focus(item)
			return
		end
		if not sameError and item.err == selected then
			sameError = item
		end
	end
	Choose(sameError or list[1])
end

-- title: nil for the widget's own text.
local function Tooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(title or self:GetText())
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
		ClickRow(self.item)
		HideCopy()
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
		local count = eachTime and (item.count or 1) or (err.counter or 1) -- in the timeline: times in that second
		row.countText:SetText(count > 1 and ("x" .. count) or "")
		row.messageText:SetText(L["KIND_SHORT_" .. (err.kind or "error")] .. ": "
			.. ns.Escape(FirstLine(ns.DisplayMessage(err))))
		row.newMark:SetShown(err.id ~= nil and err.id > newSince)
		row.selectedTexture:SetShown(marked[item.key] == true)
		row.selectedTexture:SetColorTexture(1, 0.82, 0, item.key == selectedKey and 0.22 or 0.12) -- the one on the right is brighter
		row:Show()
	end
	for i = #list + 1, #rows do
		rows[i].item, rows[i].err = nil, nil
		rows[i]:Hide()
	end
end

local REPORT_TAB_NAMES = { [TAB_ALL] = "all errors", [TAB_SESSION] = "this session", [TAB_PREVIOUS] = "previous session" }

-- Which list a copied report comes from, in English like the rest of the report.
local function ReportListText()
	local parts = { REPORT_TAB_NAMES[tab] or REPORT_TAB_NAMES[TAB_ALL] }
	if addonFilter == "?" then
		parts[#parts + 1] = "unknown addon"
	elseif addonFilter then
		parts[#parts + 1] = "addon " .. addonFilter
	else
		parts[#parts + 1] = "all addons"
	end
	if searchText ~= "" then
		parts[#parts + 1] = "search \"" .. searchText .. "\""
	end
	if ns.settings.eachTime then
		parts[#parts + 1] = "timeline"
	end
	return table.concat(parts, ", ")
end

-- The report for some rows of the list: all of them, or the picked ones. In
-- "each time" mode it starts with the same rows as the list. Returns the
-- text, how many errors are in it in full, and how many errors there are.
local function BuildReport(items, listText)
	if ns.settings.eachTime then
		return ns.FormatReportTimes(items, listText)
	end
	local errors = RowsErrors(items)
	local text, included = ns.FormatReportMany(errors, listText)
	return text, included, #errors
end

-- The text of the "Copy list" button and the copy window title: the number
-- of rows, like the list shows them.
local function CopyListLabel()
	if not ns.settings.eachTime and listIncluded < listErrors then
		return L.COPY_LIST_PART:format(listIncluded, listErrors)
	end
	return L.COPY_LIST:format(#list)
end

local ORANGE = "|cffff8040"

-- The lines above the text in the copy window. firstLine: which rows these are.
local function ReportInfo(firstLine, items, included, total)
	local lines = {}
	if included < total then
		lines[#lines + 1] = ORANGE .. L.COPY_LIST_ERRORS_PART:format(included, total) .. "|r"
	end
	if ns.settings.eachTime and #items > ns.REPORT_MAX_TIMES then
		lines[#lines + 1] = ORANGE .. L.COPY_TIMES_PART:format(ns.REPORT_MAX_TIMES, #items) .. "|r"
	end
	lines[#lines + 1] = firstLine
	if ns.settings.eachTime then
		lines[#lines + 1] = L.COPY_LIST_EACH_TIME:format(#items, total)
	end
	lines[#lines + 1] = L.COPY_WINDOW_HINT
	return table.concat(lines, "\n")
end

-- What decides the list, in the player's language: tab, addon, search.
local function FilterParts()
	local tabNames = { L.TAB_ALL, L.TAB_SESSION, L.TAB_PREVIOUS }
	local addon = addonFilter == nil and L.ALL_ADDONS or addonFilter == "?" and L.UNKNOWN_ADDON or addonFilter
	return L.COPY_LIST_TAB:format(tabNames[tab] or L.TAB_ALL),
		L.COPY_LIST_ADDON:format(ns.Escape(addon)),
		L.COPY_LIST_SEARCH:format(searchText ~= "" and ("\"" .. ns.Escape(searchText) .. "\"") or "-")
end

-- toTop: scroll the error text back to its beginning (another error is shown).
function Render(toTop)
	if not window then return end
	local isOptions = tab == TAB_OPTIONS
	PanelTemplates_SetTab(window, tab)
	optionsPanel:SetShown(isOptions)
	for _, widget in ipairs({ searchBox, eachTimeBox, addonDropdown, listScroll, listBackground, detailScroll,
		copyOneButton, copyListButton, deleteButton }) do
		widget:SetShown(not isOptions)
	end
	if isOptions then return end
	ns.MarkAllSeen() -- the error view is on screen

	RenderList()
	eachTimeBox:SetChecked(ns.settings.eachTime)
	displayed = selected and ns.FormatForWindow(selected) or L.NO_ERRORS
	textBox:SetText(displayed)

	local _, included, total = BuildReport(list, ReportListText())
	listErrors, listIncluded = total, included
	local picked = MarkedRows()
	local pickedErrors = #RowsErrors(picked)
	copyOneButton:SetEnabled(selected ~= nil)
	copyListButton:SetEnabled(#list > 0)
	deleteButton:SetEnabled(selected ~= nil)
	copyListButton:SetText(CopyListLabel())
	copyOneButton:SetText(#picked > 1 and L.COPY_SELECTED:format(#picked) or L.COPY_ONE)
	deleteButton:SetText(pickedErrors > 1 and L.DELETE_MANY:format(pickedErrors) or L.DELETE)
	if addonDropdown.GenerateMenu then
		addonDropdown:GenerateMenu()
	end
	if toTop then
		detailScroll:SetVerticalScroll(0)
		textBox:ClearFocus()
	end
end

-----------------------------------------------------------------------
-- The copy window: a report as plain text, already selected, so Ctrl+C is
-- all it takes. It shows what it was opened with and does not change.

local COPY_WIDTH, COPY_HEIGHT = 660, 440

function HideCopy()
	if copyFrame then
		copyFrame:Hide()
	end
end

-- Ctrl+C (Cmd+C on a Mac). Read by polling: a key handler on the text box
-- could take the keyboard away from the game.
local function CopyKeysDown()
	if not IsKeyDown then return false end
	local modifier = (IsControlKeyDown and IsControlKeyDown()) or (IsMetaKeyDown and IsMetaKeyDown())
	if not modifier then return false end
	local ok, down = pcall(IsKeyDown, "C")
	return ok and down == true
end

-- After Ctrl+C in the text: "Copied!", then the window closes by itself.
local function WatchCopyKeys(box)
	if copied or not box:HasFocus() or not CopyKeysDown() then return end
	copied = true
	copyFrame.status:SetText(L.COPIED)
	local token = copyToken
	if C_Timer then
		C_Timer.After(1.5, function()
			if copyToken == token then
				HideCopy()
			end
		end)
	end
end

local function SelectAllText(box)
	box:HighlightText()
end

local function CreateCopyFrame()
	copyFrame = CreateFrame("Frame", "ForeverBugsCopyFrame", window, "PortraitFrameTemplate")
	copyFrame:Hide()
	copyFrame:SetSize(COPY_WIDTH, COPY_HEIGHT)
	copyFrame:SetPoint("CENTER", window, "CENTER")
	copyFrame:SetFrameStrata("FULLSCREEN_DIALOG") -- above the main window
	copyFrame:SetToplevel(true)
	copyFrame:SetClampedToScreen(true)
	copyFrame:EnableMouse(true)
	copyFrame:SetMovable(true)
	copyFrame:RegisterForDrag("LeftButton")
	copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
	copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
	copyFrame:SetPortraitToAsset(ns.ICON)
	copyFrame.CloseButton:SetScript("OnClick", HideCopy)

	-- What is in the text and what to press.
	local info = copyFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	info:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 70, -32)
	info:SetWidth(COPY_WIDTH - 70 - 20)
	info:SetJustifyH("LEFT")
	copyFrame.info = info

	local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", info, "BOTTOMLEFT", -58, -10)
	scroll:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -34, 44)
	local background = copyFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
	background:SetPoint("TOPLEFT", scroll, "TOPLEFT", -2, 2)
	background:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 24, -2)
	background:SetColorTexture(0, 0, 0, 0.3)

	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetWidth(COPY_WIDTH - 12 - 34 - 10)
	box:SetFontObject(_G[ns.settings.fontSize] or GameFontHighlight)
	box:SetTextInsets(2, 2, 2, 2)
	box:SetScript("OnEscapePressed", HideCopy)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(copyFrame.copyText) -- read-only
			self:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", SelectAllText) -- a click into the text selects all of it again
	box:SetScript("OnMouseUp", SelectAllText)
	box:SetScript("OnUpdate", WatchCopyKeys)
	scroll:SetScrollChild(box)
	copyFrame.box, copyFrame.scroll = box, scroll

	local close = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
	close:SetSize(120, 24)
	close:SetText(L.CLOSE)
	close:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -12, 12)
	close:SetScript("OnClick", HideCopy)

	local status = copyFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	status:SetPoint("LEFT", copyFrame, "BOTTOMLEFT", 16, 24)
	status:SetTextColor(0.3, 1, 0.3)
	copyFrame.status = status
end

local function ShowCopy(title, info, text)
	if not copyFrame then
		CreateCopyFrame()
	end
	copyFrame:SetTitle(title)
	copyFrame.info:SetText(info)
	copyFrame.copyText = ns.Escape(text)
	copyFrame.box:SetText(copyFrame.copyText)
	copyFrame.status:SetText("")
	copied = false
	copyToken = copyToken + 1
	copyFrame:Show()
	copyFrame:Raise()
	copyFrame.scroll:SetVerticalScroll(0)
	copyFrame.box:SetFocus()
	copyFrame.box:HighlightText()
end

local function CopyList()
	if #list == 0 then return end
	local report, included, total = BuildReport(list, ReportListText())
	local tabPart, addonPart, searchPart = FilterParts()
	local filters = tabPart .. "     " .. addonPart .. (searchText ~= "" and ("     " .. searchPart) or "")
	ShowCopy(CopyListLabel(), ReportInfo(filters, list, included, total), report)
end

-- "Copy this error", or "Copy selected" when several rows are picked.
local function CopyPicked()
	if not selected then return end
	local picked = MarkedRows()
	if #picked <= 1 then
		local info = L.COPY_LIST_ADDON:format(ns.Escape(selected.addon or L.UNKNOWN_ADDON)) .. "\n" .. L.COPY_WINDOW_HINT
		ShowCopy(L.COPY_ONE, info, ns.FormatReport(selected))
		return
	end
	local report, included, total = BuildReport(picked, ReportListText() .. (", %d picked rows"):format(#picked))
	ShowCopy(L.COPY_SELECTED:format(#picked), ReportInfo(L.COPY_SELECTED_INFO:format(#picked, #list), picked, included, total), report)
end

-- The "Copy list" tooltip says what exactly goes into the text.
local function CopyListTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(CopyListLabel())
	GameTooltip:AddLine(L.COPY_LIST_HINT, 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	if listIncluded < listErrors then
		GameTooltip:AddLine(L.COPY_LIST_ERRORS_PART:format(listIncluded, listErrors), 1, 0.5, 0.25, true)
	else
		GameTooltip:AddLine(L.COPY_LIST_ERRORS:format(listErrors), 1, 1, 1, true)
	end
	for _, part in ipairs({ FilterParts() }) do
		GameTooltip:AddLine(part, 1, 1, 1, true)
	end
	if ns.settings.eachTime then
		GameTooltip:AddLine(L.COPY_LIST_EACH_TIME:format(#list, listErrors), 1, 1, 1, true)
	end
	GameTooltip:Show()
end

-- The row to choose after the picked errors are deleted: the next row below
-- the picked ones (or above them) that belongs to another error.
local function Neighbour(gone)
	local first, last
	for i, item in ipairs(list) do
		if marked[item.key] then
			first = first or i
			last = i
		end
	end
	first, last = first or 1, last or 1
	for i = last + 1, #list do
		if not gone[list[i].err] then return list[i] end
	end
	for i = first - 1, 1, -1 do
		if not gone[list[i].err] then return list[i] end
	end
	for i = first, last do -- between picked rows that were not side by side
		if not gone[list[i].err] then return list[i] end
	end
end

local function DeletePicked()
	if not selected then return end
	local gone, errors = {}, {}
	for _, item in ipairs(MarkedRows()) do
		if not gone[item.err] then
			gone[item.err] = true
			errors[#errors + 1] = item.err
		end
	end
	Choose(Neighbour(gone)) -- the neighbour takes their place
	HideCopy()
	ns.DeleteMany(errors)
	detailScroll:SetVerticalScroll(0)
end

local function Refresh()
	HideCopy()
	Rebuild()
	Render(true)
end

local function SelectTab(id)
	tab = id
	HideCopy()
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
		HideCopy() -- else it would come back with the window
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
		end
	end)
	detailScroll:SetScrollChild(textBox)

	-- Bottom: "Copy list" under the list; under the error text: copy it,
	-- delete it. Both copy buttons open the copy window.
	copyListButton = Button(L.COPY_LIST:format(0), LIST_WIDTH)
	copyListButton:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 12, 12)
	copyListButton:SetScript("OnClick", CopyList)
	copyListButton:SetScript("OnEnter", CopyListTooltip)
	copyListButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	copyOneButton = Button(L.COPY_ONE, 210)
	copyOneButton:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", LIST_WIDTH + 24, 12)
	copyOneButton:SetScript("OnClick", CopyPicked)
	Tooltip(copyOneButton, nil, L.COPY_HINT)

	deleteButton = Button(L.DELETE, 190)
	deleteButton:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 12)
	deleteButton:SetScript("OnClick", DeletePicked)
	Tooltip(deleteButton, nil, L.DELETE_HINT)

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
	HideCopy()
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
	HideCopy()
	window:Show()
	Render()
end

function ns.ApplyFont()
	local font = _G[ns.settings.fontSize] or GameFontHighlight
	if textBox then
		textBox:SetFontObject(font)
	end
	if copyFrame then
		copyFrame.box:SetFontObject(font)
	end
end

-- New errors: if the newest row was chosen (and only it), the new newest is chosen.
ns.OnUpdate(function()
	if not ns.IsWindowShown() or tab == TAB_OPTIONS then return end
	local before = selected
	local followNewest = selectedKey == nil
		or (list[1] ~= nil and selectedKey == list[1].key and #MarkedRows() <= 1)
	Rebuild()
	if followNewest then
		Choose(list[1])
	end
	Render(selected ~= before)
end)
