-- Run after all migrations against a disposable database. Every fixture rolls back.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('91000000-0000-4000-8000-000000000001','planning-host@example.test','{"display_name":"Planning host"}'),
 ('91000000-0000-4000-8000-000000000002','planning-one@example.test','{"display_name":"One"}'),
 ('91000000-0000-4000-8000-000000000003','planning-two@example.test','{"display_name":"Two"}'),
 ('91000000-0000-4000-8000-000000000004','planning-three@example.test','{"display_name":"Three"}');
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select set_config('test.planning_input',jsonb_build_object(
 'p_title','A walk by the river','p_description','Meet for a relaxed walk.','p_category','Hiking',
 'p_venue_name','River park','p_address','Private entrance details',
 'p_latitude',49.48,'p_longitude',8.47,'p_start_at',now()+interval '7 days','p_end_at',now()+interval '7 days 2 hours',
 'p_max_participants',4,'p_beginner_friendly',true,'p_wheelchair_accessible',false,
 'p_event_setting','outdoor','p_event_language','English','p_age_guidance','all_ages','p_what_to_bring','Water',
 'p_status','published','p_visibility','public','p_repeat_interval','none','p_repeat_count',1)::text,true);
select set_config('test.planning_details',jsonb_build_object('allow_guest',true,'meeting_instructions','At the café entrance',
 'meeting_latitude',49.481,'meeting_longitude',8.472,'invite_preview_enabled',true,'preview_area','Mannheim',
 'timezone_offset_minutes',120)::text,true);
select (public.save_event_plan(null,'this',current_setting('test.planning_input')::jsonb,current_setting('test.planning_details')::jsonb))[1] as event_id \gset
select set_config('test.planning_event',:'event_id',true);

do $$
declare preview jsonb; plan jsonb;
begin
 preview:=public.get_event_invite_preview(current_setting('test.planning_event')::uuid);
 if preview->>'area'<>'Mannheim' or preview ? 'address' or preview ? 'meeting_latitude' or preview ? 'meeting_instructions' then raise exception 'Preview exposed meeting data'; end if;
 plan:=public.get_event_plan(current_setting('test.planning_event')::uuid,false);
 if plan->>'meeting_instructions'<>'At the café entrance' or (plan->>'joined_count')::integer<>1 then raise exception 'Meeting details missing'; end if;
end;$$;

select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select public.set_event_rsvp_with_guest(:'event_id','joined',1);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000003',true);
select public.set_event_rsvp_with_guest(:'event_id','joined',1);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000004',true);
select public.set_event_rsvp_with_guest(:'event_id','joined',0);
do $$begin
 if (select status from public.event_rsvps where event_id=current_setting('test.planning_event')::uuid and user_id=auth.uid())<>'waitlisted' then raise exception 'Solo member jumped waiting party'; end if;
 if public._event_places(current_setting('test.planning_event')::uuid)<>3 then raise exception 'Guest capacity was not counted'; end if;
end;$$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select public.set_event_rsvp(:'event_id','cancelled');
do $$begin
 if public._event_places(current_setting('test.planning_event')::uuid)<>4 then raise exception 'All newly available places were not promoted'; end if;
 if exists(select 1 from public.event_rsvps where event_id=current_setting('test.planning_event')::uuid and status='waitlisted') then raise exception 'Queue was not drained'; end if;
end;$$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000004',true);
do $$begin
 begin
  perform public.set_event_rsvp_with_guest(current_setting('test.planning_event')::uuid,'joined',1);
  raise exception 'Overbooked with added guest';
 exception when sqlstate 'P0001' then if sqlerrm<>'guest_place_unavailable' then raise; end if; end;
 if (select status from public.event_rsvps where event_id=current_setting('test.planning_event')::uuid and user_id=auth.uid())<>'joined' then raise exception 'Own place was lost'; end if;
end;$$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
do $$begin
 begin
  update public.events set max_participants=3 where id=current_setting('test.planning_event')::uuid;
  raise exception 'Legacy editor undercounted guests';
 exception when sqlstate '22023' then if sqlerrm<>'capacity_below_attendance' then raise; end if; end;
 begin
  update public.events set allow_guest=false where id=current_setting('test.planning_event')::uuid;
  raise exception 'Existing guests were silently removed';
 exception when sqlstate '22023' then if sqlerrm<>'guests_already_registered' then raise; end if; end;
 if (public.get_event_host_dashboard(current_setting('test.planning_event')::uuid)->>'joined')::integer<>4 then raise exception 'Host count excludes guests'; end if;
end;$$;

-- Check-in can open before the start. It must not release a confirmed party.
update public.events set start_at=now()+interval '2 hours',end_at=now()+interval '4 hours' where id=:'event_id';
select public.set_event_attendance(:'event_id','91000000-0000-4000-8000-000000000003','attended');
do $$begin
 if public._event_places(current_setting('test.planning_event')::uuid)<>4 then raise exception 'Early check-in released party places'; end if;
end;$$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select public.set_event_rsvp_with_guest(:'event_id','tentative',1);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
do $$begin
 begin
  perform public.set_event_attendance(current_setting('test.planning_event')::uuid,'91000000-0000-4000-8000-000000000002','attended');
  raise exception 'Host check-in overbooked a tentative party';
 exception when sqlstate 'P0001' then if sqlerrm<>'guest_place_unavailable' then raise; end if; end;
end;$$;
select public.set_event_attendance(:'event_id','91000000-0000-4000-8000-000000000003','joined');
update public.events set start_at=now()+interval '7 days',end_at=now()+interval '7 days 2 hours' where id=:'event_id';

