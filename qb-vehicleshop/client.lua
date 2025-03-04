-- Variables
local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData()
local testDriveZone = nil
local vehicleMenu = {}
local Initialized = false
local testDriveVeh, inTestDrive = 0, false
local ClosestVehicle = 1
local zones = {}
local insideShop, tempShop = nil, nil

-- Handlers
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    local citizenid = PlayerData.citizenid
    TriggerServerEvent('qb-vehicleshop:server:addPlayer', citizenid)
    TriggerServerEvent('qb-vehicleshop:server:checkFinance')
    if not Initialized then Init() end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    local citizenid = PlayerData.citizenid
    TriggerServerEvent('qb-vehicleshop:server:removePlayer', citizenid)
    PlayerData = {}
end)

-- Static Headers
local vehHeaderMenu = {
    {
        header = Lang:t('menus.vehHeader_header'),
        txt = Lang:t('menus.vehHeader_txt'),
        icon = "fa-solid fa-car",
        params = {
            event = 'qb-vehicleshop:client:showVehOptions'
        }
    }
}

local financeMenu = {
    {
        header = Lang:t('menus.financed_header'),
        txt = Lang:t('menus.finance_txt'),
        icon = "fa-solid fa-user-ninja",
        params = {
            event = 'qb-vehicleshop:client:getVehicles'
        }
    }
}

local returnTestDrive = {
    {
        header = Lang:t('menus.returnTestDrive_header'),
        icon = "fa-solid fa-flag-checkered",
        params = {
            event = 'qb-vehicleshop:client:TestDriveReturn'
        }
    }
}

-- Functions
local function drawTxt(text, font, x, y, scale, r, g, b, a)
    SetTextFont(font)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextCentre(1)
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

local function comma_value(amount)
    local formatted = amount
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end
    return formatted
end

local function getVehName()
    local shop = Config.Shops[insideShop]
    if not shop or not shop["ShowroomVehicles"] then
        return ""
    end

    local vehicle = shop["ShowroomVehicles"][ClosestVehicle]
    if not vehicle or not vehicle.chosenVehicle then
        return ""
    end

    return QBCore.Shared.Vehicles[vehicle.chosenVehicle]['name']
end

local function getVehPrice()
    local shop = Config.Shops[insideShop]
    if not shop or not shop["ShowroomVehicles"] then
        return ""
    end

    local vehicle = shop["ShowroomVehicles"][ClosestVehicle]
    if not vehicle or not vehicle.chosenVehicle then
        return ""
    end

    return QBCore.Shared.Vehicles[vehicle.chosenVehicle]['price']
end

local function getVehBrand()
    local shop = Config.Shops[insideShop]
    if not shop or not shop["ShowroomVehicles"] then
        return ""
    end

    local vehicle = shop["ShowroomVehicles"][ClosestVehicle]
    if not vehicle or not vehicle.chosenVehicle then
        return ""
    end

    return QBCore.Shared.Vehicles[vehicle.chosenVehicle]['brand']
end


local function setClosestShowroomVehicle()
    local pos = GetEntityCoords(PlayerPedId(), true)
    local current = nil
    local dist = nil
    local closestShop = insideShop
    for id in pairs(Config.Shops[closestShop]["ShowroomVehicles"]) do
        local dist2 = #(pos - vector3(Config.Shops[closestShop]["ShowroomVehicles"][id].coords.x, Config.Shops[closestShop]["ShowroomVehicles"][id].coords.y, Config.Shops[closestShop]["ShowroomVehicles"][id].coords.z))
        if current then
            if dist2 < dist then
                current = id
                dist = dist2
            end
        else
            dist = dist2
            current = id
        end
    end
    if current ~= ClosestVehicle then
        ClosestVehicle = current
    end
end

local function createTestDriveReturn()
    testDriveZone = BoxZone:Create(
        Config.Shops[insideShop]["ReturnLocation"],
        3.0,
        5.0,
        {
            name = "box_zone_testdrive_return_" .. insideShop,
        })

    testDriveZone:onPlayerInOut(function(isPointInside)
        if isPointInside and IsPedInAnyVehicle(PlayerPedId()) then
            SetVehicleForwardSpeed(GetVehiclePedIsIn(PlayerPedId(), false), 0)
            exports['qb-menu']:openMenu(returnTestDrive)
        else
            exports['qb-menu']:closeMenu()
        end
    end)
end

