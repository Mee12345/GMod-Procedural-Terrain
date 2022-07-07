AddCSLuaFile()

if game.GetMap() != "gm_flatgrass" then return end

local terrain_speed = 0.1
if SERVER then 
    util.AddNetworkString("TERRAIN_SEND_DATA")  // superadmin only!
    Terrain = Terrain or {}
    
    local function genChunks()
        for y = Terrain.Resolution - 1, -Terrain.Resolution, -1 do
            for x = Terrain.Resolution - 1, -Terrain.Resolution, -1 do
                if Terrain.Variables.cave then
                    local chunk = ents.Create("terrain_chunk")
                    chunk:SetPos(Vector(x * Terrain.ChunkResScale, y * Terrain.ChunkResScale, Terrain.ZOffset))
                    chunk:SetChunkX(x)
                    chunk:SetChunkY(y)
                    chunk:SetFlipped(true)
                    chunk:Spawn()
                    table.insert(Terrain.Chunks, chunk)
                end

                local chunk = ents.Create("terrain_chunk")
                chunk:SetPos(Vector(x * Terrain.ChunkResScale, y * Terrain.ChunkResScale, Terrain.ZOffset))
                chunk:SetChunkX(x)
                chunk:SetChunkY(y)
                chunk:Spawn()
                table.insert(Terrain.Chunks, chunk)

    
                coroutine.wait(terrain_speed)
            end
        end
    end

    function Terrain.GenerateAll()
        for k, v in ipairs(Terrain.Chunks or {}) do // hotreloading
            SafeRemoveEntity(v)
        end
        
        local co = coroutine.create(genChunks)
        hook.Add("Think", "terrain_init", function()
            if coroutine.status(co) != "dead" then
                coroutine.resume(co)
            else
                hook.Remove("Think", "terrain_init")
            end
        end)
    end
    
    timer.Simple(1, Terrain.GenerateAll)    //generate all chunks

    net.Receive("TERRAIN_SEND_DATA", function(len, ply)
        if len == 0 then 
            net.Start("TERRAIN_SEND_DATA")
            net.WriteTable(Terrain.Variables)
            net.Send(ply)
            return
        end

        if !ply or !ply:IsValid() or !ply:IsSuperAdmin() then return end    // only superadmins can edit terrain

        local t = net.ReadTable()
        Terrain.MathFunc = Terrain.BuildMathFunc(t)
        net.Start("TERRAIN_SEND_DATA")
        net.WriteTable(t)
        net.Broadcast()

        Terrain.Variables = t
        timer.Simple(1, Terrain.GenerateAll)    // give clients a second to receive the data
    end)
else
    // client needs the data to build the math function
    Terrain = Terrain or {}
    Terrain.ClientLoaded = false

    local done = 0
    local sizex = ScrW() * 0.5
    local sizey = ScrH() * 0.02
    local function loadhud()
        surface.SetDrawColor(Color(0, 0, 0, 255))
        surface.DrawRect(sizex - 200, sizey - 12.5, 400, 50)
        draw.DrawText("Generating Server Chunks.. " .. math.Round(done * 100) .. "% done", "TargetID", sizex, sizey, color_white, TEXT_ALIGN_CENTER)
    end

    // clients can randomly forget chunk data during a lagspike, we rebuild it if that happens
    local co = coroutine.create(function()
        while true do 
            local cave = (Terrain.Variables.cave and 2 or 1)
            coroutine.wait(1)
            if Terrain.ClientLoaded then
                local chunks = ents.FindByClass("terrain_chunk")
                if #chunks < ((Terrain.Resolution * 2)^2) * cave then 
                    hook.Add("HUDPaint", "terrain_load", loadhud)
                    done = #chunks / (Terrain.Resolution * 2)^2 / cave
                    continue
                else
                    done = 1
                end
                for k, v in ipairs(chunks) do
                    if v:IsValid() then
                        if jit.arch != "x86" then
                            if (!v:GetPhysicsObject() or !v:GetPhysicsObject():IsValid()) then
                                print("Rebuilding Physics for Chunk " .. v:GetChunkX() .. "," .. v:GetChunkY())
                                v:OnRemove()
                                v:ClientInitialize()
                            end
                        else
                            if !v.TreeMatrices then
                                print("Rebuilding Physics for Chunk " .. v:GetChunkX() .. "," .. v:GetChunkY())
                                v:OnRemove()
                                v:ClientInitialize()
                            end
                        end
                    end
                    coroutine.wait(terrain_speed)
                end
            end
        end
    end)

    // request server to reload chunks
    hook.Add("Tick", "terrain_init", function()
        coroutine.resume(co)
    end)

    net.Receive("TERRAIN_SEND_DATA", function(len)
        local t = net.ReadTable()
        Terrain.Variables = t
        Terrain.MathFunc = Terrain.BuildMathFunc()
        Terrain.Material:SetTexture("$basetexture", t.material_2)
        Terrain.Material:SetTexture("$basetexture2", t.material_1)
        Terrain.WaterMaterial = Material(t.material_3)

        //if !Terrain.ClientLoaded then
            Terrain.ClientLoaded = true
            //local has_end = false
            //for k, v in ipairs(ents.FindByClass("terrain_chunk")) do
            //    if v.Initialize then
            //        v:Initialize()
            //        if v.GetChunkX and v:GetChunkX() == -Terrain.Resolution and v:GetChunkY() == -Terrain.Resolution then
            //            has_end = true
            //        end
            //    end
            //end

            //if has_end then
                //timer.Simple(10, function()
                //    Terrain.GenerateLightmap(1024)
                //end)
            //end
        //end
    end)

    // clients request to server to get data for height function
    hook.Add("InitPostEntity", "terrain_init", function()
        net.Start("TERRAIN_SEND_DATA")
        net.SendToServer()
    end)
end