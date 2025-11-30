# PPT 图表数据说明

本目录包含从 `PIXELS_LAMBDA_PROJECT_SUMMARY_PPT.md` 提取的数据并生成的图表。

## 📊 生成的图表列表

### 1. chart1_performance_timing.png
**ScanWorker 四阶段性能指标时间分布（柱状图）**
- READ: 9354 ms (26.19%)
- COMPUTE: 9718 ms (27.21%)
- WRITE_CACHE: 13110 ms (36.71%)
- WRITE_FILE: 3533 ms (9.89%)
- 总耗时: 35715 ms

### 2. chart2_performance_percentage.png
**性能指标占比分布（饼图）**
- 展示四个执行阶段的占比关系
- WRITE_CACHE 占比最大（36.71%）

### 3. chart3_workers_deployment.png
**Lambda Workers 部署状态（水平条形图）**
- 9 个 Workers 全部已部署
- Scan, Partition, Aggregation, BroadcastJoin, PartitionedJoin, SortedJoin, BroadcastChainJoin, PartitionedChainJoin, Sort

### 4. chart4_test_results.png
**测试结果状态分布（饼图）**
- ✅ 成功执行: 1 个 (ScanWorker)
- ⚠️ 需要正确输入: 8 个

### 5. chart5_file_sizes.png
**S3 测试文件大小对比（柱状图）**
- large_test_data.pxl: 240.2 MiB
- example.pxl: 790 Bytes
- input.pxl: 790 Bytes

### 6. chart6_memory_usage.png
**Lambda 函数内存使用情况（进度条）**
- 已使用: 3068 MB
- 总内存: 4096 MB
- 使用率: 74.9%

### 7. chart7_execution_timeline.png
**执行流程时间线（水平条形图）**
- 展示四个阶段的顺序执行和时间分布
- 总耗时: 35715 ms (约 35.7 秒)

### 8. chart8_storage_io.png
**执行时间分类分析（堆叠柱状图）**
- 存储 I/O (READ+WRITE_FILE): 12887 ms (36.08%)
- 计算 (COMPUTE): 9718 ms (27.21%)
- 内存操作 (WRITE_CACHE): 13110 ms (36.71%)

## 🔧 使用方法

### 重新生成图表
```bash
python3 generate_charts.py
```

### 依赖要求
```bash
pip install matplotlib numpy
```

## 📝 数据来源

所有数据均提取自 `PIXELS_LAMBDA_PROJECT_SUMMARY_PPT.md`：
- 性能指标数据（第 582-592 行）
- Lambda Workers 部署状态（第 530-542 行）
- 测试结果状态（第 606-621 行）
- S3 测试文件大小（第 450-454 行）

