--------------------------------------------------------------------------------
-- Popper.lua
-- Prevents your camera from clipping through walls.
--------------------------------------------------------------------------------

local camera = game.Workspace.CurrentCamera

local min = math.min
local tan = math.tan
local rad = math.rad
local inf = math.huge
local ray = Ray.new

local function eraseFromEnd(t, toSize)
	for i = #t, toSize + 1, -1 do
		t[i] = nil
	end
end

local nearPlaneZ, projX, projY do
	local function updateProjection()
		local fov = rad(camera.FieldOfView)
		local view = camera.ViewportSize
		local ar = view.X/view.Y

		projY = 2*tan(fov/2)
		projX = ar*projY
	end

	camera:GetPropertyChangedSignal('FieldOfView'):Connect(updateProjection)
	camera:GetPropertyChangedSignal('ViewportSize'):Connect(updateProjection)

	updateProjection()

	nearPlaneZ = camera.NearPlaneZ
	camera:GetPropertyChangedSignal('NearPlaneZ'):Connect(function()
		nearPlaneZ = camera.NearPlaneZ
	end)
end

local blacklist = {} do
	local charMap = {}

	local function refreshIgnoreList()
		local n = 1
		blacklist = {}
		for _, character in pairs(charMap) do
			blacklist[n] = character
			n = n + 1
		end
	end

	local function playerAdded(player)
		local function characterAdded(character)
			charMap[player] = character
			refreshIgnoreList()
		end
		local function characterRemoving()
			charMap[player] = nil
			refreshIgnoreList()
		end

		player.CharacterAdded:Connect(characterAdded)
		player.CharacterRemoving:Connect(characterRemoving)
		if player.Character then
			characterAdded(player.Character)
		end
	end

	local function playerRemoving(player)
		charMap[player] = nil
		refreshIgnoreList()
	end

	do
		local Players = game:GetService('Players')

		Players.PlayerAdded:Connect(playerAdded)
		Players.PlayerRemoving:Connect(playerRemoving)

		for _, player in ipairs(Players:GetPlayers()) do
			playerAdded(player)
		end
		refreshIgnoreList()
	end
end

--------------------------------------------------------------------------------------------
-- Popper uses the level geometry find an upper bound on subject-to-camera distance.
--
-- Hard limits are applied immediately and unconditionally. They're generally caused
-- when level geometry intersects with the near plane (with exceptions, see below).
--
-- Soft limits are only applied under certain conditions.
-- They're caused when level geometry occludes the subject without actually intersecting
-- with the near plane at the target distance.
--
-- Soft limits can be promoted to hard limits and hard limits can be demoted to soft limits.
-- We usually don't want the latter to happen.
--
-- A soft limit will be promoted to a hard limit if an obstruction
-- lies between the current and target camera positions.
--------------------------------------------------------------------------------------------

local function canOcclude(part)
	-- Filter for opaque, interactable objects
	return part.Transparency < 0.95 and part.CanCollide
end

-- Offsets for the volume visibility test
local SCAN_SAMPLE_OFFSETS = {
	Vector2.new( 0.4, 0.0),
	Vector2.new(-0.4, 0.0),
	Vector2.new( 0.0,-0.4),
	Vector2.new( 0.0, 0.4),
	Vector2.new( 0.0, 0.2),
}

--------------------------------------------------------------------------------
-- Piercing raycasts

