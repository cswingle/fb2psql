#! /usr/bin/env python
# vim: set fileencoding=utf-8 :
from __future__ import print_function
from __future__ import unicode_literals
usage = """\
Obtains an OAuth2 token, downloads fitbit data, and does something with it.
"""
# Copyright © 2015, Christopher Swingley <cswingle@swingleydev.com>
# Licensed under the terms of the GNU General Public Licence v2
import argparse
import sys
import logging
import os
import csv
import pickle

import datetime
from dateutil import parser
import psycopg2
import psycopg2.extras

import cherrypy
import threading
import traceback
import webbrowser

# from base64 import b64encode
from fitbit.api import FitbitOauth2Client
from oauthlib.oauth2.rfc6749.errors import MismatchingStateError, MissingTokenError
# from requests_oauthlib import OAuth2Session

import fitbit

argparser = argparse.ArgumentParser(
    description=usage,
    formatter_class=argparse.RawDescriptionHelpFormatter)
group = argparser.add_mutually_exclusive_group()
group.add_argument("-v", "--verbose", action="store_true", dest="verbose",
                   default=True, help="be more verbose")
group.add_argument("-q", "--quiet", action="store_false", dest="verbose",
                   default=True, help="be quiet")
argparser.add_argument("-a", "--atomic-transactions", action="store_true", dest="atomic",
                       default=False, help="use atomic transactions (safe and slow)")
argparser.add_argument("-n", "--dry-run", action="store_true", dest="dry_run",
                       default=False, help="don't insert into database, just show statements")
argparser.add_argument("-c", "--csv-output", action="store_true", dest="csv_output",
                       default=False, help="dump data to a pair of date-stamped CSV files")
argparser.add_argument("-k", "--secret-file", default="fitbit_api_secrets.conf")
argparser.add_argument("date", nargs="+", help="date")

args = argparser.parse_args()


if args.verbose:
    logger = logging.getLogger('root')
    logger.setLevel(logging.INFO)
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    formatter = logging.Formatter("%(name)-12s: %(levelname)-8s %(message)s")
    console.setFormatter(formatter)
    logger.addHandler(console)


class OAuth2Server:
    # Code from python-fitbit example script gather_keys_oauth2.py,
    # Copyright 2012-2015 ORCAS, Licensed under the Apache License, Version 2.0
    def __init__(self, client_id, client_secret,
                 redirect_uri='http://127.0.0.1:8080/'):
        """ Initialize the FitbitOauth2Client """
        self.redirect_uri = redirect_uri
        self.success_html = """
            <h1>You are now authorized to access the Fitbit API!</h1>
            <br/><h3>You can close this window</h3>"""
        self.failure_html = """
            <h1>ERROR: %s</h1><br/><h3>You can close this window</h3>%s"""
        self.oauth = FitbitOauth2Client(client_id, client_secret)

    def browser_authorize(self):
        """
        Open a browser to the authorization url and spool up a CherryPy
        server to accept the response
        """
        url, _ = self.oauth.authorize_token_url(redirect_uri=self.redirect_uri)
        # Open the web browser in a new thread for command-line browser support
        threading.Timer(1, webbrowser.open, args=(url,)).start()
        cherrypy.quickstart(self)

    @cherrypy.expose
    def index(self, state, code=None, error=None):
        """
        Receive a Fitbit response containing a verification code. Use the code
        to fetch the access_token.
        """
        error = None
        if code:
            try:
                self.oauth.fetch_access_token(code, self.redirect_uri)
            except MissingTokenError:
                error = self._fmt_failure(
                    'Missing access token parameter.</br>Please check that '
                    'you are using the correct client_secret')
            except MismatchingStateError:
                error = self._fmt_failure('CSRF Warning! Mismatching state')
        else:
            error = self._fmt_failure('Unknown error while authenticating')
        # Use a thread to shutdown cherrypy so we can return HTML first
        self._shutdown_cherrypy()
        return error if error else self.success_html

    def _fmt_failure(self, message):
        tb = traceback.format_tb(sys.exc_info()[2])
        tb_html = '<pre>%s</pre>' % ('\n'.join(tb)) if tb else ''
        return self.failure_html % (message, tb_html)

    def _shutdown_cherrypy(self):
        """ Shutdown cherrypy in one second, if it's running """
        if cherrypy.engine.state == cherrypy.engine.states.STARTED:
            threading.Timer(1, cherrypy.engine.exit).start()

