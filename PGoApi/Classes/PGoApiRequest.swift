//
//  PgoApi.swift
//  pgomap
//
//  Based on https://github.com/tejado/pgoapi/blob/master/pgoapi/pgoapi.py
//
//  Created by Luke Sapan on 7/20/16.
//  Copyright © 2016 Coadstal. All rights reserved.
//

import Foundation
import ProtocolBuffers


internal struct PGoApiMethod {
    internal let id: Pogoprotos.Networking.Requests.RequestType
    internal let message: GeneratedMessage
    internal let parser: NSData -> GeneratedMessage
}

public struct PGoLocation {
    public var lat:Double = 0
    public var long:Double = 0
    public var alt:Double = 6
    public var horizontalAccuracy: Double = 3.9
    public var speed: Double? = nil
    public var course: Double? = nil
    public var floor: UInt32? = nil
    public init() {}
}

public struct PGoSession {
    public var requestId: UInt64 = 0
    public var timeSinceStart:UInt64 = 0
    public var realisticStartTimeAdjustment:UInt64 = 0
    public var downloadSettingsHash: String? = nil
    public var sessionHash: NSData? = nil
    public init() {}
}

internal struct PGoVersion {
    internal static let versionHash: Int64 = 7363665268261373700
    internal static let versionString: String = "0.35.0"
    internal static let versionInt: UInt32 = 3500
}

internal struct PGoApiSettings {
    internal var refreshAuthTokens: Bool = true
    internal var checkChallenge: Bool = true
    internal var useResponseObjects: Bool = false
    internal var showRequests: Bool = true
}

internal struct platformRequestSettings {
    internal var useSensorInfo: Bool = true
    internal var useActivityStatus: Bool = true
    internal var useDeviceInfo: Bool = true
    internal var useLocationFix: Bool = true
    internal var randomizedTimeSnapshot = UInt64.random(100, max: 500)
}

public struct PGoDeviceInfo {
    public var deviceId = "5c69d67d886f48eba071794fc48d0ee60c13cf52"
    public var devicePlatform: Pogoprotos.Enums.Platform = .Ios
    public var androidBoardName: String? = nil
    public var androidBootloader: String? = nil
    public var deviceBrand: String? = "Apple"
    public var deviceModel: String? = "iPhone"
    public var deviceModelIdentifier: String? = nil
    public var deviceModelBoot: String? = "iPhone8,2"
    public var hardwareManufacturer: String? = "Apple"
    public var hardwareModel: String? = "N66mAP"
    public var firmwareBrand: String? = "iPhone OS"
    public var firmwareTags: String? = nil
    public var firmwareType: String? = "9.3.3"
    public var firmwareFingerprint: String? = nil
    public init() {}
}

public class PGoApiRequest {
    public var Location = PGoLocation()
    public var auth: PGoAuth?
    public var session = PGoSession()
    public var device = PGoDeviceInfo()
    internal var locationFix = LocationFixes()

    internal var unknown6Settings = platformRequestSettings()
    internal var ApiSettings = PGoApiSettings()
    
    internal var methodList: [PGoApiMethod] = []
    
    public init(auth: PGoAuth, session: PGoSession? = nil, Location: PGoLocation? = nil, device: PGoDeviceInfo? = nil) {
        self.auth = auth
        
        if session != nil {
            self.session = session!
        } else {
            self.session.requestId = UInt64.random(4611686018427388000, max: 9223372036854776000)
            self.session.timeSinceStart = getTimestamp()
            self.session.realisticStartTimeAdjustment = UInt64.random(750, max: 2000)
        }
        
        if Location != nil {
            self.Location = Location!
        }
        
        if device != nil {
            self.device = device!
        } else {
            self.device.deviceId = NSData.randomBytes(20).getHexString
        }
    }
    
    internal func getTimestamp() -> UInt64 {
        return UInt64(NSDate().timeIntervalSince1970 * 1000.0)
    }
    
    internal func getTimestampSinceStart() -> UInt64 {
        return getTimestamp() - session.timeSinceStart
    }
    
