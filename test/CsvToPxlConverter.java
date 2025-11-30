package io.pixelsdb.pixels.test;

import io.pixelsdb.pixels.common.physical.Storage;
import io.pixelsdb.pixels.common.physical.StorageFactory;
import io.pixelsdb.pixels.core.PixelsWriter;
import io.pixelsdb.pixels.core.PixelsWriterImpl;
import io.pixelsdb.pixels.core.TypeDescription;
import io.pixelsdb.pixels.core.encoding.EncodingLevel;
import io.pixelsdb.pixels.core.exception.PixelsWriterException;
import io.pixelsdb.pixels.core.vector.*;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;
import java.util.regex.Pattern;

/**
 * CSV to PXL Converter
 * Converts CSV files to Pixels format (.pxl files)
 */
public class CsvToPxlConverter {
    
    public static void main(String[] args) {
        if (args.length < 4) {
            System.out.println("Usage: CsvToPxlConverter <csvFile> <pxlFile> <schema> <delimiter>");
            System.out.println("Example: CsvToPxlConverter test.csv test.pxl 'struct<col1:int,col2:string,col3:double>' ','");
            System.exit(1);
        }
        
        String csvFile = args[0];
        String pxlFile = args[1];
        String schemaStr = args[2];
        String delimiter = args[3];
        
        try {
            convertCsvToPxl(csvFile, pxlFile, schemaStr, delimiter);
            System.out.println("Successfully converted " + csvFile + " to " + pxlFile);
        } catch (Exception e) {
            System.err.println("Error converting CSV to PXL: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
    
    public static void convertCsvToPxl(String csvFile, String pxlFile, String schemaStr, String delimiter) 
            throws IOException, PixelsWriterException {
        
        // Parse schema
        TypeDescription schema = TypeDescription.fromString(schemaStr);
        VectorizedRowBatch rowBatch = schema.createRowBatch();
        
        // Get column vectors
        ColumnVector[] columnVectors = rowBatch.cols;
        int numColumns = columnVectors.length;
        
        // Determine storage type (file or s3)
        Storage storage;
        if (pxlFile.startsWith("s3://")) {
            storage = StorageFactory.Instance().getStorage("s3");
        } else {
            storage = StorageFactory.Instance().getStorage("file");
        }
        
        // Create PixelsWriter
        PixelsWriter pixelsWriter = PixelsWriterImpl.newBuilder()
                .setSchema(schema)
                .setPixelStride(10000)
                .setRowGroupSize(64 * 1024 * 1024) // 64MB
                .setStorage(storage)
                .setPath(pxlFile)
                .setBlockSize(256 * 1024 * 1024) // 256MB
                .setReplication((short) 1)
                .setBlockPadding(true)
                .setEncodingLevel(EncodingLevel.EL2)
                .setCompressionBlockSize(1)
                .build();
        
        // Read CSV and write to PXL
        try (BufferedReader reader = new BufferedReader(new FileReader(csvFile))) {
            String line;
            boolean isFirstLine = true;
            
            while ((line = reader.readLine()) != null) {
                if (line.trim().isEmpty()) {
                    continue;
                }
                
                // Skip header if present (simple heuristic: check if first line contains column names)
                if (isFirstLine && !isNumeric(line.split(Pattern.quote(delimiter))[0])) {
                    isFirstLine = false;
                    continue;
                }
                isFirstLine = false;
                
                String[] values = line.split(Pattern.quote(delimiter), -1);
                
                // Ensure we have enough values
                if (values.length < numColumns) {
                    String[] newValues = new String[numColumns];
                    System.arraycopy(values, 0, newValues, 0, values.length);
                    for (int i = values.length; i < numColumns; i++) {
                        newValues[i] = "";
                    }
                    values = newValues;
                }
                
                // Add row to batch
                int row = rowBatch.size++;
                for (int i = 0; i < numColumns; i++) {
                    String value = values[i].trim();
                    ColumnVector col = columnVectors[i];
                    
                    if (value.isEmpty() || value.equalsIgnoreCase("\\N") || value.equalsIgnoreCase("null")) {
                        col.addNull();
                    } else {
                        try {
                            col.add(value);
                        } catch (Exception e) {
                            System.err.println("Warning: Failed to parse value '" + value + "' for column " + i + ": " + e.getMessage());
                            col.addNull();
                        }
                    }
                }
                
                // Write batch if full
                if (rowBatch.size == rowBatch.getMaxSize()) {
                    pixelsWriter.addRowBatch(rowBatch);
                    rowBatch.reset();
                }
            }
            
            // Write remaining rows
            if (rowBatch.size > 0) {
                pixelsWriter.addRowBatch(rowBatch);
                rowBatch.reset();
            }
        }
        
        pixelsWriter.close();
    }
    
    private static boolean isNumeric(String str) {
        if (str == null || str.isEmpty()) {
            return false;
        }
        try {
            Double.parseDouble(str);
            return true;
        } catch (NumberFormatException e) {
            return false;
        }
    }
}

