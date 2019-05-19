-- MonoGame v0.5
-- for TES3MP 0.7.0-alpha

-- script that implements the mechanics related to Mono card game

-- major TODO: figure out why client is frezing when picking up cards


-- bad TODO: prevent player from equipping the incorrect mesh
-- good TODO: make it so that unused deck meshes get removed from inventory
-- this was already working before in some iteration of this code, but got lost during the insane hunt for inventory fixes (which then got removed by ugly hack instead of proper way, read line 42)

-- TODO: implement logic for valid moves

-- TLDR: tell David to explain to me what kind of logic would have been required for this to have been implemented in straight-forward way, where each function does what it's meant to do
-- I lost a lot of time on this because LUA is not python and because I assumed that player always sees the exact same inventory content that server does
-- which is not the case since there can be items listed in player's file that are not visible in player's inventory
-- and if you run logic based on those items, then debugging is much more annoying process than you would want it to be

math.randomseed(os.time())

testMonoGame = {}

monoCards = {}
monoCards.blue = {"mono_blue_1", "mono_blue_2", "mono_blue_3", "mono_blue_4", "mono_blue_5", "mono_blue_6", "mono_blue_7", "mono_blue_fireball", "mono_blue_reflect", "mono_blue_take_two"}
monoCards.red = {"mono_red_1", "mono_red_2", "mono_red_3", "mono_red_4", "mono_red_5", "mono_red_6", "mono_red_7", "mono_red_fireball", "mono_red_reflect", "mono_red_take_two"}
monoCards.green = {"mono_green_1", "mono_green_2", "mono_green_3", "mono_green_4", "mono_green_5", "mono_green_6", "mono_green_7", "mono_green_fireball", "mono_green_reflect", "mono_green_take_two"}
monoCards.yellow = {"mono_yellow_1", "mono_yellow_2", "mono_yellow_3", "mono_yellow_4", "mono_yellow_5", "mono_yellow_6", "mono_yellow_7", "mono_yellow_fireball", "mono_yellow_reflect", "mono_yellow_take_two"}
monoCards.black = {"mono_take_four", "mono_colours"}

-- used to store random order of cards
tableDeck = {}

-- used to track the last played game
roundId = ""

--used to determine if game is in progress
roundInProgress = 0

-- handle the new state of player's inventory
testMonoGame.UpdatePlayerItems = function(pid, checkWin)	
	if roundInProgress == 1 and Players[pid].data.testMono.latestRoundId == roundId then

		-- make sure that all cards are valid playing cards
		testMonoGame.ReplacePlaceholderCards(pid)
		
		-- count the number of player's valid playing cards
		numberOfCards = testMonoGame.CountCards(pid)
		
		-- This is no longer TO-DO, but it stays here because I lost a week of doing ugly -1 hacks to attempt resolving what I then resolved with enableInventoryHandler
		-- DONE: the -1 is ugly workaround hack because something is messed up related to inventory sync, ask David why this is and how to make it work without hax
		-- I lost my patience and I'm not willing to look for proper solutions any more. Get someone who understands TES3MP code better than me to explain this to you
		--if checkWin and numberOfCards -1 == 0 then
		-- HARD MODE: do it without the ugly -1 hack:
		if checkWin and numberOfCards == 0 then
			testMonoGame.PlayerWon(pid)
		elseif numberOfCards > 0 then
			testMonoGame.ReplaceCardsMeshInHand(pid, numberOfCards)
		end
	
		-- TODO: Sorry David, but this has to be here, otherwise CLIENT CRASHES when picking up items with mouse cursor
		-- feel free to explain to me how to make this work without loading whole inventory
		-- OK, I reworked it, so that it does not crash any more, but I'm leaving this here so that the client crashing because of some bizarre case + LoadInventory()/LoadEquipment() is documented
		--Players[pid]:LoadInventory()
		--Players[pid]:LoadEquipment()
		--tes3mp.SendInventoryChanges(pid)
		--tes3mp.ClearInventoryChanges(pid)
	end
end

