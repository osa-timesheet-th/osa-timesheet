-- ทดสอบบนฐานข้อมูลจำลองเท่านั้น (stub.sql + migrations) — ห้ามรันบน Supabase จริง
\set ON_ERROR_STOP 1
set client_min_messages = warning;

create or replace function pg_temp.ok(cond boolean, label text) returns void language plpgsql as $$
begin
  if cond is not true then raise exception 'FAIL: %', label; end if;
  raise notice 'ok - %', label;
end $$;

create or replace function pg_temp.as_user(p_id uuid, p_aal text default 'aal2') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated', 'aal', p_aal)::text, false);
end $$;

create or replace function pg_temp.raises(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  return true;
end $$;

set client_min_messages = notice;

-- ---------- 1. สูตรชั่วโมง ----------
create temp table hcase (cin text, cout text, brk boolean, n numeric, ot numeric);
insert into hcase values
  ('08:00','17:00',true, 8,0),
  ('08:00','21:00',true, 8,3.5),
  ('06:00','20:00',true, 8,4.5),
  ('08:00','12:00',true, 4,0),
  ('08:00','22:00',true, 8,4.5),
  ('08:00','21:00',false,8,4),
  ('08:03','17:00',true, 8,0),      -- สาย 3 นาที ยังได้ 8 (เผื่อ 5 นาที)
  ('08:20','17:00',true, 7.5,0),    -- สาย 20 นาที
  ('08:00','20:20',true, 8,2.5),    -- OT 2:50 → 2.5
  ('08:00','17:40',true, 8,0),      -- พัก 17:00-17:30 แล้ว 10 นาที → 0
  ('13:00','17:00',true, 4,0),      -- บ่ายอย่างเดียว ไม่หักเที่ยง
  ('12:30','17:00',true, 4,0);      -- คร่อมพักเที่ยงครึ่งชั่วโมง
do $$ declare r record; h record; begin
  for r in select * from hcase loop
    select * into h from public.calc_hours(('2026-10-05 '||r.cin||'+07')::timestamptz, ('2026-10-05 '||r.cout||'+07')::timestamptz,
                                           r.brk, 480, '12:00', '13:00', 30, 30, 5);
    perform pg_temp.ok(h.normal_h = r.n and h.ot_h = r.ot,
      format('calc %s-%s break=%s => %s/%s (got %s/%s)', r.cin, r.cout, r.brk, r.n, r.ot, h.normal_h, h.ot_h));
  end loop;
end $$;

-- ---------- 2. ผู้ใช้ ----------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'admin@test.local'),
  ('00000000-0000-0000-0000-000000000001', 'sup1@test.local'),
  ('00000000-0000-0000-0000-000000000002', 'sup2@test.local'),
  ('00000000-0000-0000-0000-0000000000b1', 'planner@test.local'),
  ('00000000-0000-0000-0000-0000000000c1', 'purchase@test.local'),
  ('00000000-0000-0000-0000-0000000000d1', 'manager@test.local'),
  ('00000000-0000-0000-0000-0000000000ff', 'nobody@test.local');
update public.profiles set role = 'admin', full_name = 'แอดมิน' where email = 'admin@test.local';
update public.profiles set role = 'supervisor', full_name = 'หัวหน้า 1' where email = 'sup1@test.local';
update public.profiles set role = 'supervisor', full_name = 'หัวหน้า 2' where email = 'sup2@test.local';
update public.profiles set role = 'planner', full_name = 'แพลนเนอร์' where email = 'planner@test.local';
update public.profiles set role = 'purchase', full_name = 'จัดซื้อ' where email = 'purchase@test.local';
update public.profiles set role = 'manager', full_name = 'ผู้จัดการ' where email = 'manager@test.local';

-- ---------- 3. แอดมินสร้างจ็อบ ----------
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into public.jobs (id, job_no, title, contractor_name, start_date, end_date)
values ('10000000-0000-0000-0000-000000000001', 'VT260020', 'PTT GSP6', 'ชุดทดสอบ', public.bkk_today() - 20, public.bkk_today() + 5);
insert into public.teams (id, job_id, name, supervisor_id) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'ทีม A', '00000000-0000-0000-0000-000000000001');
insert into public.workers (id, job_id, team_id, full_name) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'สมชาย  ทดสอบ'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'สมหญิง ทดสอบ');
select pg_temp.ok((select full_name from public.workers where id = '30000000-0000-0000-0000-000000000001') = 'สมชาย ทดสอบ', 'ชื่อถูกจัดช่องว่าง');

-- แอดมินไม่มี MFA → มองไม่เห็น
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'aal1');
select pg_temp.ok((select count(*) from public.jobs) = 0, 'admin ไม่มี MFA มองไม่เห็นข้อมูล');