-- An existing plan warns about strictly overlapping intervals, not touching edges.
select (public.save_event_plan(null,'this',current_setting('test.planning_input')::jsonb || '{"p_title":"Another walk"}',current_setting('test.planning_details')::jsonb))[1] as overlap_id \gset
select set_config('test.overlap_event',:'overlap_id',true);
do $$begin
 if (select count(*) from public.list_event_conflicts(current_setting('test.overlap_event')::uuid))<>1 then raise exception 'Overlapping hosted plan not detected'; end if;
end;$$;

-- Date constraints are applied before the candidate limit.
insert into public.events(organizer_id,title,description,category,venue_name,address,location,start_at,end_at,max_participants)
 select auth.uid(),'Earlier walk '||n,'A walk','Hiking','River park','Address',extensions.st_setsrid(extensions.st_makepoint(8.47,49.48),4326)::extensions.geography,
 now()+interval '1 day'+n*interval '1 minute',now()+interval '1 day 1 hour'+n*interval '1 minute',12 from generate_series(1,70)n;
do $$begin
 if (select count(*) from public.discover_event_plans(49.48,8.47,10,jsonb_build_object('start_from',now()+interval '6 days','start_before',now()+interval '8 days')))<2 then raise exception 'Date filtering happened after the limit'; end if;
end;$$;

select public.create_forum_post_with_poll('Who is free for a walk?','Let us find a day for a walk by the river.','Event ideas',null,'River park','Mannheim',
 jsonb_build_array(jsonb_build_object('start_at',now()+interval '10 days','end_at',now()+interval '10 days 2 hours'),
 jsonb_build_object('start_at',now()+interval '11 days','end_at',now()+interval '11 days 2 hours'))) as post_id \gset
select set_config('test.poll_post',:'post_id',true);
select id as option_id from public.forum_poll_options where post_id=:'post_id' order by start_at limit 1 \gset
select set_config('test.poll_option',:'option_id',true);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
select public.set_forum_poll_vote(:'post_id',:'option_id',true);
select public.set_forum_poll_vote(:'post_id',:'option_id',true);
do $$begin
 if (select count(*) from public.forum_poll_votes where post_id=current_setting('test.poll_post')::uuid)<>1 then raise exception 'Repeated vote counted twice'; end if;
 begin
  perform public.save_event_plan(null,'this',current_setting('test.planning_input')::jsonb,current_setting('test.planning_details')::jsonb,current_setting('test.poll_post')::uuid,current_setting('test.poll_option')::uuid);
  raise exception 'Non-author converted poll';
 exception when insufficient_privilege then null; end;
end;$$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select (public.save_event_plan(null,'this',current_setting('test.planning_input')::jsonb ||
 (select jsonb_build_object('p_start_at',start_at,'p_end_at',end_at) from public.forum_poll_options where id=:'option_id'),
 current_setting('test.planning_details')::jsonb,:'post_id',:'option_id'))[1] as poll_event_id \gset
select set_config('test.poll_event',:'poll_event_id',true);
do $$begin
 if (public.get_forum_poll(current_setting('test.poll_post')::uuid)->>'closed')::boolean is not true then raise exception 'Converted poll not closed'; end if;
 if exists(select 1 from public.event_rsvps where event_id=current_setting('test.poll_event')::uuid and user_id='91000000-0000-4000-8000-000000000002') then raise exception 'Vote became RSVP without consent'; end if;
 begin
  perform public.save_event_plan(null,'this',current_setting('test.planning_input')::jsonb,current_setting('test.planning_details')::jsonb,current_setting('test.poll_post')::uuid,current_setting('test.poll_option')::uuid);
  raise exception 'Poll converted twice';
 exception when sqlstate 'P0001' then if sqlerrm<>'poll_closed' then raise; end if; end;
end;$$;

-- A saved search keeps its own area even when the profile is elsewhere.
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000002',true);
update public.profiles set approximate_latitude=52.52,approximate_longitude=13.405 where id=auth.uid();
select public.save_event_search_plan(null,jsonb_build_object('p_name','Mannheim next week','p_interest','','p_radius_km',10,'p_category',null,
 'p_date_filter','any','p_time_filter','any','p_timezone_offset_minutes',120,'p_spots_only',false,'p_following_only',false,
 'p_beginner_friendly_only',false,'p_wheelchair_accessible_only',false,'p_event_setting','any','p_event_language','','p_age_guidance','any','p_alerts_enabled',true),
 jsonb_build_object('latitude',49.48,'longitude',8.47,'area','Mannheim','start_from',now()+interval '6 days','start_before',now()+interval '8 days')) as search_id \gset
select set_config('test.planning_search',:'search_id',true);
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select (public.save_event_plan(null,'this',current_setting('test.planning_input')::jsonb || '{"p_title":"New matching walk"}',current_setting('test.planning_details')::jsonb))[1] as matching_event_id \gset
select set_config('test.matching_event',:'matching_event_id',true);
do $$begin
 if not exists(select 1 from public.member_notifications where source_id=current_setting('test.planning_search')::uuid and event_id=current_setting('test.matching_event')::uuid) then raise exception 'Saved area/date alert did not fire'; end if;
 update public.events set invite_preview_enabled=false where id=current_setting('test.planning_event')::uuid;
 if public.get_event_invite_preview(current_setting('test.planning_event')::uuid) is not null then raise exception 'Disabled preview still exposed'; end if;
 if has_function_privilege('anon','public.get_event_plan(uuid,boolean)','execute') or has_table_privilege('authenticated','public.forum_poll_votes','select') then raise exception 'Planning data exposed without authorization'; end if;
end;$$;
rollback;