local function startTestDriveTimer(testDriveTime, prevCoords)
    local gameTimer = GetGameTimer()
    CreateThread(function()
	Wait(2000) -- Avoids the condition to run before entering vehicle
        while inTestDrive do
            if GetGameTimer() < gameTimer + tonumber(1000 * testDriveTime) then
                local secondsLeft = GetGameTimer() - gameTimer
                if secondsLeft >= tonumber(1000 * testDriveTime) - 20 or GetPedInVehicleSeat(NetToVeh(testDriveVeh), -1) ~= PlayerPedId() then
                    TriggerServerEvent('qb-vehicleshop:server:deleteVehicle', testDriveVeh)
                    testDriveVeh = 0
                    inTestDrive = false
                    SetEntityCoords(PlayerPedId(), prevCoords)
                    QBCore.Functions.Notify(Lang:t('general.testdrive_complete'))
                end
                drawTxt(Lang:t('general.testdrive_timer') .. math.ceil(testDriveTime - secondsLeft / 1000), 4, 0.5, 0.93, 0.50, 255, 255, 255, 180)
            end
            Wait(0)
        end
    end)
end

local function createVehZones(shopName, entity)
    if not Config.UsingTarget then
        for i = 1, #Config.Shops[shopName]['ShowroomVehicles'] do
            zones[#zones + 1] = BoxZone:Create(
                vector3(Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].x,
                    Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].y,
                    Config.Shops[shopName]['ShowroomVehicles'][i]['coords'].z),
                Config.Shops[shopName]['Zone']['size'],
                Config.Shops[shopName]['Zone']['size'],
                {
                    name = "box_zone_" .. shopName .. "_" .. i,
                    minZ = Config.Shops[shopName]['Zone']['minZ'],
                    maxZ = Config.Shops[shopName]['Zone']['maxZ'],
                    debugPoly = false,
                })
        end
        local combo = ComboZone:Create(zones, {name = "vehCombo", debugPoly = false})
        combo:onPlayerInOut(function(isPointInside)
            if isPointInside then
                if PlayerData and PlayerData.job and (PlayerData.job.name == Config.Shops[insideShop]['Job'] or Config.Shops[insideShop]['Job'] == 'none') then
                    exports['qb-menu']:showHeader(vehHeaderMenu)
                end
            else
                exports['qb-menu']:closeMenu()
            end
        end)
    else
        exports['qb-target']:AddTargetEntity(entity, {
            options = {
                {
                    type = "client",
                    event = "qb-vehicleshop:client:showVehOptions",
                    icon = "fas fa-car",
                    label = Lang:t('general.vehinteraction'),
                    canInteract = function()
                        local closestShop = insideShop
                        return closestShop and (Config.Shops[closestShop]['Job'] == 'none' or PlayerData.job.name == Config.Shops[closestShop]['Job'])
                    end
                },
            },
            distance = 3.0
        })
    end
end

-- Zones
function createFreeUseShop(shopShape, name)
    local zone = PolyZone:Create(shopShape, {
        name = name,
        minZ = shopShape.minZ,
        maxZ = shopShape.maxZ
    })

    zone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            insideShop = name
            CreateThread(function()
                while insideShop do
                    setClosestShowroomVehicle()
                    local carstock = nil
                    local chosenVehicle = Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle]
                    if chosenVehicle then -- add this check to make sure chosenVehicle is not nil
                        QBCore.Functions.TriggerCallback('qb-vehicleshop:server:checkstock', function(stock)
                            if stock then
                                for _, v in pairs(stock) do
                                    if chosenVehicle.chosenVehicle == v.car then
                                        carstock = v.stock
                                    end
                                end
                            end
                        end)
                        while carstock == nil do
                            Wait(10)
                        end
                    vehicleMenu = {
                        {
                            isMenuHeader = true,
                            icon = "fa-solid fa-circle-info",
                            header = getVehBrand():upper() .. ' ' .. getVehName():upper() .. ' - $' .. getVehPrice(),
                            txt = "Stock: " .. carstock
                        },
                        {
                            header = Lang:t('menus.test_header'),
                            txt = Lang:t('menus.freeuse_test_txt'),
                            icon = "fa-solid fa-car-on",
                            params = {
                                event = 'qb-vehicleshop:client:TestDrive',
                            }
                        },
                        {
                            header = Lang:t('menus.freeuse_buy_header'),
                            txt = Lang:t('menus.freeuse_buy_txt'),
                            icon = "fa-solid fa-hand-holding-dollar",
                            params = {
                                isServer = true,
                                event = 'qb-vehicleshop:server:buyShowroomVehicle',
                                args = {
                                    buyVehicle = Config.Shops[insideShop] and Config.Shops[insideShop]["ShowroomVehicles"] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle or nil,
                                    stock = carstock
                                }
                            },
                            disabled = carstock <= 0
                        },
                        {
                            header = Lang:t('menus.finance_header'),
                            txt = Lang:t('menus.freeuse_finance_txt'),
                            icon = "fa-solid fa-coins",
                            params = {
                                event = 'qb-vehicleshop:client:openFinance',
                                args = {
                                    price = getVehPrice(),
                                    buyVehicle = Config.Shops[insideShop] and Config.Shops[insideShop]["ShowroomVehicles"] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle or nil,
                                    stock = carstock
                                }
                            },
                            disabled = carstock <= 0 -- add this line to disable the button if carstock is 0 or less
                        },
                        {
                            header = Lang:t('menus.swap_header'),
                            txt = Lang:t('menus.swap_txt'),
                            icon = "fa-solid fa-arrow-rotate-left",
                            params = {
                                event = 'qb-vehicleshop:client:vehCategories',
                            }
                        },
                    }
                    -- check if carstock is less than 2 and adds the "order" button to the menu if true
                    if carstock < 2 then
                        table.insert(vehicleMenu, {
                            header = Lang:t('menus.order_header'),
                            txt = Lang:t('menus.order_txt'),
                            icon = "fa-solid fa-envelope",
                            params = {
                                isServer = true,
                                event = 'qb-vehicleshop:client:orderVehicle',
                                args = {
                                    buyVehicle = Config.Shops[insideShop] and Config.Shops[insideShop]["ShowroomVehicles"] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle or nil,
                                    carStock = carstock
                                }
                            }
                        })
                    end
                    -- check if the player has the cardealer job and adds the "buy_stock" button to the menu if true
                    if QBCore.Functions.GetPlayerData().job.name == "cardealer" then
                        table.insert(vehicleMenu, {
                            header = Lang:t('menus.buy_stock'),
                            txt = Lang:t('menus.buy_stock_txt'),
                            icon = "fa-solid fa-envelope",
                            params = {
                                isServer = true,
                                event = 'qb-vehicleshop:server:buy-stock',
                                args = {
                                    buyVehicle = Config.Shops[insideShop] and Config.Shops[insideShop]["ShowroomVehicles"] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle or nil,
                                }
                            },
                            disabled = not (QBCore.Functions.GetPlayerData().job.name == "cardealer") -- replace "your_job_name" with the name of your job
                        })
                    end
                else
                    Wait(1000) -- wait for a second and try again
                end
            end
            end)
        else
            insideShop = nil
            ClosestVehicle = 1
        end
    end)
