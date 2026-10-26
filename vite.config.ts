import tailwindcss from '@tailwindcss/vite'
import { copyFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { defineConfig, loadEnv, type Plugin } from 'vite'

/** ใส่ Content-Security-Policy ตอน build (GitHub Pages ตั้ง HTTP header เองไม่ได้) */
function securityMeta(supabaseUrl: string): Plugin {
  const origin = (() => {
    try {
      return new URL(supabaseUrl).origin
    } catch {
      return ''
    }
  })()
  const ws = origin.replace(/^http/, 'ws')
  const csp = [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "font-src 'self'",
    `connect-src 'self' ${origin} ${ws}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    'upgrade-insecure-requests',
  ].join('; ')
  return {
    name: 'security-meta',
    apply: 'build',
    transformIndexHtml: (html) =>
      html.replace('<meta charset="UTF-8" />', `<meta charset="UTF-8" />\n    <meta http-equiv="Content-Security-Policy" content="${csp}" />`),
  }
}

/** GitHub Pages: ให้ทุก URL (เช่น /c/xxxx) เปิดแอปได้ และไม่ผ่าน Jekyll */
function githubPages(): Plugin {
  return {
    name: 'github-pages',
    apply: 'build',
    closeBundle() {
      const out = resolve(import.meta.dirname, 'dist')
      copyFileSync(resolve(out, 'index.html'), resolve(out, '404.html'))
      writeFileSync(resolve(out, '.nojekyll'), '')
    },
  }
}

/** กันพลาด: ถ้าใส่คีย์ลับ (secret / service_role) มาแทนคีย์สาธารณะ ให้ build ล้มก่อนขึ้นเว็บ */
function assertPublicKey(key: string) {
  let payload = ''
  try {
    payload = Buffer.from(key.split('.')[1] ?? '', 'base64url').toString()
  } catch {
    /* not a JWT */
  }
  if (key.startsWith('sb_secret_') || /"role"\s*:\s*"service_role"/.test(payload)) {
    throw new Error('VITE_SUPABASE_ANON_KEY เป็นคีย์ลับ — ห้ามใช้ในหน้าเว็บ ให้ใช้ Publishable key เท่านั้น')
  }
}

export default defineConfig(({ mode, command }) => {
  const env = loadEnv(mode, process.cwd(), '')
  if (command === 'build') assertPublicKey(env.VITE_SUPABASE_ANON_KEY ?? '')
  return {
    base: env.VITE_BASE || '/',
    plugins: [tailwindcss(), securityMeta(env.VITE_SUPABASE_URL ?? ''), githubPages()],
    // แปลง JSX ด้วยตัวที่มากับ Vite เอง (ไม่ต้องใช้ปลั๊กอิน React เพิ่ม)
    oxc: { jsx: { runtime: 'automatic', importSource: 'react' } },
    // ไม่ฝังไฟล์เล็กเป็น data: URI เพื่อให้ผ่าน CSP (font-src 'self')
    build: {
      sourcemap: false,
      assetsInlineLimit: 0,
      rolldownOptions: {
        // "use client" ในไลบรารีมีผลเฉพาะ server rendering ซึ่งแอพนี้ไม่ได้ใช้
        onwarn(w, warn) {
          if (w.code !== 'MODULE_LEVEL_DIRECTIVE') warn(w)
        },
      },
    },
  }
})
