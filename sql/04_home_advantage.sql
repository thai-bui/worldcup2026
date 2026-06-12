-- ============================================================
-- 04_HOME_ADVANTAGE.SQL
-- ============================================================
-- Adds a binary home advantage indicator to the teams table.
-- Only applies to the 3 host nations: USA, Canada, Mexico.
-- Weighted at 5% in the composite score model.
-- ============================================================

ALTER TABLE teams ADD COLUMN home_advantage INT DEFAULT 0; -- default 0 for all teams

UPDATE teams
SET home_advantage = 1
WHERE country_name IN ('USA', 'Canada', 'Mexico');