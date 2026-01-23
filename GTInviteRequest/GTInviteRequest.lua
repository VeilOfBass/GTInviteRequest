local addonName = "GTInviteRequest"
local addonVersion = "dev"

if C_AddOns and C_AddOns.GetAddOnMetadata then
    addonVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or addonVersion
end
local hasChecked = false
local checkDelay = 5 -- seconds to wait after login before checking
local waitingForWhoResults = false -- Flag to track if we're expecting /who results

local frame = CreateFrame("Frame")

-- Saved variables (persists between sessions)
GuildInviteRequestDB = GuildInviteRequestDB or {
    requested = false,
    preferredFriends = {}, -- Stored as BattleTags
    fallbackGuild = "",
    message = "Hey! Could I get a guild invite please? Thanks!",
    uiScale = 1.0,
    fontFace = "Fonts\\FRIZQT__.TTF" -- Default WoW font
}

-- Function to apply custom font to a font string
local function ApplyCustomFont(fontString)
    if fontString and fontString.SetFont then
        fontString:SetFont(GuildInviteRequestDB.fontFace, 12)
    end
end

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
            if GuildInviteRequestDB.fallbackGuild ~= "" then
                print("|cff00ff00[" .. addonName .. "]|r No Battle.net friends online, searching for '" .. GuildInviteRequestDB.fallbackGuild .. "' members...")
                waitingForWhoResults = true
                C_Timer.After(1, function()
                    C_FriendList.SendWho("g-\"" .. GuildInviteRequestDB.fallbackGuild .. "\"")
                end)
            else
                print("|cffff0000[" .. addonName .. "]|r No Battle.net friends online and no fallback guild configured.")
            end
        end
    elseif guildName then
        print("|cff00ff00[" .. addonName .. "]|r You're already in a guild: " .. guildName)
        GuildInviteRequestDB.requested = false -- Reset for future use
    elseif GuildInviteRequestDB.requested then
        print("|cff00ff00[" .. addonName .. "]|r Guild invite already requested. Use '/gir rt' to retry.")
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
configFrame:SetSize(450, 500)
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

-- Apply UI scale
configFrame:SetScale(GuildInviteRequestDB.uiScale)

-- Create tab buttons
local tabButtons = {}
local currentTab = 1

local function CreateTabButton(index, text, xOffset)
    local btn = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    btn:SetSize(95, 25)
    btn:SetPoint("TOPLEFT", 15 + xOffset, -35)
    btn:SetText(text)
    btn.tabIndex = index
    return btn
end

tabButtons[1] = CreateTabButton(1, "Friends", 0)
tabButtons[2] = CreateTabButton(2, "Guild", 100)
tabButtons[3] = CreateTabButton(3, "Message", 200)
tabButtons[4] = CreateTabButton(4, "Settings", 300)

-- Create content frames for each tab
local friendsFrame = CreateFrame("Frame", nil, configFrame)
friendsFrame:SetPoint("TOPLEFT", 15, -65)
friendsFrame:SetPoint("BOTTOMRIGHT", -15, 15)
friendsFrame:Hide()

local guildFrame = CreateFrame("Frame", nil, configFrame)
guildFrame:SetPoint("TOPLEFT", 15, -65)
guildFrame:SetPoint("BOTTOMRIGHT", -15, 15)
guildFrame:Hide()

local messageFrame = CreateFrame("Frame", nil, configFrame)
messageFrame:SetPoint("TOPLEFT", 15, -65)
messageFrame:SetPoint("BOTTOMRIGHT", -15, 15)
messageFrame:Hide()

local settingsFrame = CreateFrame("Frame", nil, configFrame)
settingsFrame:SetPoint("TOPLEFT", 15, -65)
settingsFrame:SetPoint("BOTTOMRIGHT", -15, 15)
settingsFrame:Hide()

local tabFrames = {friendsFrame, guildFrame, messageFrame, settingsFrame}

-- Store all font strings to update
local allFontStrings = {}

-- Tab switching function
local function ShowTab(index)
    currentTab = index
    for i, frame in ipairs(tabFrames) do
        frame:Hide()
    end
    tabFrames[index]:Show()
    
    -- Update button states
    for i, btn in ipairs(tabButtons) do
        if i == index then
            btn:Disable()
        else
            btn:Enable()
        end
    end
end

-- Set up tab button clicks
for i, btn in ipairs(tabButtons) do
    btn:SetScript("OnClick", function()
        ShowTab(btn.tabIndex)
    end)
end

-- FRIENDS TAB CONTENT
local friendsInstructions = friendsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
friendsInstructions:SetPoint("TOPLEFT", 5, -5)
friendsInstructions:SetText("Add Battle.net friends (in order of preference):")
table.insert(allFontStrings, friendsInstructions)

