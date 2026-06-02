--- CoCapn deadband / hysteresis zone.
-- Determines whether a value is within tolerance of a center point,
-- with optional one-sided treatment and approach/exceeded states.

local M = {}

-- Return states
M.STATE = {
  NORMAL      = 0,   -- within tolerance
  APPROACHING = 1,   -- inside the deadband but beyond approach threshold
  EXCEEDED    = 2,   -- outside the deadband
}

-- Direction constraint
M.DIR = {
  BOTH       = 0,   -- symmetrical deadband
  ABOVE_ONLY = 1,   -- only enforce above center
  BELOW_ONLY = 2,   -- only enforce below center
}

--- Create a deadband zone.
-- Tolerance is expressed as an absolute delta from center.
-- @param center     The nominal/expected value
-- @param tolerance  Absolute delta for the deadband (will be abs'd)
-- @param direction  M.DIR.* (default BOTH)
-- @return           Deadband table
function M.new(center, tolerance, direction)
  return {
    center     = center,
    tolerance  = math.abs(tolerance),
    direction  = direction or M.DIR.BOTH,
  }
end

--- Check a value against the deadband.
-- Returns the STATE enum.
-- @param db   Deadband table
-- @param val  Value to test
-- @return     M.STATE.*
function M.check(db, val)
  local delta = val - db.center

  -- Direction-adjusted effective delta
  if db.direction == M.DIR.ABOVE_ONLY then
    delta = math.max(delta, 0)
  elseif db.direction == M.DIR.BELOW_ONLY then
    delta = math.min(delta, 0)
  end

  local abs_delta = math.abs(delta)

  if abs_delta > db.tolerance then
    return M.STATE.EXCEEDED
  end

  -- Approaching zone: within half the tolerance from the edge
  -- (conservative early-warning)
  if abs_delta > db.tolerance * 0.5 and abs_delta <= db.tolerance then
    return M.STATE.APPROACHING
  end

  return M.STATE.NORMAL
end

--- Check if a value is within the deadband (shorthand).
-- @return boolean
function M.within(db, val)
  return M.check(db, val) == M.STATE.NORMAL
end

--- Check if a value has exceeded the deadband (shorthand).
-- @return boolean
function M.exceeded(db, val)
  return M.check(db, val) == M.STATE.EXCEEDED
end

--- Return the lower and upper bounds of the deadband.
function M.bounds(db)
  local lo, hi
  if db.direction == M.DIR.ABOVE_ONLY then
    lo = db.center
    hi = db.center + db.tolerance
  elseif db.direction == M.DIR.BELOW_ONLY then
    lo = db.center - db.tolerance
    hi = db.center
  else
    lo = db.center - db.tolerance
    hi = db.center + db.tolerance
  end
  return lo, hi
end

return M
