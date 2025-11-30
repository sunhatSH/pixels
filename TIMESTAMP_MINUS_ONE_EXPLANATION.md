# timestamp = -1 的含义和用途

## ✅ 确认：timestamp = -1 是正确的设置

### 代码证据

在 `PixelsReaderOption.java` 第 38 行有明确的注释：

```java
private long transTimestamp = -1L; // -1 means no need to consider the timestamp when reading data
```

**含义**：`-1` 是一个特殊值，表示**不需要考虑事务时间戳**。

### 使用场景

1. **测试环境**
   - 不需要事务管理
   - 不需要时间戳过滤
   - 简化测试配置

2. **非事务性读取**
   - 直接读取数据，不考虑版本控制
   - 读取所有可见的数据

3. **Lambda Worker 测试**
   - 在 Lambda 环境中，通常不需要完整的事务管理
   - `-1` 允许直接读取数据文件

### 代码中的处理

查看 `PixelsReaderOption.java` 第 103-106 行：

```java
public boolean hasValidTransTimestamp()
{
    return this.transTimestamp >= 0L;  // ⬅️ -1 被认为是无效的（不需要时间戳）
}
```

当 `timestamp = -1` 时：
- `hasValidTransTimestamp()` 返回 `false`
- 读取数据时不会进行时间戳过滤
- 读取所有可见的数据

### 在测试中的使用

当前测试脚本中：

```json
{
  "transId": 12345,
  "timestamp": -1,  // ⬅️ 正确：表示不需要时间戳过滤
  "requestId": "test-scan-$(date +%s)",
  ...
}
```

这是**完全正确**的设置，适合：
- ✅ Lambda Worker 测试
- ✅ 独立测试（不需要事务服务器）
- ✅ 性能测试

### 如果需要事务时间戳

如果您的测试需要真实的事务时间戳，可以：

1. **使用当前时间戳**：
   ```json
   "timestamp": 1733011200000  // 当前时间的毫秒数
   ```

2. **从事务服务器获取**：
   - 连接到 Pixels 事务服务器
   - 调用 `beginTrans` 获取事务 ID 和时间戳

### 总结

✅ **timestamp = -1 是正确的测试设置**
- 代码明确支持这个值
- 适合 Lambda Worker 测试场景
- 不需要额外的事务服务器配置

您的测试配置是正确的！