end

RegisterNetEvent('qb-vehicleshop:client:orderVehicle')
AddEventHandler('qb-vehicleshop:client:orderVehicle', function(message)
    local discord_webhook = "https://discord.com/api/webhooks/1083827004920561714/i7STkfP8LH9OUQNB3oicvByuUTgJLX1frMG4OlShG2FSp4XwwiZOR_j-81v_SjGlPkkp"
    local discord_message = "A vehicle has been ordered at " .. insideShop .. "." -- customize the message as needed
    local discord_payload = {
        username = "Vehicle Shop",
        content = discord_message
    }
    SendWebhookMessage(discord_webhook, json.encode(discord_payload), function(success, errorMessage)
        if success then
            print("Discord webhook sent successfully!")
        else
            print("Error sending Discord webhook: " .. errorMessage)
        end
    end)
end)



function createManagedShop(shopShape, name)
    local zone = PolyZone:Create(shopShape, {
        name = name,
        minZ = shopShape.minZ,
        maxZ = shopShape.maxZ
    })

    zone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            insideShop = name
            CreateThread(function()
                while insideShop and PlayerData.job and PlayerData.job.name == Config.Shops[name]['Job'] do
                    setClosestShowroomVehicle()
                    local carstock = nil
                    local chosenVehicle = Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle]
                    if chosenVehicle then -- add this check to make sure chosenVehicle is not nil
                        QBCore.Functions.TriggerCallback('qb-vehicleshop:server:checkstock', function(stock)
                            if stock then
                                for _, v in pairs(stock) do
                                    if chosenVehicle.chosenVehicle == v.car then
                                        carstock = v.stock
                                    end
                                end
                            end
                        end)
                        while carstock == nil do
                            Wait(10)
                        end
                    vehicleMenu = {
                        {
                            isMenuHeader = true,
                            icon = "fa-solid fa-circle-info",
                            header = getVehBrand():upper() .. ' ' .. getVehName():upper() .. ' - $' .. getVehPrice(),
                            txt = "Stock: " .. carstock
                        },
                        {
                            header = Lang:t('menus.test_header'),
                            txt = Lang:t('menus.managed_test_txt'),
                            icon = "fa-solid fa-user-plus",
                            params = {
                                event = 'qb-vehicleshop:client:openIdMenu',
                                args = {
                                    vehicle = Config.Shops[insideShop] and Config.Shops[insideShop]["ShowroomVehicles"] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle or nil,
                                    type = 'testDrive'
                                }
                            }
                        },
                        {
                            header = Lang:t('menus.managed_sell_header'),
                            txt = Lang:t('menus.managed_sell_txt'),
                            icon = "fa-solid fa-cash-register",
                            params = {
                                event = 'qb-vehicleshop:client:openIdMenu',
                                args = {
                                    vehicle = Config.Shops[insideShop] and Config.Shops[insideShop]["ShowroomVehicles"] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle or nil,
                                    type = 'sellVehicle',
                                    stock = carstock
                                }
                            },
                            disabled = carstock <= 0
                        },
                        {
                            header = Lang:t('menus.finance_header'),
                            txt = Lang:t('menus.managed_finance_txt'),
                            icon = "fa-solid fa-coins",
                            params = {
                                event = 'qb-vehicleshop:client:openCustomFinance',
                                args = {
                                    price = getVehPrice(),
                                    vehicle = Config.Shops[insideShop] and Config.Shops[insideShop]["ShowroomVehicles"] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle or nil,
                                    stock = carstock
                                }
                            },
                            disabled = carstock <= 0
                        },
                        {
                            header = Lang:t('menus.swap_header'),
                            txt = Lang:t('menus.swap_txt'),
                            icon = "fa-solid fa-arrow-rotate-left",
                            params = {
                                event = 'qb-vehicleshop:client:vehCategories',
                                }
                            },
                        }
                        if QBCore.Functions.GetPlayerData().job.name == "cardealer" then
                            table.insert(vehicleMenu, {
                                header = Lang:t('menus.buy_stock'),
                                txt = Lang:t('menus.buy_stock_txt'),
                                icon = "fa-solid fa-envelope",
                                params = {
                                    isServer = true,
                                    event = 'qb-vehicleshop:server:buy-stock',
                                    args = {
                                        buyVehicle = Config.Shops[insideShop] and Config.Shops[insideShop]["ShowroomVehicles"] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle] and Config.Shops[insideShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle or nil,
                                    }
                                },
                                disabled = not (QBCore.Functions.GetPlayerData().job.name == "cardealer") -- replace "your_job_name" with the name of your job
                            })
                        end
                    else
                        Wait(1000) -- wait for a second and try again
                    end
                end
            end)
        else
            insideShop = nil
            ClosestVehicle = 1
        end
    end)
