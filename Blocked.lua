-- Blocked actions: "Interface action failed because of an AddOn" and friends.
--
-- In WoW Forever the game prints this message from several places, and some
-- of them fire no event, so other error catchers never see them:
--   * UIParentPanelManager: ShowUIPanel/HideUIPanel do nothing in combat when
--     addon code calls them;
--   * Blizzard_GamepadSmartNavigation's SecureHelper: in combat it refuses to
--     mark frames when the game's own code runs tainted (an addon touched its
--     data earlier), e.g. while the quest log on the world map is built.
-- We watch it from three sides, all through hooksecurefunc, so nothing of the
-- game's code is replaced.

local _, ns = ...

local issecretvalue = issecretvalue or function() return false end

local function FrameName(frame)
	local ok, name = pcall(frame.GetName, frame)
	if ok and type(name) == "string" then
		return name
	end
	return tostring(frame)
end

local function IsShown(frame)
	local ok, shown = pcall(frame.IsShown, frame)
	return ok and shown and true or false
end

-- 1. Every refused open/close of a game window in combat, including the
--    repeats the game no longer reports.
local function PanelHook(isShow)
	return function(frame)
		if not frame or not InCombatLockdown() then return end
		-- After a refusal the window stays as it was.
		if IsShown(frame) == isShow then return end
		local stack = debugstack(2)
		local addon, where = ns.FindCulprit(stack)
		if not addon then return end
		ns.StoreText("blocked", isShow and "BLOCKED_SHOW" or "BLOCKED_HIDE", { addon, FrameName(frame) }, stack, addon, where)
	end
end

hooksecurefunc("ShowUIPanel", PanelHook(true))
hooksecurefunc("HideUIPanel", PanelHook(false))

-- A game function in the stack that some addon replaced with its own. The
-- game tells addons who replaced a global (issecurevariable), so this kind of
-- taint gets a name. Taint through anchors or table fields has no such trace.
local function FindReplacedFunction(stack)
	if not issecurevariable then return end
	local checked = {}
	for name in stack:gmatch("in function [`']([%a_][%w_]*)'") do
		if not checked[name] then
			checked[name] = true
			if type(_G[name]) == "function" then
				local isSecure, taintedBy = issecurevariable(name)
				if not isSecure and type(taintedBy) == "string" and taintedBy ~= "" and taintedBy ~= ns.ADDON then
					return taintedBy, name
				end
			end
		end
	end
end

-- 2. Every time the game refuses and reports it. Forever's
--    DisplayInterfaceActionBlockedMessage counts the refusals and prints only
--    the first one of a session, so hooking it sees all of them.
local function OnBlockedMessage()
	local stack = debugstack(2)
	local addon, where = ns.FindCulprit(stack)
	if addon and stack:find("UIParentPanelManager", 1, true) then
		return -- hook 1 records this one, with the window name
	end
	if addon then
		ns.StoreText("blocked", "BLOCKED_MESSAGE", { addon }, stack, addon, where)
		return
	end
	local replacer, functionName = FindReplacedFunction(stack)
	if replacer then
		ns.StoreText("blocked", "BLOCKED_REPLACED", { replacer, functionName }, stack, replacer)
	else
		ns.StoreText("blocked", "BLOCKED_TAINT", {}, stack)
	end
end

if DisplayInterfaceActionBlockedMessage then
	hooksecurefunc("DisplayInterfaceActionBlockedMessage", OnBlockedMessage)
elseif ChatFrameUtil and ChatFrameUtil.AddSystemMessage then
	-- Older interfaces: only the printed message is visible.
	hooksecurefunc(ChatFrameUtil, "AddSystemMessage", function(text)
		if issecretvalue(text) or text ~= INTERFACE_ACTION_BLOCKED then return end
		OnBlockedMessage()
	end)
end

-- 3. Cases the game reports with an event; it names the addon itself.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, addonName, func)
	local stack = debugstack(2)
	local culprit, where = ns.FindCulprit(stack)
	local addon = addonName or culprit
	if culprit ~= addon then
		where = nil
	end
	ns.StoreText("blocked", "BLOCKED_EVENT", { addon or "?", tostring(func), event }, stack, addon, where)
end)
