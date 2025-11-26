if not game:IsLoaded() then
    game.Loaded:Wait()
end
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")

local lp = Players.LocalPlayer
local playerGui = lp:WaitForChild("PlayerGui")

print("Loading Nile's Anti Chat and Voice Logger..")

if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    local startTime = tick()
    task.wait(0.21)
    local function showNotification(title, description, imageId)
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = title;
                Text = description;
                Icon = imageId;
                Duration = 15;
            })
        end)
    end

    if _G.VadriftsACLLoaded then
        showNotification("Nile's ACL", "Anti Chat and Voice Logger already loaded!", "rbxassetid://2541869220")
        print("Anti Chat and Voice Logger already loaded!")
        return
    end
    _G.VadriftsACLLoaded = true

    showNotification("Nile's ACL", string.format("Anti Chat and Voice Logger Loaded in %.2fs!", tick() - startTime), "rbxassetid://2541869220")
    print(string.format("Anti Chat and Voice Logger successfully loaded in %.2f seconds!", tick() - startTime))

    if setfflag then
        pcall(function()
            setfflag("AbuseReportScreenshot", "False")
            setfflag("AbuseReportScreenshotPercentage", "0")
            
            setfflag("GetFFlagVoiceAbuseReportsEnabled", "False")
            setfflag("FFlagVoiceAbuseReportsEnabledV3", "False")
            setfflag("VoiceAbuseReportsEnabled", "False")
            
            setfflag("DFFlagVoiceChatRecordRoomMetricsFromRCC3", "False")
            setfflag("FFlagVoiceRecordingIndicatorsEnabled", "False")
            
            setfflag("DFIntVoiceChatCallEndTelemetryHundredthsPercentage", "0")
            setfflag("DFFlagVoiceReliabilityTelemetryEventIngest", "False")
            setfflag("FFlagVoiceChatEnableEndpointErrorLogging", "False")
            setfflag("DFFlagVoiceChatSendHttpErrorsTelemetry", "False")
            setfflag("DFFlagVoiceChatSendHttpErrorsTelemetry2", "False")
            
            setfflag("DFFlagChatLineAbuseReportAPIEnabled2", "False")
            setfflag("FFlagEnableChatLineReporting2", "False")
            setfflag("FFlagChatLineReportingMessageIdEnabled", "False")
            
            setfflag("DFIntAbuseReportV2Percentage", "0")
            setfflag("FFlagEnableAbuseReportRevampFlow_1", "False")
            setfflag("FFlagReportAnythingAnnotationIXP", "False")
        end)
    end

local channel
local isPlayingEmote = false
local useTextMethod = false
local hasCharacterWithHumanoid = false

_G.VadriftsACLConnections = _G.VadriftsACLConnections or {}
_G.VadriftsACLChatHooked = _G.VadriftsACLChatHooked or false

local function trackConnection(conn)
    if conn then
        table.insert(_G.VadriftsACLConnections, conn)
    end
end

local function disconnectAll()
    for i = #_G.VadriftsACLConnections, 1, -1 do
        local c = _G.VadriftsACLConnections[i]
        if typeof(c) == "RBXScriptConnection" then
            pcall(function() c:Disconnect() end)
        end
        table.remove(_G.VadriftsACLConnections, i)
    end
    _G.VadriftsACLChatHooked = false
end

local function getTextChannel()
    local tcs = TextChatService
    if not tcs then return nil end
    local channels = tcs:FindFirstChild("TextChannels")
    if not channels then return nil end

    local prefer = channels:FindFirstChild("RBXGeneral")
    if prefer then return prefer end

    for _, ch in ipairs(channels:GetChildren()) do
        if ch:IsA("TextChannel") then
            return ch
        end
    end
    return nil
end

local function checkCharacterType()
    local char = lp.Character
    hasCharacterWithHumanoid = false
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local animate = char:FindFirstChild("Animate")
    if hum and animate then
        hasCharacterWithHumanoid = true
    end
end

local function getIdleAnimationIdFromAnimate(animate)
    if not animate then return nil end
    local idle = animate:FindFirstChild("idle")
    if not idle then return nil end
    local a1 = idle:FindFirstChild("Animation1")
    if a1 and a1:IsA("Animation") and a1.AnimationId ~= "" then
        return a1.AnimationId
    end
    local a2 = idle:FindFirstChild("Animation2")
    if a2 and a2:IsA("Animation") and a2.AnimationId ~= "" then
        return a2.AnimationId
    end
    return nil
end

local function getIdleAnimationId()
    local char = lp.Character
    if not char then return nil end
    return getIdleAnimationIdFromAnimate(char:FindFirstChild("Animate"))
end

local DEFAULT_ANIM_FOLDERS = {
    idle = true, walk = true, run = true, jump = true, fall = true,
    climb = true, sit = true, swimidle = true, swim = true
}

