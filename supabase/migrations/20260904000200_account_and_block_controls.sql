-- Complete the existing safety and account-control foundations with fixed,
-- authenticated RPCs. Blocking releases active places between the two members;
-- unblocking never silently restores follows or RSVPs.

create function public.list_blocked_profiles()
returns table (
  id uuid,
  display_name text,
  username text,
  blocked_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  return query
  select p.id, p.display_name, p.username, b.created_at
  from public.blocks b
  join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc, p.id;
end;
$$;

create function public.set_profile_block(
  p_profile_id uuid,
  p_blocked boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  affected_event_id uuid;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_profile_id = current_user_id then
    raise exception using errcode = '22023', message = 'invalid_block_target';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_profile_id) then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'block:' || least(current_user_id::text, p_profile_id::text) || ':' ||
      greatest(current_user_id::text, p_profile_id::text),
      0
    )
  );

  if not p_blocked then
    delete from public.blocks b
    where b.blocker_id = current_user_id and b.blocked_id = p_profile_id;
    return false;
  end if;

  insert into public.blocks (blocker_id, blocked_id)
  values (current_user_id, p_profile_id)
  on conflict do nothing;

  delete from public.profile_follows f
  where (f.follower_id = current_user_id and f.followed_id = p_profile_id)
     or (f.follower_id = p_profile_id and f.followed_id = current_user_id);

  for affected_event_id in
    select e.id
    from public.events e
    join public.event_rsvps r on r.event_id = e.id
    where e.status = 'published'
      and e.start_at > pg_catalog.now()
      and r.status in ('joined', 'tentative', 'waitlisted')
      and (
        (e.organizer_id = current_user_id and r.user_id = p_profile_id)
        or (e.organizer_id = p_profile_id and r.user_id = current_user_id)
      )
    order by e.id
  loop
    update public.event_rsvps r set status = 'cancelled', reconfirmed_at = null
    where r.event_id = affected_event_id
      and r.user_id in (current_user_id, p_profile_id)
      and r.status in ('joined', 'tentative', 'waitlisted');
    perform public._promote_event_waitlist(affected_event_id);
  end loop;

  delete from public.member_notifications n
  using public.events e
  where n.user_id = current_user_id
    and n.event_id = e.id
    and e.organizer_id = p_profile_id;

  return true;
end;
$$;

create function public.delete_own_account(p_confirmation text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  avatar_key text;
  post_keys text[];
  result jsonb;
begin
  if current_user_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_confirmation is distinct from 'DELETE' then
    raise exception using errcode = '22023', message = 'account_deletion_confirmation';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delete-account:' || current_user_id::text, 0)
  );
  select p.avatar_image_key into avatar_key
  from public.profiles p
  where p.id = current_user_id
  for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;

  select coalesce(
    pg_catalog.array_agg(p.image_key order by p.id)
      filter (where p.image_key is not null),
    array[]::text[]
  ) into post_keys
  from public.forum_posts p
  where p.author_id = current_user_id;

  result := pg_catalog.jsonb_build_object(
    'avatar_image_key', avatar_key,
    'forum_image_keys', post_keys
  );

  -- Hosted events must be removed first because the organizer foreign key is
  -- deliberately restrictive. Event-owned rows then disappear by cascade.
  delete from public.events e where e.organizer_id = current_user_id;
  delete from auth.users u where u.id = current_user_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'profile_not_found';
  end if;
  return result;
end;
$$;

revoke all on function public.list_blocked_profiles() from public, anon;
revoke all on function public.set_profile_block(uuid, boolean) from public, anon;
revoke all on function public.delete_own_account(text) from public, anon;

grant execute on function public.list_blocked_profiles() to authenticated;
grant execute on function public.set_profile_block(uuid, boolean) to authenticated;
grant execute on function public.delete_own_account(text) to authenticated;

comment on function public.set_profile_block(uuid, boolean) is
  'Blocks or unblocks one member, removing mutual follows and active shared RSVPs when blocking.';
comment on function public.delete_own_account(text) is
  'Permanently deletes the authenticated account and returns validated private-media keys for edge cleanup.';
