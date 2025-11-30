# 测试脚本修复说明

## 问题分析

PartitionWorker 测试失败的原因：

1. **缺少 `projection` 字段**：PartitionInput 需要 `projection` (boolean[]) 字段
2. **缺少 `filter` 字段**：tableInfo 需要 `filter` 字段
3. **partitionInfo 格式错误**：应该使用 `keyColumnIds` (int[]) 而不是 `partitionedColumns` (String[])

## 修复内容

### PartitionWorker JSON 修复

**修复前**：
```json
{
  "tableInfo": {
    ...
    // 缺少 filter
  },
  // 缺少 projection
  "partitionInfo": {
    "partitionType": "HASH",
    "numPartition": 4,
    "partitionedColumns": ["col1"]  // ❌ 错误
  }
}
```

**修复后**：
```json
{
  "tableInfo": {
    ...
    "filter": "{\"schemaName\":\"test\",\"tableName\":\"test_table\",\"columnFilters\":{}}"  // ✅ 添加
  },
  "projection": [true, true, true],  // ✅ 添加
  "partitionInfo": {
    "partitionType": "HASH",
    "numPartition": 4,
    "keyColumnIds": [0]  // ✅ 修复：使用 int[] 而不是 String[]
  }
}
```

## 其他 Workers 检查清单

确保其他 Workers 的 JSON 输入也正确：

### AggregationWorker
- ✅ `aggregationInfo` 字段
- ✅ `aggregatedTableInfo` 字段（不是 `tableInfo`）

### Join Workers
- ✅ `leftTable` / `smallTable` 和 `rightTable` / `largeTable`
- ✅ `joinInfo` 字段
- ✅ 配对数据文件（大表+小表）

## 配置问题说明

如果遇到 `WorkerCommon` 初始化错误（`NumberFormatException: Cannot parse null string`），这通常表示：

1. Lambda Layer 中的 `pixels.properties` 配置不完整
2. 缺少必要的配置项，如：
   - `row.batch.size`
   - `pixel.stride`
   - `row.group.size`
   - `executor.worker.exchange.port`
   - `worker.coordinate.server.host`
   - `worker.coordinate.server.port`

**注意**：ScanWorker 成功说明基本配置应该是存在的，但某些 Workers 可能有额外的配置需求。

