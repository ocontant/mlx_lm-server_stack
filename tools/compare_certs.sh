#!/bin/bash

# cert_checker.sh - Script to compare local certificates with deployed server certificates
# Usage: ./cert_checker.sh [config_file]

set -e

# Default config file location
CONFIG_FILE="${1:-cert_config.txt}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Temporary directory for downloaded certificates
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

print_result() {
    local server=$1
    local status=$2
    local message=$3
    
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓ $server: $message${NC}"
    else
        echo -e "${RED}✗ $server: $message${NC}"
    fi
}

check_dependencies() {
    log "Checking dependencies..."
    command -v openssl >/dev/null 2>&1 || { echo "Error: OpenSSL is required but not installed. Aborting."; exit 1; }
}

# Function to read and parse config file
parse_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Config file $CONFIG_FILE not found!"
        echo "Create a config file with the following format:"
        echo "server_name:port:/path/to/cert.crt"
        exit 1
    fi
    
    log "Using config file: $CONFIG_FILE"
}

# Function to download and save server certificate
get_server_cert() {
    local server=$1
    local port=$2
    local output_file=$3
    
    log "Getting certificate from $server:$port..."
    
    # Use timeout to avoid hanging if server doesn't respond
    timeout 10 openssl s_client -connect "$server:$port" -servername "$server" </dev/null 2>/dev/null | 
        sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "$output_file"
    
    # Check if the certificate was retrieved
    if [ ! -s "$output_file" ]; then
        return 1
    fi
    
    return 0
}

# Function to compare certificates
compare_certs() {
    local local_cert=$1
    local server_cert=$2
    local server_name=$3
    
    # Check if local cert exists
    if [ ! -f "$local_cert" ]; then
        print_result "$server_name" "ERROR" "Local certificate file not found: $local_cert"
        return 1
    fi
    
    # Create fingerprints
    local local_fingerprint=$(openssl x509 -in "$local_cert" -noout -fingerprint -sha256 | cut -d'=' -f2)
    local server_fingerprint=$(openssl x509 -in "$server_cert" -noout -fingerprint -sha256 | cut -d'=' -f2)
    
    # Compare fingerprints
    if [ "$local_fingerprint" = "$server_fingerprint" ]; then
        print_result "$server_name" "OK" "Certificate match ✓"
        return 0
    else
        print_result "$server_name" "ERROR" "Certificate mismatch!"
        
        # Get expiration dates
        local local_expiry=$(openssl x509 -in "$local_cert" -noout -enddate | cut -d'=' -f2)
        local server_expiry=$(openssl x509 -in "$server_cert" -noout -enddate | cut -d'=' -f2)
        
        echo -e "${YELLOW}  Local cert expires: $local_expiry${NC}"
        echo -e "${YELLOW}  Server cert expires: $server_expiry${NC}"
        
        # Get certificate subject
        local local_subject=$(openssl x509 -in "$local_cert" -noout -subject | sed 's/^subject=//')
        local server_subject=$(openssl x509 -in "$server_cert" -noout -subject | sed 's/^subject=//')
        
        echo -e "${YELLOW}  Local cert subject: $local_subject${NC}"
        echo -e "${YELLOW}  Server cert subject: $server_subject${NC}"
        
        return 1
    fi
}

# Check certificate expiration
check_expiration() {
    local cert_file=$1
    local server_name=$2
    
    # Get expiration date in seconds since epoch
    local expiry_date=$(date -d "$(openssl x509 -in "$cert_file" -noout -enddate | cut -d'=' -f2)" +%s)
    local current_date=$(date +%s)
    local seconds_remaining=$((expiry_date - current_date))
    local days_remaining=$((seconds_remaining / 86400))
    
    if [ $days_remaining -lt 0 ]; then
        print_result "$server_name" "ERROR" "Certificate EXPIRED ($days_remaining days ago)"
        return 1
    elif [ $days_remaining -lt 30 ]; then
        print_result "$server_name" "ERROR" "Certificate expires soon ($days_remaining days remaining)"
        return 1
    else
        return 0
    fi
}

# Main function
main() {
    check_dependencies
    parse_config
    
    local total_checks=0
    local passed_checks=0
    
    log "Starting certificate checks..."
    
    # Read config file line by line
    while IFS=: read -r server port cert_path || [ -n "$server" ]; do
        # Skip comments and empty lines
        [[ "$server" =~ ^#.*$ || -z "$server" ]] && continue
        
        total_checks=$((total_checks + 1))
        
        # Trim whitespace
        server=$(echo "$server" | xargs)
        port=$(echo "$port" | xargs)
        cert_path=$(echo "$cert_path" | xargs)
        
        server_cert_file="$TEMP_DIR/${server}_${port}.pem"
        
        echo -e "\n${YELLOW}Checking $server:$port against $cert_path${NC}"
        
        if get_server_cert "$server" "$port" "$server_cert_file"; then
            compare_result=0
            compare_certs "$cert_path" "$server_cert_file" "$server" || compare_result=1
            
            # Check expiration regardless of match
            expiry_result=0
            check_expiration "$server_cert_file" "$server" || expiry_result=1
            
            # If both checks pass, increment passed_checks
            if [ $compare_result -eq 0 ] && [ $expiry_result -eq 0 ]; then
                passed_checks=$((passed_checks + 1))
            fi
        else
            print_result "$server" "ERROR" "Failed to retrieve certificate"
        fi
    done < "$CONFIG_FILE"
    
    # Summary
    echo -e "\n${YELLOW}Certificate Check Summary:${NC}"
    echo -e "Checked $total_checks servers, $passed_checks passed, $((total_checks - passed_checks)) failed"
    
    if [ $passed_checks -eq $total_checks ]; then
        echo -e "${GREEN}All certificates match and are valid!${NC}"
        exit 0
    else
        echo -e "${RED}Some certificate checks failed.${NC}"
        exit 1
    fi
}

main "$@"