-- Scroll frame for friend list
local scrollFrame = CreateFrame("ScrollFrame", nil, friendsFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 5, -30)
scrollFrame:SetPoint("BOTTOMRIGHT", -25, 55)

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
        row:SetSize(360, 30)
        row:SetPoint("TOPLEFT", 5, -yOffset)
        
        -- Number label
        local numLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numLabel:SetPoint("LEFT", 0, 0)
        numLabel:SetText(i .. ".")
        ApplyCustomFont(numLabel)
        
        -- Friend name
        local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameLabel:SetPoint("LEFT", 20, 0)
        nameLabel:SetText(battleTag)
        ApplyCustomFont(nameLabel)
        
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
local addFriendLabel = friendsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
addFriendLabel:SetPoint("BOTTOMLEFT", 5, 30)
addFriendLabel:SetText("Add BattleTag:")
table.insert(allFontStrings, addFriendLabel)

local addFriendBox = CreateFrame("EditBox", nil, friendsFrame, "InputBoxTemplate")
addFriendBox:SetPoint("BOTTOMLEFT", 5, 5)
addFriendBox:SetPoint("BOTTOMRIGHT", -90, 5)
addFriendBox:SetHeight(20)
addFriendBox:SetAutoFocus(false)

local addFriendBtn = CreateFrame("Button", nil, friendsFrame, "UIPanelButtonTemplate")
addFriendBtn:SetSize(80, 22)
addFriendBtn:SetPoint("BOTTOMRIGHT", -5, 5)
addFriendBtn:SetText("Add")
addFriendBtn:SetScript("OnClick", function()
    local text = addFriendBox:GetText()
    if text and text ~= "" then
        table.insert(GuildInviteRequestDB.preferredFriends, text)
        addFriendBox:SetText("")
        RefreshFriendList()
    end
end)

-- GUILD TAB CONTENT
local guildInstructions = guildFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
guildInstructions:SetPoint("TOP", 0, -20)
guildInstructions:SetText("Fallback Guild Name:")
table.insert(allFontStrings, guildInstructions)

local guildSubtext = guildFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
guildSubtext:SetPoint("TOP", 0, -40)
guildSubtext:SetText("If no Battle.net friends are online, the addon will\nsearch for members of this guild to whisper.")
table.insert(allFontStrings, guildSubtext)

local guildBox = CreateFrame("EditBox", nil, guildFrame, "InputBoxTemplate")
guildBox:SetPoint("TOP", 0, -80)
guildBox:SetSize(300, 20)
guildBox:SetAutoFocus(false)
guildBox:SetScript("OnEnterPressed", function(self)
    GuildInviteRequestDB.fallbackGuild = self:GetText()
    self:ClearFocus()
    print("|cff00ff00[" .. addonName .. "]|r Fallback guild set to: " .. GuildInviteRequestDB.fallbackGuild)
end)
guildBox:SetScript("OnEscapePressed", function(self)
    self:SetText(GuildInviteRequestDB.fallbackGuild)
    self:ClearFocus()
end)

-- MESSAGE TAB CONTENT
local messageInstructions = messageFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
messageInstructions:SetPoint("TOP", 0, -20)
messageInstructions:SetText("Customize Your Invite Message:")
table.insert(allFontStrings, messageInstructions)

local messageSubtext = messageFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
messageSubtext:SetPoint("TOP", 0, -40)
messageSubtext:SetText("This message will be sent when requesting a guild invite.\nPress Enter to save, Escape to cancel.")
table.insert(allFontStrings, messageSubtext)

local messageBox = CreateFrame("EditBox", nil, messageFrame, "InputBoxTemplate")
messageBox:SetPoint("TOP", 0, -80)
messageBox:SetSize(380, 20)
messageBox:SetAutoFocus(false)
messageBox:SetScript("OnEnterPressed", function(self)
    GuildInviteRequestDB.message = self:GetText()
    self:ClearFocus()
    print("|cff00ff00[" .. addonName .. "]|r Message updated to: " .. GuildInviteRequestDB.message)
end)
messageBox:SetScript("OnEscapePressed", function(self)
    self:SetText(GuildInviteRequestDB.message)
    self:ClearFocus()
end)

-- SETTINGS TAB CONTENT
local settingsInstructions = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
settingsInstructions:SetPoint("TOP", 0, -20)
settingsInstructions:SetText("Addon Settings:")
table.insert(allFontStrings, settingsInstructions)

-- UI Scale
local uiScaleLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
uiScaleLabel:SetPoint("TOPLEFT", 20, -60)
uiScaleLabel:SetText("UI Scale:")
table.insert(allFontStrings, uiScaleLabel)

