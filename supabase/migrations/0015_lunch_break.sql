-- =====================================================================
-- 0015: ตั้งค่าพักเที่ยงต่อจ็อบ (Purchase กด "มีพักเที่ยง 1 ชม. / ไม่พักเที่ยง" เหมือนพักเย็น)
--   ไม่พักเที่ยง = ไม่หักช่วง 12:00–13:00 ชั่วโมงทำงานเพิ่มขึ้นตามจริง
--   เปลี่ยนแล้วต้องยืนยันเงื่อนไขใหม่ · ใบคิดราคาที่ส่งไปแล้วไม่เปลี่ยน (ตัวเลขถูกล็อกไว้)
-- รันใน Supabase SQL Editor ต่อจาก 0014 (รันซ้ำได้)
-- =====================================================================

alter table public.jobs add column if not exists lunch_break boolean not null default true;

create or replace view public.v_attendance_hours with (security_invoker = true) as
select a.id, a.worker_id, a.job_id, a.team_id, a.work_date, a.check_in, a.check_out,
       a.source, a.note, a.updated_by, a.updated_at,
       j.workweek, j.evening_break,
       public.is_holiday(a.work_date, j.workweek) as holiday,
       h.normal_h, h.ot_h,
       a.edit_count
from public.attendance a
join public.jobs j on j.id = a.job_id
cross join public.app_settings s
cross join lateral public.calc_hours(
  a.check_in, a.check_out, j.evening_break,
  (s.normal_hours * 60)::int, s.lunch_start,
  case when j.lunch_break then s.lunch_end else s.lunch_start end,   -- ไม่พักเที่ยง = ช่วงพักยาว 0 นาที
  s.evening_break_minutes, s.round_minutes, s.grace_minutes) h
where s.id = 1;

