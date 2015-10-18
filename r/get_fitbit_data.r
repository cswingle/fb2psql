# Uses the fitbitScraper library to pull data from the fitbit website
# and insert data into a PostgreSQL database.  Only the activity data
# is inserted; the rest is retrieved using the Python library

library(fitbitScraper)
library(dplyr)
library(RPostgreSQL)
library(lubridate)

HOST <- "DB_SERVER"
DBNAME <- "DATABASE_NAME"
PORT <- "DATABASE_PORT"
DBUSER <- "DATABASE_USER"
FITBIT_EMAIL <- "FITBIT_ACCOUNT_EMAIL"
FITBIT_PASSWORD <- "FITBIT_ACCOUNT_PASSWORD"
LOCAL_TZ <- "TIMEZONE"

fitbit_db <- src_postgres(host=HOST, dbname=DBNAME, port=PORT, user=DBUSER)
cookie <- login(email=FITBIT_EMAIL, password=FITBIT_PASSWORD)

today <- today()
today_str <- as.character(today)
yesterday <- today - days(1)
yesterday_str <- as.character(yesterday)

intraday <- get_intraday_data(cookie, what="heart-rate", date=yesterday_str)
df <- get_intraday_data(cookie, what="steps", date=yesterday_str)
intraday <- merge(intraday, df)
df <- get_intraday_data(cookie, what="distance", date=yesterday_str)
intraday <- merge(intraday, df)
df <- get_intraday_data(cookie, what="floors", date=yesterday_str)
intraday <- merge(intraday, df)
df <- get_intraday_data(cookie, what="active-minutes", date=yesterday_str)
intraday <- merge(intraday, df)
df <- get_intraday_data(cookie, what="calories-burned", date=yesterday_str)
intraday <- merge(intraday, df) %>%
    tbl_df() %>%
    transmute(dt=time,
              hr=ifelse(`heart-rate`==0, NA, `heart-rate`),
              steps=steps,
              miles=distance,
              floors=floors,
              activity_min=`active-minutes`,
              kcal=`calories-burned`)

activity <- get_activity_data(cookie, start_date=yesterday_str, end_date=yesterday_str)
activity <- activity %>%
    tbl_df() %>%
    filter(date==yesterday_str) %>%
    transmute(id=id,
              name=name,
              start_dt=parse_date_time(paste(date, gsub('([0-9:]+)(AM|PM)', '\\1 \\2', start_time)),
                                       '%Y-%m-%d %I:%M %p', tz=LOCAL_TZ),
              end_dt=start_dt+hours(duration_hours)+minutes(duration_minutes)+seconds(duration_seconds),
              hours=duration_hours+(duration_minutes/60)+(duration_seconds/3600),
              kcal=calories,
              steps=ifelse(steps=="", NA, as.integer(steps)),
              miles=ifelse(steps=="", NA, as.numeric(gsub('([0-9.]+).*', '\\1', distance)))) %>%
    arrange(start_dt)

steps <- get_daily_data(cookie, what="steps", start_date=yesterday_str, end_date=yesterday_str)
floors <- get_daily_data(cookie, what="floors", start_date=yesterday_str, end_date=yesterday_str)
daily <- merge(steps, floors) %>%
    transmute(dte=time, steps=steps, floors=floors)

sleep <- get_sleep_data(cookie, start_date=today_str, end_date=today_str)
sleep <- sleep$df %>%
    tbl_df() %>%
    filter(date==today) %>%
    mutate(start_hour=as.numeric(gsub('([0-9]+):.*', '\\1', startTime)),
           start_dt=ymd_hm(paste(date, startTime), tz=LOCAL_TZ),
           end_dt=ymd_hm(paste(date, endTime), tz=LOCAL_TZ)) %>%
    transmute(start_dt=as.POSIXct(ifelse(start_hour>12, start_dt-hours(24), start_dt),
                         origin="1970-01-01"),
              end_dt=end_dt,
              sleep_min=as.integer(sleepDuration),
              awake_n=as.integer(awakeCount),
              restless_n=as.integer(restlessCount),
              awake_min=as.integer(awakeDuration),
              restless_min=as.integer(awakeDuration),
              asleep_min=as.integer(minAsleep),
              quality_a=as.integer(sleepQualityScoreA),
              quality_b=as.numeric(sleepQualityScoreB)) %>%
    arrange(start_dt)

# dbWriteTable(fitbit_db$con, "intraday", intraday %>% data.frame(), append=TRUE, row.names=FALSE)
dbWriteTable(fitbit_db$con, "activity", activity %>% data.frame(), append=TRUE, row.names=FALSE)
# dbWriteTable(fitbit_db$con, "daily", daily %>% data.frame(), append=TRUE, row.names=FALSE)
# dbWriteTable(fitbit_db$con, "sleep", sleep %>% data.frame(), append=TRUE, row.names=FALSE)
