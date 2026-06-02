--- CoCapn stripe: device striping with failover.
-- Distributes work across a group of devices and marks dead members.
-- Supports striping (round-robin, hash) and active/passive failover.

local M = {}

M.STRATEGY = {
  ROUND_ROBIN = 1,
  HASH        = 2,
  ACTIVE_ONLY = 3,
}

--- Create a new stripe group.
-- @param devices   Array of device tables (from device.lua)
-- @param strategy  M.STRATEGY.* (default ROUND_ROBIN)
-- @return          Stripe table
function M.new(devices, strategy)
  return {
    devices   = devices or {},
    strategy  = strategy or M.STRATEGY.ROUND_ROBIN,
    cursor    = 1,
    failures  = {},  -- device_id -> consecutive_fail_count
  }
end

--- Get the next available device from the stripe.
-- Skips offline and blacklisted devices.
-- @param stripe   Stripe table
-- @param key      Optional hash key (used with HASH strategy)
-- @return         Device table or nil if all are down
function M.next(stripe, key)
  local alive = {}
  for _, dev in ipairs(stripe.devices) do
    if dev.online then
      alive[#alive + 1] = dev
    end
  end

  if #alive == 0 then return nil end

  local idx
  if stripe.strategy == M.STRATEGY.ROUND_ROBIN then
    idx = ((stripe.cursor - 1) % #alive) + 1
    stripe.cursor = stripe.cursor + 1
  elseif stripe.strategy == M.STRATEGY.HASH and key then
    local h = 0
    for i = 1, #key do
      h = h * 31 + key:byte(i)
    end
    idx = (h % #alive) + 1
  else
    -- ACTIVE_ONLY: always return first alive
    idx = 1
  end

  return alive[idx]
end

--- Mark a device as failed (increments failure counter).
-- @param stripe  Stripe table
-- @param dev_id  Device ID
-- @param max_fails  Auto-offline after this many failures (default 3)
-- @return        true if the device was taken offline
function M.fail(stripe, dev_id, max_fails)
  max_fails = max_fails or 3
  stripe.failures[dev_id] = (stripe.failures[dev_id] or 0) + 1

  if stripe.failures[dev_id] >= max_fails then
    for _, dev in ipairs(stripe.devices) do
      if dev.id == dev_id then
        dev.online = false
        return true
      end
    end
  end
  return false
end

--- Restore a previously failed device.
-- @param stripe  Stripe table
-- @param dev_id  Device ID
function M.restore(stripe, dev_id)
  stripe.failures[dev_id] = 0
  for _, dev in ipairs(stripe.devices) do
    if dev.id == dev_id then
      dev.online = true
      return true
    end
  end
  return false
end

--- Return the count of currently online devices.
function M.alive_count(stripe)
  local count = 0
  for _, dev in ipairs(stripe.devices) do
    if dev.online then count = count + 1 end
  end
  return count
end

return M
