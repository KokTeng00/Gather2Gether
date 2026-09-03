-- Privacy-conscious, low-cost personalization for events and community posts.
-- Signals are aggregated per user/content/action and views are de-duplicated,
-- avoiding an unbounded impression log while retaining useful recent intent.

create table public.recommendation_signals (
  user_id uuid not null references public.profiles(id) on delete cascade,
  content_kind text not null check (content_kind in ('event', 'forum_post')),
  content_id uuid not null,
  signal_type text not null,
  occurrence_count integer not null default 1 check (
    occurrence_count between 1 and 1000
  ),
  first_occurred_at timestamptz not null default pg_catalog.now(),
  last_occurred_at timestamptz not null default pg_catalog.now(),
  primary key (user_id, content_kind, content_id, signal_type),
  constraint recommendation_signal_type_matches_content check (
    (content_kind = 'event' and signal_type in ('view', 'tentative', 'joined'))
    or
    (content_kind = 'forum_post' and signal_type in ('view', 'like', 'comment'))
  )
);

create index recommendation_signals_recent_user_idx
  on public.recommendation_signals (
    user_id,
    content_kind,
    last_occurred_at desc
  );
create index recommendation_signals_content_idx
  on public.recommendation_signals (content_kind, content_id, signal_type);

create table public.forum_post_likes (
  post_id uuid not null references public.forum_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default pg_catalog.now(),
  primary key (post_id, user_id)
);

create index forum_post_likes_user_idx
  on public.forum_post_likes (user_id, created_at desc);

alter table public.recommendation_signals enable row level security;
alter table public.forum_post_likes enable row level security;

revoke all on public.recommendation_signals from public, anon, authenticated;
revoke all on public.forum_post_likes from public, anon, authenticated;

