-- How errors look in the window, in chat and in a copied report.

local _, ns = ...
local L = ns.L

local escapeNonPrintable = C_StringUtil and C_StringUtil.EscapeDecimalNonPrintables

-- Text for an edit box or the chat: "|" would start an escape code there.
function ns.Escape(text)
	if type(text) ~= "string" then
		return ""
	end
	if escapeNonPrintable then
		text = escapeNonPrintable(text) or text
	end
	return (text:gsub("|", "||"))
end

-- Today only the time, otherwise the date too. 24-hour clock.
function ns.FormatTime(t)
	if type(t) ~= "number" then
		return "?"
	end
	if date("%Y%m%d", t) == date("%Y%m%d") then
		return date("%H:%M:%S", t)
	end
	return date("%Y-%m-%d %H:%M:%S", t)
end

local LABEL = "|cffffd200"
local PATH = "|cffffea00"
local LINE = "|cff7fff7f"
local QUOTED = "|cff9fb4ff"
local DIM = "|cff9d9d9d"
local NUMBER = "|cffff9fff"
local VALUE = "|cffffb060"

-- Same places as ns.LOCATION_PATTERN, but keeping the quote or bracket after the path.
local LOCATION = "([^%[%]\"'`<>@:%(%)\n]+%.[LlXx][UuMm][AaLl])([\"%]]*):(%d+)"

-- Shorter paths, with file and line number standing out.
local function ColorizeCode(text)
	text = ns.Escape(text)
	text = text:gsub("Interface[/\\][Aa][Dd][Dd][Oo][Nn][Ss][/\\]", "")
	text = text:gsub(LOCATION, function(path, suffix, line)
		return PATH .. path .. "|r" .. suffix .. ":" .. LINE .. line .. "|r"
	end)
	text = text:gsub("'([^'\n]+)'", QUOTED .. "'%1'|r")
	return text
end

-- "name=value" lines from debuglocals (Forever writes them without spaces).
local function ColorizeLocals(text)
	text = "\n" .. ns.Escape(text) .. "\n"
	text = text:gsub("(\n%s*)([^\n=]-)(%s*=%s*)", "%1" .. PATH .. "%2|r%3")
	text = text:gsub("(=%s*)(%-?[%d%.]+)\n", "%1" .. NUMBER .. "%2|r\n")
	text = text:gsub("(=%s*)(nil)\n", "%1" .. DIM .. "%2|r\n")
	text = text:gsub("(=%s*)(true)\n", "%1" .. VALUE .. "%2|r\n")
	text = text:gsub("(=%s*)(false)\n", "%1" .. VALUE .. "%2|r\n")
	text = text:gsub("(=%s*)(\"[^\n]*\")\n", "%1" .. QUOTED .. "%2|r\n")
	return text:sub(2, -2)
end

local function Field(name, value)
	return LABEL .. name .. ":|r " .. value
end

-- One time for a single occurrence, first and last for repeats.
local function Repeated(err)
	return (err.counter or 1) > 1 and err.firstTime and err.firstTime ~= err.time
end

