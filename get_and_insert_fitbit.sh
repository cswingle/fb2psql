#! /bin/bash
# Usage: ./get_and_insert_fitbit.sh YYYY-mm-dd
#
# Retrieves fitbit data using get_fitbit_data.py and get_fitbit_data.r,
# transfers CSV files to database server via scp, copies into the database
# and refreshes materalized views.

dte=$1

HOST=SERVER_HOSTNAME
DBNAME=SERVER_DATABASE_NAME
PORT=DATABASE_PORT

if [ "x$dte" == "x" ]
then
    dte=$(date --date yesterday +%Y-%m-%d)
fi

./python/get_fitbit_data.py --csv-output $dte

scp daily_${dte}.csv intraday_${dte}.csv sleep_${dte}.csv $HOST:/tmp/.

psql -h $HOST -d $DBNAME -p $PORT \
     -c "COPY daily (dte, variable, value) FROM '/tmp/daily_${dte}.csv' WITH CSV HEADER;"
psql -h $HOST -d $DBNAME -p $PORT \
     -c "COPY intraday (dt, variable, value) FROM '/tmp/intraday_${dte}.csv' WITH CSV HEADER;"
psql -h $HOST -d $DBNAME -p $PORT \
    -c "COPY sleep (start_dt, variable, value) FROM '/tmp/sleep_${dte}.csv' WITH CSV HEADER;"

# Activity data
R --no-save < ./r/get_fitbit_data.r

psql -h $HOST -d $DBNAME -p $PORT \
    -c "REFRESH MATERIALIZED VIEW intraday_summary"
psql -h $HOST -d $DBNAME -p $PORT \
    -c "REFRESH MATERIALIZED VIEW sleep_summary"
psql -h $HOST -d $DBNAME -p $PORT \
    -c "REFRESH MATERIALIZED VIEW daily_summary"
