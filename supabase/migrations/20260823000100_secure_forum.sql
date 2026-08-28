-- Authenticated, moderated forum for the Gather2Gether mobile app.
-- All client access goes through fixed-search-path SECURITY DEFINER functions.
-- Tables have RLS enabled and no direct client grants.

create table public.forum_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (
    category in (
      'General',
      'Looking for group',
      'Local tips',
      'Event ideas',
      'Safety'
    )
  ),
  title text not null check (char_length(title) between 5 and 120),
  body text not null check (char_length(body) between 10 and 4000),
  status text not null default 'active' check (
    status in ('active', 'locked', 'hidden')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now()
);

create table public.forum_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.forum_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1200),
  status text not null default 'active' check (
    status in ('active', 'hidden')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.forum_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid references public.forum_posts(id) on delete cascade,
  comment_id uuid references public.forum_comments(id) on delete cascade,
  reason text not null check (
    reason in (
      'spam',
      'harassment',
      'unsafe_behaviour',
      'personal_information',
      'inappropriate_content',
      'other'
    )
  ),
  status text not null default 'open' check (
    status in ('open', 'reviewing', 'resolved', 'dismissed')
  ),
  created_at timestamptz not null default now(),
  constraint forum_report_has_one_target check (
    (post_id is null) <> (comment_id is null)
  )
);

create index forum_posts_activity_idx
  on public.forum_posts (last_activity_at desc)
  where status in ('active', 'locked');
create index forum_posts_author_rate_idx
  on public.forum_posts (author_id, created_at desc);
create index forum_comments_post_idx
  on public.forum_comments (post_id, created_at)
  where status = 'active';
create index forum_comments_author_rate_idx
  on public.forum_comments (author_id, created_at desc);
create index forum_reports_status_idx
  on public.forum_reports (status, created_at);
create unique index forum_reports_one_per_post_idx
  on public.forum_reports (reporter_id, post_id)
  where post_id is not null;
create unique index forum_reports_one_per_comment_idx
  on public.forum_reports (reporter_id, comment_id)
  where comment_id is not null;

create trigger forum_posts_set_updated_at
before update on public.forum_posts
for each row execute function public.set_updated_at();

create trigger forum_comments_set_updated_at
before update on public.forum_comments
for each row execute function public.set_updated_at();

alter table public.forum_posts enable row level security;
alter table public.forum_comments enable row level security;
alter table public.forum_reports enable row level security;

revoke all on public.forum_posts from public, anon, authenticated;
revoke all on public.forum_comments from public, anon, authenticated;
revoke all on public.forum_reports from public, anon, authenticated;

create or replace function public.create_forum_post(
  p_title text,
  p_body text,
  p_category text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  new_post_id uuid;
  recent_posts integer;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('forum-post:' || current_user_id::text, 0)
  );

  select pg_catalog.count(*) into recent_posts
  from public.forum_posts p
  where p.author_id = current_user_id
    and p.created_at > pg_catalog.now() - interval '10 minutes';

  if recent_posts >= 3 then
    raise exception using errcode = 'P0001', message = 'forum_rate_limited';
  end if;

  if pg_catalog.char_length(pg_catalog.btrim(p_title)) not between 5 and 120
    or pg_catalog.char_length(pg_catalog.btrim(p_body)) not between 10 and 4000
    or p_category not in (
      'General',
      'Looking for group',
      'Local tips',
      'Event ideas',
      'Safety'
    ) then
    raise exception using errcode = '22023', message = 'forum_validation';
  end if;

  insert into public.forum_posts (author_id, title, body, category)
  values (
    current_user_id,
    pg_catalog.btrim(p_title),
    pg_catalog.btrim(p_body),
    p_category
  )
  returning id into new_post_id;

  return new_post_id;
end;
$$;

