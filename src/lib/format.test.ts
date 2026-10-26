// รันด้วยตัวทดสอบในตัวของ Node (ไม่ต้องติดตั้งแพ็กเกจเพิ่ม): npm test
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { addDays, bahtText, daysBetween, fmtDocDate, fmtOut, isoDow } from './format.ts'

describe('bahtText', () => {
  it('อ่านจำนวนเงินตามเอกสารตัวอย่าง', () => {
    assert.equal(bahtText(293903.94), 'สองแสนเก้าหมื่นสามพันเก้าร้อยสามบาทเก้าสิบสี่สตางค์')
  })
  it('เอ็ด ยี่ ถ้วน', () => {
    assert.equal(bahtText(21), 'ยี่สิบเอ็ดบาทถ้วน')
    assert.equal(bahtText(101.01), 'หนึ่งร้อยเอ็ดบาทหนึ่งสตางค์')
    assert.equal(bahtText(1000000), 'หนึ่งล้านบาทถ้วน')
    assert.equal(bahtText(0), 'ศูนย์บาทถ้วน')
  })
})

describe('วันที่ (เวลาไทย)', () => {
  it('บวกวันข้ามเดือน', () => {
    assert.equal(addDays('2026-09-30', 1), '2026-10-01')
    assert.deepEqual(daysBetween('2026-09-29', '2026-10-02'), ['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02'])
  })
  it('วันอาทิตย์ = 7', () => {
    assert.equal(isoDow('2026-10-18'), 7)
    assert.equal(isoDow('2026-10-17'), 6)
  })
  it('รูปแบบวันที่ในเอกสาร', () => {
    assert.equal(fmtDocDate('2026-10-02'), '02/10/2026')
    assert.equal(fmtDocDate('2026-10-01T18:30:00Z'), '02/10/2026')
  })
})

describe('เวลาออกข้ามเที่ยงคืน', () => {
  it('วันเดียวกันไม่มี (+1)', () => {
    assert.equal(fmtOut('2026-10-21T01:00:00Z', '2026-10-21T10:00:00Z'), '17:00')
  })
  it('ออกหลังเที่ยงคืนเวลาไทยมี (+1)', () => {
    // เข้า 08:00 ไทย (01:00Z) ออก 01:00 ไทยของวันถัดไป (18:00Z)
    assert.equal(fmtOut('2026-10-21T01:00:00Z', '2026-10-21T18:00:00Z'), '01:00 (+1)')
  })
})
