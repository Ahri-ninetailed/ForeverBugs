-- Forever Bugs: catches Lua errors, Lua warnings and blocked actions and
-- names the addon to blame. Built for WoW Forever (interface 1.60.x).
--
-- The folder name starts with "!!", so the game loads this addon before any
-- other one and the error handler below is in place before their code runs.

local ADDON, ns = ...

ns.ADDON = ADDON
ns.TITLE = "Forever Bugs"
ns.ICON = "Interface\\Icons\\Spell_Nature_InsectSwarm"
ns.MAX_ERRORS = 500
ns.FLOOD_LIMIT = 10 -- errors per second; above that we stop recording until it calms down
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version")

local issecretvalue = issecretvalue or function() return false end

-----------------------------------------------------------------------
-- Text: the tables are filled in Locales.lua. Lookups happen at run time,
-- so a language chosen in the settings applies everywhere.

ns.LOCALES = {}

function ns.GetLanguage()
	local chosen = ns.settings and ns.settings.language
	if chosen == "enUS" or chosen == "ruRU" then
		return chosen
	end
	return GetLocale() == "ruRU" and "ruRU" or "enUS"
end

ns.L = setmetatable({}, {
	__index = function(_, key)
		local chosen = ns.LOCALES[ns.GetLanguage()]
		local english = ns.LOCALES.enUS
		return (chosen and chosen[key]) or (english and english[key]) or key
	end,
})
local L = ns.L

function ns.Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ns.TITLE .. ":|r " .. text)
end

-- Replaced by Window.lua. If the window ever fails to load, catching keeps working.
function ns.IsWindowShown() return false end
function ns.ShowWindow() end
function ns.ToggleWindow() end
function ns.ShowOptions() end

-----------------------------------------------------------------------
-- Only one error handler can be active at a time. Other error catchers would
-- compete with us for it (we load first, so they would just stay empty), so
-- the enabled ones are switched off from the next login on, and the player is
-- told so in chat at login. Rivals: BugGrabber, BugSack and ForeverBugs by
-- iThomthi (a different addon with a name like ours).

local switchedOff = {} -- names shown in the login message

local function Plain(text)
	return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s", ""):lower()
end

local function RivalName(name, title)
	if name == ADDON then
		return nil
	elseif name == "!BugGrabber" then
		return "BugGrabber"
	elseif name == "BugSack" then
		return "BugSack"
	elseif Plain(name) == "foreverbugs" or Plain(title) == "foreverbugs" then
		return "ForeverBugs (iThomthi)"
	end
end

