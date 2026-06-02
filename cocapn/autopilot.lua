--- CoCapn autopilot: PID heading controller with 360° wrap.
-- Designed for vessel autopilot (rudder control) but general enough
-- for any single-axis heading/angle regulator.

local M = {}

--- Create a PID controller.
-- @param kp         Proportional gain
-- @param ki         Integral gain
-- @param kd         Derivative gain
-- @param max_rudder Maximum absolute rudder command output
-- @param tol        Deadband tolerance (degrees) — within this, on_course=true
-- @return           PID controller table
function M.new_pid(kp, ki, kd, max_rudder, tol)
  return {
    kp         = kp,
    ki         = ki,
    kd         = kd,
    integral   = 0,
    last_error = 0,
    last_dt    = 0,
    max_rudder = max_rudder or 30,
    tol        = tol or 3,
  }
end

--- Normalise a heading error to [-180, +180).
-- @param error  Raw heading difference (degrees)
-- @return       Wrapped error
local function wrap_error(error)
  while error > 180 do error = error - 360 end
  while error <= -180 do error = error + 360 end
  return error
end

--- Update the PID controller with a new measurement.
-- @param pid     PID controller table
-- @param current Current heading (degrees)
-- @param target  Desired heading (degrees)
-- @param dt      Delta time since last update (seconds)
-- @return        rudder_command, heading_error, on_course
function M.update(pid, current, target, dt)
  local error = wrap_error(target - current)
  local on_course = math.abs(error) <= pid.tol

  -- Proportional
  local p_term = pid.kp * error

  -- Integral with anti-windup clamping
  -- Only integrate while we're not saturated
  local i_term = pid.integral + pid.ki * error * (dt or 1)
  local raw_rudder = p_term + i_term - pid.kd * (error - pid.last_error) / dt

  -- Clamp
  local clipped = math.max(-pid.max_rudder, math.min(pid.max_rudder, raw_rudder))

  -- Anti-windup: only accept the integrated value if the clipped output
  -- didn't hit the limit, OR if we're on the right side of zero.
  if math.abs(clipped) < pid.max_rudder then
    pid.integral = i_term
  else
    -- Clamp the integral term by itself to prevent deep windup
    local clamped_i = math.max(-pid.max_rudder, math.min(pid.max_rudder, i_term))
    pid.integral = pid.ki > 0 and clamped_i or 0
  end

  pid.last_error = error
  pid.last_dt    = dt

  return clipped, error, on_course
end

--- Reset integral windup and last error.
function M.reset(pid)
  pid.integral   = 0
  pid.last_error = 0
  pid.last_dt    = 0
end

return M
