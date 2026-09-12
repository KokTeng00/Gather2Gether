-- Run against a disposable database after all migrations. Fixtures roll back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('92000000-0000-4000-8000-000000000001','audience-host@example.test','{"display_name":"Audience host"}'),
 ('92000000-0000-4000-8000-000000000002','audience-follower@example.test','{"display_name":"Follower"}'),
 ('92000000-0000-4000-8000-000000000003','audience-following@example.test','{"display_name":"Following"}'),
 ('92000000-0000-4000-8000-000000000004','audience-outsider@example.test','{"display_name":"Outsider"}');
update public.profiles set username=case id
 when '92000000-0000-4000-8000-000000000001' then 'audience_host'
 when '92000000-0000-4000-8000-000000000002' then 'audience_follower'
 when '92000000-0000-4000-8000-000000000003' then 'audience_following'
 else 'audience_outsider' end
 where id::text like '92000000%';
insert into public.profile_follows(follower_id,followed_id) values
 ('92000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000001'),
 ('92000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000003');
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select set_config('test.audience_input',jsonb_build_object(
 'p_title','Private riverside walk','p_description','Meet at the private gate.','p_category','Hiking',
 'p_venue_name','River park','p_address','Private gate, Mannheim',
 'p_latitude',49.48,'p_longitude',8.47,'p_start_at',now()+interval '7 days','p_end_at',now()+interval '7 days 2 hours',
 'p_max_participants',12,'p_beginner_friendly',true,'p_wheelchair_accessible',false,
 'p_event_setting','outdoor','p_event_language','English','p_age_guidance','all_ages','p_what_to_bring','Water',
 'p_status','published','p_visibility','public','p_repeat_interval','none','p_repeat_count',1)::text,true);
do $$
declare audience text; ids uuid[]; input jsonb := current_setting('test.audience_input')::jsonb;
begin
 foreach audience in array array['public','unlisted','followers','following','selected'] loop
  ids := public.save_event_plan(null,'this',input || jsonb_build_object('p_visibility',audience),
    case when audience='selected' then '{"audience_usernames":[" @Audience_Follower ","audience_following","@AUDIENCE_FOLLOWER"]}'::jsonb else '{}'::jsonb end);
  perform set_config('test.audience_' || audience,ids[1]::text,true);
 end loop;
 if jsonb_array_length(public.get_event_plan(current_setting('test.audience_selected')::uuid)->'audience_usernames')<>2 then
  raise exception 'Host audience was not normalized'; end if;
 -- Missing, unknown, own and malformed usernames must roll back the entire event.
 foreach audience in array array['[]','["missing_audience_user"]','["audience_host"]','[42]','null','["bad-name"]'] loop
  begin
   perform public.save_event_plan(null,'this',input || '{"p_visibility":"selected"}',jsonb_build_object('audience_usernames',audience::jsonb));
   raise exception 'Invalid audience accepted: %',audience;
  exception when sqlstate '22023' then
   if sqlerrm not in ('audience_validation','audience_not_found') then raise; end if;
  end;
 end loop;
 if (select count(*) from public.events where organizer_id=auth.uid())<>5 then raise exception 'Failed save left an event'; end if;
 ids:=public.save_event_plan(null,'this',input || '{"p_visibility":"selected","p_repeat_interval":"weekly","p_repeat_count":4}',
   '{"audience_usernames":["audience_follower"]}');
 if (select count(*) from public.event_audience_members where event_id=any(ids))<>4 then raise exception 'Series missed its audience'; end if;
 perform set_config('test.audience_series',ids[1]::text,true);
 ids:=public.save_event_plan(null,'this',input || '{"p_visibility":"selected","p_status":"draft"}',
   '{"audience_usernames":["audience_follower"]}');
 perform set_config('test.audience_draft',ids[1]::text,true);
end;$$;

