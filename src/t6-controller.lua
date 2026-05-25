local sides = require("sides")
local event = require("event")

local stateMachineLib = require("lib.state-machine-lib")
local componentDiscoverLib = require("lib.component-discover-lib")
local gtSensorParserLib = require("lib.gt-sensor-parser")

---@class T6ControllerConfig
---@field transposerAddress string

local t6controller = {}

---Crate new T6Controller object from config
---@param config T6ControllerConfig
---@return T6Controller
function t6controller:newFormConfig(config)
  return self:new(config.transposerAddress)
end

---Crate new T6Controller object
---@param transposerAddress string
function t6controller:new(transposerAddress)

  ---@class T6Controller
  local obj = {}

  obj.transposerProxy = nil
  obj.controllerProxy = nil

  obj.stateMachine = stateMachineLib:new()
  obj.gtSensorParser = nil

  obj.transposerItems = {}

  ---Init T6Controller
  function obj:init()
    local config = require("config")
    local locale = require("lib.locale")[config.locale or "en"]

    local function findMatchedLens()
      local rawLens = self.gtSensorParser:getString(5, locale.t6.prefix)
      if not rawLens then
        return nil
      end
      for english, localPattern in pairs(locale.t6.lenses) do
        if string.find(rawLens, localPattern) then
          return english
        end
      end
      return nil
    end

    self:findMachineProxy()
    self:resetLenses()
    self:findTransposerItem(self.transposerProxy, locale.t6.lenses)

    self.gtSensorParser:getInformation()

    self.stateMachine.states.idle = self.stateMachine:createState("Idle")
    self.stateMachine.states.idle.init = function ()
      if self.stateMachine.data.currentLens ~= nil then
        self.transposerProxy.transferItem(
          sides.bottom, 
          self.transposerItems[self.stateMachine.data.currentLens].side,
          1,
          1,
          self.transposerItems[self.stateMachine.data.currentLens].slot)
      end
    end
    self.stateMachine.states.idle.update = function()
      if self.controllerProxy.hasWork() then
        self.stateMachine:setState(self.stateMachine.states.changeLens)
      end
    end

    self.stateMachine.states.changeLens = self.stateMachine:createState("Change Lens")
    self.stateMachine.states.changeLens.init = function()
      local lens = findMatchedLens()
      local recipeError = self.gtSensorParser:getString(6)

      local isLensError = false
      if recipeError ~= nil then
        if recipeError == "Removed lens too early. Failing this recipe." or
           string.find(recipeError, "извлечена") or
           string.find(recipeError, "удалена") or
           string.find(recipeError, "рано") then
          isLensError = true
        end
      end

      if lens == nil or isLensError then
        self.stateMachine:setState(self.stateMachine.states.waitEnd)
        return
      end

      self:putLens(lens)
    end

    self.stateMachine.states.waitLens = self.stateMachine:createState("Wait Lens")
    self.stateMachine.states.waitLens.update = function()
      local lens = findMatchedLens()

      if self.controllerProxy.hasWork() == false then
        self.stateMachine:setState(self.stateMachine.states.idle)
        return
      end

      if self.stateMachine.data.currentLens ~= lens then
        self.stateMachine:setState(self.stateMachine.states.changeLens)
      end
    end

    self.stateMachine.states.waitEnd = self.stateMachine:createState("Wait End")

    event.listen("cycle_end", function ()
      if self.stateMachine.currentState == self.stateMachine.states.waitEnd then
        self.stateMachine:setState(self.stateMachine.states.idle)
      end
    end)

    self.stateMachine:setState(self.stateMachine.states.idle)
  end

  ---Find controller proxy
  function obj:findMachineProxy()
    self.controllerProxy = componentDiscoverLib.discoverGtMachine("multimachine.purificationunituvtreatment")

    if self.controllerProxy == nil then
      error("[T6] High Energy Laser Purification Unit not found")
    end

    self.transposerProxy = componentDiscoverLib.discoverProxy(transposerAddress, "[T6] Transposer", "transposer")
    self.gtSensorParser = gtSensorParserLib:new(self.controllerProxy)
  end

  ---Find Transposer Item
  ---@param proxy transposer
  ---@param itemLabelsMap table<string, string> -- maps English name -> local pattern
  function obj:findTransposerItem(proxy, itemLabelsMap)
    local localLabels = {}
    local localToEnglish = {}
    for english, localPattern in pairs(itemLabelsMap) do
      table.insert(localLabels, localPattern)
      localToEnglish[localPattern] = english
    end

    local result, skipped = componentDiscoverLib.discoverTransposerItemStorage(proxy, localLabels)

    if #skipped ~= 0 then
      local skippedEnglish = {}
      for _, localPattern in ipairs(skipped) do
        local englishName = localToEnglish[localPattern] or localPattern
        table.insert(skippedEnglish, englishName)
      end

      if not (#skippedEnglish == 1 and skippedEnglish[1] == "Dilithium Lens") then
        error("[T6] Can't find items: "..table.concat(skippedEnglish, ", "))
      end
    end

    for localPattern, value in pairs(result) do
      local english = localToEnglish[localPattern]
      if english then
        self.transposerItems[english] = value
      end
    end
  end

  ---Reset lens from bus before init
  function obj:resetLenses()
    local transposerSides = componentDiscoverLib.discoverTransposerItemStorageSide(self.transposerProxy, {sides.bottom})

    if transposerSides[1] ~= nil then
      self.transposerProxy.transferItem(sides.bottom, transposerSides[1], 1)
    end
  end

  ---Put required lens to input bus
  ---@param lens string
  function obj:putLens(lens)
    if self.stateMachine.data.currentLens ~= nil then
      self.transposerProxy.transferItem(
        sides.bottom,
        self.transposerItems[self.stateMachine.data.currentLens].side,
        1,
        1,
        self.transposerItems[self.stateMachine.data.currentLens].slot)
    end

    if lens == "Dilithium Lens" and self.transposerItems[lens] == nil then
      self.stateMachine.data.currentLens = nil
      self.stateMachine:setState(self.stateMachine.states.waitEnd)
      return
    end

    local result = self.transposerProxy.transferItem(
      self.transposerItems[lens].side,
      sides.bottom,
      1,
      self.transposerItems[lens].slot)

    if result ~= 1 then
      self.controllerProxy.setWorkAllowed(false)
      self.stateMachine.data.currentLens = nil
      self.stateMachine:setState(self.stateMachine.states.waitEnd)
      event.push("log_warning", "[T6] Invalid slot: "..self.transposerItems[lens].slot.." for: "..lens)
      return
    end

    self.stateMachine.data.currentLens = lens

    if lens == "Dilithium Lens" then
      self.stateMachine:setState(self.stateMachine.states.waitEnd)
    else
      self.stateMachine:setState(self.stateMachine.states.waitLens)
    end
  end

  ---Loop
  function obj:loop()
    self.gtSensorParser:getInformation()
    self.stateMachine:update()
  end

  ---Get current state
  ---@return string
  function obj:getState()
    if self.controllerProxy.isWorkAllowed() == false then
      return "Controller disabled"
    end

    if self.controllerProxy.hasWork() == false then
      return "Wait cycle"
    end

    local state = self.stateMachine.currentState and self.stateMachine.currentState.name or "nil"
    local successChange = self.gtSensorParser:getNumber(2, "Success chance:")

    if successChange == nil then
      successChange = 0
    end

    return "State: ["..state.."] Success: ["..successChange.."%]"
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

return t6controller