end

function Init()
    Initialized = true
    CreateThread(function()
        for name, shop in pairs(Config.Shops) do
            if shop['Type'] == 'free-use' then
                createFreeUseShop(shop['Zone']['Shape'], name)
            elseif shop['Type'] == 'managed' then
                createManagedShop(shop['Zone']['Shape'], name)
            end
        end
    end)
    CreateThread(function()
        local financeZone = BoxZone:Create(Config.FinanceZone, 2.0, 2.0, {
            name = "vehicleshop_financeZone",
            offset = {0.0, 0.0, 0.0},
            scale = {1.0, 1.0, 1.0},
            minZ = Config.FinanceZone.z - 1,
            maxZ = Config.FinanceZone.z + 1,
            debugPoly = false,
        })

        financeZone:onPlayerInOut(function(isPointInside)
            if isPointInside then
                exports['qb-menu']:showHeader(financeMenu)
            else
                exports['qb-menu']:closeMenu()
            end
        end)
    end)
    CreateThread(function()
        for k in pairs(Config.Shops) do
            for i = 1, #Config.Shops[k]['ShowroomVehicles'] do
                local model = GetHashKey(Config.Shops[k]["ShowroomVehicles"][i].defaultVehicle)
                RequestModel(model)
                while not HasModelLoaded(model) do
                    Wait(0)
                end
                local veh = CreateVehicle(model, Config.Shops[k]["ShowroomVehicles"][i].coords.x, Config.Shops[k]["ShowroomVehicles"][i].coords.y, Config.Shops[k]["ShowroomVehicles"][i].coords.z, false, false)
                SetModelAsNoLongerNeeded(model)
                SetVehicleOnGroundProperly(veh)
                SetEntityInvincible(veh, true)
                SetVehicleDirtLevel(veh, 0.0)
                SetVehicleDoorsLocked(veh, 3)
                SetEntityHeading(veh, Config.Shops[k]["ShowroomVehicles"][i].coords.w)
                FreezeEntityPosition(veh, true)
                SetVehicleNumberPlateText(veh, 'BUY ME')
                if Config.UsingTarget then createVehZones(k, veh) end
            end
            if not Config.UsingTarget then createVehZones(k) end
        end
    end)
end

-- Events
RegisterNetEvent('qb-vehicleshop:client:homeMenu', function()
    exports['qb-menu']:openMenu(vehicleMenu)
end)

RegisterNetEvent('qb-vehicleshop:client:showVehOptions', function()
    exports['qb-menu']:openMenu(vehicleMenu)
end)

RegisterNetEvent('qb-vehicleshop:client:TestDrive', function()
    if not inTestDrive and ClosestVehicle ~= 0 then
        inTestDrive = true
        local prevCoords = GetEntityCoords(PlayerPedId())
        tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
        QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
            local veh = NetToVeh(netId)
            exports['LegacyFuel']:SetFuel(veh, 100)
            SetVehicleNumberPlateText(veh, 'TESTDRIVE')
            SetEntityHeading(veh, Config.Shops[tempShop]["TestDriveSpawn"].w)
            TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
            testDriveVeh = netId
            QBCore.Functions.Notify(Lang:t('general.testdrive_timenoti', {testdrivetime = Config.Shops[tempShop]["TestDriveTimeLimit"]}))
        end, Config.Shops[tempShop]["ShowroomVehicles"][ClosestVehicle].chosenVehicle, Config.Shops[tempShop]["TestDriveSpawn"], true)
        createTestDriveReturn()
        startTestDriveTimer(Config.Shops[tempShop]["TestDriveTimeLimit"] * 60, prevCoords)
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_alreadyin'), 'error')
    end
