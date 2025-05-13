#!/bin/bash

# Default values
KEYCHAIN="/Library/Keychains/System.keychain"
CERT_BASE_PATH="traefik/certificates"

# Help function
show_help() {
    echo "--------------------------------------------------------------------------------"
    echo " Certificate Manager - Generate and manage Self-Signed SSL certificates         "
    echo
    echo "--------------------------------------------------------------------------------"
    echo " WARNING: This script is designed for MAC OS and may not work on other systems. "
    echo "--------------------------------------------------------------------------------"
    echo 
    echo "Usage: $0 [OPTIONS] [DOMAIN|CERT_PATH]"
    echo
    echo "Options:"
    echo "  -g, --generate [domain]  Generate certificates for domain"
    echo "  -a, --add               Add certificate to system keychain"
    echo "  -d, --delete            Remove certificate from system keychain"
    echo "  -h, --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -g api.example.com          # Generate certificates only"
    echo "  $0 -g api.example.com -a       # Generate and add to keychain"
    echo "  $0 -a path/to/cert.crt         # Add existing cert to keychain"
    echo "  $0 -d path/to/cert.crt         # Remove cert from keychain"
    echo
    echo
    echo "--------------------------------------------------------------------------------"
    echo
    echo "Notes:"
    echo "  - Generate (-g) and delete (-d) are mutually exclusive"
    echo "  - Without -g, a certificate path must be provided for -a/-d"
    echo "  - Generated certificates are stored in $CERT_BASE_PATH/<domain>/"
    echo
    echo "--------------------------------------------------------------------------------"
    echo
    echo "Examples:"
    echo " # Add the Anthropic API certificate"
    echo "./scripts/manage-cert.sh -a traefik/certificates/anthropic/api.anthropic.com.crt"
    echo
    echo "# Remove the Anthropic API certificate"
    echo "./scripts/manage-cert.sh -d traefik/certificates/anthropic/api.anthropic.com.crt"
    echo
    echo "--------------------------------------------------------------------------------"
}

# Function to generate certificates
generate_certs() {
    local domain=$1
    local cert_dir="$CERT_BASE_PATH/$(echo $domain | cut -d. -f1)"
    
    echo "Generating certificates for $domain in $cert_dir"
    
    # Create directories
    mkdir -p "$cert_dir"
    
    # Generate private key and CSR
    openssl req -new -newkey rsa:2048 -nodes \
        -keyout "$cert_dir/$domain.key" \
        -out "$cert_dir/$domain.csr" \
        -subj "/C=US/ST=CA/L=SF/O=Development/CN=$domain"
    
    # Generate self-signed certificate
    openssl x509 -req -days 365 \
        -in "$cert_dir/$domain.csr" \
        -signkey "$cert_dir/$domain.key" \
        -out "$cert_dir/$domain.crt" \
        -extensions v3_req \
        -extfile <(cat <<EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
EOF
    )
    
    # Set proper permissions
    chmod 600 "$cert_dir/$domain.key"
    chmod 644 "$cert_dir/$domain.crt"
    
    echo "Certificates generated successfully in $cert_dir"
    CERT_PATH="$cert_dir/$domain.crt"
}

# Function to add certificate to keychain
add_to_keychain() {
    local cert_path=$1
    if [ ! -f "$cert_path" ]; then
        echo "Error: Certificate file not found: $cert_path"
        exit 1
    fi
    
    echo "Adding certificate to system keychain..."
    sudo security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$cert_path"
}

# Function to remove certificate from keychain
remove_from_keychain() {
    local cert_path=$1
    if [ ! -f "$cert_path" ]; then
        echo "Error: Certificate file not found: $cert_path"
        exit 1
    fi
    
    local cert_name=$(openssl x509 -noout -subject -in "$cert_path" | sed -n 's/.*CN = \(.*\)/\1/p')
    if [ -z "$cert_name" ]; then
        cert_name=$(basename "$cert_path")
    fi
    
    echo "Removing certificate for $cert_name from system keychain..."
    sudo security delete-certificate -c "$cert_name" "$KEYCHAIN"
}

# Parse arguments
GENERATE=false
ADD=false
DELETE=false
DOMAIN_OR_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--generate)
            GENERATE=true
            shift
            if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
                DOMAIN_OR_PATH="$1"
                shift
            fi
            ;;
        -a|--add)
            ADD=true
            shift
            if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
                DOMAIN_OR_PATH="$1"
                shift
            fi
            ;;
        -d|--delete)
            DELETE=true
            shift
            if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
                DOMAIN_OR_PATH="$1"
                shift
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            DOMAIN_OR_PATH="$1"
            shift
            ;;
    esac
done

# Validate domain or path argument
if [ -z "${DOMAIN_OR_PATH}" ]; then
    echo "Error: A valid domain name or certificate path is required for generate/add/delete operations."
    echo "Use -h or --help for more information."
    echo
    echo "--------------------------------------------------------------------------------"
    echo "Displaying help in 4 seconds..."
    sleep 4
    show_help
    exit 1
fi

# Validate arguments
if [ "$GENERATE" = true ] && [ "$DELETE" = true ]; then
    echo "Error: Generate (-g) and delete (-d) are mutually exclusive"
    exit 1
fi

# Execute requested operations
if [ "$GENERATE" = true ]; then
    generate_certs "${DOMAIN_OR_PATH:-$DOMAIN}"
    if [ "$ADD" = true ]; then
        add_to_keychain "$CERT_PATH"
    fi
elif [ "$ADD" = true ]; then
    add_to_keychain "$DOMAIN_OR_PATH"
elif [ "$DELETE" = true ]; then
    remove_from_keychain "$DOMAIN_OR_PATH"
fi