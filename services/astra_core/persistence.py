from uuid import uuid4
from shared.db import get_conn


def insert_decision(payload: dict, outcome: str, reason_code: str) -> str:
    decision_id = str(uuid4())
    conn = get_conn()
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO astra_decision_artifacts (
                        id, request_id, actor_id, actor_role, domain, action, outcome, reason_code
                    ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        decision_id,
                        payload["request_id"],
                        payload["actor"]["id"],
                        payload["actor"]["role"],
                        payload["context"]["domain"],
                        payload["context"]["action"],
                        outcome,
                        reason_code,
                    ),
                )
        return decision_id
    finally:
        conn.close()
