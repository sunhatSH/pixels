# CSV 文件中 0 值记录分析

## 问题总结

### 1. 为什么有这么多 0 值？

从 CloudWatch Logs 可以看到，确实存在很多全为 0 的性能指标记录：

```
Four-Stage Performance Metrics (ms): READ=0, COMPUTE=0, WRITE_CACHE=0, WRITE_FILE=0
Percentages: COMPUTE=0.00%, WRITE_CACHE=0.00%, WRITE_FILE=0.00%, S3 Storage=0.00%
```

**可能的原因**：

1. **函数执行失败或异常**
   - 输入数据无效
   - S3 文件不存在或权限问题
   - 配置错误导致提前返回

2. **空输入或没有实际工作**
   - `scanInputs` 为空
   - 所有 row groups 都被跳过（例如范围超出）

3. **测试调用**
   - Lambda 冷启动测试
   - 配置验证调用
   - 空的测试 payload

4. **计时器未启动**
   - 如果代码路径没有经过实际的 scan/compute/write 流程
   - 计时器保持在初始状态（0 值）

### 2. 为什么只有 ScanWorker？

**答案**：其他 Worker 函数从未被调用过！

检查所有 Lambda 函数的 Log Group：

```bash
aws lambda list-functions --region us-east-2 \
  --query 'Functions[?contains(FunctionName, `pixels`)].FunctionName' \
  --output text | while read func; do
    echo "=== $func ==="
    aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$func" \
      --region us-east-2 --query 'logGroups[0].logGroupName' --output text
done
```

**结果**：
- ✅ `pixels-scan-worker`: 有 Log Group（已被调用）
- ❌ `pixels-aggregationworker`: null（从未调用）
- ❌ `pixels-partitionworker`: null（从未调用）
- ❌ `pixels-broadcastjoinworker`: null（从未调用）
- ❌ 其他所有 Worker: null（从未调用）

**结论**：只有 `pixels-scan-worker` 被实际使用过，所以 CSV 中只有 ScanWorker 的数据。

## 解决方案

### 方案 1: 过滤 0 值记录（已实现）

已更新 `download-csv-metrics.py`，自动过滤掉全为 0 的记录：

```python
# 跳过全为 0 的记录（这些通常是失败的调用或测试）
if read == 0 and compute == 0 and cache == 0 and file == 0:
    zero_count += 1
    continue
```

**使用方法**：
```bash
python3 download-csv-metrics.py
```

输出会显示：
- ✅ 有效记录数
- ⚠️ 过滤掉的 0 值记录数

### 方案 2: 分析失败原因

查看 0 值记录前后的日志，找出失败原因：

```bash
aws logs tail /aws/lambda/pixels-scan-worker --since 7d --region us-east-2 \
  | grep -B 10 -A 5 "Four-Stage Performance Metrics.*0,0,0,0"
```

### 方案 3: 测试其他 Worker

要获取其他 Worker 的数据，需要：
1. 创建测试输入 JSON
2. 调用对应的 Lambda 函数
3. 等待日志生成
4. 重新运行 CSV 提取脚本

## 数据统计

从您的 CSV 文件中可以看到：

- **总记录数**: 20 条
- **全为 0 的记录**: ~13 条（65%）
- **有效记录**: ~7 条（35%）

**有效的记录示例**：
```
1764490998000,ScanWorker,9856,9900,14387,4865,25.38,36.88,12.47,37.74
1764491054000,ScanWorker,11242,11781,13774,4977,28.20,32.97,11.91,38.83
```

这些记录有正常的性能指标，说明函数在正常工作时能正确记录数据。

## 建议

1. ✅ **使用过滤后的 CSV**：已更新的脚本会自动过滤 0 值
2. 🔍 **分析失败原因**：查看失败调用的日志，找出为什么会有这么多 0 值
3. 🧪 **测试其他 Worker**：调用其他 Worker 函数以生成数据
4. 📊 **只关注有效数据**：在数据分析时，忽略全为 0 的记录