local function getCollisionPoint(origin, dir)
	local originalSize = #blacklist
	repeat
		local hitPart, hitPoint = workspace:FindPartOnRayWithIgnoreList(
			ray(origin, dir), blacklist, false, true
		)

		if hitPart then
			if hitPart.CanCollide then
				eraseFromEnd(blacklist, originalSize)
				return hitPoint, true
			end
			blacklist[#blacklist + 1] = hitPart
		end
	until not hitPart

	eraseFromEnd(blacklist, originalSize)
	return origin + dir, false
end

--------------------------------------------------------------------------------

local function queryPoint(origin, unitDir, dist, lastPos)
	debug.profilebegin('queryPoint')

	local originalSize = #blacklist

	dist = dist + nearPlaneZ
	local target = origin + unitDir*dist

	local softLimit = inf
	local hardLimit = inf
	local movingOrigin = origin

	repeat
		local entryPart, entryPos = workspace:FindPartOnRayWithIgnoreList(ray(movingOrigin, target - movingOrigin), blacklist, false, true)

		if entryPart then
			if canOcclude(entryPart) then
				local wl = {entryPart}
				local exitPart = workspace:FindPartOnRayWithWhitelist(ray(target, entryPos - target), wl, true)

				local lim = (entryPos - origin).Magnitude

				if exitPart then
					local promote = false
					if lastPos then
						promote = 
							workspace:FindPartOnRayWithWhitelist(ray(lastPos, target - lastPos), wl, true) or
							workspace:FindPartOnRayWithWhitelist(ray(target, lastPos - target), wl, true)
					end

					if promote then
						-- Ostensibly a soft limit, but the camera has passed through it in the last frame, so promote to a hard limit.
						hardLimit = lim
					elseif dist < softLimit then
						-- Trivial soft limit
						softLimit = lim
					end
				else
					-- Trivial hard limit
					hardLimit = lim
				end
			end

			blacklist[#blacklist + 1] = entryPart
			movingOrigin = entryPos
		end
	until hardLimit < inf or not entryPart

	eraseFromEnd(blacklist, originalSize)

	debug.profileend()
	return softLimit - nearPlaneZ, hardLimit - nearPlaneZ
end

local function queryViewport(focus, dist)
	debug.profilebegin('queryViewport')

	local fP =  focus.p
	local fX =  focus.rightVector
	local fY =  focus.upVector
	local fZ = -focus.lookVector

	local viewport = camera.ViewportSize

	local hardBoxLimit = inf
	local softBoxLimit = inf

	-- Center the viewport on the PoI, sweep points on the edge towards the target, and take the minimum limits
	for viewX = 0, 1 do
		local worldX = fX*((viewX - 0.5)*projX)

		for viewY = 0, 1 do
			local worldY = fY*((viewY - 0.5)*projY)

			local origin = fP + nearPlaneZ*(worldX + worldY)
			local lastPos = camera:ViewportPointToRay(
				viewport.x*viewX,
				viewport.y*viewY
			).Origin

			local softPointLimit, hardPointLimit = queryPoint(origin, fZ, dist, lastPos)

			if hardPointLimit < hardBoxLimit then
				hardBoxLimit = hardPointLimit
			end
			if softPointLimit < softBoxLimit then
				softBoxLimit = softPointLimit
			end
		end
	end
	debug.profileend()

	return softBoxLimit, hardBoxLimit
end

local function testPromotion(focus, dist, focusExtrapolation)
	debug.profilebegin('testPromotion')

	local fP = focus.p
	local fX = focus.rightVector
	local fY = focus.upVector
	local fZ = -focus.lookVector

	do
		-- Dead reckoning the camera rotation and focus
		debug.profilebegin('extrapolate')

		local SAMPLE_DT = 0.0625
		local SAMPLE_MAX_T = 1.25

		local maxDist = (getCollisionPoint(fP, focusExtrapolation.posVelocity*SAMPLE_MAX_T) - fP).Magnitude
		-- Metric that decides how many samples to take
		local combinedSpeed = focusExtrapolation.posVelocity.magnitude

		for dt = 0, min(SAMPLE_MAX_T, focusExtrapolation.rotVelocity.magnitude + maxDist/combinedSpeed), SAMPLE_DT do
			local cfDt = focusExtrapolation.extrapolate(dt) -- Extrapolated CFrame at time dt

			if queryPoint(cfDt.p, -cfDt.lookVector, dist) >= dist then
				return false
			end
		end

		debug.profileend()
	end

	do
		-- Test screen-space offsets from the focus for the presence of soft limits
		debug.profilebegin('testOffsets')

		for _, offset in ipairs(SCAN_SAMPLE_OFFSETS) do
			local scaledOffset = offset
			local pos, isHit = getCollisionPoint(fP, fX*scaledOffset.x + fY*scaledOffset.y)
			if queryPoint(pos, (fP + fZ*dist - pos).Unit, dist) == inf then
				return false
			end
		end

		debug.profileend()
	end

	debug.profileend()
	return true
end

local function Popper(focus, targetDist, focusExtrapolation)
	debug.profilebegin('popper')

	local dist = targetDist
	local soft, hard = queryViewport(focus, targetDist)
	if hard < dist then
		dist = hard
	end
	if soft < dist and testPromotion(focus, targetDist, focusExtrapolation) then
		dist = soft
	end

	debug.profileend()
	return dist
end

return Popper
