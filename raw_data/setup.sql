-- create tables to import available data
--DROP TABLE IF EXISTS teams;
CREATE TABLE teams (
    team_id INT PRIMARY KEY,
    country_name VARCHAR(100),
    fifa_rank INT,
    elo_rating INT,
    confederation VARCHAR(20)
);

DROP TABLE IF EXISTS matches;
CREATE TABLE matches (
    match_id INT PRIMARY KEY,
    home_team_name VARCHAR(100),
    away_team_name VARCHAR(100),
    match_label VARCHAR(50)
);


--DROP TABLE IF EXISTS squads;
CREATE TABLE squads (
    team_id INT,
    player_name VARCHAR(100),
    club_name VARCHAR(100)
);

--DROP TABLE IF EXISTS top5_leagues_clubs;
CREATE TABLE top5_leagues_clubs (
    league VARCHAR(50),
    club VARCHAR(100)
);

--DROP TABLE IF EXISTS hist_results;
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

-- see all current tables to confirm
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
