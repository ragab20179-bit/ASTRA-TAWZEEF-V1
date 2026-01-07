-- Minimal runnable DDL baseline (use your official DDL v2 in production)
-- Single-row inserts, append-only.

CREATE TABLE IF NOT EXISTS astra_decision_artifacts (
  id uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  request_id uuid NOT NULL,
  actor_id text NOT NULL,
  actor_role text NOT NULL,
  domain text NOT NULL,
  action text NOT NULL,
  outcome text NOT NULL,
  reason_code text NOT NULL
);

CREATE TABLE IF NOT EXISTS tawzeef_execution_artifacts (
  id uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  astra_decision_id uuid NOT NULL,
  actor_id text NOT NULL,
  domain text NOT NULL,
  action text NOT NULL,
  outcome text NOT NULL
);

CREATE TABLE IF NOT EXISTS tawzeef_watcher_artifacts (
  id uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  astra_decision_id uuid NOT NULL,
  watcher_id text NOT NULL,
  domain text NOT NULL,
  action text NOT NULL,
  outcome text NOT NULL
);

-- Minimal indexes (keep lean for latency)
CREATE INDEX IF NOT EXISTS idx_astra_created_at ON astra_decision_artifacts (created_at);
CREATE INDEX IF NOT EXISTS idx_exec_created_at  ON tawzeef_execution_artifacts (created_at);
CREATE INDEX IF NOT EXISTS idx_watch_created_at ON tawzeef_watcher_artifacts (created_at);