with open(args.secret_file, 'r') as inf:
    for line in inf:
        (key, value) = [x.strip() for x in line.split('=')]
        if key == 'oauth2_client':
            oauth2_client = value
        elif key == 'client_secret':
            client_secret = value
        elif key == 'host':
            host = value
        elif key == 'dbname':
            dbname = value
        elif key == 'port':
            port = value
        elif key == 'dbuser':
            dbuser = value

server = OAuth2Server(oauth2_client, client_secret)
server.browser_authorize()

access_token = server.oauth.token['access_token']
refresh_token = server.oauth.token['refresh_token']

authd_client = fitbit.Fitbit(oauth2_client, client_secret, oauth2=True,
                             access_token=access_token,
                             refresh_token=refresh_token)

# Output arrays
daily = []
sleep = []
intraday = []
weight = []

for dte_str in args.date:
    dte = parser.parse(dte_str).date()

    sleeps = authd_client.get_sleep(dte)
    weight = authd_client.get_bodyweight(dte)
    bmr_kcal_day = authd_client.time_series('activities/caloriesBMR', period='1d', base_date=dte_str)
    hr = authd_client.intraday_time_series('activities/heart', base_date=dte_str, detail_level='1sec')
    steps = authd_client.intraday_time_series('activities/steps', base_date=dte_str, detail_level='1min')
    kcal = authd_client.intraday_time_series('activities/calories', base_date=dte_str, detail_level='1min')
    miles = authd_client.intraday_time_series('activities/distance', base_date=dte_str, detail_level='1min')
    floors = authd_client.intraday_time_series('activities/floors', base_date=dte_str, detail_level='1min')
    activity = authd_client._COLLECTION_RESOURCE('activities', date=dte)

    # make a huge object
    data = {
        'sleep': sleeps,
        'weight': weight,
        'bmr_kcal_day': bmr_kcal_day,
        'steps': steps,
        'kcal': kcal,
        'floors': floors,
        'miles': miles,
        'hr': hr,
        'activity': activity,
    }

    with open('data_{dte_str}.pickle'.format(dte_str=dte_str), 'wb') as of:
        pickle.dump(data, of, pickle.HIGHEST_PROTOCOL)

    # heart rate data
    for hr_summary in data['hr']['activities-heart']:
        date = parser.parse(hr_summary['dateTime']).date()
        resting_hr = hr_summary['value']['restingHeartRate']
        daily.append({'dte': date, 'variable': 'resting_hr', 'value': resting_hr})

    for d in data['hr']['activities-heart-intraday']['dataset']:
        dt = parser.parse(data['hr']['activities-heart'][0]['dateTime'] + ' ' + d['time'])
        intraday.append({'dt': dt, 'variable': 'hr', 'value': d['value']})

    # sleep
    for sleep_event in data['sleep']['sleep']:
        start_dt = parser.parse(sleep_event['startTime'])
        sleep.append({'start_dt': start_dt, 'variable': 'sleep_in_bed_min',
                      'value': sleep_event['timeInBed']})
        sleep.append({'start_dt': start_dt, 'variable': 'sleep_to_fall_asleep_min',
                      'value': sleep_event['minutesToFallAsleep']})
        sleep.append({'start_dt': start_dt, 'variable': 'sleep_min',
                      'value': sleep_event['minutesAsleep']})
        sleep.append({'start_dt': start_dt, 'variable': 'sleep_after_wakeup_min',
                      'value': sleep_event['minutesAfterWakeup']})
        sleep.append({'start_dt': start_dt, 'variable': 'sleep_awake_min',
                      'value': sleep_event['awakeDuration']})
        sleep.append({'start_dt': start_dt, 'variable': 'sleep_restless_min',
                      'value': sleep_event['restlessDuration']})
        sleep.append({'start_dt': start_dt, 'variable': 'sleep_awake_n',
                      'value': sleep_event['awakeCount']})
        sleep.append({'start_dt': start_dt, 'variable': 'sleep_restless_n',
                      'value': sleep_event['restlessCount']})

        start_date = start_dt.date()
        last_hour = start_dt.time().hour
        for d in sleep_event['minuteData']:
            hour = parser.parse(d['dateTime']).time().hour
            if hour < last_hour:  # cross date
                dt = parser.parse(str(start_date) + ' ' + d['dateTime']) + datetime.timedelta(hours=24)
            else:
                dt = parser.parse(str(start_date) + ' ' + d['dateTime'])
            intraday.append({'dt': dt, 'variable': 'sleep_code',
                            'value': d['value']})

    # weight
    weights_dict = {}
    for weight_data in data['weight']['weight']:
        date = weight_data['date']
        if date not in weights_dict:
            weights_dict[date] = {}
            weights_dict[date]['weight_lb'] = []
            weights_dict[date]['bmi'] = []
        weights_dict[date]['weight_lb'].append(weight_data['weight'])
        weights_dict[date]['bmi'].append(weight_data['bmi'])

    for dte in weights_dict:
        if len(weights_dict[dte]['weight_lb']):
            weight_lb = float(sum(weights_dict[dte]['weight_lb'])/len(weights_dict[dte]['weight_lb']))
            daily.append({'dte': date, 'variable': 'weight_lb', 'value': weight_lb})
        if len(weights_dict[dte]['bmi']):
            bmi = float(sum(weights_dict[dte]['bmi'])/len(weights_dict[dte]['bmi']))
            daily.append({'dte': date, 'variable': 'bmi', 'value': bmi})

    # calories
    for bmr_kcal in data['bmr_kcal_day']['activities-caloriesBMR']:
        date = parser.parse(bmr_kcal['dateTime']).date()
        daily.append({'dte': date, 'variable': 'bmr_kcal', 'value': bmr_kcal['value']})

    for kcal_summary in data['kcal']['activities-calories']:
        date = parser.parse(kcal_summary['dateTime']).date()
        daily.append({'dte': date, 'variable': 'kcal', 'value': kcal_summary['value']})

    for d in data['kcal']['activities-calories-intraday']['dataset']:
        dt = parser.parse(data['kcal']['activities-calories'][0]['dateTime'] + ' ' + d['time'])
        intraday.append({'dt': dt, 'variable': 'kcal', 'value': d['value']})

    # miles
    for miles_summary in data['miles']['activities-distance']:
        date = parser.parse(miles_summary['dateTime']).date()
        daily.append({'dte': date, 'variable': 'miles', 'value': miles_summary['value']})

    for d in data['miles']['activities-distance-intraday']['dataset']:
        dt = parser.parse(data['miles']['activities-distance'][0]['dateTime'] + ' ' + d['time'])
        intraday.append({'dt': dt, 'variable': 'miles', 'value': d['value']})

    # steps
    for steps_summary in data['steps']['activities-steps']:
        date = parser.parse(steps_summary['dateTime']).date()
        daily.append({'dte': date, 'variable': 'steps', 'value': steps_summary['value']})

    for d in data['steps']['activities-steps-intraday']['dataset']:
        dt = parser.parse(data['steps']['activities-steps'][0]['dateTime'] + ' ' + d['time'])
        intraday.append({'dt': dt, 'variable': 'steps', 'value': d['value']})

    # floors
    for floors_summary in data['floors']['activities-floors']:
        date = parser.parse(floors_summary['dateTime']).date()
        daily.append({'dte': date, 'variable': 'floors', 'value': floors_summary['value']})

    for d in data['floors']['activities-floors-intraday']['dataset']:
        dt = parser.parse(data['floors']['activities-floors'][0]['dateTime'] + ' ' + d['time'])
        intraday.append({'dt': dt, 'variable': 'floors', 'value': d['value']})

    # activity
    activity_summary = data['activity']['summary']
    daily.append({'dte': date, 'variable': 'elevation', 'value': activity_summary['elevation']})
    daily.append({'dte': date, 'variable': 'sedentary_min', 'value': activity_summary['sedentaryMinutes']})
    daily.append({'dte': date, 'variable': 'lightly_active_min',
                'value': activity_summary['lightlyActiveMinutes']})
    daily.append({'dte': date, 'variable': 'fairly_active_min',
                'value': activity_summary['fairlyActiveMinutes']})
    daily.append({'dte': date, 'variable': 'very_active_min', 'value': activity_summary['veryActiveMinutes']})

