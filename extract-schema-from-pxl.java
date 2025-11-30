import io.pixelsdb.pixels.core.PixelsReader;
import io.pixelsdb.pixels.core.TypeDescription;
import io.pixelsdb.pixels.core.reader.PixelsReaderOption;
import io.pixelsdb.pixels.storage.Storage;
import io.pixelsdb.pixels.storage.StorageFactory;

import java.util.List;

/**
 * 从 Pixels 文件中提取 Schema 信息
 * 
 * 使用方法：
 * 1. 编译：javac -cp "pixels-common/target/*:pixels-core/target/*" extract-schema-from-pxl.java
 * 2. 运行：java -cp ".:pixels-common/target/*:pixels-core/target/*" ExtractSchemaFromPxl <pxl-file-path>
 */
public class ExtractSchemaFromPxl {
    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("用法: java ExtractSchemaFromPxl <pxl-file-path>");
            System.out.println("示例: java ExtractSchemaFromPxl s3://bucket/path/file.pxl");
            System.exit(1);
        }
        
        String filePath = args[0];
        System.out.println("读取文件: " + filePath);
        System.out.println("");
        
        try {
            // 初始化 Storage
            Storage storage = StorageFactory.Instance().getStorage(Storage.Scheme.s3);
            
            // 创建 Reader
            PixelsReader reader = io.pixelsdb.pixels.core.reader.PixelsReaderImpl.newBuilder()
                    .setStorage(storage)
                    .setPath(filePath)
                    .build();
            
            // 获取 Schema
            TypeDescription schema = reader.getFileSchema();
            
            // 提取列信息
            List<String> columnNames = schema.getFieldNames();
            List<TypeDescription> columnTypes = schema.getChildren();
            
            System.out.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            System.out.println("Schema 信息");
            System.out.println("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            System.out.println("文件路径: " + filePath);
            System.out.println("列数量: " + columnNames.size());
            System.out.println("行组数: " + reader.getRowGroupNum());
            System.out.println("总行数: " + reader.getNumberOfRows());
            System.out.println("");
            System.out.println("列名和类型：");
            System.out.println("");
            
            for (int i = 0; i < columnNames.size(); i++) {
                String colName = columnNames.get(i);
                TypeDescription colType = columnTypes.get(i);
                System.out.println("  [" + i + "] " + colName + ": " + colType.toString());
            }
            
            System.out.println("");
            System.out.println("JSON 格式（用于测试输入）：");
            System.out.print("  \"columnsToRead\": [");
            for (int i = 0; i < columnNames.size(); i++) {
                if (i > 0) System.out.print(", ");
                System.out.print("\"" + columnNames.get(i) + "\"");
            }
            System.out.println("]");
            
            reader.close();
            
        } catch (Exception e) {
            System.err.println("错误: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}