end)

RegisterNetEvent('qb-vehicleshop:client:customTestDrive', function(data)
    if not inTestDrive then
        inTestDrive = true
        local vehicle = data
        local prevCoords = GetEntityCoords(PlayerPedId())
        tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
        QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
            local veh = NetToVeh(netId)
            exports['LegacyFuel']:SetFuel(veh, 100)
            SetVehicleNumberPlateText(veh, 'TESTDRIVE')
            SetEntityHeading(veh, Config.Shops[tempShop]["TestDriveSpawn"].w)
            TriggerEvent('vehiclekeys:client:SetOwner', QBCore.Functions.GetPlate(veh))
            testDriveVeh = netId
            QBCore.Functions.Notify(Lang:t('general.testdrive_timenoti', {testdrivetime = Config.Shops[tempShop]["TestDriveTimeLimit"]}))
        end, vehicle, Config.Shops[tempShop]["TestDriveSpawn"], true)
        createTestDriveReturn()
        startTestDriveTimer(Config.Shops[tempShop]["TestDriveTimeLimit"] * 60, prevCoords)
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_alreadyin'), 'error')
    end
end)

RegisterNetEvent('qb-vehicleshop:client:TestDriveReturn', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped)
    local entity = NetworkGetEntityFromNetworkId(testDriveVeh)
    if veh == entity then
        testDriveVeh = 0
        inTestDrive = false
        DeleteEntity(veh)
        exports['qb-menu']:closeMenu()
        testDriveZone:destroy()
    else
        QBCore.Functions.Notify(Lang:t('error.testdrive_return'), 'error')
    end
end)

RegisterNetEvent('qb-vehicleshop:client:vehCategories', function()
	local catmenu = {}
    local categoryMenu = {
        {
            header = Lang:t('menus.goback_header'),
            icon = "fa-solid fa-angle-left",
            params = {
                event = 'qb-vehicleshop:client:homeMenu'
            }
        }
    }
	for k, v in pairs(QBCore.Shared.Vehicles) do
        if type(QBCore.Shared.Vehicles[k]["shop"]) == 'table' then
            for _, shop in pairs(QBCore.Shared.Vehicles[k]["shop"]) do
                if shop == insideShop then
                    catmenu[v.category] = v.category
                end
            end
        elseif QBCore.Shared.Vehicles[k]["shop"] == insideShop then
                catmenu[v.category] = v.category
        end
    end
    for k, v in pairs(catmenu) do
        categoryMenu[#categoryMenu + 1] = {
            header = v,
            icon = "fa-solid fa-circle",
            params = {
                event = 'qb-vehicleshop:client:openVehCats',
                args = {
                    catName = k
                }
            }
        }
    end
    exports['qb-menu']:openMenu(categoryMenu)
end)

RegisterNetEvent('qb-vehicleshop:client:openVehCats', function(data)
    local vehMenu = {
        {
            header = Lang:t('menus.goback_header'),
            icon = "fa-solid fa-angle-left",
            params = {
                event = 'qb-vehicleshop:client:vehCategories'
            }
        }
    }
    for k, v in pairs(QBCore.Shared.Vehicles) do
        if QBCore.Shared.Vehicles[k]["category"] == data.catName then
            if type(QBCore.Shared.Vehicles[k]["shop"]) == 'table' then
                for _, shop in pairs(QBCore.Shared.Vehicles[k]["shop"]) do
                    if shop == insideShop then
                        vehMenu[#vehMenu + 1] = {
                            header = v.name,
                            txt = Lang:t('menus.veh_price') .. v.price,
                            icon = "fa-solid fa-car-side",
                            params = {
                                isServer = true,
                                event = 'qb-vehicleshop:server:swapVehicle',
                                args = {
                                    toVehicle = v.model,
                                    ClosestVehicle = ClosestVehicle,
                                    ClosestShop = insideShop
                                }
                            }
                        }
                    end
                end
            elseif QBCore.Shared.Vehicles[k]["shop"] == insideShop then
                vehMenu[#vehMenu + 1] = {
                    header = v.name,
                    txt = Lang:t('menus.veh_price') .. v.price,
                    icon = "fa-solid fa-car-side",
                    params = {
                        isServer = true,
                        event = 'qb-vehicleshop:server:swapVehicle',
                        args = {
                            toVehicle = v.model,
                            ClosestVehicle = ClosestVehicle,
                            ClosestShop = insideShop
                        }
                    }
                }
            end
        end
    end
    exports['qb-menu']:openMenu(vehMenu)
end)

