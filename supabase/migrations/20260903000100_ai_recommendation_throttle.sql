-- Enforce a database-backed model-call ceiling even when behavior or candidate
-- changes invalidate an exact cache entry. The atomic claim also coalesces
-- concurrent refreshes from the same member and surface.

create table public.ai_recommendation_throttle (
  user_id uuid not null references public.profiles(id) on delete cascade,
  surface text not null check (surface in ('event', 'forum_post')),
  next_allowed_at timestamptz not null,
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (user_id, surface)
);

alter table public.ai_recommendation_throttle enable row level security;
revoke all on public.ai_recommendation_throttle
  from public, anon, authenticated;

create function public.claim_ai_recommendation_rerank(p_surface text)
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
    pg_catalog.now() + interval '30 minutes'
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

revoke all on function public.claim_ai_recommendation_rerank(text)
  from public, anon;
grant execute on function public.claim_ai_recommendation_rerank(text)
  to authenticated;

comment on table public.ai_recommendation_throttle is
  'Per-user model-call ceiling that coalesces concurrent recommendation refreshes.';
comment on function public.claim_ai_recommendation_rerank(text) is
  'Atomically permits at most one recommendation model attempt per member and surface every thirty minutes.';
