-- Shared DrinkSystem ByteNet packets + helpers

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getByteNetModule()
	local packages = ReplicatedStorage:FindFirstChild("Packages")
	local moduleScript = packages and packages:FindFirstChild("ByteNet") or nil
	if not moduleScript then
		moduleScript = ReplicatedStorage:FindFirstChild("ByteNet")
	end
	assert(moduleScript, "[DrinkSystem.Network] ByteNet module not found in ReplicatedStorage/Packages or ReplicatedStorage")
	return moduleScript
end

local ByteNet = require(getByteNetModule())

local Network = {}

function Network.color3ToVec3(color: Color3?): Vector3?
	if typeof(color) == "Color3" then
		return Vector3.new(color.R, color.G, color.B)
	end
	return nil
end

function Network.vec3ToColor3(vec: Vector3?): Color3?
	if typeof(vec) == "Vector3" then
		return Color3.new(vec.X, vec.Y, vec.Z)
	end
	return nil
end

Network.Packets = ByteNet.defineNamespace("DrinkSystem", function()
	local drinkPayload = ByteNet.struct({
		RecipeName = ByteNet.optional(ByteNet.string),
		DisplayName = ByteNet.optional(ByteNet.string),
		Color = ByteNet.optional(ByteNet.vec3),
		Strongness = ByteNet.float32,
		RequiresShaker = ByteNet.bool,
		Ingredients = ByteNet.array(ByteNet.string),
		IsRecipe = ByteNet.bool,
	})

	local guidancePayload = ByteNet.struct({
		Instruction = ByteNet.string,
		RecommendedIngredients = ByteNet.array(ByteNet.string),
		RequiredItemType = ByteNet.optional(ByteNet.string),
		SelectedRecipe = ByteNet.optional(ByteNet.string),
		SuggestedRecipe = ByteNet.optional(ByteNet.string),
		SuggestedRecipes = ByteNet.array(ByteNet.string),
	})

	return {
		RequestPickupItem = ByteNet.definePacket({
			value = ByteNet.struct({
				Model = ByteNet.inst,
			}),
		}),

		RequestPourIngredient = ByteNet.definePacket({
			value = ByteNet.struct({
				BottleModel = ByteNet.inst,
			}),
		}),

		RequestAddGarnish = ByteNet.definePacket({
			value = ByteNet.struct({
				Model = ByteNet.inst,
			}),
		}),

		RequestFinalizeMix = ByteNet.definePacket({
			value = ByteNet.struct({}),
		}),

		RequestSelectRecipe = ByteNet.definePacket({
			value = ByteNet.struct({
				RecipeName = ByteNet.optional(ByteNet.string),
			}),
		}),

		ShakerFinished = ByteNet.definePacket({
			value = ByteNet.struct({}),
		}),

		PlaceDrink = ByteNet.definePacket({
			value = ByteNet.struct({
				Tool     = ByteNet.inst,
				Position = ByteNet.optional(ByteNet.vec3),
			}),
		}),

		ConsumeDrink = ByteNet.definePacket({
			value = ByteNet.struct({
				Tool = ByteNet.inst,
			}),
		}),

		StartBottlePour = ByteNet.definePacket({
			value = ByteNet.struct({
				IngredientName = ByteNet.string,
				BottleModel = ByteNet.inst,
			}),
		}),

		StartShakerSequence = ByteNet.definePacket({
			value = drinkPayload,
		}),

		MissingShakerNotify = ByteNet.definePacket({
			value = ByteNet.struct({}),
		}),

		GuidanceUpdate = ByteNet.definePacket({
			value = guidancePayload,
		}),

		SetBackpackLocked = ByteNet.definePacket({
			value = ByteNet.struct({
				Locked = ByteNet.bool,
			}),
		}),

		DrinkOutcome = ByteNet.definePacket({
			value = ByteNet.struct({
				DrinkName = ByteNet.string,
				Outcome = ByteNet.string,
				Score = ByteNet.uint8,
			}),
		}),
	}
end)

return Network