-- Exercise actual authenticated permissions, including direct RLS table reads.
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
do $$
declare plan jsonb;
begin
 if public.get_event_plan(current_setting('test.audience_followers')::uuid) is null then raise exception 'Follower excluded'; end if;
 if public.get_event_plan(current_setting('test.audience_following')::uuid,true) is not null then raise exception 'Follow direction reversed'; end if;
 plan:=public.get_event_plan(current_setting('test.audience_selected')::uuid);
 if plan is null or plan->'audience_usernames'<>'[]'::jsonb then raise exception 'Audience missing or recipients leaked'; end if;
 if public.get_event_plan(current_setting('test.audience_draft')::uuid,true) is not null then raise exception 'Draft leaked'; end if;
 if not exists(select 1 from public.events where id=current_setting('test.audience_followers')::uuid) then raise exception 'RLS excluded follower'; end if;
 if exists(select 1 from public.events where id=current_setting('test.audience_following')::uuid) then raise exception 'RLS leaked following audience'; end if;
 if not exists(select 1 from public.discover_event_plans(49.48,8.47,10,'{}') d where d->>'id'=current_setting('test.audience_followers')) then raise exception 'Discover omitted follower event'; end if;
 if exists(select 1 from public.discover_event_plans(49.48,8.47,10,'{}') d where d->>'id'=current_setting('test.audience_following')) then raise exception 'Discover leaked event'; end if;
 if not exists(select 1 from public.list_profile_events('92000000-0000-4000-8000-000000000001','hosting') e where e.id=current_setting('test.audience_followers')::uuid) then raise exception 'Host profile omitted audience event'; end if;
 perform public.set_event_saved(current_setting('test.audience_public')::uuid,true);
 if (public.get_ai_recommendation_state('event',array[current_setting('test.audience_public')::uuid,current_setting('test.audience_selected')::uuid])->>'eligible')::boolean then
  raise exception 'Private content eligible for automatic model reranking'; end if;
 perform public.set_event_rsvp(current_setting('test.audience_selected')::uuid,'joined');
 perform public.set_event_saved(current_setting('test.audience_selected')::uuid,true);
end;$$;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000003',true);
do $$begin
 if public.get_event_plan(current_setting('test.audience_following')::uuid) is null then raise exception 'Following excluded'; end if;
 if public.get_event_plan(current_setting('test.audience_followers')::uuid,true) is not null then raise exception 'Followers direction reversed'; end if;
 if public.get_event_plan(current_setting('test.audience_selected')::uuid) is null then raise exception 'Selected member excluded'; end if;
end;$$;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000004',true);
do $$
declare audience text; target uuid;
begin
 foreach audience in array array['followers','following','selected','draft'] loop
  target:=current_setting('test.audience_' || audience)::uuid;
  if public.get_event_plan(target,true) is not null then raise exception 'Invite bypassed audience'; end if;
  if public.get_event_invite_preview(target) is not null then raise exception 'Public preview leaked event'; end if;
  if public.get_event_meeting_image_key(target) is not null then raise exception 'Image leaked'; end if;
  begin perform public.set_event_rsvp(target,'joined'); raise exception 'Outsider joined';
  exception when sqlstate '42501' then null; when sqlstate 'P0001' then if sqlerrm<>'event_unavailable' then raise; end if; end;
  begin perform public.set_event_saved(target,true); raise exception 'Outsider saved';
  exception when sqlstate 'P0001' then if sqlerrm<>'event_unavailable' then raise; end if; end;
 end loop;
 if public.get_event_plan(current_setting('test.audience_unlisted')::uuid,true) is null then raise exception 'Existing unlisted invitation broken'; end if;
end;$$;
reset role;

-- Usernames may change without transferring audience access to another profile.
update public.profiles set username='audience_renamed' where id='92000000-0000-4000-8000-000000000003';
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000003',true);
do $$begin
 if public.get_event_plan(current_setting('test.audience_selected')::uuid) is null then raise exception 'Username rename lost access'; end if;
end;$$;
-- Seed an already queued notification while its member still has access.
insert into public.push_devices(user_id,token,platform) values
 ('92000000-0000-4000-8000-000000000002','audience-test-device-token','android');
