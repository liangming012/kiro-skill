#!/usr/bin/env python3
"""
多语种图片尺寸统一工具

功能：
1. trim   - 裁剪图片四周透明区域（尺寸偏大时使用）
2. expand - 扩展画布到指定尺寸，原图居中放置（尺寸偏小时使用）
3. unify  - 批量统一多张图片到相同尺寸（取最大宽高，各图居中放置）

用法：
  python img_unify_size.py trim <图片路径> [--target-width W] [--target-height H]
  python img_unify_size.py expand <图片路径> --target-width W --target-height H
  python img_unify_size.py unify <图片路径1> <图片路径2> ... [--target-width W] [--target-height H]

参数说明：
  trim:
    - 裁剪图片四周透明区域
    - 如果指定了 --target-width/--target-height，裁剪后会进一步将图片放到目标尺寸画布居中
    - 如果裁剪后仍超出目标尺寸，输出警告信息

  expand:
    - 创建目标尺寸的透明画布，将原图居中放置
    - 必须指定 --target-width 和 --target-height

  unify:
    - 如果指定了 --target-width/--target-height，使用指定尺寸作为统一画布
    - 如果未指定，自动取所有图片中的最大宽度和最大高度作为统一尺寸
    - 每张图片先裁剪透明区域，再居中放置到统一画布上
"""

import sys
import os
import argparse
from PIL import Image


def trim_image(img_path, target_w=None, target_h=None):
    """裁剪图片透明区域，可选择性适配到目标尺寸"""
    img = Image.open(img_path).convert('RGBA')
    original_size = (img.width, img.height)

    # 获取非透明区域边界
    bbox = img.getbbox()
    if not bbox:
        print(f'⚠️ 图片内容为空（全透明）: {img_path}')
        return

    trimmed = img.crop(bbox)
    print(f'📐 裁剪透明区域: {original_size[0]}×{original_size[1]} → {trimmed.width}×{trimmed.height}')
    print(f'   裁剪了: 左{bbox[0]}px, 上{bbox[1]}px, 右{original_size[0]-bbox[2]}px, 下{original_size[1]-bbox[3]}px')

    # 如果指定了目标尺寸
    if target_w and target_h:
        if trimmed.width <= target_w and trimmed.height <= target_h:
            # 裁剪后尺寸 ≤ 目标，居中放置到目标画布
            canvas = Image.new('RGBA', (target_w, target_h), (0, 0, 0, 0))
            offset_x = (target_w - trimmed.width) // 2
            offset_y = (target_h - trimmed.height) // 2
            canvas.paste(trimmed, (offset_x, offset_y), trimmed)
            canvas.save(img_path)
            print(f'✅ 裁剪 + 居中放置完成: {target_w}×{target_h}')
        else:
            # 裁剪后仍超出目标
            trimmed.save(img_path)
            print(f'⚠️ 裁剪透明区域后仍超出目标尺寸: {trimmed.width}×{trimmed.height} > {target_w}×{target_h}')
            print(f'   需要通过修改代码兼容不同尺寸，或与设计师确认调整设计稿')
    else:
        # 未指定目标尺寸，直接保存裁剪结果
        trimmed.save(img_path)
        print(f'✅ 裁剪完成: {trimmed.width}×{trimmed.height}')


def expand_image(img_path, target_w, target_h):
    """扩展画布到目标尺寸，原图居中放置"""
    img = Image.open(img_path).convert('RGBA')
    original_size = (img.width, img.height)

    if img.width == target_w and img.height == target_h:
        print(f'✅ {os.path.basename(img_path)}: 尺寸已是 {target_w}×{target_h}，无需处理')
        return

    canvas = Image.new('RGBA', (target_w, target_h), (0, 0, 0, 0))
    offset_x = (target_w - img.width) // 2
    offset_y = (target_h - img.height) // 2
    canvas.paste(img, (offset_x, offset_y), img)
    canvas.save(img_path)
    print(f'✅ {os.path.basename(img_path)}: {original_size[0]}×{original_size[1]} → {target_w}×{target_h}（居中放置）')


