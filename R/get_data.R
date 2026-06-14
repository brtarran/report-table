source("R/config.R")

# Packages
library(readr)
library(dplyr)
library(tidyr)
library(purrr)
library(glue)
library(stringr)
library(rairtable)

# Set up Airtable access (API key must be in AIRTABLE_API_KEY env var)
set_airtable_api_key(Sys.getenv("AIRTABLE_API_KEY"))

# Prefer a local sample CSV for testing when available
sample_path_env <- Sys.getenv("SAMPLE_REPORTS_CSV", unset = "")
local_data_path <- if (nzchar(sample_path_env)) sample_path_env else "data/sample_reports.csv"

if (file.exists(local_data_path)) {
  message("Using local sample CSV for reports: ", local_data_path)
  reports_raw <- readr::read_csv(local_data_path, col_types = readr::cols(.default = "c")) |> as_tibble()
} else {
  # Read from Airtable when no local sample is available
  reports_at <- airtable("Research Reports", airtable_base_id)
  reports_raw <- read_airtable(reports_at) |> as_tibble()
}

reports_raw <- reports_raw |>
  filter(`Publication Status` == "Published")

expected_cols <- c("Title", "Authors", "Publication Date", "Description",
                    "Report Format", "Publication Status", "URL",
                    "Publication type", "Topic/theme")

missing_cols <- setdiff(expected_cols, names(reports_raw))
reports_raw[missing_cols] <- NA

# Normalize and extract fields we need
normalize_multi_value <- function(value) {
  if (is.null(value) || length(value) == 0 || all(is.na(value))) {
    return("")
  }
  if (is.list(value)) {
    value <- unlist(value)
  }
  if (!is.character(value)) {
    value <- as.character(value)
  }
  value <- value[!is.na(value) & value != ""]
  if (length(value) == 0) {
    return("")
  }
  parts <- str_split(value, "\\s*[;,]\\s*") |> unlist()
  parts <- str_trim(parts)
  parts <- parts[parts != ""]
  if (length(parts) == 0) {
    return("")
  }
  paste(unique(parts), collapse = "; ")
}

reports <- reports_raw |>
  mutate(
    Title = coalesce(Title, ""),
    Authors = coalesce(Authors, ""),
    Date = coalesce(as.character(`Publication Date`), ""),
    Description = coalesce(Description, ""),
    Report_Format = coalesce(`Report Format`, ""),
    Publication_Status = coalesce(`Publication Status`, ""),
    URL = coalesce(!!rlang::sym("URL"), "")
  ) |>
  mutate(
    Type = map_chr(.data[["Publication type"]], normalize_multi_value),
    Topics = map_chr(.data[["Topic/theme"]], normalize_multi_value)
  )

# Description snippet for table
reports <- reports |>
  mutate(Description_snippet = if_else(nchar(Description) > 200, paste0(str_sub(Description, 1, 200), "..."), Description))

# Row ids and link button for modal
reports <- reports |>
  mutate(row_id = row_number()) |>
  rowwise() |>
  mutate(Link = glue("<button type='button' class='btn' id='r-{row_id}'>Details</button>")) |>
  ungroup()

# Output the main reports table CSV used by OJS
reports_table <- reports |>
  transmute(
    Title = Title,
    Authors = Authors,
    Date = Date,
    Topics = Topics,
    Type = Type,
    Description_snippet = Description_snippet,
    Description = Description,
    Report_Format = Report_Format,
    Publication_Status = Publication_Status,
    URL = URL,
    Link = Link,
    row_id = row_id
  )

write_csv(reports_table, "data/reports_table.csv")

# Build option CSVs for filters (deduplicated)
extract_opts <- function(x) {
  # x is a character vector where entries may use commas or semicolons as separators
  vals <- x[ x != "" ]
  if (length(vals) == 0) return(tibble(Value = character()))
  parts <- str_split(vals, "\\s*[;,]\\s*") |> unlist()
  parts <- str_trim(parts)
  parts <- parts[ parts != "" ]
  tibble(Value = sort(unique(parts)))
}

publication_types_opts <- extract_opts(reports_table$Type)
colnames(publication_types_opts) <- c("Publication type")
write_csv(publication_types_opts, "data/publication_types_opts.csv")

topics_opts <- extract_opts(reports_table$Topics)
colnames(topics_opts) <- c("Topic/theme")
write_csv(topics_opts, "data/topics_opts.csv")

message("Wrote data/reports_table.csv, data/publication_types_opts.csv, data/topics_opts.csv")
