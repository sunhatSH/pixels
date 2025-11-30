/*
 * Copyright 2022 PixelsDB.
 *
 * This file is part of Pixels.
 *
 * Pixels is free software: you can redistribute it and/or modify
 * it under the terms of the Affero GNU General Public License as
 * published by the Free Software Foundation, either version 3 of
 * the License, or (at your option) any later version.
 *
 * Pixels is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * Affero GNU General Public License for more details.
 *
 * You should have received a copy of the Affero GNU General Public
 * License along with Pixels.  If not, see
 * <https://www.gnu.org/licenses/>.
 */
package io.pixelsdb.pixels.worker.common;

import java.io.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * @author hank
 * @create 2022-08-02
 */
public class WorkerMetrics {
    public static class Timer {
        private final AtomicLong elapsedNs = new AtomicLong(0);
        private long startTime = 0L;

        public Timer start() {
            startTime = System.nanoTime();
            return this;
        }

        /**
         * @return the cumulative duration of this timer
         */
        public long stop() {
            long endTime = System.nanoTime();
            elapsedNs.addAndGet(endTime - startTime);
            return elapsedNs.get();
        }

        public void add(long timeNs) {
            this.elapsedNs.addAndGet(timeNs);
        }

        public void minus(long timeNs) {
            this.elapsedNs.addAndGet(-timeNs);
        }

        public long getElapsedNs() {
            return elapsedNs.get();
        }
    }

    /**
     * A cluster of timers for the four performance stages: READ, COMPUTE,
     * WRITE_CACHE, WRITE_FILE
     */
    public static class StageTimers {

        private static StageTimers empty = null;

        // It is not thread-safe, but it is ok because it is only used with .
        public static StageTimers getEmpty() {
            if (empty == null) {
                empty = new StageTimers();
            }
            return empty;
        }

        private final Timer readTimer = new Timer();
        private final Timer computeTimer = new Timer();
        private final Timer writeCacheTimer = new Timer();
        private final Timer writeFileTimer = new Timer();

        public Timer getReadTimer() {
            return readTimer;
        }

        public Timer getComputeTimer() {
            return computeTimer;
        }

        public Timer getWriteCacheTimer() {
            return writeCacheTimer;
        }

        public Timer getWriteFileTimer() {
            return writeFileTimer;
        }

        public void clear() {
            // Timers are cumulative, no need to clear individual elapsed times
        }

        public long getReadTimeMs() {
            return readTimer.getElapsedNs() / 1_000_000;
        }

        public long getComputeTimeMs() {
            return computeTimer.getElapsedNs() / 1_000_000;
        }

        public long getWriteCacheTimeMs() {
            return writeCacheTimer.getElapsedNs() / 1_000_000;
        }

        public long getWriteFileTimeMs() {
            return writeFileTimer.getElapsedNs() / 1_000_000;
        }

        public long getTotalTimeMs() {
            return getReadTimeMs() + getComputeTimeMs() + getWriteCacheTimeMs() + getWriteFileTimeMs();
        }
    }

    private final AtomicInteger numReadRequests = new AtomicInteger(0);
    private final AtomicInteger numWriteRequests = new AtomicInteger(0);
    private final AtomicLong readBytes = new AtomicLong(0);
    private final AtomicLong writeBytes = new AtomicLong(0);
    private final AtomicLong inputCostNs = new AtomicLong(0);
    private final AtomicLong outputCostNs = new AtomicLong(0);
    private final AtomicLong computeCostNs = new AtomicLong(0);

    public void clear() {
        numReadRequests.set(0);
        numWriteRequests.set(0);
        readBytes.set(0);
        writeBytes.set(0);
        inputCostNs.set(0);
        outputCostNs.set(0);
        computeCostNs.set(0);
    }

    public int getNumReadRequests() {
        return numReadRequests.get();
    }

    public int getNumWriteRequests() {
        return numWriteRequests.get();
    }

    public long getReadBytes() {
        return readBytes.get();
    }

    public long getWriteBytes() {
        return writeBytes.get();
    }

    public long getInputCostNs() {
        return inputCostNs.get();
    }

    public long getOutputCostNs() {
        return outputCostNs.get();
    }

    public long getComputeCostNs() {
        return computeCostNs.get();
    }

    public void addNumReadRequests(int numReadRequests) {
        this.numReadRequests.addAndGet(numReadRequests);
    }

    public void addNumWriteRequests(int numWriteRequests) {
        this.numWriteRequests.addAndGet(numWriteRequests);
    }

    public void addReadBytes(long readBytes) {
        this.readBytes.addAndGet(readBytes);
    }

    public void addWriteBytes(long writeBytes) {
        this.writeBytes.addAndGet(writeBytes);
    }

    public void addInputCostNs(long inputDurationNs) {
        this.inputCostNs.addAndGet(inputDurationNs);
    }

    public void addOutputCostNs(long outputDurationNs) {
        this.outputCostNs.addAndGet(outputDurationNs);
    }

    public void addComputeCostNs(long computeDurationNs) {
        this.computeCostNs.addAndGet(computeDurationNs);
    }

    /**
     * Common performance metrics writer for all workers.
     */
    public static class PerformanceMetricsWriter {
        public static void writePerformanceToFile(WorkerMetrics workerMetrics, StageTimers stageTimers,
                Logger logger, String workerType, String csvFilePath) {
            writePerformanceToFileWithFallback(workerMetrics, stageTimers, logger, workerType, csvFilePath, false);
        }

