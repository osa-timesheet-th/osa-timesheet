import { Pencil, Plus, Split, Trash2, X } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router'
import { addDays, fmtDate, todayYmd } from '../lib/format'
import { must, useLoad } from '../lib/hooks'
import { supabase } from '../lib/supabase'
import type { Job } from '../lib/types'
import { Badge, Button, Card, CardHeader, ErrorBox, Field, Input, Modal, Select, Spinner, useToast } from './ui'

type Alloc = {
  id: string
  source_job_id: string
  target_job_id: string
  date_from: string
  date_to: string
  pct: number
  source: { job_no: string; title: string } | null
  target: { job_no: string; title: string } | null
}
type OtherJob = { id: string; job_no: string; title: string; start_date: string; end_date: string }
type Share = { job_id: string; pct: string }
type Draft = { from: string; to: string; shares: Share[]; editing: boolean }

const num = (v: string) => Number(v || 0)
const round2 = (n: number) => Math.round(n * 100) / 100

/** แบ่งชั่วโมงของจ็อบนี้ไปจ็อบอื่นเป็น % (Purchase / แอดมิน) — เซิร์ฟเวอร์ตรวจสิทธิ์และเงื่อนไขทั้งหมด */
export function JobAllocation({
  job,
  canEdit,
  lockedUntil,
  onChanged,
}: {
  job: Job
  canEdit: boolean
  /** วันสุดท้ายที่อยู่ในใบคิดราคาที่ส่งแล้ว (แบ่งได้ตั้งแต่วันถัดไป) */
  lockedUntil?: string
  onChanged?: () => void
}) {
  const toast = useToast()
  const [draft, setDraft] = useState<Draft | null>(null)
  const [busy, setBusy] = useState(false)

  const { data, error, reload } = useLoad(async () => {
    const [allocs, jobs] = await Promise.all([
      supabase
        .from('job_allocations')
        .select(
          'id, source_job_id, target_job_id, date_from, date_to, pct, source:jobs!job_allocations_source_job_id_fkey(job_no, title), target:jobs!job_allocations_target_job_id_fkey(job_no, title)',
        )
        .or(`source_job_id.eq.${job.id},target_job_id.eq.${job.id}`)
        .order('date_from'),
      canEdit
        ? supabase.from('jobs').select('id, job_no, title, start_date, end_date').eq('status', 'active').neq('id', job.id).order('job_no')
        : Promise.resolve({ data: [], error: null }),
    ])
    return { allocs: must(allocs) as unknown as Alloc[], jobs: must(jobs) as OtherJob[] }
  }, [job.id, canEdit])

  if (error) return <ErrorBox message={error} onRetry={reload} />
  if (!data) return <Spinner />

  // การแบ่งออก: รวมเป็นชุดตามช่วงวันที่
  const groups = new Map<string, Alloc[]>()
  data.allocs
    .filter((a) => a.source_job_id === job.id)
    .forEach((a) => {
      const k = `${a.date_from}|${a.date_to}`
      groups.set(k, [...(groups.get(k) ?? []), a])
    })
  const incoming = data.allocs.filter((a) => a.target_job_id === job.id)
  if (!canEdit && groups.size === 0 && incoming.length === 0) return null

  const used = draft ? round2(draft.shares.reduce((s, x) => s + num(x.pct), 0)) : 0
  const keep = round2(100 - used)

  function openNew() {
    const t = todayYmd()
    const from = lockedUntil && addDays(lockedUntil, 1) > job.start_date ? addDays(lockedUntil, 1) : job.start_date
    setDraft({ from, to: t < job.end_date ? t : job.end_date, shares: [{ job_id: '', pct: '' }], editing: false })
  }

  function openEdit(rows: Alloc[]) {
    setDraft({
      from: rows[0].date_from,
      to: rows[0].date_to,
      shares: rows.map((r) => ({ job_id: r.target_job_id, pct: String(Number(r.pct)) })),
      editing: true,
    })
  }

  // หารเท่ากัน: จ็อบนี้ + จ็อบปลายทางทุกจ็อบได้เท่ากัน เศษอยู่กับจ็อบนี้
  function splitEven() {
    if (!draft) return
    const each = Math.floor((100 / (draft.shares.length + 1)) * 100) / 100
    setDraft({ ...draft, shares: draft.shares.map((s) => ({ ...s, pct: String(each) })) })
  }

  function setShare(i: number, patch: Partial<Share>) {
    if (!draft) return
    setDraft({ ...draft, shares: draft.shares.map((s, j) => (j === i ? { ...s, ...patch } : s)) })
  }

  async function save(shares: Share[], from: string, to: string) {
    setBusy(true)
    const { error } = await supabase.rpc('set_job_allocation', {
      p_source: job.id,
      p_from: from,
      p_to: to,
      p_shares: shares.map((s) => ({ job_id: s.job_id, pct: num(s.pct) })),
    })
    setBusy(false)
    if (error) return toast.err(error)
    toast.ok(shares.length ? 'บันทึกการแบ่งชั่วโมงแล้ว' : 'ยกเลิกการแบ่งชั่วโมงแล้ว')
    setDraft(null)
    reload()
    onChanged?.()
  }

  function submit() {
    if (!draft) return
    if (!draft.from || !draft.to || draft.from > draft.to) return toast.err('ช่วงวันที่ไม่ถูกต้อง')
    if (draft.shares.some((s) => !s.job_id)) return toast.err('เลือกจ็อบปลายทางให้ครบ')
    if (draft.shares.some((s) => !(num(s.pct) > 0 && num(s.pct) <= 100))) return toast.err('ใส่ % มากกว่า 0 และไม่เกิน 100')
    if (new Set(draft.shares.map((s) => s.job_id)).size !== draft.shares.length) return toast.err('เลือกจ็อบปลายทางซ้ำ')
    if (keep < 0) return toast.err('รวมกันเกิน 100%')
    save(draft.shares, draft.from, draft.to)
  }

  function remove(rows: Alloc[]) {
    if (!confirm(`ยกเลิกการแบ่งชั่วโมงช่วง ${fmtDate(rows[0].date_from)} – ${fmtDate(rows[0].date_to)}? ชั่วโมงจะกลับมาอยู่จ็อบนี้ทั้งหมด`)) return
    save([], rows[0].date_from, rows[0].date_to)
  }

  return (
    <Card className="mb-6">
      <CardHeader
        title="แบ่งชั่วโมงไปจ็อบอื่น"
        sub="ใช้เมื่อทีมเดียวทำหลายจ็อบ — เกลี่ยชั่วโมงปกติและ OT ของทุกคนตาม % ไปคิดเงินในจ็อบนั้น (ค่าแรงเดิม)"
        right={
          canEdit && (
            <Button size="sm" variant="secondary" onClick={openNew}>
              <Split className="size-4" /> แบ่งชั่วโมง
            </Button>
          )
        }
      />
      {groups.size === 0 && incoming.length === 0 ? (
        <p className="px-5 pb-5 text-sm text-slate-500">ยังไม่มีการแบ่ง ชั่วโมงทั้งหมดคิดเงินในจ็อบนี้</p>
      ) : (
        <ul className="divide-y divide-slate-100 border-t border-slate-100">
          {[...groups.values()].map((rows) => {
            const rest = round2(100 - rows.reduce((s, r) => s + Number(r.pct), 0))
            return (
              <li key={rows[0].id} className="flex flex-wrap items-center gap-3 px-5 py-3.5">
                <p className="w-52 shrink-0 font-medium text-slate-900">
                  {fmtDate(rows[0].date_from)} – {fmtDate(rows[0].date_to)}
                </p>
                <div className="flex flex-1 flex-wrap gap-1.5">
                  <Badge tone="blue">จ็อบนี้ {rest}%</Badge>
                  {rows.map((r) => (
                    <Link key={r.id} to={`/jobs/${r.target_job_id}`}>
                      <Badge tone="green">
                        → {r.target?.job_no} {Number(r.pct)}%
                      </Badge>
                    </Link>
                  ))}
                </div>
                {canEdit && (
                  <div className="flex gap-1">
                    <Button size="sm" variant="ghost" onClick={() => openEdit(rows)} title="แก้ %">
                      <Pencil className="size-4" />
                    </Button>
                    <Button size="sm" variant="ghost" className="text-rose-600 hover:bg-rose-50" onClick={() => remove(rows)} title="ยกเลิกการแบ่ง">
                      <Trash2 className="size-4" />
                    </Button>
                  </div>
                )}
              </li>
            )
          })}
          {incoming.map((a) => (
            <li key={a.id} className="flex flex-wrap items-center gap-3 px-5 py-3.5">
              <p className="w-52 shrink-0 font-medium text-slate-900">
                {fmtDate(a.date_from)} – {fmtDate(a.date_to)}
              </p>
              <p className="flex-1 text-sm text-slate-600">
                รับ <b>{Number(a.pct)}%</b> ของชั่วโมงจาก{' '}
                <Link to={`/jobs/${a.source_job_id}`} className="font-mono text-brand-700 hover:underline">
                  {a.source?.job_no}
                </Link>{' '}
                · แก้ได้ที่จ็อบต้นทาง
              </p>
            </li>
          ))}
        </ul>
      )}

      <Modal
        open={Boolean(draft)}
        onClose={() => setDraft(null)}
        title={draft?.editing ? 'แก้การแบ่งชั่วโมง' : 'แบ่งชั่วโมงไปจ็อบอื่น'}
        footer={
          <>
            <Button variant="secondary" onClick={() => setDraft(null)}>
              ยกเลิก
            </Button>
            <Button onClick={submit} loading={busy}>
              บันทึก
            </Button>
          </>
        }
      >
        {draft && (
          <div className="space-y-4 text-sm">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="ตั้งแต่วันที่">
                <Input type="date" value={draft.from} disabled={draft.editing} onChange={(e) => setDraft({ ...draft, from: e.target.value })} />
              </Field>
              <Field label="ถึงวันที่">
                <Input type="date" value={draft.to} disabled={draft.editing} onChange={(e) => setDraft({ ...draft, to: e.target.value })} />
              </Field>
            </div>
            {draft.editing && <p className="-mt-2 text-xs text-slate-500">อยากเปลี่ยนช่วงวันที่ ให้ลบการแบ่งนี้แล้วสร้างใหม่</p>}

            <div className="space-y-2">
              <div className="flex items-center gap-2 rounded-xl bg-brand-50 px-3 py-2.5">
                <span className="flex-1 font-medium text-brand-800">
                  {job.job_no} (จ็อบนี้)
                </span>
                <span className={`tabular font-semibold ${keep < 0 ? 'text-rose-600' : 'text-brand-800'}`}>{keep}%</span>
              </div>
              {draft.shares.map((s, i) => (
                <div key={i} className="flex items-center gap-2">
                  <Select className="flex-1" value={s.job_id} onChange={(e) => setShare(i, { job_id: e.target.value })}>
                    <option value="">— เลือกจ็อบ —</option>
                    {data.jobs.map((j) => (
                      <option key={j.id} value={j.id}>
                        {j.job_no} · {j.title}
                      </option>
                    ))}
                  </Select>
                  <div className="relative w-28">
                    <Input
                      type="number"
                      min={0}
                      max={100}
                      step="0.01"
                      inputMode="decimal"
                      value={s.pct}
                      onChange={(e) => setShare(i, { pct: e.target.value })}
                      className="pr-7 text-right"
                      placeholder="0"
                    />
                    <span className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-slate-400">%</span>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    disabled={draft.shares.length === 1}
                    onClick={() => setDraft({ ...draft, shares: draft.shares.filter((_, j) => j !== i) })}
                    title="เอาออก"
                  >
                    <X className="size-4" />
                  </Button>
                </div>
              ))}
              <div className="flex flex-wrap gap-2 pt-1">
                <Button size="sm" variant="secondary" onClick={() => setDraft({ ...draft, shares: [...draft.shares, { job_id: '', pct: '' }] })}>
                  <Plus className="size-4" /> เพิ่มจ็อบ
                </Button>
                <Button size="sm" variant="secondary" onClick={splitEven}>
                  หารเท่ากัน
                </Button>
              </div>
            </div>

            <div className="rounded-xl bg-slate-50 p-3 text-slate-600">
              ชั่วโมงปกติและ OT ของทุกคนในจ็อบนี้ ในช่วงวันที่นี้ จะถูกเกลี่ยตาม % ไปคิดเงินในจ็อบปลายทาง ด้วยค่าแรงเดิม · การลงเวลาและการอนุมัติยังอยู่ที่จ็อบนี้ · Allowance
              ไม่ถูกแบ่ง · ช่วงที่ส่งใบคิดราคาไปแล้วแก้ไม่ได้
            </div>
          </div>
        )}
      </Modal>
    </Card>
  )
}