insert into public.member_notifications(user_id,event_id,kind,title,body) values
 ('92000000-0000-4000-8000-000000000002',current_setting('test.audience_selected')::uuid,'announcement','Private reminder','Private event details');
do $$begin
 if not exists(select 1 from public.push_deliveries d join public.member_notifications n on n.id=d.notification_id where n.event_id=current_setting('test.audience_selected')::uuid) then
  raise exception 'Notification fixture did not queue a push'; end if;
end;$$;
-- Narrowing an existing event must revoke access even for saved/joined members.
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select public.save_event_plan(current_setting('test.audience_selected')::uuid,'this',
 current_setting('test.audience_input')::jsonb || '{"p_visibility":"selected"}',
 '{"audience_usernames":["audience_renamed"]}');
select public.save_event_plan(current_setting('test.audience_series')::uuid,'all',
 current_setting('test.audience_input')::jsonb || '{"p_visibility":"selected"}',
 '{"audience_usernames":["audience_renamed"]}');
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
do $$
declare target uuid:=current_setting('test.audience_selected')::uuid;
begin
 if public.get_event_plan(target,true) is not null then raise exception 'Existing RSVP bypassed removal'; end if;
 if exists(select 1 from public.get_event_details(target)) or exists(select 1 from public.get_event_details_v2(target)) then raise exception 'Legacy reader bypassed removal'; end if;
 if exists(select 1 from public.list_my_events_v2('going') where id=target) or exists(select 1 from public.list_my_events('saved') where id=target) then raise exception 'Plans leaked removed event'; end if;
 if public.get_event_plan(current_setting('test.audience_series')::uuid,true) is not null then raise exception 'Series edit retained old audience'; end if;
 begin perform public.create_event_discussion_message(target,'Can I still read this?'); raise exception 'Removed member posted'; exception when sqlstate '42501' then null; end;
 if exists(select 1 from public.list_event_discussion(target)) or exists(select 1 from public.list_event_announcements(target)) then raise exception 'Discussion leaked'; end if;
 if exists(select 1 from public.list_event_conflicts(current_setting('test.audience_public')::uuid) conflict where conflict->>'id'=target::text) then raise exception 'Conflict check leaked removed event'; end if;
 if exists(select 1 from public.list_member_notifications() where event_id=target) then raise exception 'Notification leaked updated event'; end if;
 -- Unsave/cancel still work to clean up a member's own old plan.
 perform public.set_event_saved(target,false);
 perform public.set_event_rsvp(target,'cancelled');
end;$$;
reset role;

select set_config('request.jwt.claim.role','service_role',true);
do $$begin
 if exists(select 1 from public.claim_push_delivery_batch(100) d where d.event_id=current_setting('test.audience_selected')::uuid) then raise exception 'Queued push bypassed audience removal'; end if;
end;$$;
select set_config('request.jwt.claim.role','authenticated',true);

-- Follow changes and blocks are evaluated live.
delete from public.profile_follows where follower_id='92000000-0000-4000-8000-000000000002';
do $$begin
 if public.get_event_plan(current_setting('test.audience_followers')::uuid,true) is not null then raise exception 'Unfollow did not revoke access'; end if;
end;$$;
insert into public.blocks(blocker_id,blocked_id) values('92000000-0000-4000-8000-000000000003','92000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000003',true);
do $$begin
 if public.get_event_plan(current_setting('test.audience_following')::uuid,true) is not null or public.get_event_plan(current_setting('test.audience_selected')::uuid,true) is not null then raise exception 'Block bypassed'; end if;
end;$$;

-- A restricted event can become public and explicitly enable its preview atomically.
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select public.save_event_plan(current_setting('test.audience_selected')::uuid,'this',current_setting('test.audience_input')::jsonb,'{"invite_preview_enabled":true}');
do $$begin
 if public.get_event_invite_preview(current_setting('test.audience_selected')::uuid) is null then raise exception 'Public transition failed'; end if;
end;$$;
rollback;
