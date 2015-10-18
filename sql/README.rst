fb2psql SQL
===========

SQL to set up the database schema.  This could easily be adapted to
other SQL servers, but certain data types (``serial``, ``text``) might
need to be adapted to your server, and your database may not have
materialized views, so those would need to be included as standard
views.

Setup
-----

.. code:: bash

   $ createdb fitbit
   $ cat fitbit_schema.sql | psql -d fitbit

.. vim:ft=rst:fenc=utf-8:tw=72:ts=3:sw=3:sts=3

