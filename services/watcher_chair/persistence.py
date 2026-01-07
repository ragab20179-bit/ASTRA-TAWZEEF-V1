from uuid import uuid4
from shared.db import get_conn


def insert_watcher(astra_decision_id: str, watcher_id: str, payload: dict, outcome: str) -> str:
    watcher_artifact_id = str(uuid4())
    conn = get_conn()
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO tawzeef_watcher_artifacts (
                        id, astra_decision_id, watcher_id, domain, action, outcome
                    ) VALUES (%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        watcher_artifact_id,
                        astra_decision_id,
                        watcher_id,
                        payload["context"]["domain"],
                        payload["context"]["action"],
                        outcome,
                    ),
                )
        return watcher_artifact_id
    finally:
        conn.close()
