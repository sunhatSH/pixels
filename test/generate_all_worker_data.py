#!/usr/bin/env python3
"""
为所有 Pixels Lambda Workers 生成测试数据
生成 CSV 文件并转换为 PXL 格式
"""

import os
import sys
import subprocess
import csv
import random
from pathlib import Path

# Worker 配置：每个 Worker 需要的数据文件数量和 Schema
WORKER_CONFIGS = {
    "ScanWorker": {
        "num_files": 1,
        "schema": "struct<col1:int,col2:string,col3:double>",
        "columns": ["col1", "col2", "col3"],
        "num_rows": 10000
    },
    "BroadcastJoinWorker": {
        "num_files": 2,
        "schema": "struct<col1:int,col2:string,col3:double>",
        "columns": ["col1", "col2", "col3"],
        "num_rows": [5000, 10000]
    },
    "PartitionedJoinWorker": {
        "num_files": 2,
        "schema": "struct<col1:int,col2:string,col3:double>",
        "columns": ["col1", "col2", "col3"],
        "num_rows": [5000, 10000]
    },
    "BroadcastChainJoinWorker": {
        "num_files": 3,
        "schema": "struct<col1:int,col2:string,col3:double>",
        "columns": ["col1", "col2", "col3"],
        "num_rows": [3000, 3000, 10000]
    },
    "PartitionedChainJoinWorker": {
        "num_files": 3,
        "schema": "struct<col1:int,col2:string,col3:double>",
        "columns": ["col1", "col2", "col3"],
        "num_rows": [3000, 3000, 10000]
    },
    "AggregationWorker": {
        "num_files": 1,
        "schema": "struct<group_col:int,agg_col1:double,agg_col2:double>",
        "columns": ["group_col", "agg_col1", "agg_col2"],
        "num_rows": 10000
    },
    "PartitionWorker": {
        "num_files": 1,
        "schema": "struct<col1:int,col2:string,col3:double>",
        "columns": ["col1", "col2", "col3"],
        "num_rows": 10000
    },
    "SortWorker": {
        "num_files": 1,
        "schema": "struct<col1:int,col2:string,col3:double>",
        "columns": ["col1", "col2", "col3"],
        "num_rows": 10000
    },
    "SortedJoinWorker": {
        "num_files": 2,
        "schema": "struct<col1:int,col2:string,col3:double>",
        "columns": ["col1", "col2", "col3"],
        "num_rows": [5000, 10000]
    }
}

def generate_csv_data(output_file, schema, columns, num_rows, worker_name, file_index=1):
    """生成 CSV 测试数据"""
    print(f"  生成 CSV: {os.path.basename(output_file)} ({num_rows} 行)")
    
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(columns)
        
        if worker_name == "AggregationWorker":
            group_values = list(range(1, 101))
            for i in range(num_rows):
                group_col = random.choice(group_values)
                agg_col1 = round(random.uniform(10.0, 1000.0), 2)
                agg_col2 = round(random.uniform(1.0, 100.0), 2)
                writer.writerow([group_col, agg_col1, agg_col2])
        elif "Join" in worker_name:
            if file_index == 1:
                for i in range(1, num_rows + 1):
                    writer.writerow([i, f"value_{i}", round(i * 1.5, 2)])
            else:
                start_key = 2500 if file_index == 2 else 5000
                for i in range(num_rows):
                    key = start_key + i
                    writer.writerow([key, f"value_{key}", round(key * 1.5, 2)])
        elif worker_name == "SortWorker":
            keys = list(range(1, num_rows + 1))
            random.shuffle(keys)
            for key in keys:
                writer.writerow([key, f"value_{key}", round(key * 1.5, 2)])
        else:
            for i in range(1, num_rows + 1):
                writer.writerow([i, f"value_{i}", round(i * 1.5, 2)])
    
    print(f"  ✅ CSV 已生成")

def convert_csv_to_pxl(csv_file, pxl_file, schema, pixels_home):
    """使用 Java 转换器将 CSV 转换为 PXL"""
    print(f"  转换 CSV 到 PXL: {os.path.basename(pxl_file)}")
    
    classpath_parts = [
        os.path.join(pixels_home, "test", "target", "classes"),
        os.path.join(pixels_home, "pixels-core", "target", "classes"),
        os.path.join(pixels_home, "pixels-common", "target", "classes")
    ]
    
    for module in ["pixels-core", "pixels-common", "pixels-storage-localfs", "pixels-storage-s3"]:
        module_path = os.path.join(pixels_home, module, "target")
        if os.path.exists(module_path):
            for jar in os.listdir(module_path):
                if jar.endswith(".jar") and "-sources" not in jar and "-javadoc" not in jar:
                    classpath_parts.append(os.path.join(module_path, jar))
    
    classpath = ":".join(classpath_parts)
    
    cmd = ["java", "-cp", classpath, "io.pixelsdb.pixels.test.CsvToPxlConverter",
           csv_file, pxl_file, schema, ","]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, cwd=pixels_home)
        if os.path.exists(pxl_file):
            size = os.path.getsize(pxl_file) / 1024
            print(f"  ✅ PXL 已生成 ({size:.2f} KB)")
        else:
            print(f"  ❌ PXL 文件未生成")
            if result.stderr:
                print(f"  错误: {result.stderr}")
    except subprocess.CalledProcessError as e:
        print(f"  ❌ 转换失败")
        if e.stderr:
            print(f"  错误: {e.stderr}")
        raise

