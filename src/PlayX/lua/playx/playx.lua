-- PlayX
-- Copyright (c) 2009 sk89q <http://www.sk89q.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 2 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 
-- $Id$

require("datastream")

-- FCVAR_GAMEDLL makes cvar change detection work
CreateConVar("playx_jw_url", "http://playx.googlecode.com/svn/jwplayer/player.swf",
             {FCVAR_ARCHIVE, FCVAR_GAMEDLL})
CreateConVar("playx_host_url", "http://sk89q.github.com/playx/host/host.html",
             {FCVAR_ARCHIVE, FCVAR_GAMEDLL})
CreateConVar("playx_jw_youtube", "1", {FCVAR_ARCHIVE})
CreateConVar("playx_admin_timeout", "120", {FCVAR_ARCHIVE})
CreateConVar("playx_expire", "-1", {FCVAR_ARCHIVE})
CreateConVar("playx_race_protection", "1", {FCVAR_ARCHIVE})

-- Note: Not using cvar replication because this can start causing problems
-- if the server has been left online for a while.

PlayX = {}

include("playx/functions.lua")
include("playx/providers.lua")

PlayX.CurrentMedia = nil
PlayX.AdminTimeoutTimerRunning = false
PlayX.LastOpenTime = 0

local _version = ""

--- Checks if a player instance exists in the game.
-- @return Whether a player exists
function PlayX.PlayerExists()
    return table.Count(ents.FindByClass("gmod_playx")) > 0
end

--- Gets the player instance entity
-- @return Entity or nil
function PlayX.GetInstance()
    local props = ents.FindByClass("gmod_playx")
    return props[1]
end

--- Checks whether the JW player is enabled.
-- @return Whether the JW player is enabled
function PlayX.IsUsingJW()
    return GetConVar("playx_jw_url"):GetString():Trim():gmatch("^https?://.+") and true or false
end

--- Gets the URL of the JW player.
-- @return
function PlayX.GetJWURL()
    return GetConVar("playx_jw_url"):GetString():Trim()
end

--- Returns whether the JW player supports YouTube.
-- @return
function PlayX.JWPlayerSupportsYouTube()
    return GetConVar("playx_jw_youtube"):GetBool()
end

--- Gets the URL of the host file.
-- @return
function PlayX.GetHostURL()
    return GetConVar("playx_host_url"):GetString():Trim()
end

--- Checks whether the host URL is valid.
-- @return Whether the host URL is valid
function PlayX.HasValidHost()
    return PlayX.GetHostURL():Trim():gmatch("^https?://.+") and true or false
end

--- Returns whether a player is permitted to use the player.
-- @param ply Player
-- @return
function PlayX.IsPermitted(ply)
    if PlayXIsPermittedHandler then
        return PlayXIsPermittedHook(ply)
    else
        return ply:IsAdmin()
    end
end

--- Spawns the player at the location that a player is looking at. This
-- function will check whether there is already a player or not.
-- @param ply Player
-- @param model Model path
-- @return Success, and error message
function PlayX.SpawnForPlayer(ply, model)
    if PlayX.PlayerExists() then
        return false, "There is already a PlayX player somewhere on the map"
    end
    
    if not util.IsValidModel(model) then
        return false, "The server doesn't have the selected model"
    end
    
    local tr = ply.GetEyeTraceNoCursor and ply:GetEyeTraceNoCursor() or
        ply:GetEyeTrace()

	local ent = ents.Create("gmod_playx")
    ent:SetModel(model)
    
	local info = PlayXScreens[model:lower()]
    
	if not info or not info.IsProjector or 
	   not ((info.Up == 0 and info.Forward == 0) or
	        (info.Forward == 0 and info.Right == 0) or
	        (info.Right == 0 and info.Up == 0)) then
        ent:SetAngles(Angle(0, (ply:GetPos() - tr.HitPos):Angle().y, 0))
	    ent:SetPos(tr.HitPos - ent:OBBCenter() + 
	       ((ent:OBBMaxs().z - ent:OBBMins().z) + 10) * tr.HitNormal)
        ent:DropToFloor()
    else
        local ang = Angle(0, 0, 0)
        
        if info.Forward > 0 then
            ang = ang + Angle(180, 0, 180)
        elseif info.Forward < 0 then
            ang = ang + Angle(0, 0, 0)
        elseif info.Right > 0 then
            ang = ang + Angle(90, 0, 90)
        elseif info.Right < 0 then
            ang = ang + Angle(-90, 0, 90)
        elseif info.Up > 0 then
            ang = ang + Angle(-90, 0, 0)
        elseif info.Up < 0 then
            ang = ang + Angle(90, 0, 0)
        end
        
        local tryDist = math.min(ply:GetPos():Distance(tr.HitPos), 4000)
        local data = {}
        data.start = tr.HitPos + tr.HitNormal * (ent:OBBMaxs() - ent:OBBMins()):Length()
        data.endpos = tr.HitPos + tr.HitNormal * tryDist
        data.filter = player.GetAll()
        local dist = util.TraceLine(data).Fraction * tryDist - 
            (ent:OBBMaxs() - ent:OBBMins()):Length() / 2
        
        ent:SetAngles(ang + tr.HitNormal:Angle())
        ent:SetPos(tr.HitPos - ent:OBBCenter() + dist * tr.HitNormal)
    end
    
    ent:Spawn()
    ent:Activate()
    
    local phys = ent:GetPhysicsObject()
    if phys:IsValid() then
        phys:EnableMotion(false)
        phys:Sleep()
    end
    
    ply:AddCleanup("gmod_playx", ent)
    
    undo.Create("gmod_playx")
    undo.AddEntity(ent)
    undo.SetPlayer(ply)
    undo.Finish()
    
    return true
