#!/bin/bash
# 测试所有 Workers 的性能

set -e
set -o pipefail

# 配置
BUCKET_NAME="home-sunhao"
LAMBDA_REGION="us-east-2"
REGION="$LAMBDA_REGION"
LOCAL_DATA_DIR="/Users/sunhao/Documents/pixels/test/test_datasource"
S3_TEST_DATA_PREFIX="test-data/workers-performance"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
}

# 检查本地文件
if [ ! -d "$LOCAL_DATA_DIR" ]; then
    log_error "本地数据目录不存在: $LOCAL_DATA_DIR"
    exit 1
fi

# 步骤 2: 测试 ScanWorker
log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "步骤 2: 测试 ScanWorker"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_scan_worker() {
    local FUNC_NAME="pixels-scan-worker"
    local TIMESTAMP=$(date +%s)
    
    cat > /tmp/test-scan-input.json << JSON
{
  "transId": 12345,
  "timestamp": -1,
  "requestId": "test-scan-$TIMESTAMP",
  "tableInfo": {
    "tableName": "test_table",
    "base": true,
    "columnsToRead": ["id", "col1", "col2", "col3", "col4", "col5"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputSplits": [
      {
        "inputInfos": [
          {
            "inputId": 1,
            "path": "s3://${BUCKET_NAME}/${S3_TEST_DATA_PREFIX}/ScanWorker_data.pxl",
            "rgStart": 0,
            "rgLength": -1,
            "storageInfo": {
              "scheme": "s3",
              "endpoint": "https://s3.${REGION}.amazonaws.com"
            }
          }
        ]
      }
    ],
    "filter": "{\"schemaName\":\"test\",\"tableName\":\"test_table\",\"columnFilters\":{}}"
  },
  "scanProjection": [true, true, true, true, true, true],
  "partialAggregationPresent": false,
  "partialAggregationInfo": null,
  "output": {
    "path": "s3://pixels-turbo-intermediate/output/",
    "fileNames": ["scan_result_$TIMESTAMP.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${REGION}.amazonaws.com"
  }
}
JSON

    log_info "调用 Lambda: $FUNC_NAME"
    if aws lambda invoke \
        --function-name "$FUNC_NAME" \
        --payload file:///tmp/test-scan-input.json \
        --cli-binary-format raw-in-base64-out \
        --region "$REGION" \
        /tmp/response-scan.json > /dev/null 2>&1; then
        
        if grep -q '"successful":true' /tmp/response-scan.json 2>/dev/null; then
            log_success "ScanWorker 执行成功"
            return 0
        else
            ERROR_MSG=$(grep -o '"errorMessage":"[^"]*"' /tmp/response-scan.json 2>/dev/null || echo "Unknown error")
            log_error "ScanWorker 执行失败: $ERROR_MSG"
            return 1
        fi
    else
        log_error "调用 Lambda 失败"
        return 1
    fi
}

# test_scan_worker

# 步骤 3: 测试 PartitionWorker
log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "步骤 3: 测试 PartitionWorker"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_partition_worker() {
    local FUNC_NAME="pixels-partitionworker"
    local TIMESTAMP=$(date +%s)
    
    cat > /tmp/test-partition-input.json << JSON
{
  "transId": 12346,
  "timestamp": -1,
  "requestId": "test-partition-$TIMESTAMP",
  "tableInfo": {
    "tableName": "test_table",
    "base": true,
    "columnsToRead": ["key", "value1", "value2", "value3", "value4"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputSplits": [
      {
        "inputInfos": [
          {
            "inputId": 1,
            "path": "s3://${BUCKET_NAME}/${S3_TEST_DATA_PREFIX}/PartitionWorker_data.pxl",
            "rgStart": 0,
            "rgLength": -1,
            "storageInfo": {
              "scheme": "s3",
              "endpoint": "https://s3.${REGION}.amazonaws.com"
            }
          }
        ]
      }
    ],
    "filter": "{\"schemaName\":\"test\",\"tableName\":\"test_table\",\"columnFilters\":{}}"
  },
  "projection": [true, true, true, true, true],
  "partitionInfo": {
    "partitionType": "HASH",
    "numPartition": 4,
    "keyColumnIds": [0]
  },
  "output": {
    "path": "s3://pixels-turbo-intermediate/output/",
    "fileNames": ["partition_result_$TIMESTAMP.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${REGION}.amazonaws.com"
  }
}
JSON

    log_info "调用 Lambda: $FUNC_NAME"
    if aws lambda invoke \
        --function-name "$FUNC_NAME" \
        --payload file:///tmp/test-partition-input.json \
        --cli-binary-format raw-in-base64-out \
        --region "$REGION" \
        /tmp/response-partition.json > /dev/null 2>&1; then
        
        if grep -q '"successful":true' /tmp/response-partition.json 2>/dev/null; then
            log_success "PartitionWorker 执行成功"
            return 0
        else
            ERROR_MSG=$(grep -o '"errorMessage":"[^"]*"' /tmp/response-partition.json 2>/dev/null || echo "Unknown error")
            log_error "PartitionWorker 执行失败: $ERROR_MSG"
            return 1
        fi
    else
        log_error "调用 Lambda 失败"
        return 1
    fi
}

# test_partition_worker 

# 步骤 4: 测试 AggregationWorker
log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "步骤 4: 测试 AggregationWorker"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_aggregation_worker() {
    local FUNC_NAME="pixels-aggregationworker"
    local TIMESTAMP=$(date +%s)
    
    cat > /tmp/test-aggregation-input.json << JSON
{
  "transId": 12347,
  "timestamp": -1,
  "requestId": "test-aggregation-$TIMESTAMP",
  "aggregationInfo": {
    "inputPartitioned": false,
    "hashValues": [],
    "numPartition": 1,
    "groupKeyColumnIds": [0],
    "aggregateColumnIds": [2],
    "groupKeyColumnNames": ["group_key"],
    "groupKeyColumnProjection": [true],
    "resultColumnNames": ["sum_agg_col2"],
    "resultColumnTypes": ["bigint"],
    "functionTypes": ["SUM"]
  },
  "aggregatedTableInfo": {
    "tableName": "test_table",
    "base": false,
    "columnsToRead": ["group_key", "agg_col1", "agg_col2", "agg_col3", "agg_col4"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputFiles": [
      "s3://${BUCKET_NAME}/${S3_TEST_DATA_PREFIX}/AggregationWorker_data.pxl"
    ],
    "parallelism": 1
  },
  "output": {
    "path": "s3://pixels-turbo-intermediate/output/",
    "fileNames": ["aggregation_result_$TIMESTAMP.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${REGION}.amazonaws.com"
  }
}
JSON

    log_info "调用 Lambda: $FUNC_NAME"
    if aws lambda invoke \
        --function-name "$FUNC_NAME" \
        --payload file:///tmp/test-aggregation-input.json \
        --cli-binary-format raw-in-base64-out \
        --region "$REGION" \
        /tmp/response-aggregation.json > /dev/null 2>&1; then
        
        if grep -q '"successful":true' /tmp/response-aggregation.json 2>/dev/null; then
            log_success "AggregationWorker 执行成功"
            return 0
        else
            ERROR_MSG=$(grep -o '"errorMessage":"[^"]*"' /tmp/response-aggregation.json 2>/dev/null || echo "Unknown error")
            log_error "AggregationWorker 执行失败: $ERROR_MSG"
            return 1
        fi
    else
        log_error "调用 Lambda 失败"
        return 1
    fi
}

# test_aggregation_worker

# 步骤 5: 测试 BroadcastJoinWorker
log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "步骤 5: 测试 BroadcastJoinWorker"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

test_broadcast_join_worker() {
    local FUNC_NAME="pixels-broadcastjoinworker"
    local TIMESTAMP=$(date +%s)
    
    cat > /tmp/test-broadcast-join-input.json << JSON
{
  "transId": 12348,
  "timestamp": -1,
  "requestId": "test-broadcast-join-$TIMESTAMP",
  "smallTable": {
    "tableName": "small_table",
    "base": true,
    "columnsToRead": ["join_key", "col1", "col2"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputSplits": [
      {
        "inputInfos": [
          {
            "inputId": 1,
            "path": "s3://${BUCKET_NAME}/${S3_TEST_DATA_PREFIX}/BroadcastJoinWorker_data2.pxl",
            "rgStart": 0,
            "rgLength": -1,
            "storageInfo": {
              "scheme": "s3",
              "endpoint": "https://s3.${REGION}.amazonaws.com"
            }
          }
        ]
      }
    ],
    "filter": "{\"schemaName\":\"test\",\"tableName\":\"small_table\",\"columnFilters\":{}}",
    "keyColumnIds": [0]
  },
  "largeTable": {
    "tableName": "large_table",
    "base": true,
    "columnsToRead": ["id", "join_key", "col1", "col2", "col3", "col4"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputSplits": [
      {
        "inputInfos": [
          {
            "inputId": 1,
            "path": "s3://${BUCKET_NAME}/${S3_TEST_DATA_PREFIX}/BroadcastJoinWorker_data1.pxl",
            "rgStart": 0,
            "rgLength": -1,
            "storageInfo": {
              "scheme": "s3",
              "endpoint": "https://s3.${REGION}.amazonaws.com"
            }
          }
        ]
      }
    ],
    "filter": "{\"schemaName\":\"test\",\"tableName\":\"large_table\",\"columnFilters\":{}}",
    "keyColumnIds": [1]
  },
  "joinInfo": {
    "joinType": "EQUI_INNER",
    "smallColumnAlias": ["join_key", "col1", "col2"],
    "largeColumnAlias": ["id", "join_key", "col1", "col2", "col3", "col4"],
    "smallProjection": [true, true, true],
    "largeProjection": [true, true, true, true, true, true],
    "postPartition": false,
    "postPartitionInfo": null
  },
  "partialAggregationPresent": false,
  "partialAggregationInfo": null,
  "output": {
    "path": "s3://pixels-turbo-intermediate/output/",
    "fileNames": ["broadcast_join_result_$TIMESTAMP.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${REGION}.amazonaws.com"
  }
}
JSON

    log_info "调用 Lambda: $FUNC_NAME"
    if aws lambda invoke \
        --function-name "$FUNC_NAME" \
        --payload file:///tmp/test-broadcast-join-input.json \
        --cli-binary-format raw-in-base64-out \
        --region "$REGION" \
        /tmp/response-broadcast-join.json > /dev/null 2>&1; then
        
        if grep -q '"successful":true' /tmp/response-broadcast-join.json 2>/dev/null; then
            log_success "BroadcastJoinWorker 执行成功"
            return 0
        else
            ERROR_MSG=$(grep -o '"errorMessage":"[^"]*"' /tmp/response-broadcast-join.json 2>/dev/null || echo "Unknown error")
            log_error "BroadcastJoinWorker 执行失败: $ERROR_MSG"
            return 1
        fi
    else
        log_error "调用 Lambda 失败"
        return 1
    fi
}

# test_broadcast_join_worker

# 步骤 6: 测试 PartitionedJoinWorker
log_info ""
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "步骤 6: 测试 PartitionedJoinWorker"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info ""
log_info "前置步骤: 为 Join 生成分区文件..."

# 先运行 PartitionWorker 为两个表生成分区文件
generate_partitioned_files_for_join() {
    local PARTITION_TIMESTAMP=$(date +%s)
    
    log_info "为小表生成分区文件..." >&2
    cat > /tmp/partition-small-join.json << JSON
{
  "transId": 12352,
  "timestamp": -1,
  "requestId": "partition-small-join-$PARTITION_TIMESTAMP",
  "tableInfo": {
    "tableName": "small_table",
    "base": true,
    "columnsToRead": ["join_key", "col1", "col2", "col3"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputSplits": [
      {
        "inputInfos": [
          {
            "inputId": 1,
            "path": "s3://${BUCKET_NAME}/${S3_TEST_DATA_PREFIX}/PartitionedJoinWorker_data2.pxl",
            "rgStart": 0,
            "rgLength": -1,
            "storageInfo": {
              "scheme": "s3",
              "endpoint": "https://s3.${REGION}.amazonaws.com"
            }
          }
        ]
      }
    ],
    "filter": "{\"schemaName\":\"test\",\"tableName\":\"small_table\",\"columnFilters\":{}}"
  },
  "projection": [true, true, true, true],
  "partitionInfo": {
    "partitionType": "HASH",
    "numPartition": 4,
    "keyColumnIds": [0]
  },
  "output": {
    "path": "s3://pixels-turbo-intermediate/output/partitioned-join/",
    "fileNames": ["small_partitioned_${PARTITION_TIMESTAMP}.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${REGION}.amazonaws.com"
  }
}
JSON
    
    if aws lambda invoke \
        --function-name pixels-partitionworker \
        --payload file:///tmp/partition-small-join.json \
        --cli-binary-format raw-in-base64-out \
        --region "$REGION" \
        /tmp/partition-small-join-response.json > /dev/null 2>&1; then
        if grep -q '"successful":true' /tmp/partition-small-join-response.json 2>/dev/null; then
            log_success "小表分区文件生成成功" >&2
            SMALL_PARTITION_FILE="s3://pixels-turbo-intermediate/output/partitioned-join/small_partitioned_${PARTITION_TIMESTAMP}.pxl"
        else
            log_error "小表分区文件生成失败" >&2
            return 1
        fi
    else
        log_error "调用 PartitionWorker 失败" >&2
        return 1
    fi
    
    log_info "为大表生成分区文件..." >&2
    cat > /tmp/partition-large-join.json << JSON
{
  "transId": 12353,
  "timestamp": -1,
  "requestId": "partition-large-join-$PARTITION_TIMESTAMP",
  "tableInfo": {
    "tableName": "large_table",
    "base": true,
    "columnsToRead": ["id", "join_key", "col1", "col2", "col3", "col4", "col5"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputSplits": [
      {
        "inputInfos": [
          {
            "inputId": 1,
            "path": "s3://${BUCKET_NAME}/${S3_TEST_DATA_PREFIX}/PartitionedJoinWorker_data1.pxl",
            "rgStart": 0,
            "rgLength": -1,
            "storageInfo": {
              "scheme": "s3",
              "endpoint": "https://s3.${REGION}.amazonaws.com"
            }
          }
        ]
      }
    ],
    "filter": "{\"schemaName\":\"test\",\"tableName\":\"large_table\",\"columnFilters\":{}}"
  },
  "projection": [true, true, true, true, true, true, true],
  "partitionInfo": {
    "partitionType": "HASH",
    "numPartition": 4,
    "keyColumnIds": [1]
  },
  "output": {
    "path": "s3://pixels-turbo-intermediate/output/partitioned-join/",
    "fileNames": ["large_partitioned_${PARTITION_TIMESTAMP}.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${REGION}.amazonaws.com"
  }
}
JSON
    
    if aws lambda invoke \
        --function-name pixels-partitionworker \
        --payload file:///tmp/partition-large-join.json \
        --cli-binary-format raw-in-base64-out \
        --region "$REGION" \
        /tmp/partition-large-join-response.json > /dev/null 2>&1; then
        if grep -q '"successful":true' /tmp/partition-large-join-response.json 2>/dev/null; then
            log_success "大表分区文件生成成功" >&2
            LARGE_PARTITION_FILE="s3://pixels-turbo-intermediate/output/partitioned-join/large_partitioned_${PARTITION_TIMESTAMP}.pxl"
        else
            log_error "大表分区文件生成失败" >&2
            return 1
        fi
    else
        log_error "调用 PartitionWorker 失败" >&2
        return 1
    fi
    
    # 等待文件完全写入
    log_info "等待分区文件完全写入..." >&2
    sleep 3
    
    # 只输出文件路径到 stdout，其他信息输出到 stderr
    echo "$SMALL_PARTITION_FILE" >&1
    echo "$LARGE_PARTITION_FILE" >&1
}

# 生成分区文件
PARTITION_FILES=$(generate_partitioned_files_for_join)
if [ $? -ne 0 ]; then
    log_error "生成分区文件失败，跳过 PartitionedJoinWorker 测试"
    exit 1
fi

SMALL_PARTITION_FILE=$(echo "$PARTITION_FILES" | head -1)
LARGE_PARTITION_FILE=$(echo "$PARTITION_FILES" | tail -1)

log_info "使用分区文件:"
log_info "  小表: $SMALL_PARTITION_FILE"
log_info "  大表: $LARGE_PARTITION_FILE"

test_partitioned_join_worker() {
    local FUNC_NAME="pixels-partitionedjoinworker"
    local TIMESTAMP=$(date +%s)
    
    cat > /tmp/test-partitioned-join-input.json << JSON
{
  "transId": 12349,
  "timestamp": -1,
  "requestId": "test-partitioned-join-$TIMESTAMP",
  "smallTable": {
    "tableName": "small_table",
    "base": false,
    "columnsToRead": ["join_key", "col1", "col2", "col3"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputFiles": [
      "${SMALL_PARTITION_FILE}"
    ],
    "parallelism": 1,
    "keyColumnIds": [0]
  },
  "largeTable": {
    "tableName": "large_table",
    "base": false,
    "columnsToRead": ["id", "join_key", "col1", "col2", "col3", "col4", "col5"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputFiles": [
      "${LARGE_PARTITION_FILE}"
    ],
    "parallelism": 1,
    "keyColumnIds": [1]
  },
  "joinInfo": {
    "joinType": "EQUI_INNER",
    "smallColumnAlias": ["join_key", "col1", "col2", "col3"],
    "largeColumnAlias": ["id", "join_key", "col1", "col2", "col3", "col4", "col5"],
    "smallProjection": [true, true, true, true],
    "largeProjection": [true, true, true, true, true, true, true],
    "postPartition": false,
    "postPartitionInfo": null,
    "numPartition": 4,
    "hashValues": [0, 1, 2, 3]
  },
  "partialAggregationPresent": false,
  "partialAggregationInfo": null,
  "output": {
    "path": "s3://pixels-turbo-intermediate/output/",
    "fileNames": ["partitioned_join_result_$TIMESTAMP.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${REGION}.amazonaws.com"
  }
}
JSON

    log_info "调用 Lambda: $FUNC_NAME"
    if aws lambda invoke \
        --function-name "$FUNC_NAME" \
        --payload file:///tmp/test-partitioned-join-input.json \
        --cli-binary-format raw-in-base64-out \
        --region "$REGION" \
        /tmp/response-partitioned-join.json > /dev/null 2>&1; then
        
        if grep -q '"successful":true' /tmp/response-partitioned-join.json 2>/dev/null; then
            log_success "PartitionedJoinWorker 执行成功"
            return 0
        else
            ERROR_MSG=$(grep -o '"errorMessage":"[^"]*"' /tmp/response-partitioned-join.json 2>/dev/null || echo "Unknown error")
            log_error "PartitionedJoinWorker 执行失败: $ERROR_MSG"
            return 1
        fi
    else
        log_error "调用 Lambda 失败"
        return 1
    fi
}

test_partitioned_join_worker

# 总结
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "性能测试完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "请使用以下命令提取性能数据："
echo ""
echo "python3 download-csv-metrics.py --region $REGION"
echo ""