# daily output
if args.csv_output:
    daily_filename = 'daily_' + dte_str + '.csv'
    daily_file = open(daily_filename, 'w')
    writer = csv.writer(daily_file, lineterminator='\n')
    writer.writerow(('dte', 'variable', 'value'))
else:
    if not args.dry_run:
        connection = psycopg2.connect(
            host=host, database=dbname, port=port, user=dbuser,
            application_name=os.path.basename(__file__))
        cursor = connection.cursor()
for day in daily:
    if args.csv_output:
        writer.writerow((day['dte'], day['variable'], day['value']))
    else:
        query = ("INSERT INTO daily (dte, variable, value) "
                 "VALUES (%s, %s, %s);")
        params = (day['dte'], day['variable'], day['value'])
        if not args.dry_run:
            logger.info(cursor.mogrify(query, params).decode())
            try:
                cursor.execute(query, params)
            except Exception as e:
                logger.warning(str(e).strip())
                connection.rollback()
            else:
                if args.atomic:
                    connection.commit()
        else:
            print(("INSERT INTO daily (dte, variable, value) "
                   "VALUES ('{dte}', '{variable}', {value});").format(**day))
if args.csv_output:
    daily_file.close()
else:
    if not args.atomic and not args.dry_run:
        connection.commit()

# intraday output
if args.csv_output:
    intraday_filename = 'intraday_' + dte_str + '.csv'
    intraday_file = open(intraday_filename, 'w')
    writer = csv.writer(intraday_file, lineterminator='\n')
    writer.writerow(('dt', 'variable', 'value'))