RegisterNetEvent('qb-vehicleshop:client:openFinance', function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = getVehBrand():upper() .. ' ' .. data.buyVehicle:upper() .. ' - $' .. data.price,
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'downPayment',
                text = Lang:t('menus.financesubmit_downpayment') .. Config.MinimumDown .. '%'
            },
            {
                type = 'number',
                isRequired = true,
                name = 'paymentAmount',
                text = Lang:t('menus.financesubmit_totalpayment') .. Config.MaximumPayments
            }
        }
    })
    if dialog then
        if not dialog.downPayment or not dialog.paymentAmount then return end
        TriggerServerEvent('qb-vehicleshop:server:financeVehicle', dialog.downPayment, dialog.paymentAmount, data.buyVehicle, data.stock)
    end
end)

RegisterNetEvent('qb-vehicleshop:client:openCustomFinance', function(data)
    TriggerEvent('animations:client:EmoteCommandStart', {"tablet2"})
    local dialog = exports['qb-input']:ShowInput({
        header = getVehBrand():upper() .. ' ' .. data.vehicle:upper() .. ' - $' .. data.price,
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'downPayment',
                text = Lang:t('menus.financesubmit_downpayment') .. Config.MinimumDown .. '%'
            },
            {
                type = 'number',
                isRequired = true,
                name = 'paymentAmount',
                text = Lang:t('menus.financesubmit_totalpayment') .. Config.MaximumPayments
            },
            {
                text = Lang:t('menus.submit_ID'),
                name = "playerid",
                type = "number",
                isRequired = true
            }
        }
    })
    if dialog then
        if not dialog.downPayment or not dialog.paymentAmount or not dialog.playerid then return end
        TriggerEvent('animations:client:EmoteCommandStart', {"c"})
        TriggerServerEvent('qb-vehicleshop:server:sellfinanceVehicle', dialog.downPayment, dialog.paymentAmount, data.vehicle, dialog.playerid)
    end
end)

RegisterNetEvent('qb-vehicleshop:client:swapVehicle', function(data)
    local shopName = data.ClosestShop
    if Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].chosenVehicle ~= data.toVehicle then
        local closestVehicle, closestDistance = QBCore.Functions.GetClosestVehicle(vector3(Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].coords.x, Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].coords.y, Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].coords.z))
        if closestVehicle == 0 then return end
        if closestDistance < 5 then DeleteEntity(closestVehicle) end
        while DoesEntityExist(closestVehicle) do
            Wait(50)
        end
        Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].chosenVehicle = data.toVehicle
        local model = GetHashKey(data.toVehicle)
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(50)
        end
        local veh = CreateVehicle(model, Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].coords.x, Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].coords.y, Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].coords.z, false, false)
        while not DoesEntityExist(veh) do
            Wait(50)
        end
        SetModelAsNoLongerNeeded(model)
        SetVehicleOnGroundProperly(veh)
        SetEntityInvincible(veh, true)
        SetEntityHeading(veh, Config.Shops[shopName]["ShowroomVehicles"][data.ClosestVehicle].coords.w)
        SetVehicleDoorsLocked(veh, 3)
        FreezeEntityPosition(veh, true)
        SetVehicleNumberPlateText(veh, 'BUY ME')
        if Config.UsingTarget then createVehZones(shopName, veh) end
    end
end)

RegisterNetEvent('qb-vehicleshop:client:buyShowroomVehicle', function(vehicle, plate)
    tempShop = insideShop -- temp hacky way of setting the shop because it changes after the callback has returned since you are outside the zone
    QBCore.Functions.TriggerCallback('QBCore:Server:SpawnVehicle', function(netId)
        local veh = NetToVeh(netId)
        exports['LegacyFuel']:SetFuel(veh, 100)
        SetVehicleNumberPlateText(veh, plate)
        SetEntityHeading(veh, Config.Shops[tempShop]["VehicleSpawn"].w)
        TriggerEvent("vehiclekeys:client:SetOwner", QBCore.Functions.GetPlate(veh))
        TriggerServerEvent("qb-vehicletuning:server:SaveVehicleProps", QBCore.Functions.GetVehicleProperties(veh))
    end, vehicle, Config.Shops[tempShop]["VehicleSpawn"], true)
end)

RegisterNetEvent('qb-vehicleshop:client:getVehicles', function()
    QBCore.Functions.TriggerCallback('qb-vehicleshop:server:getVehicles', function(vehicles)
        local ownedVehicles = {}
        for _, v in pairs(vehicles) do
            if v.balance ~= 0 then
                local name = QBCore.Shared.Vehicles[v.vehicle]["name"]
                local plate = v.plate:upper()
                ownedVehicles[#ownedVehicles + 1] = {
                    header = name,
                    txt = Lang:t('menus.veh_platetxt') .. plate,
                    icon = "fa-solid fa-car-side",
                    params = {
                        event = 'qb-vehicleshop:client:getVehicleFinance',
                        args = {
                            vehiclePlate = plate,
                            balance = v.balance,
                            paymentsLeft = v.paymentsleft,
                            paymentAmount = v.paymentamount
                        }
                    }
                }
            end
        end
        if #ownedVehicles > 0 then
            exports['qb-menu']:openMenu(ownedVehicles)
        else
            QBCore.Functions.Notify(Lang:t('error.nofinanced'), 'error', 7500)
        end
    end)
end)

