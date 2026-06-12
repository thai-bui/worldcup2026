library(dplyr)
library(RPostgres)

## ============================================================
## 04_EXPORT_RESULTS.R
## ============================================================
## Writes all aggregated simulation outputs to PostgreSQL for
## Tableau to connect to directly.
## Must be run in the same R session as 03_aggregation.R.
## ============================================================

## Write all tables to PostgreSQL — overwrite on each run
dbWriteTable(con, "champion_probs", champion_probs, overwrite = TRUE)
dbWriteTable(con, "advancement_probs", advancement_probs, overwrite = TRUE)
dbWriteTable(con, "expected_round", expected_round, overwrite = TRUE)
dbWriteTable(con, "group_stats", group_stats, overwrite = TRUE)
dbWriteTable(con, "third_place_cutoff", third_place_cutoff, overwrite = TRUE)
dbWriteTable(con, "group_of_death", group_of_death, overwrite = TRUE)
dbWriteTable(con, "confederation_performance",confederation_performance, overwrite = TRUE)
dbWriteTable(con, "hardest_path", hardest_path, overwrite = TRUE)

## Verify all tables wrote correctly
cat("\nVerifying export:\n")
cat("champion_probs:", dbGetQuery(con, "SELECT COUNT(*) FROM champion_probs")[1,1], "rows\n")
cat("advancement_probs:", dbGetQuery(con, "SELECT COUNT(*) FROM advancement_probs")[1,1], "rows\n")
cat("expected_round:", dbGetQuery(con, "SELECT COUNT(*) FROM expected_round")[1,1], "rows\n")
cat("group_stats:", dbGetQuery(con, "SELECT COUNT(*) FROM group_stats")[1,1], "rows\n")
cat("third_place_cutoff:", dbGetQuery(con, "SELECT COUNT(*) FROM third_place_cutoff")[1,1], "rows\n")
cat("group_of_death:", dbGetQuery(con, "SELECT COUNT(*) FROM group_of_death")[1,1], "rows\n")
cat("confederation_performance:", dbGetQuery(con, "SELECT COUNT(*) FROM confederation_performance")[1,1], "rows\n")
cat("hardest_path:", dbGetQuery(con, "SELECT COUNT(*) FROM hardest_path")[1,1], "rows\n")

cat("\nExport complete.\n")

##exporting team composite score for Github - set to the correct working directory before doing this
write.csv(team_scores, "team_composite_score.csv", row.names = FALSE)

## export all tables to csv for Tableau - set to the correct working directory before doing this
write.csv(champion_probs, "champion_probs.csv", row.names = FALSE)
write.csv(advancement_probs, "advancement_probs.csv", row.names = FALSE)
write.csv(expected_round, "expected_round.csv", row.names = FALSE)
write.csv(group_stats, "group_stats.csv", row.names = FALSE)
write.csv(third_place_cutoff, "third_place_cutoff.csv", row.names = FALSE)
write.csv(group_of_death, "group_of_death.csv", row.names = FALSE)
write.csv(confederation_performance, "confederation_performance.csv", row.names = FALSE)
write.csv(hardest_path, "hardest_path.csv", row.names = FALSE)