def unify_images(img_paths, target_w=None, target_h=None):
    """批量统一多张图片尺寸"""
    if not img_paths:
        print('❌ 未提供图片路径')
        return

    # 先对所有图片裁剪透明区域，获取实际内容尺寸
    trimmed_sizes = []
    trimmed_images = []

    print('📏 第一步：裁剪各图片透明区域，获取实际内容尺寸\n')
    for path in img_paths:
        if not os.path.exists(path):
            print(f'⚠️ 文件不存在，跳过: {path}')
            continue

        img = Image.open(path).convert('RGBA')
        bbox = img.getbbox()
        if bbox:
            trimmed = img.crop(bbox)
            print(f'   {os.path.basename(path)}: {img.width}×{img.height} → {trimmed.width}×{trimmed.height}（裁剪透明区域）')
        else:
            print(f'   ⚠️ {os.path.basename(path)}: 内容为空（全透明），跳过')
            continue

        trimmed_sizes.append((trimmed.width, trimmed.height))
        trimmed_images.append((path, trimmed))

    if not trimmed_images:
        print('❌ 没有有效的图片可处理')
        return

    # 确定统一尺寸
    if target_w and target_h:
        unified_w, unified_h = target_w, target_h
        print(f'\n🎯 使用指定的统一尺寸: {unified_w}×{unified_h}')
    else:
        unified_w = max(s[0] for s in trimmed_sizes)
        unified_h = max(s[1] for s in trimmed_sizes)
        print(f'\n🎯 自动计算统一尺寸（取最大宽高）: {unified_w}×{unified_h}')

    # 将每张图片居中放置到统一画布
    print(f'\n📐 第二步：各图片居中放置到 {unified_w}×{unified_h} 画布\n')
    for path, trimmed in trimmed_images:
        canvas = Image.new('RGBA', (unified_w, unified_h), (0, 0, 0, 0))
        offset_x = (unified_w - trimmed.width) // 2
        offset_y = (unified_h - trimmed.height) // 2
        canvas.paste(trimmed, (offset_x, offset_y), trimmed)
        canvas.save(path)
        print(f'   ✅ {os.path.basename(path)}: {trimmed.width}×{trimmed.height} → {unified_w}×{unified_h}')

    print(f'\n🎉 完成！所有 {len(trimmed_images)} 张图片已统一为 {unified_w}×{unified_h}')


def main():
    parser = argparse.ArgumentParser(description='多语种图片尺寸统一工具')
    subparsers = parser.add_subparsers(dest='command', help='操作命令')

    # trim 子命令
    trim_parser = subparsers.add_parser('trim', help='裁剪图片四周透明区域')
    trim_parser.add_argument('image', help='图片路径')
    trim_parser.add_argument('--target-width', type=int, help='目标宽度（可选，裁剪后适配到此尺寸）')
    trim_parser.add_argument('--target-height', type=int, help='目标高度（可选，裁剪后适配到此尺寸）')

    # expand 子命令
    expand_parser = subparsers.add_parser('expand', help='扩展画布到指定尺寸，原图居中')
    expand_parser.add_argument('image', help='图片路径')
    expand_parser.add_argument('--target-width', type=int, required=True, help='目标宽度')
    expand_parser.add_argument('--target-height', type=int, required=True, help='目标高度')

    # unify 子命令
    unify_parser = subparsers.add_parser('unify', help='批量统一多张图片尺寸')
    unify_parser.add_argument('images', nargs='+', help='图片路径列表')
    unify_parser.add_argument('--target-width', type=int, help='指定统一宽度（可选，不指定则取最大值）')
    unify_parser.add_argument('--target-height', type=int, help='指定统一高度（可选，不指定则取最大值）')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == 'trim':
        trim_image(args.image, args.target_width, args.target_height)
    elif args.command == 'expand':
        expand_image(args.image, args.target_width, args.target_height)
    elif args.command == 'unify':
        unify_images(args.images, args.target_width, args.target_height)


if __name__ == '__main__':
    main()