-- "21:37:20, 21:37:25 x2, 21:41:02": the times of the error's occurrences,
-- oldest first, with repeats in the same second joined.
local function HistoryText(times, format)
	local parts, last, repeats = {}, nil, 0
	local function Flush()
		if last then
			parts[#parts + 1] = format(last) .. (repeats > 1 and (" x" .. repeats) or "")
		end
	end
	for _, t in ipairs(times) do
		if t == last then
			repeats = repeats + 1
		else
			Flush()
			last, repeats = t, 1
		end
	end
	Flush()
	return table.concat(parts, ", ")
end

function ns.FormatForWindow(err)
	local head = {
		Field(L.ADDON, ns.Escape(err.addon or L.UNKNOWN_ADDON)),
		Field(L.KIND, L["KIND_" .. (err.kind or "error")]),
		Field(L.COUNT, tostring(err.counter or 1)),
		Field(L.SESSION, tostring(err.session or "?")),
	}
	local times
	if Repeated(err) then
		times = Field(L.FIRST, ns.FormatTime(err.firstTime)) .. "     " .. Field(L.LAST, ns.FormatTime(err.time))
	else
		times = Field(L.TIME, ns.FormatTime(err.time))
	end
	local lines = { table.concat(head, "     "), times }
	local history = ns.GetHistory(err)
	if #history > 1 or (#history == 1 and (err.counter or 1) > 1) then
		local label = #history < (err.counter or 1) and L.HISTORY_PARTIAL:format(#history, err.counter) or L.HISTORY:format(#history)
		lines[#lines + 1] = Field(label, HistoryText(history, ns.FormatTime))
	end
	if err.where then
		lines[#lines + 1] = Field(L.PLACE, ColorizeCode(err.where))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = ColorizeCode(ns.DisplayMessage(err))
	if err.stack and err.stack ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = LABEL .. L.STACK .. ":|r"
		lines[#lines + 1] = ColorizeCode(err.stack)
	end
	if err.locals and err.locals ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = LABEL .. L.LOCALS .. ":|r"
		lines[#lines + 1] = ColorizeLocals(err.locals)
	end
	return table.concat(lines, "\n")
end

local KIND_NAMES = { error = "Lua error", warning = "Lua warning", blocked = "Blocked action" }

local function AddonVersion(name)
	if not name then return nil end
	local ok, version = pcall(C_AddOns.GetAddOnMetadata, name, "Version")
	return ok and version or nil
end

local function FullTime(t)
	return type(t) == "number" and date("%Y-%m-%d %H:%M:%S", t) or "?"
end

local function ReportHeader(title)
	local gameVersion, build = GetBuildInfo()
	local version = (ns.VERSION and not ns.VERSION:find("^@")) and ns.VERSION or "dev"
	return {
		"```",
		"Forever Bugs " .. version .. " " .. title,
		("Game: WoW Forever %s (%s)"):format(tostring(gameVersion), tostring(build)),
	}
end

-- Addon, type, count, times (and history), place, message and stack of one error.
local function AddErrorLines(lines, err, prefix, withHistory)
	local version = AddonVersion(err.addon)
	lines[#lines + 1] = prefix .. "Addon: " .. (err.addon or "unknown") .. (version and (" " .. version) or "")
	lines[#lines + 1] = ("Type: %s, %dx, session %s"):format(KIND_NAMES[err.kind] or KIND_NAMES.error,
		err.counter or 1, tostring(err.session or "?"))
	if Repeated(err) then
		lines[#lines + 1] = ("Time: first %s, last %s"):format(FullTime(err.firstTime), FullTime(err.time))
	else
		lines[#lines + 1] = "Time: " .. FullTime(err.time)
	end
	if withHistory then
		local history = ns.GetHistory(err)
		if #history > 1 then
			lines[#lines + 1] = "History: " .. HistoryText(history, FullTime)
		end
	end
	if err.where then
		lines[#lines + 1] = "Place: " .. err.where
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = err.message
	if err.stack and err.stack ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Stack:"
		lines[#lines + 1] = (err.stack:gsub("\n$", ""))
	end
end

-- Plain text for GitHub, CurseForge or Discord. Always in English, so any
-- addon author can read it.
function ns.FormatReport(err)
	local lines = ReportHeader("report")
	AddErrorLines(lines, err, "", true)
	if err.locals and err.locals ~= "" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Locals:"
		lines[#lines + 1] = (err.locals:gsub("\n$", ""))
	end
	lines[#lines + 1] = "```"
	return table.concat(lines, "\n")
end

ns.REPORT_MAX_ERRORS = 10
ns.REPORT_MAX_LENGTH = 60000 -- a GitHub issue holds about 65 000 characters

-- Several errors (newest first) in one block: without local variables, at most
-- 10 of them and short enough for a GitHub issue.
function ns.FormatReportMany(list)
	local lines = ReportHeader("report")
	local length, included = 0, 0
	for i = 1, math.min(#list, ns.REPORT_MAX_ERRORS) do
		local part = {}
		AddErrorLines(part, list[i], "#" .. i .. " ")
		local text = table.concat(part, "\n")
		if included > 0 and length + #text > ns.REPORT_MAX_LENGTH then
			break
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = text
		length = length + #text
		included = included + 1
	end
	lines[2] = lines[2] .. (", %d of %d errors"):format(included, #list)
	if included < #list then
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("%d more errors are not included. Filter by addon to copy them."):format(#list - included)
	end
	lines[#lines + 1] = "```"
	return table.concat(lines, "\n")
end
