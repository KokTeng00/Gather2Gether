create table public.ai_tool_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  tool text not null check (tool in ('event_draft', 'translation', 'summary')),
  window_start timestamptz not null,
  usage_count integer not null default 1 check (usage_count between 1 and 100),
  primary key (user_id, tool, window_start)
);

create index ai_tool_usage_cleanup_idx
  on public.ai_tool_usage (window_start);

alter table public.ai_tool_usage enable row level security;
revoke all on table public.ai_tool_usage from anon, authenticated;

create function public.claim_ai_tool_use(p_tool text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  current_window timestamptz := date_trunc('hour', pg_catalog.now());
  tool_limit integer;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_tool not in ('event_draft', 'translation', 'summary') then
    raise exception using errcode = '22023', message = 'assistant_validation';
  end if;
  if not coalesce((
    select p.assistant_enabled from public.profiles p
    where p.id = current_user_id
  ), false) then
    raise exception using errcode = '42501', message = 'assistant_disabled';
  end if;

  tool_limit := case p_tool
    when 'translation' then 20
    else 10
  end;
  insert into public.ai_tool_usage (user_id, tool, window_start, usage_count)
  values (current_user_id, p_tool, current_window, 1)
  on conflict (user_id, tool, window_start) do update
    set usage_count = ai_tool_usage.usage_count + 1
    where ai_tool_usage.usage_count < tool_limit;
  return found;
end;
$$;

revoke all on function public.claim_ai_tool_use(text) from public, anon;
grant execute on function public.claim_ai_tool_use(text) to authenticated;

comment on table public.ai_tool_usage is
  'Short-lived per-member counters that bound optional generative AI helpers.';
comment on function public.claim_ai_tool_use is
  'Atomically claims one bounded AI helper request for the current hour.';
