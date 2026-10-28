export type Role = 'admin' | 'supervisor' | 'planner' | 'purchase' | 'manager'

export const ROLE_LABEL: Record<Role, string> = {
  admin: 'แอดมิน',
  supervisor: 'หัวหน้างาน',
  planner: 'Planner',
  purchase: 'Purchase',
  manager: 'Manager',
}

export interface Profile {
  id: string
  email: string | null
  full_name: string
  role: Role | null
  active: boolean
  signature_id?: string | null
  created_at: string
}

export interface Job {
  id: string
  job_no: string
  title: string
  contractor_name: string | null
  location: string | null
  start_date: string
  end_date: string
  workweek: 5 | 6
  evening_break: boolean
  lunch_break: boolean
  status: 'active' | 'closed'
  terms_confirmed_by: string | null
  terms_confirmed_at: string | null
  budget: number | null
  created_at: string
}

export interface Team {
  id: string
  job_id: string
  name: string
  supervisor_id: string | null
  qr_token: string
}

export interface Worker {
  id: string
  job_id: string
  team_id: string
  full_name: string
  position: string
  active: boolean
}

export interface AttendanceHours {
  id: string
  worker_id: string
  job_id: string
  team_id: string
  work_date: string
  check_in: string
  check_out: string | null
  source: 'self' | 'supervisor'
  note: string | null
  updated_by: string | null
  updated_at: string
  holiday: boolean
  normal_h: number
  ot_h: number
  edit_count: number
}

export interface DaySheet {
  id: string
  job_id: string
  team_id: string
  work_date: string
  supervisor_approved_by: string | null
  supervisor_approved_at: string | null
  planner_approved_by: string | null
  planner_approved_at: string | null
  supervisor_sig_id: string | null
  supervisor_name: string | null
  planner_sig_id: string | null
  planner_name: string | null
  rejected_by: string | null
  rejected_at: string | null
  reject_reason: string | null
  team_name: string
  supervisor_id: string | null
  job_no: string
  job_title: string
  locked: boolean
  people: number
  open_people: number
}

export interface Allowance {
  id: string
  worker_id: string
  job_id: string
  work_date: string
  kind: string
  amount: number
}

export interface CostSheet {
  id: string
  job_id: string
  period_from: string
  period_to: string
  status: 'draft' | 'submitted' | 'approved'
  revision: number
  reject_reason: string | null
  rejected_at: string | null
  snapshot: CostSnapshot | null
  subtotal: number | null
  wht_amount: number | null
  net_total: number | null
  created_at: string
  submitted_at: string | null
  submitted_by: string | null
  submitted_sig_id: string | null
  submitted_name: string | null
  approved_at: string | null
}

export interface CostDay {
  date: string
  holiday: boolean
  in: string
  out: string | null
  normal: number
  ot: number
  approved: boolean
  edits?: number
}

export interface CostWorker {
  worker_id: string
  name: string
  position: string
  team: string
  day_rate: number
  unit: number
  work_days: number
  hours: { n1: number; ot15: number; h2: number; h3: number }
  amounts: { n1: number; ot15: number; h2: number; h3: number }
  allowance_total: number
  total: number
  days: CostDay[]
  allowances: { date: string; kind: string; amount: number }[]
}

export interface CostSnapshot {
  job: { id: string; job_no: string; title: string; contractor: string | null; location: string | null; workweek: 5 | 6; evening_break: boolean; lunch_break?: boolean }
  period: { from: string; to: string }
  settings: { normal_hours: number; wht_rate: number; break_minutes: number; round_minutes: number; company: string }
  holidays: string[]
  workers: CostWorker[]
  subtotal: number
  wht: number
  net: number
  pending_days: number
  missing_rates: number
  generated_at: string
}
