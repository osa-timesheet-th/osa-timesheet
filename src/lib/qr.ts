import qrcode from 'qrcode-generator'

/** วาด QR ลง canvas (ขอบขาว 1 ช่อง แบบเดียวกับของเดิม) — ใช้ไลบรารี qrcode-generator ที่ไม่มีแพ็กเกจพ่วง */
export function drawQr(canvas: HTMLCanvasElement, text: string, size: number, dark = '#0f172a') {
  const q = qrcode(0, 'M')
  q.addData(text, 'Byte')
  q.make()
  const n = q.getModuleCount() + 2
  const cell = size / n
  canvas.width = size
  canvas.height = size
  const ctx = canvas.getContext('2d')!
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, size, size)
  ctx.fillStyle = dark
  for (let r = 0; r < n - 2; r++)
    for (let c = 0; c < n - 2; c++)
      if (q.isDark(r, c)) ctx.fillRect(Math.floor((c + 1) * cell), Math.floor((r + 1) * cell), Math.ceil(cell), Math.ceil(cell))
  return canvas
}

/** รูป QR เป็น data URL (PNG) สำหรับแสดงบนหน้าจอ */
export function qrDataUrl(text: string, size = 480) {
  return drawQr(document.createElement('canvas'), text, size).toDataURL('image/png')
}
