local addonName = "GTInviteRequest"
local hasChecked = false
local checkDelay = 5 -- seconds to wait after login before checking
local waitingForWhoResults = false -- Flag to track if we're expecting /who results

local frame = CreateFrame("Frame")

-- Saved variables (persists between sessions)
GuildInviteRequestDB = GuildInviteRequestDB or {
    requested = false,
    preferredFriends = {}, -- Stored as BattleTags
    fallbackGuild = "Glamour Toads",
    message = "Hey! Could I get a guild invite please? Thanks!"
}

-- Function to find an online BNet friend playing WoW
local function FindOnlineBNetFriend()
    local numBNetTotal, numBNetOnline = BNGetNumFriends()
    
    for _, preferredFriend in ipairs(GuildInviteRequestDB.preferredFriends) do
        for i = 1, numBNetOnline do
            local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
            
            if accountInfo then
                local battleTag = accountInfo.battleTag
                local accountName = accountInfo.accountName
                
                -- Check if this is one of our preferred friends
                if battleTag == preferredFriend or accountName == preferredFriend then
                    -- Check if they're playing WoW
                    if accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
                        local gameInfo = accountInfo.gameAccountInfo
                        if gameInfo.clientProgram == BNET_CLIENT_WOW then
                            return gameInfo.characterName, gameInfo.realmName, battleTag, accountInfo.bnetAccountID
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

-- Function to check guild status and message friend
local function CheckGuildStatus()
    if hasChecked then return end
    hasChecked = true
    
    -- Check if player is in a guild
    local guildName = GetGuildInfo("player")
    
    if not guildName and not GuildInviteRequestDB.requested then
        -- Not in a guild and haven't requested yet
        local charName, realmName, battleTag, bnetID = FindOnlineBNetFriend()
        
        if charName and bnetID then
            -- Send Battle.net whisper
            BNSendWhisper(bnetID, GuildInviteRequestDB.message)
            
            -- Mark as requested
            GuildInviteRequestDB.requested = true
            
            print("|cff00ff00[" .. addonName .. "]|r Guild invite requested from " .. battleTag .. " via Battle.net")
        else
            -- No BNet friends online, try /who for the fallback guild
            print("|cff00ff00[" .. addonName .. "]|r No Battle.net friends online, searching for '" .. GuildInviteRequestDB.fallbackGuild .. "' members...")
            waitingForWhoResults = true
            C_Timer.After(1, function()
                C_FriendList.SendWho("g-\"" .. GuildInviteRequestDB.fallbackGuild .. "\"")
            end)
        end
    elseif guildName then
        print("|cff00ff00[" .. addonName .. "]|r You're already in a guild: " .. guildName)
        GuildInviteRequestDB.requested = false -- Reset for future use
    end
end

-- Event handler
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
frame:RegisterEvent("WHO_LIST_UPDATE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Wait a bit for game data to load
        C_Timer.After(checkDelay, CheckGuildStatus)
    elseif event == "GUILD_ROSTER_UPDATE" then
        -- If we join a guild, reset the requested flag
        local guildName = GetGuildInfo("player")
        if guildName then
            GuildInviteRequestDB.requested = false
        end
    elseif event == "WHO_LIST_UPDATE" then
        -- Process /who results only if we triggered it
        if not waitingForWhoResults then return end
        waitingForWhoResults = false
        
        if GuildInviteRequestDB.requested then return end
        
        local numWho = C_FriendList.GetNumWhoResults()
        if numWho > 0 then
            local whoInfo = C_FriendList.GetWhoInfo(1)
            if whoInfo and whoInfo.fullName then
                SendChatMessage(GuildInviteRequestDB.message, "WHISPER", nil, whoInfo.fullName)
                GuildInviteRequestDB.requested = true
                print("|cff00ff00[" .. addonName .. "]|r Guild invite requested from " .. whoInfo.fullName .. " (from " .. GuildInviteRequestDB.fallbackGuild .. ")")
            end
        else
            print("|cffff0000[" .. addonName .. "]|r No members of '" .. GuildInviteRequestDB.fallbackGuild .. "' found online.")
        end
    end
end)

