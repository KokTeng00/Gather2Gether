-- Exercise the real authenticated role, including direct PostgREST table access.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id,email,raw_user_meta_data) values
 ('93000000-0000-4000-8000-000000000001','security-host@example.test','{"display_name":"Host"}'),
 ('93000000-0000-4000-8000-000000000002','security-member@example.test','{"display_name":"Member"}');
select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000001',true);
select public.create_event_v3('Security walk','A test walk.','Hiking','Park','Park entrance',52.52,13.40,
 now()+interval '1 day',now()+interval '1 day 1 hour',10,true,false,'outdoor','English','all_ages','',
 'published','public','none',1) as ids \gset
select set_config('test.security_public',(:'ids'::uuid[])[1]::text,true);
select public.create_event_v3('Private walk','A private test walk.','Hiking','Park','Private entrance',52.52,13.40,
 now()+interval '1 day',now()+interval '1 day 1 hour',10,true,false,'outdoor','English','all_ages','',
 'published','selected','none',1) as ids \gset
select set_config('test.security_private',(:'ids'::uuid[])[1]::text,true);
do $$ declare ids uuid[]; begin
 for i in 1..20 loop
  ids:=public.create_event_v3('Rate test ' || i,'A test walk.','Hiking','Park','Park entrance',52.52,13.40,
   now()+interval '1 day',now()+interval '1 day 1 hour',10,true,false,'outdoor','English','all_ages','',
   'published','public','none',1);
  perform set_config('test.security_extra_' || i,ids[1]::text,true);
 end loop;
end; $$;

select set_config('request.jwt.claim.sub','93000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;

do $$ begin
 begin
  insert into public.reports(reporter_id,event_id,reason,status)
   values(auth.uid(),current_setting('test.security_public')::uuid,'spam','resolved');
  raise exception 'Member supplied a moderator-only report status';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.reports(reporter_id,event_id,reason,created_at)
   values(auth.uid(),current_setting('test.security_public')::uuid,'spam',now()-interval '1 year');
  raise exception 'Member forged report creation time';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.reports(reporter_id,event_id,reason)
   values(auth.uid(),current_setting('test.security_private')::uuid,'spam');
  raise exception 'Member reported an inaccessible private event';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.reports(reporter_id,event_id,reason)
   values('93000000-0000-4000-8000-000000000001',current_setting('test.security_public')::uuid,'spam');
  raise exception 'Member impersonated another reporter';
 exception when insufficient_privilege then null; end;
end; $$;

-- Retries must remain successful without creating duplicate moderation work.
insert into public.reports(reporter_id,event_id,reason)
 values(auth.uid(),current_setting('test.security_public')::uuid,'spam');
insert into public.reports(reporter_id,event_id,reason)
 values(auth.uid(),current_setting('test.security_public')::uuid,'misleading');
reset role;
do $$ begin
 if (select count(*) from public.reports where reporter_id=auth.uid())<>1 then
  raise exception 'Report retries created duplicate rows';
 end if;
end; $$;

set local role authenticated;
do $$ begin
 for i in 1..19 loop
  insert into public.reports(reporter_id,event_id,reason)
   values(auth.uid(),current_setting('test.security_extra_' || i)::uuid,'spam');
 end loop;
 begin
  insert into public.reports(reporter_id,event_id,reason)
   values(auth.uid(),current_setting('test.security_extra_20')::uuid,'spam');
  raise exception 'Report rate limit was bypassed';
 exception when sqlstate 'P0001' then
  if sqlerrm<>'report_rate_limited' then raise; end if;
 end;
end; $$;
reset role;

-- Elevated app metadata alone does not prove the session completed MFA.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal1","app_metadata":{"role":"moderator"}}',true);
do $$ begin
 if public.get_moderation_status() then raise exception 'Moderator bypassed MFA'; end if;
 begin
  perform public.list_moderation_reports('open');
  raise exception 'Moderator read sensitive reports without MFA';
 exception when insufficient_privilege then null; end;
end; $$;
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal2","user_metadata":{"role":"moderator"}}',true);
do $$ begin
 if public.get_moderation_status() then raise exception 'User metadata granted moderator authority'; end if;
end; $$;
select set_config('request.jwt.claims','{"sub":"93000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal2","app_metadata":{"role":"moderator"}}',true);
do $$ begin
 if not public.get_moderation_status() then raise exception 'Verified moderator lost access'; end if;
 perform public.list_moderation_reports('open');
end; $$;
reset role;
rollback;
