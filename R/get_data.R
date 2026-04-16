source("R/config.R")

# Packages
library(readr)
library(dplyr)
library(tidyr)
library(purrr)
library(glue)
library(stringr)
library(rairtable)

# Set up Airtable access
set_airtable_api_key(Sys.getenv("AIRTABLE_API_KEY"))

# Grab data tables from Airtable
data_gaps_at <- airtable("Data Gaps", airtable_base_id)
data_gaps <- read_airtable(data_gaps_at) |>
  as_tibble()

reports_at <- airtable("Reports", airtable_base_id)
reports <- read_airtable(reports_at) |>
  as_tibble()

types_at <- airtable("Gap Types", airtable_base_id)
types <- read_airtable(types_at) |>
  as_tibble()

topics_at <- airtable("Topics", airtable_base_id)
topics <- read_airtable(topics_at) |>
  as_tibble()

sources_at <- airtable("Data Sources", airtable_base_id)
sources <- read_airtable(sources_at) |>
  as_tibble() |>
  select(airtable_record_id, Source = Name)

# Join
data_gaps_data <- data_gaps |>
  filter(Publishable) |>
  # Link report and get info
  mutate(Report = unlist(`Report Link`)) |>
  left_join(reports, by = c("Report" = "airtable_record_id")) |>
  # Link Filters
  mutate(Type = map_chr(`Name (from Gap Types)`, ~ paste(.x, collapse = "; "))) |>
  mutate(Topics = map_chr(`Topic (from Topics)`, ~ paste(.x, collapse = "; "))) |>
  mutate(Sources = map_chr(`Name (from Sources)`, ~ paste(.x, collapse = "; ")))

data_gaps_table <- data_gaps_data |>
  mutate(
    across(
      any_of(topics$Topic),
      ~ if_else(
        is.na(.x),
        "",
        paste0(cur_column(), " (", .x, ")")
      )
    )
  ) |>
  mutate(across(any_of(topics$Topic), ~ na_if(.x, ""))) |>
  unite(Topics_Text, any_of(topics$Topic), sep = "; ", na.rm = TRUE) |>
  # Content for modal
  mutate(row_id = row_number()) |>
  rowwise() |>
  mutate(Link = glue("<button type='button' class='btn' id='{row_id}'>Details</button>")) |>
  select(Name, Sources, Topics, Type, Link,
    Headline, Questions = `Research Questions`, Impact,
    Update = `Contextual Update`, Evidence, Report = `Report Title`, Author,
    Date, URL, Topics_Text
  ) |>
  ungroup()
write_csv(data_gaps_table, "data/data_gaps_table.csv")

reports_data <- reports |>
  unnest_longer(`Data Gaps`) |>
  left_join(data_gaps, by = c("Data Gaps" = "airtable_record_id")) |>
  arrange(desc(Date)) |>
  # Filters
  mutate(Type = map_chr(`Name (from Gap Types)`, ~ paste(.x, collapse = "; "))) |>
  mutate(Topics = map_chr(`Topic (from Topics)`, ~ paste(.x, collapse = "; "))) |>
  mutate(Sources = map_chr(`Name (from Sources)`, ~ paste(.x, collapse = "; ")))

gaps_lookup <- reports_data |>
  mutate(
    Gap_Text = glue("<strong>{Name}</strong><p><b>Type of Data Gap: </b>{Type}<br><b>Sources: </b>{Sources} <br><b>Topics: </b>{Topics}</p>")
  ) |>
  select(airtable_record_id, Gap_Text) |>
  group_by(airtable_record_id) %>%
  summarise(GapText = str_c(Gap_Text, collapse = "<br>"))

sources_lookup <- reports_data |>
  select(airtable_record_id, Sources) |>
  distinct() |>
  group_by(airtable_record_id) %>%
  summarise(Sources = str_c(Sources, collapse = "; "))

types_lookup <- reports_data |>
  select(airtable_record_id, Type) |>
  distinct() |>
  group_by(airtable_record_id) %>%
  summarise(Type = str_c(Type, collapse = "; "))

topics_lookup <- reports_data |>
  select(airtable_record_id, Topics) |>
  distinct() |>
  group_by(airtable_record_id) %>%
  summarise(Topics = str_c(Topics, collapse = "; "))

reports_table <- reports_data |>
  select(-c(Sources, Topics, Type)) |>
  left_join(gaps_lookup, by = "airtable_record_id") |>
  left_join(sources_lookup, by = "airtable_record_id") |>
  left_join(types_lookup, by = "airtable_record_id") |>
  left_join(topics_lookup, by = "airtable_record_id") |>
  select(Title = `Report Title`, Author, Date, Sources, Topics, Type, GapText, URL) |>
  distinct() |>
  mutate(row_id = row_number()) |>
  mutate(URL = glue("<button type='button' class='btn btn-quarto' onclick='window.open(\"{URL}\", \"_blank\")'>View Report</button>")) |>
  mutate(Link = glue("<button type='button' class='btn' id='r-{row_id}'>Related Gaps</button>")) |>
  rowwise() |>
  select(Title, Author, Date, URL, Link, Sources, Topics, Type, GapText) |>
  ungroup()
write_csv(reports_table, "data/reports_table.csv")

# Drop down options
sources_opts <- sources |>
  select(Source) |>
  arrange(Source)
write_csv(sources_opts, "data/sources_opts.csv")

topics_opts <- topics |>
  select(Topic) |>
  arrange(Topic)
write_csv(topics_opts, "data/topics_opts.csv")

types_opts <- types |>
  select(Name, Description) |>
  arrange(Name)
write_csv(types_opts, "data/types_opts.csv")
