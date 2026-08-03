#!/usr/bin/env python3
"""
通用 Playwright 截图脚本
用法: python3 playwright_screenshot.py <config_json_path>

根据配置文件执行页面截图，支持全页面截图、局部区域截图、弹窗触发截图。

配置文件结构:
{
  "url": "http://localhost:5173/page",
  "viewport": {"width": 750, "height": 1334},
  "output_dir": "./",
  "screenshots": [
    {
      "type": "fullpage",
      "output": "_screenshot_result_temp.png"
    },
    {
      "type": "locator",
      "selector": ".header-section",
      "output": "_screenshot_header_temp.png"
    },
    {
      "type": "popup",
      "trigger": "click",
      "trigger_selector": ".rule-btn",
      "wait_selector": ".popup-rule",
      "output": "_screenshot_popup_rule_temp.png"
    },
    {
      "type": "popup",
      "trigger": "evaluate",
      "evaluate_script": "document.querySelector('#app').__vue__.showPopup = true",
      "wait_selector": ".popup-modal",
      "output": "_screenshot_popup_temp.png"
    }
  ]
}
"""
import json
import sys
import os

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("❌ playwright 未安装，请先执行:")
    print("   ~/.kiro/skills/design-to-code/.venv/Scripts/pip install playwright")
    print("   ~/.kiro/skills/design-to-code/.venv/Scripts/python -m playwright install chromium")
    sys.exit(1)


def take_screenshots(config):
    url = config["url"]
    viewport = config.get("viewport", {"width": 750, "height": 1334})
    output_dir = config.get("output_dir", "./")
    screenshots = config.get("screenshots", [])

    if not screenshots:
        screenshots = [{"type": "fullpage", "output": "_screenshot_result_temp.png"}]

    os.makedirs(output_dir, exist_ok=True)
    results = []
    page_errors = []

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()

        # 设置视口
        page.set_viewport_size(viewport)
        print(f"📐 视口尺寸: {viewport['width']}×{viewport['height']}")

        # 监听页面错误
        page.on("pageerror", lambda err: page_errors.append(f"JS错误: {err}"))
        page.on("requestfailed", lambda req: page_errors.append(f"资源加载失败: {req.url}"))

        # 导航到页面
        print(f"🌐 正在加载: {url}")
        response = page.goto(url, timeout=30000)
        if not response or response.status >= 400:
            status = response.status if response else "无响应"
            print(f"❌ 页面加载失败，状态码: {status}")
            browser.close()
            sys.exit(1)

        page.wait_for_load_state("networkidle")
        page.wait_for_timeout(2000)
        print("✅ 页面加载完成")

        # 执行截图任务
        total = len(screenshots)
        for i, shot in enumerate(screenshots, 1):
            shot_type = shot.get("type", "fullpage")
            output_path = os.path.join(output_dir, shot["output"])

            try:
                if shot_type == "fullpage":
                    page.screenshot(path=output_path, full_page=True)
                    print(f"[{i}/{total}] ✅ 全页面截图: {shot['output']}")

                elif shot_type == "locator":
                    selector = shot["selector"]
                    locator = page.locator(selector)
                    if locator.count() == 0:
                        print(f"[{i}/{total}] ⚠️ 元素不存在: {selector}，跳过")
                        results.append({"output": shot["output"], "status": "SKIP", "reason": f"元素不存在: {selector}"})
                        continue
                    locator.screenshot(path=output_path)
                    box = locator.bounding_box()
                    size_info = f" ({int(box['width'])}×{int(box['height'])})" if box else ""
                    print(f"[{i}/{total}] ✅ 局部截图: {shot['output']}{size_info}")

                elif shot_type == "popup":
                    trigger = shot.get("trigger", "click")
                    wait_selector = shot.get("wait_selector")

                    if trigger == "click":
                        page.click(shot["trigger_selector"])
                    elif trigger == "evaluate":
                        page.evaluate(shot["evaluate_script"])

                    if wait_selector:
                        page.wait_for_selector(wait_selector, state="visible", timeout=5000)
                    page.wait_for_timeout(500)

                    page.screenshot(path=output_path, full_page=True)
                    print(f"[{i}/{total}] ✅ 弹窗截图: {shot['output']}")

                    # 关闭弹窗（尝试点击遮罩或按 ESC）
                    close_selector = shot.get("close_selector")
                    if close_selector:
                        page.click(close_selector)
                    else:
                        page.keyboard.press("Escape")
                    page.wait_for_timeout(300)

                elif shot_type == "check_image":
                    # 检查图片是否加载成功
                    selector = shot["selector"]
                    locator = page.locator(selector)
                    if locator.count() == 0:
                        print(f"[{i}/{total}] ⚠️ 图片元素不存在: {selector}")
                        results.append({"output": shot.get("output", ""), "status": "FAIL", "data": {"exists": False}})
                        continue
                    # 先滚动到元素可见区域（处理懒加载场景）
                    locator.first.scroll_into_view_if_needed()
                    page.wait_for_timeout(500)
                    loaded = locator.first.evaluate("""el => {
                        if (el.tagName === 'IMG') {
                            return { exists: true, loaded: el.complete && el.naturalWidth > 0, width: el.naturalWidth, height: el.naturalHeight };
                        }
                        const bg = getComputedStyle(el).backgroundImage;
                        return { exists: true, loaded: bg && bg !== 'none', bg: bg };
                    }""")
                    print(f"[{i}/{total}] \U0001f50d 图片检查 {selector}: {json.dumps(loaded)}")
                    results.append({"output": shot.get("output", ""), "status": "OK" if loaded.get("loaded") else "FAIL", "data": loaded})
                    continue

                results.append({"output": shot["output"], "status": "OK"})

            except Exception as e:
                print(f"[{i}/{total}] ❌ 截图失败 ({shot['output']}): {e}")
                results.append({"output": shot["output"], "status": "ERROR", "error": str(e)})

        browser.close()

    # 输出页面错误
    if page_errors:
        print(f"\n⚠️ 页面存在 {len(page_errors)} 个错误:")
        for e in page_errors[:10]:
            print(f"  - {e}")
        if len(page_errors) > 10:
            print(f"  ... 还有 {len(page_errors) - 10} 个错误")

    # 输出结果摘要
    ok_count = len([r for r in results if r["status"] == "OK"])
    fail_count = len([r for r in results if r["status"] != "OK"])
    print(f"\n📊 截图完成: {ok_count} 成功, {fail_count} 失败/跳过")

    return results


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法: python3 playwright_screenshot.py <config_json_path>")
        sys.exit(1)

    config_path = sys.argv[1]
    if not os.path.exists(config_path):
        print(f"错误: 配置文件不存在 - {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path, 'r', encoding='utf-8') as f:
        config = json.load(f)

    take_screenshots(config)
