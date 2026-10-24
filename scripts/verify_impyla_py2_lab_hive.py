#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Smoke-test impyla 0.14.x on Python 2 against lab Hive (ACT-033).

Lab HS2: hive.server2.authentication=NONE (see /opt/lab/hive/conf/hive-site.xml).
impyla 0.14 still needs auth_mechanism='PLAIN' here; NOSASL is rejected (TSocket read 0).

If PLAIN fails with "no worthy mechs", uninstall the Cyrus-backed `sasl` pip package so
impyla falls back to pure-sasl (impala.sasl_compat). Do not pass password=''; omit
password or use any non-empty placeholder (empty password fails OpenSession on lab).
"""
from __future__ import print_function

import sys

from impala.dbapi import connect


def main():
    host = '127.0.0.1'
    port = 10000
    user = 'ubuntu'
    conn = connect(host=host, port=port, user=user, auth_mechanism='PLAIN')
    cur = conn.cursor()
    cur.execute('SELECT 1 AS n')
    print('SELECT 1:', cur.fetchall())
    cur.execute('SELECT COUNT(*) FROM lab.ioc_hit')
    print('ioc_hit count:', cur.fetchall())
    cur.execute('SELECT ioc_value FROM lab.ioc_hit LIMIT 3')
    print('sample:', cur.fetchall())
    conn.close()
    print('OK python', sys.version.split()[0])
    return 0


if __name__ == '__main__':
    sys.exit(main())
