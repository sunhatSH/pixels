#!/bin/bash

# check-pixels.sh - Check the status of Pixels Daemon components

echo "========================================"
echo "       Pixels Daemon Status Check       "
echo "========================================"

# 1. Check Processes
echo ""
echo "[Process Status]"
echo "----------------"

check_process() {
    local role=$1
    local pattern=$2
    
    # Using pgrep -f to match the full command line including java arguments
    pids=$(pgrep -f "$pattern")
    
    if [ -n "$pids" ]; then
        # If multiple PIDs found (e.g. multiple workers locally), list them
        # Replace newlines with commas for display
        pid_list=$(echo "$pids" | tr '\n' ' ')
        echo -e "✅ $role:\tRunning (PID: $pid_list)"
    else
        echo -e "❌ $role:\tNot Running"
    fi
}

check_process "Coordinator" "io.pixelsdb.pixels.daemon.PixelsCoordinator"
check_process "Worker     " "io.pixelsdb.pixels.daemon.PixelsWorker"
check_process "Retina     " "io.pixelsdb.pixels.daemon.PixelsRetina"

# 2. Check Ports
echo ""
echo "[Port Status]"
echo "-------------"

check_port() {
    local service=$1
    local port=$2
    
    # Try lsof first, fall back to netstat (common on minimal installs)
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :$port -sTCP:LISTEN -P -n >/dev/null 2>&1; then
            status="✅ Listening"
        else
            status="❌ Closed"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tulpn 2>/dev/null | grep -q ":$port "; then
            status="✅ Listening"
        else
            status="❌ Closed"
        fi
    else
        status="❓ Unknown (lsof/netstat missing)"
    fi
    
    printf "%-25s %-8s %s\n" "$service" "($port)" "$status"
}

check_port "Metadata Server" 18888
check_port "Transaction Server" 18889
check_port "Retina Server" 18890
check_port "Query Schedule" 18893
check_port "Worker Coordinate" 18894

echo ""
echo "========================================"

