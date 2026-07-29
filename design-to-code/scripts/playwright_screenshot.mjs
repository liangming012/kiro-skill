/**
 * 通用 Playwright 截图脚本（Node.js 版）
 * 用法: node playwright_screenshot.mjs <config_json_path>
 *
 * 根据配置文件执行页面截图，支持全页面截图、局部区域截图、弹窗触发截图。
 *
 * 配置文件结构:
 * {
 *   "url": "http://localhost:5173/page",
 *   "viewport": {"width": 750, "height": 1334},
 *   "output_dir": "./",
 *   "screenshots": [
 *     {"type": "fullpage", "output": "_screenshot_result_temp.png"},
 *     {"type": "locator", "selector": ".header-section", "output": "_screenshot_header_temp.png"},
 *     {"type": "popup", "trigger": "click", "trigger_selector": ".rule-btn", "wait_selector": ".popup-rule", "output": "_screenshot_popup_temp.png"},
 *     {"type": "check_image", "selector": ".banner-img"}
 *   ]
 * }
 */
import { chromium } from 'playwright';
import { readFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';

const configPath = process.argv[2];
if (!configPath) {
  console.error('用法: node playwright_screenshot.mjs <config_json_path>');
  process.exit(1);
}

if (!existsSync(configPath)) {
  console.error(`错误: 配置文件不存在 - ${configPath}`);
  process.exit(1);
}

const config = JSON.parse(readFileSync(configPath, 'utf-8'));
const { url, viewport = { width: 750, height: 1334 }, output_dir = './', screenshots = [] } = config;

if (!screenshots.length) {
  screenshots.push({ type: 'fullpage', output: '_screenshot_result_temp.png' });
}

if (!existsSync(output_dir)) {
  mkdirSync(output_dir, { recursive: true });
}

const results = [];
const pageErrors = [];
let browser;

try {
  browser = await chromium.launch();
  const page = await browser.newPage();

  // 设置视口
  await page.setViewportSize(viewport);
  console.log(`📐 视口尺寸: ${viewport.width}×${viewport.height}`);

  // 监听页面错误
  page.on('pageerror', err => pageErrors.push(`JS错误: ${err.message}`));
  page.on('requestfailed', req => pageErrors.push(`资源加载失败: ${req.url()}`));

  // 导航到页面
  console.log(`🌐 正在加载: ${url}`);
  const response = await page.goto(url, { timeout: 30000 });
  if (!response || response.status() >= 400) {
    const status = response ? response.status() : '无响应';
    console.error(`❌ 页面加载失败，状态码: ${status}`);
    process.exit(1);
  }

  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(2000);
  console.log('✅ 页面加载完成');

  // 执行截图任务
  const total = screenshots.length;
  for (let i = 0; i < total; i++) {
    const shot = screenshots[i];
    const shotType = shot.type || 'fullpage';
    const outputPath = join(output_dir, shot.output || `_screenshot_${i}_temp.png`);

    try {
      if (shotType === 'fullpage') {
        await page.screenshot({ path: outputPath, fullPage: true });
        console.log(`[${i + 1}/${total}] ✅ 全页面截图: ${shot.output}`);

      } else if (shotType === 'locator') {
        const locator = page.locator(shot.selector);
        const count = await locator.count();
        if (count === 0) {
          console.log(`[${i + 1}/${total}] ⚠️ 元素不存在: ${shot.selector}，跳过`);
          results.push({ output: shot.output, status: 'SKIP', reason: `元素不存在: ${shot.selector}` });
          continue;
        }
        await locator.screenshot({ path: outputPath });
        const box = await locator.boundingBox();
        const sizeInfo = box ? ` (${Math.round(box.width)}×${Math.round(box.height)})` : '';
        console.log(`[${i + 1}/${total}] ✅ 局部截图: ${shot.output}${sizeInfo}`);

      } else if (shotType === 'popup') {
        const trigger = shot.trigger || 'click';

        if (trigger === 'click') {
          await page.click(shot.trigger_selector);
        } else if (trigger === 'evaluate') {
          await page.evaluate(shot.evaluate_script);
        }

        if (shot.wait_selector) {
          await page.waitForSelector(shot.wait_selector, { state: 'visible', timeout: 5000 });
        }
        await page.waitForTimeout(500);

        await page.screenshot({ path: outputPath, fullPage: true });
        console.log(`[${i + 1}/${total}] ✅ 弹窗截图: ${shot.output}`);

        // 关闭弹窗
        if (shot.close_selector) {
          await page.click(shot.close_selector);
        } else {
          await page.keyboard.press('Escape');
        }
        await page.waitForTimeout(300);

      } else if (shotType === 'check_image') {
        const loaded = await page.evaluate((selector) => {
          const el = document.querySelector(selector);
          if (!el) return { exists: false };
          if (el.tagName === 'IMG') {
            return { exists: true, loaded: el.complete && el.naturalWidth > 0, width: el.naturalWidth, height: el.naturalHeight };
          }
          const bg = getComputedStyle(el).backgroundImage;
          return { exists: true, loaded: bg && bg !== 'none', bg };
        }, shot.selector);
        console.log(`[${i + 1}/${total}] 🔍 图片检查 ${shot.selector}: ${JSON.stringify(loaded)}`);
        results.push({ output: shot.output || '', status: loaded.loaded ? 'OK' : 'FAIL', data: loaded });
        continue;
      }

      results.push({ output: shot.output, status: 'OK' });

    } catch (err) {
      console.error(`[${i + 1}/${total}] ❌ 截图失败 (${shot.output}): ${err.message}`);
      results.push({ output: shot.output, status: 'ERROR', error: err.message });
    }
  }

  await browser.close();

} catch (err) {
  console.error(`❌ 执行失败: ${err.message}`);
  if (browser) await browser.close();
  process.exit(1);
}

// 输出页面错误
if (pageErrors.length > 0) {
  console.warn(`\n⚠️ 页面存在 ${pageErrors.length} 个错误:`);
  pageErrors.slice(0, 10).forEach(e => console.warn(`  - ${e}`));
  if (pageErrors.length > 10) {
    console.warn(`  ... 还有 ${pageErrors.length - 10} 个错误`);
  }
}

// 输出结果摘要
const okCount = results.filter(r => r.status === 'OK').length;
const failCount = results.filter(r => r.status !== 'OK').length;
console.log(`\n📊 截图完成: ${okCount} 成功, ${failCount} 失败/跳过`);