-- toggle the player's ready state
testMonoGame.TogglePlayerState = function(pid)
	tes3mp.LogMessage(2, "Setting the state variable for ".. Players[pid].data.login.name)
	if Players[pid].data.testMono.status == 0 then
		tes3mp.SendMessage(pid, Players[pid].data.login.name .. " is up for a round of Mono.\n", true)
		Players[pid].data.testMono.status = 1
	else
		tes3mp.SendMessage(pid, Players[pid].data.login.name .. " is no longer up for a round of Mono.\n", true)
		Players[pid].data.testMono.status = 0
	end
end

-- start the round if the conditions are met
testMonoGame.StartRound = function()
	tes3mp.LogMessage(2, "Started the round.")
	
	-- check how many players are in queue
	numberOfParticipants = 0

	for pid, p in pairs(Players) do
		if Players[pid].data.testMono.status == 1 then
			numberOfParticipants = numberOfParticipants + 1
		end
	end
	
	-- check if conditions for starting the new round are met and if the are not return the reason
	if numberOfParticipants == 0 then
		return color.Yellow .. "Looks like nobody wants to play.\n"
	elseif roundInProgress == 1 then
		return color.Yellow .. "How about we wait for the current round to end.\n"
	end	
	
	-- set up round variables
	roundId = os.date("%y%m%d%H%M%S")
	roundInProgress = 1
	
	-- mark all participants with this round's ID
	for pid, p in pairs(Players) do
		if Players[pid].data.testMono.status == 1 then
			Players[pid].data.testMono.latestRoundId = roundId
			--Players[pid]:Save()
			testMonoGame.UpdatePlayerItems(pid, false)
		end
	end

	-- set up random card order for new game
	testMonoGame.FillDeck()

	return numberOfParticipants
end

-- end round and set status of everyone to "not in game"
testMonoGame.EndRound = function()
	tes3mp.LogMessage(2, "Ending the round.")
	for pid, p in pairs(Players) do
		Players[pid].data.testMono.status = 0
		testMonoGame.RemoveAllDeckMeshes(pid)
		Players[pid]:Save()
	end
	roundInProgress = 0
end

-- allow one of the participants to start the round
testMonoGame.CallForRoundStart = function(pid)
	if Players[pid].data.testMono.status == 1 then
		-- contains either reason for round not starting or a number of participants
		roundStartState = testMonoGame.StartRound()

		tes3mp.LogMessage(1, "roundStartState is: " .. roundStartState)
		if type(roundStartState) == "string" then
			-- tell player why the round has not started
			tes3mp.SendMessage(pid, roundStartState, false)
		else
			-- broadcast a message about start of the round
			tes3mp.SendMessage(0, color.Yellow .. "Round of Mono has started with ".. roundStartState .." players\n", true)
		end
	else 
		tes3mp.SendMessage(0, color.Yellow .. "You can't initiate a round that you will not participate in\n", true)
	end
end

-- force end the round
testMonoGame.ForceEndRound = function(pid)
	tes3mp.LogMessage(2, "Player " .. Players[pid].data.login.name .. " forced the end of the round.")
	tes3mp.SendMessage(pid, color.Yellow .. Players[pid].data.login.name .. " says that this round should end.\n", true)
	testMonoGame.EndRound()
end


-- compose deck from which the cards are drawn
testMonoGame.FillDeck = function()
	tes3mp.LogMessage(2, "Filling up deck with cards in random order.")
	
	-- iterate through all cards in monoCards and add each of them to the deck
	for colourIndex, colourCards in pairs(monoCards) do
		for cardIndex, cardName in pairs(colourCards) do
			table.insert(tableDeck, cardName)
		end
	end
	
	-- add some more black cards
	for i=1,3 do
		for cardIndex, cardName in pairs(monoCards.black) do
			table.insert(tableDeck, cardName)
		end
	end

	-- shuffle the deck in order to rndomise draw order
	-- code for shuffling table stolen from Github because bloody LUA doesn't have a built-in function to shuffle array
	size = #tableDeck
	for i = size, 1, -1 do
		rand = math.random(size)
		tableDeck[i], tableDeck[rand] = tableDeck[rand], tableDeck[i]
	end
	
	tes3mp.LogMessage(2, "Finished filling deck.")
end