for minute in intraday:
    if args.csv_output:
        writer.writerow((minute['dt'], minute['variable'], minute['value']))
    else:
        query = ("INSERT INTO intraday (dt, variable, value) "
                 "VALUES (%s, %s, %s);")
        params = (minute['dt'], minute['variable'], minute['value'])
        if not args.dry_run:
            logger.info(cursor.mogrify(query, params).decode())
            try:
                cursor.execute(query, params)
            except Exception as e:
                logger.warning(str(e).strip())
                connection.rollback()
            else:
                if args.atomic:
                    connection.commit()
        else:
            print(("INSERT INTO intraday (dt, variable, value) "
                   "VALUES ('{dt}', '{variable}', {value});").format(**minute))
if args.csv_output:
    intraday_file.close()
else:
    if not args.atomic and not args.dry_run:
        connection.commit()

if not args.dry_run and not args.csv_output:
    cursor.close()
    connection.close()

# sleep output
if args.csv_output:
    sleep_filename = 'sleep_' + dte_str + '.csv'
    sleep_file = open(sleep_filename, 'w')
    writer = csv.writer(sleep_file, lineterminator='\n')
    writer.writerow(('start_dt', 'variable', 'value'))
for day in sleep:
    if args.csv_output:
        writer.writerow((day['start_dt'], day['variable'], day['value']))
    else:
        query = ("INSERT INTO sleep (start_dt, variable, value) "
                 "VALUES (%s, %s, %s);")
        params = (day['start_dt'], day['variable'], day['value'])
        if not args.dry_run:
            logger.info(cursor.mogrify(query, params).decode())
            try:
                cursor.execute(query, params)
            except Exception as e:
                logger.warning(str(e).strip())
                connection.rollback()
            else:
                if args.atomic:
                    connection.commit()
        else:
            print(("INSERT INTO sleep (start_dt, variable, value) "
                   "VALUES ('{start_dt}', '{variable}', {value});").format(**day))
if args.csv_output:
    sleep_file.close()
else:
    if not args.atomic and not args.dry_run:
        connection.commit()