-- Create Config GUI
local configFrame = CreateFrame("Frame", "GTInviteRequestConfig", UIParent, "BasicFrameTemplateWithInset")
configFrame:SetSize(400, 500)
configFrame:SetPoint("CENTER")
configFrame:SetMovable(true)
configFrame:EnableMouse(true)
configFrame:RegisterForDrag("LeftButton")
configFrame:SetScript("OnDragStart", configFrame.StartMoving)
configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
configFrame:Hide()

configFrame.title = configFrame:CreateFontString(nil, "OVERLAY")
configFrame.title:SetFontObject("GameFontHighlight")
configFrame.title:SetPoint("TOP", configFrame.TitleBg, "TOP", 0, -5)
configFrame.title:SetText("Glamour Toad Invite Request - Settings")

-- Instructions
local instructions = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
instructions:SetPoint("TOPLEFT", 20, -40)
instructions:SetText("Add Battle.net friends (in order of preference):")

-- Scroll frame for friend list
local scrollFrame = CreateFrame("ScrollFrame", nil, configFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 20, -65)
scrollFrame:SetPoint("BOTTOMRIGHT", -40, 190)

local scrollChild = CreateFrame("Frame")
scrollFrame:SetScrollChild(scrollChild)
scrollChild:SetWidth(scrollFrame:GetWidth())
scrollChild:SetHeight(1)

-- Function to refresh the friend list display
local function RefreshFriendList()
    -- Clear existing elements
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = 0
    
    for i, battleTag in ipairs(GuildInviteRequestDB.preferredFriends) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetSize(320, 30)
        row:SetPoint("TOPLEFT", 5, -yOffset)
        
        -- Number label
        local numLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numLabel:SetPoint("LEFT", 0, 0)
        numLabel:SetText(i .. ".")
        
        -- Friend name
        local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameLabel:SetPoint("LEFT", 20, 0)
        nameLabel:SetText(battleTag)
        
        -- Up button
        local upBtn = CreateFrame("Button", nil, row, "UIPanelScrollUpButtonTemplate")
        upBtn:SetSize(20, 20)
        upBtn:SetPoint("RIGHT", -125, 0)
        if i == 1 then
            upBtn:Disable()
        else
            upBtn:SetScript("OnClick", function()
                -- Swap with previous
                GuildInviteRequestDB.preferredFriends[i], GuildInviteRequestDB.preferredFriends[i-1] = 
                    GuildInviteRequestDB.preferredFriends[i-1], GuildInviteRequestDB.preferredFriends[i]
                RefreshFriendList()
            end)
        end
        
        -- Down button
        local downBtn = CreateFrame("Button", nil, row, "UIPanelScrollDownButtonTemplate")
        downBtn:SetSize(20, 20)
        downBtn:SetPoint("RIGHT", -100, 0)
        if i == #GuildInviteRequestDB.preferredFriends then
            downBtn:Disable()
        else
            downBtn:SetScript("OnClick", function()
                -- Swap with next
                GuildInviteRequestDB.preferredFriends[i], GuildInviteRequestDB.preferredFriends[i+1] = 
                    GuildInviteRequestDB.preferredFriends[i+1], GuildInviteRequestDB.preferredFriends[i]
                RefreshFriendList()
            end)
        end
        
        -- Remove button
        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(60, 22)
        removeBtn:SetPoint("RIGHT", 0, 0)
        removeBtn:SetText("Remove")
        removeBtn:SetScript("OnClick", function()
            table.remove(GuildInviteRequestDB.preferredFriends, i)
            RefreshFriendList()
        end)
        
        yOffset = yOffset + 35
    end
    
    scrollChild:SetHeight(math.max(yOffset, 1))
end