create or replace function public.list_forum_posts(
  p_limit integer default 30,
  p_before timestamptz default null
)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  category text,
  title text,
  body text,
  status text,
  created_at timestamptz,
  last_activity_at timestamptz,
  comment_count bigint,
  viewer_is_author boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.author_id,
    profile.display_name,
    p.category,
    p.title,
    p.body,
    p.status,
    p.created_at,
    p.last_activity_at,
    (
      select pg_catalog.count(*)
      from public.forum_comments c
      where c.post_id = p.id
        and c.status = 'active'
        and not exists (
          select 1
          from public.blocks cb
          where (cb.blocker_id = auth.uid() and cb.blocked_id = c.author_id)
            or (cb.blocker_id = c.author_id and cb.blocked_id = auth.uid())
        )
    ),
    p.author_id = auth.uid()
  from public.forum_posts p
  join public.profiles profile on profile.id = p.author_id
  where auth.uid() is not null
    and p.status in ('active', 'locked')
    and (p_before is null or p.last_activity_at < p_before)
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.author_id)
        or (b.blocker_id = p.author_id and b.blocked_id = auth.uid())
    )
  order by p.last_activity_at desc, p.id
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.get_forum_post(p_post_id uuid)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  category text,
  title text,
  body text,
  status text,
  created_at timestamptz,
  last_activity_at timestamptz,
  comment_count bigint,
  viewer_is_author boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.author_id,
    profile.display_name,
    p.category,
    p.title,
    p.body,
    p.status,
    p.created_at,
    p.last_activity_at,
    (
      select pg_catalog.count(*)
      from public.forum_comments c
      where c.post_id = p.id
        and c.status = 'active'
        and not exists (
          select 1
          from public.blocks cb
          where (cb.blocker_id = auth.uid() and cb.blocked_id = c.author_id)
            or (cb.blocker_id = c.author_id and cb.blocked_id = auth.uid())
        )
    ),
    p.author_id = auth.uid()
  from public.forum_posts p
  join public.profiles profile on profile.id = p.author_id
  where auth.uid() is not null
    and p.id = p_post_id
    and p.status in ('active', 'locked')
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = p.author_id)
        or (b.blocker_id = p.author_id and b.blocked_id = auth.uid())
    );
$$;

create or replace function public.get_forum_comments(
  p_post_id uuid,
  p_limit integer default 100
)
returns table (
  id uuid,
  post_id uuid,
  author_id uuid,
  author_name text,
  body text,
  created_at timestamptz,
  viewer_is_author boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    c.id,
    c.post_id,
    c.author_id,
    profile.display_name,
    c.body,
    c.created_at,
    c.author_id = auth.uid()
  from public.forum_comments c
  join public.forum_posts p on p.id = c.post_id
  join public.profiles profile on profile.id = c.author_id
  where auth.uid() is not null
    and c.post_id = p_post_id
    and c.status = 'active'
    and p.status in ('active', 'locked')
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id in (p.author_id, c.author_id))
        or (b.blocked_id = auth.uid() and b.blocker_id in (p.author_id, c.author_id))
    )
  order by c.created_at, c.id
  limit least(greatest(p_limit, 1), 200);
$$;

