#!/bin/bash
# Script to create Secure Boot keys for signing

echo "Creating Secure Boot keys..."
mkdir -p secure_boot_keys
cd secure_boot_keys

# Create Platform Key (PK)
openssl req -newkey rsa:2048 -nodes -keyout PK.key -new -x509 -sha256 -days 3650 -subj "/CN=My Platform Key/" -out PK.crt

# Create Key Exchange Key (KEK)
openssl req -newkey rsa:2048 -nodes -keyout KEK.key -new -x509 -sha256 -days 3650 -subj "/CN=My Key Exchange Key/" -out KEK.crt

# Create Signature Database (db) key
openssl req -newkey rsa:2048 -nodes -keyout db.key -new -x509 -sha256 -days 3650 -subj "/CN=My Signature Database key/" -out db.crt

# Convert to DER format for UEFI
openssl x509 -in PK.crt -outform DER -out PK.cer
openssl x509 -in KEK.crt -outform DER -out KEK.cer
openssl x509 -in db.crt -outform DER -out db.cer

echo "Keys created in secure_boot_keys/ directory"
echo "You can now use these keys to sign your bootloaders and kernels"
