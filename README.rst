fb2psql
=======

Retrieves personal FitBit data and inserts it into a PostgreSQL database.  It
is a mixture of shell, Python, and R code that should run on any Unix-like
system where it is possible to install the required Python and R libraries.
Since Python and R will also run on Windows systems, it is conceivable this
could also work on that platform.

Designed to work with the data available from a Charge HR tracker, which should
mean it will also work with a Surge (minus location data). I don't know
why it wouldn’t work with other trackers, but some of the database views
will have columns without data (heart rate for most other trackers, for
example).

Setup
-----

You will need to register an app at http://dev.fitbit.com/ in order to get a
“Client (Consumer) Key”, and an “OAuth 2.0 Client ID.” Key options to select
when registering your app are an “OAuth 2.0 Application Type” of ``Server``,
and a Callback URL set to ``http://127.0.0.1:8080/``.  I set my “Default Access
Type” to ``Read-Only``, but that’s up to you.  Finally, send email to
``<api@fitbit.com>`` and ask for access to your personal Intraday Time Series
data.

Clone the repository:

.. code:: bash

    $ git clone https://github.com/cswingle/fb2psql.git

Set up the PostgreSQL database:

.. code:: bash

   $ createdb -h HOST -p PORT fitbit
   $ cat sql/fitbit_schema.sql | psql -h HOST -p PORT -d fitbit

Install the Python and R libraries:

.. code:: bash

   $ pip install -r python/requirements.txt
   $ R
   > install.packages(c('fitbitScraper', 'dplyr', 'RPostgreSQL', 'lubridate'))

Copy your Client (Consumer) Key and OAuth 2.0 Client ID into the Python
secrets file, ``python/fitbit_api_secrets.conf``, and populate the
database connection variables.

Fill in the database settings ``HOST``, ``DBNAME``, ``PORT``,
``DBUSER``, ``LOCAL_TZ``, and your FitBit account email and password
``FITBIT_EMAIL``, ``FITBIT_PASSWORD`` in ``r/get_fitbit_data.r``.

Fill in database connection variables ``HOST``, ``DBNAME``, and ``PORT``
in ``get_and_insert_fitbit.sh``.

Usage
-----

The Python and R scripts can be run individually, but best way to get
your data is to use the driver script, passing a date or multiple dates
for the data you want to retrieve and insert.

.. code:: bash

   $ ./get_and_insert_fitbit.sh 2015-10-17

TODO
----

* Add date as an argument to the R code:  The R code only gets
  yesterday's data, unlike the Python script which accepts the date to
  be downloaded as an argument.

* Consolidate database, account, and secrets into a single configuration
  file.

* Currently known to work with a Charge HR:  Update code to handle other
  trackers?

.. vim:ft=rst:fenc=utf-8:tw=72:ts=3:sw=3:sts=3
