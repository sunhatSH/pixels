# 测试数据信息

## 📊 已上传到 S3 的数据文件

所有测试数据已上传到：`s3://home-sunhao/test-data/workers-performance/`

### 文件列表

| 文件名 | 大小 | Worker 类型 | 说明 |
|--------|------|------------|------|
| `ScanWorker_data.pxl` | 48.72 MB | Scan | 扫描操作测试数据 |
| `PartitionWorker_data.pxl` | 53.94 MB | Partition | 分区操作测试数据 |
| `AggregationWorker_data.pxl` | 55.52 MB | Aggregation | 聚合操作测试数据 |
| `BroadcastJoinWorker_data1.pxl` | 5.09 MB | BroadcastJoin | 广播连接 - **大表** |
| `BroadcastJoinWorker_data2.pxl` | 1.34 MB | BroadcastJoin | 广播连接 - **小表** |
| `PartitionedJoinWorker_data1.pxl` | 4.71 MB | PartitionedJoin | 分区连接 - **大表** |
| `PartitionedJoinWorker_data2.pxl` | 1.17 MB | PartitionedJoin | 分区连接 - **小表** |

**总大小**: 170.51 MB

---

## 🔗 S3 路径参考

### ScanWorker
```
s3://home-sunhao/test-data/workers-performance/ScanWorker_data.pxl
```

### PartitionWorker
```
s3://home-sunhao/test-data/workers-performance/PartitionWorker_data.pxl
```

### AggregationWorker
```
s3://home-sunhao/test-data/workers-performance/AggregationWorker_data.pxl
```

### BroadcastJoinWorker
- **大表** (leftTable):
  ```
  s3://home-sunhao/test-data/workers-performance/BroadcastJoinWorker_data1.pxl
  ```
- **小表** (rightTable - 将被广播):
  ```
  s3://home-sunhao/test-data/workers-performance/BroadcastJoinWorker_data2.pxl
  ```

### PartitionedJoinWorker
- **大表** (largeTable):
  ```
  s3://home-sunhao/test-data/workers-performance/PartitionedJoinWorker_data1.pxl
  ```
- **小表** (smallTable):
  ```
  s3://home-sunhao/test-data/workers-performance/PartitionedJoinWorker_data2.pxl
  ```

---

## 📝 数据文件说明

### 配对关系

相似命名的文件属于同一个 Worker：

- **BroadcastJoinWorker**:
  - `BroadcastJoinWorker_data1.pxl` → 大表（5.09 MB）
  - `BroadcastJoinWorker_data2.pxl` → 小表（1.34 MB）

- **PartitionedJoinWorker**:
  - `PartitionedJoinWorker_data1.pxl` → 大表（4.71 MB）
  - `PartitionedJoinWorker_data2.pxl` → 小表（1.17 MB）

### 单个文件 Workers

- **ScanWorker**: 仅需一个输入文件
- **PartitionWorker**: 仅需一个输入文件
- **AggregationWorker**: 仅需一个输入文件

---

## 🧪 测试建议

### 测试顺序

1. **ScanWorker** - 最简单的操作，可以验证基本的数据读取能力
2. **PartitionWorker** - 验证分区功能
3. **AggregationWorker** - 验证聚合计算
4. **BroadcastJoinWorker** - 验证连接操作（广播小表）
5. **PartitionedJoinWorker** - 验证分区连接操作

### Lambda 函数名称

| Worker 类型 | Lambda 函数名 |
|------------|--------------|
| Scan | `pixels-scan-worker` |
| Partition | `pixels-partitionworker` |
| Aggregation | `pixels-aggregationworker` |
| BroadcastJoin | `pixels-broadcastjoinworker` |
| PartitionedJoin | `pixels-partitionedjoinworker` |

---

## 📋 上传脚本

使用以下脚本可以重新上传数据：

```bash
./upload-test-data-to-s3.sh
```

脚本会自动：
- 检查本地文件是否存在
- 显示文件大小
- 上传到 S3
- 显示上传进度和速度
- 验证上传结果

---

## ✅ 验证数据存在

使用以下命令验证 S3 中的文件：

```bash
aws s3 ls s3://home-sunhao/test-data/workers-performance/ --region us-east-2 --human-readable
```

---

**更新时间**: 2025-12-01
**区域**: us-east-2
**存储桶**: home-sunhao

