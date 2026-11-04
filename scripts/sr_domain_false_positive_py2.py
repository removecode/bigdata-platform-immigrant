# -*- coding: utf-8 -*-
"""Python 2.7：在 StarRocks 查 domain_false_positive 审计行。依赖 pymysql。

连接（勿把密码写进仓库，在 shell 里 export）：
  export SR_HOST=10.206.3.10
  export SR_PORT=32013
  export SR_USER=32966
  export SR_PASSWORD='...'
  export SR_CATALOG=paimon   # 若 csc 表在 paimon catalog 下则设置

运行：
  python2 sr_domain_false_positive_py2.py
"""
from __future__ import print_function

import os
import sys

import pymysql

SQL = """
SELECT dt, tenant, item_id
FROM csc.ods_csc_log_audit
WHERE day = 20261018
  AND app_id = 'domainreputation'
  AND str1 = 'domain_false_positive'
  AND str2 IN (
    'shurufa-sogou.sh.cn',
    'deepseek-sek.com.cn'
  )
"""


def main():
    for key in ('SR_HOST', 'SR_USER'):
        if not os.environ.get(key):
            print('missing env %s' % key, file=sys.stderr)
            sys.exit(2)

    conn = pymysql.connect(
        host=os.environ['SR_HOST'],
        port=int(os.environ.get('SR_PORT', '9030')),
        user=os.environ['SR_USER'],
        passwd=os.environ.get('SR_PASSWORD', ''),
        charset='utf8mb4',
        connect_timeout=10,
        read_timeout=int(os.environ.get('SR_READ_TIMEOUT', '3700')),
    )
    try:
        with conn.cursor() as cursor:
            catalog = os.environ.get('SR_CATALOG')
            if catalog:
                cursor.execute('SET CATALOG %s' % catalog)
            cursor.execute(SQL.strip())
            columns = [col[0] for col in cursor.description]
            count = 0
            for row in cursor:
                count += 1
                data = dict(zip(columns, row))
                print(data.get('dt'), data.get('tenant'), data.get('item_id'))
            print('[sr] done, total rows: %d' % count)
    finally:
        conn.close()


if __name__ == '__main__':
    main()
