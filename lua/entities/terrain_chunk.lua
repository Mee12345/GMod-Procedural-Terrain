

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Category		= "Deform Test"
ENT.PrintName		= "Terrain Chunk"
ENT.Author			= "Mee"
ENT.Purpose			= ""
ENT.Instructions	= ""
ENT.Spawnable		= false

if game.GetMap() != "gm_flatgrass" then return end

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "ChunkX")
    self:NetworkVar("Int", 1, "ChunkY")
    self:NetworkVar("Bool", 0, "Flipped")
end

Terrain = Terrain or {}

if CLIENT then
    //Terrain.Material = Material("nature/blendrocksgrass006a")
    Terrain.Material = CreateMaterial("NatureblendTerrain01", "WorldVertexTransition", {
        ["$basetexture"] = "nature/rockfloor005a",
	    ["$surfaceprop"] = "rock",
	    ["$basetexture2"] = "gm_construct/grass1",
	    ["$surfaceprop2"] = "dirt",
        ["$seamless_scale"] = 0.002,
        ["$nocull"] = 1,
    })
end

function ENT:GetTreeData(pos, data, heightFunction)
    local heightFunction = heightFunction or Terrain.MathFunc

    // pos is local to chunk
    local x = pos[1]
    local y = pos[2]

    // chunk offset in world space
    local chunkoffsetx = self:GetChunkX() * Terrain.ChunkResScale
    local chunkoffsety = self:GetChunkY() * Terrain.ChunkResScale

    // no trees in spawn area (1000x1000 hu square)
    if data.spawnArea and math.abs(x + chunkoffsetx) < 1500 and math.abs(y + chunkoffsety) < 1500 then return nil end

    // the height of the vertex using the math function
    local vertexHeight = heightFunction(x + chunkoffsetx, y + chunkoffsety)
    local middleHeight = Vector(0, 0, vertexHeight)

    local finalPos = Vector(x + chunkoffsetx, y + chunkoffsety, vertexHeight + Terrain.ZOffset - 25.6 * data.treeHeight) // pushed down 25.6 units, (height of the base of the tree model)

    // no trees under water
    if data.waterHeight and finalPos[3] < data.waterHeight then return nil end

    // calculate the smoothed normal, if it is extreme, do not place a tree
    local smoothedNormal = Vector()
    for cornery = 0, 1 do
        for cornerx = 0, 1 do
            // get 4 corners in a for loop ranging from -1 to 1
            local cornerx = (cornerx - 0.5) * 2
            local cornery = (cornery - 0.5) * 2

            // get the height of the 0x triangle
            local cornerWorldy = (y + cornery)
            local cornerHeight = heightFunction(x + chunkoffsetx, cornerWorldy + chunkoffsety)
            local middleXPosition = Vector(0, cornery, cornerHeight)

            // get the height of the 0y triangle
            local cornerWorldx = (x + cornerx)
            local cornerHeight = heightFunction(cornerWorldx + chunkoffsetx, y + chunkoffsety)
            local middleYPosition = Vector(cornerx, 0, cornerHeight)
            
            // we now have 3 points, construct a triangle from this and add the normal to the average normal
            local triNormal = (middleYPosition - middleHeight):Cross(middleXPosition - middleHeight) * cornerx * cornery
            smoothedNormal = smoothedNormal + triNormal
        end
    end

    smoothedNormal = smoothedNormal:GetNormalized()
    if smoothedNormal[3] < data.treeThreshold then return nil end    // remove trees on extreme slopes

    return finalPos, smoothedNormal
end