-- ---------- 4. สิทธิ์การมองเห็น ----------
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
select pg_temp.ok((select count(*) from public.jobs) = 0, 'หัวหน้า 2 มองไม่เห็นจ็อบที่ไม่ได้คุม');
select pg_temp.ok(pg_temp.raises($q$insert into public.workers (job_id, team_id, full_name) values ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','แอบเพิ่ม')$q$), 'หัวหน้า 2 เพิ่มคนในจ็อบอื่นไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000ff');
select pg_temp.ok((select count(*) from public.jobs) = 0 and (select count(*) from public.profiles) = 1, 'คนไม่มี role เห็นแค่โปรไฟล์ตัวเอง');
select pg_temp.ok(pg_temp.raises($q$update public.profiles set role = 'admin' where id = auth.uid()$q$)
  or (select role from public.profiles where id = auth.uid()) is null, 'ตั้งตัวเองเป็นแอดมินไม่ได้');

select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok((select count(*) from public.jobs) = 1, 'หัวหน้า 1 เห็นจ็อบตัวเอง');
insert into public.workers (job_id, team_id, full_name) values ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','เพิ่มโดยหัวหน้า');
select pg_temp.ok(pg_temp.raises($q$update public.jobs set title = 'แก้' $q$) or (select title from public.jobs) = 'PTT GSP6', 'หัวหน้าแก้จ็อบไม่ได้');
select pg_temp.ok(pg_temp.raises($q$update public.day_sheets set planner_approved_at = now()$q$), 'แก้ day_sheets ตรงไม่ได้');

-- ---------- 5. anon: ตารางปิดหมด ----------
reset role; set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
select pg_temp.ok(pg_temp.raises('select * from public.workers'), 'anon อ่าน workers ไม่ได้');
select pg_temp.ok(pg_temp.raises('select * from public.daily_pins'), 'anon อ่าน PIN ไม่ได้');
select pg_temp.ok(pg_temp.raises('select * from public.v_attendance_hours'), 'anon อ่าน view ไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.generate_pins('20000000-0000-0000-0000-000000000001')$q$), 'anon สร้าง PIN ไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.cost_preview('10000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31')$q$), 'anon ดูราคาไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.kiosk_check_pin('x', null, null)$q$), 'anon เรียก kiosk_check_pin ตรงไม่ได้');

reset role;
insert into public.kiosk_tokens (team_id, kind, expires_at) values ('20000000-0000-0000-0000-000000000001', 'in', now() + interval '1 hour') returning token as tok \gset
insert into public.kiosk_tokens (team_id, kind, expires_at) values ('20000000-0000-0000-0000-000000000001', 'out', now() + interval '1 hour') returning token as tok_out \gset
select qr_token as oldtok from public.teams where id = '20000000-0000-0000-0000-000000000001' \gset
set role anon;
select pg_temp.ok(public.kiosk_team(:'oldtok') ->> 'error' = 'QR ไม่ถูกต้อง', 'QR ประจำทีมแบบเดิมใช้ลงเวลาไม่ได้แล้ว');
select pg_temp.ok((public.kiosk_team('bad') ->> 'ok')::boolean = false, 'QR ผิดถูกปฏิเสธ');
select pg_temp.ok(public.kiosk_team(:'tok') ->> 'error' like 'หัวหน้างานยังไม่เปิด%', 'ยังไม่เปิดลงเวลา สแกน QR แล้วถูกปฏิเสธ');
select pg_temp.ok(public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000001', '0000') ->> 'error' like 'หัวหน้างานยังไม่เปิด%', 'ยังไม่เปิด ใส่ PIN ไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.open_day('20000000-0000-0000-0000-000000000001')$q$), 'anon เปิดลงเวลาไม่ได้');

reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(public.generate_pins('20000000-0000-0000-0000-000000000001') = 3, 'หัวหน้าสร้าง PIN 3 คน');
select pg_temp.ok(public.generate_pins('20000000-0000-0000-0000-000000000001') = 0, 'สร้างซ้ำไม่ทับของเดิม');
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
select pg_temp.ok(pg_temp.raises($q$select public.open_day('20000000-0000-0000-0000-000000000001')$q$), 'หัวหน้าทีมอื่นเปิดลงเวลาแทนไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select pg_temp.ok(pg_temp.raises($q$select public.open_day('20000000-0000-0000-0000-000000000001')$q$), 'Planner เปิดลงเวลาไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok((public.open_day('20000000-0000-0000-0000-000000000001') ->> 'pins_created')::int = 0, 'หัวหน้าเปิดลงเวลาวันนี้ได้');
select pg_temp.ok((select opened_by = '00000000-0000-0000-0000-000000000001' from public.day_sheets), 'บันทึกว่าใครเปิด');
reset role; set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
select pg_temp.ok(jsonb_array_length(public.kiosk_team(:'tok') -> 'workers') = 3, 'เปิดแล้ว QR ได้รายชื่อทีม');
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pin as pin1 from public.daily_pins where worker_id = '30000000-0000-0000-0000-000000000001' \gset
select (select pin from public.daily_pins where worker_id = '30000000-0000-0000-0000-000000000002') as pin2 \gset
select pg_temp.ok((select count(distinct pin) from public.daily_pins) = 3, 'PIN ในทีมไม่ซ้ำกัน');

reset role; set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
select pg_temp.ok((public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000001', :'pin2') ->> 'ok')::boolean = false, 'ใช้ PIN ของคนอื่นไม่ได้');
select public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000001', '9999x');
select public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000001', 'aaaa');
select public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000001', 'bbbb');
select pg_temp.ok((public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000001', 'cccc') ->> 'remaining')::int = 0, 'นับครั้งที่ผิดจริง (rollback ไม่ลบ)');
select pg_temp.ok((public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000001', :'pin1') ->> 'locked')::boolean, 'ผิด 5 ครั้งล็อก แม้กรอกถูก');

reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select public.generate_pins('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001');
select pin as pin1 from public.daily_pins where worker_id = '30000000-0000-0000-0000-000000000001' \gset

reset role; set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
select pg_temp.ok((public.kiosk_clock(:'tok', '30000000-0000-0000-0000-000000000001', :'pin1', 'in') ->> 'ok')::boolean, 'เช็คอินสำเร็จหลังรีเซ็ต PIN');
select pg_temp.ok((public.kiosk_clock(:'tok', '30000000-0000-0000-0000-000000000001', :'pin1', 'in') ->> 'ok')::boolean = false, 'เช็คอินซ้ำไม่ได้');
select pg_temp.ok(public.kiosk_clock(:'tok', '30000000-0000-0000-0000-000000000001', :'pin1', 'out') ->> 'error' like 'QR นี้ใช้ลงเวลาเข้างานเท่านั้น%', 'QR เข้างานใช้เช็คเอาท์ไม่ได้');
select pg_temp.ok(public.kiosk_clock(:'tok_out', '30000000-0000-0000-0000-000000000001', :'pin1', 'out') ->> 'error' like 'เพิ่งลงเวลาเข้า%', 'เช็คเอาท์ทันทีไม่ได้');
select pg_temp.ok(jsonb_array_length(public.kiosk_team(:'tok_out') -> 'workers') = 1, 'QR ออกงาน แสดงเฉพาะคนที่ยังไม่ออก');
reset role;
update public.attendance set check_in = check_in - interval '9 hours' where worker_id = '30000000-0000-0000-0000-000000000001';
set role anon;
select pg_temp.ok((public.kiosk_clock(:'tok_out', '30000000-0000-0000-0000-000000000001', :'pin1', 'out') ->> 'ok')::boolean, 'เช็คเอาท์สำเร็จ');
reset role;
select pg_temp.ok((select source from public.attendance where worker_id = '30000000-0000-0000-0000-000000000001') = 'self', 'บันทึกว่าลงเวลาเอง');
select pg_temp.ok((select count(*) from public.day_sheets) = 1, 'สร้างใบรายวันอัตโนมัติ');

-- ---------- 6. ข้อมูลย้อนหลังโดยหัวหน้า + อนุมัติ ----------
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
-- วันจันทร์-อาทิตย์ย้อนหลัง: หาวันอาทิตย์ล่าสุดก่อนวันนี้อย่างน้อย 7 วัน
select (public.bkk_today() - 7 - extract(isodow from public.bkk_today() - 7)::int) as sun \gset
insert into public.attendance (worker_id, team_id, check_in, check_out) values
  ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001', (:'sun'::date - 1 + time '08:00') at time zone 'Asia/Bangkok', (:'sun'::date - 1 + time '21:00') at time zone 'Asia/Bangkok'),
  ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001', (:'sun'::date + time '08:00') at time zone 'Asia/Bangkok', (:'sun'::date + time '22:00') at time zone 'Asia/Bangkok'),
  ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001', (:'sun'::date - 1 + time '08:00') at time zone 'Asia/Bangkok', null);
select pg_temp.ok((select source from public.attendance where work_date = :'sun'::date - 1 and worker_id = '30000000-0000-0000-0000-000000000001') = 'supervisor', 'บันทึกว่าหัวหน้าเป็นคนลง');
select id as sheet_sat from public.day_sheets where work_date = :'sun'::date - 1 \gset
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select pg_temp.ok(pg_temp.raises(format($q$update public.attendance set note = 'planner' where work_date = %L$q$, :'sun'::date - 1)), 'Planner แก้เวลาก่อนหัวหน้างานอนุมัติไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select id as sheet_sun from public.day_sheets where work_date = :'sun'::date \gset
select pg_temp.ok(pg_temp.raises(format('select public.approve_day(%L)', :'sheet_sat')), 'อนุมัติไม่ได้ถ้ามีคนยังไม่ออก');
update public.attendance set check_out = (:'sun'::date - 1 + time '17:00') at time zone 'Asia/Bangkok' where worker_id = '30000000-0000-0000-0000-000000000002' and work_date = :'sun'::date - 1;
select public.approve_day(:'sheet_sat');
select public.approve_day(:'sheet_sun');
select pg_temp.ok(pg_temp.raises(format($q$update public.attendance set check_out = check_out + interval '1 hour' where work_date = %L$q$, :'sun')), 'แก้เวลาไม่ได้หลังหัวหน้าอนุมัติ');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
insert into public.allowances (worker_id, work_date, amount) values
  ('30000000-0000-0000-0000-000000000001', :'sun'::date - 1, 50),
  ('30000000-0000-0000-0000-000000000002', :'sun'::date - 1, 50);
select public.reject_day(:'sheet_sun', 'ตรวจเวลาอีกครั้ง');
select pg_temp.ok((select supervisor_approved_at is null and reject_reason is not null from public.day_sheets where id = :'sheet_sun'), 'planner ตีกลับได้');
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select public.approve_day(:'sheet_sun');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select public.approve_day(:'sheet_sat');
select public.approve_day(:'sheet_sun');
select pg_temp.ok(pg_temp.raises(format($q$insert into public.allowances (worker_id, work_date, amount) values ('30000000-0000-0000-0000-000000000001', %L, 10)$q$, :'sun')), 'เพิ่ม allowance ไม่ได้หลังอนุมัติ');

-- ---------- 7. คิดราคา ----------
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1', 'aal1');
select pg_temp.ok(pg_temp.raises($q$insert into public.worker_rates values ('30000000-0000-0000-0000-000000000001', 1100)$q$), 'purchase ไม่มี MFA ทำไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into public.worker_rates (worker_id, day_rate) values ('30000000-0000-0000-0000-000000000001', 1100), ('30000000-0000-0000-0000-000000000002', 800);
select pg_temp.ok(pg_temp.raises($q$update public.jobs set title = 'x'$q$), 'purchase แก้ชื่อจ็อบไม่ได้');
update public.jobs set workweek = 6, evening_break = true;
select pg_temp.ok((select terms_confirmed_at is null from public.jobs), 'ตั้งค่าเดิมซ้ำ ไม่ถือว่ายืนยัน');
select pg_temp.ok((select count(*) = 1 and min(period_from) <= :'sun'::date - 1 and max(period_to) >= :'sun'::date and min(status) = 'draft'
                    from public.cost_sheets), 'มีใบคิดราคาร่างครอบช่วงจ็อบตั้งแต่สร้างจ็อบ (รวมวันที่อนุมัติแล้ว)');
delete from public.cost_sheets;  -- ทดสอบต่อด้วยใบที่กำหนด id เอง
insert into public.cost_sheets (id, job_id, period_from, period_to) values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', :'sun'::date - 1, :'sun'::date + 2);
select public.cost_preview('10000000-0000-0000-0000-000000000001', :'sun'::date - 1, :'sun'::date) as pv \gset
-- สมชาย 1100/วัน → 137.5/ชม: เสาร์ 8 ปกติ + 3.5 OT, อาทิตย์ 8 ×2 + 4.5 ×3, ค่ารถ 50
--   = 1100 + 3.5*206.25 + 8*275 + 4.5*412.5 + 50 = 1100 + 721.875→721.88 + 2200 + 1856.25 + 50 = 5928.13
-- สมหญิง 800 → 100/ชม: เสาร์ 08-17 = 8 ปกติ + ค่ารถ 50 = 850
select pg_temp.ok((:'pv'::jsonb ->> 'subtotal')::numeric = 6778.13, 'ยอดรวม 6,778.13 (ได้ ' || (:'pv'::jsonb ->> 'subtotal') || ')');
select pg_temp.ok((:'pv'::jsonb ->> 'wht')::numeric = 203.34 and (:'pv'::jsonb ->> 'net')::numeric = 6574.79, 'หัก 3% และยอดสุทธิถูก');
select pg_temp.ok(pg_temp.raises($q$select public.submit_cost_sheet('40000000-0000-0000-0000-000000000001')$q$), 'ส่งไม่ได้ถ้ายังไม่ยืนยันเงื่อนไข');
update public.jobs set terms_confirmed_at = now(), terms_confirmed_by = '00000000-0000-0000-0000-00000000000a';
select pg_temp.ok((select terms_confirmed_by = '00000000-0000-0000-0000-0000000000c1' from public.jobs), 'ยืนยันเงื่อนไขแล้ว และปลอมชื่อผู้ยืนยันไม่ได้');
select public.submit_cost_sheet('40000000-0000-0000-0000-000000000001', :'sun'::date);
select pg_temp.ok((select status = 'submitted' and period_to = :'sun'::date from public.cost_sheets where id = '40000000-0000-0000-0000-000000000001'), 'ส่งถึงวันที่ที่เลือก (ตัดช่วง)');
select pg_temp.ok((select count(*) = 1 from public.cost_sheets where status = 'draft' and period_from = :'sun'::date + 1 and period_to = :'sun'::date + 2), 'วันที่เหลือย้ายไปใบร่างใหม่');
select pg_temp.ok(pg_temp.raises($q$update public.cost_sheets set net_total = 1$q$), 'แก้ยอดเงินหลังส่งไม่ได้');

reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(pg_temp.raises($q$select public.approve_cost_sheet('40000000-0000-0000-0000-000000000001')$q$), 'หัวหน้างานอนุมัติราคาไม่ได้ (ต้องเป็น Manager)');
select pg_temp.ok(pg_temp.raises($q$select public.reject_cost_sheet('40000000-0000-0000-0000-000000000001', 'ทดสอบตีกลับ')$q$), 'หัวหน้างานตีกลับใบคิดราคาไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(pg_temp.raises($q$select public.approve_cost_sheet('40000000-0000-0000-0000-000000000001')$q$), 'Purchase อนุมัติราคาตัวเองไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select pg_temp.ok((select count(*) from public.jobs) >= 1 and (select count(*) from public.attendance) > 0, 'Manager เห็นทุกจ็อบ');
select pg_temp.ok(pg_temp.raises($q$insert into public.worker_rates values ('30000000-0000-0000-0000-000000000002', 5000)$q$)
                  or (select day_rate from public.worker_rates where worker_id = '30000000-0000-0000-0000-000000000002') = 800, 'Manager แก้ค่าแรงไม่ได้');
select pg_temp.ok(pg_temp.raises($q$update public.attendance set note = 'แก้' where true$q$)
                  or not exists (select 1 from public.attendance where note = 'แก้'), 'Manager แก้เวลาไม่ได้');
select pg_temp.ok(pg_temp.raises(format('select public.approve_day(%L)', :'sheet_sat')), 'Manager อนุมัติใบรายวันไม่ได้');
select pg_temp.ok(public.approve_cost_sheet('40000000-0000-0000-0000-000000000001') = 'approved', 'Manager คนเดียวอนุมัติราคาได้');
select pg_temp.ok((select approver_name = 'ผู้จัดการ' from public.cost_sheet_approvals where cost_sheet_id = '40000000-0000-0000-0000-000000000001'), 'บันทึกชื่อ Manager ติดเอกสาร');
select pg_temp.ok((select count(*) from public.audit_log) > 0, 'Manager อ่านประวัติการแก้ไขได้');
select pg_temp.ok((public.job_budgets('10000000-0000-0000-0000-000000000001') -> 0 ->> 'spent')::numeric = 6778.13,
  'Budget หักตามวันที่อนุมัติครบ = ยอดรวมก่อนหัก 3% (' || (public.job_budgets('10000000-0000-0000-0000-000000000001') -> 0 ->> 'spent') || ')');
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select public.set_job_budget('10000000-0000-0000-0000-000000000001', 50000);
select pg_temp.ok((select budget = 50000 from public.jobs where id = '10000000-0000-0000-0000-000000000001'), 'หัวหน้างานตั้ง Budget จ็อบของตัวเองได้');
select pg_temp.ok(pg_temp.raises($q$update public.jobs set title = 'แอบแก้' where id = '10000000-0000-0000-0000-000000000001'$q$)
                  or (select title from public.jobs where id = '10000000-0000-0000-0000-000000000001') = 'PTT GSP6', 'ตั้ง Budget ไม่ได้เปิดให้แก้อย่างอื่น');
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
select pg_temp.ok(pg_temp.raises($q$select public.set_job_budget('10000000-0000-0000-0000-000000000001', 1)$q$), 'ตั้ง Budget จ็อบที่มองไม่เห็นไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(pg_temp.raises(format('select public.unapprove_day(%L)', :'sheet_sat')), 'ยกเลิกอนุมัติวันที่ถูกคิดราคาแล้วไม่ได้');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.ok((select count(*) from public.audit_log) > 10, 'มี audit log');
select pg_temp.ok((public.dashboard() ->> 'active_jobs')::int = 1, 'dashboard ทำงาน');
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(pg_temp.raises('select 1 from public.audit_log limit 1') or (select count(*) from public.audit_log) = 0, 'หัวหน้าอ่าน audit ไม่ได้');

-- ---------- 8. ช่องโหว่จากการตรวจความปลอดภัย (ต้องปิดได้) ----------
reset role; select id as wnew from public.workers where full_name = 'เพิ่มโดยหัวหน้า' \gset
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(pg_temp.raises(format($q$insert into public.attendance (worker_id, job_id, check_in, check_out) values (%L, '10000000-0000-0000-0000-000000000001', %L, %L)$q$,
  :'wnew', ((:'sun'::date - 1 + time '08:00') at time zone 'Asia/Bangkok'), ((:'sun'::date - 1 + time '17:00') at time zone 'Asia/Bangkok'))),
  'H1: เพิ่มเวลาเข้าวันที่ล็อกแล้วโดยไม่ส่ง team_id ไม่ได้');
insert into public.attendance (worker_id, team_id, check_in) values (:'wnew', '20000000-0000-0000-0000-000000000001', now() - interval '1 hour');
select pg_temp.ok(pg_temp.raises(format($q$update public.attendance set check_in = %L where worker_id = %L$q$,
  ((:'sun'::date - 1 + time '08:00') at time zone 'Asia/Bangkok'), :'wnew')), 'H1: ย้ายเวลาเข้าไปวันที่ล็อกแล้วไม่ได้');
select pg_temp.ok(pg_temp.raises(format($q$insert into public.attendance (worker_id, team_id, work_date, check_in) values (%L, '20000000-0000-0000-0000-000000000001', current_date + 30, %L)$q$,
  '30000000-0000-0000-0000-000000000002', ((:'sun'::date + time '08:00') at time zone 'Asia/Bangkok'))), 'H1: ปลอม work_date ไม่ได้');

reset role; set session_replication_role = replica;
insert into public.allowances (worker_id, job_id, work_date, amount) values (:'wnew', '10000000-0000-0000-0000-000000000001', :'sun'::date, 99);
set session_replication_role = origin;
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select pg_temp.ok(pg_temp.raises(format($q$update public.allowances set work_date = public.bkk_today(), amount = 500 where worker_id = %L$q$, :'wnew')),
  'M1: ย้าย allowance ออกจากช่วงที่คิดราคาแล้วไม่ได้');

select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into public.cost_sheets (id, job_id, period_from, period_to, created_by, net_total, status)
values ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', public.bkk_today(), public.bkk_today(),
        '00000000-0000-0000-0000-00000000000a', 9999999, 'draft');
select pg_temp.ok((select created_by = '00000000-0000-0000-0000-0000000000c1' and net_total is null from public.cost_sheets where id = '40000000-0000-0000-0000-000000000002'),
  'L2: ปลอมผู้สร้าง/ยอดเงินตอนสร้างใบคิดราคาไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.period_frozen('10000000-0000-0000-0000-000000000001', current_date)$q$), 'L4: เรียก period_frozen ตรงไม่ได้');

-- ---------- 9. หัวหน้างานต้องมีทุกทีม ----------
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.ok(pg_temp.raises($q$select public.create_job('{"job_no":"NOSUP1","title":"t","start_date":"2026-10-01","end_date":"2026-10-02","teams":[{"name":"A","supervisor_id":""}]}')$q$), 'สร้างจ็อบที่ทีมไม่มีหัวหน้างานไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.create_job('{"job_no":"NOSUP2","title":"t","start_date":"2026-10-01","end_date":"2026-10-02","teams":[{"name":"A","supervisor_id":"00000000-0000-0000-0000-0000000000b1"}]}')$q$), 'เลือก planner เป็นหัวหน้างานไม่ได้');
select pg_temp.ok(pg_temp.raises($q$update public.teams set supervisor_id = null$q$), 'ลบหัวหน้างานออกจากทีมไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok(pg_temp.raises($q$update public.jobs set terms_confirmed_at = now()$q$) or (select terms_confirmed_by = '00000000-0000-0000-0000-0000000000c1' from public.jobs), 'หัวหน้างานยืนยันเงื่อนไขแทนไม่ได้');

-- ---------- 10. ทำงานข้ามเที่ยงคืน ----------
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
insert into public.attendance (worker_id, team_id, check_in, check_out) values
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001',
   (:'sun'::date - 6 + time '20:00') at time zone 'Asia/Bangkok', (:'sun'::date - 5 + time '01:00') at time zone 'Asia/Bangkok');
select pg_temp.ok((select work_date = :'sun'::date - 6 and normal_h = 5 and ot_h = 0 from public.v_attendance_hours
                   where worker_id = '30000000-0000-0000-0000-000000000002' and work_date = :'sun'::date - 6), 'กะ 20:00–01:00 นับเป็นวันเริ่มงาน 5 ชม.');
select pg_temp.ok(pg_temp.raises(format($q$insert into public.attendance (worker_id, team_id, check_in, check_out) values ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', %L, %L)$q$,
   ((:'sun'::date - 8 + time '08:00') at time zone 'Asia/Bangkok'), ((:'sun'::date - 7 + time '09:00') at time zone 'Asia/Bangkok'))), 'กะเกิน 24 ชม. ไม่ได้');

reset role;
insert into public.workers (id, job_id, team_id, full_name) values
  ('30000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'ข้ามคืน ทดสอบ');
set session_replication_role = replica;
insert into public.day_sheets (job_id, team_id, work_date, opened_at) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', public.bkk_today() - 1, now() - interval '1 day')
  on conflict (team_id, work_date) do update set opened_at = coalesce(public.day_sheets.opened_at, excluded.opened_at),
    supervisor_approved_at = null, planner_approved_at = null;
insert into public.daily_pins (worker_id, work_date, pin) values ('30000000-0000-0000-0000-000000000009', public.bkk_today() - 1, '4321');
insert into public.attendance (worker_id, job_id, team_id, work_date, check_in) values
  ('30000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
   public.bkk_today() - 1, now() - interval '3 hours');
set session_replication_role = origin;
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
select pg_temp.ok((public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000009', '4321') ->> 'overnight')::boolean, 'หลังเที่ยงคืน ใช้ PIN เมื่อวานเข้าได้ (กะข้ามคืน)');
select pg_temp.ok(public.kiosk_clock(:'tok', '30000000-0000-0000-0000-000000000009', '4321', 'in') ->> 'error' like 'ยังไม่ได้ลงเวลาออกของเมื่อวาน%', 'ยังไม่ออกของเมื่อวาน เช็คอินใหม่ไม่ได้');
select pg_temp.ok((public.kiosk_clock(:'tok_out', '30000000-0000-0000-0000-000000000009', '4321', 'out') ->> 'ok')::boolean, 'สแกนออกหลังเที่ยงคืนได้');
reset role;
-- (ข้อมูลทดสอบสร้างเวลาเข้าเป็น "3 ชม.ก่อน" จึงเช็กแค่ว่าอัปเดตรายการเดิม ไม่ได้สร้างรายการใหม่)
select pg_temp.ok((select count(*) = 1 and bool_and(check_out is not null) from public.attendance where worker_id = '30000000-0000-0000-0000-000000000009'), 'เวลาออกบันทึกในรายการเดิม ไม่สร้างรายการใหม่');

-- ---------- 11. ชื่อจริงและลายเซ็น ----------
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
update public.profiles set full_name = 'สมชาย หัวหน้า' where id = auth.uid();
select public.set_my_signature('data:image/png;base64,iVBORw0KGgo=') as sig1 \gset
select pg_temp.ok((select full_name = 'สมชาย หัวหน้า' and signature_id = :'sig1' from public.profiles where id = auth.uid()), 'แก้ชื่อและลายเซ็นของตัวเองได้');
update public.profiles set full_name = 'แอบแก้' where id = '00000000-0000-0000-0000-000000000002';
select pg_temp.ok((select full_name <> 'แอบแก้' from public.profiles where id = '00000000-0000-0000-0000-000000000002'), 'แก้โปรไฟล์คนอื่นไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.set_my_signature('javascript:alert(1)')$q$), 'ลายเซ็นต้องเป็นรูป PNG เท่านั้น');
select pg_temp.ok(pg_temp.raises($q$select public.set_my_signature('data:image/png;base64,' || encode('GIF89a not a png'::bytea, 'base64'))$q$), 'ไฟล์ที่แอบอ้างว่าเป็น PNG ถูกปฏิเสธ');
select pg_temp.ok(pg_temp.raises($q$update public.profiles set created_at = now() - interval '9 years' where id = auth.uid()$q$)
                  or (select created_at > now() - interval '1 day' from public.profiles where id = auth.uid()), 'แก้วันที่สร้างบัญชีไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
select pg_temp.ok((select count(*) from public.signatures where id = :'sig1') = 0, 'ดึงลายเซ็นของคนอื่นที่ไม่ได้อยู่ในเอกสารของตัวเองไม่ได้');
select pg_temp.ok(pg_temp.raises(format('update public.profiles set signature_id = %L where id = auth.uid()', :'sig1'))
                  or (select signature_id is null from public.profiles where id = auth.uid()), 'เอาลายเซ็นของคนอื่นมาใช้ไม่ได้');
select pg_temp.ok(pg_temp.raises($q$insert into public.signatures (user_id, png) values (auth.uid(), 'data:image/png;base64,iVBORw0KGgo=')$q$), 'เขียนตารางลายเซ็นตรงไม่ได้');
reset role;
select pg_temp.ok(not exists (select 1 from information_schema.columns where table_name = 'profiles' and column_name = 'signature_png'), 'ลายเซ็นไม่อยู่ในตาราง profiles แล้ว');

-- ---------- 12. ลบจ็อบ ----------
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.ok(pg_temp.raises($q$select public.delete_job('10000000-0000-0000-0000-000000000001', 'VT260020')$q$), 'ลบจ็อบที่มีใบคิดราคาอนุมัติแล้วไม่ได้');
select pg_temp.ok(pg_temp.raises($q$delete from public.jobs where id = '10000000-0000-0000-0000-000000000001'$q$)
                  or exists (select 1 from public.jobs where id = '10000000-0000-0000-0000-000000000001'), 'ลบตรงผ่าน API ไม่ได้ ต้องผ่าน delete_job');
select public.create_job(format('{"job_no":"DEL1","title":"ทดสอบลบ","start_date":"%s","end_date":"%s","teams":[{"name":"A","supervisor_id":"00000000-0000-0000-0000-000000000001","members":[{"full_name":"คนทดสอบ ลบ"}]}]}',
  public.bkk_today() - 3, public.bkk_today() + 3)::jsonb) as deljob \gset
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
insert into public.attendance (worker_id, team_id, check_in, check_out)
select w.id, w.team_id, (public.bkk_today() - 2 + time '08:00') at time zone 'Asia/Bangkok', (public.bkk_today() - 2 + time '17:00') at time zone 'Asia/Bangkok'
from public.workers w where w.job_id = :'deljob';
select public.approve_day(d.id) from public.day_sheets d where d.job_id = :'deljob';
select pg_temp.ok(pg_temp.raises(format('select public.delete_job(%L, %L)', :'deljob', 'DEL1')), 'หัวหน้างานลบจ็อบไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select public.approve_day(d.id) from public.day_sheets d where d.job_id = :'deljob';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select pg_temp.ok(pg_temp.raises(format('select public.delete_job(%L, %L)', :'deljob', 'ผิด')), 'พิมพ์เลขจ็อบไม่ตรง ลบไม่ได้');
select public.delete_job(:'deljob', 'DEL1');
reset role;
select pg_temp.ok((select count(*) from public.jobs where id = :'deljob') = 0
                  and (select count(*) from public.workers where job_id = :'deljob') = 0
                  and (select count(*) from public.attendance where job_id = :'deljob') = 0
                  and (select count(*) from public.cost_sheets where job_id = :'deljob') = 0, 'ลบจ็อบพร้อมข้อมูลทั้งหมด (รวมวันที่อนุมัติแล้ว)');


-- ---------- 13. ตรวจความปลอดภัยรอบ 2 ----------
-- ใบคิดราคาส่งได้ถึงเมื่อวานเท่านั้น
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
select pg_temp.ok(pg_temp.raises($q$select public.submit_cost_sheet('40000000-0000-0000-0000-000000000002')$q$), 'ส่งใบคิดราคาที่เป็นวันนี้/อนาคตไม่ได้');

-- อนุมัติแล้ว ชื่อ/ลายเซ็นติดเอกสาร เปลี่ยนโปรไฟล์ทีหลังเอกสารไม่เปลี่ยน
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.create_job(format('{"job_no":"SIG1","title":"ทดสอบลายเซ็น","start_date":"%s","end_date":"%s","teams":[{"name":"A","supervisor_id":"00000000-0000-0000-0000-000000000001","members":[{"full_name":"คนทดสอบ ลายเซ็น"}]}]}',
  public.bkk_today() - 3, public.bkk_today() + 3)::jsonb) as sigjob \gset
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
insert into public.attendance (worker_id, team_id, check_in, check_out)
select w.id, w.team_id, (public.bkk_today() - 2 + time '08:00') at time zone 'Asia/Bangkok', (public.bkk_today() - 2 + time '17:00') at time zone 'Asia/Bangkok'
from public.workers w where w.job_id = :'sigjob';
select id as sigsheet from public.day_sheets where job_id = :'sigjob' \gset
select public.approve_day(:'sigsheet');
select pg_temp.ok(pg_temp.raises(format($q$update public.attendance set check_out = check_out - interval '1 hour' where job_id = %L$q$, :'sigjob')), 'หัวหน้างานแก้เวลาหลังอนุมัติแล้วไม่ได้');
update public.profiles set full_name = 'เปลี่ยนชื่อทีหลัง' where id = auth.uid();
select public.set_my_signature('data:image/png;base64,iVBORw0KGgoA') as sig2 \gset
select pg_temp.ok((select supervisor_sig_id = :'sig1' and supervisor_name = 'สมชาย หัวหน้า' from public.day_sheets where id = :'sigsheet'),
  'เอกสารที่อนุมัติแล้วใช้ชื่อและลายเซ็นตอนอนุมัติ');
select pg_temp.ok((select count(*) from public.signatures where id in (:'sig1', :'sig2')) = 2, 'ลายเซ็นเก่าที่ติดเอกสารยังอยู่');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select pg_temp.ok((select count(*) from public.signatures where id = :'sig1') = 1, 'Planner เห็นลายเซ็นในเอกสารที่ตัวเองดูได้');
select pg_temp.ok((select count(*) from public.signatures where id = :'sig2') = 0, 'Planner ไม่เห็นลายเซ็นปัจจุบันที่ยังไม่ได้ใช้ในเอกสาร');
update public.attendance set check_out = check_out - interval '1 hour', note = 'Planner ตรวจแล้วแก้' where job_id = :'sigjob';
select pg_temp.ok((select edit_count = 2 and source = 'supervisor' from public.attendance where job_id = :'sigjob'), 'Planner แก้เวลาได้หลังหัวหน้าอนุมัติ และนับเป็นแก้ไขครั้งที่ 2');
select public.approve_day(:'sigsheet');
select pg_temp.ok((select planner_name = 'แพลนเนอร์' and planner_sig_id is null from public.day_sheets where id = :'sigsheet'), 'Planner ที่ไม่มีลายเซ็น บันทึกแค่ชื่อ');
select pg_temp.ok(pg_temp.raises(format($q$update public.attendance set note = 'x' where job_id = %L$q$, :'sigjob')), 'Planner อนุมัติแล้ว แก้ไม่ได้');
select public.set_my_signature('data:image/png;base64,iVBORw0KGgo=') as plsig \gset
select pg_temp.ok((select planner_sig_id = :'plsig' from public.day_sheets where id = :'sigsheet'), 'อัปโหลดลายเซ็นทีหลัง เติมลงเอกสารที่อนุมัติไปแล้ว');

-- วันที่เปิดลงเวลาแต่ไม่มีใครมา (ใบว่าง) ไม่ขวางการส่งใบคิดราคา
reset role;
insert into public.day_sheets (job_id, team_id, work_date, opened_at)
select :'sigjob', t.id, public.bkk_today() - 1, now() - interval '1 day' from public.teams t where t.job_id = :'sigjob';
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
insert into public.worker_rates (worker_id, day_rate) select w.id, 900 from public.workers w where w.job_id = :'sigjob';
update public.jobs set terms_confirmed_at = now() where id = :'sigjob';
select pg_temp.ok((public.cost_preview(:'sigjob', public.bkk_today() - 3, public.bkk_today() - 1) ->> 'pending_days')::int = 0, 'ใบว่างไม่นับเป็นวันรออนุมัติ');
select id as sigcost from public.cost_sheets where job_id = :'sigjob' and status = 'draft' \gset
select public.submit_cost_sheet(:'sigcost');
select pg_temp.ok((select status = 'submitted' and period_to = public.bkk_today() - 1 from public.cost_sheets where id = :'sigcost'), 'ส่งใบคิดราคาได้แม้มีวันว่าง (ตัดถึงเมื่อวานอัตโนมัติ)');

-- สิทธิ์ระดับทีม: หัวหน้าทีม B ในจ็อบเดียวกัน ยุ่งกับทีม A ไม่ได้
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into public.teams (id, job_id, name, supervisor_id) values
  ('20000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001', 'ทีม B', '00000000-0000-0000-0000-000000000002');
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
select pg_temp.ok((select count(*) from public.daily_pins p join public.workers w on w.id = p.worker_id
                   where w.team_id = '20000000-0000-0000-0000-000000000001') = 0, 'หัวหน้าทีม B ดู PIN ทีม A ไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.generate_pins('20000000-0000-0000-0000-000000000001')$q$), 'หัวหน้าทีม B สร้าง PIN ทีม A ไม่ได้');
select pg_temp.ok(pg_temp.raises($q$insert into public.attendance (worker_id, team_id, check_in) values ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', now())$q$),
  'หัวหน้าทีม B ลงเวลาแทนทีม A ไม่ได้');
select pg_temp.ok(pg_temp.raises($q$select public.rotate_team_qr('20000000-0000-0000-0000-000000000001')$q$), 'หัวหน้าทีม B ออก QR ใหม่ให้ทีม A ไม่ได้');
select pg_temp.ok((select count(*) from public.jobs where id = '10000000-0000-0000-0000-000000000001') = 1, 'หัวหน้าทีม B ยังเห็นจ็อบ');

-- กรอก PIN ผิดรัวๆ ทั้งทีม → พักทั้งทีม
reset role;
insert into public.kiosk_failures (team_id) select '20000000-0000-0000-0000-000000000001' from generate_series(1, 30);
set role anon; select set_config('request.jwt.claims', '{"role":"anon"}', false);
select pg_temp.ok(public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000002', :'pin2') ->> 'error' like '%รอ 10 นาที%', 'กรอกผิดเกินกำหนดทั้งทีม ถูกพักชั่วคราว');
reset role; delete from public.kiosk_failures;
set role anon;
select pg_temp.ok((public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000002', :'pin2') ->> 'ok')::boolean, 'พ้นช่วงพัก กรอกถูกใช้ได้ตามปกติ');
select pg_temp.ok(pg_temp.raises('select * from public.kiosk_failures'), 'anon อ่านบันทึกการกรอกผิดไม่ได้');
select pg_temp.ok(pg_temp.raises('select * from public.signatures'), 'anon อ่านลายเซ็นไม่ได้');

-- บัญชีใหม่ไม่รับชื่อที่ส่งมาเอง
reset role;
insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000ee', 'fake@test.local', '{"full_name":"สมชาย หัวหน้า"}');
select pg_temp.ok((select full_name = '' and role is null from public.profiles where id = '00000000-0000-0000-0000-0000000000ee'), 'สมัครเองตั้งชื่อเลียนแบบพนักงานไม่ได้');

-- QR มีอายุ 1 ชั่วโมง และออกได้เฉพาะหัวหน้าของทีม
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok((public.issue_kiosk_qr('20000000-0000-0000-0000-000000000001', 'in') ->> 'expires_at')::timestamptz between now() + interval '59 minutes' and now() + interval '61 minutes', 'หัวหน้าออก QR เข้างาน อายุ 1 ชั่วโมง');
select pg_temp.as_user('00000000-0000-0000-0000-000000000002');
select pg_temp.ok(pg_temp.raises($q$select public.issue_kiosk_qr('20000000-0000-0000-0000-000000000001', 'in')$q$), 'หัวหน้าทีมอื่นออก QR ให้ทีม A ไม่ได้');
reset role; set role anon;
select pg_temp.ok(pg_temp.raises($q$select public.issue_kiosk_qr('20000000-0000-0000-0000-000000000001', 'in')$q$), 'anon ออก QR ไม่ได้');
select pg_temp.ok(pg_temp.raises('select * from public.kiosk_tokens'), 'anon อ่านรายการ QR ไม่ได้');
reset role; update public.kiosk_tokens set expires_at = now() - interval '1 minute' where token = :'tok';
set role anon;
select pg_temp.ok(public.kiosk_team(:'tok') ->> 'error' like 'QR นี้หมดอายุแล้ว%', 'QR เกิน 1 ชั่วโมง ใช้ไม่ได้');
select pg_temp.ok((public.kiosk_status(:'tok', '30000000-0000-0000-0000-000000000002', :'pin2') ->> 'ok')::boolean = false, 'QR หมดอายุ ใส่ PIN ไม่ได้');

-- Manager ใหญ่สุด: สร้างจ็อบ ลงเวลา อนุมัติแทนหัวหน้าและ Planner
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-0000000000d1');
select public.create_job(format('{"job_no":"MGR1","title":"ทดสอบ Manager","start_date":"%s","end_date":"%s","teams":[{"name":"A","supervisor_id":"00000000-0000-0000-0000-000000000001","members":[{"full_name":"คนทดสอบ ผู้จัดการ"}]}]}',
  public.bkk_today() - 3, public.bkk_today() + 3)::jsonb) as mgrjob \gset
insert into public.attendance (worker_id, team_id, check_in, check_out)
select w.id, w.team_id, (public.bkk_today() - 2 + time '08:00') at time zone 'Asia/Bangkok', (public.bkk_today() - 2 + time '17:00') at time zone 'Asia/Bangkok'
from public.workers w where w.job_id = :'mgrjob';
select id as mgrsheet from public.day_sheets where job_id = :'mgrjob' \gset
select public.approve_day(:'mgrsheet');
select public.approve_day(:'mgrsheet');
select pg_temp.ok((select supervisor_approved_by = '00000000-0000-0000-0000-0000000000d1' and planner_approved_by = '00000000-0000-0000-0000-0000000000d1'
                   from public.day_sheets where id = :'mgrsheet'), 'Manager อนุมัติแทนหัวหน้างานและ Planner ได้');
select pg_temp.ok(pg_temp.raises(format('select public.approve_day(%L)', :'mgrsheet')), 'อนุมัติซ้ำใบที่ครบแล้วไม่ได้');
update public.profiles set role = 'planner' where id = '00000000-0000-0000-0000-0000000000ee';
select pg_temp.ok((select role = 'planner' from public.profiles where id = '00000000-0000-0000-0000-0000000000ee'), 'Manager กำหนดตำแหน่งผู้ใช้ได้');
select pg_temp.ok(pg_temp.raises($q$update public.profiles set role = 'admin' where id = auth.uid()$q$)
                  or (select role = 'manager' from public.profiles where id = auth.uid()), 'Manager เปลี่ยนตำแหน่งตัวเองไม่ได้');
reset role;



-- ---------- 14. ลงเวลาผ่าน QR บนมือถือที่ล็อกอินเป็นพนักงาน = ผู้รับเหมาลงเอง ----------
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.create_job(format('{"job_no":"KIOSK1","title":"ทดสอบ QR","start_date":"%s","end_date":"%s","teams":[{"name":"A","supervisor_id":"00000000-0000-0000-0000-000000000001","members":[{"full_name":"คนทดสอบ คิวอาร์"}]}]}',
  public.bkk_today() - 1, public.bkk_today() + 3)::jsonb) as kjob \gset
select id as kteam from public.teams where job_id = :'kjob' \gset
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select public.open_day(:'kteam');
reset role;
insert into public.kiosk_tokens (team_id, kind, expires_at) values (:'kteam', 'in', now() + interval '1 hour') returning token as ktok \gset
select w.id as kw, p.pin as kpin from public.workers w join public.daily_pins p on p.worker_id = w.id where w.job_id = :'kjob' \gset
set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
select pg_temp.ok((public.kiosk_clock(:'ktok', :'kw', :'kpin', 'in') ->> 'ok')::boolean, 'สแกน QR เข้างานบนมือถือที่หัวหน้าล็อกอินค้างไว้ได้');
reset role;
select pg_temp.ok((select source = 'self' and edit_count = 0 and updated_by is null from public.attendance where worker_id = :'kw'),
  'บันทึกเป็นผู้รับเหมาลงเอง ไม่ใช่หัวหน้าแก้ (ไม่ขึ้นสีแดง)');


-- ---------- 15. พักเที่ยงต่อจ็อบ ----------
reset role; set role authenticated; select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select public.create_job(format('{"job_no":"LUNCH1","title":"ทดสอบพักเที่ยง","start_date":"%s","end_date":"%s","teams":[{"name":"A","supervisor_id":"00000000-0000-0000-0000-000000000001","members":[{"full_name":"คนทดสอบ เที่ยง"}]}]}',
  public.bkk_today() - 3, public.bkk_today() + 3)::jsonb) as ljob \gset
select pg_temp.as_user('00000000-0000-0000-0000-000000000001');
insert into public.attendance (worker_id, team_id, check_in, check_out)
select w.id, w.team_id, (public.bkk_today() - 2 + time '08:00') at time zone 'Asia/Bangkok', (public.bkk_today() - 2 + time '17:00') at time zone 'Asia/Bangkok'
from public.workers w where w.job_id = :'ljob';
select pg_temp.ok((select normal_h = 8 and ot_h = 0 from public.v_attendance_hours where job_id = :'ljob'), 'มีพักเที่ยง (ค่าเริ่มต้น): 08:00–17:00 = ปกติ 8 ชม.');
select pg_temp.ok(pg_temp.raises(format('update public.jobs set lunch_break = false where id = %L', :'ljob'))
                  or (select lunch_break from public.jobs where id = :'ljob'), 'หัวหน้างานเปลี่ยนพักเที่ยงไม่ได้');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000c1');
update public.jobs set lunch_break = false, evening_break = false where id = :'ljob';
select pg_temp.ok((select normal_h = 8 and ot_h = 1 from public.v_attendance_hours where job_id = :'ljob'), 'ไม่พักเที่ยง: 08:00–17:00 = ปกติ 8 + OT 1 ชม.');
select pg_temp.ok((select terms_confirmed_by = '00000000-0000-0000-0000-0000000000c1' from public.jobs where id = :'ljob'), 'เปลี่ยนพักเที่ยง = Purchase ยืนยันเงื่อนไขใหม่');
select pg_temp.ok((public.cost_preview(:'ljob', public.bkk_today() - 3, public.bkk_today()) -> 'job' ->> 'lunch_break')::boolean = false, 'ใบคิดราคาบันทึกเงื่อนไขพักเที่ยง');

\echo ALL TESTS PASSED
