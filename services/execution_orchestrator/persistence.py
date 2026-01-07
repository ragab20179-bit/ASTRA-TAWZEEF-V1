from uuid import uuid4
from shared.db import get_conn


def insert_execution(astra_decision_id: str, payload: dict, outcome: str) -> str:
    execution_id = str(uuid4())
    conn = get_conn()
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO tawzeef_execution_artifacts (
                        id, astra_decision_id, actor_id, domain, action, outcome
                    ) VALUES (%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        execution_id,
                        astra_decision_id,
                        payload["actor"]["id"],
                        payload["context"]["domain"],
                        payload["context"]["action"],
                        outcome,
                    ),
                )
        return execution_id
    finally:
        conn.close()