end
--- Stops playing.
function PlayX.CloseMedia()
    if PlayX.CurrentMedia then
        PlayX.EndMedia()
    end
end

--- Updates the current media metadata. This can be called even after the media
-- has begun playing. Calling this when there is no player spawned has
-- no effect or there is no media playing has no effect.
-- @param data Metadata structure
function PlayX.UpdateMetadata(data)
    if not PlayX.PlayerExists() or not PlayX.CurrentMedia then
        return
    end
    
    table.Merge(PlayX.CurrentMedia, data)
    PlayX:GetInstance():SetWireMetadata(PlayX.CurrentMedia)
    
    hook.Call("PlayXMetadataReceived", nil, {PlayX.CurrentMedia, data})
    
    -- Now handle the length
    if data.Length then
	    if GetConVar("playx_expire"):GetFloat() <= -1 then
	        timer.Stop("PlayXMediaExpire")
	        return
	    end
	    
	    length = length + GetConVar("playx_expire"):GetFloat() -- Pad length
	     
	    PlayX.CurrentMedia.StopTime = PlayX.CurrentMedia.StartTime + length
	    
	    local timeLeft = PlayX.CurrentMedia.StopTime - PlayX.CurrentMedia.StartTime
	    
	    print("PlayX: Length of current media set to " .. tostring(length) ..
	          " (grace 10 seconds), time left: " .. tostring(timeLeft) .. " seconds")
	    
	    if timeLeft > 0 then
	        timer.Adjust("PlayXMediaExpire", timeLeft, 1)
	        timer.Start("PlayXMediaExpire")
	    else -- Looks like it ended already!
	        print("PlayX: Media has already expired")
	        PlayX.EndMedia()
	    end
    end
end

--- Clears the current media information and inform clients of the change.
-- Unlike PlayX.CloseMedia(), this does not check if something is already
-- playing to begin with.
function PlayX.EndMedia()
    timer.Stop("PlayXMediaExpire")
    timer.Stop("PlayXAdminTimeout")
    
    PlayX.GetInstance():ClearWireOutputs()
    
    PlayX.CurrentMedia = nil
    PlayX.AdminTimeoutTimerRunning = false
    
    hook.Call("PlayXMediaEnded", nil, {})
    
    PlayX.SendEndUMsg()
end

--- Send the PlayXBegin datastream to clients. You should not have much of
-- a reason to call this method. We're using datastreams here because
-- some providers (cough. Livestream cough.) send a little too much data.
-- @param ply Pass a player to filter the message to just that player
function PlayX.SendBeginDStream(ply)
    local filter = nil
    
    if ply then
        filter = ply
    else
        filter = RecipientFilter()
        filter:AddAllPlayers()
    end
    
    datastream.StreamToClients(filter, "PlayXBegin", {
        ["Handler"] = PlayX.CurrentMedia.Handler,
        ["URI"] = PlayX.CurrentMedia.URI,
        ["PlayAge"] = CurTime() - PlayX.CurrentMedia.StartTime,
        ["ResumeSupported"] = PlayX.CurrentMedia.ResumeSupported,
        ["LowFramerate"] = PlayX.CurrentMedia.LowFramerate,
        ["HandlerArgs"] = PlayX.CurrentMedia.HandlerArgs,
    })
