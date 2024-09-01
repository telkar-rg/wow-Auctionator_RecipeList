local lib = LibStub:NewLibrary("MyLibrary-1.0", "$Revision: 5$")

if not lib then
  return
end

if not lib.frm then
  lib.frm = CreateFrame("Frame")
end

local function GetID(s,t)
	local id
	for k,v in pairs(t) do
		if v==s then
			id = k
		end
	end
	return id
end

lib.frm:RegisterEvent("AUCTION_HOUSE_SHOW")
lib.frm:SetScript("OnEvent", function()
	local neededRecipes = {}

	for ProfileRealmName,charData in pairs(DataStore_CraftsDB["global"]["Characters"]) do
		local _,realm,name = strsplit(".",ProfileRealmName)
		if realm == GetRealmName() then
			for profName,profData in pairs(charData["Professions"]) do
				local profID = GetID(profName,LibTextbookReference["skill"])
				assert(profID,"Profession ID not found.")
				local tsRecipes = {}
				for k,v in pairs(LibTextbookDB) do
					if not v["note"] and                               --skip fake and trainable ones
					v["type"] == "RECIPE" and                          --tradeskill recipes only
					v["reqSkill"] == profID and                        --selected profession only
					v["binding"] ~= 1 and                              --skip BoP ones
					(v["quality"] > 1 or k == 10713 or k == 10644) and --skip white ones (vendored) unles they are engineer created ones
					(not v["reqClasses"] or floor(v["reqClasses"] / 2^GetID(DataStore_CharactersDB["global"]["Characters"][ProfileRealmName]["class"],LibTextbookReference["class"])) % 2 == 1) then  --see if class mask fits
						tsRecipes[v["teachesSpell"]] = k
					end
				end
				for _,str in pairs(profData["Crafts"]) do
					local _,s = strsplit("|",str)
					if s then
						local n = tonumber(s)
						if n then
							tsRecipes[n] = nil --remove if character knows the recipe
						end
					end
				end
				for spell,item in pairs(tsRecipes) do --adding to global list
					neededRecipes[item] = (neededRecipes[item] or 0) + 1
				end
			end
			for _,bag in pairs(DataStore_ContainersDB["global"]["Characters"][ProfileRealmName]["Containers"]) do
				if bag["links"] then
					for _,lnk in pairs(bag["links"]) do --found in bags, subtract one
						local _,s = strsplit(":",lnk)
						local id = tonumber(s)
						if id then
							neededRecipes[id] = (neededRecipes[id] or 0) - 1
						end
					end
				end
			end
			for _,mail in pairs(DataStore_MailsDB["global"]["Characters"][ProfileRealmName]["Mails"]) do
				if mail["link"] then
					local _,s = strsplit(":",mail["link"]) --found in mail, subtract one
					local id = tonumber(s)
					if id then
						neededRecipes[id] = (neededRecipes[id] or 0) - 1
					end
				end
			end
		end
	end
	
	local done = false
	while not done do --delete all existing lists
		local p = 0
		for i=1,#AUCTIONATOR_SHOPPING_LISTS do
			if AUCTIONATOR_SHOPPING_LISTS[i]["name"]=="Textbook:Recipes" then
				p = i
			end
		end
		if p > 0 then
			table.remove(AUCTIONATOR_SHOPPING_LISTS,p)
		else
			done = true
		end
	end

	local slist = Atr_SList.create("Textbook:Recipes") --make a fresh list and fill it
	for item,count in pairs(neededRecipes) do
		if count and count > 0 then
			slist:AddItem(LibTextbookDB[item]["itemName"])
		end
	end
end)
