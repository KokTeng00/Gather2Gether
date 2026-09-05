-- Transactional regression checks: fixtures never become visible to app users.
begin;
do $$
declare
  owner_id uuid := gen_random_uuid();
  visitor_id uuid := gen_random_uuid();
  member_id uuid;
  alice_id uuid;
  ids uuid[] := '{}';
  first_page uuid[];
  second_page uuid[];
  last_id uuid;
  n integer;
begin
  insert into auth.users (id, raw_user_meta_data) values
    (owner_id, '{"display_name":"Connection test owner"}'),
    (visitor_id, '{"display_name":"Connection test visitor"}');
  for n in 1..34 loop
    member_id := gen_random_uuid();
    ids := array_append(ids, member_id);
    if n = 1 then alice_id := member_id; end if;
    insert into auth.users (id, raw_user_meta_data)
      values (member_id, jsonb_build_object('display_name', case when n = 1 then 'Connection Alice' else 'Connection Member ' || n end));
    update public.profiles set username = 'conn_' || replace(member_id::text, '-', '')::varchar(20) where id = member_id;
    insert into public.profile_follows (follower_id, followed_id, created_at)
      values (member_id, owner_id, '2026-09-05T14:00:00.123456Z');
    if n <= 2 then insert into public.profile_follows (follower_id, followed_id) values (owner_id, member_id); end if;
  end loop;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  select array_agg(id) into first_page from public.list_profile_connections(owner_id, 'followers');
  assert cardinality(first_page) = 31, 'bounded first page';
  last_id := first_page[30];
  select array_agg(id) into second_page from public.list_profile_connections(owner_id, 'followers', null, '2026-09-05T14:00:00.123456Z', last_id);
  assert cardinality(second_page) = 4, 'keyset page includes the lookahead member';
  assert not (first_page[1:30] && second_page), 'pages do not overlap with identical timestamps';
  select count(*) into n from public.list_profile_connections(owner_id, 'followers', 'ALICE');
  assert n = 1, 'case-insensitive display name search';
  select count(*) into n from public.list_profile_connections(owner_id, 'following', '@conn_' || left(replace(alice_id::text, '-', ''), 20));
  assert n = 1, 'username search accepts leading @';
  select count(*) into n from public.list_profile_connections(owner_id, 'followers', '%');
  assert n = 0, 'search wildcard is literal';
  perform set_config('request.jwt.claim.sub', visitor_id::text, true);
  select count(*) into n from public.list_profile_connections(owner_id, 'following');
  assert n = 2, 'visitors can browse';
  begin
    perform public.list_profile_connections(owner_id, 'followers', 'Alice');
    raise exception 'non-owner search was allowed';
  exception when insufficient_privilege then
    assert sqlerrm = 'connection_search_owner_only';
  end;
  begin
    perform public.list_profile_connections(owner_id, 'following', 'Alice');
    raise exception 'non-owner following search was allowed';
  exception when insufficient_privilege then
    assert sqlerrm = 'connection_search_owner_only';
  end;
  insert into public.blocks (blocker_id, blocked_id) values (visitor_id, alice_id);
  select count(*) into n from public.list_profile_connections(owner_id, 'following');
  assert n = 1, 'blocked members are omitted';
  insert into public.blocks (blocker_id, blocked_id) values (owner_id, visitor_id);
  begin
    perform public.list_profile_connections(owner_id, 'followers');
    raise exception 'blocked owner list was visible';
  exception when insufficient_privilege then
    assert sqlerrm = 'permission_denied';
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.list_profile_connections(owner_id, 'followers');
    raise exception 'anonymous list was visible';
  exception when insufficient_privilege then
    assert sqlerrm = 'authentication_required';
  end;
  assert not has_function_privilege('anon', 'public.list_profile_connections(uuid,text,text,timestamptz,uuid,integer)', 'EXECUTE');
  assert has_function_privilege('authenticated', 'public.list_profile_connections(uuid,text,text,timestamptz,uuid,integer)', 'EXECUTE');
  raise notice 'Connection list database checks passed';
end;
$$;
rollback;