-- check if player has a next_card in inventory and convert it into actual playing card
testMonoGame.ReplacePlaceholderCards = function(pid)
	tes3mp.LogMessage(2, "Checking for next_card in " .. Players[pid].data.login.name .. "'s inventory.")
	hasNextCard = inventoryHelper.containsItem(Players[pid].data.inventory, "mono_next_card")

	if hasNextCard then
		-- don't assume that player has only one card, replace all next_cards
		tes3mp.LogMessage(2, Players[pid].data.login.name .. " has at least one next_card. All next_cards being replaced.")
		next_card_index = inventoryHelper.getItemIndex(Players[pid].data.inventory, "mono_next_card")
		next_card_count = Players[pid].data.inventory[next_card_index].count
		
		-- make next_card disappear from player's inventory
		testMonoGame.RemovePlaceholderCards(pid, next_card_count)

		-- add specified number of random playing cards to player's inventory
		testMonoGame.AddRandomCards(pid, next_card_count)

		Players[pid]:Save()

	end
end

testMonoGame.RemovePlaceholderCards = function(pid, count)
	tes3mp.LogMessage(2, "Removing next_card from " .. Players[pid].data.login.name)
	Players[pid].data.testMono.enableInventoryHandler = true
	-- IMPORTANT: I lost a week of time end nerves because I didn't have BOTH of the lines below:
	Players[pid]:LoadItemChanges({{refId = "mono_next_card", count = next_card_count, charge = -1, enchantmentCharge = -1, soul = "" }}, enumerations.inventory.REMOVE)
	inventoryHelper.removeItem(Players[pid].data.inventory, "mono_next_card", 1)
	-- the "mono_next_card" did not get cleared well from the player's inventory and despite player not seeing it in inventory window, 
	-- the logic was still there and it kept giving player new card every time it ran
end

