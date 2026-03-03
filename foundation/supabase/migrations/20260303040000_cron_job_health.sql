-- =============================================================================
-- PILAR ERP — Foundation Gap: Cron Job Health Tracking
-- =============================================================================
-- Adds cron_job_runs table for tracking custom job executions.
-- Complements the existing v_cron_job_health view (which reads cron.job_run_details)
-- with a dedicated application-level table for jobs that need custom logging.
-- =============================================================================

-- ─── 1. Custom job runs table ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cron_job_runs (
  id            BIGSERIAL PRIMARY KEY,
  job_name      TEXT NOT NULL,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at   TIMESTAMPTZ,
  success       BOOLEAN,
  error_msg     TEXT,
  rows_affected INT
);

CREATE INDEX IF NOT EXISTS idx_cron_runs_job
  ON public.cron_job_runs(job_name, started_at DESC);

-- ─── 2. Application-level health view ───────────────────────────────────────
-- Named differently from the existing v_cron_job_health to avoid conflict.
CREATE OR REPLACE VIEW public.v_cron_app_job_health AS
SELECT
  job_name,
  MAX(started_at) AS last_run,
  BOOL_AND(success) FILTER (WHERE started_at > now() - INTERVAL '7 days') AS healthy_7d,
  COUNT(*) FILTER (WHERE NOT success AND started_at > now() - INTERVAL '7 days') AS failures_7d,
  COUNT(*) AS total_runs
FROM public.cron_job_runs
GROUP BY job_name;

-- ─── 3. Grants ──────────────────────────────────────────────────────────────
-- Only admin roles should see job health data
GRANT SELECT ON public.cron_job_runs TO authenticated;
GRANT SELECT ON public.v_cron_app_job_health TO authenticated;

-- ─── 4. Helper function to log a job run ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.log_cron_job_run(
  p_job_name    TEXT,
  p_success     BOOLEAN,
  p_error_msg   TEXT DEFAULT NULL,
  p_rows        INT DEFAULT NULL,
  p_started_at  TIMESTAMPTZ DEFAULT now()
)
RETURNS BIGINT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.cron_job_runs(job_name, started_at, finished_at, success, error_msg, rows_affected)
  VALUES (p_job_name, p_started_at, now(), p_success, p_error_msg, p_rows)
  RETURNING id;
$$;

-- Only service_role should call this (from pg_cron jobs or Edge Functions)
REVOKE EXECUTE ON FUNCTION public.log_cron_job_run FROM PUBLIC, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.log_cron_job_run TO service_role;

-- ─── 5. pg_cron cleanup for old runs (90 days) ─────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('cleanup-cron-job-runs')
    FROM cron.job WHERE jobname = 'cleanup-cron-job-runs';

    PERFORM cron.schedule(
      'cleanup-cron-job-runs',
      '30 3 * * *',
      $$DELETE FROM public.cron_job_runs WHERE started_at < now() - INTERVAL '90 days'$$
    );
  END IF;
END $$;
