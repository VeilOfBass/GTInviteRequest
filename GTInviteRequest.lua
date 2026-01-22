local addonName = "GTInviteRequest"
local hasChecked = false
local checkDelay = 5 -- seconds to wait after login before checking

-- LIST YOUR PREFERRED BATTLE.NET FRIENDS HERE (in order of preference)
-- Use their BattleTag (e.g., "FriendName#1234") or their Battle.net display name
local preferredBNetFriends = {
    "Ephrick#1517",
	"VeilOfBass#1159",
    "Ranger#1237",
    "Viperish#1350",
    -- Add more BattleTags as needed
}

-- Fallback guild to search if no BNet friends are online
local fallbackGuildName = "Glamour Toads"

-- Saved variable to track if we've already requested (persists between sessions)
GuildInviteRequestDB = GuildInviteRequestDB or { requested = false }

local frame = CreateFrame("Frame")

-- Function to find an online BNet friend playing WoW
local function FindOnlineBNetFriend()
    local numBNetTotal, numBNetOnline = BNGetNumFriends()
    
    for _, preferredFriend in ipairs(preferredBNetFriends) do
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
            local message = "Hey! Could I get a guild invite please? Thanks!"
            
            -- Send Battle.net whisper
            BNSendWhisper(bnetID, message)
            
            -- Mark as requested
            GuildInviteRequestDB.requested = true
            
            print("|cff00ff00[" .. addonName .. "]|r Guild invite requested from " .. battleTag .. " via Battle.net")
        else
            -- No BNet friends online, try /who for the fallback guild
            print("|cff00ff00[" .. addonName .. "]|r No Battle.net friends online, searching for '" .. fallbackGuildName .. "' members...")
            C_Timer.After(1, function()
                C_FriendList.SendWho("g-\"" .. fallbackGuildName .. "\"")
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
        -- Process /who results
        if GuildInviteRequestDB.requested then return end
        
        local numWho = C_FriendList.GetNumWhoResults()
        if numWho > 0 then
            local whoInfo = C_FriendList.GetWhoInfo(1)
            if whoInfo and whoInfo.fullName then
                local message = "Hey! Could I get a guild invite please? Thanks!"
                SendChatMessage(message, "WHISPER", nil, whoInfo.fullName)
                GuildInviteRequestDB.requested = true
                print("|cff00ff00[" .. addonName .. "]|r Guild invite requested from " .. whoInfo.fullName .. " (from " .. fallbackGuildName .. ")")
            end
        else
            print("|cffff0000[" .. addonName .. "]|r No members of '" .. fallbackGuildName .. "' found online.")
        end
    end
end)

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
    elseif msg == "ver" or msg == "version" then
        print("|cff00ff00[" .. addonName .. "]|r Version 0.3")
    else
        print("|cff00ff00[" .. addonName .. "]|r Commands:")
        print("  /gir check - Manually check and request guild invite")
        print("  /gir reset - Reset request status")
        print("  /gir list - List all Battle.net friends")
        print("  /gir ver - Show addon version")
    end
end

print("|cff00ff00[" .. addonName .. "]|r Loaded. Use /gir for commands.")