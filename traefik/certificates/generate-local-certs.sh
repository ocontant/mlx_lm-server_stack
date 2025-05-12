#!/bin/bash
set -e

# Script to generate self-signed SSL certificates for localhost.loc development

# Default parameters
DOMAIN="localhost.loc"
DAYS=365
CERT_DIR="$(dirname "$0")"
CERT_FILE="$CERT_DIR/cert.pem"
KEY_FILE="$CERT_DIR/key.pem"

# Help function
function show_help {
  echo "Usage: $0 [options]"
  echo "Generate self-signed SSL certificates for local development"
  echo ""
  echo "Options:"
  echo "  -d, --domain DOMAIN    Domain name (default: localhost.loc)"
  echo "  --days DAYS            Certificate validity in days (default: 365)"
  echo "  -h, --help             Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 --domain myapp.local --days 730"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--domain)
      DOMAIN="$2"
      shift 2
      ;;
    --days)
      DAYS="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

echo "Generating self-signed certificates for: $DOMAIN"
echo "Certificates will be valid for $DAYS days"
echo "Output location: $CERT_DIR"

# Create certificate
openssl req -x509 -nodes -days "$DAYS" -newkey rsa:2048 \
  -keyout "$KEY_FILE" -out "$CERT_FILE" \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"

# Set permissions
chmod 644 "$CERT_FILE"
chmod 600 "$KEY_FILE"

echo ""
echo "✅ Certificates generated successfully!"
echo ""
echo "Certificate file: $CERT_FILE"
echo "Key file: $KEY_FILE"
echo ""
echo "⚠️  Important: Add the following entry to your /etc/hosts file:"
echo "127.0.0.1 $DOMAIN"
echo ""
echo "To trust this certificate on macOS, run:"
echo "sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CERT_FILE"