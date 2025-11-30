#!/usr/bin/env python3
"""
从 CloudWatch Logs 提取性能指标并保存为 CSV 文件
"""

import subprocess
import re
import sys
import csv
from datetime import datetime
from collections import defaultdict

REGION = "us-east-2"
LAMBDA_NAME = "pixels-scan-worker"
LOG_GROUP = f"/aws/lambda/{LAMBDA_NAME}"
OUTPUT_FILE = "./performance-metrics/scan_performance_metrics.csv"

print("")
print("╔════════════════════════════════════════════════════════════╗")
print("║    从 CloudWatch Logs 提取性能指标为 CSV                  ║")
print("╚════════════════════════════════════════════════════════════╝")
print("")
print(f"Log Group: {LOG_GROUP}")
print(f"输出文件: {OUTPUT_FILE}")
print("")

# Run aws logs tail command
try:
    result = subprocess.run(
        ["aws", "logs", "tail", LOG_GROUP, "--since", "24h", "--region", REGION, "--format", "short"],
        capture_output=True,
        text=True,
        check=True
    )
except subprocess.CalledProcessError as e:
    print(f"❌ 错误: 无法读取日志")
    print(f"   错误信息: {e.stderr}")
    sys.exit(1)

# Parse logs and extract metrics
metrics_data = defaultdict(dict)
current_request_id = None

for line in result.stdout.split('\n'):
    if not line.strip():
        continue
    
    # Extract request ID
    request_match = re.search(r'\[([0-9a-f-]+)\]', line)
    if request_match:
        current_request_id = request_match.group(1)
    
    # Extract timestamp
    timestamp_match = re.search(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})', line)
    if timestamp_match and current_request_id:
        try:
            dt = datetime.strptime(timestamp_match.group(1), '%Y-%m-%dT%H:%M:%S')
            timestamp_ms = int(dt.timestamp() * 1000)
            metrics_data[current_request_id]['timestamp'] = timestamp_ms
        except:
            pass
    
    # Extract Four-Stage Performance Metrics
    if 'Four-Stage Performance Metrics' in line and current_request_id:
        read_match = re.search(r'READ=(\d+)', line)
        compute_match = re.search(r'COMPUTE=(\d+)', line)
        cache_match = re.search(r'WRITE_CACHE=(\d+)', line)
        file_match = re.search(r'WRITE_FILE=(\d+)', line)
        
        if read_match:
            metrics_data[current_request_id]['read'] = int(read_match.group(1))
        if compute_match:
            metrics_data[current_request_id]['compute'] = int(compute_match.group(1))
        if cache_match:
            metrics_data[current_request_id]['cache'] = int(cache_match.group(1))
        if file_match:
            metrics_data[current_request_id]['file'] = int(file_match.group(1))
    
    # Extract Percentages
    if 'Percentages:' in line and current_request_id:
        compute_pct_match = re.search(r'COMPUTE=([0-9.]+)%', line)
        cache_pct_match = re.search(r'WRITE_CACHE=([0-9.]+)%', line)
        file_pct_match = re.search(r'WRITE_FILE=([0-9.]+)%', line)
        s3_pct_match = re.search(r'S3 Storage=([0-9.]+)%', line)
        
        if compute_pct_match:
            metrics_data[current_request_id]['compute_pct'] = float(compute_pct_match.group(1))
        if cache_pct_match:
            metrics_data[current_request_id]['cache_pct'] = float(cache_pct_match.group(1))
        if file_pct_match:
            metrics_data[current_request_id]['file_pct'] = float(file_pct_match.group(1))
        if s3_pct_match:
            metrics_data[current_request_id]['s3_pct'] = float(s3_pct_match.group(1))

# Write to CSV
import os
os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)

with open(OUTPUT_FILE, 'w', newline='') as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow([
        'Timestamp', 'WorkerType', 'ReadTimeMs', 'ComputeTimeMs',
        'WriteCacheTimeMs', 'WriteFileTimeMs', 'ComputePct',
        'WriteCachePct', 'WriteFilePct', 'S3StoragePct'
    ])
    
    count = 0
    zero_count = 0
    for request_id, data in metrics_data.items():
        if 'read' in data and 'compute' in data:
            # 检查是否全为 0（可能是失败的调用或测试）
            read = data.get('read', 0)
            compute = data.get('compute', 0)
            cache = data.get('cache', 0)
            file = data.get('file', 0)
            
            # 跳过全为 0 的记录（这些通常是失败的调用或测试）
            if read == 0 and compute == 0 and cache == 0 and file == 0:
                zero_count += 1
                continue
            
            writer.writerow([
                data.get('timestamp', 0),
                'ScanWorker',
                read,
                compute,
                cache,
                file,
                f"{data.get('compute_pct', 0.0):.2f}",
                f"{data.get('cache_pct', 0.0):.2f}",
                f"{data.get('file_pct', 0.0):.2f}",
                f"{data.get('s3_pct', 0.0):.2f}"
            ])
            count += 1

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
if count > 0:
    print(f"✅ 提取成功: {count} 条有效记录")
    if zero_count > 0:
        print(f"⚠️  已过滤: {zero_count} 条全为 0 的记录（可能是失败的调用或测试）")
    print(f"")
    print(f"文件位置: {OUTPUT_FILE}")
    print(f"")
    print("前 5 行数据:")
    with open(OUTPUT_FILE, 'r') as f:
        lines = f.readlines()
        for i, line in enumerate(lines[:6]):  # Header + 5 data rows
            print(f"  {line.strip()}")
else:
    print("⚠️  未提取到有效数据")
    if zero_count > 0:
        print(f"   发现 {zero_count} 条全为 0 的记录（可能是失败的调用）")
    print("   提示: 可能需要先调用 Lambda 函数生成日志")
print("")

