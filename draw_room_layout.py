#!/usr/bin/env python3
"""
绘制School.tscn中所有RoomArea的布局图，输出为PNG
"""

import re
from PIL import Image, ImageDraw, ImageFont

def parse_school_tscn(filepath):
    """解析School.tscn文件，提取RoomArea信息"""
    
    room_areas = []
    shape_sizes = {}
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    # 第一步：提取所有RectangleShape2D的size
    shape_pattern = r'\[sub_resource type="RectangleShape2D" id="([^"]+)"\]\nsize = Vector2\(([^,]+),\s*([^)]+)\)'
    for match in re.finditer(shape_pattern, content):
        shape_id = match.group(1)
        width = float(match.group(2))
        height = float(match.group(3))
        shape_sizes[shape_id] = (width, height)
    
    # 第二步：提取所有RoomArea
    lines = content.split('\n')
    current_room = None
    
    for i, line in enumerate(lines):
        if '[node name="RoomArea_' in line:
            match = re.search(r'\[node name="([^"]+)"', line)
            if match:
                current_room = {
                    'node_name': match.group(1),
                    'room_name': None,
                    'x': 0,
                    'y': 0,
                    'width': 0,
                    'height': 0
                }
        
        if current_room:
            if 'room_name = ' in line:
                match = re.search(r'room_name = "([^"]+)"', line)
                if match:
                    current_room['room_name'] = match.group(1)
            
            if 'position = Vector2(' in line and 'sit_position' not in line:
                match = re.search(r'position = Vector2\(([^,]+),\s*([^)]+)\)', line)
                if match:
                    current_room['x'] = float(match.group(1))
                    current_room['y'] = float(match.group(2))
            
            if 'shape = SubResource(' in line:
                match = re.search(r'shape = SubResource\("([^"]+)"\)', line)
                if match:
                    shape_id = match.group(1)
                    if shape_id in shape_sizes:
                        current_room['width'] = shape_sizes[shape_id][0]
                        current_room['height'] = shape_sizes[shape_id][1]
                
                if current_room['room_name'] and current_room['width'] > 0:
                    room_areas.append(current_room.copy())
                current_room = None
    
    return room_areas

def draw_png_layout(room_areas, output_path='room_layout.png'):
    """绘制房间布局图为PNG"""
    
    # 场景尺寸
    scene_width = 1184
    scene_height = 640
    
    # 缩放因子 (让图片更大一些，便于查看)
    scale = 1.5
    img_width = int(scene_width * scale)
    img_height = int(scene_height * scale)
    
    # 创建图片 (灰色背景)
    img = Image.new('RGB', (img_width, img_height), color='#CCCCCC')
    draw = ImageDraw.Draw(img)
    
    # 颜色映射 (每个房间不同的颜色)
    colors = {
        '教室（主教学区）': '#FF6B6B',    # 红色
        '教室（小组讨论区）': '#4ECDC4',  # 青色
        '食堂': '#45B7D1',                # 蓝色
        '走廊': '#96CEB4',                # 浅绿
        '走廊2': '#88D8B0',               # 绿色
        '走廊3': '#98D8C8',               # 薄荷绿
        '体育馆': '#FFEAA7',              # 黄色
    }
    
    # 绘制每个RoomArea
    for room in room_areas:
        x = (room['x'] - room['width']/2) * scale
        y = (room['y'] - room['height']/2) * scale
        width = room['width'] * scale
        height = room['height'] * scale
        
        color = colors.get(room['room_name'], '#999999')
        
        # 绘制填充矩形
        draw.rectangle([x, y, x + width, y + height], fill=color, outline='black', width=2)
        
        # 尝试添加文字标签
        try:
            # 使用默认字体
            font = ImageFont.load_default()
            
            # 计算文字位置 (居中)
            text = room['room_name']
            bbox = draw.textbbox((0, 0), text, font=font)
            text_width = bbox[2] - bbox[0]
            text_height = bbox[3] - bbox[1]
            
            text_x = x + width/2 - text_width/2
            text_y = y + height/2 - text_height/2
            
            # 只在矩形足够大时显示文字
            if width > 60 and height > 30:
                draw.text((text_x, text_y), text, fill='black', font=font)
        except:
            pass
    
    # 保存图片
    img.save(output_path)
    print(f"Layout saved to: {output_path}")
    print(f"Image size: {img_width}×{img_height}")
    
    # 打印统计信息
    total_area = scene_width * scene_height
    covered_area = sum(r['width'] * r['height'] for r in room_areas)
    coverage = covered_area / total_area * 100
    
    print(f"\n场景尺寸: {scene_width}×{scene_height} = {total_area} px²")
    print(f"覆盖面积: {covered_area:.0f} px² ({coverage:.1f}%)")
    print(f"房间数量: {len(room_areas)}")
    
    print("\n房间详情:")
    print("-" * 60)
    for room in room_areas:
        area = room['width'] * room['height']
        print(f"  {room['room_name']:<20} | ({room['x']:.1f}, {room['y']:.1f}) | {room['width']:.0f}×{room['height']:.0f}")
    print("-" * 60)

if __name__ == '__main__':
    import sys
    
    if len(sys.argv) > 1:
        tscn_path = sys.argv[1]
    else:
        tscn_path = '/Users/yuke/Desktop/Godot Microverse/Microverse/scene/maps/School.tscn'
    
    if len(sys.argv) > 2:
        output_path = sys.argv[2]
    else:
        output_path = '/Users/yuke/Desktop/Godot Microverse/Microverse/room_layout.png'
    
    room_areas = parse_school_tscn(tscn_path)
    
    if not room_areas:
        print("No RoomArea found!")
        sys.exit(1)
    
    draw_png_layout(room_areas, output_path)
