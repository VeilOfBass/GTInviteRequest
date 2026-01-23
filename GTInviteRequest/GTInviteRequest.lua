-- =========================================================
-- GTInviteRequest.lua (Rewritten)
-- =========================================================

local addonName = ...
local addonVersion = "dev"

if C_AddOns and C_AddOns.GetAddOnMetadata then
    addonVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or addonVersion
end

local frame = CreateFrame("Frame")

local checkDelay = 5
local hasChecked = false
local waitingForWhoResults = false

-- =========================================================
-- Saved Variables (with safe defaults merge)
-- =========================================================

local defaults = {
    requested = false,
    preferredFriends = {},
    fallbackGuild = "",
    message = "Hey! Could I get a guild invite please? Thanks!",
    fontSize = 12,
    fontFace = "Fonts\\FRIZQT__.TTF"
}

GuildInviteRequestDB = GuildInviteRequestDB or {}
for k, v in pairs(defaults) do
    if GuildInviteRequestDB[k] == nil then
        GuildInviteRequestDB[k] = v
    end
end

-- =========================================================
-- Helpers
-- =========================================================

local function Normalize(str)
    return str and str:lower():gsub("%s+", "") or ""
end

local function ResetRequestState()
    GuildInviteRequestDB.requested = false
    hasChecked = false
end

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

local function ApplyFont(fs)
    local face = GuildInviteRequestDB.fontFace or DEFAULT_FONT
    local size = GuildInviteRequestDB.fontSize or 12

    local ok = fs:SetFont(face, size)
    if not ok then
        fs:SetFont(DEFAULT_FONT, size)
    end
end

-- =========================================================
-- Find preferred BNet friend
-- =========================================================

local function FindOnlineBNetFriend()
    local _, numOnline = BNGetNumFriends()

    for _, preferred in ipairs(GuildInviteRequestDB.preferredFriends) do
        local prefNorm = Normalize(preferred)

        for i = 1, numOnline do
            local info = C_BattleNet.GetFriendAccountInfo(i)
            if info and info.gameAccountInfo and info.gameAccountInfo.isOnline then
                if info.gameAccountInfo.clientProgram == BNET_CLIENT_WOW then
                    if Normalize(info.battleTag) == prefNorm then
                        return info.bnetAccountID, info.battleTag
                    end
                end
            end
        end
    end
end

-- =========================================================
-- Core Logic
-- =========================================================

local function CheckGuildStatus()
    if hasChecked then return end
    hasChecked = true

    if IsInGuild() then
        GuildInviteRequestDB.requested = false
        return
    end

    if GuildInviteRequestDB.requested then return end

    local bnetID, battleTag = FindOnlineBNetFriend()
    if bnetID then
        BNSendWhisper(bnetID, GuildInviteRequestDB.message)
        GuildInviteRequestDB.requested = true
        print("|cff00ff00[" .. addonName .. "]|r Invite requested from " .. battleTag)
        return
    end

    if GuildInviteRequestDB.fallbackGuild ~= "" then
        waitingForWhoResults = true
        C_Timer.After(1, function()
            C_FriendList.SendWho("g-\"" .. GuildInviteRequestDB.fallbackGuild .. "\"")
        end)
    end
end

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("WHO_LIST_UPDATE")

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(checkDelay, CheckGuildStatus)

    elseif event == "GUILD_ROSTER_UPDATE" then
        if IsInGuild() then
            GuildInviteRequestDB.requested = false
        end

    elseif event == "WHO_LIST_UPDATE" then
        if not waitingForWhoResults or GuildInviteRequestDB.requested then return end
        waitingForWhoResults = false

        local num = C_FriendList.GetNumWhoResults()
        if num > 0 then
            local who = C_FriendList.GetWhoInfo(1)
            if who and who.fullName then
                SendChatMessage(GuildInviteRequestDB.message, "WHISPER", nil, who.fullName)
                GuildInviteRequestDB.requested = true
                print("|cff00ff00[" .. addonName .. "]|r Invite requested from " .. who.fullName)
            end
        else
            print("|cffff0000[" .. addonName .. "]|r No members found for fallback guild.")
        end
    end
end)

-- =========================================================
-- Config UI
-- =========================================================

local configFrame = CreateFrame("Frame", "GTInviteRequestConfig", UIParent, "BasicFrameTemplateWithInset")
configFrame:SetSize(450, 500)
configFrame:SetPoint("CENTER")
configFrame:SetMovable(true)
configFrame:EnableMouse(true)
configFrame:RegisterForDrag("LeftButton")
configFrame:SetScript("OnDragStart", configFrame.StartMoving)
configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
configFrame:Hide()

local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", 0, -8)
title:SetText("Glamour Toad Invite Request")
ApplyFont(fs)

-- =========================================================
-- Tabs
-- =========================================================

local tabs, frames = {}, {}
local function ShowTab(i)
    for idx, f in ipairs(frames) do
        f:SetShown(idx == i)
        tabs[idx]:SetEnabled(idx ~= i)
    end
end

local function CreateTab(i, text, x)
    local b = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    b:SetSize(100, 25)
    b:SetPoint("TOPLEFT", 20 + x, -30)
    b:SetText(text)
    b:SetScript("OnClick", function() ShowTab(i) end)
    tabs[i] = b
end

CreateTab(1, "Friends", 0)
CreateTab(2, "Guild", 110)
CreateTab(3, "Message", 220)
CreateTab(4, "Settings", 330)

for i = 1, 4 do
    local f = CreateFrame("Frame", nil, configFrame)
    f:SetPoint("TOPLEFT", 15, -65)
    f:SetPoint("BOTTOMRIGHT", -15, 15)
    f:Hide()
    frames[i] = f