def compile_converter(pixels_home):
    """编译 CSV 到 PXL 转换器"""
    print("编译 CSV 到 PXL 转换器...")
    print("  编译项目依赖...")
    subprocess.run(["mvn", "compile", "-DskipTests", "-pl", "pixels-core,pixels-common,pixels-storage-localfs,pixels-storage-s3", "-am", "-q"],
                   cwd=pixels_home, check=True)
    
    class_dir = os.path.join(pixels_home, "test", "target", "classes", "io", "pixelsdb", "pixels", "test")
    os.makedirs(class_dir, exist_ok=True)
    
    classpath_parts = []
    for module in ["pixels-core", "pixels-common", "pixels-storage-localfs", "pixels-storage-s3"]:
        module_path = os.path.join(pixels_home, module, "target", "classes")
        if os.path.exists(module_path):
            classpath_parts.append(module_path)
        jar_path = os.path.join(pixels_home, module, "target")
        if os.path.exists(jar_path):
            for jar in os.listdir(jar_path):
                if jar.endswith(".jar") and "-sources" not in jar and "-javadoc" not in jar:
                    classpath_parts.append(os.path.join(jar_path, jar))
    
    classpath = ":".join(classpath_parts)
    java_file = os.path.join(pixels_home, "test", "CsvToPxlConverter.java")
    print(f"  编译: {os.path.basename(java_file)}")
    subprocess.run(["javac", "-d", os.path.join(pixels_home, "test", "target", "classes"),
                    "-cp", classpath, java_file], check=True, cwd=pixels_home)
    print("  ✅ 编译完成")

def main():
    test_dir = Path(__file__).parent.absolute()
    pixels_home = test_dir.parent
    
    print("=" * 60)
    print("为所有 Pixels Lambda Workers 生成测试数据")
    print("=" * 60)
    print(f"测试目录: {test_dir}")
    print(f"项目根目录: {pixels_home}")
    print()
    
    try:
        compile_converter(str(pixels_home))
    except subprocess.CalledProcessError as e:
        print(f"❌ 编译失败: {e}")
        sys.exit(1)
    
    print()
    
    for worker_name, config in WORKER_CONFIGS.items():
        print(f"处理 {worker_name}...")
        print("-" * 60)
        
        worker_dir = test_dir / worker_name
        worker_dir.mkdir(exist_ok=True)
        
        num_files = config["num_files"]
        schema = config["schema"]
        columns = config["columns"]
        num_rows = config["num_rows"]
        
        for file_idx in range(1, num_files + 1):
            rows = num_rows[file_idx - 1] if isinstance(num_rows, list) else num_rows
            
            if num_files == 1:
                csv_file = worker_dir / f"{worker_name}_data.csv"
                pxl_file = worker_dir / f"{worker_name}_data.pxl"
            else:
                csv_file = worker_dir / f"{worker_name}_data{file_idx}.csv"
                pxl_file = worker_dir / f"{worker_name}_data{file_idx}.pxl"
            
            generate_csv_data(str(csv_file), schema, columns, rows, worker_name, file_idx)
            
            try:
                convert_csv_to_pxl(str(csv_file), str(pxl_file), schema, str(pixels_home))
            except Exception as e:
                print(f"  ⚠️  转换失败，跳过: {e}")
        
        print(f"✅ {worker_name} 数据生成完成\n")
    
    print("=" * 60)
    print("✅ 所有 Worker 测试数据生成完成！")
    print("=" * 60)
    print("\n生成的文件结构:")
    for worker_name in WORKER_CONFIGS.keys():
        worker_dir = test_dir / worker_name
        if worker_dir.exists():
            files = sorted(worker_dir.glob("*.pxl"))
            if files:
                print(f"  {worker_name}/")
                for f in files:
                    size = f.stat().st_size / 1024
                    print(f"    - {f.name} ({size:.2f} KB)")

if __name__ == "__main__":
    main()
