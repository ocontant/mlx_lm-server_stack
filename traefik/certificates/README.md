# SSL Certificates for Traefik

Place your SSL certificates in this directory:

- `cert.pem`: Your SSL certificate
- `key.pem`: Your SSL private key

## For Development/Testing

To generate self-signed certificates for local development, you can use the following command:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ./key.pem -out ./cert.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
```

## For Production

For production environments, obtain proper certificates from a trusted Certificate Authority or use Let's Encrypt.