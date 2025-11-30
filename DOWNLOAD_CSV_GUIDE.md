# 下载性能指标 CSV 文件指南

## ✅ 已创建的脚本

### `download-csv-metrics.py` - Python 脚本（推荐）

从 CloudWatch Logs 提取性能指标并保存为 CSV 文件。

**使用方法**:
```bash
python3 download-csv-metrics.py
```

**功能**:
- 自动从 CloudWatch Logs 提取最近 24 小时的数据
- 解析性能指标和百分比
- 生成标准 CSV 格式文件
- 保存到 `./performance-metrics/scan_performance_metrics.csv`

**输出格式**:
```csv
Timestamp,WorkerType,ReadTimeMs,ComputeTimeMs,WriteCacheTimeMs,WriteFileTimeMs,ComputePct,WriteCachePct,WriteFilePct,S3StoragePct
1764408274000,ScanWorker,9856,9900,14387,4865,25.38,36.88,12.47,37.74
```

## 📁 文件位置

提取的 CSV 文件保存在：
```
./performance-metrics/scan_performance_metrics.csv
```

## 🔧 自定义

### 修改 Lambda 函数名

编辑 `download-csv-metrics.py`，修改以下变量：
```python
LAMBDA_NAME = "pixels-scan-worker"  # 改为其他 Worker 名称
```

### 修改时间范围

修改 `--since` 参数：
```python
["aws", "logs", "tail", LOG_GROUP, "--since", "24h", ...]  # 改为 "48h", "7d" 等
```

### 下载其他 Worker 的 CSV

当前脚本只提取 ScanWorker 的数据。要为其他 Worker 创建 CSV：

1. 修改脚本中的 `LAMBDA_NAME` 和 `OUTPUT_FILE`
2. 或者创建一个包装脚本批量下载所有 Worker

## 📊 CSV 字段说明

| 字段 | 说明 |
|------|------|
| Timestamp | 时间戳（毫秒） |
| WorkerType | Worker 类型（如 ScanWorker） |
| ReadTimeMs | 读取时间（毫秒） |
| ComputeTimeMs | 计算时间（毫秒） |
| WriteCacheTimeMs | 写入缓存时间（毫秒） |
| WriteFileTimeMs | 写入文件时间（毫秒） |
| ComputePct | 计算时间百分比 |
| WriteCachePct | 写入缓存时间百分比 |
| WriteFilePct | 写入文件时间百分比 |
| S3StoragePct | S3 存储时间百分比（READ + WRITE_FILE） |

## 💡 提示

1. **确保有日志数据**: 脚本需要先有 Lambda 函数执行的日志才能提取数据
2. **权限要求**: 需要 AWS CLI 配置并具有 CloudWatch Logs 读取权限
3. **时间范围**: 默认提取最近 24 小时的数据，可根据需要调整

## 🔄 自动化

可以设置定时任务自动下载：
```bash
# 添加到 crontab
0 */6 * * * cd /path/to/pixels && python3 download-csv-metrics.py
```

## 📝 注意事项

- CSV 文件包含从 CloudWatch Logs 提取的数据，不是从 Lambda 函数的 `/tmp` 目录直接读取
- 如果需要 Lambda 函数的原始 CSV 文件，需要修改代码将文件上传到 S3



