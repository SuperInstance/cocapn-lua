--- CoCapn device: sensor, actuator, or compute node with capability flags.
-- Lua port: bit ops via arithmetic (no bit32 dependency).

local M = {}

-- Tier constants (higher = more capable / more latency)
M.TIER = {
  REFLEX   = 1,   -- <1ms, on-sensor or local relay
  BACKBONE = 2,   -- 1-10ms, gateway or local controller
  CORTEX   = 3,   -- 10-100ms, edge inference / fusion
  CLOUD    = 4,   -- >100ms, heavy compute or global state
}

-- Capability bit flags
M.CAP = {
  SENSE   = 1,    -- read sensor data
  ACT     = 2,    -- write actuator/toggle relay
  ROUTE   = 4,    -- forward messages between layers
  PREDICT = 8,    -- run inference
  TRAIN   = 16,   -- update model weights
  COMM    = 32,   -- external communications (NMEA, WiFi, LoRa)
}

--- Create a new device descriptor.
-- @param id      Unique device identifier (string or number)
-- @param name    Human-readable name
-- @param tier    One of M.TIER.*
-- @param caps    Bitwise-OR of M.CAP.* (default 0)
-- @param online  Whether the device is reachable (default true)
-- @return        Device table
function M.new_device(id, name, tier, caps, online)
  return {
    id     = id,
    name   = name,
    tier   = tier,
    caps   = caps or 0,
    online = online ~= false,
  }
end

--- Check if a device has a specific capability and is online.
-- Uses arithmetic modulo for bit test (Lua 5.1/5.2/LuaJIT compatible).
-- @param dev  Device table
-- @param cap  Single M.CAP.* value
-- @return     boolean
function M.can(dev, cap)
  return dev.online and (dev.caps % (cap * 2) >= cap)
end

--- List all capabilities a device has.
-- @param dev  Device table
-- @return     Array of cap name strings
function M.list_caps(dev)
  local names = {}
  for name, val in pairs(M.CAP) do
    if M.can(dev, val) then
      names[#names + 1] = name
    end
  end
  return names
end

--- Return a human-readable summary of a device.
function M.tostring(dev)
  local status = dev.online and "online" or "offline"
  local caps = table.concat(M.list_caps(dev), ", ")
  if caps == "" then caps = "none" end
  return string.format("[%s] %s (%s) — %s — %s", dev.id, dev.name, status, caps, dev.tier)
end

return M