end

-- =========================================================
-- Friends Tab
-- =========================================================

local friendsFrame = frames[1]

local label = friendsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("TOPLEFT", 5, -5)
label:SetText("Preferred Battle.net Friends (top = first tried)")
ApplyFont(fs)

local function RefreshFriendList()
    for _, c in ipairs({friendsFrame:GetChildren()}) do
        if c.row then c:Hide() end
    end

    local y = -30
    for i, tag in ipairs(GuildInviteRequestDB.preferredFriends) do
        local row = CreateFrame("Frame", nil, friendsFrame)
        row.row = true
        row:SetSize(360, 24)
        row:SetPoint("TOPLEFT", 5, y)

        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("LEFT")
        txt:SetText(i .. ". " .. tag)
        ApplyFont(fs)

        local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        del:SetSize(60, 20)
        del:SetPoint("RIGHT")
        del:SetText("Remove")
        del:SetScript("OnClick", function()
            table.remove(GuildInviteRequestDB.preferredFriends, i)
            ResetRequestState()
            RefreshFriendList()
        end)

        y = y - 28
    end
end

local addBox = CreateFrame("EditBox", nil, friendsFrame, "InputBoxTemplate")
addBox:SetPoint("BOTTOMLEFT", 5, 5)
addBox:SetSize(260, 20)
addBox:SetAutoFocus(false)

local addBtn = CreateFrame("Button", nil, friendsFrame, "UIPanelButtonTemplate")
addBtn:SetPoint("LEFT", addBox, "RIGHT", 5, 0)
addBtn:SetSize(80, 22)
addBtn:SetText("Add")
addBtn:SetScript("OnClick", function()
    local t = addBox:GetText()
    if t ~= "" then
        table.insert(GuildInviteRequestDB.preferredFriends, t)
        addBox:SetText("")
        ResetRequestState()
        RefreshFriendList()
    end
end)

-- =========================================================
-- Guild Tab
-- =========================================================

local guildFrame = frames[2]

local guildBox = CreateFrame("EditBox", nil, guildFrame, "InputBoxTemplate")
guildBox:SetPoint("TOP", 0, -60)
guildBox:SetSize(300, 20)
guildBox:SetAutoFocus(false)

guildBox:SetScript("OnEnterPressed", function(self)
    GuildInviteRequestDB.fallbackGuild = self:GetText()
    ResetRequestState()
    self:ClearFocus()
end)

-- =========================================================
-- Message Tab
-- =========================================================

local messageFrame = frames[3]

local messageBox = CreateFrame("EditBox", nil, messageFrame, "InputBoxTemplate")
messageBox:SetPoint("TOP", 0, -60)
messageBox:SetSize(380, 20)
messageBox:SetAutoFocus(false)

messageBox:SetScript("OnEnterPressed", function(self)
    GuildInviteRequestDB.message = self:GetText()
    ResetRequestState()
    self:ClearFocus()
end)

-- =========================================================
-- Settings Tab
-- =========================================================

local settingsFrame = frames[4]

local sizeSlider = CreateFrame("Slider", nil, settingsFrame, "OptionsSliderTemplate")
sizeSlider:SetPoint("TOPLEFT", 20, -60)
sizeSlider:SetMinMaxValues(8, 24)
sizeSlider:SetValueStep(1)
sizeSlider:SetScript("OnValueChanged", function(_, v)
    GuildInviteRequestDB.fontSize = v
    ResetRequestState()
end)

-- =========================================================
-- Show Config
-- =========================================================

local function ShowConfig()
    guildBox:SetText(GuildInviteRequestDB.fallbackGuild)
    messageBox:SetText(GuildInviteRequestDB.message)
    sizeSlider:SetValue(GuildInviteRequestDB.fontSize)
    RefreshFriendList()
    ShowTab(1)
    configFrame:Show()
end

SLASH_GUILDINVITEREQUEST1 = "/gir"
SlashCmdList["GUILDINVITEREQUEST"] = function(msg)
    if msg == "reset" then
        -- Reset to default values
        GuildInviteRequestDB.requested = false
        GuildInviteRequestDB.preferredFriends = {}
        GuildInviteRequestDB.fallbackGuild = ""
        GuildInviteRequestDB.message = "Hey! Could I get a guild invite please? Thanks!"
        GuildInviteRequestDB.fontSize = 12
        GuildInviteRequestDB.fontFace = "Fonts\\FRIZQT__.TTF"
        hasChecked = false
        print("|cff00ff00[" .. addonName .. "]|r Configuration reset to defaults.")
    elseif msg == "check" then
        hasChecked = false
        CheckGuildStatus()
    elseif msg == "list" then
        print("|cff00ff00[" .. addonName .. "]|r Your Battle.net friends:")
        local numBNetTotal, numBNetOnline = BNGetNumFriends()
        for i = 1, numBNetTotal do
            local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
            if accountInfo then
                local status = accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline and "|cff00ff00Online|r" or "|cff888888Offline|r"
                print("  " .. (accountInfo.battleTag or accountInfo.accountName) .. " - " .. status)
            end
        end
    elseif msg == "config" or msg == "settings" then
        ShowConfig()
    elseif msg == "ver" or msg == "version" then
        print("|cff00ff00[" .. addonName .. "]|r Version " .. addonVersion)
    else
        print("|cff00ff00[" .. addonName .. "]|r Commands:")
        print("  /gir config - Open settings GUI")
        print("  /gir check - Manually check and request guild invite")
        print("  /gir reset - Reset all settings to defaults")
        print("  /gir list - List all Battle.net friends")
        print("  /gir ver - Show addon version")
    end
end

