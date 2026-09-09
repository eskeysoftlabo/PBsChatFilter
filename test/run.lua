-- Behavioural tests for PB's ChatFilter.
--
-- The add-on runs on a console, where one real test costs a whole session: build, upload, boot
-- the PS5, log in, and then talk a guildmate into saying something. harness.lua stubs the part
-- of the client the add-on actually touches -- CHAT_ROUTER and its formatter table, the guild
-- list, saved variables and LibHarvensAddonSettings -- so the logic can be exercised here.
--
--   lua test/run.lua        (from the add-on folder; any Lua 5.1+)
--
-- The stub numbers the guild channels out of order and non-contiguously on purpose: a build
-- that derived the guild index by arithmetic on CHAT_CHANNEL_GUILD_1 would pass against a
-- 1,2,3,4,5 stub and mute the wrong guild on a real client.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
ADDON_DIR = HERE .. "/.."

local failures = 0
local function check(label, got, want)
	local ok = got == want
	if not ok then failures = failures + 1 end
	print(string.format("%s %-56s got=%s want=%s", ok and "PASS" or "FAIL", label, tostring(got), tostring(want)))
end

-- Collect the keys a lang file defines without disturbing the live string table.
local function CollectStringKeys(path)
	local collected = {}
	local realCreate = ZO_CreateStringId
	local realVersion = SafeAddVersion
	ZO_CreateStringId = function(id) collected[id] = true end
	SafeAddVersion = function() end
	dofile(path)
	ZO_CreateStringId = realCreate
	SafeAddVersion = realVersion
	return collected
end

dofile(HERE .. "/harness.lua")

local ALPHA, BRAVO, CHARLIE = 1000, 2000, 3000
SetGuilds({ { id = ALPHA, name = "Alpha" }, { id = BRAVO, name = "Bravo" }, { id = CHARLIE, name = "Charlie" } })

local function Shown(channel, fromName, fromDisplayName)
	ClearOutput()
	Emit(channel, fromName or "@Someone", "hello", fromDisplayName)
	return #ChatOutput == 1
end

local function ShownWithText(channel, text, fromName, fromDisplayName)
	ClearOutput()
	Emit(channel, fromName or "@Someone", text, fromDisplayName)
	return #ChatOutput == 1
end

local RECRUIT = "Casual trade guild, all welcome! " .. GuildLink(777777, "Some Other Guild")
local MY_GUILD_LINK = "have a look " .. GuildLink(2000, "Bravo")

print("\n== 1. load ==")
Fire(EVENT_ADD_ON_LOADED, "PBsChatFilter")
local addon = PBS_CHAT_FILTER
check("version read from manifest", addon.version, "1.2.0")
check("slash command registered", type(SLASH_COMMANDS["/pbfilter"]), "function")
check("short slash registered", type(SLASH_COMMANDS["/pbcf"]), "function")
check("chat formatter wrapped", addon.installed, true)
check("keep-attack formatter wrapped", addon.hookedKeepAttack, true)
check("nothing written to settings at load", next(addon.sv.guilds), nil)