        public static void writeBasicPerformanceToFile(WorkerMetrics workerMetrics, Logger logger,
                String workerType, String csvFilePath) {
            writePerformanceToFileWithFallback(workerMetrics, null, logger, workerType, csvFilePath, true);
        }

        private static void writePerformanceToFileWithFallback(WorkerMetrics workerMetrics, StageTimers stageTimers,
                Logger logger, String workerType, String csvFilePath, boolean useBasicMetricsOnly) {
            long timestamp = System.currentTimeMillis();

            // Determine if we have detailed timing from StageTimers
            boolean hasDetailedTiming = stageTimers != null && stageTimers != StageTimers.getEmpty()
                    && !useBasicMetricsOnly;

            long readTimeMs, computeTimeMsNew, writeCacheTimeMs, writeFileTimeMs;

            if (hasDetailedTiming) {
                // Use detailed stage timers - all metrics from StageTimers
                readTimeMs = stageTimers.getReadTimeMs();
                computeTimeMsNew = stageTimers.getComputeTimeMs();
                writeCacheTimeMs = stageTimers.getWriteCacheTimeMs();
                writeFileTimeMs = stageTimers.getWriteFileTimeMs();
            } else {
                // Fall back to basic WorkerMetrics
                readTimeMs = workerMetrics.getInputCostNs() / 1_000_000;
                computeTimeMsNew = workerMetrics.getComputeCostNs() / 1_000_000;
                writeCacheTimeMs = 0; // Not available in basic metrics
                writeFileTimeMs = workerMetrics.getOutputCostNs() / 1_000_000;
            }

            long totalTimeMs = readTimeMs + computeTimeMsNew + writeCacheTimeMs + writeFileTimeMs;

            // Calculate percentages (avoid division by zero)
            double computePct = totalTimeMs > 0 ? ((double) computeTimeMsNew / totalTimeMs) * 100 : 0;
            double writeCachePct = totalTimeMs > 0 ? ((double) writeCacheTimeMs / totalTimeMs) * 100 : 0;
            double writeFilePct = totalTimeMs > 0 ? ((double) writeFileTimeMs / totalTimeMs) * 100 : 0;
            double s3StoragePct = totalTimeMs > 0 ? ((double) (readTimeMs + writeFileTimeMs) / totalTimeMs) * 100 : 0;

            // Write to Log
            if (hasDetailedTiming) {
                logger.info(
                        "Four-Stage Performance Metrics (ms): READ={}, COMPUTE={}, WRITE_CACHE={}, WRITE_FILE={}, TOTAL={}",
                        readTimeMs, computeTimeMsNew, writeCacheTimeMs, writeFileTimeMs, totalTimeMs);
                logger.info(
                        "Percentages: READ={:.2f}%, COMPUTE={:.2f}%, WRITE_CACHE={:.2f}%, WRITE_FILE={:.2f}%, S3 Storage={:.2f}%",
                        totalTimeMs > 0 ? (readTimeMs * 100.0 / totalTimeMs) : 0,
                        computePct, writeCachePct, writeFilePct, s3StoragePct);
            } else {
                logger.info("Basic Performance Metrics (ms): READ={}, COMPUTE={}, OUTPUT={}, TOTAL={}",
                        readTimeMs, computeTimeMsNew, writeFileTimeMs, totalTimeMs);
                logger.info("Percentages: READ={:.2f}%, COMPUTE={:.2f}%, OUTPUT={:.2f}%",
                        totalTimeMs > 0 ? (readTimeMs * 100.0 / totalTimeMs) : 0,
                        computePct,
                        totalTimeMs > 0 ? (writeFileTimeMs * 100.0 / totalTimeMs) : 0);
            }

            // Write to CSV file
            try {
                File csvFile = new File(csvFilePath);
                boolean isNewFile = !csvFile.exists();

                try (FileWriter writer = new FileWriter(csvFilePath, true)) // Append mode
                {
                    // Write header if file is new
                    if (isNewFile) {
                        if (hasDetailedTiming) {
                            writer.write(
                                    "Timestamp,WorkerType,ReadTimeMs,ComputeTimeMs,WriteCacheTimeMs,WriteFileTimeMs,ComputePct,WriteCachePct,WriteFilePct,S3StoragePct\n");
                        } else {
                            writer.write(
                                    "Timestamp,WorkerType,ReadTimeMs,ComputeTimeMs,OutputTimeMs,TotalTimeMs,ReadPct\n");
                        }
                    }

                    // Write data row
                    if (hasDetailedTiming) {
                        writer.write(String.format("%d,%s,%d,%d,%d,%d,%.2f,%.2f,%.2f,%.2f\n",
                                timestamp, workerType, readTimeMs, computeTimeMsNew, writeCacheTimeMs, writeFileTimeMs,
                                computePct, writeCachePct, writeFilePct, s3StoragePct));
                    } else {
                        double readPct = totalTimeMs > 0 ? (readTimeMs * 100.0 / totalTimeMs) : 0;
                        writer.write(String.format("%d,%s,%d,%d,%d,%d,%.2f\n",
                                timestamp, workerType, readTimeMs, computeTimeMsNew, writeFileTimeMs, totalTimeMs,
                                readPct));
                    }
                    writer.flush();
                }
            } catch (IOException e) {
                logger.error("Failed to write performance metrics to CSV file: " + e.getMessage());
            }
        }
    }
}
