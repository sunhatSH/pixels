# Schema 信息汇总

本文档包含所有 Worker 测试数据文件的 Schema 定义。

## 单表 Worker

### ScanWorker_data.pxl
- **列名**: `["id", "col1", "col2", "col3", "col4", "col5"]`
- **Schema**: `struct<id:int,col1:varchar(100),col2:int,col3:double,col4:boolean,col5:timestamp>`
- **用途**: 扫描操作测试

### PartitionWorker_data.pxl
- **列名**: `["key", "value1", "value2", "value3", "value4"]`
- **Schema**: `struct<key:int,value1:varchar(100),value2:double,value3:int,value4:boolean>`
- **分区键**: `key` (keyColumnIds: [0])
- **用途**: 分区操作测试

### AggregationWorker_data.pxl
- **列名**: `["group_key", "agg_col1", "agg_col2", "agg_col3", "agg_col4"]`
- **Schema**: `struct<group_key:int,agg_col1:double,agg_col2:int,agg_col3:double,agg_col4:varchar(100)>`
- **分组键**: `group_key`
- **聚合列**: `agg_col1`, `agg_col2`
- **用途**: 聚合操作测试

## Join Workers

### BroadcastJoinWorker

#### data1.pxl (大表)
- **列名**: `["id", "join_key", "col1", "col2", "col3", "col4"]`
- **Schema**: `struct<id:int,join_key:int,col1:varchar(100),col2:double,col3:int,col4:boolean>`
- **Join 键**: `join_key`

#### data2.pxl (小表)
- **列名**: `["join_key", "col1", "col2"]`
- **Schema**: `struct<join_key:int,col1:varchar(100),col2:double>`
- **Join 键**: `join_key`

### PartitionedJoinWorker

#### data1.pxl (大表)
- **列名**: `["id", "join_key", "col1", "col2", "col3", "col4", "col5"]`
- **Schema**: `struct<id:int,join_key:int,col1:varchar(100),col2:double,col3:int,col4:boolean,col5:timestamp>`
- **Join 键**: `join_key`

#### data2.pxl (小表)
- **列名**: `["join_key", "col1", "col2", "col3"]`
- **Schema**: `struct<join_key:int,col1:varchar(100),col2:double,col3:boolean>`
- **Join 键**: `join_key`

## 测试配置参考

### ScanWorker
```json
{
  "columnsToRead": ["id", "col1", "col2", "col3", "col4", "col5"],
  "scanProjection": [true, true, true, true, true, true]
}
```

### PartitionWorker
```json
{
  "columnsToRead": ["key", "value1", "value2", "value3", "value4"],
  "projection": [true, true, true, true, true],
  "partitionInfo": {
    "keyColumnIds": [0]  // key 列索引为 0
  }
}
```

### AggregationWorker
```json
{
  "columnsToRead": ["group_key", "agg_col1", "agg_col2", "agg_col3", "agg_col4"],
  "groupByColumns": ["group_key"],
  "aggregateFunctions": [
    {"functionType": "COUNT", "columnName": "agg_col1"},
    {"functionType": "SUM", "columnName": "agg_col2"}
  ]
}
```

### BroadcastJoinWorker
```json
{
  "leftTable": {
    "columnsToRead": ["id", "join_key", "col1", "col2", "col3", "col4"]
  },
  "rightTable": {
    "columnsToRead": ["join_key", "col1", "col2"]
  },
  "joinInfo": {
    "joinConditions": [
      {"leftColumn": "join_key", "rightColumn": "join_key"}
    ]
  }
}
```

### PartitionedJoinWorker
```json
{
  "smallTable": {
    "columnsToRead": ["join_key", "col1", "col2", "col3"]
  },
  "largeTable": {
    "columnsToRead": ["id", "join_key", "col1", "col2", "col3", "col4", "col5"]
  },
  "joinInfo": {
    "joinConditions": [
      {"leftColumn": "join_key", "rightColumn": "join_key"}
    ]
  }
}
```