    public func debugMessage(message:String) {
        if ApiSettings.showRequests {
            print(message)
        }
    }
    
    public func refreshAuthToken() {
        self.auth!.authToken = nil
        print("Attempting to refresh auth token..")
    }
    
    public func makeRequest(intent: PGoApiIntent, delegate: PGoApiDelegate?) {
        // analogous to call in pgoapi.py
        
        if methodList.count == 0 {
            delegate?.didReceiveApiException(intent, exception: .NoApiMethodsCalled)
            print("makeRequest() called without any methods in methodList.")
            return
        }
        
        if self.auth != nil {
            if !self.auth!.loggedIn {
                print("makeRequest() called without being logged in.")
                delegate?.didReceiveApiException(intent, exception: .NotLoggedIn)
                return
            }
            
            if self.auth!.authToken != nil {
                if (self.auth!.authToken?.expireTimestampMs < getTimestamp()) {
                    print("Auth token has expired.")
                    if (ApiSettings.refreshAuthTokens) {
                        refreshAuthToken()
                    } else {
                        delegate?.didReceiveApiException(intent, exception: .AuthTokenExpired)
                        return
                    }
                }
            }
            
            if self.auth!.banned {
                delegate?.didReceiveApiException(intent, exception: .Banned)
                return
            } else if self.auth!.expired {
                if (ApiSettings.refreshAuthTokens) {
                    refreshAuthToken()
                } else {
                    delegate?.didReceiveApiException(intent, exception: .AuthTokenExpired)
                    return
                }
            }
            
        } else {
            delegate?.didReceiveApiException(intent, exception: .NoAuth)
            print("makeRequest() called without initializing auth.")
            return
        }
        
        if ApiSettings.checkChallenge {
            checkChallenge()
        }
        
        let request = PGoRpcApi(subrequests: methodList, intent: intent, auth: self.auth!, api: self, delegate: delegate)
        request.request()
        methodList.removeAll()
    }
    
    public func setLocation(latitude: Double, longitude: Double, altitude: Double? = 6.0, horizontalAccuracy: Double? = 3.9, floor: UInt32? = nil, speed: Double? = nil, course: Double? = nil) {
        Location.lat = latitude
        Location.long = longitude
        Location.alt = altitude!
        Location.horizontalAccuracy = horizontalAccuracy!
        Location.speed = speed
        Location.course = course
        Location.floor = floor
    }
    
    public func setSettings(refreshAuthTokens: Bool, checkChallenge: Bool, useResponseObjects: Bool, showRequests: Bool) {
        ApiSettings.refreshAuthTokens = refreshAuthTokens
        ApiSettings.checkChallenge = checkChallenge
        ApiSettings.useResponseObjects = useResponseObjects
        ApiSettings.showRequests = showRequests
    }
    
    public func setPlatformRequestSettings(useActivityStatus useActivityStatus: Bool, useDeviceInfo: Bool, useSensorInfo: Bool, useLocationFix: Bool, locationFixCount: Int? = 3) {
        unknown6Settings.useActivityStatus = useActivityStatus
        unknown6Settings.useDeviceInfo = useDeviceInfo
        unknown6Settings.useSensorInfo = useSensorInfo
        unknown6Settings.useLocationFix = useLocationFix
        locationFix.count = locationFixCount!
    }
    
    public func setDevice(deviceId: String? = nil, androidBoardName: String? = nil, androidBootloader: String? = nil, deviceModel: String? = nil, deviceBrand: String? = nil, deviceModelIdentifier: String? = nil, deviceModelBoot: String? = nil, hardwareManufacturer: String? = nil, hardwareModel: String? = nil, firmwareBrand: String? = nil, firmwareTags: String? = nil, firmwareType: String? = nil, firmwareFingerprint: String? = nil, devicePlatform: Pogoprotos.Enums.Platform? = .Ios) {
        if deviceId != nil {
            self.device.deviceId = deviceId!
        }
        self.device.androidBoardName = androidBoardName
        self.device.devicePlatform = devicePlatform!
        self.device.androidBootloader = androidBootloader
        self.device.deviceBrand = deviceBrand
        self.device.deviceModel = deviceModel
        self.device.deviceModelIdentifier = deviceModelIdentifier
        self.device.deviceModelBoot = deviceModelBoot
        self.device.hardwareManufacturer = hardwareManufacturer
        self.device.hardwareModel = hardwareModel
        self.device.firmwareBrand = firmwareBrand
        self.device.firmwareTags = firmwareTags
        self.device.firmwareType = firmwareType
        self.device.firmwareFingerprint = firmwareFingerprint
    }
    
