-- Keep personalization storage proportional to recent distinct interactions.
-- Cleanup is scoped to the member currently generating a signal and uses the
-- recent-user index, avoiding a global maintenance scan on the request path.

create or replace function public._upsert_recommendation_signal(
  p_user_id uuid,
  p_content_kind text,
  p_content_id uuid,
  p_signal_type text,
  p_increment integer default 1,
  p_deduplicate_for interval default interval '0 seconds'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.recommendation_signals
  where user_id = p_user_id
    and last_occurred_at < pg_catalog.now() - interval '180 days';

  insert into public.recommendation_signals (
    user_id,
    content_kind,
    content_id,
    signal_type,
    occurrence_count
  )
  values (
    p_user_id,
    p_content_kind,
    p_content_id,
    p_signal_type,
    least(greatest(p_increment, 1), 1000)
  )
  on conflict (user_id, content_kind, content_id, signal_type)
  do update set
    occurrence_count = case
      when public.recommendation_signals.last_occurred_at
        <= pg_catalog.now() - p_deduplicate_for
      then least(
        public.recommendation_signals.occurrence_count
          + least(greatest(p_increment, 1), 1000),
        1000
      )
      else public.recommendation_signals.occurrence_count
    end,
    last_occurred_at = case
      when public.recommendation_signals.last_occurred_at
        <= pg_catalog.now() - p_deduplicate_for
      then pg_catalog.now()
      else public.recommendation_signals.last_occurred_at
    end;
end;
$$;

revoke all on function public._upsert_recommendation_signal(
  uuid, text, uuid, text, integer, interval
) from public, anon, authenticated;

comment on function public._upsert_recommendation_signal(
  uuid, text, uuid, text, integer, interval
) is 'Aggregates a recommendation signal and removes that member''s signals older than 180 days.';