local function isEmoteAnimation(animationTrack)
    local char = lp.Character
    if not char then return false end
    if not animationTrack then return false end

    local animate = char:FindFirstChild("Animate")
    if not animate then return false end

    local ok, anim = pcall(function() return animationTrack.Animation end)
    if not ok or not anim or not anim:IsA("Animation") then
        return false
    end

    local animId = anim.AnimationId
    if not animId or animId == "" then
        return false
    end

    for folderName in pairs(DEFAULT_ANIM_FOLDERS) do
        local folder = animate:FindFirstChild(folderName)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Animation") and child.AnimationId == animId then
                    return false
                end
            end
        end
    end

    local toolFolder = animate:FindFirstChild("toolnone")
    if toolFolder then
        for _, child in ipairs(toolFolder:GetChildren()) do
            if child:IsA("Animation") and child.AnimationId == animId then
                return false
            end
        end
    end

    return true
end

local function bindCheerToIdle(character)
    local animate = character:FindFirstChild("Animate")
    if not animate then return end

    local function apply()
        local cheer = animate:FindFirstChild("cheer")
        local cheerAnim = cheer and cheer:FindFirstChild("CheerAnim")
        local idleId = getIdleAnimationIdFromAnimate(animate)
        if cheerAnim and cheerAnim:IsA("Animation") and idleId and cheerAnim.AnimationId ~= idleId then
            cheerAnim.AnimationId = idleId
        end
    end

    apply()

    local function hookAnim(anim)
        if anim and anim:IsA("Animation") then
            trackConnection(anim:GetPropertyChangedSignal("AnimationId"):Connect(apply))
        end
    end

    local function hookIdleChildren()
        local idle = animate:FindFirstChild("idle")
        if not idle then return end
        hookAnim(idle:FindFirstChild("Animation1"))
        hookAnim(idle:FindFirstChild("Animation2"))
    end

    hookIdleChildren()

    trackConnection(animate.ChildAdded:Connect(function(child)
        if child.Name == "idle" or child.Name == "cheer" then
            hookIdleChildren()
            apply()
        end
    end))

    trackConnection(animate.DescendantAdded:Connect(function(desc)
        if desc:IsA("Animation") and (desc.Name == "Animation1" or desc.Name == "Animation2" or desc.Name == "CheerAnim") then
            if desc.Name ~= "CheerAnim" then
                hookAnim(desc)
            end
            apply()
        end
    end))

    trackConnection(animate.DescendantRemoving:Connect(function(desc)
        if desc:IsA("Animation") and (desc.Name == "Animation1" or desc.Name == "Animation2" or desc.Name == "CheerAnim") then
            task.defer(apply)
        end
    end))
end

