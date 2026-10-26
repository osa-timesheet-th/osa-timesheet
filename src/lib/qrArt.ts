import { drawQr } from './qr'

export interface QrArtInfo {
  url: string
  kind: 'in' | 'out'
  jobNo: string
  jobTitle: string
  team: string
  validText: string
  company: string
}

const W = 1080
const H = 1350
const INK = '#142a4b'
const MUTED = '#5b6b82'
const FONT = '"IBM Plex Sans Thai", sans-serif'

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

function loadImage(src: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = reject
    img.src = src
  })
}

function fitText(ctx: CanvasRenderingContext2D, text: string, maxWidth: number) {
  if (ctx.measureText(text).width <= maxWidth) return text
  let t = text
  while (t.length > 1 && ctx.measureText(t + '…').width > maxWidth) t = t.slice(0, -1)
  return t + '…'
}

/** การ์ดภาพ QR สำหรับส่งในไลน์/พิมพ์ — ดูเป็นทางการและน่าสแกน */
export async function makeQrArtwork(info: QrArtInfo): Promise<Blob> {
  await Promise.all([document.fonts.load(`600 64px ${FONT}`), document.fonts.load(`400 32px ${FONT}`), document.fonts.load(`500 32px ${FONT}`)])
  const canvas = document.createElement('canvas')
  canvas.width = W
  canvas.height = H
  const ctx = canvas.getContext('2d')!
  ctx.textAlign = 'center'
  ctx.textBaseline = 'alphabetic'

  // พื้นหลัง
  ctx.fillStyle = '#eef4fb'
  ctx.fillRect(0, 0, W, H)
  const accent = info.kind === 'in' ? '#059669' : '#ea580c'
  ctx.fillStyle = accent
  ctx.fillRect(0, 0, W, 210)

  // การ์ดขาว
  ctx.save()
  ctx.shadowColor = 'rgba(20,42,75,0.18)'
  ctx.shadowBlur = 40
  ctx.shadowOffsetY = 12
  roundRect(ctx, 60, 70, W - 120, H - 170, 48)
  ctx.fillStyle = '#ffffff'
  ctx.fill()
  ctx.restore()

  // โลโก้
  try {
    const logo = await loadImage(`${import.meta.env.BASE_URL}brand/osa-logo.png`)
    const lh = 120
    const lw = (logo.width / logo.height) * lh
    ctx.drawImage(logo, (W - lw) / 2, 110, lw, lh)
  } catch {
    /* ไม่มีโลโก้ก็ยังใช้ได้ */
  }

  // หัวเรื่อง
  ctx.fillStyle = INK
  ctx.font = `600 72px ${FONT}`
  ctx.fillText(info.kind === 'in' ? 'สแกนลงเวลาเข้างาน' : 'สแกนลงเวลาออกงาน', W / 2, 330)
  ctx.fillStyle = accent
  ctx.font = `600 38px ${FONT}`
  ctx.fillText(info.validText, W / 2, 385)

  // QR
  const q = document.createElement('canvas')
  drawQr(q, info.url, 560)
  const qs = 560
  const qx = (W - qs) / 2
  const qy = 425
  roundRect(ctx, qx - 26, qy - 26, qs + 52, qs + 52, 36)
  ctx.lineWidth = 6
  ctx.strokeStyle = accent
  ctx.stroke()
  ctx.drawImage(q, qx, qy, qs, qs)

  // ข้อมูลจ็อบ
  ctx.fillStyle = INK
  ctx.font = `600 44px ${FONT}`
  ctx.fillText(fitText(ctx, `${info.jobNo}  ·  ${info.jobTitle}`, W - 220), W / 2, 1075)
  ctx.fillStyle = MUTED
  ctx.font = `400 32px ${FONT}`
  ctx.fillText(fitText(ctx, info.team, W - 220), W / 2, 1125)

  // ขั้นตอน
  const steps = ['สแกน QR', 'เลือกชื่อ + ใส่ PIN', info.kind === 'in' ? 'กดเช็คอิน' : 'กดเช็คเอาท์']
  const colW = (W - 200) / 3
  steps.forEach((t, i) => {
    const cx = 100 + colW * i + colW / 2
    ctx.fillStyle = accent
    ctx.beginPath()
    ctx.arc(cx, 1172, 22, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = '#ffffff'
    ctx.font = `600 26px ${FONT}`
    ctx.fillText(String(i + 1), cx, 1181)
    ctx.fillStyle = INK
    ctx.font = `500 28px ${FONT}`
    ctx.fillText(t, cx, 1232)
  })

  // ท้ายภาพ
  ctx.fillStyle = MUTED
  ctx.font = `400 24px ${FONT}`
  ctx.fillText(fitText(ctx, `${info.company}  ·  ขอ PIN จากหัวหน้างานทุกวัน ห้ามลงเวลาแทนผู้อื่น`, W - 80), W / 2, H - 40)

  return new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('สร้างภาพไม่สำเร็จ'))), 'image/png'))
}

export function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
