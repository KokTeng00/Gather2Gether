-- Keep high-accuracy reranking affordable at scale. Fresh behavior continues
-- to affect the local semantic rank immediately; only the paid cross-encoder
-- refresh is held to one attempt per member and surface every six hours.

create function public._enforce_ai_recommendation_cache_ttl()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.expires_at := pg_catalog.now() + interval '6 hours';
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

revoke all on function public._enforce_ai_recommendation_cache_ttl()
  from public, anon, authenticated;

create trigger ai_recommendation_cache_enforce_ttl
before insert or update on public.ai_recommendation_cache
for each row execute function public._enforce_ai_recommendation_cache_ttl();

create or replace function public.claim_ai_recommendation_rerank(p_surface text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  claimed boolean := false;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_surface is null or p_surface not in ('event', 'forum_post') then
    raise exception using errcode = '22023', message = 'invalid_recommendation_surface';
  end if;

  insert into public.ai_recommendation_throttle (
    user_id,
    surface,
    next_allowed_at
  ) values (
    current_user_id,
    p_surface,
    pg_catalog.now() + interval '6 hours'
  )
  on conflict (user_id, surface)
  do update set
    next_allowed_at = excluded.next_allowed_at,
    updated_at = pg_catalog.now()
  where public.ai_recommendation_throttle.next_allowed_at <= pg_catalog.now()
  returning true into claimed;

  return coalesce(claimed, false);
end;
$$;

comment on table public.ai_recommendation_cache is
  'Six-hour per-user cross-encoder ordering cache; inaccessible through direct table APIs.';
comment on table public.ai_recommendation_throttle is
  'Per-user model-call ceiling that coalesces concurrent recommendation refreshes.';
comment on function public.claim_ai_recommendation_rerank(text) is
  'Atomically permits at most one recommendation model attempt per member and surface every six hours.';
comment on function public.set_ai_recommendation_cache(text, text, uuid[]) is
  'Stores a validated visible recommendation ordering with an enforced six-hour lifetime.';
