-- Location-aware assistant with private per-user history.
-- The GiST event index from the initial migration serves ST_DWithin/KNN queries;
-- this migration adds a generated tsvector and GIN index for text filtering.

alter table public.profiles
  add column assistant_enabled boolean not null default true;

alter table public.events
  add column search_document tsvector generated always as (
    setweight(to_tsvector('english'::regconfig, coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english'::regconfig, coalesce(category, '')), 'A') ||
    setweight(to_tsvector('english'::regconfig, coalesce(venue_name, '')), 'B') ||
    setweight(to_tsvector('english'::regconfig, coalesce(description, '')), 'C') ||
    setweight(to_tsvector('english'::regconfig, coalesce(address, '')), 'D')
  ) stored;

create index events_search_document_gin
  on public.events using gin (search_document);

create table public.assistant_messages (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) between 1 and 4000),
  reply_to_id bigint references public.assistant_messages(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint assistant_message_shape check (
    (role = 'user' and reply_to_id is null)
    or (role = 'assistant' and reply_to_id is not null)
  )
);

create index assistant_messages_history_idx
  on public.assistant_messages (user_id, created_at desc, id desc);
create unique index assistant_messages_one_reply_idx
  on public.assistant_messages (reply_to_id)
  where reply_to_id is not null;

alter table public.assistant_messages enable row level security;
revoke all on public.assistant_messages from public, anon, authenticated;
revoke all on sequence public.assistant_messages_id_seq
  from public, anon, authenticated;

create or replace function public.search_nearby_events(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision default 10,
  p_query text default null,
  p_limit integer default 8
)
returns table (
  id uuid,
  title text,
  description text,
  category text,
  venue_name text,
  address text,
  start_at timestamptz,
  end_at timestamptz,
  distance_meters double precision
)
language sql
stable
security definer
set search_path = ''
as $$
  with input as (
    select
      extensions.st_setsrid(
        extensions.st_makepoint(p_longitude, p_latitude),
        4326
      )::extensions.geography as origin,
      case
        when nullif(btrim(left(coalesce(p_query, ''), 120)), '') is null
          then null::tsquery
        else websearch_to_tsquery(
          'english'::regconfig,
          btrim(left(p_query, 120))
        )
      end as query
  )
  select
    e.id,
    e.title,
    left(e.description, 320),
    e.category,
    e.venue_name,
    e.address,
    e.start_at,
    e.end_at,
    extensions.st_distance(e.location, input.origin)
  from public.events e
  cross join input
  where auth.uid() is not null
    and p_latitude between -90 and 90
    and p_longitude between -180 and 180
    and e.status = 'published'
    and e.visibility = 'public'
    and e.start_at > now()
    and extensions.st_dwithin(
      e.location,
      input.origin,
      least(greatest(p_radius_km, 1), 100) * 1000
    )
    and (input.query is null or e.search_document @@ input.query)
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
        or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
    )
  order by
    case
      when input.query is null then 0
      else ts_rank_cd(e.search_document, input.query)
    end desc,
    e.location operator(extensions.<->) input.origin,
    e.start_at
  limit least(greatest(p_limit, 1), 10);
$$;

create or replace function public.list_assistant_messages(p_limit integer default 40)
returns table (
  id bigint,
  role text,
  content text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select recent.id, recent.role, recent.content, recent.created_at
  from (
    select m.id, m.role, m.content, m.created_at
    from public.assistant_messages m
    where auth.uid() is not null
      and m.user_id = auth.uid()
    order by m.created_at desc, m.id desc
    limit least(greatest(p_limit, 1), 60)
  ) recent
  order by recent.created_at, recent.id;
$$;

create or replace function public.begin_assistant_turn(p_message text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  message_id bigint;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(btrim(p_message)) not between 1 and 600 then
    raise exception using errcode = '22023', message = 'assistant_validation';
  end if;
  if not coalesce(
    (select p.assistant_enabled from public.profiles p where p.id = current_user_id),
    false
  ) then
    raise exception using errcode = '42501', message = 'assistant_disabled';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('assistant:' || current_user_id::text, 0)
  );
  if (
    select count(*)
    from public.assistant_messages m
    where m.user_id = current_user_id
      and m.role = 'user'
      and m.created_at > now() - interval '1 minute'
  ) >= 8 then
    raise exception using errcode = 'P0001', message = 'assistant_rate_limited';
  end if;

  insert into public.assistant_messages (user_id, role, content)
  values (current_user_id, 'user', btrim(p_message))
  returning id into message_id;

  delete from public.assistant_messages m
  where m.user_id = current_user_id
    and m.id in (
      select old.id
      from public.assistant_messages old
      where old.user_id = current_user_id
      order by old.created_at desc, old.id desc
      offset 200
    );

  return message_id;
end;
$$;

create or replace function public.finish_assistant_turn(
  p_user_message_id bigint,
  p_message text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  message_id bigint;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if char_length(btrim(p_message)) not between 1 and 4000 then
    raise exception using errcode = '22023', message = 'assistant_validation';
  end if;
  if not exists (
    select 1
    from public.assistant_messages m
    where m.id = p_user_message_id
      and m.user_id = current_user_id
      and m.role = 'user'
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  insert into public.assistant_messages (user_id, role, content, reply_to_id)
  values (current_user_id, 'assistant', btrim(p_message), p_user_message_id)
  returning id into message_id;
  return message_id;
end;
$$;

create or replace function public.discard_assistant_turn(p_user_message_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.assistant_messages m
  where auth.uid() is not null
    and m.id = p_user_message_id
    and m.user_id = auth.uid()
    and m.role = 'user';
$$;

create or replace function public.clear_assistant_history()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.assistant_messages m
  where auth.uid() is not null
    and m.user_id = auth.uid();
$$;

revoke all on function public.search_nearby_events(
  double precision, double precision, double precision, text, integer
) from public, anon;
revoke all on function public.list_assistant_messages(integer) from public, anon;
revoke all on function public.begin_assistant_turn(text) from public, anon;
revoke all on function public.finish_assistant_turn(bigint, text) from public, anon;
revoke all on function public.discard_assistant_turn(bigint) from public, anon;
revoke all on function public.clear_assistant_history() from public, anon;

grant execute on function public.search_nearby_events(
  double precision, double precision, double precision, text, integer
) to authenticated;
grant execute on function public.list_assistant_messages(integer) to authenticated;
grant execute on function public.begin_assistant_turn(text) to authenticated;
grant execute on function public.finish_assistant_turn(bigint, text) to authenticated;
grant execute on function public.discard_assistant_turn(bigint) to authenticated;
grant execute on function public.clear_assistant_history() to authenticated;

comment on column public.events.search_document is
  'Weighted full-text document used with the GIN index for assistant event search.';
comment on table public.assistant_messages is
  'Private assistant history. Direct table access is denied; authenticated RPCs scope every operation to auth.uid().';
