CREATE TABLE daily (
    id serial PRIMARY KEY,
    dte date,
    variable text,
    value numeric,
    UNIQUE (dte, variable)
);

CREATE TABLE sleep (
    id serial PRIMARY KEY,
    start_dt timestamp with time zone,
    variable text,
    value numeric,
    UNIQUE (start_dt, variable)
);

CREATE TABLE activity (
    id serial PRIMARY KEY,
    name text,
    start_dt timestamp with time zone,
    end_dt timestamp with time zone,
    hours numeric(8,4),
    kcal integer,
    steps integer,
    miles numeric,
    UNIQUE (start_dt)
);

CREATE TABLE intraday (
    id serial PRIMARY KEY,
    dt timestamp with time zone,
    variable text,
    value numeric,
    UNIQUE (dt, variable)
);

CREATE TABLE sleep_codes (
    id integer NOT NULL,
    sleep_code numeric,
    title text
);
COPY sleep_codes (id, sleep_code, title) FROM stdin;
1	1	asleep
2	2	awake
3	3	really awake
\.

CREATE MATERIALIZED VIEW intraday_summary AS
 SELECT dts.dt,
    round(dts.hr, 1) AS hr,
    round(dts.kcal, 4) AS kcal,
    dts.steps,
    dts.floors,
    round(dts.miles, 4) AS miles,
    s.title AS sleep,
    a.name AS activity
   FROM ((( SELECT date_trunc('minute'::text, intraday.dt) AS dt,
            avg(
                CASE
                    WHEN (intraday.variable = 'hr'::text) THEN intraday.value
                    ELSE NULL::numeric
                END) AS hr,
            max(
                CASE
                    WHEN (intraday.variable = 'kcal'::text) THEN intraday.value
                    ELSE NULL::numeric
                END) AS kcal,
            max(
                CASE
                    WHEN (intraday.variable = 'steps'::text) THEN intraday.value
                    ELSE NULL::numeric
                END) AS steps,
            max(
                CASE
                    WHEN (intraday.variable = 'floors'::text) THEN intraday.value
                    ELSE NULL::numeric
                END) AS floors,
            max(
                CASE
                    WHEN (intraday.variable = 'miles'::text) THEN intraday.value
                    ELSE NULL::numeric
                END) AS miles,
            max(
                CASE
                    WHEN (intraday.variable = 'sleep_code'::text) THEN intraday.value
                    ELSE NULL::numeric
                END) AS sleep_code
           FROM intraday
          GROUP BY date_trunc('minute'::text, intraday.dt)) dts
     LEFT JOIN sleep_codes s USING (sleep_code))
     LEFT JOIN activity a ON (((dts.dt >= a.start_dt) AND (dts.dt <= a.end_dt))))
  ORDER BY dts.dt
  WITH NO DATA;

CREATE MATERIALIZED VIEW sleep_summary AS
 SELECT sleep.start_dt,
    max(
        CASE
            WHEN (sleep.variable = 'sleep_min'::text) THEN sleep.value
            ELSE NULL::numeric
        END) AS sleep_min,
    max(
        CASE
            WHEN (sleep.variable = 'sleep_in_bed_min'::text) THEN sleep.value
            ELSE NULL::numeric
        END) AS in_bed_min,
    max(
        CASE
            WHEN (sleep.variable = 'sleep_to_fall_asleep_min'::text) THEN sleep.value
            ELSE NULL::numeric
        END) AS to_fall_asleep_min,
    max(
        CASE
            WHEN (sleep.variable = 'sleep_after_wakeup_min'::text) THEN sleep.value
            ELSE NULL::numeric
        END) AS after_wakeup_min,
    max(
        CASE
            WHEN (sleep.variable = 'sleep_awake_n'::text) THEN sleep.value
            ELSE NULL::numeric
        END) AS awake_n,
    max(
        CASE
            WHEN (sleep.variable = 'sleep_awake_min'::text) THEN sleep.value
            ELSE NULL::numeric
        END) AS awake_min,
    max(
        CASE
            WHEN (sleep.variable = 'sleep_restless_n'::text) THEN sleep.value
            ELSE NULL::numeric
        END) AS restless_n,
    max(
        CASE
            WHEN (sleep.variable = 'sleep_restless_min'::text) THEN sleep.value
            ELSE NULL::numeric
        END) AS restless_min
   FROM sleep
  GROUP BY sleep.start_dt
  ORDER BY sleep.start_dt
  WITH NO DATA;