local uiScaleSlider = CreateFrame("Slider", nil, settingsFrame, "OptionsSliderTemplate")
uiScaleSlider:SetPoint("TOPLEFT", 20, -85)
uiScaleSlider:SetMinMaxValues(0.5, 1.5)
uiScaleSlider:SetValue(GuildInviteRequestDB.uiScale)
uiScaleSlider:SetValueStep(0.05)
uiScaleSlider:SetObeyStepOnDrag(true)
uiScaleSlider.Low:SetText("50%")
uiScaleSlider.High:SetText("150%")
uiScaleSlider.Text:SetText("Scale: " .. math.floor(GuildInviteRequestDB.uiScale * 100) .. "%")
uiScaleSlider:SetScript("OnValueChanged", function(self, value)
    GuildInviteRequestDB.uiScale = value
    self.Text:SetText("Scale: " .. math.floor(value * 100) .. "%")
    configFrame:SetScale(value)
end)

-- Font Face
local fontFaceLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fontFaceLabel:SetPoint("TOPLEFT", 20, -140)
fontFaceLabel:SetText("Font Face:")
table.insert(allFontStrings, fontFaceLabel)

local fontDropdown = CreateFrame("Frame", "GTIRFontDropdown", settingsFrame, "UIDropDownMenuTemplate")
fontDropdown:SetPoint("TOPLEFT", 0, -155)

local fontOptions = {
    {text = "Friz Quadrata (Default)", value = "Fonts\\FRIZQT__.TTF"},
    {text = "Arial", value = "Fonts\\ARIALN.TTF"},
    {text = "Skurri", value = "Fonts\\skurri.ttf"},
    {text = "Morpheus", value = "Fonts\\MORPHEUS.TTF"}
}

local function GetFontName(path)
    for _, option in ipairs(fontOptions) do
        if option.value == path then
            return option.text
        end
    end
    return "Friz Quadrata (Default)"
end

UIDropDownMenu_Initialize(fontDropdown, function(self, level)
    for _, option in ipairs(fontOptions) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = option.text
        info.value = option.value
        info.func = function()
            GuildInviteRequestDB.fontFace = option.value
            UIDropDownMenu_SetText(fontDropdown, option.text)
            -- Apply new font face to all font strings
            for _, fs in ipairs(allFontStrings) do
                ApplyCustomFont(fs)
            end
            RefreshFriendList() -- Refresh to apply to friend list items
        end
        UIDropDownMenu_AddButton(info)
    end
end)

UIDropDownMenu_SetText(fontDropdown, GetFontName(GuildInviteRequestDB.fontFace))

-- Function to show config
local function ShowConfig()
    -- Load saved values into text boxes
    guildBox:SetText(GuildInviteRequestDB.fallbackGuild)
    messageBox:SetText(GuildInviteRequestDB.message)
    
    -- Apply saved fonts when opening config
    for _, fs in ipairs(allFontStrings) do
        ApplyCustomFont(fs)
    end
    RefreshFriendList()
    ShowTab(1) -- Always start on Friends tab
    configFrame:Show()
end

-- Slash command to manually trigger, reset, or list BNet friends
SLASH_GUILDINVITEREQUEST1 = "/gir"
SlashCmdList["GUILDINVITEREQUEST"] = function(msg)
    if msg == "reset" then
        -- Reset to default values
        GuildInviteRequestDB.requested = false
        GuildInviteRequestDB.preferredFriends = {}
        GuildInviteRequestDB.fallbackGuild = ""
        GuildInviteRequestDB.message = "Hey! Could I get a guild invite please? Thanks!"
        GuildInviteRequestDB.uiScale = 1.0
        GuildInviteRequestDB.fontFace = "Fonts\\FRIZQT__.TTF"
        hasChecked = false
        
        -- Update UI if config is open
        if configFrame:IsShown() then
            uiScaleSlider:SetValue(1.0)
            configFrame:SetScale(1.0)
            UIDropDownMenu_SetText(fontDropdown, "Friz Quadrata (Default)")
            guildBox:SetText("")
            messageBox:SetText("Hey! Could I get a guild invite please? Thanks!")
            for _, fs in ipairs(allFontStrings) do
                ApplyCustomFont(fs)
            end
            RefreshFriendList()
        end
        
        print("|cff00ff00[" .. addonName .. "]|r Configuration reset to defaults.")
    elseif msg == "check" then
        hasChecked = false
        GuildInviteRequestDB.requested = false
        CheckGuildStatus()
    elseif msg == "rt" or msg == "retry" then
        -- Reset the requested flag and retry
        GuildInviteRequestDB.requested = false
        hasChecked = false
        print("|cff00ff00[" .. addonName .. "]|r Retrying guild invite request...")
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
        print("  /gir rt - Retry requesting guild invite")
        print("  /gir reset - Reset all settings to defaults")
        print("  /gir list - List all Battle.net friends")
        print("  /gir ver - Show addon version")
    end
end
