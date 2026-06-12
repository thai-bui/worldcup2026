##install.packages("RPostgres")
##install.packages("dplyr")
##install.packages("tidyr")

library(RPostgres)
library(dplyr)

con <- dbConnect(
  RPostgres::Postgres(),
  dbname = "world_cup_2026",
  host = "localhost",
  port = 5432,
  user = "postgres",
  password = "Buihoangthai2003"
)

## composite scores are the primary input to the simulation — all match
## probabilities derive from this view
team_scores <- dbGetQuery(con, "SELECT * FROM team_composite_score")

## Pull matches
matches <- dbGetQuery(con, "SELECT * FROM match_schedule")

## Pull teams
teams <- dbGetQuery(con, "SELECT * FROM teams")

## Pull third_place_combinations
third_place_combinations <- dbGetQuery(con, "SELECT * FROM third_place_combinations")

## Verify row counts before running simulation
## expected: 48 teams, 104 matches, 495 bracket combinations
print(head(team_scores))
print(nrow(matches))
print(nrow(teams))
print(nrow(third_place_combinations))
