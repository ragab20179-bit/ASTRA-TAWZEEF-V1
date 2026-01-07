"""
Minimal PostgreSQL connection helper.
Intentionally: NO pooling, NO retries.
"""
import os
import psycopg2


def get_conn():
    return psycopg2.connect(
        host=os.getenv("PG_HOST", "postgres"),
        port=int(os.getenv("PG_PORT", "5432")),
        dbname=os.getenv("PG_DB", "astra"),
        user=os.getenv("PG_USER", "astra"),
        password=os.getenv("PG_PASSWORD", "astra"),
        connect_timeout=int(os.getenv("PG_CONNECT_TIMEOUT", "2")),
    )