end

--- Send the PlayXEnd umsg to clients. You should not have much of a
-- a reason to call this method.
function PlayX.SendEndUMsg()
    local filter = RecipientFilter()
    filter:AddAllPlayers()
    
    umsg.Start("PlayXEnd", filter)
    umsg.End()
end

--- Send the PlayXUpdateInfo umsg to a user. You should not have much of a
-- a reason to call this method.
function PlayX.SendUpdateInfoUMsg(ply, ver)
    umsg.Start("PlayXUpdateInfo", ply)
    umsg.String(ver)
    umsg.End()
end

--- Send the PlayXEnd umsg to clients. You should not have much of a
-- a reason to call this method.
function PlayX.SendError(ply, err)
    umsg.Start("PlayXError", ply)
	umsg.String(err)
    umsg.End()
end

--- Send the PlayXSpawnDialog umsg to a client, telling the client to
-- open the spawn dialog.
-- @param ply Player to send to
function PlayX.SendSpawnDialogUMsg(ply)
	if not ply or not ply:IsValid() then
        return
    elseif not PlayX.IsPermitted(ply) then
        PlayX.SendError(ply, "You do not have permission to use the player")
    else
        umsg.Start("PlayXSpawnDialog", ply)
        umsg.End()
    end
end

local function JWURLCallback(cvar, old, new)
    -- Do our own cvar replication
    SendUserMessage("PlayXJWURL", nil, GetConVar("playx_jw_url"):GetString())
end

local function HostURLCallback(cvar, old, new)
    -- Do our own cvar replication
    SendUserMessage("PlayXHostURL", nil, GetConVar("playx_host_url"):GetString())
end

cvars.AddChangeCallback("playx_jw_url", JWURLCallback)
cvars.AddChangeCallback("playx_host_url", HostURLCallback)

--- Called for concmd playx_open.
local function ConCmdOpen(ply, cmd, args)
	if not ply or not ply:IsValid() then
        return
    elseif not PlayX.IsPermitted(ply) then
        PlayX.SendError(ply, "You do not have permission to use the player")
    elseif not PlayX.PlayerExists() then
        PlayX.SendError(ply, "There is no player spawned! Go to the spawn menu > Entities")
    elseif not args[1] then
        ply:PrintMessage(HUD_PRINTCONSOLE, "playx_open requires a URI")
    elseif GetConVar("playx_race_protection"):GetFloat() > 0 and 
        (CurTime() - PlayX.LastOpenTime) < GetConVar("playx_race_protection"):GetFloat() then
        PlayX.SendError(ply, "Another video/media selection was started too recently.")
    else
        local uri = args[1]:Trim()
        local provider = PlayX.ConCmdToString(args[2], ""):Trim()
        local start = PlayX.ParseTimeString(args[3])
        local forceLowFramerate = PlayX.ConCmdToBool(args[4], false)
        local useJW = PlayX.ConCmdToBool(args[5], true)
        local ignoreLength = PlayX.ConCmdToBool(args[6], false)
        
        if start == nil then
            PlayX.SendError(ply, "The time format you entered for \"Start At\" isn't understood")
        elseif start < 0 then
            PlayX.SendError(ply, "A non-negative start time is required")
        else
            local result, err = PlayX.OpenMedia(provider, uri, start,
                                                forceLowFramerate, useJW,
                                                ignoreLength)
            
            if not result then
                PlayX.SendError(ply, err)
            end
        end
    end
end

--- Called for concmd playx_close.
function ConCmdClose(ply, cmd, args)
	if not ply or not ply:IsValid() then
        return
    elseif not PlayX.IsPermitted(ply) then
        PlayX.SendError(ply, "You do not have permission to use the player")
    else
        PlayX.EndMedia()
    end
end