CREATE MATERIALIZED VIEW daily_summary AS
 SELECT dtes.dte,
    dtes.resting_hr AS rest_hr,
    dtes.kcal,
    dtes.bmr_kcal,
    (dtes.kcal - dtes.bmr_kcal) AS ex_kcal,
    dtes.steps,
    dtes.floors,
    dtes.miles,
    dtes.sedentary_min AS sed_min,
    dtes.lightly_active_min AS light_min,
    dtes.fairly_active_min AS fair_min,
    dtes.very_active_min AS active_min,
    dtes.weight_lb,
    dtes.bmi,
    dtes.sleep_min,
    ((floor((dtes.sleep_min / (60)::numeric)) || ':'::text) ||
        btrim(to_char((dtes.sleep_min - (floor((dtes.sleep_min / (60)::numeric)) *
                        (60)::numeric)), '00'::text))) AS sleep_hhmm,
    dtes.hr_minutes AS hr_min
   FROM ( SELECT daily.dte,
            max(
                CASE
                    WHEN (daily.variable = 'resting_hr'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS resting_hr,
            max(
                CASE
                    WHEN (daily.variable = 'kcal'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS kcal,
            max(
                CASE
                    WHEN (daily.variable = 'bmr_kcal'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS bmr_kcal,
            max(
                CASE
                    WHEN (daily.variable = 'steps'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS steps,
            max(
                CASE
                    WHEN (daily.variable = 'floors'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS floors,
            max(
                CASE
                    WHEN (daily.variable = 'miles'::text) THEN round(daily.value, 2)
                    ELSE NULL::numeric
                END) AS miles,
            max(
                CASE
                    WHEN (daily.variable = 'sedentary_min'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS sedentary_min,
            max(
                CASE
                    WHEN (daily.variable = 'lightly_active_min'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS lightly_active_min,
            max(
                CASE
                    WHEN (daily.variable = 'fairly_active_min'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS fairly_active_min,
            max(
                CASE
                    WHEN (daily.variable = 'very_active_min'::text) THEN daily.value
                    ELSE NULL::numeric
                END) AS very_active_min,
            max(
                CASE
                    WHEN (daily.variable = 'weight_lb'::text) THEN round(daily.value, 1)
                    ELSE NULL::numeric
                END) AS weight_lb,
            max(
                CASE
                    WHEN (daily.variable = 'bmi'::text) THEN round(daily.value, 1)
                    ELSE NULL::numeric
                END) AS bmi,
            max(isum.hr_minutes) AS hr_minutes,
            max(ssum.sleep_min) AS sleep_min
           FROM ((daily
             LEFT JOIN ( SELECT date(intraday_summary.dt) AS dte,
                    sum(
                        CASE
                            WHEN (intraday_summary.hr IS NOT NULL) THEN 1
                            ELSE 0
                        END) AS hr_minutes
                   FROM intraday_summary
                  GROUP BY date(intraday_summary.dt)) isum USING (dte))
             LEFT JOIN ( SELECT date((sleep_summary.start_dt + '12:00:00'::interval)) AS dte,
                    sum(sleep_summary.sleep_min) AS sleep_min
                   FROM sleep_summary
                  GROUP BY date((sleep_summary.start_dt + '12:00:00'::interval))) ssum USING (dte))
          GROUP BY daily.dte) dtes
  ORDER BY dtes.dte
  WITH NO DATA;

CREATE MATERIALIZED VIEW daily_summary_activity_filter AS
 SELECT
        CASE
            WHEN ((to_char((l.dte)::timestamp with time zone, 'D'::text))::integer = 5) THEN 'R'::text
            ELSE "substring"(to_char((l.dte)::timestamp with time zone, 'DAY'::text), 1, 1)
        END AS dow,
    l.dte,
    l.avg_hr,
    a.all_avg_hr AS all_hr,
    l.steps,
    a.all_steps,
    l.floors,
    a.all_floors,
    l.miles,
    a.all_miles,
    daily_summary.light_min,
    daily_summary.fair_min,
    daily_summary.active_min,
    daily_summary.weight_lb,
    daily_summary.sleep_hhmm
   FROM ((( SELECT date(intraday_summary.dt) AS dte,
            round(avg(intraday_summary.hr), 1) AS avg_hr,
            sum(intraday_summary.steps) AS steps,
            sum(intraday_summary.floors) AS floors,
            sum(intraday_summary.miles) AS miles
           FROM intraday_summary
          WHERE ((intraday_summary.activity IS NULL) OR (intraday_summary.activity = 'Hike'::text))
          GROUP BY date(intraday_summary.dt)) l
     JOIN ( SELECT date(intraday_summary.dt) AS dte,
            round(avg(intraday_summary.hr), 1) AS all_avg_hr,
            sum(intraday_summary.steps) AS all_steps,
            sum(intraday_summary.floors) AS all_floors,
            sum(intraday_summary.miles) AS all_miles
           FROM intraday_summary
          GROUP BY date(intraday_summary.dt)) a USING (dte))
     JOIN daily_summary USING (dte))
  WHERE (l.dte > '2015-10-05'::date)
  ORDER BY l.dte
  WITH NO DATA;
