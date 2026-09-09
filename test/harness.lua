-- Stub of just enough ESO client to exercise PBsChatFilter.
--
-- The interesting part is CHAT_ROUTER, which is modelled on the real
-- ZO_ChatRouter:FormatAndAddChatMessage: it calls the registered formatter and only publishes
-- the message if the formatter returned text. That "if" is the whole mechanism the add-on
-- relies on, so the stub reproduces it exactly rather than approximating it.
local DIR = ADDON_DIR

-- ---- string table -------------------------------------------------------------------
local stringValues = {}
local nextId = 1
function ZO_CreateStringId(id, value) if not _G[id] then _G[id] = nextId; nextId = nextId + 1 end; stringValues[_G[id]] = value end
function SafeAddVersion() end
function SafeAddString(id, value) stringValues[id] = value end
function GetString(id) return stringValues[id] or ("<missing " .. tostring(id) .. ">") end

-- ---- channels -----------------------------------------------------------------------
-- Deliberately NOT contiguous, and deliberately not in guild order. The add-on maps channels
-- to guild indices through an explicit table; a build that ever went back to arithmetic on
-- CHAT_CHANNEL_GUILD_1 would filter the wrong guild here and the tests would say so.
CHAT_CHANNEL_SAY = 1
CHAT_CHANNEL_YELL = 2
CHAT_CHANNEL_ZONE = 3
CHAT_CHANNEL_WHISPER = 4
CHAT_CHANNEL_WHISPER_SENT = 9
CHAT_CHANNEL_PARTY = 5
CHAT_CHANNEL_EMOTE = 6
CHAT_CHANNEL_SYSTEM = 7
CHAT_CHANNEL_GUILD_1 = 40
CHAT_CHANNEL_GUILD_2 = 43
CHAT_CHANNEL_GUILD_3 = 46
CHAT_CHANNEL_GUILD_4 = 49
CHAT_CHANNEL_GUILD_5 = 52
CHAT_CHANNEL_OFFICER_1 = 41
CHAT_CHANNEL_OFFICER_2 = 44
CHAT_CHANNEL_OFFICER_3 = 47
CHAT_CHANNEL_OFFICER_4 = 50
CHAT_CHANNEL_OFFICER_5 = 53

-- ---- links --------------------------------------------------------------------------
-- zo_linkhandler.lua: GUILD_LINK_TYPE = "guild", and ZO_LinkHandler_CreateLink writes
-- "|H%d:%s|h[%s]|h" with the link style, the colon-joined data and the display text.
GUILD_LINK_TYPE = "guild"
ITEM_LINK_TYPE = "item"
LINK_STYLE_BRACKETS = 1

function GuildLink(guildId, name)
	return string.format("|H%d:%s:%d|h[%s]|h", LINK_STYLE_BRACKETS, GUILD_LINK_TYPE, guildId, name)
end
function ItemLink(itemId, name)
	return string.format("|H%d:%s:%d|h[%s]|h", LINK_STYLE_BRACKETS, ITEM_LINK_TYPE, itemId, name)
end

-- ---- events -------------------------------------------------------------------------
EVENT_ADD_ON_LOADED = "EVENT_ADD_ON_LOADED"
EVENT_PLAYER_ACTIVATED = "EVENT_PLAYER_ACTIVATED"
EVENT_CHAT_MESSAGE_CHANNEL = 1001
EVENT_GUILD_KEEP_ATTACK_UPDATE = 1002

local handlers = {}
EVENT_MANAGER = {
	RegisterForEvent = function(_, name, event, fn) handlers[event] = handlers[event] or {}; handlers[event][name] = fn end,
	UnregisterForEvent = function(_, name, event) if handlers[event] then handlers[event][name] = nil end end,
}
function Fire(event, ...) for _, fn in pairs(handlers[event] or {}) do fn(event, ...) end end

-- ---- chat ---------------------------------------------------------------------------
ChatOutput = {}    -- what reached a chat window through the formatters
SystemOutput = {}  -- the add-on's own status lines

function ClearOutput() ChatOutput = {}; SystemOutput = {} end

CHAT_ROUTER = {
	registeredMessageFormatters = {},
}
function CHAT_ROUTER:RegisterMessageFormatter(eventKey, formatter)
	self.registeredMessageFormatters[eventKey] = formatter
