-- =====================================================================
-- 0014: ลงเวลาผ่าน QR บนมือถือที่ล็อกอินเป็นพนักงานค้างไว้ → ยังนับเป็นผู้รับเหมาลงเอง
--       (เดิมระบบบันทึกว่าพนักงานคนนั้นเป็นคนแก้เวลา และขึ้นสีแดง)
-- รันใน Supabase SQL Editor ต่อจาก 0013 (รันซ้ำได้)
-- =====================================================================

create or replace function public.kiosk_clock(p_token text, p_worker uuid, p_pin text, p_action text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb; a record; v_now timestamptz := now(); v_sheet record;
begin
  -- ลงเวลาผ่าน QR = ผู้รับเหมาลงเอง เสมอ แม้มือถือเครื่องนั้นจะล็อกอินเป็นพนักงานค้างไว้
  -- (ไม่งั้นระบบจะบันทึกว่าพนักงานคนนั้นแก้เวลา และขึ้นสีแดง "แก้ไขครั้งที่")
  perform set_config('request.jwt.claims', '', true);
  r := public.kiosk_check_pin(p_token, p_worker, p_pin);
  if not (r ->> 'ok')::boolean then return r; end if;
  if p_action is distinct from r ->> 'kind' then
    return jsonb_build_object('ok', false, 'error',
      case when r ->> 'kind' = 'in' then 'QR นี้ใช้ลงเวลาเข้างานเท่านั้น — ตอนเลิกงานให้สแกน QR ออกงาน'
           else 'QR นี้ใช้ลงเวลาออกงานเท่านั้น' end);
  end if;

  select d.supervisor_approved_at, d.planner_approved_at into v_sheet from public.day_sheets d
  where d.team_id = (r ->> 'team_id')::uuid and d.work_date = (r ->> 'today')::date;
  if v_sheet.supervisor_approved_at is not null or v_sheet.planner_approved_at is not null then
    return jsonb_build_object('ok', false, 'error', 'ใบลงเวลาวันนี้ถูกอนุมัติแล้ว กรุณาติดต่อหัวหน้างาน');
  end if;

  select x.id, x.check_in, x.check_out into a from public.attendance x
  where x.worker_id = p_worker and x.work_date = (r ->> 'today')::date for update;

  if p_action = 'in' then
    if (r ->> 'overnight')::boolean then
      return jsonb_build_object('ok', false, 'error', 'ยังไม่ได้ลงเวลาออกของเมื่อวาน กรุณาลงเวลาออกก่อน');
    end if;
    if found then return jsonb_build_object('ok', false, 'error', 'วันนี้ลงเวลาเข้างานไปแล้ว'); end if;
    insert into public.attendance (worker_id, job_id, team_id, work_date, check_in, source)
    values (p_worker, (r ->> 'job_id')::uuid, (r ->> 'team_id')::uuid, (r ->> 'today')::date, v_now, 'self');
  elsif p_action = 'out' then
    if not found then return jsonb_build_object('ok', false, 'error', 'ยังไม่ได้ลงเวลาเข้างาน'); end if;
    if a.check_out is not null then return jsonb_build_object('ok', false, 'error', 'วันนี้ลงเวลาออกไปแล้ว'); end if;
    if v_now < a.check_in + interval '1 minute' then
      return jsonb_build_object('ok', false, 'error', 'เพิ่งลงเวลาเข้า กรุณารอสักครู่');
    end if;
    update public.attendance set check_out = v_now where id = a.id;
  else
    return jsonb_build_object('ok', false, 'error', 'คำสั่งไม่ถูกต้อง');
  end if;
  return jsonb_build_object('ok', true, 'action', p_action, 'at', v_now, 'name', r ->> 'name');
end;
$$;

revoke execute on function public.kiosk_clock(text, uuid, text, text) from public;
grant execute on function public.kiosk_clock(text, uuid, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
