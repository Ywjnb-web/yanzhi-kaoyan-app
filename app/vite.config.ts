import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import uni from '@dcloudio/vite-plugin-uni'
import { WeappTailwindcss } from 'weapp-tailwindcss/vite'
import { uniAppX } from 'weapp-tailwindcss/presets'

// HBuilderX 启动构建时会改变 process.cwd()，所以项目根目录必须从配置文件位置推导，
// 不能依赖 cwd，也不能硬编码机器路径。
const projectRoot = dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  plugins: [
    uni(),
    WeappTailwindcss(
      uniAppX({
        base: projectRoot,
        // Tailwind CSS 4 采用 CSS-first 配置，需要一个真实的 CSS 入口文件，
        // 由 App.uvue 通过 @import './main.css' 引入。
        cssEntries: [resolve(projectRoot, 'main.css')],
        // 设计稿为 px，统一换算为 rpx 以适配小程序屏幕。
        rem2rpx: true,
      }),
    ),
  ],
})