do
	local character = UnitNameUnmodified and UnitNameUnmodified("player")
	for i = 1, C_AddOns.GetNumAddOns() do
		local name, title = C_AddOns.GetAddOnInfo(i)
		local shown = type(name) == "string" and RivalName(name, title)
		if shown then
			local ok, state = pcall(C_AddOns.GetAddOnEnableState, name, character)
			if ok and type(state) == "number" and state > 0 and pcall(C_AddOns.DisableAddOn, name) then
				switchedOff[#switchedOff + 1] = shown
			end
		end
	end
end

-----------------------------------------------------------------------
-- Settings

ns.FONTS = { "GameFontHighlightSmall", "GameFontHighlight", "GameFontHighlightMedium", "GameFontHighlightLarge" }

-- Only sounds of the classic era: Forever's game data lacks many sounds of
-- later expansions although SOUNDKIT still lists them (the boss whisper,
-- for one, stays silent).
ns.SOUNDS = {
	"RAID_WARNING",
	"READY_CHECK",
	"TELL_MESSAGE",
	"PVP_THROUGH_QUEUE",
	"MAP_PING",
	"IG_PLAYER_INVITE",
	"IG_QUEST_LIST_COMPLETE",
}

-- Sound kit IDs from the game, in case SOUNDKIT is missing an entry.
local SOUND_IDS = {
	RAID_WARNING = 8959,
	READY_CHECK = 8960,
	TELL_MESSAGE = 3081,
	PVP_THROUGH_QUEUE = 8459,
	MAP_PING = 3175,
	IG_PLAYER_INVITE = 880,
	IG_QUEST_LIST_COMPLETE = 878,
}

local DEFAULTS = {
	autoPopup = false,
	chatReminder = false,
	mute = false,
	masterChannel = false,
	altClickWipe = false,
	fontSize = "GameFontHighlight",
	sound = "RAID_WARNING",
	language = "auto",
	eachTime = false, -- the window lists every occurrence instead of one row per error
	taintLog = false, -- turn the game's taint log on at every login
}

local function IsOneOf(value, list)
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

local function SoundId(key)
	return (SOUNDKIT and SOUNDKIT[key]) or SOUND_IDS[key]
end

-- Plays the alert sound; if the chosen one does not play, the raid warning
-- plays instead. Returns whether the chosen sound played.
function ns.PlayAlertSound(key, channel)
	key = key or ns.settings.sound
	channel = channel or (ns.settings.masterChannel and "Master" or "SFX")
	local willPlay = PlaySound(SoundId(key) or SOUND_IDS.RAID_WARNING, channel)
	if not willPlay and key ~= "RAID_WARNING" then
		PlaySound(SoundId("RAID_WARNING"), channel)
	end
	return willPlay and true or false
end

-- For the settings: plays on the Master channel, so the check does not depend
-- on whether sound effects are on, and says so when the sound is missing.
function ns.PreviewSound(key)
	if not ns.PlayAlertSound(key, "Master") then
		ns.Print(L.SOUND_MISSING)
	end
end

-----------------------------------------------------------------------
-- Who is to blame: the first place in an error message or a call stack
-- that points into a third-party addon folder.

local knownAddons
local function KnownAddons()
	if not knownAddons then
		knownAddons = {}
		for i = 1, C_AddOns.GetNumAddOns() do
			local name = C_AddOns.GetAddOnInfo(i)
			if type(name) == "string" then
				knownAddons[name:lower()] = name
			end
		end
	end
	return knownAddons
end

-- "Interface/AddOns/Name/Sub/File.lua" -> "Name", "Sub/File.lua".
-- Lua shortens long paths from the left ("...dOns/Name/File.lua"); then the
-- folder is recognized by the list of installed addons.
local function SplitPath(path)
	local parts = {}
	for part in path:gmatch("[^/\\]+") do
		parts[#parts + 1] = part
	end
	for i = 1, #parts - 1 do
		if parts[i]:lower() == "addons" then
			return parts[i + 1], table.concat(parts, "/", i + 2)
		end
	end
	local known = KnownAddons()
	for i = 1, #parts - 1 do
		local name = known[parts[i]:match("^%s*(.-)$"):lower()]
		if name then
			return name, table.concat(parts, "/", i + 1)
		end
	end
end

-- Every "path/file.lua:123" in the text. Stacks write paths in several ways:
--   Interface/AddOns/Name/File.lua:12: in function ...
--   [string "@Interface/AddOns/Name/File.lua"]:12: in function ...
--   [Interface/AddOns/Name/File.lua]:12: in function <...>
local LOCATION = "([^%[%]\"'`<>@:%(%)\n]+%.[LlXx][UuMm][AaLl])[\"%]]*:(%d+)"
ns.LOCATION_PATTERN = LOCATION

function ns.FindCulprit(...)
	for i = 1, select("#", ...) do
		local text = select(i, ...)
		if type(text) == "string" and not issecretvalue(text) then
			for path, line in text:gmatch(LOCATION) do
				local folder, file = SplitPath(path)
				if folder and folder ~= ADDON and not folder:lower():find("^blizzard_") then
					local where = file ~= "" and (folder .. "/" .. file) or folder
					return folder, where .. ":" .. line
				end
			end
		end
	end
end

-----------------------------------------------------------------------
-- Storage. Saved errors live in ForeverBugsDB.errors (oldest first).

local db                 -- ForeverBugsDB once the saved variables are ready
local errors = {}        -- db.errors, or a temporary list while loading
local byMessage = {}     -- message -> error, to count repeats
local earlyHistory = {}  -- occurrences caught before the saved variables were ready

-----------------------------------------------------------------------
-- History: every occurrence with its time, in ForeverBugsDB.history (oldest
-- first) as { id = error id, time = time(), session = n }. Kept small: the
-- last 50 occurrences of each error and 1000 in all. The counter of an error
-- still counts every time.

ns.MAX_HISTORY = 1000
ns.MAX_HISTORY_PER_ERROR = 50

local function RemoveHistory(id)
	if not db or not id then return end
	local history = db.history
	for i = #history, 1, -1 do
		if history[i].id == id then
			table.remove(history, i)
		end
	end
end

local function AddHistory(err, t)
	if not db then
		earlyHistory[#earlyHistory + 1] = { err = err, time = t }
		return
	end
	local history = db.history
	history[#history + 1] = { id = err.id, time = t, session = db.session }
	local count, oldest = 0, nil
	for i = 1, #history do
		if history[i].id == err.id then
			count = count + 1
			oldest = oldest or i
		end
	end
	if count > ns.MAX_HISTORY_PER_ERROR then
		table.remove(history, oldest)
	end
	while #history > ns.MAX_HISTORY do
		table.remove(history, 1)
	end
end

-- Times of the error's occurrences, oldest first.
function ns.GetHistory(err)
	local times = {}
	if db and err.id then
		for _, entry in ipairs(db.history) do
			if entry.id == err.id then
				times[#times + 1] = entry.time
			end
		end
	end
	return times
end

local function Remove(err)
	for i = #errors, 1, -1 do
		if errors[i] == err then
			table.remove(errors, i)
			return
		end
	end
end

local function Append(err)
	errors[#errors + 1] = err
	while #errors > ns.MAX_ERRORS do
		local old = table.remove(errors, 1)
		if byMessage[old.message] == old then
			byMessage[old.message] = nil
		end
		RemoveHistory(old.id)
	end
end

local function NextId()
	local id = db.nextId
	db.nextId = id + 1
	return id
end

function ns.GetSession()
	return db and db.session or 0
end

function ns.GetById(id)
	for i = #errors, 1, -1 do
		if errors[i].id == id then
			return errors[i]
		end
	end
end

local SEARCH_FIELDS = { "message", "stack", "locals", "addon", "where" }

local function Contains(err, needle)
	for _, field in ipairs(SEARCH_FIELDS) do
		local value = err[field]
		if type(value) == "string" and value:lower():find(needle, 1, true) then
			return true
		end
	end
	return err.textKey ~= nil and ns.DisplayMessage(err):lower():find(needle, 1, true) ~= nil
end

-- session: number or nil for all; addon: folder name, "?" for unknown, nil for
-- all; text: plain text (not a pattern) to look for.
function ns.GetErrors(session, addon, text)
	local result = {}
	local needle = type(text) == "string" and text ~= "" and text:lower() or nil
	for _, err in ipairs(errors) do
		if (not session or err.session == session)
			and (not addon or (addon == "?" and not err.addon) or err.addon == addon)
			and (not needle or Contains(err, needle)) then
			result[#result + 1] = err
		end
	end
	return result
end

-- Every occurrence of the matching errors, newest first, as
-- { key = history entry, err = error, time = when }. session filters by the
-- session of the occurrence.
function ns.GetOccurrences(session, addon, text)
	local byId = {}
	for _, err in ipairs(ns.GetErrors(nil, addon, text)) do
		if err.id then
			byId[err.id] = err
		end
	end
	local result = {}
	local history = db and db.history or {}
	for i = #history, 1, -1 do
		local entry = history[i]
		local err = byId[entry.id]
		if err and (not session or entry.session == session) then
			result[#result + 1] = { key = entry, err = err, time = entry.time }
		end
	end
	return result
end

-- Addon name -> number of errors, for the given session (nil = all).
function ns.CountByAddon(session)
	local counts = {}
	for _, err in ipairs(ns.GetErrors(session)) do
		local key = err.addon or "?"
		counts[key] = (counts[key] or 0) + 1
	end
	return counts
end

-- Records an error or counts a repeat of it.
-- stack/locals: pass them only when they should be (re)captured.
-- textKey/textArgs: for texts we write ourselves (see ns.StoreText).
function ns.Store(message, kind, stack, locals, addon, where, textKey, textArgs)
	local now = time()
	local session = ns.GetSession()
	local err = byMessage[message]
	if not err then
		err = {
			message = message,
			kind = kind,
			stack = stack,
			locals = locals,
			addon = addon,
			where = where,
			textKey = textKey,
			textArgs = textArgs,
			counter = 1,
			session = session,
			firstTime = now,
			time = now, -- the last time it happened
		}
		if db then
			err.id = NextId()
		end
		byMessage[message] = err
		Append(err)
	else
		err.counter = (err.counter or 1) + 1
		if err.session ~= session then
			-- seen in an older session: it belongs to this one now
			err.session = session
			Remove(err)
			Append(err)
		elseif now - (err.time or now) > 10 then
			-- keep the list in the order errors happen, but not on every repeat of a spam
			Remove(err)
			Append(err)
		end
		err.time = now
		if stack then
			err.stack, err.locals = stack, locals
		end
		if addon then
			err.addon, err.where = addon, where
		end
	end
	AddHistory(err, now)
	ns.OnStored(err)
	return err
end

-- Texts we write ourselves are saved in English: the same text in any
-- language, so repeats keep counting and a copied report is readable by any
-- addon author. The window shows them in the chosen language.
function ns.StoreText(kind, textKey, textArgs, stack, addon, where)
	local message = ns.LOCALES.enUS[textKey]:format(unpack(textArgs))
	return ns.Store(message, kind, stack, nil, addon, where, textKey, textArgs)
end

function ns.DisplayMessage(err)
	if err.textKey and ns.LOCALES.enUS[err.textKey] then
		local ok, text = pcall(string.format, L[err.textKey], unpack(err.textArgs or {}))
		if ok then
			return text
		end
	end
	return err.message
end

-----------------------------------------------------------------------
-- Seen and unseen: errors with an id above db.seenId came in after the
-- window was last looked at. Repeats keep their id, so a known error that
-- keeps coming back does not count as new.

function ns.CountUnseen()
	local seen = db and db.seenId or 0
	local count = 0
	for _, err in ipairs(errors) do
		if err.id and err.id > seen then
			count = count + 1
		end
	end
	return count
end

function ns.GetSeenId()
	return db and db.seenId or 0
end

function ns.MarkAllSeen()
	if db and db.nextId - 1 > db.seenId then
		db.seenId = db.nextId - 1
		if ns.RefreshButton then
			ns.RefreshButton()
		end
	end
end

-----------------------------------------------------------------------
-- The game's taint log (Logs\taint.log): it names the addon that tainted
-- the game's data, which addons themselves cannot find out.

local function GetCVarValue(name)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	return get and get(name)
end

function ns.IsTaintLogOn()
	local value = GetCVarValue("taintLog")
	return value ~= nil and value ~= "0"
end

local function WriteTaintLog(on)
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if set then
		pcall(set, "taintLog", on and "1" or "0")
	end
	return ns.IsTaintLogOn() == on
end

-- The game forgets taintLog when it restarts, so the choice is kept in our
-- settings and applied again at every login (see PLAYER_LOGIN).
function ns.SetTaintLog(on)
	if not WriteTaintLog(on) then
		ns.Print(L.TAINTLOG_REFUSED)
		return
	end
	ns.settings.taintLog = on
	ns.Print(on and L.TAINTLOG_ON or L.TAINTLOG_OFF)
end

function ns.ApplyTaintLog()
	if ns.settings.taintLog and not ns.IsTaintLogOn() and not WriteTaintLog(true) then
		ns.Print(L.TAINTLOG_REFUSED)
	end
end

function ns.Delete(err)
	Remove(err)
	if byMessage[err.message] == err then
		byMessage[err.message] = nil
	end
	RemoveHistory(err.id)
	ns.FireUpdate()
end

function ns.Wipe()
	wipe(errors)
	wipe(byMessage)
	if db then
		wipe(db.history)
	end
	ns.ResetAlerts()
	ns.FireUpdate()
	ns.Print(L.WIPED)
end

local function InitDatabase()
	if type(ForeverBugsDB) ~= "table" then
		ForeverBugsDB = {}
	end
	db = ForeverBugsDB
	ns.db = db
	db.session = (type(db.session) == "number" and db.session or 0) + 1
	if type(db.nextId) ~= "number" then db.nextId = 1 end
	if type(db.seenId) ~= "number" then db.seenId = 0 end
	if type(db.errors) ~= "table" then db.errors = {} end
	if type(db.history) ~= "table" then db.history = {} end
	if type(db.settings) ~= "table" then db.settings = {} end
	if type(db.minimap) ~= "table" then db.minimap = {} end

	local settings = db.settings
	for key, value in pairs(DEFAULTS) do
		if type(settings[key]) ~= type(value) then
			settings[key] = value
		end
	end
	if not IsOneOf(settings.fontSize, ns.FONTS) then settings.fontSize = DEFAULTS.fontSize end
	if not IsOneOf(settings.sound, ns.SOUNDS) then settings.sound = DEFAULTS.sound end
	if not IsOneOf(settings.language, { "auto", "enUS", "ruRU" }) then settings.language = DEFAULTS.language end
	ns.settings = settings

	-- Drop broken entries, rebuild the repeat index.
	local early = errors
	local saved = {}
	for _, err in ipairs(db.errors) do
		if type(err) == "table" and type(err.message) == "string" then
			err.id = err.id or NextId()
			err.firstTime = err.firstTime or err.time
			saved[#saved + 1] = err
		end
	end
	db.errors = saved
	errors = saved
	wipe(byMessage)
	for _, err in ipairs(errors) do
		byMessage[err.message] = err
	end
	while #errors > ns.MAX_ERRORS do
		local old = table.remove(errors, 1)
		if byMessage[old.message] == old then
			byMessage[old.message] = nil
		end
	end

	-- Keep only history entries of errors that still exist.
	local known = {}
	for _, err in ipairs(errors) do
		known[err.id] = true
	end
	local history = {}
	for _, entry in ipairs(db.history) do
		if type(entry) == "table" and type(entry.time) == "number" and known[entry.id] then
			history[#history + 1] = entry
		end
	end
	db.history = history

	-- Errors caught before the saved variables were ready.
	for _, err in ipairs(early) do
		local same = byMessage[err.message]
		if same then
			same.counter = (same.counter or 1) + err.counter
			same.session, same.time = db.session, err.time
			same.stack, same.locals = err.stack or same.stack, err.locals or same.locals
			Remove(same)
			Append(same)
		else
			err.session = db.session
			err.id = NextId()
			byMessage[err.message] = err
			Append(err)
		end
	end
	for _, entry in ipairs(earlyHistory) do
		local err = byMessage[entry.err.message]
		if err then
			AddHistory(err, entry.time)
		end
	end
	wipe(earlyHistory)
end

ns.settings = {}
for key, value in pairs(DEFAULTS) do
	ns.settings[key] = value
end

-- The game normally gives us the saved variables before this file runs
-- (LoadSavedVariablesFirst). On a fresh install, or if that is not supported,
-- we wait for ADDON_LOADED.
if type(ForeverBugsDB) == "table" then
	InitDatabase()
end

-----------------------------------------------------------------------
-- Alerts and listeners

local listeners = {}
local loginListeners = {}
local loggedIn = false
local updating = false

function ns.OnUpdate(fn)
	listeners[#listeners + 1] = fn
end

function ns.OnLogin(fn)
	loginListeners[#loginListeners + 1] = fn
end

local function Safely(fn, ...)
	local ok, problem = pcall(fn, ...)
	if not ok then
		ns.Print(L.INTERNAL_ERROR:format(tostring(problem)))
	end
end

-- Listeners run under pcall: an error inside them must not come back through
-- our own error handler and loop.
function ns.FireUpdate()
	if updating then return end
	updating = true
	for _, fn in ipairs(listeners) do
		Safely(fn)
	end
	updating = false
end

function ns.Link(err)
	return ("|Haddon:foreverbugs:%d|h|cffff5555[%s]|r|h"):format(err.id or 0, err.addon or L.UNKNOWN_ADDON)
end

local lastAlert, alertedAt = -100, {}

function ns.ResetAlerts()
	lastAlert = -100
	wipe(alertedAt)
end

local function Alert(err)
	if not ns.settings.mute then
		ns.PlayAlertSound()
	end
	if ns.settings.chatReminder then
		ns.Print(L.CHAT_REMINDER:format(ns.Link(err)))
	end
end

-- Sound and chat reminder: at most once in 3 seconds, and the same error
-- at most once in 30 seconds.
function ns.OnStored(err)
	if not loggedIn then
		return -- errors from the loading screen are announced once at login
	end
	local now = GetTime()
	local key = err.id or err
	if now - lastAlert > 3 and (not alertedAt[key] or now - alertedAt[key] > 30) then
		lastAlert, alertedAt[key] = now, now
		Safely(Alert, err)
	end
	if ns.settings.autoPopup and not InCombatLockdown() and not ns.IsWindowShown() then
		Safely(ns.ShowWindow)
	end
	ns.FireUpdate()
end

-----------------------------------------------------------------------
-- The error handler

local floodSecond, floodCount, floodNoticeAt = -1, 0, -100

local function Flooded()
	local now = GetTime()
	local second = math.floor(now)
	if second ~= floodSecond then
		floodSecond, floodCount = second, 0
	end
	floodCount = floodCount + 1
	if floodCount > ns.FLOOD_LIMIT then
		if now - floodNoticeAt > 10 then
			floodNoticeAt = now
			ns.Print(L.FLOOD_PAUSED)
		end
		return true
	end
	return false
end

-- Stack and local variables at the place of the error. The level is found
-- the same way the game's own error frame finds it; without the error height
-- the error is 3 levels up from here (CaptureStack <- OnError <- error).
local function CaptureStack()
	local level = 3
	local height = GetCallstackHeight and GetCallstackHeight()
	local errorHeight = GetErrorCallstackHeight and GetErrorCallstackHeight()
	if height and errorHeight then
		level = height - errorHeight + 1
	end
	local stack = debugstack(level)
	local locals = debuglocals and debuglocals(level)
	if issecretvalue(stack) then stack = ns.LOCALES.enUS.SECRET_STACK end
	if issecretvalue(locals) then locals = ns.LOCALES.enUS.SECRET_LOCALS end
	return stack, locals
end

local function RecordError(message, stack, locals, textKey)
	local addon, where
	if stack or not byMessage[message] then
		addon, where = ns.FindCulprit(message, stack)
	end
	ns.Store(message, "error", stack, locals, addon, where, textKey, textKey and {} or nil)
end

local function OnError(message)
	if Flooded() then
		return
	end
	local textKey
	if issecretvalue(message) then
		textKey = "SECRET_MESSAGE"
		message = ns.LOCALES.enUS.SECRET_MESSAGE
	else
		message = tostring(message)
	end
	-- The stack is captured for new errors, for errors from older sessions and
	-- for errors that keep repeating for over 2 minutes.
	local known = byMessage[message]
	local stack, locals
	if not known or known.session ~= ns.GetSession() or time() - (known.time or 0) > 120 then
		stack, locals = CaptureStack()
	end
	Safely(RecordError, message, stack, locals, textKey)
end
ns.OnError = OnError

seterrorhandler(OnError)
-- Nobody else may take the errors away from us.
seterrorhandler = function() end

-----------------------------------------------------------------------
-- Events

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("LUA_WARNING")

-- The game's warning popup would duplicate our record.
if ScriptErrorsFrame and ScriptErrorsFrame.UnregisterEvent then
	ScriptErrorsFrame:UnregisterEvent("LUA_WARNING")
end

events:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			self:UnregisterEvent("ADDON_LOADED")
			if not db then
				InitDatabase()
			end
		end
	elseif event == "PLAYER_LOGIN" then
		loggedIn = true
		if #switchedOff > 0 then
			ns.Print(L.RIVALS_OFF:format(table.concat(switchedOff, ", ")))
		end
		Safely(ns.ApplyTaintLog)
		for _, fn in ipairs(loginListeners) do
			Safely(fn)
		end
		local current = ns.GetErrors(ns.GetSession())
		if #current > 0 then
			Safely(Alert, current[#current])
			if ns.settings.autoPopup then
				Safely(ns.ShowWindow)
			end
		end
		ns.FireUpdate()
	elseif event == "LUA_WARNING" then
		if Flooded() then return end
		local first, second = ...
		local text = type(second) == "string" and second or first
		if type(text) ~= "string" or issecretvalue(text) then return end
		Safely(ns.Store, text, "warning", nil, nil, ns.FindCulprit(text))
	end
end)

-- Clicks on our chat links ("|Haddon:foreverbugs:<id>|h").
if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("SetItemRef", function(_, link)
		local id = type(link) == "string" and tonumber(link:match("^addon:foreverbugs:(%d+)"))
		if id then
			ns.ShowWindow(ns.GetById(id))
		end
	end, ns)
end

-----------------------------------------------------------------------
-- Slash commands

SLASH_FOREVERBUGS1 = "/fbugs"
SLASH_FOREVERBUGS2 = "/foreverbugs"
SlashCmdList.FOREVERBUGS = function(input)
	local command = (input or ""):match("^%s*(.-)%s*$"):lower()
	if command == "" then
		ns.ToggleWindow()
	elseif command == "options" or command == "config" then
		ns.ShowOptions()
	elseif command == "clear" or command == "wipe" then
		ns.Wipe()
	elseif tonumber(command) then
		local number = tonumber(command)
		local err = errors[number]
		if not err then
			ns.Print(L.NO_SUCH_ERROR:format(number, #errors))
			return
		end
		ns.Print(("#%d %s (%dx)"):format(number, ns.Link(err), err.counter or 1))
		DEFAULT_CHAT_FRAME:AddMessage(ns.Escape(err.message))
		if err.stack then
			DEFAULT_CHAT_FRAME:AddMessage(ns.Escape(err.stack))
		end
	else
		ns.Print(L.SLASH_HELP)
	end
end
