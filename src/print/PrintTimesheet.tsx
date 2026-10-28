import { useParams } from 'react-router'
import { ErrorBox, Spinner } from '../components/ui'
import { dayOfMonth, daysBetween, fmtDocDate, fmtHours, fmtMoney, isoDow, weekdayShort } from '../lib/format'
import { useLoad } from '../lib/hooks'
import type { CostWorker } from '../lib/types'
import { DocHeader, DraftMark, loadCost, Paper, PrintShell } from './common'

const PER_PAGE = 16
const ROWS = [
  { key: 'n1', label: 'Normal/Day', mult: 'ปกติ', holiday: false, field: 'normal' },
  { key: 'ot15', label: 'x1.5/Hrs.', mult: 'x1.5', holiday: false, field: 'ot' },
  { key: 'h2', label: 'x2 Holiday', mult: 'x2', holiday: true, field: 'normal' },
  { key: 'h3', label: 'x3/Hrs', mult: 'x3', holiday: true, field: 'ot' },
] as const

const monthTitle = (from: string, to: string) => {
  const f = new Intl.DateTimeFormat('en-US', { month: 'long', year: 'numeric', timeZone: 'Asia/Bangkok' })
  const a = f.format(new Date(`${from}T12:00:00+07:00`))
  const b = f.format(new Date(`${to}T12:00:00+07:00`))
  return a === b ? a : `${a} – ${b}`
}

export type CostDocData = Awaited<ReturnType<typeof loadCost>>

export default function PrintTimesheet() {
  const { id = '' } = useParams()
  const { data, error } = useLoad(() => loadCost(id), [id])
  if (error) return <ErrorBox message={error} />
  if (!data) return <Spinner />
  return (
    <PrintShell landscape title={`Time Sheet ${data.snap.job.job_no}`}>
      <TimesheetDoc data={data} />
    </PrintShell>
  )
}

