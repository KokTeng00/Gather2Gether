-- Public follow lists respect blocks; only the list owner may search them.
create function public.list_profile_connections(
  p_profile_id uuid,
  p_kind text,
  p_query text default null,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 31
)
returns table (
  id uuid, display_name text, username text, has_avatar boolean,
  avatar_version timestamptz, followed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  viewer_id uuid := auth.uid();
  search_text text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_query, '')));
begin
  if viewer_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_profile_id is null or p_kind is null or p_kind not in ('followers', 'following')
     or p_limit is null or p_limit < 1 or p_limit > 31
     or pg_catalog.char_length(search_text) > 80
     or (p_before_created_at is null) <> (p_before_id is null) then
    raise exception using errcode = '22023', message = 'connection_list_validation';
  end if;
  if search_text <> '' and viewer_id <> p_profile_id then
    raise exception using errcode = '42501', message = 'connection_search_owner_only';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_profile_id) then
    raise exception using errcode = 'P0002', message = 'profile_not_found';
  end if;
  if exists (
    select 1 from public.blocks b
    where (b.blocker_id = viewer_id and b.blocked_id = p_profile_id)
       or (b.blocker_id = p_profile_id and b.blocked_id = viewer_id)
  ) then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  -- A leading @ is optional when searching usernames. Treat % and _ literally.
  search_text := pg_catalog.regexp_replace(search_text, '^@', '');
  return query
  with connections as (
    select f.follower_id as member_id, f.created_at
    from public.profile_follows f
    where p_kind = 'followers' and f.followed_id = p_profile_id
    union all
    select f.followed_id as member_id, f.created_at
    from public.profile_follows f
    where p_kind = 'following' and f.follower_id = p_profile_id
  )
  select p.id, p.display_name, p.username, p.avatar_image_key is not null,
         p.updated_at, c.created_at
  from connections c
  join public.profiles p on p.id = c.member_id
  where (p_before_created_at is null or (c.created_at, p.id) < (p_before_created_at, p_before_id))
    and (search_text = ''
         or pg_catalog.strpos(pg_catalog.lower(coalesce(p.username, '')), search_text) > 0
         or pg_catalog.strpos(pg_catalog.lower(p.display_name), search_text) > 0)
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = viewer_id and b.blocked_id = p.id)
         or (b.blocker_id = p.id and b.blocked_id = viewer_id)
    )
  order by c.created_at desc, p.id desc
  limit p_limit;
end;
$$;

revoke all on function public.list_profile_connections(uuid, text, text, timestamptz, uuid, integer) from public, anon;
grant execute on function public.list_profile_connections(uuid, text, text, timestamptz, uuid, integer) to authenticated;