create or replace function public.create_forum_comment(
  p_post_id uuid,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  post_author_id uuid;
  post_status text;
  new_comment_id uuid;
  recent_comments integer;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('forum-comment:' || current_user_id::text, 0)
  );

  if pg_catalog.char_length(pg_catalog.btrim(p_body)) not between 1 and 1200 then
    raise exception using errcode = '22023', message = 'forum_validation';
  end if;

  select p.author_id, p.status into post_author_id, post_status
  from public.forum_posts p
  where p.id = p_post_id
  for update;

  if not found or post_status not in ('active', 'locked') then
    raise exception using errcode = 'P0001', message = 'forum_post_unavailable';
  end if;
  if post_status = 'locked' then
    raise exception using errcode = 'P0001', message = 'forum_post_locked';
  end if;
  if exists (
    select 1
    from public.blocks b
    where (b.blocker_id = current_user_id and b.blocked_id = post_author_id)
      or (b.blocker_id = post_author_id and b.blocked_id = current_user_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  select pg_catalog.count(*) into recent_comments
  from public.forum_comments c
  where c.author_id = current_user_id
    and c.created_at > pg_catalog.now() - interval '10 minutes';

  if recent_comments >= 15 then
    raise exception using errcode = 'P0001', message = 'forum_rate_limited';
  end if;

  insert into public.forum_comments (post_id, author_id, body)
  values (p_post_id, current_user_id, pg_catalog.btrim(p_body))
  returning id into new_comment_id;

  update public.forum_posts
  set last_activity_at = pg_catalog.now()
  where id = p_post_id;

  return new_comment_id;
end;
$$;

create or replace function public.report_forum_post(
  p_post_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  content_author_id uuid;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_reason not in (
    'spam',
    'harassment',
    'unsafe_behaviour',
    'personal_information',
    'inappropriate_content',
    'other'
  ) then
    raise exception using errcode = '22023', message = 'invalid_report_reason';
  end if;

  select p.author_id into content_author_id
  from public.forum_posts p
  where p.id = p_post_id and p.status in ('active', 'locked');

  if not found then
    raise exception using errcode = 'P0001', message = 'forum_post_unavailable';
  end if;
  if content_author_id = current_user_id then
    raise exception using errcode = '22023', message = 'cannot_report_own_content';
  end if;

  insert into public.forum_reports (reporter_id, post_id, reason)
  values (current_user_id, p_post_id, p_reason)
  on conflict (reporter_id, post_id) where post_id is not null do nothing;
end;
$$;

create or replace function public.report_forum_comment(
  p_comment_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  content_author_id uuid;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_reason not in (
    'spam',
    'harassment',
    'unsafe_behaviour',
    'personal_information',
    'inappropriate_content',
    'other'
  ) then
    raise exception using errcode = '22023', message = 'invalid_report_reason';
  end if;

  select c.author_id into content_author_id
  from public.forum_comments c
  join public.forum_posts p on p.id = c.post_id
  where c.id = p_comment_id
    and c.status = 'active'
    and p.status in ('active', 'locked');

  if not found then
    raise exception using errcode = 'P0001', message = 'forum_comment_unavailable';
  end if;
  if content_author_id = current_user_id then
    raise exception using errcode = '22023', message = 'cannot_report_own_content';
  end if;

  insert into public.forum_reports (reporter_id, comment_id, reason)
  values (current_user_id, p_comment_id, p_reason)
  on conflict (reporter_id, comment_id) where comment_id is not null do nothing;
end;
$$;

revoke all on function public.create_forum_post(text, text, text)
  from public, anon;
revoke all on function public.list_forum_posts(integer, timestamptz)
  from public, anon;
revoke all on function public.get_forum_post(uuid)
  from public, anon;
revoke all on function public.get_forum_comments(uuid, integer)
  from public, anon;
revoke all on function public.create_forum_comment(uuid, text)
  from public, anon;
revoke all on function public.report_forum_post(uuid, text)
  from public, anon;
revoke all on function public.report_forum_comment(uuid, text)
  from public, anon;

grant execute on function public.create_forum_post(text, text, text)
  to authenticated;
grant execute on function public.list_forum_posts(integer, timestamptz)
  to authenticated;
grant execute on function public.get_forum_post(uuid)
  to authenticated;
grant execute on function public.get_forum_comments(uuid, integer)
  to authenticated;
grant execute on function public.create_forum_comment(uuid, text)
  to authenticated;
grant execute on function public.report_forum_post(uuid, text)
  to authenticated;
grant execute on function public.report_forum_comment(uuid, text)
  to authenticated;

comment on table public.forum_posts is
  'Authenticated forum posts. Direct client access is denied; use secured RPCs.';
comment on table public.forum_comments is
  'Authenticated forum comments with database-enforced length and rate limits.';
comment on table public.forum_reports is
  'Private moderation queue. Reporters cannot read or modify queue records.';
