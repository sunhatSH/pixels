#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 PIXELS_LAMBDA_PROJECT_SUMMARY_PPT.md 提取数据并生成图表
"""

import os
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from matplotlib import rcParams

# 确保输出目录存在
OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUTPUT_DIR, exist_ok=True)

# 设置中文字体（macOS 常见字体）
import platform
if platform.system() == 'Darwin':  # macOS
    rcParams['font.sans-serif'] = ['Arial Unicode MS', 'PingFang SC', 'STHeiti', 'SimHei']
else:
    rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'DejaVu Sans']
rcParams['axes.unicode_minus'] = False
# 如果中文显示仍有问题，可以尝试使用英文标签
USE_ENGLISH = False  # 设为 True 使用英文标签

# 设置图表样式
plt.style.use('seaborn-v0_8-darkgrid')
colors = ['#3498db', '#e74c3c', '#2ecc71', '#f39c12', '#9b59b6', '#1abc9c', '#34495e', '#e67e22']

# ============================================================================
# 图表 1: ScanWorker 性能指标时间分布（柱状图）
# ============================================================================

def chart1_performance_timing():
    """四阶段性能指标时间分布"""
    stages = ['READ', 'COMPUTE', 'WRITE_CACHE', 'WRITE_FILE']
    times_ms = [9354, 9718, 13110, 3533]
    colors_stages = ['#3498db', '#e74c3c', '#2ecc71', '#f39c12']
    
    fig, ax = plt.subplots(figsize=(10, 6))
    bars = ax.bar(stages, times_ms, color=colors_stages, alpha=0.8, edgecolor='black', linewidth=1.5)
    
    # 添加数值标签
    for bar, time in zip(bars, times_ms):
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{time} ms\n({time/35715*100:.2f}%)',
                ha='center', va='bottom', fontsize=11, fontweight='bold')
    
    ax.set_ylabel('时间 (毫秒)', fontsize=12, fontweight='bold')
    ax.set_xlabel('执行阶段', fontsize=12, fontweight='bold')
    ax.set_title('ScanWorker 四阶段性能指标时间分布\n(测试数据: 240.2 MiB, 总耗时: 35715 ms)', 
                 fontsize=14, fontweight='bold', pad=20)
    ax.grid(axis='y', alpha=0.3, linestyle='--')
    
    plt.tight_layout()
    output_path = os.path.join(OUTPUT_DIR, 'chart1_performance_timing.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print("✅ 图表1已生成: chart1_performance_timing.png")

# ============================================================================
# 图表 2: 性能指标占比（饼图）
# ============================================================================

def chart2_performance_percentage():
    """性能指标占比饼图"""
    stages = ['READ', 'COMPUTE', 'WRITE_CACHE', 'WRITE_FILE']
    times_ms = [9354, 9718, 13110, 3533]
    percentages = [27.21, 27.21, 36.71, 9.89]
    colors_stages = ['#3498db', '#e74c3c', '#2ecc71', '#f39c12']
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    # 创建饼图，突出显示 WRITE_CACHE（最大占比）
    explode = (0, 0, 0.1, 0)
    
    wedges, texts, autotexts = ax.pie(times_ms, labels=stages, colors=colors_stages,
                                       autopct=lambda pct: f'{pct:.2f}%\n({int(pct/100*35715)} ms)',
                                       explode=explode, shadow=True, startangle=90,
                                       textprops={'fontsize': 11, 'fontweight': 'bold'})
    
    # 美化百分比文本
    for autotext in autotexts:
        autotext.set_color('white')
        autotext.set_fontsize(10)
    
    ax.set_title('ScanWorker performance metrics percentage distribution\n(Total time: 35715 ms)', 
                 fontsize=14, fontweight='bold', pad=20)
    
    plt.tight_layout()
    output_path = os.path.join(OUTPUT_DIR, 'chart2_performance_percentage.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print("✅ 图表2已生成: chart2_performance_percentage.png")

# ============================================================================
# 图表 3: Lambda Workers 部署状态（条形图）
# ============================================================================

def chart3_workers_deployment():
    """Lambda Workers 部署状态"""
    workers = ['Scan', 'Partition', 'Aggregation', 'BroadcastJoin', 
               'PartitionedJoin', 'SortedJoin', 'BroadcastChainJoin',
               'PartitionedChainJoin', 'Sort']
    deployment_status = [1] * 9  # 全部已部署
    colors_status = ['#2ecc71'] * 9  # 绿色表示已部署
    
    fig, ax = plt.subplots(figsize=(12, 6))
    bars = ax.barh(workers, deployment_status, color=colors_status, alpha=0.8, edgecolor='black', linewidth=1.5)
    
    # 添加标签
    for i, (bar, worker) in enumerate(zip(bars, workers)):
        ax.text(0.5, bar.get_y() + bar.get_height()/2, 
                '✅ 已部署', ha='center', va='center',
                fontsize=10, fontweight='bold', color='white')
    
    ax.set_xlabel('部署状态', fontsize=12, fontweight='bold')
    ax.set_title('Lambda Workers 部署状态\n(总计: 9 个 Workers)', 
                 fontsize=14, fontweight='bold', pad=20)
    ax.set_xlim(0, 1.2)
    ax.set_xticks([])
    ax.grid(axis='x', alpha=0.3, linestyle='--')
    
    plt.tight_layout()
    output_path = os.path.join(OUTPUT_DIR, 'chart3_workers_deployment.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print("✅ 图表3已生成: chart3_workers_deployment.png")

# ============================================================================
# 图表 4: 测试结果状态（饼图）
# ============================================================================

def chart4_test_results():
    """测试结果状态分布"""
    labels = ['✅ 成功执行', '⚠️ 需要正确输入']
    sizes = [1, 8]
    colors_status = ['#2ecc71', '#f39c12']
    explode = (0.1, 0)  # 突出显示成功的
    
    fig, ax = plt.subplots(figsize=(10, 8))
    
    wedges, texts, autotexts = ax.pie(sizes, labels=labels, colors=colors_status,
                                       autopct=lambda pct: f'{int(pct/100*9)} 个\n({pct:.1f}%)',
                                       explode=explode, shadow=True, startangle=90,
                                       textprops={'fontsize': 12, 'fontweight': 'bold'})
    
    for autotext in autotexts:
        autotext.set_color('white')
        autotext.set_fontsize(11)
    
    ax.set_title('Lambda Workers 测试结果状态\n(总计: 9 个 Workers)', 
                 fontsize=14, fontweight='bold', pad=20)
    
    plt.tight_layout()
    output_path = os.path.join(OUTPUT_DIR, 'chart4_test_results.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print("✅ 图表4已生成: chart4_test_results.png")

# ============================================================================
# 图表 5: S3 测试文件大小对比（柱状图）
# ============================================================================

def chart5_file_sizes():
    """S3 测试文件大小对比"""
    files = ['large_test_data.pxl', 'example.pxl', 'input.pxl']
    # 转换为 MB 便于比较（790 Bytes = 0.00079 MB）
    sizes_mb = [240.2, 0.00079, 0.00079]
    colors_files = ['#3498db', '#95a5a6', '#95a5a6']
    
    fig, ax = plt.subplots(figsize=(10, 6))
    bars = ax.bar(files, sizes_mb, color=colors_files, alpha=0.8, edgecolor='black', linewidth=1.5)
    
    # 添加数值标签
    for bar, size in zip(bars, sizes_mb):
        height = bar.get_height()
        if size >= 1:
            label = f'{size:.1f} MiB'
        else:
            label = f'{size*1024:.2f} KB'
        ax.text(bar.get_x() + bar.get_width()/2., height,
                label, ha='center', va='bottom', fontsize=11, fontweight='bold')
    
    ax.set_ylabel('文件大小 (MiB)', fontsize=12, fontweight='bold')
    ax.set_xlabel('文件名', fontsize=12, fontweight='bold')
    ax.set_title('S3 测试文件大小对比', fontsize=14, fontweight='bold', pad=20)
    ax.set_yscale('log')  # 使用对数刻度，因为大小差异很大
    ax.grid(axis='y', alpha=0.3, linestyle='--', which='both')
    
    plt.xticks(rotation=15, ha='right')
    plt.tight_layout()
    output_path = os.path.join(OUTPUT_DIR, 'chart5_file_sizes.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print("✅ 图表5已生成: chart5_file_sizes.png")

# ============================================================================
# 图表 6: 内存使用情况（进度条风格）
# ============================================================================

def chart6_memory_usage():
    """Lambda 内存使用情况"""
    used_mb = 3068
    total_mb = 4096
    usage_percent = used_mb / total_mb * 100
    
    fig, ax = plt.subplots(figsize=(10, 4))
    
    # 创建进度条
    bar_width = 0.6
    bar_height = 0.3
    x_pos = 0.2
    
    # 背景条（总内存）
    bg_bar = mpatches.Rectangle((x_pos, 0.4), bar_width, bar_height,
                                 facecolor='#ecf0f1', edgecolor='black', linewidth=2)
    ax.add_patch(bg_bar)
    
    # 使用条（已用内存）
    used_bar = mpatches.Rectangle((x_pos, 0.4), bar_width * (used_mb/total_mb), bar_height,
                                   facecolor='#3498db', edgecolor='black', linewidth=2, alpha=0.9)
    ax.add_patch(used_bar)
    
    # 添加标签
    ax.text(x_pos + bar_width/2, 0.55 + bar_height/2,
            f'内存使用: {used_mb} MB / {total_mb} MB ({usage_percent:.1f}%)',
            ha='center', va='center', fontsize=14, fontweight='bold')
    ax.text(x_pos + bar_width * (used_mb/total_mb)/2, 0.4 + bar_height/2,
            f'{used_mb} MB', ha='center', va='center',
            fontsize=12, fontweight='bold', color='white')
    
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')
    ax.set_title('Lambda 函数内存使用情况\n(pixels-scan-worker)', 
                 fontsize=14, fontweight='bold', pad=20)
    
    plt.tight_layout()
    output_path = os.path.join(OUTPUT_DIR, 'chart6_memory_usage.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print("✅ 图表6已生成: chart6_memory_usage.png")

# ============================================================================
# 图表 7: 执行流程时间线（水平条形图）
# ============================================================================

def chart7_execution_timeline():
    """执行流程时间线"""
    stages = ['READ', 'COMPUTE', 'WRITE_CACHE', 'WRITE_FILE']
    times_ms = [9354, 9718, 13110, 3533]
    colors_stages = ['#3498db', '#e74c3c', '#2ecc71', '#f39c12']
    
    # 计算累积时间
    cumulative = [0]
    for t in times_ms:
        cumulative.append(cumulative[-1] + t)
    
    fig, ax = plt.subplots(figsize=(12, 4))
    
    # 绘制每个阶段
    for i, (stage, time, color) in enumerate(zip(stages, times_ms, colors_stages)):
        ax.barh(0, time, left=cumulative[i], height=0.6, 
                color=color, alpha=0.8, edgecolor='black', linewidth=1.5, label=stage)
        
        # 添加阶段标签
        ax.text(cumulative[i] + time/2, 0,
                f'{stage}\n{time}ms', ha='center', va='center',
                fontsize=10, fontweight='bold', color='white')
    
    # 添加总时间标签
    ax.text(cumulative[-1]/2, -0.5,
            f'总耗时: {cumulative[-1]} ms (约 {cumulative[-1]/1000:.1f} 秒)',
            ha='center', va='top', fontsize=12, fontweight='bold')
    
    ax.set_xlim(0, cumulative[-1])
    ax.set_ylim(-0.8, 0.8)
    ax.set_yticks([])
    ax.set_xlabel('时间 (毫秒)', fontsize=12, fontweight='bold')
    ax.set_title('ScanWorker 执行流程时间线\n(测试数据: 240.2 MiB)', 
                 fontsize=14, fontweight='bold', pad=20)
    ax.legend(loc='upper right', fontsize=10)
    ax.grid(axis='x', alpha=0.3, linestyle='--')
    
    plt.tight_layout()
    output_path = os.path.join(OUTPUT_DIR, 'chart7_execution_timeline.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print("✅ 图表7已生成: chart7_execution_timeline.png")

# ============================================================================
# 图表 8: 存储 I/O 占比分析（堆叠柱状图）
# ============================================================================

def chart8_storage_io():
    """存储 I/O 占比分析"""
    categories = ['计算相关', '存储 I/O']
    compute_time = 9718  # COMPUTE 时间
    storage_time = 9354 + 3533  # READ + WRITE_FILE
    write_cache_time = 13110  # WRITE_CACHE（内存操作）
    
    # 重新分类：存储 I/O vs 计算 vs 内存操作
    storage_io = 9354 + 3533  # READ + WRITE_FILE
    compute = 9718  # COMPUTE
    memory_ops = 13110  # WRITE_CACHE
    
    fig, ax = plt.subplots(figsize=(10, 6))
    
    categories = ['总耗时分布']
    bottom = 0
    colors_stack = ['#3498db', '#e74c3c', '#2ecc71']
    labels_stack = ['存储 I/O (READ+WRITE_FILE)', '计算 (COMPUTE)', '内存操作 (WRITE_CACHE)']
    
    bars = []
    for i, (label, time, color) in enumerate(zip(labels_stack, 
                                                   [storage_io, compute, memory_ops], 
                                                   colors_stack)):
        bar = ax.bar(categories, time, bottom=bottom, label=label, 
                     color=color, alpha=0.8, edgecolor='black', linewidth=1.5)
        bars.append(bar)
        
        # 添加标签
        ax.text(0, bottom + time/2, f'{label}\n{time} ms ({time/35715*100:.1f}%)',
                ha='center', va='center', fontsize=10, fontweight='bold', color='white')
        bottom += time
    
    ax.set_ylabel('时间 (毫秒)', fontsize=12, fontweight='bold')
    ax.set_title('ScanWorker 执行时间分类分析\n存储 I/O vs 计算 vs 内存操作', 
                 fontsize=14, fontweight='bold', pad=20)
    ax.legend(loc='upper right', fontsize=10)
    ax.grid(axis='y', alpha=0.3, linestyle='--')
    
    plt.tight_layout()
    output_path = os.path.join(OUTPUT_DIR, 'chart8_storage_io.png')
    plt.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close()
    print("✅ 图表8已生成: chart8_storage_io.png")

# ============================================================================
# 主函数
# ============================================================================

def main():
    print("=" * 60)
    print("开始生成图表...")
    print("=" * 60)
    
    try:
        chart1_performance_timing()
        chart2_performance_percentage()
        chart3_workers_deployment()
        chart4_test_results()
        chart5_file_sizes()
        chart6_memory_usage()
        chart7_execution_timeline()
        chart8_storage_io()
        
        print("=" * 60)
        print("✅ 所有图表生成完成！")
        print(f"📁 输出目录: pptdata/")
        print("=" * 60)
        
    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()

