-- ============================================================
-- 01_CREATE_TABLES.SQL
-- ============================================================
-- Creates all base tables for the World Cup 2026 project.
-- Run once before importing CSV data.
-- Tables are dropped and recreated where safe to do so.
-- Teams and squads are commented out to prevent accidental data loss
-- after manual corrections were applied directly to those tables.
-- ============================================================

--DROP TABLE IF EXISTS teams CASCADE;
CREATE TABLE teams (
    team_id INT PRIMARY KEY,
    country_name VARCHAR(100),
    fifa_rank INT,
    elo_rating INT,
    confederation VARCHAR(20)
);

-- DROP TABLE IF EXISTS matches CASCADE;
CREATE TABLE matches (
    match_id INT PRIMARY KEY,
    home_team_name VARCHAR(100),
    away_team_name VARCHAR(100),
    match_label VARCHAR(50)
);

--DROP TABLE IF EXISTS squads CASCADE;
CREATE TABLE squads (
    team_id INT,
    player_name VARCHAR(100),
    club_name VARCHAR(100)
);

--DROP TABLE IF EXISTS top5_leagues_clubs CASCADE;
CREATE TABLE top5_leagues_clubs (
    league VARCHAR(50),
    club VARCHAR(100)
);

-- home_score and away_score stored as VARCHAR to handle 'NA' values in source data
-- CAST to INT is applied downstream in views where arithmetic is needed
-- DROP TABLE IF EXISTS hist_results CASCADE;
CREATE TABLE hist_results (
    date DATE,
    home_team VARCHAR(100),
    away_team VARCHAR(100),
    home_score VARCHAR(10),
    away_score VARCHAR(10),
    tournament VARCHAR(100),
    city VARCHAR(100),
    country VARCHAR(100),
    neutral BOOLEAN
);

--DROP TABLE IF EXISTS world_elo_ratings CASCADE;
CREATE TABLE world_elo_ratings (
    country_name VARCHAR(100),
    elo_rating INT
);

-- 495 rows — one per valid combination of 8 qualifying third-place groups out of 12
-- DROP TABLE IF EXISTS third_place_bracket CASCADE;
CREATE TABLE third_place_bracket (
    combination_id INT,
    groups_advancing VARCHAR(20),
    slot_1A VARCHAR(5),
    slot_1B VARCHAR(5),
    slot_1D VARCHAR(5),
    slot_1E VARCHAR(5),
    slot_1G VARCHAR(5),
    slot_1I VARCHAR(5),
    slot_1K VARCHAR(5),
    slot_1L VARCHAR(5)
);
-- confirm 495 combinations loaded correctly
SELECT COUNT(*) FROM third_place_bracket;

-- see all current tables to confirm
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;