-- Add friend section
local addLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
addLabel:SetPoint("BOTTOM", 0, 155)
addLabel:SetText("Add BattleTag:")

local addBox = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
addBox:SetPoint("BOTTOMLEFT", 20, 130)
addBox:SetPoint("BOTTOMRIGHT", -20, 130)
addBox:SetHeight(20)
addBox:SetAutoFocus(false)

-- Message section
local messageLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
messageLabel:SetPoint("BOTTOM", 0, 105)
messageLabel:SetText("Invite Message:")

local messageBox = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
messageBox:SetPoint("BOTTOMLEFT", 20, 80)
messageBox:SetPoint("BOTTOMRIGHT", -20, 80)
messageBox:SetHeight(20)
messageBox:SetAutoFocus(false)
messageBox:SetText(GuildInviteRequestDB.message)
messageBox:SetScript("OnEnterPressed", function(self)
    GuildInviteRequestDB.message = self:GetText()
    self:ClearFocus()
    print("|cff00ff00[" .. addonName .. "]|r Message updated to: " .. GuildInviteRequestDB.message)
end)
messageBox:SetScript("OnEscapePressed", function(self)
    self:SetText(GuildInviteRequestDB.message)
    self:ClearFocus()
end)

-- Fallback guild section
local guildLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
guildLabel:SetPoint("BOTTOM", 0, 55)
guildLabel:SetText("Fallback Guild Name:")

local guildBox = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
guildBox:SetPoint("BOTTOMLEFT", 20, 30)
guildBox:SetPoint("BOTTOMRIGHT", -20, 30)
guildBox:SetHeight(20)
guildBox:SetAutoFocus(false)
guildBox:SetText(GuildInviteRequestDB.fallbackGuild)
guildBox:SetScript("OnEnterPressed", function(self)
    GuildInviteRequestDB.fallbackGuild = self:GetText()
    self:ClearFocus()
    print("|cff00ff00[" .. addonName .. "]|r Fallback guild set to: " .. GuildInviteRequestDB.fallbackGuild)
end)
guildBox:SetScript("OnEscapePressed", function(self)
    self:SetText(GuildInviteRequestDB.fallbackGuild)
    self:ClearFocus()
end)

-- Bottom buttons (centered)
local addBtn = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
addBtn:SetSize(80, 22)
addBtn:SetPoint("BOTTOM", -45, 8)
addBtn:SetText("Add")
addBtn:SetScript("OnClick", function()
    local text = addBox:GetText()
    if text and text ~= "" then
        table.insert(GuildInviteRequestDB.preferredFriends, text)
        addBox:SetText("")
        RefreshFriendList()
    end
end)

local closeBtn = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
closeBtn:SetSize(80, 22)
closeBtn:SetPoint("BOTTOM", 45, 8)
closeBtn:SetText("Close")
closeBtn:SetScript("OnClick", function()
    configFrame:Hide()
end)

-- Function to show config
local function ShowConfig()
    RefreshFriendList()
    configFrame:Show()
end

-- Slash command to manually trigger, reset, or list BNet friends
SLASH_GUILDINVITEREQUEST1 = "/gir"
SlashCmdList["GUILDINVITEREQUEST"] = function(msg)
    if msg == "reset" then
        GuildInviteRequestDB.requested = false
        hasChecked = false
        print("|cff00ff00[" .. addonName .. "]|r Request status reset. Relog to trigger again.")
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
        print("|cff00ff00[" .. addonName .. "]|r Version 0.9")
    else
        print("|cff00ff00[" .. addonName .. "]|r Commands:")
        print("  /gir config - Open settings GUI")
        print("  /gir check - Manually check and request guild invite")
        print("  /gir reset - Reset request status")
        print("  /gir list - List all Battle.net friends")
        print("  /gir ver - Show addon version")
    end
end

print("|cff00ff00[" .. addonName .. "]|r Loaded. Use /gir config to manage preferred friends.")