RegisterNetEvent('qb-vehicleshop:client:getVehicleFinance', function(data)
    local vehFinance = {
        {
            header = Lang:t('menus.goback_header'),
            params = {
                event = 'qb-vehicleshop:client:getVehicles'
            }
        },
        {
            isMenuHeader = true,
            icon = "fa-solid fa-sack-dollar",
            header = Lang:t('menus.veh_finance_balance'),
            txt = Lang:t('menus.veh_finance_currency') .. comma_value(data.balance)
        },
        {
            isMenuHeader = true,
            icon = "fa-solid fa-hashtag",
            header = Lang:t('menus.veh_finance_total'),
            txt = data.paymentsLeft
        },
        {
            isMenuHeader = true,
            icon = "fa-solid fa-sack-dollar",
            header = Lang:t('menus.veh_finance_reccuring'),
            txt = Lang:t('menus.veh_finance_currency') .. comma_value(data.paymentAmount)
        },
        {
            header = Lang:t('menus.veh_finance_pay'),
            icon = "fa-solid fa-hand-holding-dollar",
            params = {
                event = 'qb-vehicleshop:client:financePayment',
                args = {
                    vehData = data,
                    paymentsLeft = data.paymentsleft,
                    paymentAmount = data.paymentamount
                }
            }
        },
        {
            header = Lang:t('menus.veh_finance_payoff'),
            icon = "fa-solid fa-hand-holding-dollar",
            params = {
                isServer = true,
                event = 'qb-vehicleshop:server:financePaymentFull',
                args = {
                    vehBalance = data.balance,
                    vehPlate = data.vehiclePlate
                }
            }
        },
    }
    exports['qb-menu']:openMenu(vehFinance)
end)

RegisterNetEvent('qb-vehicleshop:client:financePayment', function(data)
    local dialog = exports['qb-input']:ShowInput({
        header = Lang:t('menus.veh_finance'),
        submitText = Lang:t('menus.veh_finance_pay'),
        inputs = {
            {
                type = 'number',
                isRequired = true,
                name = 'paymentAmount',
                text = Lang:t('menus.veh_finance_payment')
            }
        }
    })
    if dialog then
        if not dialog.paymentAmount then return end
        TriggerServerEvent('qb-vehicleshop:server:financePayment', dialog.paymentAmount, data.vehData)
    end
end)

RegisterNetEvent('qb-vehicleshop:client:openIdMenu', function(data, stock)
    local vehicle = data.vehicle
    local type = data.type
    local stock = data.stock
    local dialog = exports['qb-input']:ShowInput({
        header = QBCore.Shared.Vehicles[data.vehicle]["name"],
        submitText = Lang:t('menus.submit_text'),
        inputs = {
            {
                text = Lang:t('menus.submit_ID'),
                name = "playerid",
                type = "number",
                isRequired = true
            }
        }
    })
    if dialog then
        if not dialog.playerid then return end
        if data.type == 'testDrive' then
            TriggerServerEvent('qb-vehicleshop:server:customTestDrive', data.vehicle, dialog.playerid, data.stock)
        elseif data.type == 'sellVehicle' then
            print(stock)
            TriggerServerEvent('qb-vehicleshop:server:sellShowroomVehicle', data.vehicle, dialog.playerid, data.stock)
        end
    end
end)

-- Threads
CreateThread(function()
    for k, v in pairs(Config.Shops) do
        if v.showBlip then
            local Dealer = AddBlipForCoord(Config.Shops[k]["Location"])
            SetBlipSprite(Dealer, Config.Shops[k]["blipSprite"])
            SetBlipDisplay(Dealer, 4)
            SetBlipScale(Dealer, 0.70)
            SetBlipAsShortRange(Dealer, true)
            SetBlipColour(Dealer, Config.Shops[k]["blipColor"])
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(Config.Shops[k]["ShopLabel"])
            EndTextCommandSetBlipName(Dealer)
        end
    end
end)



--------------------------------------------------------------------
local purchasedvehicle = nil
local pickupblip = nil


RegisterCommand('setstock', function()
    TriggerServerEvent('qb-vehicleshop:server:updatestock')
end)