end
function CHAT_ROUTER:GetRegisteredMessageFormatters()
	return self.registeredMessageFormatters
end
-- ZO_ChatRouter:FormatAndAddChatMessage, cut down to the branch that matters.
function CHAT_ROUTER:FormatAndAddChatMessage(eventKey, ...)
	local formatter = self.registeredMessageFormatters[eventKey]
	if formatter then
		local formattedEventText = formatter(...)
		if formattedEventText then
			ChatOutput[#ChatOutput + 1] = formattedEventText
		end
	end
end
function CHAT_ROUTER:AddSystemMessage(text)
	SystemOutput[#SystemOutput + 1] = text
end

function d(text) print("[d] " .. tostring(text)) end

-- The client's own formatters, registered before any add-on loads. Their output is stubbed
-- down to something a test can match on; the add-on never inspects it.
CHAT_ROUTER:RegisterMessageFormatter(EVENT_CHAT_MESSAGE_CHANNEL,
	function(channel, fromName, text, isCustomerService, fromDisplayName)
		return string.format("[%d] %s: %s", channel, tostring(fromName), tostring(text))
	end)
CHAT_ROUTER:RegisterMessageFormatter(EVENT_GUILD_KEEP_ATTACK_UPDATE,
	function(channel, numGuardsKilled, numAttackers, location)
		return string.format("[%d] keep %s", channel, tostring(location))
	end)

-- What the client does when a message arrives on the wire.
function Emit(channel, fromName, text, fromDisplayName)
	CHAT_ROUTER:FormatAndAddChatMessage(EVENT_CHAT_MESSAGE_CHANNEL, channel, fromName, text, false, fromDisplayName)
end
function EmitKeepAttack(channel, location)
	CHAT_ROUTER:FormatAndAddChatMessage(EVENT_GUILD_KEEP_ATTACK_UPDATE, channel, 3, 5, location or "Farragut")
end

SLASH_COMMANDS = {}
function Slash(argumentString) SLASH_COMMANDS["/pbfilter"](argumentString) end

-- ---- guilds -------------------------------------------------------------------------
local guilds = {}
function SetGuilds(list) guilds = list or {} end
function GetNumGuilds() return #guilds end
function GetGuildId(index) local g = guilds[index]; return g and g.id or 0 end
function GetGuildName(guildId)
	for _, g in ipairs(guilds) do
		if g.id == guildId then return g.name end
	end
	return ""
end

-- ---- the player ---------------------------------------------------------------------
local myDisplayName = "@PinkBanther"
local myCharacterName = "Banther the Pink"
function GetDisplayName() return myDisplayName end
function GetUnitName(unitTag) return unitTag == "player" and myCharacterName or "" end

-- ---- add-on manager -----------------------------------------------------------------
function GetAddOnManager()
	return {
		GetNumAddOns = function() return 1 end,
		GetAddOnInfo = function(_, i) return "PBsChatFilter", "|cFF69B4PB\u{2019}s ChatFilter|r 1.2.0" end,
	}
end

-- ---- saved variables ----------------------------------------------------------------
SavedStore = {}
local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end
ZO_SavedVars = {
	NewAccountWide = function(_, name, version, namespace, defaults)
		SavedStore[name] = SavedStore[name] or {}
		local store = SavedStore[name]
		for k, v in pairs(defaults or {}) do if store[k] == nil then store[k] = DeepCopy(v) end end
		return store
	end,
}

-- ---- LibHarvensAddonSettings --------------------------------------------------------
PanelRows = {}
PanelUpdates = 0
LibHarvensAddonSettings = {
	ST_LABEL = "label", ST_SECTION = "section", ST_CHECKBOX = "checkbox", ST_BUTTON = "button",
	AddAddon = function(_, title)
		local panel = { title = title }
		function panel:AddSetting(row) PanelRows[#PanelRows + 1] = row end
		function panel:UpdateControls() PanelUpdates = PanelUpdates + 1 end
		return panel
	end,
}
function PanelRow(label)
	for _, row in ipairs(PanelRows) do
		if row.label == label then return row end
	end
end

-- ---- load the add-on ----------------------------------------------------------------
-- English strings only: jp.lua would win and the assertions below read better in English.
-- run.lua checks separately that jp.lua covers exactly the same keys.
dofile(DIR .. "/lang/strings.lua")
dofile(DIR .. "/Main.lua")
dofile(DIR .. "/Settings.lua")
