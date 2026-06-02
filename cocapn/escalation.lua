--- CoCapn escalation: multi-tier alert routing and prioritisation.
-- Broadcasts state changes through a chain of handlers, with configurable
-- cooldown, priority, and sticky conditions.

local M = {}

M.PRIORITY = {
  LOW      = 1,
  MEDIUM   = 2,
  HIGH     = 3,
  CRITICAL = 4,
}

M.SEVERITY = {
  INFO     = 1,
  WARNING  = 2,
  ERROR    = 3,
  FATAL    = 4,
}

--- Create an escalation chain.
-- @param handlers  Array of {fn, priority_min} handler tables
-- @return          Escalation table
function M.new_chain(handlers)
  return {
    handlers   = handlers or {},
    cooldowns  = {},  -- tag -> cooldown_until (monotonic clock)
    sticky     = {},  -- tag -> sticky_severity
  }
end

--- Register a handler at a given priority threshold.
-- @param chain        Escalation chain
-- @param handler_fn   Function(severity, priority, tag, message)
-- @param priority_min Minimum priority to trigger this handler
function M.add_handler(chain, handler_fn, priority_min)
  chain.handlers[#chain.handlers + 1] = {
    fn = handler_fn,
    priority_min = priority_min or M.PRIORITY.LOW,
  }
end

--- Dispatch an alert through the escalation chain.
-- @param chain     Escalation chain
-- @param severity  M.SEVERITY.*
-- @param priority  M.PRIORITY.*
-- @param tag       Unique string tag for cooldown/sticky dedup
-- @param message   Alert payload text
-- @param opts      {cooldown=seconds, sticky=bool}
function M.alert(chain, severity, priority, tag, message, opts)
  opts = opts or {}

  -- Cooldown check
  if opts.cooldown then
    local now = os.clock()
    local until_time = chain.cooldowns[tag] or 0
    if now < until_time then
      return false, "cooldown active"
    end
    chain.cooldowns[tag] = now + opts.cooldown
  end

  -- Sticky: remember highest severity seen
  if opts.sticky then
    local existing = chain.sticky[tag] or 0
    if severity <= existing then
      return false, "sticky already active at equal or higher severity"
    end
    chain.sticky[tag] = severity
  end

  local triggered = 0
  for _, h in ipairs(chain.handlers) do
    if priority >= h.priority_min then
      local ok, err = pcall(h.fn, severity, priority, tag, message)
      if not ok then
        error("Handler error: " .. tostring(err))
      end
      triggered = triggered + 1
    end
  end

  return triggered > 0, "triggered " .. tostring(triggered) .. " handler(s)"
end

--- Acknowledge/clear a sticky alert.
function M.ack(chain, tag)
  chain.sticky[tag] = nil
  chain.cooldowns[tag] = nil
end

--- Build a simple logging handler (writes to io.stderr).
function M.stderr_handler()
  return function(severity, priority, tag, message)
    io.stderr:write(string.format(
      "[%s][%s] %s: %s\n",
      tag, priority, severity, message
    ))
  end
end

return M