print("\n== 2. the settings panel is built at player activated ==")
check("no panel before activation", #PanelRows, 0)
Fire(EVENT_PLAYER_ACTIVATED)
-- explanation, master, own, 3 x (heading + guild + officer),
-- "Guild recruitment" + note + 2 switches, "General", reset, reload hint
check("panel rows built", #PanelRows, 19)
check("a guild heading is named", PanelRow("2. Bravo") ~= nil, true)
check("no login banner by default", #SystemOutput, 0)

-- A heading with nothing under it draws as an empty collapsible row. Every heading has to be
-- followed by something that is not another heading, and the panel must not end on one.
local function EmptySections()
	local empty = {}
	for index, row in ipairs(PanelRows) do
		if row.type == LibHarvensAddonSettings.ST_SECTION then
			local nextRow = PanelRows[index + 1]
			if not nextRow or nextRow.type == LibHarvensAddonSettings.ST_SECTION then
				empty[#empty + 1] = row.label
			end
		end
	end
	return table.concat(empty, ",")
end
check("no heading is left empty", EmptySections(), "")
check("no bare guild-list heading", PanelRow("Your guilds"), nil)

-- The no-guilds branch: there the heading does have something under it, so it stays.
do
	local builtRows, builtPanel = PanelRows, addon.settingsControls
	PanelRows = {}
	SetGuilds({})
	addon:InitSettings()
	check("empty guild list still gets a heading", PanelRow("Your guilds") ~= nil, true)
	check("and it is not an empty heading", EmptySections(), "")
	PanelRows, addon.settingsControls = builtRows, builtPanel
	SetGuilds({ { id = ALPHA, name = "Alpha" }, { id = BRAVO, name = "Bravo" }, { id = CHARLIE, name = "Charlie" } })
end

print("\n== 3. a fresh install changes nothing ==")
check("guild 1 shown", Shown(CHAT_CHANNEL_GUILD_1), true)
check("guild 2 shown", Shown(CHAT_CHANNEL_GUILD_2), true)
check("officer 3 shown", Shown(CHAT_CHANNEL_OFFICER_3), true)
check("zone shown", Shown(CHAT_CHANNEL_ZONE), true)
check("whisper shown", Shown(CHAT_CHANNEL_WHISPER), true)

print("\n== 4. switching one guild off ==")
Slash("2 off")
check("guild 2 hidden", Shown(CHAT_CHANNEL_GUILD_2), false)
check("officer 2 hidden too", Shown(CHAT_CHANNEL_OFFICER_2), false)
check("guild 1 untouched", Shown(CHAT_CHANNEL_GUILD_1), true)
check("guild 3 untouched", Shown(CHAT_CHANNEL_GUILD_3), true)
check("zone untouched", Shown(CHAT_CHANNEL_ZONE), true)
check("say untouched", Shown(CHAT_CHANNEL_SAY), true)
check("party untouched", Shown(CHAT_CHANNEL_PARTY), true)
check("panel told to re-read", PanelUpdates > 0, true)

print("\n== 5. the officer channel is its own switch ==")
Slash("3 officer off")
check("guild 3 still shown", Shown(CHAT_CHANNEL_GUILD_3), true)
check("officer 3 hidden", Shown(CHAT_CHANNEL_OFFICER_3), false)
Slash("1 guild off")
check("guild 1 hidden", Shown(CHAT_CHANNEL_GUILD_1), false)
check("officer 1 still shown", Shown(CHAT_CHANNEL_OFFICER_1), true)

print("\n== 6. your own messages come back ==")
check("own, by display name", Shown(CHAT_CHANNEL_GUILD_2, "@PinkBanther"), true)
check("own, by character name", Shown(CHAT_CHANNEL_GUILD_2, "Banther the Pink", "@PinkBanther"), true)
check("own, undecorated display name", Shown(CHAT_CHANNEL_GUILD_2, "PinkBanther"), true)
check("somebody else, same channel", Shown(CHAT_CHANNEL_GUILD_2, "@Stranger"), false)
Slash("own off")
check("own hidden once the switch is off", Shown(CHAT_CHANNEL_GUILD_2, "@PinkBanther"), false)
Slash("own on")

print("\n== 7. the master switch ==")
Slash("off")
check("guild 2 back while off", Shown(CHAT_CHANNEL_GUILD_2), true)
check("officer 1 back while off", Shown(CHAT_CHANNEL_OFFICER_2), true)
Slash("on")
check("guild 2 hidden again", Shown(CHAT_CHANNEL_GUILD_2), false)

print("\n== 8. only / all / none ==")
Slash("only 1")
check("only 1: guild 1 shown", Shown(CHAT_CHANNEL_GUILD_1), true)
check("only 1: officer 1 shown", Shown(CHAT_CHANNEL_OFFICER_1), true)
check("only 1: guild 2 hidden", Shown(CHAT_CHANNEL_GUILD_2), false)
check("only 1: guild 3 hidden", Shown(CHAT_CHANNEL_GUILD_3), false)
Slash("none")
check("none: every guild hidden", Shown(CHAT_CHANNEL_GUILD_1), false)
check("none: zone still shown", Shown(CHAT_CHANNEL_ZONE), true)
check("none: whisper still shown", Shown(CHAT_CHANNEL_WHISPER), true)
check("none: emote still shown", Shown(CHAT_CHANNEL_EMOTE), true)
check("none: system still shown", Shown(CHAT_CHANNEL_SYSTEM), true)
Slash("all")
check("all: guild 2 shown", Shown(CHAT_CHANNEL_GUILD_2), true)

print("\n== 9. keep-attack notices follow the guild ==")
Slash("2 off")
ClearOutput()
EmitKeepAttack(CHAT_CHANNEL_GUILD_2, "Farragut")
check("hidden guild's keep notice dropped", #ChatOutput, 0)
ClearOutput()
EmitKeepAttack(CHAT_CHANNEL_GUILD_1, "Farragut")
check("shown guild's keep notice kept", #ChatOutput, 1)

print("\n== 10. settings belong to the guild, not to the slot ==")
-- Bravo is switched off above, sitting at index 2. Put it at index 1 and it stays off there.
SetGuilds({ { id = BRAVO, name = "Bravo" }, { id = ALPHA, name = "Alpha" }, { id = CHARLIE, name = "Charlie" } })
check("Bravo hidden at its new index", Shown(CHAT_CHANNEL_GUILD_1), false)
check("Alpha shown at Bravo's old index", Shown(CHAT_CHANNEL_GUILD_2), true)
SetGuilds({ { id = ALPHA, name = "Alpha" }, { id = BRAVO, name = "Bravo" }, { id = CHARLIE, name = "Charlie" } })

print("\n== 11. it fails open ==")
SetGuilds({})
check("no guild data: guild 2 shown", Shown(CHAT_CHANNEL_GUILD_2), true)
SetGuilds({ { id = ALPHA, name = "Alpha" } })
check("fewer guilds than channels: guild 2 shown", Shown(CHAT_CHANNEL_GUILD_2), true)
check("guild 1 still resolves", Shown(CHAT_CHANNEL_GUILD_1), true)
SetGuilds({ { id = ALPHA, name = "Alpha" }, { id = BRAVO, name = "Bravo" }, { id = CHARLIE, name = "Charlie" } })

print("\n== 12. the status line ==")
ClearOutput()
Slash("")
check("status is not eaten by the filter", #SystemOutput > 0, true)
check("status names a hidden guild", (table.concat(SystemOutput, "\n"):find("Bravo") ~= nil), true)
check("status counts what it hid", (table.concat(SystemOutput, "\n"):find("hidden this session") ~= nil), true)
ClearOutput()
Slash("4")
check("a guild slot you have not filled is refused", (table.concat(SystemOutput, "\n"):find("not in a guild 4") ~= nil), true)
ClearOutput()
Slash("9")
check("a number past the five slots is refused too", (table.concat(SystemOutput, "\n"):find("not in a guild 9") ~= nil), true)
ClearOutput()
Slash("wibble")
check("an unknown command is refused", (table.concat(SystemOutput, "\n"):find("no such command") ~= nil), true)

print("\n== 13. guild recruitment links ==")
Slash("all")
check("off by default: an advert in zone is shown", ShownWithText(CHAT_CHANNEL_ZONE, RECRUIT), true)
Slash("recruit on")
check("advert in zone hidden", ShownWithText(CHAT_CHANNEL_ZONE, RECRUIT), false)
check("advert in say hidden", ShownWithText(CHAT_CHANNEL_SAY, RECRUIT), false)
check("advert in yell hidden", ShownWithText(CHAT_CHANNEL_YELL, RECRUIT), false)
check("ordinary zone chat untouched", ShownWithText(CHAT_CHANNEL_ZONE, "anyone selling nirncrux"), true)
check("an item link is not a guild link", ShownWithText(CHAT_CHANNEL_ZONE, "wts " .. ItemLink(54321, "Nirncrux")), true)
check("a guild channel is never touched by this rule", ShownWithText(CHAT_CHANNEL_GUILD_1, RECRUIT), true)
check("nor is an officer channel", ShownWithText(CHAT_CHANNEL_OFFICER_1, MY_GUILD_LINK), true)

check("whispers exempt by default", ShownWithText(CHAT_CHANNEL_WHISPER, RECRUIT), true)
Slash("recruit whisper on")
check("whisper advert hidden once asked for", ShownWithText(CHAT_CHANNEL_WHISPER, RECRUIT), false)
check("your own outgoing whisper follows it", ShownWithText(CHAT_CHANNEL_WHISPER_SENT, RECRUIT, "@Stranger"), false)
Slash("recruit whisper off")
check("whispers exempt again", ShownWithText(CHAT_CHANNEL_WHISPER, RECRUIT), true)

check("your own advert is shown", ShownWithText(CHAT_CHANNEL_ZONE, RECRUIT, "@PinkBanther"), true)
Slash("own off")
check("and hidden once own is off", ShownWithText(CHAT_CHANNEL_ZONE, RECRUIT, "@PinkBanther"), false)
Slash("own on")

Slash("off")
check("the master switch covers this rule too", ShownWithText(CHAT_CHANNEL_ZONE, RECRUIT), true)
Slash("on")

check("it counted what it hid", addon.hiddenRecruit > 0, true)
ClearOutput()
Slash("")
check("status reports the recruitment rule", (table.concat(SystemOutput, "\n"):find("recruitment") ~= nil), true)

print("\n== 14. reset ==")
Slash("reset")
check("settings cleared", next(addon.sv.guilds), nil)
check("guild 2 shown again", Shown(CHAT_CHANNEL_GUILD_2), true)
check("master back on", addon.sv.enabled, true)
check("own messages back on", addon.sv.keepOwn, true)
check("recruitment rule back off", addon.sv.recruit, false)
check("recruitment adverts shown again", ShownWithText(CHAT_CHANNEL_ZONE, RECRUIT), true)

print("\n== 15. translations ==")
local english = CollectStringKeys(ADDON_DIR .. "/lang/strings.lua")
local japanese = CollectStringKeys(ADDON_DIR .. "/lang/jp.lua")
local missing, extra = {}, {}
for key in pairs(english) do if not japanese[key] then missing[#missing + 1] = key end end
for key in pairs(japanese) do if not english[key] then extra[#extra + 1] = key end end
table.sort(missing)
table.sort(extra)
check("every English string has a Japanese one", table.concat(missing, ","), "")
check("no Japanese string without an English one", table.concat(extra, ","), "")

print("")
if failures == 0 then
	print("all tests passed")
else
	print(failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