function ENT:GenerateTrees(heightFunction, data)
    local data = data or Terrain.Variables
    local heightFunction = heightFunction or Terrain.MathFunc
    local treeResolution = data.treeResolution or Terrain.Variables.treeResolution

    self.TreeMatrices = {}
    self.TreeModels = {}
    self.TreeShading = {}
    self.TreeColors = {}

    local treeMultiplier = Terrain.ChunkResolution / data.treeResolution * Terrain.ChunkSize
    local randomIndex = 0
    local chunkIndex = tostring(self:GetChunkX()) .. tostring(self:GetChunkY())
    for y = 0, data.treeResolution - 1 do
        for x = 0, data.treeResolution - 1 do
            randomIndex = randomIndex + 1
            local m = Matrix()

            // generate seeded random position for tree
            local randseedx = util.SharedRandom("TerrainSeedX" .. chunkIndex, 0, 1, randomIndex)
            local randseedy = util.SharedRandom("TerrainSeedY" .. chunkIndex, 0, 1, randomIndex)
            local randPos = Vector(randseedx, randseedy) * data.treeResolution * treeMultiplier

            local finalPos, smoothedNormal = self:GetTreeData(randPos, data, heightFunction)
            if !finalPos then continue end

            m:SetTranslation(finalPos)
            m:SetAngles(Angle(0, randseedx * 3600, 0))//smoothedNormal:Angle() + Angle(90, 0, 0) Angle(0, randseedx * 3600, 0)
            m:SetScale(Vector(1, 1, 1) * data.treeHeight)
            finalPos[3] = finalPos[3] + 256 * data.treeHeight  // add tree height
            table.insert(self.TreeMatrices, m)
            local modelIndex = math.floor(util.SharedRandom("TerrainModel" .. chunkIndex, 0, #Terrain.TreeModels - 0.9, randomIndex)) + 1
            table.insert(self.TreeModels, modelIndex)  // 4.1 means 1/50 chance for a rock to generate instead of a tree
            local shading = util.TraceLine({start = finalPos, endpos = finalPos + Terrain.SunDir * 99999}).HitSky and 1.5 or 0.5
            table.insert(self.TreeShading, shading)
            table.insert(self.TreeColors, modelIndex != 5 and Vector(shading, shading, shading) * data.treeColor or Vector(shading, shading, shading))
        end
    end
end

function ENT:GenerateMesh(heightFunction)
    local heightFunction = heightFunction or Terrain.MathFunc
    // generate a mesh for the chunk using the mesh library
    self.RenderMesh = Mesh(Terrain.Material)
    local mesh = mesh   // local lookup is faster than global
    local err, msg
    local function smoothedNormal(chunkoffsetx, chunkoffsety, vertexPos)
        local unwrappedPos = vertexPos / Terrain.ChunkSize
        local smoothedNormal = Vector()
        for cornery = 0, 1 do
            for cornerx = 0, 1 do
                // get 4 corners in a for loop ranging from -1 to 1
                local cornerx = (cornerx - 0.5) * 2
                local cornery = (cornery - 0.5) * 2

                // get the height of the 0x triangle
                local cornerWorldx = vertexPos[1]
                local cornerWorldy = (unwrappedPos[2] + cornery) * Terrain.ChunkSize
                local cornerHeight = heightFunction(cornerWorldx + chunkoffsetx, cornerWorldy + chunkoffsety)
                local middleXPosition = Vector(0, Terrain.ChunkSize * cornery, cornerHeight)

                // get the height of the 0y triangle
                local cornerWorldx = (unwrappedPos[1] + cornerx) * Terrain.ChunkSize
                local cornerWorldy = vertexPos[2]
                local cornerHeight = heightFunction(cornerWorldx + chunkoffsetx, cornerWorldy + chunkoffsety)
                local middleYPosition = Vector(Terrain.ChunkSize * cornerx, 0, cornerHeight)

                // we now have 3 points, construct a triangle from this and add the normal to the average normal
                local triNormal = (middleYPosition - vertexPos):Cross(middleXPosition - vertexPos) * cornerx * cornery
                smoothedNormal = smoothedNormal + triNormal
            end
        end

        return smoothedNormal:GetNormalized()
    end

    mesh.Begin(self.RenderMesh, MATERIAL_TRIANGLES, Terrain.ChunkResolution^2 * 2)
    err, msg = pcall(function()
        for y = 0, Terrain.ChunkResolution - 1 do
            for x = 0, Terrain.ChunkResolution - 1 do
                // chunk offset in world space
                local chunkoffsetx = self:GetChunkX() * Terrain.ChunkResScale   // Terrain.ChunkSize * Terrain.ChunkResolution
                local chunkoffsety = self:GetChunkY() * Terrain.ChunkResScale

                // vertex of the triangle in the chunks local space
                local worldx1 = x * Terrain.ChunkSize
                local worldy1 = y * Terrain.ChunkSize
                local worldx2 = (x + 1) * Terrain.ChunkSize
                local worldy2 = (y + 1) * Terrain.ChunkSize

                // the height of the vertex using the math function
                local flipped = self:GetFlipped()
                local vertexHeight1 = heightFunction(worldx1 + chunkoffsetx, worldy1 + chunkoffsety, flipped)
                local vertexHeight2 = heightFunction(worldx1 + chunkoffsetx, worldy2 + chunkoffsety, flipped)
                local vertexHeight3 = heightFunction(worldx2 + chunkoffsetx, worldy1 + chunkoffsety, flipped)
                local vertexHeight4 = heightFunction(worldx2 + chunkoffsetx, worldy2 + chunkoffsety, flipped)

                // vertex positions in local space
                local vertexPos1 = Vector(worldx1, worldy1, vertexHeight1)
                local vertexPos2 = Vector(worldx1, worldy2, vertexHeight2)
                local vertexPos3 = Vector(worldx2, worldy1, vertexHeight3)
                local vertexPos4 = Vector(worldx2, worldy2, vertexHeight4)

                // lightmap uv calculation, needs to spread over whole terrain or it looks weird
                // since chunks range into negative numbers we need to adhere to that
                local r = Terrain.Resolution
                local uvx1 = ((self:GetChunkX() + r) / r + (x / Terrain.ChunkResolution / r)) * 0.5
                local uvy1 = ((self:GetChunkY() + r) / r + (y / Terrain.ChunkResolution / r)) * 0.5
                local uvx2 = ((self:GetChunkX() + r) / r + ((x + 1) / Terrain.ChunkResolution / r)) * 0.5
                local uvy2 = ((self:GetChunkY() + r) / r + ((y + 1) / Terrain.ChunkResolution / r)) * 0.5

                local normal1 = -(vertexPos1 - vertexPos2):Cross(vertexPos1 - vertexPos3):GetNormalized()
                local normal2 = -(vertexPos4 - vertexPos3):Cross(vertexPos4 - vertexPos2):GetNormalized()

                local smoothedNormal1 = smoothedNormal(chunkoffsetx, chunkoffsety, vertexPos1)
                local smoothedNormal2 = smoothedNormal(chunkoffsetx, chunkoffsety, vertexPos2)
                local smoothedNormal3 = smoothedNormal(chunkoffsetx, chunkoffsety, vertexPos3)
                local smoothedNormal4 = smoothedNormal(chunkoffsetx, chunkoffsety, vertexPos4)

                local waterHeight = Terrain.Variables.waterHeight or -math.huge
                local rock1 = (vertexHeight1 + Terrain.ZOffset < waterHeight) and 0.3 or smoothedNormal1[3]
                local rock2 = (vertexHeight2 + Terrain.ZOffset < waterHeight) and 0.3 or smoothedNormal2[3]
                local rock3 = (vertexHeight3 + Terrain.ZOffset < waterHeight) and 0.3 or smoothedNormal3[3]
                local rock4 = (vertexHeight4 + Terrain.ZOffset < waterHeight) and 0.3 or smoothedNormal4[3]

                local color1 = math.Min(rock1 * 512, 255)
                local color2 = math.Min(rock2 * 512, 255)
                local color3 = math.Min(rock3 * 512, 255)
                local color4 = math.Min(rock4 * 512, 255)

                // first tri
                mesh.Position(vertexPos1)
                mesh.TexCoord(0, 0, 0)        // texture UV
                mesh.TexCoord(1, uvx1, uvy1)  // lightmap UV
                mesh.Color(255, 255, 255, color1)
                mesh.Normal(normal1)
                
                mesh.AdvanceVertex()
                mesh.Position(vertexPos2)
                mesh.TexCoord(0, 1, 0)
                mesh.TexCoord(1, uvx1, uvy2)  
                mesh.Color(255, 255, 255, color2)
                mesh.Normal(normal1)
                mesh.AdvanceVertex()

                mesh.Position(vertexPos3)
                mesh.TexCoord(0, 0, 1)
                mesh.TexCoord(1, uvx2, uvy1)  
                mesh.Color(255, 255, 255, color3)
                mesh.Normal(normal1)
                mesh.AdvanceVertex()

                // second tri
                mesh.Position(vertexPos3)
                mesh.TexCoord(0, 0, 1)
                mesh.TexCoord(1, uvx2, uvy1)  
                mesh.Color(255, 255, 255, color3)
                mesh.Normal(normal2)
                mesh.AdvanceVertex()

                mesh.Position(vertexPos2)
                mesh.TexCoord(0, 1, 0)
                mesh.TexCoord(1, uvx1, uvy2) 
                mesh.Color(255, 255, 255, color2)
                mesh.Normal(normal2)
                mesh.AdvanceVertex()

                mesh.Position(vertexPos4)
                mesh.TexCoord(0, 1, 1)
                mesh.TexCoord(1, uvx2, uvy2) 
                mesh.Color(255, 255, 255, color4)
                mesh.Normal(normal2)
                mesh.AdvanceVertex()
            end
        end
    end)
    mesh.End()

    if !err then print(msg) end  // if there is an error, catch it and throw it outside of mesh.begin since you crash if mesh.end is not called
end

local grassAmount = 104
function ENT:GenerateGrass()
    self.GrassMesh = Mesh()
    if !Terrain.Variables.generateGrass then return end
    local grassSize = Terrain.Variables.grassSize

    local mesh = mesh
    local err, msg
    local chunkIndex = tostring(self:GetChunkX()) .. tostring(self:GetChunkY())
    local randomIndex = 0
    mesh.Begin(self.GrassMesh, MATERIAL_TRIANGLES, grassAmount^2)
    err, msg = pcall(function()
        for y = 0, grassAmount - 1 do
            for x = 0, grassAmount - 1 do
                randomIndex = randomIndex + 1
                local mult = Terrain.ChunkResolution / grassAmount
                local x = x * mult
                local y = y * mult
                local randoffsetx = util.SharedRandom("TerrainGrassX" .. chunkIndex, 0, 1, randomIndex) * mult
                local randoffsety = util.SharedRandom("TerrainGrassY" .. chunkIndex, 0, 1, randomIndex) * mult
                
                // chunk offset in world space
                local chunkoffsetx = self:GetChunkX() * Terrain.ChunkResScale   // Terrain.ChunkSize * Terrain.ChunkResolution
                local chunkoffsety = self:GetChunkY() * Terrain.ChunkResScale

                // vertex of the triangle in the chunks local space
                local worldx = (x + randoffsetx) * Terrain.ChunkSize
                local worldy = (y + randoffsety) * Terrain.ChunkSize

                // the height of the vertex using the math function
                local vertexHeight = Terrain.MathFunc(worldx + chunkoffsetx, worldy + chunkoffsety) 
                local mainPos = Vector(chunkoffsetx + worldx, chunkoffsety + worldy, vertexHeight + Terrain.ZOffset)
                if Terrain.Variables.waterHeight and mainPos[3] < Terrain.Variables.waterHeight then continue end

                local randbrushx = math.floor(((randoffsetx * 9999) % 1) * 3) * 0.3 
                local randbrushy = math.floor(((randoffsety * 9999) % 1) * 3) * 0.3 
                local offsetx = randbrushx - 0.1
                local offsety = 0.5 - randbrushy
                local randdir = Angle(0, randoffsetx * 9999, 0)

                mesh.TexCoord(0, offsetx, 0.3 + offsety)
                mesh.Position(mainPos - randdir:Right() * grassSize)
                mesh.Color(200, 255, 200, 200)
                mesh.AdvanceVertex()

                mesh.TexCoord(0, 0.3 + offsetx, 0.3 + offsety)
                mesh.Position(mainPos + randdir:Right() * grassSize)
                mesh.Color(200, 255, 200, 255)
                mesh.AdvanceVertex()

                mesh.TexCoord(0, 0.3 + offsetx, offsety)
                mesh.Position(mainPos + (randdir:Right() + randdir:Up() * 2) * grassSize)
                mesh.Color(200, 255, 200, 255)
                mesh.AdvanceVertex()
            end
        end
    end)
    mesh.End()

    if !err then print(msg) end
end

// get the height of the terrain at a given point with given offset
local function getChunkOffset(x, y, offsetx, offsety, flipped, heightFunction)
	local cs = Terrain.ChunkSize
	local ox, oy = x * cs, y * cs
	return Vector(ox, oy, heightFunction(ox + offsetx, oy + offsety, flipped))
end

// create the collision mesh for the chunk, runs on server & client
function ENT:BuildCollision(heightFunction)
    if CLIENT and jit.arch == "x86" then 
        self:SetRenderBounds(Vector(0, 0, 0), Vector(1, 1, 1000) * Terrain.ChunkResScale + Vector(0, 0, 1000)) // add 1000 units for trees
        print("CLIENT IS ON 32 BIT, PREVENTING INCOMING CRASH BY NOT GENERATING PHYSICS OBJECT") 
        return 
    end  // no collision for 32 bit because funny memory leak crashing hahaha

    local heightFunction = heightFunction or Terrain.MathFunc

    // main base terrain
	local finalMesh = {}
	for y = 1, Terrain.ChunkResolution do 
		for x = 1, Terrain.ChunkResolution do
			local offsetx = self:GetChunkX() * Terrain.ChunkResScale
			local offsety = self:GetChunkY() * Terrain.ChunkResScale

            local flipped = self:GetFlipped()
			local p1 = getChunkOffset(x, y, offsetx, offsety, flipped, heightFunction)
			local p2 = getChunkOffset(x - 1, y, offsetx, offsety, flipped, heightFunction)
			local p3 = getChunkOffset(x, y - 1, offsetx, offsety, flipped, heightFunction)
			local p4 = getChunkOffset(x - 1, y - 1, offsetx, offsety, flipped, heightFunction)
			
			table.Add(finalMesh, {
				{pos = p1},
				{pos = p2},
				{pos = p3}
			})

			table.Add(finalMesh, {
				{pos = p2},
				{pos = p3},
				{pos = p4}
			})
		end 
	end

    // tree collision
    // crashes if this is generated on client, guess trees & rocks will be buggy to interact with.. oh well
    if SERVER and !self:GetFlipped() then
        local data = Terrain.Variables
        data.treeMultiplier = Terrain.ChunkResolution / data.treeResolution * Terrain.ChunkSize
        local randomIndex = 0
        local chunkIndex = tostring(self:GetChunkX()) .. tostring(self:GetChunkY())
        for y = 0, data.treeResolution - 1 do
            for x = 0, data.treeResolution - 1 do
                randomIndex = randomIndex + 1

                // generate seeded random position for tree
                local randseedx = util.SharedRandom("TerrainSeedX" .. chunkIndex, 0, 1, randomIndex)
                local randseedy = util.SharedRandom("TerrainSeedY" .. chunkIndex, 0, 1, randomIndex)
                local randPos = Vector(randseedx, randseedy) * data.treeResolution * data.treeMultiplier

                local finalPos = self:GetTreeData(randPos, data, heightFunction)
                if !finalPos then continue end

                local treeIndex = math.floor(util.SharedRandom("TerrainModel" .. chunkIndex, 0, #Terrain.TreeModels - 0.9, randomIndex)) + 1
                local treeMesh = {}
                for k, v in ipairs(Terrain.TreePhysMeshes[treeIndex]) do
                    local rotatedPos = Vector(v.pos[1], v.pos[2], v.pos[3])
                    rotatedPos:Rotate(Angle(0, randseedx * 3600, 0))
                    treeMesh[k] = {pos = (rotatedPos * data.treeHeight + finalPos) - self:GetPos()}
                end

                table.Add(finalMesh, treeMesh)
            end
        end
    end

    self:PhysicsDestroy()
	self:PhysicsFromMesh(finalMesh)

    if CLIENT then
        self:SetRenderBounds(self:OBBMins(), self:OBBMaxs() + Vector(0, 0, 1000))
    end
end

function ENT:Initialize()
    if CLIENT then return end

    self:SetModel("models/props_c17/FurnitureCouch002a.mdl")
    self:BuildCollision()
    self:SetSolid(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_NONE)
    self:EnableCustomCollisions(true)
    self:GetPhysicsObject():EnableMotion(false)
    self:GetPhysicsObject():SetMass(50000)  // max weight, should help a bit with the physics solver
    self:DrawShadow(false)
end

function ENT:ClientInitialize()
    self:BuildCollision()
    if self:GetPhysicsObject():IsValid() then
        self:GetPhysicsObject():EnableMotion(false)
        self:GetPhysicsObject():SetMass(50000)  // make sure to call these on client or else when you touch it, you will crash
        self:GetPhysicsObject():SetPos(self:GetPos())
    end

    self:GenerateMesh()
    if !self:GetFlipped() then
        self:GenerateTrees()
        self:GenerateGrass()
    end

    // if its the last chunk, generate the lightmap
    if self:GetChunkX() == -Terrain.Resolution and self:GetChunkY() == -Terrain.Resolution then
        timer.Simple(2, function()
            Terrain.GenerateLightmap(1024)
        end)
    end
end

// it has to be transmitted to the client always because its like, the world
function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

function ENT:CanProperty(ply, property)
	return false
end

hook.Add("CanDrive", "terrain_stopdrive", function(ply, ent)
    if ent:GetClass() == "terrain_chunk" then return false end
end)

// disable physgun pickup because that would be cancer
hook.Add("PhysgunPickup", "Terrain_DisablePhysgun", function(ply, ent)
	if ent and ent:GetClass() == "terrain_chunk" then
		return false
	end
end)

function ENT:OnRemove()
    if self.RenderMesh and self.RenderMesh:IsValid() then
        self.RenderMesh:Destroy()
    end

    if self.GrassMesh and self.GrassMesh:IsValid() then
        self.GrassMesh:Destroy()
    end
end

// drawing, no server here
if SERVER then return end

local lm = Terrain.Lightmap
local detailMaterial = Material("detail/detailsprites")  // detail/detailsprites models/props_combine/combine_interface_disp

// cache ALL of these for faster lookup
local renderTable = {Material = Terrain.Material}
local render_SetLightmapTexture = render.SetLightmapTexture
local render_SetMaterial = render.SetMaterial
local render_SetModelLighting = render.SetModelLighting
local render_SetLocalModelLights = render.SetLocalModelLights
local cam_PushModelMatrix = cam.PushModelMatrix
local cam_PopModelMatrix = cam.PopModelMatrix
local math_DistanceSqr = math.DistanceSqr
local math_Distance = math.Distance

// this MUST be optimized as much as possible, it is called multiple times every frame
function ENT:GetRenderMesh()
    local self = self

    // set a lightmap texture to be used instead of the default one
    render_SetLightmapTexture(lm)

    if !self.TreeMatrices then 
        renderTable.Mesh = self.RenderMesh
        return renderTable 
    end

    // get local vars
    local lod = self.LOD
    local models = self.TreeModels
    local lighting = self.TreeShading
    local color = self.TreeColors
    local matrices = self.TreeMatrices
    local materials = Terrain.TreeMaterials
    local flashlightOn = LocalPlayer():FlashlightIsOn()

    // reset lighting
    render_SetLocalModelLights()
    render_SetModelLighting(1, 0.1, 0.1, 0.1)
    render_SetModelLighting(3, 0.1, 0.1, 0.1)
    render_SetModelLighting(5, 0.1, 0.1, 0.1)

    // render foliage
    if lod then // chunk is near us, render high quality foliage
        local lastlight
        local lastmat
        for i = 1, #matrices do
            local matrix = matrices[i]
            local modelID = models[i]
            if lastmat != modelID then
                if i == 1 or lastmat == 5 or modelID == 5 then
                    render_SetMaterial(materials[modelID])
                end
                lastmat = modelID
            end

            // give the tree its shading
            local tree_color = color[i]
            if tree_color != lastlight then
                local light = lighting[i]
                local light_2 = light * 0.45
                render_SetModelLighting(0, light_2, light_2, light_2)
                render_SetModelLighting(2, light, light, light)
                render_SetModelLighting(4, tree_color[1], tree_color[2], tree_color[3])
                lastlight = tree_color
            end

            // push custom matrix generated earlier and render the tree
            cam_PushModelMatrix(matrix)
                Terrain.TreeMeshes[modelID]:Draw()
                if flashlightOn then   // flashlight compatability
                    render.PushFlashlightMode(true)
                    Terrain.TreeMeshes[modelID]:Draw()
                    render.PopFlashlightMode()
                end
            cam_PopModelMatrix()
        end
    else // chunk is far, render low definition
        local lastlight
        local lastmat
        for i = 1, #matrices do
            local matrix = matrices[i]
            local modelID = models[i]
            if lastmat != modelID then
                if i == 1 or lastmat == 5 or modelID == 5 then
                    render_SetMaterial(materials[modelID])
                end
                lastmat = modelID
            end

            // give the tree its shading
            local tree_color = color[i]
            if tree_color != lastlight then
                local light = lighting[i]
                local light_2 = light * 0.45
                render_SetModelLighting(0, light_2, light_2, light_2)
                render_SetModelLighting(2, light, light, light)
                render_SetModelLighting(4, tree_color[1], tree_color[2], tree_color[3])
                lastlight = tree_color
            end

            // push custom matrix generated earlier and render the tree
            cam_PushModelMatrix(matrix)
                Terrain.TreeMeshes_Low[modelID]:Draw()
            cam_PopModelMatrix()
        end
    end

    // render the chunk mesh itself
    renderTable.Mesh = self.RenderMesh
    return renderTable
end

function ENT:Draw()
    local self = self
    local selfpos = (self:GetPos() + self:OBBCenter())
    local eyepos = EyePos()
    self.LOD = math_DistanceSqr(selfpos[1], selfpos[2], eyepos[1], eyepos[2]) < Terrain.LODDistance
    self:DrawModel()
    if self.LOD and IsValid(self.GrassMesh) then 
        render_SetMaterial(detailMaterial)
        self.GrassMesh:Draw()
    end
end