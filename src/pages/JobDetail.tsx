import { ArrowLeft, CalendarDays, ChevronRight, FileSpreadsheet, Pencil, Plus, Trash2, UserRound, Users } from 'lucide-react'
import { useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router'
import { JobBudgetCard } from '../components/Budget'
import { JobRates } from '../components/JobRates'
import { TermsStatus } from '../components/TermsStatus'
import { Badge, Button, Card, CardHeader, Empty, ErrorBox, Field, Input, Modal, PageHeader, Spinner, Tabs, useToast } from '../components/ui'
import { useAuth } from '../lib/auth'
import { fmtDate, fmtDateLong, fmtMoney, todayYmd } from '../lib/format'
import { must, useLoad } from '../lib/hooks'
import { CostBadge, DayBadge } from '../lib/status'
import { supabase } from '../lib/supabase'
import type { CostSheet, DaySheet, Job } from '../lib/types'

type TeamRow = {
  id: string
  name: string
  supervisor_id: string | null
  supervisor: { full_name: string; email: string } | null
  workers: { id: string; active: boolean }[]
}

export default function JobDetail() {
  const { id = '' } = useParams()
  const { is, profile } = useAuth()
  const nav = useNavigate()
  const toast = useToast()
  const [params] = useSearchParams()
  const [tab, setTab] = useState<'teams' | 'days' | 'cost' | 'terms'>(() =>
    params.get('tab') === 'terms' || (is('purchase') && !is('admin')) ? 'terms' : 'teams',
  )
  const [newCost, setNewCost] = useState<{ from: string; to: string } | null>(null)
  const [busy, setBusy] = useState(false)
  const [delText, setDelText] = useState<string | null>(null)

  const { data, error, loading, reload } = useLoad(async () => {
    const today = todayYmd()
    const [job, teams, days, costs, att] = await Promise.all([
      supabase.from('jobs').select('*').eq('id', id).single(),
      supabase.from('teams').select('id, name, supervisor_id, supervisor:profiles(full_name, email), workers(id, active)').eq('job_id', id).order('name'),
      supabase.from('v_day_sheets').select('*').eq('job_id', id).order('work_date', { ascending: false }).order('team_name'),
      supabase.from('cost_sheets').select('id, job_id, period_from, period_to, status, revision, reject_reason, net_total, subtotal, submitted_at, approved_at, created_at').eq('job_id', id).order('created_at', { ascending: false }),
      supabase.from('attendance').select('team_id, check_out').eq('job_id', id).eq('work_date', today),
    ])
    return {
      job: must(job) as Job,
      teams: must(teams) as unknown as TeamRow[],
      days: must(days) as DaySheet[],
      costs: must(costs) as CostSheet[],
      today: must(att) as { team_id: string; check_out: string | null }[],
    }
  }, [id])

  if (loading && !data) return <Spinner />
  if (error || !data) return <ErrorBox message={error ?? 'ไม่พบจ็อบ'} onRetry={reload} />
  const { job, teams, days, costs, today } = data
  const canPrice = is('purchase', 'admin')

  async function toggleStatus() {
    setBusy(true)
    const { error } = await supabase.from('jobs').update({ status: job.status === 'active' ? 'closed' : 'active' }).eq('id', id)
    setBusy(false)
    if (error) return toast.err(error)
    toast.ok(job.status === 'active' ? 'ปิดจ็อบแล้ว' : 'เปิดจ็อบแล้ว')
    reload()
  }

  async function deleteJob() {
    setBusy(true)
    const { error } = await supabase.rpc('delete_job', { p_job: id, p_confirm: delText })
    setBusy(false)
    if (error) return toast.err(error)
    toast.ok(`ลบจ็อบ ${job.job_no} แล้ว`)
    nav('/jobs', { replace: true })
  }

  async function saveTerms(patch: Partial<Job>) {
    const { error } = await supabase.from('jobs').update(patch).eq('id', id)
    if (error) return toast.err(error)
    toast.ok('บันทึกเงื่อนไขแล้ว')
    reload()
  }

  async function createCost() {
    if (!newCost) return
    setBusy(true)
    const { data: row, error } = await supabase
      .from('cost_sheets')
      .insert({ job_id: id, period_from: newCost.from, period_to: newCost.to })
      .select('id')
      .single()
    setBusy(false)
    if (error) return toast.err(error)
    nav(`/cost/${row.id}`)
  }

  const myTeams = teams.filter((t) => is('admin') || t.supervisor_id === profile?.id)

  return (
    <>
      <PageHeader
        back={
          <Link to="/jobs" className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800">
            <ArrowLeft className="size-4" /> จ็อบทั้งหมด
          </Link>
        }
        title={
          <span className="flex flex-wrap items-center gap-3">
            <span className="font-mono text-brand-700">{job.job_no}</span>
            <span>{job.title}</span>
            {job.status === 'closed' && <Badge>ปิดแล้ว</Badge>}
          </span>
        }
        sub={
          <span className="flex flex-wrap gap-x-4">
            {job.contractor_name && <span>{job.contractor_name}</span>}
            <span>
              {fmtDate(job.start_date)} – {fmtDate(job.end_date)}
            </span>
            {job.location && <span>{job.location}</span>}
          </span>
        }
        right={
          is('admin') && (
            <>
              <Button variant="ghost" className="text-rose-600 hover:bg-rose-50" onClick={() => setDelText('')}>
                <Trash2 className="size-4" /> ลบจ็อบ
              </Button>
              <Button variant="secondary" onClick={toggleStatus} loading={busy}>
                {job.status === 'active' ? 'ปิดจ็อบ' : 'เปิดจ็อบอีกครั้ง'}
              </Button>
              <Link to={`/jobs/${id}/edit`}>
                <Button variant="secondary">
                  <Pencil className="size-4" /> แก้ไข
                </Button>
              </Link>
            </>
          )
        }
      />

      <JobBudgetCard jobId={id} />

      <Tabs
        value={tab}
        onChange={setTab}
        items={[
          { value: 'teams', label: `ทีม (${teams.length})` },
          { value: 'days', label: `ใบลงเวลารายวัน (${days.length})` },
          { value: 'cost', label: `ใบคิดราคา (${costs.length})` },
          { value: 'terms', label: canPrice && !job.terms_confirmed_at ? 'ค่าแรงและเงื่อนไข ⚠️' : 'ค่าแรงและเงื่อนไข' },
        ]}
      />

      {tab === 'teams' && (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {teams.map((t) => {
            const active = t.workers.filter((w) => w.active).length
            const inNow = today.filter((a) => a.team_id === t.id && !a.check_out).length
            const came = today.filter((a) => a.team_id === t.id).length
            const mine = myTeams.some((m) => m.id === t.id)
            return (
              <Card key={t.id} className="flex flex-col p-5">
                <div className="flex items-start justify-between">
                  <div>
                    <p className="text-lg font-semibold text-slate-900">{t.name}</p>
                    <p className="mt-0.5 flex items-center gap-1.5 text-sm text-slate-500">
                      <UserRound className="size-4" /> {t.supervisor?.full_name || t.supervisor?.email || 'ยังไม่กำหนดหัวหน้างาน'}
                    </p>
                  </div>
                  <Badge tone="blue">
                    <Users className="size-3" /> {active} คน
                  </Badge>
                </div>
                <div className="mt-4 grid grid-cols-2 gap-2 text-center">
                  <div className="rounded-xl bg-emerald-50 p-2.5">
                    <p className="tabular text-xl font-semibold text-emerald-700">{inNow}</p>
                    <p className="text-xs text-emerald-700">อยู่หน้างานตอนนี้</p>
                  </div>
                  <div className="rounded-xl bg-slate-50 p-2.5">
                    <p className="tabular text-xl font-semibold text-slate-700">{came}</p>
                    <p className="text-xs text-slate-500">มาวันนี้</p>
                  </div>
                </div>
                <div className="mt-4 flex gap-2">
                  {mine && (
                    <Link to={`/today?team=${t.id}`} className="flex-1">
                      <Button className="w-full">ลงเวลาวันนี้</Button>
                    </Link>
                  )}
                  {mine && (
                    <Link to={`/teams/${t.id}`}>
                      <Button variant="secondary" title="จัดการรายชื่อ">
                        <Users className="size-4" />
                      </Button>
                    </Link>
                  )}
                </div>
              </Card>
            )
          })}
          {teams.length === 0 && (
            <Card className="md:col-span-2 xl:col-span-3">
              <Empty icon={<Users className="size-6" />} title="ยังไม่มีทีม" />
            </Card>
          )}
        </div>
      )}

      {tab === 'days' && (
        <Card>
          {days.length === 0 ? (
            <Empty icon={<CalendarDays className="size-6" />} title="ยังไม่มีการลงเวลา" sub="ใบลงเวลารายวันจะถูกสร้างอัตโนมัติเมื่อมีคนเช็คอิน" />
          ) : (
            <ul className="divide-y divide-slate-100">
              {days.map((d) => (
                <li key={d.id}>
                  <Link to={`/days/${d.id}`} className="flex items-center gap-4 px-5 py-3.5 hover:bg-slate-50">
                    <div className="w-40 shrink-0">
                      <p className="font-medium text-slate-900">{fmtDateLong(d.work_date)}</p>
                      <p className="text-sm text-slate-500">{d.team_name}</p>
                    </div>
                    <p className="flex-1 text-sm text-slate-600">{d.people} คน</p>
                    <DayBadge d={d} />
                    <ChevronRight className="size-4 text-slate-400" />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === 'cost' && (
        <Card>
          <CardHeader
            title="ใบคิดราคา"
            sub="รวมชั่วโมงจากใบลงเวลาที่อนุมัติครบแล้ว × ค่าแรง"
            right={
              canPrice && (
                <Button
                  size="sm"
                  onClick={() => {
                    const t = todayYmd()
                    setNewCost({ from: job.start_date, to: t < job.end_date ? t : job.end_date })
                  }}
                >
                  <Plus className="size-4" /> สร้างใบคิดราคา
                </Button>
              )
            }
          />
          {costs.length === 0 ? (
            <Empty icon={<FileSpreadsheet className="size-6" />} title="ยังไม่มีใบคิดราคา" />
          ) : (
            <ul className="divide-y divide-slate-100">
              {costs.map((c) => (
                <li key={c.id}>
                  <Link to={`/cost/${c.id}`} className="flex flex-wrap items-center gap-4 px-5 py-3.5 hover:bg-slate-50">
                    <div className="min-w-48 flex-1">
                      <p className="font-medium text-slate-900">
                        {fmtDate(c.period_from)} – {fmtDate(c.period_to)}
                      </p>
                      <p className="text-sm text-slate-500">{c.revision > 0 ? `Revise ${c.revision}` : 'ยังไม่ส่ง'}</p>
                    </div>
                    {c.net_total != null && <p className="tabular font-semibold text-slate-900">{fmtMoney(c.net_total)} ฿</p>}
                    <CostBadge c={c} />
                    <ChevronRight className="size-4 text-slate-400" />
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      )}

      {tab === 'terms' && (
        <div className="grid gap-6 xl:grid-cols-2">
        <Card className="h-fit">
          <CardHeader title="เงื่อนไขคิดราคา" sub={canPrice ? 'Purchase เป็นผู้กำหนด' : 'กำหนดโดย Purchase'} />
          <div className="space-y-5 p-5">
            <TermsStatus job={job} canEdit={canPrice} onConfirm={() => saveTerms({ terms_confirmed_at: new Date().toISOString() })} />
            <div>
              <p className="mb-2 text-sm font-medium text-slate-700">วันทำงานต่อสัปดาห์</p>
              <div className="grid gap-2 sm:grid-cols-2">
                {[
                  { v: 6 as const, t: 'ทำงาน 6 วัน', d: 'วันอาทิตย์คิด ×2' },
                  { v: 5 as const, t: 'ทำงาน 5 วัน', d: 'วันเสาร์-อาทิตย์คิด ×2' },
                ].map((o) => (
                  <button
                    key={o.v}
                    disabled={!canPrice}
                    onClick={() => saveTerms({ workweek: o.v })}
                    className={`rounded-xl border-2 p-4 text-left transition ${job.workweek === o.v ? 'border-brand-500 bg-brand-50' : 'border-slate-200 hover:border-slate-300'} disabled:cursor-default`}
                  >
                    <p className="font-medium text-slate-900">{o.t}</p>
                    <p className="text-sm text-slate-500">{o.d}</p>
                  </button>
                ))}
              </div>
            </div>
            <div>
              <p className="mb-2 text-sm font-medium text-slate-700">พักเย็นก่อน OT</p>
              <div className="grid gap-2 sm:grid-cols-2">
                {[
                  { v: true, t: 'มีพัก 30 นาที', d: 'OT เริ่มหลังครบ 8 ชม. + 30 นาที (เช่น 17:30)' },
                  { v: false, t: 'ไม่พัก ทำต่อเลย', d: 'OT เริ่มทันทีหลังครบ 8 ชม. (เช่น 17:00)' },
                ].map((o) => (
                  <button
                    key={String(o.v)}
                    disabled={!canPrice}
                    onClick={() => saveTerms({ evening_break: o.v })}
                    className={`rounded-xl border-2 p-4 text-left transition ${job.evening_break === o.v ? 'border-brand-500 bg-brand-50' : 'border-slate-200 hover:border-slate-300'} disabled:cursor-default`}
                  >
                    <p className="font-medium text-slate-900">{o.t}</p>
                    <p className="text-sm text-slate-500">{o.d}</p>
                  </button>
                ))}
              </div>
            </div>
            <div>
              <p className="mb-2 text-sm font-medium text-slate-700">พักเที่ยง</p>
              <div className="grid gap-2 sm:grid-cols-2">
                {[
                  { v: true, t: 'มีพักเที่ยง 1 ชม.', d: 'หักช่วง 12:00–13:00 ออกจากชั่วโมงทำงาน' },
                  { v: false, t: 'ไม่พักเที่ยง', d: 'ไม่หักช่วงเที่ยง นับชั่วโมงทำงานเต็ม' },
                ].map((o) => (
                  <button
                    key={String(o.v)}
                    disabled={!canPrice}
                    onClick={() => saveTerms({ lunch_break: o.v })}
                    className={`rounded-xl border-2 p-4 text-left transition ${job.lunch_break === o.v ? 'border-brand-500 bg-brand-50' : 'border-slate-200 hover:border-slate-300'} disabled:cursor-default`}
                  >
                    <p className="font-medium text-slate-900">{o.t}</p>
                    <p className="text-sm text-slate-500">{o.d}</p>
                  </button>
                ))}
              </div>
            </div>
            <div className="rounded-xl bg-slate-50 p-4 text-sm text-slate-600">
              <p className="font-medium text-slate-800">ตัวคูณ (เรทต่อชั่วโมง = ค่าแรงต่อวัน ÷ 8)</p>
              <div className="mt-2 grid grid-cols-2 gap-1 sm:grid-cols-4">
                <span>ปกติ ×1</span>
                <span>OT วันปกติ ×1.5</span>
                <span>วันหยุด ×2</span>
                <span>OT วันหยุด ×3</span>
              </div>
            </div>
          </div>
        </Card>
        <JobRates jobId={id} canEdit={canPrice} />
        </div>
      )}

      <Modal
        open={delText !== null}
        onClose={() => setDelText(null)}
        title={`ลบจ็อบ ${job.job_no}`}
        footer={
          <>
            <Button variant="secondary" onClick={() => setDelText(null)}>
              ยกเลิก
            </Button>
            <Button variant="danger" loading={busy} disabled={delText?.trim() !== job.job_no} onClick={deleteJob}>
              <Trash2 className="size-4" /> ลบถาวร
            </Button>
          </>
        }
      >
        <div className="space-y-4 text-sm">
          <div className="rounded-xl bg-rose-50 p-3 text-rose-800">
            <p className="font-medium">ลบแล้วกู้คืนไม่ได้</p>
            <p className="mt-1">จะลบทีม รายชื่อลูกทีม เวลาเข้า-ออก ใบลงเวลารายวัน Allowance และใบคิดราคาที่ยังเป็นร่างของจ็อบนี้ทั้งหมด</p>
          </div>
          <p className="text-slate-600">
            ถ้าจ็อบนี้มีใบคิดราคาที่ส่งหรืออนุมัติแล้ว ระบบจะไม่ให้ลบ (เป็นเอกสารการเงิน) ให้ใช้ <b>ปิดจ็อบ</b> แทน
          </p>
          <Field label={`พิมพ์เลขจ็อบ "${job.job_no}" เพื่อยืนยัน`}>
            <Input autoFocus value={delText ?? ''} onChange={(e) => setDelText(e.target.value)} placeholder={job.job_no} />
          </Field>
        </div>
      </Modal>

      <Modal
        open={Boolean(newCost)}
        onClose={() => setNewCost(null)}
        title="สร้างใบคิดราคา"
        footer={
          <>
            <Button variant="secondary" onClick={() => setNewCost(null)}>
              ยกเลิก
            </Button>
            <Button onClick={createCost} loading={busy}>
              สร้าง
            </Button>
          </>
        }
      >
        {newCost && (
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="ตั้งแต่วันที่">
              <Input type="date" value={newCost.from} onChange={(e) => setNewCost({ ...newCost, from: e.target.value })} />
            </Field>
            <Field label="ถึงวันที่">
              <Input type="date" value={newCost.to} onChange={(e) => setNewCost({ ...newCost, to: e.target.value })} />
            </Field>
          </div>
        )}
      </Modal>
    </>
  )
}