    public func simulateAppStart() {
        getPlayer()
        heartBeat()
        downloadRemoteConfigVersion()
    }
    
    public func heartBeat() {
        getHatchedEggs()
        getInventory()
        checkAwardedBadges()
        downloadSettings()
    }
    
    public func updatePlayer() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.PlayerUpdateMessage.Builder()
        messageBuilder.latitude = Location.lat
        messageBuilder.longitude = Location.long
        methodList.append(PGoApiMethod(id: .PlayerUpdate, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.PlayerUpdateResponse.parseFromData(data)
        }))
    }
    
    public func getPlayer(country: String? = "US", language: String? = "en") {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetPlayerMessage.Builder()
        let playerLocale = Pogoprotos.Networking.Requests.Messages.GetPlayerMessage.PlayerLocale.Builder()
        playerLocale.language = language!
        playerLocale.country = country!
        messageBuilder.playerLocale = try! playerLocale.build()
        methodList.append(PGoApiMethod(id: .GetPlayer, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetPlayerResponse.parseFromData(data)
        }))
    }
    
    public func getInventory(lastTimestampMs: Int64? = nil, itemBeenSeen: Int32? = nil) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetInventoryMessage.Builder()
        if lastTimestampMs != nil {
            messageBuilder.lastTimestampMs = lastTimestampMs!
        }
        if itemBeenSeen != nil {
            messageBuilder.itemBeenSeen = itemBeenSeen!
        }
        methodList.append(PGoApiMethod(id: .GetInventory, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetInventoryResponse.parseFromData(data)
        }))
    }
    
    public func downloadSettings() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.DownloadSettingsMessage.Builder()
        if (session.downloadSettingsHash != nil) {
            messageBuilder.hash = session.downloadSettingsHash!
        }
        methodList.append(PGoApiMethod(id: .DownloadSettings, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.DownloadSettingsResponse.parseFromData(data)
        }))
    }
    
    public func downloadItemTemplates() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.DownloadItemTemplatesMessage.Builder()
        methodList.append(PGoApiMethod(id: .DownloadItemTemplates, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.DownloadItemTemplatesResponse.parseFromData(data)
        }))
    }
    
    public func downloadRemoteConfigVersion(deviceModel: String? = nil, deviceManufacturer: String? = nil, locale: String? = nil, appVersion: UInt32? = PGoVersion.versionInt) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.DownloadRemoteConfigVersionMessage.Builder()
        messageBuilder.platform = device.devicePlatform
        if deviceModel != nil {
            messageBuilder.deviceModel = deviceModel!
        }
        if deviceManufacturer != nil {
            messageBuilder.deviceManufacturer = deviceManufacturer!
        }
        if locale != nil {
            messageBuilder.locale = locale!
        }
        messageBuilder.appVersion = appVersion!
        methodList.append(PGoApiMethod(id: .DownloadRemoteConfigVersion, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.DownloadRemoteConfigVersionResponse.parseFromData(data)
        }))
    }
    
    public func fortSearch(fortId: String, fortLatitude: Double, fortLongitude: Double) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.FortSearchMessage.Builder()
        messageBuilder.fortId = fortId
        messageBuilder.fortLatitude = fortLatitude
        messageBuilder.fortLongitude = fortLongitude
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        methodList.append(PGoApiMethod(id: .FortSearch, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.FortSearchResponse.parseFromData(data)
        }))
    }
    
    public func encounterPokemon(encounterId: UInt64, spawnPointId: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.EncounterMessage.Builder()
        messageBuilder.encounterId = encounterId
        messageBuilder.spawnPointId = spawnPointId
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        methodList.append(PGoApiMethod(id: .Encounter, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.EncounterResponse.parseFromData(data)
        }))
    }
    
    public func catchPokemon(encounterId: UInt64, spawnPointId: String, pokeball: Pogoprotos.Inventory.Item.ItemId, hitPokemon: Bool? = nil, normalizedReticleSize: Double? = nil, normalizedHitPosition: Double? = nil, spinModifier: Double? = nil) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.CatchPokemonMessage.Builder()
        messageBuilder.encounterId = encounterId
        messageBuilder.spawnPointId = spawnPointId
        messageBuilder.pokeball = pokeball
        
        if hitPokemon == nil {
            messageBuilder.hitPokemon = true
        } else {
            messageBuilder.hitPokemon = hitPokemon!
        }
        
        if normalizedReticleSize == nil {
            messageBuilder.normalizedReticleSize = 1.95 + Double(Float.random(min: 0, max: 0.05))
        } else {
            messageBuilder.normalizedReticleSize = normalizedReticleSize!
        }
        
        if normalizedHitPosition == nil {
            messageBuilder.normalizedHitPosition = 1.0
        } else {
            messageBuilder.normalizedHitPosition = normalizedHitPosition!
        }
        
        if spinModifier == nil {
            messageBuilder.spinModifier = 0.85 + Double(Float.random(min: 0, max: 0.15))
        } else {
            messageBuilder.spinModifier = spinModifier!
        }
        
        methodList.append(PGoApiMethod(id: .CatchPokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.CatchPokemonResponse.parseFromData(data)
        }))
    }
    
    public func fortDetails(fortId: String, fortLatitude: Double, fortLongitude: Double) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.FortDetailsMessage.Builder()
        messageBuilder.fortId = fortId
        messageBuilder.latitude = fortLatitude
        messageBuilder.longitude = fortLongitude
        methodList.append(PGoApiMethod(id: .FortDetails, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.FortDetailsResponse.parseFromData(data)
        }))
    }
    
    public func generateS2Cells(lat: Double, long: Double) -> Array<UInt64> {
        let cell = S2CellId(p: S2LatLon(latDegrees: lat, lonDegrees: long).toPoint()).parent(15)
        let cells = cell.getEdgeNeighbors()
        var unfiltered: [S2CellId] = []
        var filtered: [UInt64] = []
        unfiltered.appendContentsOf(cells)
        for ce in cells {
            unfiltered.appendContentsOf(ce.getAllNeighbors(15))
        }
        for item in unfiltered {
            if !filtered.contains(item.id) {
                filtered += [item.id]
            }
        }
        return filtered
    }
    
    public func getMapObjects(cellIds: Array<UInt64>? = nil, sinceTimestampMs: Array<Int64>? = nil) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetMapObjectsMessage.Builder()
        messageBuilder.latitude = Location.lat
        messageBuilder.longitude = Location.long
        
        if cellIds != nil {
            messageBuilder.cellId = cellIds!
            
        } else {
            let cells = generateS2Cells(Location.lat, long: Location.long)
            messageBuilder.cellId = cells
        }
        
        if sinceTimestampMs != nil {
            messageBuilder.sinceTimestampMs = sinceTimestampMs!
        } else {
            var timeStamps: Array<Int64> = []
            for _ in messageBuilder.cellId {
                timeStamps.append(0)
            }
            messageBuilder.sinceTimestampMs = timeStamps
        }
        
        methodList.append(PGoApiMethod(id: .GetMapObjects, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetMapObjectsResponse.parseFromData(data)
        }))
    }
    
    public func fortDeployPokemon(fortId: String, pokemonId:UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.FortDeployPokemonMessage.Builder()
        messageBuilder.fortId = fortId
        messageBuilder.pokemonId = pokemonId
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        methodList.append(PGoApiMethod(id: .FortDeployPokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.FortDeployPokemonResponse.parseFromData(data)
        }))
    }
    
    public func fortRecallPokemon(fortId: String, pokemonId:UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.FortRecallPokemonMessage.Builder()
        messageBuilder.fortId = fortId
        messageBuilder.pokemonId = pokemonId
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        methodList.append(PGoApiMethod(id: .FortRecallPokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.FortRecallPokemonResponse.parseFromData(data)
        }))
    }
    
    public func releasePokemon(pokemonId:UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.ReleasePokemonMessage.Builder()
        messageBuilder.pokemonId = pokemonId
        methodList.append(PGoApiMethod(id: .ReleasePokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.ReleasePokemonResponse.parseFromData(data)
        }))
    }
    
    public func useItemPotion(itemId: Pogoprotos.Inventory.Item.ItemId, pokemonId:UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.UseItemPotionMessage.Builder()
        messageBuilder.itemId = itemId
        messageBuilder.pokemonId = pokemonId
        methodList.append(PGoApiMethod(id: .UseItemPotion, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.UseItemPotionResponse.parseFromData(data)
        }))
    }
    
    public func useItemCapture(itemId: Pogoprotos.Inventory.Item.ItemId, encounterId:UInt64, spawnPointId: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.UseItemCaptureMessage.Builder()
        messageBuilder.itemId = itemId
        messageBuilder.encounterId = encounterId
        messageBuilder.spawnPointId = spawnPointId
        methodList.append(PGoApiMethod(id: .UseItemCapture, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.UseItemCaptureResponse.parseFromData(data)
        }))
    }
    
    public func useItemRevive(itemId: Pogoprotos.Inventory.Item.ItemId, pokemonId: UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.UseItemReviveMessage.Builder()
        messageBuilder.itemId = itemId
        messageBuilder.pokemonId = pokemonId
        methodList.append(PGoApiMethod(id: .UseItemRevive, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.UseItemReviveResponse.parseFromData(data)
        }))
    }
    
    public func getPlayerProfile(playerName: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetPlayerProfileMessage.Builder()
        messageBuilder.playerName = playerName
        methodList.append(PGoApiMethod(id: .GetPlayerProfile, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetPlayerProfileResponse.parseFromData(data)
        }))
    }
    
    public func evolvePokemon(pokemonId: UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.EvolvePokemonMessage.Builder()
        messageBuilder.pokemonId = pokemonId
        methodList.append(PGoApiMethod(id: .EvolvePokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.EvolvePokemonResponse.parseFromData(data)
        }))
    }
    
    public func getHatchedEggs() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetHatchedEggsMessage.Builder()
        methodList.append(PGoApiMethod(id: .GetHatchedEggs, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetHatchedEggsResponse.parseFromData(data)
        }))
    }
    
    public func encounterTutorialComplete(pokemonId: Pogoprotos.Enums.PokemonId) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.EncounterTutorialCompleteMessage.Builder()
        messageBuilder.pokemonId = pokemonId
        methodList.append(PGoApiMethod(id: .EncounterTutorialComplete, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.EncounterTutorialCompleteResponse.parseFromData(data)
        }))
    }
    
    public func levelUpRewards(level:Int32) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.LevelUpRewardsMessage.Builder()
        messageBuilder.level = level
        methodList.append(PGoApiMethod(id: .LevelUpRewards, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.LevelUpRewardsResponse.parseFromData(data)
        }))
    }
    
    public func checkAwardedBadges() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.CheckAwardedBadgesMessage.Builder()
        methodList.append(PGoApiMethod(id: .CheckAwardedBadges, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.CheckAwardedBadgesResponse.parseFromData(data)
        }))
    }
    
    public func useItemGym(itemId: Pogoprotos.Inventory.Item.ItemId, gymId: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.UseItemGymMessage.Builder()
        messageBuilder.itemId = itemId
        messageBuilder.gymId = gymId
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        methodList.append(PGoApiMethod(id: .UseItemGym, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.UseItemGymResponse.parseFromData(data)
        }))
    }
    
    public func getGymDetails(gymId: String, gymLatitude: Double, gymLongitude: Double, clientVersion: String? = PGoVersion.versionString) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetGymDetailsMessage.Builder()
        messageBuilder.gymId = gymId
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        messageBuilder.gymLatitude = gymLatitude
        messageBuilder.gymLongitude = gymLongitude
        messageBuilder.clientVersion = clientVersion!
        methodList.append(PGoApiMethod(id: .GetGymDetails, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetGymDetailsResponse.parseFromData(data)
        }))
    }
    
    public func startGymBattle(gymId: String, attackingPokemonIds: Array<UInt64>, defendingPokemonId: UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.StartGymBattleMessage.Builder()
        messageBuilder.gymId = gymId
        messageBuilder.attackingPokemonIds = attackingPokemonIds
        messageBuilder.defendingPokemonId = defendingPokemonId
        methodList.append(PGoApiMethod(id: .StartGymBattle, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.StartGymBattleResponse.parseFromData(data)
        }))
    }
    
    public func attackGym(gymId: String, battleId: String, attackActions: Array<Pogoprotos.Data.Battle.BattleAction>, lastRetrievedAction: Pogoprotos.Data.Battle.BattleAction) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.AttackGymMessage.Builder()
        messageBuilder.gymId = gymId
        messageBuilder.battleId = battleId
        messageBuilder.attackActions = attackActions
        messageBuilder.lastRetrievedActions = lastRetrievedAction
        messageBuilder.playerLongitude = Location.lat
        messageBuilder.playerLatitude = Location.long
        
        methodList.append(PGoApiMethod(id: .AttackGym, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.AttackGymResponse.parseFromData(data)
        }))
    }
    
    public func recycleInventoryItem(itemId: Pogoprotos.Inventory.Item.ItemId, itemCount: Int32) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.RecycleInventoryItemMessage.Builder()
        messageBuilder.itemId = itemId
        messageBuilder.count = itemCount
        methodList.append(PGoApiMethod(id: .RecycleInventoryItem, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.RecycleInventoryItemResponse.parseFromData(data)
        }))
    }
    
    public func collectDailyBonus() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.CollectDailyBonusMessage.Builder()
        methodList.append(PGoApiMethod(id: .CollectDailyBonus, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.CollectDailyBonusResponse.parseFromData(data)
        }))
    }
    
    public func useItemXPBoost(itemId: Pogoprotos.Inventory.Item.ItemId) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.UseItemXpBoostMessage.Builder()
        messageBuilder.itemId = itemId
        methodList.append(PGoApiMethod(id: .UseItemXpBoost, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.UseItemXpBoostResponse.parseFromData(data)
        }))
    }
    
    public func useItemEggIncubator(itemId: String, pokemonId: UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.UseItemEggIncubatorMessage.Builder()
        messageBuilder.itemId = itemId
        messageBuilder.pokemonId = pokemonId
        methodList.append(PGoApiMethod(id: .UseItemEggIncubator, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.UseItemEggIncubatorResponse.parseFromData(data)
        }))
    }
    
    public func useIncense(itemId: Pogoprotos.Inventory.Item.ItemId) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.UseIncenseMessage.Builder()
        messageBuilder.incenseType = itemId
        methodList.append(PGoApiMethod(id: .UseIncense, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.UseIncenseResponse.parseFromData(data)
        }))
    }
    
    public func getIncensePokemon() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetIncensePokemonMessage.Builder()
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        methodList.append(PGoApiMethod(id: .GetIncensePokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetIncensePokemonResponse.parseFromData(data)
        }))
    }
    
    public func incenseEncounter(encounterId: UInt64, encounterLocation: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.IncenseEncounterMessage.Builder()
        messageBuilder.encounterId = encounterId
        messageBuilder.encounterLocation = encounterLocation
        methodList.append(PGoApiMethod(id: .IncenseEncounter, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.IncenseEncounterResponse.parseFromData(data)
        }))
    }
    
    public func addFortModifier(itemId: Pogoprotos.Inventory.Item.ItemId, fortId: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.AddFortModifierMessage.Builder()
        messageBuilder.modifierType = itemId
        messageBuilder.fortId = fortId
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        methodList.append(PGoApiMethod(id: .AddFortModifier, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.AddFortModifierResponse.parseFromData(data)
        }))
    }
    
    public func diskEncounter(encounterId: UInt64, fortId: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.DiskEncounterMessage.Builder()
        messageBuilder.encounterId = encounterId
        messageBuilder.fortId = fortId
        messageBuilder.playerLatitude = Location.lat
        messageBuilder.playerLongitude = Location.long
        methodList.append(PGoApiMethod(id: .DiskEncounter, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.DiskEncounterResponse.parseFromData(data)
        }))
    }
    
    public func collectDailyDefenderBonus(encounterId: UInt64, fortId: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.CollectDailyDefenderBonusMessage.Builder()
        methodList.append(PGoApiMethod(id: .CollectDailyDefenderBonus, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.CollectDailyDefenderBonusResponse.parseFromData(data)
        }))
    }
    
    public func upgradePokemon(pokemonId: UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.UpgradePokemonMessage.Builder()
        messageBuilder.pokemonId = pokemonId
        methodList.append(PGoApiMethod(id: .UpgradePokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.UpgradePokemonResponse.parseFromData(data)
        }))
    }
    
    public func setFavoritePokemon(pokemonId: Int64, isFavorite: Bool) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.SetFavoritePokemonMessage.Builder()
        messageBuilder.pokemonId = pokemonId
        messageBuilder.isFavorite = isFavorite
        methodList.append(PGoApiMethod(id: .SetFavoritePokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.SetFavoritePokemonResponse.parseFromData(data)
        }))
    }
    
    public func nicknamePokemon(pokemonId: UInt64, nickname: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.NicknamePokemonMessage.Builder()
        messageBuilder.pokemonId = pokemonId
        messageBuilder.nickname = nickname
        methodList.append(PGoApiMethod(id: .NicknamePokemon, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.NicknamePokemonResponse.parseFromData(data)
        }))
    }
    
    public func equipBadge(badgeType: Pogoprotos.Enums.BadgeType) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.EquipBadgeMessage.Builder()
        messageBuilder.badgeType = badgeType
        methodList.append(PGoApiMethod(id: .EquipBadge, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.EquipBadgeResponse.parseFromData(data)
        }))
    }
    
    public func setContactSettings(sendMarketingEmails: Bool, sendPushNotifications: Bool) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.SetContactSettingsMessage.Builder()
        let contactSettings = Pogoprotos.Data.Player.ContactSettings.Builder()
        contactSettings.sendMarketingEmails = sendMarketingEmails
        contactSettings.sendPushNotifications = sendPushNotifications
        try! messageBuilder.contactSettings = contactSettings.build()
        methodList.append(PGoApiMethod(id: .SetContactSettings, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.SetContactSettingsResponse.parseFromData(data)
        }))
    }
    
    public func getAssetDigest(deviceModel: String?, deviceManufacturer: String?, locale: String?, appVersion: UInt32? = PGoVersion.versionInt) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetAssetDigestMessage.Builder()
        messageBuilder.platform = device.devicePlatform
        if deviceModel != nil {
            messageBuilder.deviceModel = deviceModel!
        }
        if deviceManufacturer != nil {
            messageBuilder.deviceManufacturer = deviceManufacturer!
        }
        if locale != nil {
            messageBuilder.locale = locale!
        }
        messageBuilder.appVersion = appVersion!
        methodList.append(PGoApiMethod(id: .GetAssetDigest, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetAssetDigestResponse.parseFromData(data)
        }))
    }
    
    public func getDownloadURLs(assetId: Array<String>) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetDownloadUrlsMessage.Builder()
        messageBuilder.assetId = assetId
        methodList.append(PGoApiMethod(id: .GetDownloadUrls, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetDownloadUrlsResponse.parseFromData(data)
        }))
    }
    
    public func getSuggestedCodenames() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetSuggestedCodenamesMessage.Builder()
        methodList.append(PGoApiMethod(id: .GetSuggestedCodenames, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetSuggestedCodenamesResponse.parseFromData(data)
        }))
    }
    
    public func checkCodenameAvailable(codename: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.CheckCodenameAvailableMessage.Builder()
        messageBuilder.codename = codename
        methodList.append(PGoApiMethod(id: .CheckCodenameAvailable, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.CheckCodenameAvailableResponse.parseFromData(data)
        }))
    }
    
    public func claimCodename(codename: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.ClaimCodenameMessage.Builder()
        messageBuilder.codename = codename
        methodList.append(PGoApiMethod(id: .ClaimCodename, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.ClaimCodenameResponse.parseFromData(data)
        }))
    }
    
    public func setAvatar(skin: Int32, hair: Int32, shirt: Int32, pants: Int32, hat: Int32, shoes: Int32, gender: Pogoprotos.Enums.Gender, eyes: Int32, backpack: Int32) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.SetAvatarMessage.Builder()
        
        let playerAvatar = Pogoprotos.Data.Player.PlayerAvatar.Builder()
        playerAvatar.backpack = backpack
        playerAvatar.skin = skin
        playerAvatar.hair = hair
        playerAvatar.shirt = shirt
        playerAvatar.pants = pants
        playerAvatar.hat = hat
        playerAvatar.gender = gender
        playerAvatar.eyes = eyes
        
        try! messageBuilder.playerAvatar = playerAvatar.build()
        
        methodList.append(PGoApiMethod(id: .SetAvatar, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.SetAvatarResponse.parseFromData(data)
        }))
    }
    
    public func setPlayerTeam(teamColor: Pogoprotos.Enums.TeamColor) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.SetPlayerTeamMessage.Builder()
        messageBuilder.team = teamColor
        methodList.append(PGoApiMethod(id: .SetPlayerTeam, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.SetPlayerTeamResponse.parseFromData(data)
        }))
    }
    
    public func markTutorialComplete(tutorialState: Array<Pogoprotos.Enums.TutorialState>, sendMarketingEmails: Bool, sendPushNotifications: Bool) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.MarkTutorialCompleteMessage.Builder()
        messageBuilder.tutorialsCompleted = tutorialState
        messageBuilder.sendMarketingEmails = sendMarketingEmails
        messageBuilder.sendPushNotifications = sendPushNotifications
        methodList.append(PGoApiMethod(id: .MarkTutorialComplete, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.MarkTutorialCompleteResponse.parseFromData(data)
        }))
    }
    
    public func echo() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.EchoMessage.Builder()
        methodList.append(PGoApiMethod(id: .Echo, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.EchoResponse.parseFromData(data)
        }))
    }
    
    public func sfidaActionLog() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.SfidaActionLogMessage.Builder()
        methodList.append(PGoApiMethod(id: .SfidaActionLog, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.SfidaActionLogResponse.parseFromData(data)
        }))
    }
    
    public func getBuddyWalked() {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.GetBuddyWalkedMessage.Builder()
        methodList.append(PGoApiMethod(id: .CheckChallenge, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.GetBuddyWalkedResponse.parseFromData(data)
        }))

    }
 
    public func setBuddyPokemon(pokemonId: UInt64) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.SetBuddyPokemonMessage.Builder()
        messageBuilder.pokemonId = pokemonId
        methodList.append(PGoApiMethod(id: .CheckChallenge, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.SetBuddyPokemonResponse.parseFromData(data)
        }))
        
    }
    
    private func checkChallenge(debug: Bool? = false) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.CheckChallengeMessage.Builder()
        messageBuilder.debugRequest = debug!
        methodList.insert(PGoApiMethod(id: .CheckChallenge, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.CheckChallengeResponse.parseFromData(data)
        }), atIndex: 1)
    }
    
    public func verifyChallenge(token: String) {
        let messageBuilder = Pogoprotos.Networking.Requests.Messages.VerifyChallengeMessage.Builder()
        messageBuilder.token = token
        methodList.append(PGoApiMethod(id: .VerifyChallenge, message: try! messageBuilder.build(), parser: { data in
            return try! Pogoprotos.Networking.Responses.VerifyChallengeResponse.parseFromData(data)
        }))
    }
}
