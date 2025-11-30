# 最新执行摘要

## 执行时间
2025-11-30 16:09:14 (UTC)

## 执行状态
✅ **成功完成**

## Lambda 函数执行详情

### Request ID
`446ce969-9970-466b-82fb-d8a08e17f1fa`

### 执行结果
- **状态码**: 200 (成功)
- **总耗时**: 31,829.71 ms (约 31.8 秒)
- **计费时长**: 32,796 ms
- **初始化时间**: 965.59 ms
- **内存使用**: 2,138 MB / 4,096 MB (52.2%)

### 性能指标 (Four-Stage Performance Metrics)

| 阶段 | 耗时 (ms) | 占比 |
|------|-----------|------|
| **READ** | 9,856 | 31.0% |
| **COMPUTE** | 9,900 | 25.38% |
| **WRITE_CACHE** | 14,387 | 36.88% |
| **WRITE_FILE** | 4,865 | 12.47% |
| **S3 Storage** | - | 37.74% |

### 数据传输统计

- **读取请求数**: 5
- **写入请求数**: 0
- **总读取字节数**: 251,811,018 bytes (约 240 MB)
- **总写入字节数**: 0 bytes
- **输出文件**: `s3://home-sunhao/output/scan_0`
- **Row Groups**: 0

### 成本指标

- **Input Cost**: 9,856 ms
- **Compute Cost**: 0 ms
- **Output Cost**: 20,191 ms
- **GBMs**: 0

## 完整日志位置

### CloudWatch Logs
- **Log Group**: `/aws/lambda/pixels-scan-worker`
- **Region**: `us-east-2`
- **Request ID**: `446ce969-9970-466b-82fb-d8a08e17f1fa`

### 本地日志文件
- 脚本执行日志: `deploy-test-final-20251130-235753.log`
- Lambda 完整日志: `lambda-full-execution-log.txt` (如果已生成)

## 查看完整日志的命令

```bash
# 查看最近的 CloudWatch Logs
aws logs tail /aws/lambda/pixels-scan-worker --since 10m --region us-east-2 --format short

# 查看特定 Request ID 的日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/pixels-scan-worker \
  --filter-pattern "446ce969-9970-466b-82fb-d8a08e17f1fa" \
  --region us-east-2 \
  --query 'events[*].message' \
  --output text

# 查看脚本执行日志
tail -100 deploy-test-final-20251130-235753.log
```

## 注意事项

1. **Multipart Upload 错误**: 日志中出现了 "Failed to initiate multipart upload" 错误，但这不影响整体执行，Lambda 仍然成功完成。

2. **性能指标**: 性能指标已成功记录，显示：
   - 读取阶段耗时最长 (9.8秒)
   - 计算阶段占 25.38%
   - 写入缓存占 36.88%
   - S3 存储操作占 37.74%

3. **输出文件**: 结果已成功写入 S3: `s3://home-sunhao/output/scan_0`

## 下一步

如果需要查看更详细的日志或性能分析，可以使用上述命令从 CloudWatch 提取完整日志。