--- Called for concmd playx_spawn.
function ConCmdSpawn(ply, cmd, args)
    if not ply or not ply:IsValid() then
        return
    elseif not PlayX.IsPermitted(ply) then
        PlayX.SendError(ply, "You do not have permission to use the player")
    else
        if not args[1] or args[1]:Trim() == "" then
            PlayX.SendError(ply, "No model specified")
        else
            local model = args[1]:Trim()
            local result, err = PlayX.SpawnForPlayer(ply, model)
        
            if not result then
                PlayX.SendError(ply, err)
            end
        end
    end
end

--- Called for concmd playx_update_info.
function ConCmdUpdateInfo(ply, cmd, args)
    if not ply or not ply:IsValid() then
        return
    else	    
        Msg(Format("PlayX: %s asked for update info; ver=%s\n", ply:GetName(), _version))
	    
	    PlayX.SendUpdateInfoUMsg(ply, _version)
    end
end
 
concommand.Add("playx_open", ConCmdOpen)
concommand.Add("playx_close", ConCmdClose)
concommand.Add("playx_spawn", ConCmdSpawn)
concommand.Add("playx_update_info", ConCmdUpdateInfo)

--- Called on game mode hook PlayerInitialSpawn.
function PlayerInitialSpawn(ply)
    -- Do our own cvar replication
    SendUserMessage("PlayXJWURL", ply, GetConVar("playx_jw_url"):GetString())
    SendUserMessage("PlayXHostURL", ply, GetConVar("playx_host_url"):GetString())
    
    -- Send providers list.
    datastream.StreamToClients(ply, "PlayXProvidersList", {
        ["List"] = list.Get("PlayXProvidersList"),
    })
    
    timer.Simple(3, function()
        if PlayX.CurrentMedia and PlayX.CurrentMedia.ResumeSupported then
            if PlayX.CurrentMedia.StopTime and PlayX.CurrentMedia.StopTime < CurTime() then
                print("PlayX: Media expired, not sending begin UMSG")
                
                PlayX.EndMedia()
            else
                print("PlayX: Sending begin UMSG " .. ply:GetName())
                
                PlayX.SendBeginDStream(ply)
            end
        end
    end)
end

--- Called on game mode hook PlayerAuthed.
function PlayerAuthed(ply, steamID, uniqueID)
    if PlayX.CurrentMedia and PlayX.AdminTimeoutTimerRunning then
        if PlayX.IsPermitted(ply) then
            print("PlayX: Administrator authed (connecting); killing timeout")
            
            timer.Stop("PlayXAdminTimeout")
            PlayX.AdminTimeoutTimerRunning = false
        end
    end
end

--- Called on game mode hook PlayerDisconnected.
function PlayerDisconnected(ply)
    if not PlayX.CurrentMedia then return end
    if PlayX.AdminTimeoutTimerRunning then return end
    
    for _, v in pairs(player.GetAll()) do
        if v ~= ply and PlayX.IsPermitted(v) then return end
    end
    
    -- No timer, no admin, no soup for you
    local timeout = GetConVar("playx_admin_timeout"):GetFloat()
    
    if timeout > 0 then
        print(string.format("PlayX: No admin on server; setting timeout for %fs", timeout))
        
        timer.Adjust("PlayXAdminTimeout", timeout, 1)
        timer.Start("PlayXAdminTimeout")
        
        PlayX.AdminTimeoutTimerRunning = true
    end
end

hook.Add("PlayerInitialSpawn", "PlayXPlayerInitialSpawn", PlayerInitialSpawn)
hook.Add("PlayerAuthed", "PlayXPlayerPlayerAuthed", PlayerAuthed)
hook.Add("PlayerDisconnected", "PlayXPlayerDisconnected", PlayerDisconnected)

timer.Adjust("PlayXMediaExpire", 1, 1, function()
    print("PlayX: Media has expired")
    hook.Call("PlayXMediaExpired", nil, {})
    PlayX.EndMedia()
end)

timer.Adjust("PlayXAdminTimeout", 1, 1, function()
    print("PlayX: No administrators have been present for an extended period of time; timing out media")
    hook.Call("PlayXAdminTimeout", nil, {})
    PlayX.EndMedia()
end)

-- Get version
if file.Exists("../addons/PlayX/info.txt") then
    local contents = file.Read("../addons/PlayX/info.txt")
    _version = string.match(contents, "\"version\"[ \t]*\"([^\"]+)\"")
    if _version == nil then
        _version = ""
    end
end