export function TimesheetDoc({ data }: { data: CostDocData }) {
  const { cs, snap } = data

  const days = daysBetween(snap.period.from, snap.period.to)
  const holidaySet = new Set(snap.holidays)
  const isHol = (d: string) => isoDow(d) === 7 || (snap.job.workweek === 5 && isoDow(d) === 6) || holidaySet.has(d)
  const chunks: string[][] = []
  for (let i = 0; i < days.length; i += PER_PAGE) chunks.push(days.slice(i, i + PER_PAGE))
  const kinds = [...new Set(['ค่ารถ/ค่าเดินทาง', ...snap.workers.flatMap((w) => w.allowances.map((a) => a.kind))])]

  const cell = (w: CostWorker, d: string, field: 'normal' | 'ot', holiday: boolean) => {
    const x = w.days.find((y) => y.date === d)
    if (!x || x.holiday !== holiday) return ''
    return fmtHours(x[field])
  }
  const allowCell = (w: CostWorker, d: string, kind: string) => {
    const s = w.allowances.filter((a) => a.date === d && a.kind === kind).reduce((t, a) => t + Number(a.amount), 0)
    return s ? fmtMoney(s).replace(/\.00$/, '') : ''
  }

  return (
    <>
      {chunks.map((chunk, ci) => {
        const last = ci === chunks.length - 1
        return (
          <Paper key={ci} landscape className="page-break mx-auto">
            <DraftMark show={cs.status !== 'approved'} />
            <DocHeader
              company={snap.settings.company}
              right={
                <div className="text-right text-[11px]">
                  {cs.revision > 0 && <p className="text-base font-bold text-rose-600">REVISE {cs.revision}</p>}
                  <p>
                    {fmtDocDate(snap.period.from)} – {fmtDocDate(snap.period.to)}
                  </p>
                  {chunks.length > 1 && (
                    <p>
                      หน้า {ci + 1}/{chunks.length}
                    </p>
                  )}
                </div>
              }
            />
            <div className="mb-2 grid grid-cols-3 items-end text-sm">
              <p>
                Job <b className="ml-2 text-base">{snap.job.job_no}</b>
              </p>
              <p className="text-center text-lg font-bold">
                Time Sheet <span className="ml-2 text-sm font-normal">{snap.job.title}</span>
              </p>
              <p className="text-right">
                Date: <b>{monthTitle(snap.period.from, snap.period.to)}</b>
              </p>
            </div>
            {snap.job.contractor && <p className="mb-2 text-[11px]">ผู้รับเหมา: {snap.job.contractor}</p>}

            <table className="text-[9.5px]">
              <thead>
                <tr className="bg-slate-200">
                  <th rowSpan={2} className="w-6">No</th>
                  <th rowSpan={2} className="w-36">Name</th>
                  <th className="w-24">Position / Rate/Day</th>
                  {chunk.map((d) => (
                    <th key={d} className={`w-6 font-normal ${isHol(d) ? 'bg-slate-400' : ''}`}>
                      {weekdayShort(d)}
                    </th>
                  ))}
                  {last && (
                    <>
                      <th colSpan={3}>Total</th>
                      <th className="w-14">Unit Rate</th>
                      <th className="w-20">Total</th>
                    </>
                  )}
                </tr>
                <tr className="bg-slate-200">
                  <th>Date</th>
                  {chunk.map((d) => (
                    <th key={d} className={isHol(d) ? 'bg-slate-400' : ''}>
                      {dayOfMonth(d)}
                    </th>
                  ))}
                  {last && <th colSpan={5} />}
                </tr>
              </thead>
              {snap.workers.map((w, wi) => {
                const allowRows = kinds.filter((k) => k === kinds[0] || w.allowances.some((a) => a.kind === k))
                const span = ROWS.length + allowRows.length
                return (
                  <tbody key={w.worker_id} style={{ breakInside: 'avoid' }}>
                    {ROWS.map((r, ri) => (
                      <tr key={r.key}>
                        {ri === 0 && (
                          <>
                            <td rowSpan={span} className="text-center align-top">
                              {wi + 1}
                            </td>
                            <td rowSpan={span} className="align-top">
                              <p className="font-semibold">{w.name}</p>
                              <p className="mt-1 text-[8.5px] text-slate-600">Normal Time (8 ชม.)</p>
                            </td>
                          </>
                        )}
                        <td className="whitespace-nowrap">
                          {r.label}
                          {ri === 0 && <span className="float-right">{w.position}</span>}
                          {ri === 1 && <span className="float-right font-semibold">{fmtMoney(w.day_rate).replace(/\.00$/, '')}</span>}
                        </td>
                        {chunk.map((d) => (
                          <td key={d} className={`text-center ${isHol(d) ? 'bg-slate-200' : ''}`}>
                            {cell(w, d, r.field, r.holiday)}
                          </td>
                        ))}
                        {last && (
                          <>
                            <td className="w-8 text-center">{r.mult}</td>
                            <td className="w-8 text-right font-semibold">{fmtHours(w.hours[r.key]) || '0'}</td>
                            <td className="w-8 text-center">Hrs.</td>
                            <td className="text-right">{fmtMoney(w.unit * { n1: 1, ot15: 1.5, h2: 2, h3: 3 }[r.key])}</td>
                            <td className="bg-slate-100 text-right">{w.amounts[r.key] ? fmtMoney(w.amounts[r.key]) : '-'}</td>
                          </>
                        )}
                      </tr>
                    ))}
                    {allowRows.map((k) => {
                      const list = w.allowances.filter((a) => a.kind === k)
                      const total = list.reduce((s, a) => s + Number(a.amount), 0)
                      const uniform = list.length > 0 && list.every((a) => Number(a.amount) === Number(list[0].amount))
                      return (
                        <tr key={k}>
                          <td className="whitespace-nowrap font-semibold">{k}</td>
                          {chunk.map((d) => (
                            <td key={d} className={`text-center ${isHol(d) ? 'bg-slate-200' : ''}`}>
                              {allowCell(w, d, k)}
                            </td>
                          ))}
                          {last && (
                            <>
                              <td />
                              <td className="text-right font-semibold">{new Set(list.map((a) => a.date)).size}</td>
                              <td className="text-center">Day</td>
                              <td className="text-right">{uniform ? fmtMoney(list[0].amount) : ''}</td>
                              <td className="bg-slate-100 text-right">{total ? fmtMoney(total) : '-'}</td>
                            </>
                          )}
                        </tr>
                      )
                    })}
                    {last && (
                      <tr className="bg-slate-300 font-semibold">
                        <td colSpan={3 + chunk.length + 4} className="text-center">
                          Summary
                        </td>
                        <td className="text-right">{fmtMoney(w.total)}</td>
                      </tr>
                    )}
                  </tbody>
                )
              })}
              {last && (
                <tbody style={{ breakInside: 'avoid' }}>
                  <tr className="bg-slate-400 text-[11px] font-bold">
                    <td colSpan={3 + chunk.length + 4} className="text-center">
                      Grand TOTAL
                    </td>
                    <td className="text-right">{fmtMoney(snap.subtotal)}</td>
                  </tr>
                </tbody>
              )}
            </table>

            {last && (
              <div className="mt-4 flex items-start justify-between gap-6 text-[10px]" style={{ breakInside: 'avoid' }}>
                <div className="space-y-0.5">
                  <p>
                    วันทำงาน {snap.job.workweek} วัน/สัปดาห์ · {snap.job.lunch_break === false ? 'ไม่พักเที่ยง' : 'พักเที่ยง 12:00–13:00'} · {snap.job.evening_break ? `พักเย็น ${snap.settings.break_minutes} นาทีก่อน OT` : 'ไม่พักก่อน OT'} · เรท/ชม. = ค่าแรงต่อวัน ÷ {snap.settings.normal_hours}
                  </p>
                  <p>ช่องสีเทา = วันหยุด (×2, OT ×3)</p>
                </div>
              </div>
            )}
            {!last && <p className="mt-3 text-right text-[10px]">ต่อหน้าถัดไป →</p>}
          </Paper>
        )
      })}
    </>
  )
}