create or replace function public.guard_jobs() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not public.has_role('admin')
     and (to_jsonb(new) - 'workweek' - 'evening_break' - 'lunch_break' - 'terms_confirmed_by' - 'terms_confirmed_at' - 'budget')
      <> (to_jsonb(old) - 'workweek' - 'evening_break' - 'lunch_break' - 'terms_confirmed_by' - 'terms_confirmed_at' - 'budget') then
    raise exception 'แก้ไขได้เฉพาะเงื่อนไขการคิดราคา';
  end if;
  if (new.workweek, new.evening_break, new.lunch_break) is distinct from (old.workweek, old.evening_break, old.lunch_break)
     or new.terms_confirmed_at is distinct from old.terms_confirmed_at
     or new.terms_confirmed_by is distinct from old.terms_confirmed_by then
    if not public.has_role('admin', 'purchase') then raise exception 'เฉพาะ Purchase หรือแอดมิน'; end if;
    new.terms_confirmed_by := auth.uid();
    new.terms_confirmed_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.cost_preview(p_job uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare s public.app_settings; j public.jobs; v_workers jsonb; v_sub numeric; v_pending int; v_missing int;
begin
  if not public.can_see_job(p_job) then raise exception 'ไม่มีสิทธิ์'; end if;
  select * into s from public.app_settings where id = 1;
  select * into j from public.jobs where id = p_job;

  with d as (
    select v.worker_id, v.work_date, v.holiday, v.check_in, v.check_out, v.normal_h, v.ot_h, v.edit_count,
           coalesce(ds.supervisor_approved_at is not null and ds.planner_approved_at is not null, false) as approved
    from public.v_attendance_hours v
    left join public.day_sheets ds on ds.team_id = v.team_id and ds.work_date = v.work_date
    where v.job_id = p_job and v.work_date between p_from and p_to
  ),
  base as (
    select w.id, w.full_name, w.position, t.name as team_name, coalesce(r.day_rate, 0) as day_rate,
           coalesce(r.day_rate, 0) / s.normal_hours as unit,
           dd.days, coalesce(dd.n1, 0) n1, coalesce(dd.ot15, 0) ot15, coalesce(dd.h2, 0) h2, coalesce(dd.h3, 0) h3,
           coalesce(dd.work_days, 0) work_days,
           coalesce(aa.allowances, '[]'::jsonb) allowances, coalesce(aa.allow_total, 0) allow_total
    from public.workers w
    join public.teams t on t.id = w.team_id
    left join public.worker_rates r on r.worker_id = w.id
    left join lateral (
      select jsonb_agg(jsonb_build_object('date', d.work_date, 'holiday', d.holiday, 'in', d.check_in,
               'out', d.check_out, 'normal', d.normal_h, 'ot', d.ot_h, 'approved', d.approved, 'edits', d.edit_count) order by d.work_date) days,
             sum(d.normal_h) filter (where not d.holiday) n1, sum(d.ot_h) filter (where not d.holiday) ot15,
             sum(d.normal_h) filter (where d.holiday) h2, sum(d.ot_h) filter (where d.holiday) h3,
             count(*) filter (where d.check_out is not null) work_days
      from d where d.worker_id = w.id) dd on true
    left join lateral (
      select jsonb_agg(jsonb_build_object('date', a.work_date, 'kind', a.kind, 'amount', a.amount) order by a.work_date, a.kind) allowances,
             sum(a.amount) allow_total
      from public.allowances a where a.worker_id = w.id and a.work_date between p_from and p_to) aa on true
    where w.job_id = p_job and (dd.days is not null or aa.allowances is not null)
  ),
  priced as (
    select b.*,
      round(b.n1 * b.unit, 2) a1, round(b.ot15 * b.unit * 1.5, 2) a15,
      round(b.h2 * b.unit * 2, 2) a2, round(b.h3 * b.unit * 3, 2) a3
    from base b
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'worker_id', p.id, 'name', p.full_name, 'position', p.position, 'team', p.team_name,
           'day_rate', p.day_rate, 'unit', round(p.unit, 4), 'work_days', p.work_days,
           'hours', jsonb_build_object('n1', p.n1, 'ot15', p.ot15, 'h2', p.h2, 'h3', p.h3),
           'amounts', jsonb_build_object('n1', p.a1, 'ot15', p.a15, 'h2', p.a2, 'h3', p.a3),
           'allowance_total', p.allow_total,
           'total', p.a1 + p.a15 + p.a2 + p.a3 + p.allow_total,
           'days', coalesce(p.days, '[]'::jsonb), 'allowances', p.allowances)
           order by p.team_name, p.full_name), '[]'::jsonb),
         coalesce(sum(p.a1 + p.a15 + p.a2 + p.a3 + p.allow_total), 0)
    into v_workers, v_sub
  from priced p;

  -- วันที่เปิดลงเวลาแต่ไม่มีใครมาทำงาน ไม่ต้องรออนุมัติ
  select count(*) into v_pending from public.day_sheets ds
  where ds.job_id = p_job and ds.work_date between p_from and p_to
    and (ds.supervisor_approved_at is null or ds.planner_approved_at is null)
    and exists (select 1 from public.attendance a where a.team_id = ds.team_id and a.work_date = ds.work_date);
  select count(*) into v_missing from jsonb_array_elements(v_workers) x
  where (x ->> 'day_rate')::numeric <= 0
    and ((x -> 'hours' ->> 'n1')::numeric + (x -> 'hours' ->> 'ot15')::numeric
       + (x -> 'hours' ->> 'h2')::numeric + (x -> 'hours' ->> 'h3')::numeric) > 0;

  return jsonb_build_object(
    'job', jsonb_build_object('id', j.id, 'job_no', j.job_no, 'title', j.title, 'contractor', j.contractor_name,
                              'location', j.location, 'workweek', j.workweek, 'evening_break', j.evening_break, 'lunch_break', j.lunch_break),
    'period', jsonb_build_object('from', p_from, 'to', p_to),
    'settings', jsonb_build_object('normal_hours', s.normal_hours, 'wht_rate', s.wht_rate,
                                   'break_minutes', s.evening_break_minutes, 'round_minutes', s.round_minutes,
                                   'company', s.company_name),
    'holidays', coalesce((select jsonb_agg(h.holiday_date order by h.holiday_date) from public.holidays h
                          where h.holiday_date between p_from and p_to), '[]'::jsonb),
    'workers', v_workers,
    'subtotal', v_sub,
    'wht', round(v_sub * s.wht_rate / 100, 2),
    'net', v_sub - round(v_sub * s.wht_rate / 100, 2),
    'pending_days', v_pending,
    'missing_rates', v_missing,
    'generated_at', now());
end;
$$;

revoke all on public.v_attendance_hours from anon;
grant select on public.v_attendance_hours to authenticated;
revoke execute on function public.guard_jobs() from public, anon, authenticated;
revoke execute on function public.cost_preview(uuid, date, date) from public, anon;
grant execute on function public.cost_preview(uuid, date, date) to authenticated;

notify pgrst, 'reload schema';
