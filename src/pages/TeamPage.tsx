import { ArrowLeft, CalendarClock, Eye, EyeOff, Lock, Pencil, RefreshCw, UserMinus, UserPlus } from 'lucide-react'
import { useState } from 'react'
import { Link, useParams } from 'react-router'
import { Forbidden } from '../components/Guards'
import { Badge, Button, Card, CardHeader, Empty, ErrorBox, Field, Input, Modal, PageHeader, Select, Spinner, useToast } from '../components/ui'
import { useAuth } from '../lib/auth'
import { fmtDateLong, fmtOut, fmtTime, todayYmd } from '../lib/format'
import { must, useLoad } from '../lib/hooks'
import { supabase } from '../lib/supabase'
import type { Job, Team, Worker } from '../lib/types'

type Pin = { worker_id: string; pin: string; failed_attempts: number }
type Att = { id: string; worker_id: string; check_in: string; check_out: string | null }

export function kioskUrl(token: string) {
  return `${window.location.origin}${import.meta.env.BASE_URL}c/${token}`
}

export default function TeamPage() {
  const { id = '' } = useParams()
  const { is, profile } = useAuth()
  const toast = useToast()
  const [showPins, setShowPins] = useState(false)
  const [edit, setEdit] = useState<Partial<Worker> | null>(null)
  const [busy, setBusy] = useState(false)

  const { data, error, loading, reload } = useLoad(async () => {
    const team = must(await supabase.from('teams').select('*').eq('id', id).single()) as Team
    const today = todayYmd()
    const [job, teams, workers, pins, att, sheet, settings] = await Promise.all([
      supabase.from('jobs').select('*').eq('id', team.job_id).single(),
      supabase.from('teams').select('id, name, supervisor_id').eq('job_id', team.job_id).order('name'),
      supabase.from('workers').select('*').eq('team_id', id).order('active', { ascending: false }).order('full_name'),
      supabase.from('daily_pins').select('worker_id, pin, failed_attempts').eq('work_date', today),
      supabase.from('attendance').select('id, worker_id, check_in, check_out').eq('team_id', id).eq('work_date', today),
      supabase.from('day_sheets').select('id').eq('team_id', id).eq('work_date', today).maybeSingle(),
      supabase.from('app_settings').select('pin_max_attempts').eq('id', 1).maybeSingle(),
    ])
    return {
      team,
      job: must(job) as Job,
      teams: must(teams) as { id: string; name: string; supervisor_id: string | null }[],
      workers: must(workers) as Worker[],
      pins: must(pins) as Pin[],
      att: must(att) as Att[],
      sheetId: (must(sheet) as { id: string } | null)?.id ?? null,
      maxAttempts: (must(settings) as { pin_max_attempts: number } | null)?.pin_max_attempts ?? 5,
    }
  }, [id])


  if (loading && !data) return <Spinner />
  if (error || !data) return <ErrorBox message={error ?? 'ไม่พบทีม'} onRetry={reload} />
  const { team, job, teams, workers, pins, att, sheetId, maxAttempts } = data
  if (!(is('admin') || team.supervisor_id === profile?.id)) return <Forbidden />
  // ย้ายคนได้เฉพาะทีมที่ตัวเองดูแล (เซิร์ฟเวอร์บังคับเหมือนกัน)
  const myTeams = teams.filter((t) => is('admin') || t.supervisor_id === profile?.id)

  const pinOf = (w: string) => pins.find((p) => p.worker_id === w)
  const attOf = (w: string) => att.find((a) => a.worker_id === w)

  async function genPins(worker?: string) {
    setBusy(true)
    const { data: n, error } = await supabase.rpc('generate_pins', { p_team: id, p_worker: worker ?? null })
    setBusy(false)
    if (error) return toast.err(error)
    toast.ok(worker ? 'สุ่ม PIN ใหม่และปลดล็อกแล้ว' : `สร้าง PIN ให้ ${n} คน`)
    setShowPins(true)
    reload()
  }

  async function saveWorker() {
    if (!edit?.full_name?.trim()) return toast.err('กรุณากรอกชื่อ')
    setBusy(true)
    const row = { full_name: edit.full_name.trim(), position: edit.position?.trim() || 'T/C', team_id: edit.team_id || id }
    const res = edit.id
      ? await supabase.from('workers').update(row).eq('id', edit.id)
      : await supabase.from('workers').insert({ ...row, job_id: team.job_id })
    setBusy(false)
    if (res.error) return toast.err(res.error)
    toast.ok(edit.id ? 'บันทึกแล้ว' : 'เพิ่มคนแล้ว')
    setEdit(null)
    reload()
  }

  async function setActive(w: Worker, v: boolean) {
    if (!v && !confirm(`นำ ${w.full_name} ออกจากทีม? (ประวัติการลงเวลายังอยู่)`)) return
    const { error } = await supabase.from('workers').update({ active: v }).eq('id', w.id)
    if (error) return toast.err(error)
    toast.ok(v ? 'นำกลับเข้าทีมแล้ว' : 'นำออกจากทีมแล้ว')
    reload()
  }

  return (
    <>
      <PageHeader
        back={
          <Link to={`/jobs/${job.id}`} className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800">
            <ArrowLeft className="size-4" /> {job.job_no} · {job.title}
          </Link>
        }
        title={team.name}
        sub={fmtDateLong(todayYmd())}
        right={
          sheetId && (
            <Link to={`/days/${sheetId}`}>
              <Button variant="secondary">ใบลงเวลาวันนี้</Button>
            </Link>
          )
        }
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader
            title="ลูกทีมและ PIN วันนี้"
            sub="PIN สุ่มใหม่ทุกวัน บอกผู้รับเหมาเป็นรายคน อย่าส่งในกลุ่มแชท"
            right={
              <>
                <Button variant="ghost" size="sm" onClick={() => setShowPins(!showPins)}>
                  {showPins ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
                  {showPins ? 'ซ่อน PIN' : 'แสดง PIN'}
                </Button>
                <Link to={`/today?team=${team.id}`}>
                  <Button size="sm">
                    <CalendarClock className="size-4" /> เปิดลงเวลา / PIN วันนี้
                  </Button>
                </Link>
              </>
            }
          />
          {workers.length === 0 ? (
            <Empty title="ยังไม่มีลูกทีม" />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 text-left text-xs font-medium text-slate-500">
                  <tr>
                    <th className="px-5 py-2.5">ชื่อ</th>
                    <th className="px-3 py-2.5 text-center">PIN</th>
                    <th className="px-3 py-2.5 text-center">เข้า</th>
                    <th className="px-3 py-2.5 text-center">ออก</th>
                    <th className="px-5 py-2.5 text-right" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {workers.map((w) => {
                    const p = pinOf(w.id)
                    const a = attOf(w.id)
                    const locked = p && p.failed_attempts >= maxAttempts
                    return (
                      <tr key={w.id} className={w.active ? '' : 'bg-slate-50 text-slate-400'}>
                        <td className="px-5 py-3">
                          <p className="font-medium text-slate-900">{w.full_name}</p>
                          <p className="text-xs text-slate-500">{w.position}{!w.active && ' · ออกจากทีมแล้ว'}</p>
                        </td>
                        <td className="px-3 py-3 text-center">
                          {!w.active ? null : p ? (
                            <span className="inline-flex items-center gap-1">
                              <span className="tabular rounded-lg bg-slate-100 px-2.5 py-1 font-mono text-base font-semibold tracking-widest text-slate-900">
                                {showPins ? p.pin : '••••'}
                              </span>
                              {locked && (
                                <Badge tone="red">
                                  <Lock className="size-3" /> ล็อก
                                </Badge>
                              )}
                            </span>
                          ) : (
                            <span className="text-xs text-slate-400">ยังไม่มี</span>
                          )}
                        </td>
                        <td className="tabular px-3 py-3 text-center">{a ? fmtTime(a.check_in) : '–'}</td>
                        <td className="tabular px-3 py-3 text-center">{a?.check_out ? fmtOut(a.check_in, a.check_out) : a ? <Badge tone="green">อยู่</Badge> : '–'}</td>
                        <td className="px-5 py-3">
                          <div className="flex justify-end gap-1">
                            {w.active && p && (
                              <button onClick={() => genPins(w.id)} className="rounded-lg p-2 text-slate-500 hover:bg-slate-100" title="สุ่ม PIN ใหม่ / ปลดล็อก">
                                <RefreshCw className="size-4" />
                              </button>
                            )}
                            <button onClick={() => setEdit(w)} className="rounded-lg p-2 text-slate-500 hover:bg-slate-100" title="แก้ไข / ย้ายทีม">
                              <Pencil className="size-4" />
                            </button>
                            <button onClick={() => setActive(w, !w.active)} className="rounded-lg p-2 text-slate-500 hover:bg-slate-100" title={w.active ? 'นำออกจากทีม' : 'นำกลับเข้าทีม'}>
                              {w.active ? <UserMinus className="size-4" /> : <UserPlus className="size-4" />}
                            </button>
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
          <div className="border-t border-slate-100 px-5 py-3">
            <Button variant="secondary" size="sm" onClick={() => setEdit({ full_name: '', position: 'T/C', team_id: id })}>
              <UserPlus className="size-4" /> เพิ่มคนในทีม
            </Button>
          </div>
        </Card>

        <Card className="h-fit">
          <CardHeader title="ลงเวลาวันนี้" sub="เปิดลงเวลา, PIN ประจำวัน และ QR เข้างาน/ออกงาน อยู่ที่หน้าลงเวลาวันนี้" />
          <div className="space-y-3 p-5">
            <Link to={`/today?team=${team.id}`} className="block">
              <Button className="w-full">
                <CalendarClock className="size-4" /> ไปหน้าลงเวลาวันนี้
              </Button>
            </Link>
          </div>
        </Card>
      </div>

      <Modal
        open={Boolean(edit)}
        onClose={() => setEdit(null)}
        title={edit?.id ? 'แก้ไขข้อมูล' : 'เพิ่มคนในทีม'}
        footer={
          <>
            <Button variant="secondary" onClick={() => setEdit(null)}>
              ยกเลิก
            </Button>
            <Button onClick={saveWorker} loading={busy}>
              บันทึก
            </Button>
          </>
        }
      >
        {edit && (
          <div className="space-y-4">
            <Field label="ชื่อ-นามสกุล">
              <Input autoFocus maxLength={120} value={edit.full_name ?? ''} onChange={(e) => setEdit({ ...edit, full_name: e.target.value })} />
            </Field>
            <Field label="ตำแหน่ง">
              <Input maxLength={40} value={edit.position ?? ''} onChange={(e) => setEdit({ ...edit, position: e.target.value })} />
            </Field>
            {myTeams.length > 1 && (
              <Field label="ทีม" hint="ย้ายไปทีมอื่นของคุณในจ็อบเดียวกันได้ เวลาที่ลงไปแล้วยังอยู่กับทีมเดิม">
                <Select value={edit.team_id ?? id} onChange={(e) => setEdit({ ...edit, team_id: e.target.value })}>
                  {myTeams.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.name}
                    </option>
                  ))}
                </Select>
              </Field>
            )}
          </div>
        )}
      </Modal>
    </>
  )
}
