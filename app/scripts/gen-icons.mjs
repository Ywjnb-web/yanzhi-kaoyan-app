/**
 * 图标代码生成器
 * ---------------------------------------------------------------
 * 线框图里的图标是内联 SVG。小程序端 <image> 无法继承 currentColor，
 * 因此这里把每个图标按「形状 × 颜色」预渲染成 base64 data URI，
 * 生成 utils/icons.uts（Map<string, string>），组件通过 ICONS.get(name) 取用。
 *
 * 用法：pnpm gen:icons
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const projectRoot = resolve(here, '..')

const SIZE = 18
const VB = `0 0 ${SIZE} ${SIZE}`

const wrap = (inner, size = SIZE) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" fill="none">${inner}</svg>`

const line = (d, color, w = 1.6) =>
  `<path d="${d}" stroke="${color}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`

/* ── 通用图标 ─────────────────────────────────────────────── */
const ICON_BACK = wrap(line('M11.5 3.5 6 9l5.5 5.5', '#1F2329'))

const ICON_CLOSE = wrap(
  '<path d="M4.5 4.5 13.5 13.5M13.5 4.5 4.5 13.5" stroke="#1F2329" stroke-width="1.6" stroke-linecap="round"/>',
)

const ICON_CHEVRON = wrap(line('M6.8 3.6 11.2 9 6.8 14.4', '#A6ABB3', 1.5))

/* ── 底部 Tab（灰 / 白两套） ───────────────────────────────── */
const home = (c) =>
  wrap(line('M2.6 7.4 9 2.6l6.4 4.8v7.1a.9.9 0 0 1-.9.9H3.5a.9.9 0 0 1-.9-.9V7.4Z', c, 1.4))

const doc = (c) =>
  wrap(
    `<rect x="3" y="2.5" width="12" height="13" rx="2" stroke="${c}" stroke-width="1.4"/>` +
      `<path d="M6 7h6M6 10h6M6 12.6h3" stroke="${c}" stroke-width="1.4" stroke-linecap="round"/>`,
  )

const user = (c) =>
  wrap(
    `<circle cx="9" cy="6.3" r="3.1" stroke="${c}" stroke-width="1.4"/>` +
      `<path d="M3.5 15.2c.6-2.6 2.8-4.1 5.5-4.1s4.9 1.5 5.5 4.1" stroke="${c}" stroke-width="1.4" stroke-linecap="round"/>`,
  )

const magnifier = (c, w = 1.4) =>
  wrap(
    `<circle cx="8" cy="8" r="5" stroke="${c}" stroke-width="${w}"/>` +
      `<path d="M11.8 11.8 15.5 15.5" stroke="${c}" stroke-width="${w}" stroke-linecap="round"/>`,
  )

/* ── 状态图标 ─────────────────────────────────────────────── */
const ICON_CHECK_CIRCLE = wrap(
  '<circle cx="9" cy="9" r="7.5" fill="#1F2329"/>' +
    '<path d="M5.6 9.2 7.9 11.5 12.4 6.6" stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
)

const ICON_STEP_ACTIVE = wrap(
  '<circle cx="9" cy="9" r="7" stroke="#1F2329" stroke-width="1.6"/>' +
    '<circle cx="9" cy="9" r="3" fill="#1F2329"/>',
)

const ICON_STEP_IDLE = wrap('<circle cx="9" cy="9" r="7" stroke="#C9CDD4" stroke-width="1.6"/>')

const ICON_TICK = wrap(
  '<path d="M2.4 6.4 4.8 8.8 9.6 3.6" stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
  12,
)

const ICON_INFO = wrap(
  '<circle cx="9" cy="9" r="7.5" stroke="#646A73" stroke-width="1.4"/>' +
    '<path d="M9 8v4.2" stroke="#646A73" stroke-width="1.5" stroke-linecap="round"/>' +
    '<circle cx="9" cy="5.7" r="1" fill="#646A73"/>',
)

const ALL = {
  back: ICON_BACK,
  close: ICON_CLOSE,
  chevron: ICON_CHEVRON,
  tick: ICON_TICK,
  checkCircle: ICON_CHECK_CIRCLE,
  stepActive: ICON_STEP_ACTIVE,
  stepIdle: ICON_STEP_IDLE,
  info: ICON_INFO,

  searchMuted: magnifier('#A6ABB3', 1.5),
  searchInk: magnifier('#646A73', 1.4),
  searchWhite: magnifier('#FFFFFF', 1.4),

  homeMuted: home('#646A73'),
  homeWhite: home('#FFFFFF'),
  docMuted: doc('#646A73'),
  docWhite: doc('#FFFFFF'),
  userMuted: user('#646A73'),
  userWhite: user('#FFFFFF'),
}

const entries = Object.entries(ALL)
  .map(([key, svg]) => {
    const b64 = Buffer.from(svg, 'utf8').toString('base64')
    return `ICONS.set('${key}', 'data:image/svg+xml;base64,${b64}')`
  })
  .join('\n')

const out = `/**
 * 图标资源表 —— 由 scripts/gen-icons.mjs 自动生成，请勿手工修改。
 * 重新生成：pnpm gen:icons
 *
 * 说明：小程序端 <image> 不继承 currentColor，所以每个图标按颜色预渲染为
 * base64 data URI。同名图标存在 Muted（#646A73 未选中）与 White（#FFFFFF 选中）
 * 等变体，取用时按语义选择。
 */
export const ICONS: Map<string, string> = new Map<string, string>()

${entries}
`

mkdirSync(resolve(projectRoot, 'utils'), { recursive: true })
writeFileSync(resolve(projectRoot, 'utils/icons.uts'), out, 'utf8')

console.log(`[gen-icons] 已生成 ${entries.split('\n').length} 个图标 -> utils/icons.uts`)
