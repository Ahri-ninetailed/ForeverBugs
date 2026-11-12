-- Forever Bugs tests. Every test starts its own game: the WoW API from
-- mock.lua plus the addon files in the order of the .toc file.
-- Run with: python tests/run.py

local root = ...
local passed, failed = 0, 0

local function check(name, condition, detail)
	if condition then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL  " .. name .. (detail ~= nil and ("\n      got: " .. tostring(detail)) or ""))
	end
end

local function ReadFile(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end

local function TocFiles()
	local files = {}
	for line in ReadFile(root .. "/!!ForeverBugs.toc"):gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and not line:match("^#") and not line:match("%.xml$") then
			files[#files + 1] = line
		end
	end
	return files
end

local BASE = {
	string = string, table = table, math = math, os = os, io = io,
	pairs = pairs, ipairs = ipairs, select = select, type = type, next = next,
	tostring = tostring, tonumber = tonumber, pcall = pcall, xpcall = xpcall, error = error,
	setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset,
	unpack = unpack, assert = assert, loadstring = loadstring, setfenv = setfenv, print = print,
}

local function RunFile(env, path, ...)
	local chunk = assert(loadstring(ReadFile(path), "@" .. path))
	setfenv(chunk, env)
	return chunk(...)
end

-- options: saved (ForeverBugsDB before loading), lateSaved (given only at
-- ADDON_LOADED), locale, login (false = stay on the loading screen),
-- beforeLoaded(env, ns) runs between loading the files and ADDON_LOADED.
local function NewGame(options)
	options = options or {}
	local env = setmetatable({}, { __index = BASE })
	env._G = env
	RunFile(env, root .. "/tests/mock.lua")
	env.mock.locale = options.locale or "enUS"
	env.ForeverBugsDB = options.saved
	local ns = {}
	for _, file in ipairs(TocFiles()) do
		RunFile(env, root .. "/" .. file, "!!ForeverBugs", ns)
	end
	if options.beforeLoaded then
		options.beforeLoaded(env, ns)
	end
	if options.lateSaved then
		env.ForeverBugsDB = options.lateSaved
	end
	env.mock.Fire("ADDON_LOADED", "!!ForeverBugs")
	if options.login ~= false then
		env.mock.Fire("PLAYER_LOGIN")
	end
	return env, ns
end

local function Errors(env)
	return env.ForeverBugsDB.errors
end

local function Printed(env, needle)
	for _, line in ipairs(env.mock.printed) do
		if line:find(needle, 1, true) then
			return true
		end
	end
	return false
end

local function TextBox(env)
	return env.mock.Find("EditBox", function(o) return o.parent and o.parent.kind == "ScrollFrame" end)
end

-- The visible rows of the error list, top to bottom.
local function Rows(env)
	local rows = {}
	for _, object in ipairs(env.mock.frames) do
		if rawget(object, "isErrorRow") and object.shown then
			rows[#rows + 1] = object
		end
	end
	return rows
end

-- Messages of the visible rows, e.g. "third,second,first".
local function RowTexts(env)
	local texts = {}
	for _, row in ipairs(Rows(env)) do
		texts[#texts + 1] = row.err.message:match("(%w+)$")
	end
	return table.concat(texts, ",")
end

local function Shown(env)
	local found = env.mock.Find("FontString", function(o) return type(o.text) == "string" and o.text:match("^Shown: %d+$") end)
	return found and found.text
end

local function ButtonWithText(env, text)
	return env.mock.Find("Button", function(o) return o.text == text end)
end

local function MenuItem(items, prefix)
	for _, item in ipairs(items) do
		if item.text:sub(1, #prefix) == prefix then
			return item
		end
	end
end

local function Checkbox(env, label, parent)
	return env.mock.Find("CheckButton", function(o)
		return o.Text and o.Text.text == label and (not parent or o.parent == parent)
	end)
end

-----------------------------------------------------------------------
-- Loading

do
	local env, ns = NewGame()
	check("our error handler is installed", env.mock.handler == ns.OnError)
	env.seterrorhandler(function() end)
	check("other addons cannot replace it", env.mock.handler == ns.OnError)
	local disabled = table.concat(env.mock.disabled, ",")
	check("BugGrabber and BugSack get disabled", disabled:find("!BugGrabber", 1, true) and disabled:find("BugSack", 1, true), disabled)
	check("the game's warning popup is switched off", not env.ScriptErrorsFrame.events.LUA_WARNING)
	check("fresh install starts at session 1", env.ForeverBugsDB.session == 1, env.ForeverBugsDB.session)
	check("default settings", ns.settings.sound == "RAID_WARNING" and ns.settings.fontSize == "GameFontHighlight"
		and ns.settings.mute == false and ns.settings.language == "auto")
	check("settings page in the game menu", env.mock.registeredCategory and env.mock.registeredCategory.name == "Forever Bugs")
	check("minimap button registered", env.mock.DBIcon.buttons.ForeverBugs ~= nil
		and env.mock.DBIcon.buttons.ForeverBugs.db == env.ForeverBugsDB.minimap)
end

-----------------------------------------------------------------------
-- Who is to blame

do
	local env, ns = NewGame()
	local function culprit(...)
		local addon, where = ns.FindCulprit(...)
		return tostring(addon) .. " | " .. tostring(where)
	end
	local cases = {
		{ "Interface/AddOns/OpenMap/Map/Window.lua:103: attempt to index nil", "OpenMap | OpenMap/Map/Window.lua:103" },
		{ '[string "@Interface/AddOns/OpenMap/Map/Window.lua"]:103: in function <x>', "OpenMap | OpenMap/Map/Window.lua:103" },
		{ "[Interface/AddOns/OpenMap/Map/Window.lua]:103: in function 'Y'", "OpenMap | OpenMap/Map/Window.lua:103" },
		{ "Interface\\AddOns\\OpenMap\\Map\\Window.lua:103: in function X", "OpenMap | OpenMap/Map/Window.lua:103" },
		{ "...dOns/Baganator/Core/Main.lua:12: attempt to call", "Baganator | Baganator/Core/Main.lua:12" },
		{ "...ns/Library Books/Books.lua:7: bad argument", "Library Books | Library Books/Books.lua:7" },
		{ "...gator/Core/Main.lua:12: attempt to call", "nil | nil" },
		{ "Interface/AddOns/OpenMap/Map/Window.xml:5: script error", "OpenMap | OpenMap/Map/Window.xml:5" },
		{ "no place at all", "nil | nil" },
	}
	for _, case in ipairs(cases) do
		local got = culprit(case[1])
		check("culprit of: " .. case[1], got == case[2], got)
	end
	local stack = "Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua:318: in function <x>\n"
		.. "Interface/AddOns/!!ForeverBugs/Blocked.lua:20: in function <y>\n"
		.. "Interface/AddOns/TwoLineChat/TwoLineChat.lua:50: in function <z>"
	check("game code and our own code are skipped", culprit(stack) == "TwoLineChat | TwoLineChat/TwoLineChat.lua:50", culprit(stack))
	check("the message wins over the stack",
		culprit("Interface/AddOns/OpenMap/Init.lua:5: boom", stack) == "OpenMap | OpenMap/Init.lua:5")
	check("the stack is used when the message has no place",
		culprit("boom", stack) == "TwoLineChat | TwoLineChat/TwoLineChat.lua:50")
end

-----------------------------------------------------------------------
-- Recording errors

do
	local env, ns = NewGame()
	env.mock.stack = "Interface/AddOns/OpenMap/Init.lua:5: in main chunk"
	env.mock.locals = "x = nil\ny = 5"
	env.mock.handler("Interface/AddOns/OpenMap/Init.lua:5: attempt to index a nil value")
	local err = Errors(env)[1]
	check("an error is saved", #Errors(env) == 1 and err.message:find("attempt to index", 1, true))
	check("with addon, place, stack and locals", err.addon == "OpenMap" and err.where == "OpenMap/Init.lua:5"
		and err.stack == env.mock.stack and err.locals == env.mock.locals and err.kind == "error")
	check("with id, session and counter", err.id == 1 and err.session == 1 and err.counter == 1)

	env.mock.handler("Interface/AddOns/OpenMap/Init.lua:5: attempt to index a nil value")
	check("a repeat only counts", #Errors(env) == 1 and err.counter == 2, err.counter)

	env.mock.stack = "new stack"
	env.mock.clock = env.mock.clock + 5
	env.mock.handler("Interface/AddOns/OpenMap/Init.lua:5: attempt to index a nil value")
	check("the stack is kept for a quick repeat", err.stack ~= "new stack")
	env.mock.clock = env.mock.clock + 130
	env.mock.now = env.mock.now + 1
	env.mock.handler("Interface/AddOns/OpenMap/Init.lua:5: attempt to index a nil value")
	check("the stack is refreshed after 2 minutes", err.stack == "new stack")

	env.mock.now = env.mock.now + 1
	env.mock.handler("second error")
	env.mock.clock = env.mock.clock + 5
	env.mock.handler("Interface/AddOns/OpenMap/Init.lua:5: attempt to index a nil value")
	check("a repeat within 10 s keeps its place", Errors(env)[1] == err)
	env.mock.clock = env.mock.clock + 11
	env.mock.handler("Interface/AddOns/OpenMap/Init.lua:5: attempt to index a nil value")
	check("a later repeat moves to the end", Errors(env)[2] == err)

	env.mock.now = env.mock.now + 1
	env.mock.handler({ secret = true })
	check("a hidden error text is replaced", Errors(env)[3].message == ns.L.SECRET_MESSAGE, Errors(env)[3].message)
end

do
	local env, ns = NewGame()
	for i = 1, 15 do
		env.mock.handler("flood " .. i)
	end
	check("more than 10 errors a second pause recording", #Errors(env) == 10, #Errors(env))
	check("with one notice in chat", Printed(env, "too many errors"))
	env.mock.now = env.mock.now + 1
	env.mock.handler("after the flood")
	check("recording resumes the next second", #Errors(env) == 11)
end

do
	local env, ns = NewGame()
	ns.FLOOD_LIMIT = 100000
	for i = 1, 505 do
		env.mock.handler("error number " .. i)
	end
	check("only the last 500 errors are kept", #Errors(env) == 500 and Errors(env)[1].message == "error number 6", #Errors(env))
	env.mock.handler("error number 1")
	check("a dropped error counts as new again", Errors(env)[500].message == "error number 1" and Errors(env)[500].counter == 1)
end

do
	local env = NewGame()
	env.mock.Fire("LUA_WARNING", "Interface/AddOns/Baganator/Bag.lua:3: deprecated call")
	env.mock.now = env.mock.now + 1
	env.mock.Fire("LUA_WARNING", 0, "second warning")
	local first, second = Errors(env)[1], Errors(env)[2]
	check("Lua warnings are saved", first and first.kind == "warning" and first.addon == "Baganator")
	check("also when the event passes a warning type first", second and second.message == "second warning")
end

-----------------------------------------------------------------------
-- Saved variables

do
	local saved = {
		session = 5,
		nextId = 10,
		errors = {
			{ message = "old error", counter = 2, session = 5, time = os.time() - 100, id = 9, stack = "old stack" },
			"junk",
			{ message = 123 },
		},
		settings = { mute = true, sound = "NOPE", fontSize = "Nope", language = "ruRU" },
	}
	local env, ns = NewGame({ saved = saved })
	check("a new session starts", env.ForeverBugsDB.session == 6, env.ForeverBugsDB.session)
	check("broken entries are dropped", #Errors(env) == 1)
	check("good settings are kept, bad ones reset", ns.settings.mute == true and ns.settings.sound == "RAID_WARNING"
		and ns.settings.fontSize == "GameFontHighlight" and ns.settings.language == "ruRU")
	env.mock.stack = "fresh stack"
	env.mock.handler("old error")
	local err = Errors(env)[1]
	check("an old error seen again moves to this session", err.session == 6 and err.counter == 3 and err.stack == "fresh stack")
	env.mock.handler("brand new")
	check("ids continue", Errors(env)[2].id == 10, Errors(env)[2].id)
end

do
	local env = NewGame({
		beforeLoaded = function(env)
			env.mock.handler("Interface/AddOns/Baganator/Load.lua:1: early error")
		end,
	})
	local err = Errors(env)[1]
	check("errors before the saved variables are kept", err and err.id == 1 and err.session == 1 and err.addon == "Baganator")
end

do
	local env = NewGame({
		lateSaved = { session = 3, nextId = 4, errors = { { message = "early error", counter = 1, session = 3, time = 1, id = 3 } } },
		beforeLoaded = function(env)
			env.mock.handler("early error")
			env.mock.now = env.mock.now + 1
			env.mock.handler("other early error")
		end,
	})
	check("without LoadSavedVariablesFirst the saved data is used", env.ForeverBugsDB.session == 4)
	local errors = Errors(env)
	check("early repeats merge into saved errors", #errors == 2 and errors[1].message == "early error" and errors[1].counter == 2
		and errors[1].session == 4, #errors)
	check("early new errors get ids", errors[2].message == "other early error" and errors[2].id == 4)
end

-----------------------------------------------------------------------
-- Sound, chat reminder, auto popup

do
	local env = NewGame({ login = false })
	env.mock.handler("during the loading screen")
	check("no sound on the loading screen", #env.mock.sounds == 0)
	env.mock.Fire("PLAYER_LOGIN")
	check("one sound at login", #env.mock.sounds == 1 and env.mock.sounds[1].id == 8959 and env.mock.sounds[1].channel == "SFX")
end

do
	local env, ns = NewGame()
	local function sounds() return #env.mock.sounds end
	env.mock.handler("A")
	check("sound on a new error", sounds() == 1)
	env.mock.now = env.mock.now + 1
	env.mock.handler("B")
	check("no second sound within 3 seconds", sounds() == 1)
	env.mock.now = env.mock.now + 3
	env.mock.handler("B")
	check("sound again after 3 seconds", sounds() == 2)
	env.mock.now = env.mock.now + 4
	env.mock.handler("A")
	check("the same error is quiet for 30 seconds", sounds() == 2)
	env.mock.now = env.mock.now + 30
	env.mock.handler("A")
	check("and sounds again after that", sounds() == 3)

	ns.settings.mute = true
	env.mock.now = env.mock.now + 100
	env.mock.handler("C")
	check("no sound when muted", sounds() == 3)
	ns.settings.mute = false
	ns.settings.masterChannel = true
	ns.settings.sound = "READY_CHECK"
	env.mock.now = env.mock.now + 100
	env.mock.handler("D")
	local last = env.mock.sounds[sounds()]
	check("chosen sound on the Master channel", last.id == 8960 and last.channel == "Master", last.id)

	ns.settings.chatReminder = true
	env.mock.now = env.mock.now + 100
	env.mock.handler("Interface/AddOns/OpenMap/Init.lua:1: E")
	check("chat reminder with a link", Printed(env, "|Haddon:foreverbugs:") and Printed(env, "[OpenMap]"))

	ns.settings.autoPopup = true
	env.mock.combat = true
	env.mock.now = env.mock.now + 100
	env.mock.handler("F")
	check("no auto popup in combat", not ns.IsWindowShown())
	env.mock.combat = false
	env.mock.now = env.mock.now + 100
	env.mock.handler("G")
	check("auto popup out of combat", ns.IsWindowShown())
end

do
	local env, ns = NewGame({ saved = { session = 1, settings = { sound = "UI_RAID_BOSS_WHISPER_WARNING" } } })
	check("a sound removed from the list resets to the default", ns.settings.sound == "RAID_WARNING")
	env.mock.missingSounds[8960] = true
	ns.settings.sound = "READY_CHECK"
	env.mock.handler("X")
	local sounds = env.mock.sounds
	check("a missing sound falls back to the raid warning", #sounds == 2 and sounds[1].id == 8960 and sounds[2].id == 8959)
	ns.PreviewSound("READY_CHECK")
	check("preview says when a sound is missing", Printed(env, "does not play"))
	check("preview uses the Master channel", sounds[#sounds].channel == "Master")
	env.mock.printed = {}
	ns.PreviewSound("TELL_MESSAGE")
	check("no notice for a sound that plays", not Printed(env, "does not play"))
end

-----------------------------------------------------------------------
-- Blocked actions

local PANEL_STACK = "Interface/AddOns/Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:886: in function 'ShowUIPanel'\n"
	.. "Interface/AddOns/OpenMap/Map/Window.lua:103: in function <Interface/AddOns/OpenMap/Map/Window.lua:100>"

do
	local env, ns = NewGame()
	local map = env.CreateFrame("Frame", "WorldMapFrame")
	map:Hide()
	env.mock.combat, env.mock.secure, env.mock.stack = true, false, PANEL_STACK
	env.ShowUIPanel(map)
	local errors = Errors(env)
	check("a refused window is recorded once", #errors == 1, #errors)
	check("with addon, window and place", errors[1].kind == "blocked" and errors[1].addon == "OpenMap"
		and errors[1].message:find("WorldMapFrame", 1, true) and errors[1].where == "OpenMap/Map/Window.lua:103", errors[1].message)
	check("the game's own message was printed", Printed(env, "Interface action failed"))
	env.ShowUIPanel(map)
	check("repeats are counted although the game stays silent", errors[1].counter == 2 and #errors == 1)

	local bags = env.CreateFrame("Frame", "BagsFrame")
	env.HideUIPanel(bags)
	check("refused closing is recorded too", #errors == 2 and errors[2].message:find("close", 1, true))

	env.mock.combat = false
	map:Hide()
	env.ShowUIPanel(map)
	check("nothing out of combat", #errors == 2)
	env.mock.combat, env.mock.secure = true, true
	env.mock.stack = "Interface/AddOns/Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:886: in function 'ShowUIPanel'"
	map:Hide()
	env.ShowUIPanel(map)
	check("nothing when the game itself opens a window", #errors == 2)
end

do
	local env = NewGame()
	local frame = env.CreateFrame("Frame", "QuestFrame")
	frame:Hide()
	env.mock.combat, env.mock.secure = true, false
	env.mock.stack = "Interface/AddOns/Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua:886: in function 'ShowUIPanel'\n"
		.. "Interface/AddOns/Blizzard_QuestFrame/QuestFrame.lua:12: in function <x>"
	env.ShowUIPanel(frame)
	local err = Errors(env)[1]
	check("only game code in the chain: taint hint", #Errors(env) == 1 and err.addon == nil and err.message:find("taintLog", 1, true))
end

do
	local env = NewGame()
	env.mock.stack = "Interface/AddOns/Baganator/Bags.lua:40: in function <x>"
	env.DisplayInterfaceActionBlockedMessage()
	local err = Errors(env)[1]
	check("the message from another place names the addon", #Errors(env) == 1 and err.addon == "Baganator"
		and err.where == "Baganator/Bags.lua:40")

	env.mock.stack = "nothing useful"
	env.mock.Fire("ADDON_ACTION_FORBIDDEN", "TwoLineChat", "CastSpellByName()")
	err = Errors(env)[2]
	check("protected function events are recorded", err and err.addon == "TwoLineChat" and err.message:find("CastSpellByName", 1, true))
end

do
	local env = NewGame()
	env.mock.stack = "[Interface/AddOns/Blizzard_GamepadSmartNavigation/SecureHelper.lua]:19: in function <x>\n"
		.. "[Interface/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua]:1410: in function 'ToggleWorldMap'"
	env.DisplayInterfaceActionBlockedMessage()
	env.DisplayInterfaceActionBlockedMessage()
	local first = Errors(env)[1]
	check("every refusal counts, not only the one printed in chat", #Errors(env) == 1 and first.counter == 2)
	local printed = 0
	for _, line in ipairs(env.mock.printed) do
		if line == env.INTERFACE_ACTION_BLOCKED then printed = printed + 1 end
	end
	check("while the game prints the message once", printed == 1, printed)

	env.ToggleWorldMap = function() end
	env.mock.replaced.ToggleWorldMap = "MapsPlus"
	env.DisplayInterfaceActionBlockedMessage()
	local second = Errors(env)[2]
	check("a replaced game function names its addon", second and second.addon == "MapsPlus"
		and second.message:find("replaced the game function ToggleWorldMap", 1, true), second and second.message)
	env.mock.replaced.ToggleWorldMap = "!!ForeverBugs"
	env.DisplayInterfaceActionBlockedMessage()
	check("our own replacements are not blamed", first.counter == 3 and #Errors(env) == 2)
end

do
	local env = NewGame()
	local page = env.mock.settingsCategory.frame
	local box = Checkbox(env, "Taint log for finding the culprit", page)
	box:SetChecked(true)
	box:Click()
	check("the taint log switch turns the game's log on", env.mock.cvars.taintLog == "1" and box.checked
		and Printed(env, "the taint log is on"))
	box:SetChecked(false)
	box:Click()
	check("and off", env.mock.cvars.taintLog == "0" and not box.checked)
	env.mock.cvarLocked = true
	box:SetChecked(true)
	box:Click()
	check("a refused switch is reported and stays off", env.mock.cvars.taintLog == "0" and not box.checked
		and Printed(env, "did not let the addon"))
	check("the choice is kept in our settings", env.ForeverBugsDB.settings.taintLog == false)
end

do
	local env = NewGame({ saved = { session = 1, settings = { taintLog = true } } })
	check("the game forgets taintLog on restart: we turn it on again at login", env.mock.cvars.taintLog == "1")
	env = NewGame({ saved = { session = 1, settings = { taintLog = true } }, login = false })
	env.mock.cvarLocked = true
	env.mock.Fire("PLAYER_LOGIN")
	check("and say so if the game refuses", Printed(env, "did not let the addon"))
	env = NewGame()
	check("nothing is turned on unless asked", env.mock.cvars.taintLog == "0")
end

do
	local env, ns = NewGame()
	ns.settings.language = "ruRU"
	env.mock.stack = "[Interface/AddOns/Leatrix_Plus/Leatrix_Plus.lua]:9074: in function <x>"
	env.mock.Fire("ADDON_ACTION_BLOCKED", "Leatrix_Plus", "ChatFrame1:StartSizing()")
	local err = Errors(env)[1]
	check("own texts are saved in English",
		err.message == "Leatrix_Plus called the protected function ChatFrame1:StartSizing() (ADDON_ACTION_BLOCKED).", err.message)
	check("and shown in the chosen language", ns.FormatForWindow(err):find("вызвал защищённую функцию", 1, true) ~= nil)
	check("search finds the shown text", #ns.GetErrors(nil, nil, "защищённую") == 1)
	check("the report stays in English", ns.FormatReport(err):find("called the protected function", 1, true) ~= nil
		and not ns.FormatReport(err):find("вызвал", 1, true))
	ns.settings.language = "enUS"
	env.mock.Fire("ADDON_ACTION_BLOCKED", "Leatrix_Plus", "ChatFrame1:StartSizing()")
	check("repeats count across a language change", #Errors(env) == 1 and err.counter == 2)
	check("report names the version", ns.FormatReport(err):find("Forever Bugs 1.0.0 report", 1, true) ~= nil)
	ns.VERSION = "@project-version@"
	check("an unreleased build says dev", ns.FormatReport(err):find("Forever Bugs dev report", 1, true) ~= nil)
end

-----------------------------------------------------------------------
-- Report and window text

do
	local env, ns = NewGame()
	-- the real formats WoW Forever writes
	env.mock.stack = "[Interface/AddOns/OpenMap/Init.lua]:5: in main chunk\n"
	env.mock.locals = "x=nil\nmsg=\"hi\"\ncount=3\n"
	env.mock.handler("Interface/AddOns/OpenMap/Init.lua:5: bad |cff text")
	local err = Errors(env)[1]
	local report = ns.FormatReport(err)
	check("report is fenced", report:sub(1, 3) == "```" and report:sub(-3) == "```")
	check("report has versions", report:find("Addon: OpenMap 2.0", 1, true) and report:find("Game: WoW Forever 1.60.1 (70888)", 1, true))
	check("report has place, stack and locals", report:find("Place: OpenMap/Init.lua:5", 1, true)
		and report:find("\nStack:\n", 1, true) and report:find("\nLocals:\nx=nil", 1, true))
	local shown = ns.FormatForWindow(err)
	check("window text escapes pipes", shown:find("||cff text", 1, true) ~= nil)
	check("window text shortens paths", not shown:find("Interface/AddOns/", 1, true))
	check("bracketed stack paths are highlighted", shown:find("[|cffffea00OpenMap/Init.lua|r]:|cff7fff7f5|r:", 1, true) ~= nil)
	check("local names and values are highlighted", shown:find("|cffffea00x|r=|cff9d9d9dnil|r", 1, true)
		and shown:find("|cffffea00msg|r=|cff9fb4ff\"hi\"|r", 1, true) and shown:find("|cffffea00count|r=|cffff9fff3|r", 1, true), shown)
	check("today shows only the time", ns.FormatTime(env.mock.clock):match("^%d%d:%d%d:%d%d$") ~= nil)
	check("other days show the date", ns.FormatTime(env.mock.clock - 3 * 86400):match("^%d%d%d%d%-%d%d%-%d%d ") ~= nil)
end

-----------------------------------------------------------------------
-- The window

do
	local env, ns = NewGame()
	env.mock.handler("Interface/AddOns/OpenMap/A.lua:1: first")
	env.mock.now = env.mock.now + 1
	env.mock.handler("Interface/AddOns/Baganator/B.lua:2: second")
	env.mock.now = env.mock.now + 1
	env.mock.handler("Interface/AddOns/OpenMap/C.lua:3: third")

	env.SlashCmdList.FOREVERBUGS("")
	check("/fbugs opens the window", ns.IsWindowShown())
	local rows = Rows(env)
	check("the list shows all errors, newest on top", RowTexts(env) == "third,second,first", RowTexts(env))
	check("a row shows time, addon and the start of the text", rows[1].addonText.text == "OpenMap"
		and rows[1].timeText.text:match("^%d%d:%d%d:%d%d$") and rows[1].messageText.text == "Lua: Interface/AddOns/OpenMap/C.lua:3: third"
		and rows[1].countText.text == "", rows[1].messageText.text)
	check("new errors are marked while the window is open", rows[1].newMark.shown and rows[3].newMark.shown)
	check("the newest is chosen", rows[1].selectedTexture.shown and TextBox(env).text:find("third", 1, true))
	check("how many are shown", Shown(env) == "Shown: 3", Shown(env))

	rows[3]:Click()
	check("a click shows that error", TextBox(env).text:find("first", 1, true) and rows[3].selectedTexture.shown
		and not rows[1].selectedTexture.shown)

	env.mock.clock = env.mock.clock + 60
	env.mock.handler("Interface/AddOns/OpenMap/A.lua:1: first")
	check("a repeat moves up and keeps the choice", RowTexts(env) == "first,third,second" and Rows(env)[1].selectedTexture.shown)
	check("the row counts repeats", Rows(env)[1].countText.text == "x2")
	check("repeats show the first and the last time", TextBox(env).text:find("First:", 1, true)
		and TextBox(env).text:find("Last:", 1, true))

	local box = TextBox(env)
	local before = box.text
	box:Type("typed by the player")
	check("the text cannot be edited", box.text == before)

	local copyOne = ButtonWithText(env, "Copy this error")
	copyOne:Click()
	check("copy one shows its selected report", box.text:sub(1, 3) == "```" and box.text:find("A.lua:1: first", 1, true)
		and box.text:find("Time: first ", 1, true) and box.highlighted and box.focused)
	copyOne:Click()
	check("and goes back", box.text:find("First:", 1, true) and copyOne.text == "Copy this error")

	local copyAll = ButtonWithText(env, "Copy all shown")
	copyAll:Click()
	check("copy all shows every listed error", box.text:find("report, 3 of 3 errors", 1, true)
		and box.text:find("#1 Addon: OpenMap", 1, true) and box.text:find("#3 Addon: Baganator", 1, true) and box.highlighted)
	copyAll:Click()
	check("and goes back too", not box.text:find("```", 1, true))

	local search = env.mock.Find("EditBox", function(o) return rawget(o, "Instructions") ~= nil end)
	search:Type("second")
	check("search narrows the list", RowTexts(env) == "second" and box.text:find("second", 1, true))
	search:Type("(")
	check("special characters do not break search", RowTexts(env) == "" and TextBox(env).text == "No errors here. Nice!")
	search:Type("")

	local dropdown = env.mock.Find("DropdownButton", function(o) return o.parent == env.ForeverBugsFrame end)
	local items = dropdown:GenerateMenu()
	check("addon filter lists addons with counts", MenuItem(items, "All addons") and MenuItem(items, "OpenMap (2)")
		and MenuItem(items, "Baganator (1)"))
	MenuItem(items, "OpenMap").setSelected()
	check("addon filter narrows the list", RowTexts(env) == "first,third")
	copyAll:Click()
	check("copy all copies only the filtered ones", box.text:find("report, 2 of 2 errors", 1, true)
		and not box.text:find("Baganator", 1, true))
	MenuItem(dropdown:GenerateMenu(), "All addons").setSelected()
	check("and resets", RowTexts(env) == "first,third,second")

	Rows(env)[1]:Click()
	env.mock.now = env.mock.now + 1
	env.mock.handler("fourth")
	check("follows a new error when the newest was chosen", Rows(env)[1].selectedTexture.shown
		and TextBox(env).text:find("fourth", 1, true))
	Rows(env)[3]:Click()
	env.mock.now = env.mock.now + 1
	env.mock.handler("fifth")
	check("stays put when reading an older one", Rows(env)[4].selectedTexture.shown and TextBox(env).text:find("third", 1, true))

	ButtonWithText(env, "Delete error"):Click()
	check("delete removes only the chosen error", #Errors(env) == 4 and RowTexts(env) == "fifth,fourth,first,second", RowTexts(env))
	check("and its neighbour takes its place", Rows(env)[4].selectedTexture.shown and TextBox(env).text:find("second", 1, true))

	env.ForeverBugsFrameTab3:Click()
	check("previous session tab", RowTexts(env) == "" and TextBox(env).text == "No errors here. Nice!"
		and env.ForeverBugsFrame.selectedTab == 3)
	env.ForeverBugsFrameTab4:Click()
	check("settings tab hides the error view", not TextBox(env).parent.shown and env.ForeverBugsFrame.selectedTab == 4)
	env.ForeverBugsFrameTab2:Click()
	check("this session tab", RowTexts(env) == "fifth,fourth,first,second")

	env.EventRegistry:TriggerEvent("SetItemRef", "addon:foreverbugs:2", "[x]")
	check("a chat link opens its error", TextBox(env).text:find("second", 1, true) and Rows(env)[4].selectedTexture.shown)

	env.SlashCmdList.FOREVERBUGS("")
	check("/fbugs closes it again", not ns.IsWindowShown())
	env.SlashCmdList.FOREVERBUGS("options")
	check("/fbugs options opens settings", ns.IsWindowShown() and env.ForeverBugsFrame.selectedTab == 4)
	env.SlashCmdList.FOREVERBUGS("1")
	check("/fbugs 1 prints the oldest saved error", Printed(env, "B.lua:2: second"))
	env.SlashCmdList.FOREVERBUGS("99")
	check("/fbugs 99 says there is none", Printed(env, "There is no error #99"))
	env.SlashCmdList.FOREVERBUGS("what")
	check("/fbugs help", Printed(env, "/fbugs clear"))
	env.SlashCmdList.FOREVERBUGS("clear")
	check("/fbugs clear deletes everything", #Errors(env) == 0 and Printed(env, "All saved errors were deleted."))
	env.ForeverBugsFrameTab1:Click()
	check("empty window after clearing", TextBox(env).text == "No errors here. Nice!")
end

-----------------------------------------------------------------------
-- Settings

do
	local env, ns = NewGame()
	ns.ShowOptions()
	local page = env.mock.settingsCategory.frame
	local mute = Checkbox(env, "No sound", page)
	mute:SetChecked(true)
	mute:Click()
	check("checkboxes change settings", ns.settings.mute == true)

	local minimap = Checkbox(env, "Minimap button", page)
	minimap:SetChecked(false)
	minimap:Click()
	check("minimap button can be hidden", env.ForeverBugsDB.minimap.hide == true)
	local compartment = Checkbox(env, "Addon menu at the minimap", page)
	compartment:SetChecked(true)
	compartment:Click()
	check("addon menu entry can be added", ns.IsInCompartment())

	local function Dropdown(firstItem)
		return env.mock.Find("DropdownButton", function(o)
			return o.parent == page and o.menu and MenuItem(o:GenerateMenu(), firstItem) ~= nil
		end)
	end
	MenuItem(Dropdown("Raid warning"):GenerateMenu(), "Ready check").setSelected()
	check("sound choice plays it", ns.settings.sound == "READY_CHECK" and env.mock.sounds[#env.mock.sounds].id == 8960)
	MenuItem(Dropdown("Small"):GenerateMenu(), "Large").setSelected()
	check("text size choice", ns.settings.fontSize == "GameFontHighlightMedium" and TextBox(env).font == env.GameFontHighlightMedium)
	MenuItem(Dropdown("Same as the game"):GenerateMenu(), "Русский").setSelected()
	check("language choice", ns.settings.language == "ruRU" and Printed(env, "/reload"))
	check("the language applies to texts", ns.L.TAB_ALL == "Все ошибки", ns.L.TAB_ALL)
end

do
	local env, ns = NewGame({ locale = "ruRU" })
	check("Russian client gets Russian texts", ns.L.DELETE == "Удалить ошибку")
	ns.settings.language = "enUS"
	check("unless English is chosen", ns.L.DELETE == "Delete error")
	check("missing keys fall back to the key", ns.L.SOMETHING_MISSING == "SOMETHING_MISSING")
end

-----------------------------------------------------------------------
-- Minimap button

do
	local env, ns = NewGame()
	local broker = env.mock.broker
	check("no errors: plain icon", broker.text == "0" and broker.iconG == 1)
	env.mock.handler("Interface/AddOns/OpenMap/A.lua:1: oops")
	check("errors: count and red icon", broker.text == "1" and broker.iconG < 1)

	env.GameTooltip.lines = {}
	broker.OnTooltipShow(env.GameTooltip)
	check("tooltip says how many are new", env.GameTooltip.lines[2] == "New: 1", env.GameTooltip.lines[2])
	check("tooltip lists errors", env.GameTooltip.lines[3] and env.GameTooltip.lines[3]:find("1x", 1, true)
		and env.GameTooltip.lines[3]:find("OpenMap", 1, true), env.GameTooltip.lines[3])

	broker.OnClick(nil, "LeftButton")
	check("click opens the window", ns.IsWindowShown())
	broker.OnClick(nil, "LeftButton")
	check("click again closes it", not ns.IsWindowShown())
	broker.OnClick(nil, "RightButton")
	check("right-click opens settings", ns.IsWindowShown() and env.ForeverBugsFrame.selectedTab == 4)
	env.mock.shift = true
	broker.OnClick(nil, "LeftButton")
	env.mock.shift = false
	check("shift-click reloads", env.mock.reloads == 1)
	env.mock.alt = true
	broker.OnClick(nil, "LeftButton")
	check("alt-click does not delete unless allowed", #Errors(env) == 1)
	ns.settings.altClickWipe = true
	broker.OnClick(nil, "LeftButton")
	env.mock.alt = false
	check("alt-click deletes when allowed", #Errors(env) == 0 and broker.text == "0" and broker.iconG == 1)

	env.GameTooltip.lines = {}
	broker.OnTooltipShow(env.GameTooltip)
	check("tooltip without errors", env.GameTooltip.lines[2] == "No errors in this session.")
end

do
	local env, ns = NewGame({ saved = { session = 1, nextId = 3, seenId = 2,
		errors = { { message = "seen before", id = 2, session = 1, counter = 1, time = 1 } } } })
	local broker = env.mock.broker
	check("seen errors of an earlier session: plain button", broker.iconG == 1)
	env.mock.handler("seen before")
	check("a repeat of a seen error is yellow, not red", broker.iconG == 0.85, broker.iconG)
	env.mock.now = env.mock.now + 1
	env.mock.handler("brand new")
	check("a new error is red", broker.iconG == 0.35)
	ns.ShowWindow()
	check("opening the window marks it seen", broker.iconG == 0.85 and env.ForeverBugsDB.seenId == 3)
	env.mock.now = env.mock.now + 1
	env.mock.handler("while the window is open")
	check("errors shown in the open window are seen", broker.iconG == 0.85)
	ns.ShowOptions()
	env.mock.now = env.mock.now + 1
	env.mock.handler("while on the settings tab")
	check("but not while the settings tab is open", broker.iconG == 0.35)
	ns.Wipe()
	check("no errors: plain again", broker.iconG == 1)
end

do
	local env, ns = NewGame()
	ns.FLOOD_LIMIT = 100000
	for i = 1, 15 do
		env.mock.handler("many " .. i)
	end
	local text = ns.FormatReportMany(ns.GetErrors())
	check("copy all takes at most 10", text:find("report, 10 of 15 errors", 1, true)
		and text:find("5 more errors are not included", 1, true) and not text:find("#11 ", 1, true))
	ns.REPORT_MAX_LENGTH = 50 -- less than one error: still the newest one is included
	text = ns.FormatReportMany(ns.GetErrors())
	check("and stays short enough for GitHub", text:find("report, 1 of 15 errors", 1, true) ~= nil, text:match("[^\n]*report[^\n]*"))
end

-----------------------------------------------------------------------
-- History of occurrences

do
	local env, ns = NewGame()
	env.mock.handler("Interface/AddOns/OpenMap/A.lua:1: boom")
	env.mock.clock = env.mock.clock + 5
	env.mock.handler("Interface/AddOns/OpenMap/A.lua:1: boom")
	env.mock.handler("Interface/AddOns/OpenMap/A.lua:1: boom")
	local err = Errors(env)[1]
	local times = ns.GetHistory(err)
	check("every occurrence is kept with its time", #times == 3 and times[1] + 5 == times[2] and times[2] == times[3])
	local shown = ns.FormatForWindow(err)
	check("details list the history, same-second repeats joined", shown:find("History (3):", 1, true)
		and shown:find(" x2", 1, true), shown:match("History[^\n]*"))
	check("the report has the history", ns.FormatReport(err):find("\nHistory: ", 1, true) ~= nil)
	check("the report of many leaves it out", not ns.FormatReportMany({ err }):find("History:", 1, true))
end

do
	local env, ns = NewGame()
	ns.FLOOD_LIMIT = 100000
	for _ = 1, 60 do
		env.mock.clock = env.mock.clock + 1
		env.mock.handler("again and again")
	end
	local err = Errors(env)[1]
	check("at most 50 occurrences of one error", #ns.GetHistory(err) == 50 and err.counter == 60)
	check("details say only the last ones are kept", ns.FormatForWindow(err):find("History (last 50 of 60):", 1, true) ~= nil)
	ns.MAX_HISTORY = 20
	for i = 1, 25 do
		env.mock.handler("other " .. i)
	end
	check("a limit for all occurrences (1000, here 20)", #env.ForeverBugsDB.history == 20)
	local last = Errors(env)[#Errors(env)]
	ns.Delete(last)
	local left = true
	for _, entry in ipairs(env.ForeverBugsDB.history) do
		if entry.id == last.id then left = false end
	end
	check("deleting an error deletes its history", #env.ForeverBugsDB.history == 19 and left)
	ns.Wipe()
	check("clearing deletes the whole history", #env.ForeverBugsDB.history == 0)
end

do
	local env = NewGame({ saved = {
		session = 2, nextId = 3,
		errors = { { message = "kept", id = 1, session = 2, counter = 2, time = 100 } },
		history = { { id = 1, time = 90, session = 2 }, { id = 1, time = 100, session = 2 }, { id = 2, time = 95, session = 2 }, "junk" },
	} })
	check("saved history of missing errors and junk is dropped", #env.ForeverBugsDB.history == 2)
end

do
	local env, ns = NewGame({
		beforeLoaded = function(env)
			env.mock.handler("early one")
			env.mock.handler("early one")
		end,
	})
	check("occurrences from the loading screen are kept", #ns.GetHistory(Errors(env)[1]) == 2
		and env.ForeverBugsDB.history[1].session == 1)
end

do
	local env, ns = NewGame()
	env.mock.handler("Interface/AddOns/OpenMap/A.lua:1: alpha")
	env.mock.clock = env.mock.clock + 10
	env.mock.handler("Interface/AddOns/Baganator/B.lua:2: beta")
	env.mock.clock = env.mock.clock + 10
	env.mock.handler("Interface/AddOns/OpenMap/A.lua:1: alpha")
	ns.ShowWindow()
	check("one row per error by default", RowTexts(env) == "alpha,beta" and Rows(env)[1].countText.text == "x2", RowTexts(env))

	local eachTime = Checkbox(env, "Each time separately", env.ForeverBugsFrame)
	eachTime:SetChecked(true)
	eachTime:Click()
	check("each time separately lists every occurrence", RowTexts(env) == "alpha,beta,alpha"
		and Rows(env)[1].countText.text == "", RowTexts(env))
	check("the choice is saved", ns.settings.eachTime == true)
	check("a row shows the time of that occurrence", Rows(env)[1].timeText.text ~= Rows(env)[3].timeText.text)
	Rows(env)[3]:Click()
	check("choosing an old occurrence shows its error", Rows(env)[3].selectedTexture.shown
		and not Rows(env)[1].selectedTexture.shown and TextBox(env).text:find("alpha", 1, true))

	ButtonWithText(env, "Copy all shown"):Click()
	check("copy all takes each error once", TextBox(env).text:find("report, 2 of 2 errors", 1, true) ~= nil)
	ButtonWithText(env, "Back to the error"):Click()

	local dropdown = env.mock.Find("DropdownButton", function(o) return o.parent == env.ForeverBugsFrame end)
	MenuItem(dropdown:GenerateMenu(), "Baganator").setSelected()
	check("the addon filter works here too", RowTexts(env) == "beta")
	MenuItem(dropdown:GenerateMenu(), "All addons").setSelected()

	Rows(env)[2]:Click()
	ButtonWithText(env, "Delete error"):Click()
	check("delete removes every occurrence of the error", RowTexts(env) == "alpha,alpha" and #Errors(env) == 1, RowTexts(env))
	check("and chooses a row of another error", Rows(env)[2].selectedTexture.shown)
	Rows(env)[1]:Click()
	ButtonWithText(env, "Delete error"):Click()
	check("never a row of the deleted error", RowTexts(env) == "" and TextBox(env).text == "No errors here. Nice!")

	eachTime:SetChecked(false)
	eachTime:Click()
	check("switching back", ns.settings.eachTime == false)
end

do
	local env, ns = NewGame({ saved = { session = 1, settings = { eachTime = true } } })
	for _, message in ipairs({ "gamma", "alpha", "alpha", "beta" }) do
		env.mock.clock = env.mock.clock + 10
		env.mock.handler(message)
	end
	ns.ShowWindow()
	check("each time mode is remembered", RowTexts(env) == "beta,alpha,alpha,gamma", RowTexts(env))
	Rows(env)[2]:Click()
	ButtonWithText(env, "Delete error"):Click()
	check("after delete the next other error below is chosen", RowTexts(env) == "beta,gamma"
		and Rows(env)[2].selectedTexture.shown and TextBox(env).text:find("gamma", 1, true))
end

print(("%d passed, %d failed"):format(passed, failed))
return failed