testMonoGame.AddRandomCards = function(pid, count)

	new_cards = {}
	for i=1,count do
		table.insert(new_cards, {refId = table.remove(tableDeck, #tableDeck), count = 1, charge = -1, enchantmentCharge = -1, soul = "" })
		if #tableDeck == 0 then
			testMonoGame.FillDeck()
		end
	end
	-- allow inventory to be updated AGAIN -- actually, does LoadItemChanges trigger OnPlayerInventory?
	Players[pid].data.testMono.enableInventoryHandler = true

	tes3mp.LogMessage(2, "Sending changes about newly recieved cards to " .. Players[pid].data.login.name)
	Players[pid]:LoadItemChanges(new_cards, enumerations.inventory.ADD)
	-- new_cards should be the length of next_card_count		
	for i=1,count do
		Players[pid].data.testMono.enableInventoryHandler = true
		inventoryHelper.addItem(Players[pid].data.inventory, new_cards[i].refId, 1, -1, -1)
	end

end

-- check how many item in player's inventory are considered valid playable cards
testMonoGame.CountCards = function(pid)
	tes3mp.LogMessage(2, "Counting cards in inventory of " .. Players[pid].data.login.name .. ".")
	
	-- count the cards in player's inventory
	numberOfCards = 0	
	for itemIndex, item in pairs(Players[pid].data.inventory) do
		for colourIndex, colourCards in pairs(monoCards) do
			for cardIndex, cardName in pairs(colourCards) do
				if item["refId"] == cardName then
					numberOfCards = numberOfCards + 1 * item["count"]
				end
			end
		end
	end

	
	tes3mp.LogMessage(2, Players[pid].data.login.name .. " has " .. numberOfCards .. " cards")
	return numberOfCards
end

-- make mesh in player's hand accurately reflect the state of player's inventory
testMonoGame.ReplaceCardsMeshInHand = function(pid, numberOfCards)
	tes3mp.LogMessage(2, "Running logic for cards in " .. Players[pid].data.login.name .. "'s hand.")
	tes3mp.LogMessage(2, "######################### " .. Players[pid].data.login.name .. " has " .. numberOfCards .. " cards. #######################")
	
	-- some strange nil check
	if not numberOfCards or numberOfCards == 0 then
		tes3mp.LogMessage(4, "Wait what? How? is this nil / 0?")
		tes3mp.SendMessage(0, color.Yellow .. "Something went horribly wrong, yell at testman for writing bad code. Ending current round.\n", true)
		testMonoGame.EndRound()
	end
	
	-- because game represents 4 and more than 4 cards the same way
	if numberOfCards > 4 then
		numberOfCards = 4
	end

	-- check if player has correct deck in hand
	if testMonoGame.DoesPlayerHaveDeckInHand(pid) and testMonoGame.DoesPlayerHaveCorrectDeckInHand(pid, numberOfCards) then
		tes3mp.LogMessage(2, Players[pid].data.login.name .. " already has the correct mesh in hand")
		return 0
	else 
		tes3mp.LogMessage(2, Players[pid].data.login.name .. " needs to get a correct mesh")

		-- remove the deck that player currently holds
		testMonoGame.RemoveAllDeckMeshes(pid)

		-- give player the correct mesh
		testMonoGame.GivePlayerTheDeck(pid, numberOfCards)

		-- make player equip the given deck
		testMonoGame.MakePlayerEquipTheDeck(pid)
	end
	
end


-- make player equip the deck from inventory
testMonoGame.MakePlayerEquipTheDeck = function(pid)
	tes3mp.LogMessage(2, "Making " .. Players[pid].data.login.name .. " equip the given mesh" )
	deckMeshIndex = inventoryHelper.getItemIndex(Players[pid].data.inventory, "mono_deck" .. numberOfCards)
	tes3mp.LogMessage(2, Players[pid].data.login.name .. " has new deck mesh in inventory, in slot "  .. deckMeshIndex )
	Players[pid].data.testMono.enableInventoryHandler = true
	Players[pid].data.equipment[16] = Players[pid].data.inventory[deckMeshIndex]
	Players[pid].data.inventory[deckMeshIndex] = nil
	Players[pid]:LoadEquipment()
end


-- give player the certain mesh
testMonoGame.GivePlayerTheDeck = function(pid, numberOfCards)		
	tes3mp.LogMessage(2, "Giving " .. Players[pid].data.login.name .. " a mesh with " .. numberOfCards .. " cards.")
	Players[pid].data.testMono.enableInventoryHandler = true
	Players[pid]:LoadItemChanges({{refId = "mono_deck" .. numberOfCards, count = 1, charge = -1, enchantmentCharge = -1, soul = "" }}, enumerations.inventory.ADD)
	inventoryHelper.addItem(Players[pid].data.inventory, "mono_deck" .. numberOfCards, 1, -1, -1, "")
	
end


-- check if player has a deck-of-cards-looking mesh in hand
testMonoGame.DoesPlayerHaveDeckInHand = function(pid)
	if Players[pid].data.equipment[16] and string.sub(Players[pid].data.equipment[16].refId, 1, 9) == "mono_deck" then
		return true
	end
	
	return false
end

-- check if mesh in player's hand reflects player's count of numbers in inventory
testMonoGame.DoesPlayerHaveCorrectDeckInHand = function(pid, numberOfCards)
	if Players[pid].data.equipment[16].refId == "mono_deck" .. numberOfCards then
		return true
	end
	
	return false
end

testMonoGame.RemoveAllDeckMeshes = function(pid)
	tes3mp.LogMessage(2, "Removing all meshes from " .. Players[pid].data.login.name .. ".")
	for i=1,4 do
		tempIndex = inventoryHelper.getItemIndex(Players[pid].data.inventory, "mono_deck" .. i)
		if tempIndex then
			tes3mp.LogMessage(2, "Removing mesh " .. i)
			Players[pid].data.testMono.enableInventoryHandler = true
			Players[pid]:LoadItemChanges({{refId = "mono_deck" .. i, count = 1, charge = -1, enchantmentCharge = -1, soul = "" }}, enumerations.inventory.REMOVE)
			inventoryHelper.removeItem(Players[pid].data.inventory, "mono_deck" .. i, 1)
		end
	end
	Players[pid]:Save()
end

-- broadcast message about player winning and end the round
testMonoGame.PlayerWon = function(pid)
	tes3mp.LogMessage(2, "Checking if " .. Players[pid].data.login.name .. " has won.")
	tes3mp.LogMessage(2, "Player " .. Players[pid].data.login.name .. " has won the round of Mono.")
	tes3mp.SendMessage(pid, color.Yellow .. Players[pid].data.login.name .. " has won the round of Mono\n", true)
	testMonoGame.EndRound()
end

-- make player force the end of the round if conditions are met
testMonoGame.ForceEndRound = function(pid)
	tes3mp.LogMessage(2, "Player " .. Players[pid].data.login.name .. " called for the end of the round.")
	if roundInProgress ~= 1 then
		tes3mp.SendMessage(pid, color.Yellow .."There is currently no round in progress.\n", true)
	elseif  Players[pid].data.testMono.latestRoundId ~= roundId then
		tes3mp.SendMessage(pid, color.Yellow .."You are not a participant in the current round.\n", true)
	else
		tes3mp.SendMessage(pid, color.Yellow .. Players[pid].data.login.name .. " says that this round should end.\n", true)
		testMonoGame.EndRound()
	end
end

-- check if player file has data required for game
testMonoGame.CheckPlayerVariables = function(pid)
	tes3mp.LogMessage(2, "Checking existing Mono info in player file of " .. Players[pid].data.login.name .. ".")
	
	if Players[pid].data.testMono == nil then
		testMonoGame.CreatePlayerVariables(pid)
	end
end

-- add required data to player's file
testMonoGame.CreatePlayerVariables = function(pid)
	tes3mp.LogMessage(2, "Creating variables for Mono mechanics for player " .. Players[pid].data.login.name )
	monoInfo = {}
	monoInfo.latestRoundId = ""
	monoInfo.status = 0 -- 0 = not in round of Mono, 1 = in round of Mono or waiting for round to start
	monoInfo.positionInRound = 0
	-- this is set to true when OnObjectPLace is caught, so that it can then allow for one-time activation of OnPLayerInventory
	-- because at the time of OnObjectPLace the inventory is not yet in a state that logic should be handling :(
	monoInfo.enableInventoryHandler = false
	-- used to limit the condition checking to just potential events instead of all inventory-related events
	monoInfo.checkForWin = false
	Players[pid].data.testMono = monoInfo
	Players[pid]:Save()
end

-- make it so that player gets data added when character is created
customEventHooks.registerHandler("OnPlayerEndCharGen", function(eventstatus, pid)
	if Players[pid] ~= nil then
		testMonoGame.CreatePlayerVariables(pid)
	end
end)

-- update player's inventory when player places an item
customEventHooks.registerHandler("OnObjectPlace", function(eventstatus, pid, cellDescription, objects)
	-- SENSITIVE NUCLEAR TEST, THINGS MIGHT EXPLODE:
	Players[pid].data.testMono.enableInventoryHandler = true
	Players[pid].data.testMono.checkForWin = true
	Players[pid]:Save()
	--testMonoGame.UpdatePlayerItems(pid, true)
end)


-- update player's inventory when player picks up an item
customEventHooks.registerHandler("OnObjectDelete", function(eventstatus, pid)
	testMonoGame.UpdatePlayerItems(pid, false)
end)


-- make it so that player can't hide the deck of cards
customEventHooks.registerHandler("OnPlayerItemUse", function(eventstatus, pid)
	testMonoGame.UpdatePlayerItems(pid, false)
end)

-- update player's inventory when player places an item
customEventHooks.registerHandler("OnObjectPlace", function(eventstatus, pid, cellDescription, objects)
	-- mid-test defuse attempt
	Players[pid].data.testMono.enableInventoryHandler = true
	testMonoGame.UpdatePlayerItems(pid, true)
end)

-- make it so that player can't hide the deck of cards
customEventHooks.registerHandler("OnPlayerInventory", function(eventstatus, pid)
	-- SENSITIVE NUCLEAR TEST PART DEUX: ELECTRIC BOOGALOO, THINGS MIGHT EXPLODE:
	if Players[pid].data.testMono.enableInventoryHandler then
		testMonoGame.UpdatePlayerItems(pid, Players[pid].data.testMono.checkForWin)
		Players[pid].data.testMono.enableInventoryHandler = false
		Players[pid].data.testMono.checkForWin = false
		Players[pid]:Save()
	end
end)

-- testman's instant debug script
--[[
testMonoGame.TestmanSuperStart = function(pid)
	Players[pid].data.testMono.status = 1
	testMonoGame.CallForRoundStart(pid)
end
]]


customCommandHooks.registerCommand("mono", testMonoGame.TogglePlayerState)
customCommandHooks.registerCommand("startround", testMonoGame.CallForRoundStart)
customCommandHooks.registerCommand("endround", testMonoGame.ForceEndRound)
--customCommandHooks.registerCommand("x", testMonoGame.TestmanSuperStart)

return testMonoGame
