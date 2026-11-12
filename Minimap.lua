-- Minimap button (LibDataBroker + LibDBIcon) and the addon menu entry.

local _, ns = ...
local L = ns.L

local NAME = "ForeverBugs"
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

function ns.CompartmentAvailable()
	return DBIcon ~= nil and DBIcon.IsButtonCompartmentAvailable ~= nil and DBIcon:IsButtonCompartmentAvailable() and true or false
end

function ns.IsInCompartment()
	return DBIcon ~= nil and DBIcon:IsButtonInCompartment(NAME) and true or false
end

function ns.SetInCompartment(value)
	if not DBIcon then return end
	if value then
		DBIcon:AddButtonToCompartment(NAME)
	else
		DBIcon:RemoveButtonFromCompartment(NAME)
	end
end

function ns.SetMinimapShown(show)
	ns.db.minimap.hide = not show
	if not DBIcon then return end
	if show then
		DBIcon:Show(NAME)
	else
		DBIcon:Hide(NAME)
	end
end

if not LDB then
	return
end

local broker = LDB:NewDataObject(NAME, {
	type = "data source",
	label = ns.TITLE,
	text = "0",
	icon = ns.ICON,
})

function broker.OnClick(_, button)
	if button == "RightButton" then
		ns.ShowOptions()
	elseif IsShiftKeyDown() then
		ReloadUI()
	elseif IsAltKeyDown() and ns.settings.altClickWipe then
		ns.Wipe()
	else
		ns.ToggleWindow()
	end
end

-- The newest 9 errors of this session.
function broker.OnTooltipShow(tooltip)
	tooltip:AddLine(ns.TITLE)
	local unseen = ns.CountUnseen()
	if unseen > 0 then
		tooltip:AddLine(L.TOOLTIP_NEW:format(unseen), 1, 0.35, 0.35)
	end
	local current = ns.GetErrors(ns.GetSession())
	if #current == 0 then
		tooltip:AddLine(L.TOOLTIP_NONE, 1, 1, 1)
	else
		for i = #current, math.max(1, #current - 8), -1 do
			local err = current[i]
			local firstLine = ns.DisplayMessage(err):match("^[^\n]*")
			if #firstLine > 80 then
				firstLine = firstLine:sub(1, 77) .. "..."
			end
			tooltip:AddLine(("%dx |cffffd200%s|r: %s"):format(err.counter or 1,
				ns.Escape(err.addon or L.UNKNOWN_ADDON), ns.Escape(firstLine)), 0.85, 0.85, 0.85)
		end
	end
	tooltip:AddLine(" ")
	tooltip:AddLine(L.TOOLTIP_HINT, 0.2, 1, 0.2, true)
end

-- Number of errors in this session. Icon: red while there are errors you have
-- not looked at, yellow when this session has errors and all are seen,
-- plain when there are none.
function ns.RefreshButton()
	local count = #ns.GetErrors(ns.GetSession())
	broker.text = tostring(count)
	if ns.CountUnseen() > 0 then
		broker.iconR, broker.iconG, broker.iconB = 1, 0.35, 0.35
	elseif count > 0 then
		broker.iconR, broker.iconG, broker.iconB = 1, 0.85, 0.3
	else
		broker.iconR, broker.iconG, broker.iconB = 1, 1, 1
	end
end
ns.OnUpdate(ns.RefreshButton)

ns.OnLogin(function()
	if DBIcon then
		DBIcon:Register(NAME, broker, ns.db.minimap)
	end
end)