create function public._upsert_recommendation_signal(
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

create function public.record_recommendation_view(
  p_content_kind text,
  p_content_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  content_is_visible boolean := false;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_content_kind = 'event' then
    select true into content_is_visible
    from public.events e
    where e.id = p_content_id
      and e.status = 'published'
      and e.visibility = 'public'
      and not exists (
        select 1
        from public.blocks b
        where (b.blocker_id = current_user_id and b.blocked_id = e.organizer_id)
          or (b.blocker_id = e.organizer_id and b.blocked_id = current_user_id)
      );
  elsif p_content_kind = 'forum_post' then
    select true into content_is_visible
    from public.forum_posts p
    where p.id = p_content_id
      and p.status in ('active', 'locked')
      and not exists (
        select 1
        from public.blocks b
        where (b.blocker_id = current_user_id and b.blocked_id = p.author_id)
          or (b.blocker_id = p.author_id and b.blocked_id = current_user_id)
      );
  else
    raise exception using errcode = '22023', message = 'invalid_content_kind';
  end if;

  if not content_is_visible then
    return false;
  end if;

  perform public._upsert_recommendation_signal(
    current_user_id,
    p_content_kind,
    p_content_id,
    'view',
    1,
    interval '6 hours'
  );
  return true;
end;
$$;

create function public.set_forum_post_like(
  p_post_id uuid,
  p_liked boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  post_author_id uuid;
  post_status text;
  changed boolean := false;
  total_likes bigint;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_liked is null then
    raise exception using errcode = '22023', message = 'forum_validation';
  end if;

  select p.author_id, p.status into post_author_id, post_status
  from public.forum_posts p
  where p.id = p_post_id;

  if not found or post_status not in ('active', 'locked') then
    raise exception using errcode = 'P0001', message = 'forum_post_unavailable';
  end if;
  if exists (
    select 1
    from public.blocks b
    where (b.blocker_id = current_user_id and b.blocked_id = post_author_id)
      or (b.blocker_id = post_author_id and b.blocked_id = current_user_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  if p_liked then
    insert into public.forum_post_likes (post_id, user_id)
    values (p_post_id, current_user_id)
    on conflict (post_id, user_id) do nothing;
    changed := found;
    if changed then
      perform public._upsert_recommendation_signal(
        current_user_id,
        'forum_post',
        p_post_id,
        'like'
      );
    end if;
  else
    delete from public.forum_post_likes
    where post_id = p_post_id and user_id = current_user_id;
    changed := found;
    delete from public.recommendation_signals
    where user_id = current_user_id
      and content_kind = 'forum_post'
      and content_id = p_post_id
      and signal_type = 'like';
  end if;

  select pg_catalog.count(*) into total_likes
  from public.forum_post_likes l
  where l.post_id = p_post_id;

  return pg_catalog.jsonb_build_object(
    'liked', p_liked,
    'like_count', total_likes,
    'changed', changed
  );
end;
$$;

create function public.get_forum_post_like_state(p_post_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'liked', exists (
      select 1
      from public.forum_post_likes l
      where l.post_id = p_post_id and l.user_id = auth.uid()
    ),
    'like_count', (
      select pg_catalog.count(*)
      from public.forum_post_likes l
      where l.post_id = p_post_id
    )
  )
  from public.forum_posts p
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

create function public._event_rsvp_recommendation_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'joined' then
    delete from public.recommendation_signals
    where user_id = new.user_id
      and content_kind = 'event'
      and content_id = new.event_id
      and signal_type = 'tentative';
    perform public._upsert_recommendation_signal(
      new.user_id, 'event', new.event_id, 'joined'
    );
  elsif new.status = 'tentative' then
    delete from public.recommendation_signals
    where user_id = new.user_id
      and content_kind = 'event'
      and content_id = new.event_id
      and signal_type = 'joined';
    perform public._upsert_recommendation_signal(
      new.user_id, 'event', new.event_id, 'tentative'
    );
  else
    delete from public.recommendation_signals
    where user_id = new.user_id
      and content_kind = 'event'
      and content_id = new.event_id
      and signal_type in ('joined', 'tentative');
  end if;
  return new;
end;
$$;

create trigger event_rsvps_insert_recommendation_signal
after insert on public.event_rsvps
for each row
execute function public._event_rsvp_recommendation_signal();

create trigger event_rsvps_update_recommendation_signal
after update of status on public.event_rsvps
for each row
when (old.status is distinct from new.status)
execute function public._event_rsvp_recommendation_signal();

create function public._forum_comment_recommendation_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public._upsert_recommendation_signal(
    new.author_id, 'forum_post', new.post_id, 'comment'
  );
  return new;
end;
$$;

create trigger forum_comments_record_recommendation_signal
after insert on public.forum_comments
for each row execute function public._forum_comment_recommendation_signal();

create function public._delete_event_recommendation_signals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.recommendation_signals
  where content_kind = 'event' and content_id = old.id;
  return old;
end;
$$;

create trigger events_delete_recommendation_signals
after delete on public.events
for each row execute function public._delete_event_recommendation_signals();

create function public._delete_forum_recommendation_signals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.recommendation_signals
  where content_kind = 'forum_post' and content_id = old.id;
  return old;
end;
$$;

create trigger forum_posts_delete_recommendation_signals
after delete on public.forum_posts
for each row execute function public._delete_forum_recommendation_signals();

-- Seed strong existing choices so current members are not treated as entirely
-- new after rollout. Views and likes begin accumulating after this migration.
insert into public.recommendation_signals (
  user_id,
  content_kind,
  content_id,
  signal_type,
  occurrence_count,
  first_occurred_at,
  last_occurred_at
)
select
  r.user_id,
  'event',
  r.event_id,
  r.status,
  1,
  r.created_at,
  r.updated_at
from public.event_rsvps r
join public.events e on e.id = r.event_id
where r.status in ('joined', 'tentative')
  and e.end_at > pg_catalog.now()
on conflict do nothing;

insert into public.recommendation_signals (
  user_id,
  content_kind,
  content_id,
  signal_type,
  occurrence_count,
  first_occurred_at,
  last_occurred_at
)
select
  c.author_id,
  'forum_post',
  c.post_id,
  'comment',
  least(pg_catalog.count(*)::integer, 1000),
  min(c.created_at),
  max(c.created_at)
from public.forum_comments c
join public.forum_posts p on p.id = c.post_id
where c.status = 'active'
  and p.status in ('active', 'locked')
  and c.created_at > pg_catalog.now() - interval '90 days'
group by c.author_id, c.post_id
on conflict do nothing;

create function public.recommend_personalized_events(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision default 10
)
returns table (
  id uuid,
  organizer_id uuid,
  organizer_name text,
  title text,
  description text,
  category text,
  venue_name text,
  address text,
  latitude double precision,
  longitude double precision,
  start_at timestamptz,
  end_at timestamptz,
  max_participants integer,
  joined_count bigint,
  tentative_count bigint,
  distance_meters double precision,
  user_rsvp_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  with input as materialized (
    select extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude),
      4326
    )::extensions.geography as origin
  ),
  weighted_signals as materialized (
    select
      s.content_id,
      (
        case s.signal_type
          when 'joined' then 8.0
          when 'tentative' then 4.0
          else 1.0
        end
        * least(s.occurrence_count, case when s.signal_type = 'view' then 3 else 1 end)
        * pg_catalog.exp(
          -extract(epoch from (pg_catalog.now() - s.last_occurred_at))
            / 2592000.0
        )
      ) as weight
    from public.recommendation_signals s
    where s.user_id = auth.uid()
      and s.content_kind = 'event'
      and s.last_occurred_at > pg_catalog.now() - interval '90 days'
  ),
  category_preferences as materialized (
    select e.category, sum(s.weight) as affinity
    from weighted_signals s
    join public.events e on e.id = s.content_id
    group by e.category
  ),
  organizer_preferences as materialized (
    select e.organizer_id, sum(s.weight) as affinity
    from weighted_signals s
    join public.events e on e.id = s.content_id
    group by e.organizer_id
  ),
  candidates as materialized (
    select
      e.id,
      e.organizer_id,
      profile.display_name as organizer_name,
      e.title,
      e.description,
      e.category,
      e.venue_name,
      e.address,
      extensions.st_y(e.location::extensions.geometry) as latitude,
      extensions.st_x(e.location::extensions.geometry) as longitude,
      e.start_at,
      e.end_at,
      e.max_participants,
      (
        select pg_catalog.count(*)
        from public.event_rsvps r
        where r.event_id = e.id and r.status = 'joined'
      ) as joined_count,
      (
        select pg_catalog.count(*)
        from public.event_rsvps r
        where r.event_id = e.id and r.status = 'tentative'
      ) as tentative_count,
      extensions.st_distance(e.location, input.origin) as distance_meters,
      (
        select r.status
        from public.event_rsvps r
        where r.event_id = e.id and r.user_id = auth.uid()
      ) as user_rsvp_status
    from public.events e
    join public.profiles profile on profile.id = e.organizer_id
    cross join input
    where auth.uid() is not null
      and p_latitude between -90 and 90
      and p_longitude between -180 and 180
      and e.status = 'published'
      and e.visibility = 'public'
      and e.start_at > pg_catalog.now()
      and extensions.st_dwithin(
        e.location,
        input.origin,
        least(greatest(p_radius_km, 1), 100) * 1000
      )
      and not exists (
        select 1
        from public.blocks b
        where (b.blocker_id = auth.uid() and b.blocked_id = e.organizer_id)
          or (b.blocker_id = e.organizer_id and b.blocked_id = auth.uid())
      )
    order by e.location operator(extensions.<->) input.origin, e.start_at
    limit 500
  )
  select
    c.id,
    c.organizer_id,
    c.organizer_name,
    c.title,
    c.description,
    c.category,
    c.venue_name,
    c.address,
    c.latitude,
    c.longitude,
    c.start_at,
    c.end_at,
    c.max_participants,
    c.joined_count,
    c.tentative_count,
    c.distance_meters,
    c.user_rsvp_status
  from candidates c
  left join category_preferences category on category.category = c.category
  left join organizer_preferences organizer on organizer.organizer_id = c.organizer_id
  order by
    coalesce(category.affinity, 0.0) * 2.5
      + coalesce(organizer.affinity, 0.0) * 0.6
      + pg_catalog.ln(1.0 + c.joined_count::double precision) * 0.4
      + 1.0 / (1.0 + c.distance_meters / 10000.0)
      + 1.0 / (
        1.0 + greatest(
          extract(epoch from (c.start_at - pg_catalog.now())) / 1209600.0,
          0.0
        )
      )
      - case c.user_rsvp_status
          when 'joined' then 8.0
          when 'tentative' then 3.0
          else 0.0
        end desc,
    c.distance_meters,
    c.start_at,
    c.id
  limit 100;
$$;

create function public.recommend_personalized_forum_posts(
  p_limit integer default 30,
  p_before timestamptz default null
)
returns table (
  id uuid,
  author_id uuid,
  author_name text,
  author_username text,
  category text,
  title text,
  body text,
  status text,
  created_at timestamptz,
  last_activity_at timestamptz,
  comment_count bigint,
  viewer_is_author boolean,
  has_image boolean,
  place_name text,
  place_address text
)
language sql
stable
security definer
set search_path = ''
as $$
  with weighted_signals as materialized (
    select
      s.content_id,
      (
        case s.signal_type
          when 'comment' then 7.0
          when 'like' then 4.0
          else 1.0
        end
        * least(
          s.occurrence_count,
          case
            when s.signal_type = 'view' then 3
            when s.signal_type = 'comment' then 5
            else 1
          end
        )
        * pg_catalog.exp(
          -extract(epoch from (pg_catalog.now() - s.last_occurred_at))
            / 2592000.0
        )
      ) as weight
    from public.recommendation_signals s
    where s.user_id = auth.uid()
      and s.content_kind = 'forum_post'
      and s.last_occurred_at > pg_catalog.now() - interval '90 days'
  ),
  category_preferences as materialized (
    select p.category, sum(s.weight) as affinity
    from weighted_signals s
    join public.forum_posts p on p.id = s.content_id
    group by p.category
  ),
  author_preferences as materialized (
    select p.author_id, sum(s.weight) as affinity
    from weighted_signals s
    join public.forum_posts p on p.id = s.content_id
    group by p.author_id
  ),
  candidates as materialized (
    select
      p.id,
      p.author_id,
      profile.display_name as author_name,
      profile.username as author_username,
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
              or (cb.blocked_id = auth.uid() and cb.blocker_id = c.author_id)
          )
      ) as comment_count,
      (
        select pg_catalog.count(*)
        from public.forum_post_likes l
        where l.post_id = p.id
      ) as like_count,
      p.author_id = auth.uid() as viewer_is_author,
      p.image_key is not null as has_image,
      p.place_name,
      p.place_address
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
    limit 500
  )
  select
    c.id,
    c.author_id,
    c.author_name,
    c.author_username,
    c.category,
    c.title,
    c.body,
    c.status,
    c.created_at,
    c.last_activity_at,
    c.comment_count,
    c.viewer_is_author,
    c.has_image,
    c.place_name,
    c.place_address
  from candidates c
  left join category_preferences category on category.category = c.category
  left join author_preferences author on author.author_id = c.author_id
  order by
    coalesce(category.affinity, 0.0) * 2.0
      + coalesce(author.affinity, 0.0) * 0.5
      + pg_catalog.ln(1.0 + c.like_count::double precision) * 0.8
      + pg_catalog.ln(1.0 + c.comment_count::double precision) * 0.45
      + 1.0 / (
        1.0 + greatest(
          extract(epoch from (pg_catalog.now() - c.last_activity_at))
            / 1209600.0,
          0.0
        )
      )
      - case when c.viewer_is_author then 1.5 else 0.0 end desc,
    c.last_activity_at desc,
    c.id
  limit least(greatest(p_limit, 1), 50);
$$;

revoke all on function public.record_recommendation_view(text, uuid)
  from public, anon;
revoke all on function public.set_forum_post_like(uuid, boolean)
  from public, anon;
revoke all on function public.get_forum_post_like_state(uuid)
  from public, anon;
revoke all on function public.recommend_personalized_events(
  double precision, double precision, double precision
) from public, anon;
revoke all on function public.recommend_personalized_forum_posts(
  integer, timestamptz
) from public, anon;

grant execute on function public.record_recommendation_view(text, uuid)
  to authenticated;
grant execute on function public.set_forum_post_like(uuid, boolean)
  to authenticated;
grant execute on function public.get_forum_post_like_state(uuid)
  to authenticated;
grant execute on function public.recommend_personalized_events(
  double precision, double precision, double precision
) to authenticated;
grant execute on function public.recommend_personalized_forum_posts(
  integer, timestamptz
) to authenticated;

comment on table public.recommendation_signals is
  'Aggregated first-party engagement signals used for private, time-decayed recommendations.';
comment on function public.recommend_personalized_events(
  double precision, double precision, double precision
) is 'Ranks a bounded nearby-event candidate set using recent private engagement, distance, time, and popularity.';
comment on function public.recommend_personalized_forum_posts(
  integer, timestamptz
) is 'Ranks a bounded recent discussion candidate set using recent private views, likes, comments, freshness, and popularity.';