local function setupEmoteDetection(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    trackConnection(humanoid.AnimationPlayed:Connect(function(animationTrack)
        if isEmoteAnimation(animationTrack) then
            isPlayingEmote = true
            useTextMethod = true

            trackConnection(animationTrack.Stopped:Connect(function()
                isPlayingEmote = false
                useTextMethod = false
            end))
        end
    end))
end

local invisibleChars = {
    "ּ",
    "​",
    "‌",
    "‍",
    "⠀",
    "ׁ",
    "ׂ",
    "֑",
    "᠎",
    "⁠",
}

local function AntiChatLog(message)
    if not message or message == "" then return message end
    if message:sub(1, 1) == "/" then
        return message
    else
        local prefix = ""
        local count = math.random(1, 3)
        for i = 1, count do
            prefix = prefix .. invisibleChars[math.random(1, #invisibleChars)]
        end
        return prefix .. message
    end
end

local function createSpoofedMessage(originalMessage)
    local variance = math.random(50, 150) / 1000
    task.wait(variance)
    return AntiChatLog(originalMessage)
end

local function disableVoiceChatLogging()
    pcall(function()
        local VoiceChatService = game:GetService("VoiceChatService")
        if VoiceChatService then
            for _, connection in pairs(getconnections and getconnections(VoiceChatService.PlayerMicActivitySignalChange) or {}) do
                pcall(function() connection:Disable() end)
            end
        end
    end)
end

local function blockTelemetryRequests()
    if hookfunction and typeof(hookfunction) == "function" then
        pcall(function()
            local oldHttpRequest = (syn and syn.request) or (http and http.request) or (request) or (http_request)
            if oldHttpRequest then
                local blockedPatterns = {
                    "voice",
                    "telemetry",
                    "analytics",
                    "abuse",
                    "report",
                    "moderation",
                    "logging"
                }
                
                local newRequest = function(options)
                    if options and options.Url then
                        local urlLower = options.Url:lower()
                        for _, pattern in ipairs(blockedPatterns) do
                            if urlLower:find(pattern) then
                                return {StatusCode = 200, Body = "{}"}
                            end
                        end
                    end
                    return oldHttpRequest(options)
                end
                
                if syn and syn.request then
                    hookfunction(syn.request, newRequest)
                elseif request then
                    hookfunction(request, newRequest)
                end
            end
        end)
    end
end

local function blockLogServiceMessages()
    pcall(function()
        local LogService = game:GetService("LogService")
        if LogService and getconnections then
            for _, connection in pairs(getconnections(LogService.MessageOut)) do
                local info = getinfo and getinfo(connection.Function)
                if info then
                    pcall(function() connection:Disable() end)
                end
            end
        end
    end)
end

local function clearChatHistory()
    pcall(function()
        local TextChatService = game:GetService("TextChatService")
        if TextChatService then
            for _, channel in pairs(TextChatService:GetDescendants()) do
                if channel:IsA("TextChannel") then
                    pcall(function()
                        if channel:FindFirstChild("MessageHistory") then
                            channel.MessageHistory:ClearAllChildren()
                        end
                    end)
                end
            end
        end
    end)
end

local function spoofVoiceState()
    pcall(function()
        local VoiceChatService = game:GetService("VoiceChatService")
        if VoiceChatService and VoiceChatService.IsVoiceEnabledForUserIdAsync then
            local oldIsVoiceEnabled = VoiceChatService.IsVoiceEnabledForUserIdAsync
            if hookfunction then
                hookfunction(VoiceChatService.IsVoiceEnabledForUserIdAsync, function(self, userId)
                    if userId == lp.UserId then
                        return false
                    end
                    return oldIsVoiceEnabled(self, userId)
                end)
            end
        end
    end)
end

task.spawn(function()
    disableVoiceChatLogging()
    blockTelemetryRequests()
    blockLogServiceMessages()
    spoofVoiceState()
    
    task.spawn(function()
        while _G.VadriftsACLLoaded do
            clearChatHistory()
            task.wait(30)
        end
    end)
end)

local function findChatBar()
    local chat = playerGui:FindFirstChild("Chat")
    if chat then
        local found = chat:FindFirstChild("ChatBar", true)
        if found and found:IsA("TextBox") then
            return found
        end
    end
    local container = CoreGui:FindFirstChild("TextBoxContainer", true)
    if container then
        local tb = container:FindFirstChild("TextBox") or container
        if tb and tb:IsA("TextBox") then
            return tb
        end
    end
    return nil
end

local function setupChatHook()
    if _G.VadriftsACLChatHooked then return end

    channel = channel or getTextChannel()
    if not channel then
        warn("[ACL] No TextChannel found.")
    end

    local chatBar = findChatBar()
    if not chatBar then
        warn("[ACL] Could not find chat bar.")
        return
    end


    local function onSubmit(enterPressed)
        if not enterPressed then return end
        local msg = chatBar.Text

        if useTextMethod and msg and msg ~= "" then
            channel = channel or getTextChannel()
            if channel then
                chatBar.Text = ""
                local modified = AntiChatLog(msg)
                channel:SendAsync(modified)
            else
                warn("[ACL] No TextChannel available; leaving message to default chat pipeline.")
            end
        end
    end

    trackConnection(chatBar.FocusLost:Connect(onSubmit))
    _G.VadriftsACLChatHooked = true
end

lp.CharacterAdded:Connect(function(character)
    disconnectAll()
    channel = getTextChannel()

    checkCharacterType()
    isPlayingEmote = false
    useTextMethod = false

    setupEmoteDetection(character)
    bindCheerToIdle(character)
    setupChatHook()
end)

lp.CharacterRemoving:Connect(function()
    disconnectAll()
    isPlayingEmote = false
    useTextMethod = false
    hasCharacterWithHumanoid = false
end)

checkCharacterType()
channel = getTextChannel()
if lp.Character then
    setupEmoteDetection(lp.Character)
    bindCheerToIdle(lp.Character)
end
setupChatHook()

    task.spawn(function()
        local emoteErr = '<font color="#f74b52">You can\'t use Emotes here.</font>'
        local function onDescendantAdded(obj)
            if not _G.VadriftsACLLoaded then return end
            if obj:IsA("TextLabel") and obj.Text == emoteErr then
                if hasCharacterWithHumanoid and not useTextMethod then
                    local msg = obj:FindFirstAncestor("TextMessage")
                    if msg then
                        msg:Destroy()
                    end
                end
            end
        end

        for _, obj in ipairs(CoreGui:GetDescendants()) do
            onDescendantAdded(obj)
        end
        CoreGui.DescendantAdded:Connect(onDescendantAdded)
    end)
else
    if not pcall(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/vqmpjayZ/More-Scripts/main/Anthony's%20ACL"))()
    end) then
        loadstring(game:HttpGet("https://raw.githubusercontent.com/vqmpjayZ/More-Scripts/main/Anthony's%20ACL"))()
    end
    print("Anti Chat and Voice Logger Loaded!")
end

task.spawn(function()
    repeat
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
        task.wait()
    until StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat)
end)