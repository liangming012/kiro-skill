#!/usr/bin/env python3
"""
虚拟环境初始化脚本
用法: python setup_venv.py

在 skill 目录下创建 .venv 虚拟环境并安装依赖。
支持 Windows 和 macOS/Linux。
"""
import subprocess
import sys
import os
import platform

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENV_DIR = os.path.join(SKILL_DIR, ".venv")
REQUIREMENTS = ["psd-tools", "Pillow", "playwright"]

IS_WINDOWS = platform.system() == "Windows"


def get_venv_python():
    """获取虚拟环境中的 Python 解释器路径"""
    if IS_WINDOWS:
        return os.path.join(VENV_DIR, "Scripts", "python.exe")
    return os.path.join(VENV_DIR, "bin", "python3")


def get_venv_pip():
    """获取虚拟环境中的 pip 路径"""
    if IS_WINDOWS:
        pip_path = os.path.join(VENV_DIR, "Scripts", "pip.exe")
        if not os.path.exists(pip_path):
            pip_path = os.path.join(VENV_DIR, "Scripts", "pip3.exe")
        return pip_path
    pip_path = os.path.join(VENV_DIR, "bin", "pip3")
    if not os.path.exists(pip_path):
        pip_path = os.path.join(VENV_DIR, "bin", "pip")
    return pip_path


def main():
    # 创建虚拟环境
    if not os.path.exists(VENV_DIR):
        print(f"📦 创建虚拟环境: {VENV_DIR}")
        subprocess.check_call([sys.executable, "-m", "venv", VENV_DIR])
    else:
        print(f"✅ 虚拟环境已存在: {VENV_DIR}")

    # 确定 pip 路径
    pip_path = get_venv_pip()

    # 升级 pip
    print("📦 升级 pip...")
    subprocess.check_call([pip_path, "install", "--upgrade", "pip", "-q"])

    # 安装依赖
    print(f"📦 安装依赖: {', '.join(REQUIREMENTS)}")
    subprocess.check_call([pip_path, "install"] + REQUIREMENTS + ["-q"])

    # 安装 Playwright 浏览器（仅 Chromium）
    python_path = get_venv_python()
    print("📦 安装 Playwright Chromium 浏览器...")
    result_pw = subprocess.run(
        [python_path, "-m", "playwright", "install", "chromium"],
        capture_output=True, text=True
    )
    if result_pw.returncode == 0:
        print("✅ Playwright Chromium 安装完成")
    else:
        print(f"⚠️ Playwright Chromium 安装失败（截图功能将不可用）: {result_pw.stderr.strip()}")

    # 验证安装
    result = subprocess.run(
        [python_path, "-c", "import psd_tools; from PIL import Image; from playwright.sync_api import sync_playwright; print(f'psd-tools {psd_tools.__version__}, Pillow OK, Playwright OK')"],
        capture_output=True, text=True
    )

    if result.returncode == 0:
        print(f"✅ 环境就绪: {result.stdout.strip()}")
        print(f"   Python: {python_path}")
    else:
        print(f"❌ 验证失败: {result.stderr}")
        sys.exit(1)


if __name__ == "__main__":
    main()
