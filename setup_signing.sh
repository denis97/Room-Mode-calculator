#!/bin/bash
set -e

echo "=== ModeMap Signing Keystore Setup ==="
echo ""
echo "This script generates a signing keystore for Play Store releases."
echo "You will be prompted for a password (keep it secure!)."
echo ""

# Generate keystore interactively (prompts for password)
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload \
  -dname "CN=denodes, OU=ModeMap, O=denodes, L=, ST=, C="

echo ""
echo "✓ Keystore generated: upload-keystore.jks"
echo ""
echo "Next steps:"
echo "1. Create android/key.properties with:"
echo ""
echo "   storeFile=upload-keystore.jks"
echo "   storePassword=<your-password-here>"
echo "   keyAlias=upload"
echo "   keyPassword=<your-password-here>"
echo ""
echo "2. Base64 encode the keystore for GitHub Secrets:"
echo "   base64 -w0 upload-keystore.jks > keystore.b64"
echo ""
echo "3. Add to GitHub Secrets:"
echo "   - UPLOAD_KEYSTORE_BASE64: (contents of keystore.b64)"
echo "   - KEYSTORE_PASSWORD: <your-password>"
echo "   - KEY_ALIAS: upload"
echo "   - KEY_PASSWORD: <your-password>"
echo ""