RegisterNetEvent('qb-vehicleshop:client:create_blip', function(vehicle)
    onmission = true
    ccarid = k
    local shopData = Config.Shops[insideShop]['pickupblip']
    local coords = vector3(shopData.x, shopData.y, shopData.z)
        pickupblip = AddBlipForCoord(vector3(shopData.x,shopData.y,shopData.z))
        SetBlipSprite(pickupblip, 1)
        SetBlipDisplay(pickupblip, 2)
        SetBlipScale(pickupblip, 1.0)
        SetBlipAsShortRange(pickupblip, false)
        SetBlipColour(pickupblip, 0)
        BeginTextCommandSetBlipName("Drop off")
        EndTextCommandSetBlipName(pickupblip)
        SetBlipRoute(pickupblip, true)
    ondelivery = true
    plate = splate
    TriggerEvent("qb-vehicleshop:client:buystock", vehicle)
    TriggerEvent("qb-vehicleshop:client:checkdistance", coords, k, insideShop)
end)


------------ vehicle pickup
CreateThread(function()
    RegisterNetEvent('qb-vehicleshop:client:checkdistance', function(coords, k, shop)
        local ondelivery = true
        while ondelivery do
            Citizen.Wait(1)
            local playerPed = PlayerPedId()
            if not DoesEntityExist(playerPed) then return end -- Check if the playerPed is valid
            local pos = GetEntityCoords(playerPed)
            local pickupCoords = vector3(coords.x, coords.y, coords.z)
            if Vdist(pos, pickupCoords) < 5 then
                TriggerEvent('qb-vehicleshop:client:removeblip')
                TriggerEvent('qb-vehicleshop:client:create_delevery_blip', k, shop)
                ondelivery = false
                dropoff = true
                break
            end
        end
    end)
end)

------------ Blip for delevery 
CreateThread(function()
    RegisterNetEvent('qb-vehicleshop:client:checkdeleverydistance', function(coords, vehicle)
        while true do
            Citizen.Wait(1)
            veh = GetVehiclePedIsIn(PlayerPedId())
            local pos = GetEntityCoords(PlayerPedId(), true)
            if #(pos - vector3(coords.x, coords.y, coords.z)) < 5 then
                if IsPedInAnyVehicle(PlayerPedId()) then
                    if GetVehicleNumberPlateText(GetVehiclePedIsIn(PlayerPedId())) == purchasedvehicle then
                        TriggerEvent('qb-vehicleshop:client:removedeleveryblip')
                        ondelivery = false
                        dropoff = true
                        TriggerEvent('qb-vehicleshop:client:addtostock', data, vehicle, svehicle)
                        break
                    else
                        print("TRIED TO EXPLOIT")
                    end
                end
            end
        end
    end)
end)

local spawnedcar = nil

    RegisterNetEvent('qb-vehicleshop:client:buystock', function(vehicle)
        RequestModel(vehicle)
        while not HasModelLoaded(vehicle) do
            Wait(1)
        end
        local shopData = Config.Shops[insideShop]
        local veh = CreateVehicle(
            vehicle,
            shopData['spawn'].x,
            shopData['spawn'].y,
            shopData['spawn'].z,
            0,
            true,
            true
        )
        PlayerData = QBCore.Functions.GetPlayerData()
        local citizenid = PlayerData.citizenid
            spawnedcar = vehicle
            local src = source
            SetEntityAsMissionEntity(veh, true, true)
            local plate = GetVehicleNumberPlateText(veh)
            while not plate do
                Wait(1)
            end
            purchasedvehicle = plate
            TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys',plate)
    end)


RegisterNetEvent('qb-vehicleshop:client:removeblip', function(data)
    RemoveBlip(pickupblip)
    pickupblip = nil
end)

RegisterNetEvent('qb-vehicleshop:client:removedeleveryblip', function(data)
    RemoveBlip(deliveryBlip)
    deliveryBlip = nil
end)


RegisterNetEvent('qb-vehicleshop:client:create_delevery_blip', function(k, shop)
    onmission = true
    ccarid = k
    local coords = Config.Shops[shop]['deliveryblip'] -- get the delivery blip coordinates for the current shop
    deliveryBlip = AddBlipForCoord(coords) -- create the blip at the delivery location
        SetBlipSprite(deliveryBlip, 1)
        SetBlipDisplay(deliveryBlip, 2)
        SetBlipScale(deliveryBlip, 1.0)
        SetBlipAsShortRange(deliveryBlip, true)
        SetBlipColour(deliveryBlip, 0)
        BeginTextCommandSetBlipName("Drop off")
        EndTextCommandSetBlipName(deliveryBlip)
        SetBlipRoute(deliveryBlip, true)
    ondelivery = true
    plate = splate
    svehicle = vehicle
    TriggerEvent('qb-vehicleshop:client:checkdeleverydistance',coords, k)
end)


RegisterNetEvent('qb-vehicleshop:client:addtostock', function(data, vehicle, svehicle)
    local vehicle = GetVehiclePedIsIn(PlayerPedId())
    DeleteVehicle(vehicle)
    TriggerServerEvent('qb-vehicleshop:owncar',data, spawnedcar, svehicle)
end)



RegisterCommand('checkstock', function()
    QBCore.Functions.TriggerCallback('test:server:checkstock', function(stock)
        for _, v in pairs(stock) do
            if v.car == 'sultan' then
                print(v.stock)
            end
        end
    end)
end)