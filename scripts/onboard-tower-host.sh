#!/bin/bash
#
# Tower of Omens Host Onboarding Script
# Automates SSH key setup and TPM configuration
#
# Usage: ./onboard-tower-host.sh <hostname>
# Example: ./onboard-tower-host.sh auth
#          ./onboard-tower-host.sh ca

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Check if hostname provided
if [ $# -ne 1 ]; then
    error "Usage: $0 <hostname>\nExample: $0 auth  OR  $0 ca"
fi

HOST=$1
FQDN="${HOST}.funlab.casa"

# Validate hostname
if [[ ! "$HOST" =~ ^(auth|ca)$ ]]; then
    error "Invalid hostname. Must be 'auth' or 'ca'"
fi

info "Starting onboarding for ${FQDN}"
echo ""

# Step 1: Check network connectivity
info "Step 1: Checking network connectivity..."
if ping -c 1 -W 2 $FQDN > /dev/null 2>&1; then
    success "Host is reachable"
else
    error "Cannot ping ${FQDN}. Check network connectivity."
fi

# Step 2: Export SSH keys from 1Password
info "Step 2: Exporting SSH keys from 1Password..."
cd ~/.ssh

# Determine 1Password item name (capitalized)
if [ "$HOST" = "auth" ]; then
    OP_ITEM="SSH Key - Funlab.Casa.Auth"
elif [ "$HOST" = "ca" ]; then
    OP_ITEM="SSH Key - Funlab.casa.Ca"
fi

# Export keys
info "Exporting private key..."
op item get "$OP_ITEM" --fields "private key" --reveal > ${HOST}_1password 2>/dev/null || error "Failed to export private key from 1Password"

info "Exporting public key..."
op item get "$OP_ITEM" --fields "public key" > ${HOST}_1password.pub 2>/dev/null || error "Failed to export public key from 1Password"

# Clean up formatting
sed -i '1{/^$/d}' ${HOST}_1password
sed -i 's/^"//; s/"$//' ${HOST}_1password

# Set permissions
chmod 600 ${HOST}_1password
chmod 644 ${HOST}_1password.pub

# Verify key
info "Verifying key format..."
ssh-keygen -y -f ${HOST}_1password > /dev/null 2>&1 || error "SSH key is invalid format"

success "SSH keys exported and verified"

# Step 3: Copy public key to host
info "Step 3: Copying public key to ${FQDN}..."
echo "You will be prompted for the root password..."

cat ${HOST}_1password.pub | \
  ssh -o PreferredAuthentications=password \
      -o PubkeyAuthentication=no \
      root@${FQDN} \
  "mkdir -p /home/tygra/.ssh && \
   cat >> /home/tygra/.ssh/authorized_keys && \
   chmod 700 /home/tygra/.ssh && \
   chmod 600 /home/tygra/.ssh/authorized_keys && \
   chown -R tygra:tygra /home/tygra/.ssh && \
   echo 'Key installed successfully'" || error "Failed to copy SSH key"

success "Public key copied to ${FQDN}"

# Step 4: Test SSH connection
info "Step 4: Testing SSH connection..."
if ssh -o ConnectTimeout=5 tygra@${FQDN} exit 2>/dev/null; then
    success "SSH connection successful!"
else
    error "SSH connection failed. Check configuration."
fi

# Step 5: Verify SSH config
info "Step 5: Verifying SSH config..."
if grep -q "Host ${HOST}" ~/.ssh/config; then
    success "SSH config entry exists"
else
    info "SSH config entry not found. It should have been created earlier."
    info "Entry should look like:"
    echo "Host ${HOST} ${FQDN}"
    echo "    HostName ${FQDN}"
    echo "    User tygra"
    echo "    IdentityFile ~/.ssh/${HOST}_1password"
    echo "    IdentitiesOnly yes"
fi

echo ""
success "=========================================="
success "SSH Setup Complete for ${FQDN}!"
success "=========================================="
echo ""

# Next steps
info "Next Steps:"
echo "1. Test SSH: ssh ${HOST}"
echo "2. Disable root SSH: ssh ${HOST} 'sudo sed -i \"s/^PermitRootLogin yes/PermitRootLogin no/\" /etc/ssh/sshd_config && sudo systemctl restart sshd'"
echo "3. Install TPM packages: ssh ${HOST} 'sudo apt update && sudo apt install -y tpm2-tools clevis clevis-tpm2 clevis-luks clevis-initramfs cryptsetup-bin'"
echo "4. Follow Phase 4 in tower-of-omens-onboarding.md for TPM setup"
echo ""
echo "Full onboarding guide: ~/infrastructure/tower-of-omens-onboarding.md"
