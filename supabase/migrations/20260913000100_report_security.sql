-- Preserve the existing report POST contract, but limit direct client writes
-- to user input. Status, timestamps and identifiers are server-owned.
revoke insert on public.reports from authenticated;
grant insert (reporter_id,event_id,reason) on public.reports to authenticated;

create index reports_reporter_created_idx on public.reports(reporter_id,created_at desc);
create index reports_reporter_event_idx on public.reports(reporter_id,event_id);

create function public._guard_event_report()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or new.reporter_id is distinct from auth.uid()
    or not public.can_view_event(new.event_id,true) then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if public._can_manage_event(new.event_id,auth.uid()) then
    raise exception using errcode='22023',message='cannot_report_own_content';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('event-reports:' || auth.uid()::text,0)
  );
  -- Idempotent retries also work with existing historical duplicate reports;
  -- no report history needs to be removed to install this protection.
  if exists(select 1 from public.reports r
    where r.reporter_id=auth.uid() and r.event_id=new.event_id) then
    return null;
  end if;
  if (select count(*) from public.reports r where r.reporter_id=auth.uid()
    and r.created_at>pg_catalog.now()-interval '1 hour')>=20 then
    raise exception using errcode='P0001',message='report_rate_limited';
  end if;
  new.id:=pg_catalog.gen_random_uuid();
  new.status:='open';
  new.created_at:=pg_catalog.now();
  return new;
end;
$$;
revoke all on function public._guard_event_report() from public,anon,authenticated;
create trigger reports_guard_insert before insert on public.reports
  for each row execute function public._guard_event_report();

drop policy reports_insert_own on public.reports;
create policy reports_insert_own on public.reports for insert to authenticated
  with check (reporter_id=(select auth.uid()) and public.can_view_event(event_id,true));
