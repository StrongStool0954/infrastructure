# step-ca PKCS#8 Migration - Full Disaster Recovery Exercise

**Date:** 2026-02-13
**Status:** PLANNED (Not Started)
**Type:** Disaster Recovery Exercise + PKCS#8 Standardization
**Estimated Duration:** 7 hours active work
**Risk Level:** HIGH (Complete PKI regeneration)

---

## Executive Summary

**Objective:** Regenerate the entire Certificate Authority infrastructure from scratch using PKCS#8 format keys, simulating a complete disaster recovery scenario.

**What We're Doing:**
- Generate NEW root CA: Eye of Thundera v2 (RSA 4096, PKCS#8, 100-year validity)
- Generate NEW intermediate CA: Sword of Omens v2 (RSA 2048, PKCS#8, 10-year validity)
- Redistribute root CA trust to all infrastructure hosts
- Re-sign OpenBao PKI intermediate (Book of Omens v2)
- Renew all service certificates with new PKI chain
- Achieve 100% PKCS#8 compliance across entire infrastructure

**Why Full DR Exercise vs Simple Intermediate Renewal:**
- Tests complete CA loss recovery procedure (hardware failure, security breach simulation)
- Validates trust redistribution mechanisms
- Documents real-world recovery timeline
- Hardens disaster recovery playbook with actual execution
- Identifies all dependencies and touch points
- Higher complexity but better preparedness

**Trade-offs Accepted:**
- Longer deployment time (7 hours vs 4-5 hours for intermediate-only)
- Must redistribute root CA trust to all systems (3 hosts)
- Higher complexity, more touch points
- Benefit: Complete DR capability validated

---

## Current State (Pre-Migration)

### Certificate Authority Hierarchy

```
Eye of Thundera (Root CA)
├─ RSA 4096-bit, Traditional format
├─ 100-year validity
├─ Self-signed
├─ Stored in 1Password (Funlab.Casa.Ca vault)
│
└─── Sword of Omens (Intermediate CA)
     ├─ RSA 2048-bit, Traditional format
     ├─ 10-year validity
     ├─ Signed by Eye of Thundera
     ├─ Key stored on YubiKey NEO #5497305 (Slot 9d)
     │
     └─── Book of Omens (OpenBao PKI Intermediate)
          ├─ RSA 4096-bit
          ├─ 10-year validity
          ├─ Signs all infrastructure certificates
          │
          └─── Service Certificates (24h-30d TTL)
               ├─ Keylime Agent/Registrar/Verifier (24h)
               ├─ Nginx TLS (30d)
               └─ SPIRE Agents (if applicable)
```

### Affected Hosts

| Host | Services | Certificate Usage |
|------|----------|-------------------|
| **spire.funlab.casa** | Keylime Agent, Registrar, Verifier, Nginx, OpenBao | All services use certificates from Book of Omens |
| **auth.funlab.casa** | Keylime Agent | Agent certificate from Book of Omens |
| **ca.funlab.casa** | step-ca, Keylime Agent | Hosts intermediate CA, agent certificate |

### Key Files (Current State)

**step-ca on ca.funlab.casa:**
- `/etc/step-ca/config/ca.json` - Main configuration (KMS pointing to YubiKey)
- `/etc/step-ca/certs/intermediate_ca.crt` - Current Sword of Omens cert
- `/etc/step-ca/certs/root_ca.crt` - Current Eye of Thundera cert
- `/etc/step-ca/secrets/` - Encrypted keys (if any)
- `/etc/step-ca/db/` - Certificate database (BadgerV2)
- YubiKey Slot 9d - Current intermediate CA private key

**Trust stores (all 3 hosts):**
- `/etc/keylime/certs/ca-root-only.crt` - Root CA only
- `/etc/keylime/certs/ca-complete-chain.crt` - Full chain
- `/etc/nginx/certs/keylime-ca-chain.crt` - Nginx trust (spire only)
- `/usr/local/share/ca-certificates/` - System trust store
- `/etc/ssl/certs/` - Auto-generated system trust

### Critical Dependencies

- **YubiKey NEO #5497305** - Must be physically present during migration
- **1Password Access** - Required for retrieving YubiKey PIN and management key
- **Network Connectivity** - SSH access to all 3 hosts required
- **Patched Binary** - `/tmp/step-ca-full-pkcs8-binary` with native PKCS#8 support

### 1Password References

**Vault:** Funlab.Casa.Ca

**Items:**
- "YubiKey NEO - ca.funlab.casa" - Contains PIN and Management Key
  - PIN: `S1iNIv2g`
  - Management Key: `de0836a40794ff047e9dc1658a98a3471af2b63a309ce111`
- "Eye of Thundera - Root CA Private Key" (current v1, traditional format)
- "Eye of Thundera - Root CA Certificate" (current v1)
- "Sword of Omens - Intermediate CA Private Key" (current v1, traditional format)

---

## Migration Plan

### Phase 1: Pre-Migration Preparation (1 hour)

**Objectives:**
- Complete backup with rollback capability
- Document current state for comparison
- Freeze new certificate operations

**Steps:**

1. **Full backup of ca.funlab.casa:**
   ```bash
   ssh root@ca.funlab.casa "
     BACKUP_DIR=/root/step-ca-backup-\$(date +%Y%m%d-%H%M%S)
     mkdir -p \$BACKUP_DIR

     # Backup entire step-ca directory
     tar -czf \$BACKUP_DIR/step-ca-full.tar.gz /etc/step-ca/

     # Export BadgerV2 database
     systemctl stop step-ca
     cp -r /etc/step-ca/db \$BACKUP_DIR/db-backup
     systemctl start step-ca

     # Record certificate state
     step-cli certificate inspect /etc/step-ca/certs/root_ca.crt > \$BACKUP_DIR/root-ca-pre.txt
     step-cli certificate inspect /etc/step-ca/certs/intermediate_ca.crt > \$BACKUP_DIR/intermediate-ca-pre.txt

     # List directory
     ls -lah \$BACKUP_DIR/
     tar -tzf \$BACKUP_DIR/step-ca-full.tar.gz | wc -l
   "
   ```

2. **Document current certificate state on all hosts:**
   ```bash
   for host in spire auth ca; do
     ssh root@\${host}.funlab.casa "
       # Capture CA fingerprints
       openssl x509 -in /etc/keylime/certs/ca-root-only.crt -noout -fingerprint -sha256 > /tmp/pre-migration-state-\${host}.txt

       # Record service status
       systemctl is-active keylime_agent >> /tmp/pre-migration-state-\${host}.txt

       # Record current cert serials
       if [ -f /etc/keylime/certs/agent.crt ]; then
         openssl x509 -in /etc/keylime/certs/agent.crt -noout -serial -subject >> /tmp/pre-migration-state-\${host}.txt
       fi

       cat /tmp/pre-migration-state-\${host}.txt
     "
   done
   ```

3. **Record OpenBao PKI state:**
   ```bash
   ssh root@spire.funlab.casa "
     export BAO_ADDR='https://bao.funlab.casa:8200'
     export BAO_CACERT='/etc/keylime/certs/ca-complete-chain.crt'

     # Read current intermediate
     bao read -format=json pki_int/cert/ca > /tmp/book-of-omens-pre.json
     bao read -format=json pki_int/config/urls > /tmp/pki-config-pre.json
   "
   ```

4. **Verify rollback capability:**
   ```bash
   ssh root@ca.funlab.casa "
     BACKUP_DIR=\$(ls -td /root/step-ca-backup-* | head -1)

     # Verify tarball integrity
     tar -tzf \$BACKUP_DIR/step-ca-full.tar.gz | head -20
     tar -tzf \$BACKUP_DIR/step-ca-full.tar.gz | wc -l

     # Verify ca.json present
     tar -tzf \$BACKUP_DIR/step-ca-full.tar.gz | grep ca.json

     echo \"Backup validated: \$BACKUP_DIR\"
   "
   ```

5. **Optional: Freeze ACME provisioner:**
   ```bash
   # Edit /etc/step-ca/config/ca.json on ca.funlab.casa
   # Set ACME provisioner "claims": {"disableRenewal": true}
   # systemctl restart step-ca
   # Reduces risk of partial state during migration
   ```

**Success Criteria:**
- [ ] Backup tarball created (>100 files)
- [ ] Pre-migration state documented on all 3 hosts
- [ ] OpenBao PKI state captured
- [ ] Rollback capability verified

---

### Phase 2: Regenerate Root and Intermediate CAs with PKCS#8 (2 hours)

**Objectives:**
- Generate NEW root CA (Eye of Thundera v2) with PKCS#8 key
- Generate NEW intermediate CA (Sword of Omens v2) with PKCS#8 key
- Sign intermediate with new root
- Install to YubiKey and step-ca
- Store all keys in 1Password for disaster recovery

**Steps:**

#### 2.1: Generate New Root CA (Eye of Thundera v2)

1. **Generate PKCS#8 root CA private key:**
   ```bash
   cd /tmp/step-ca-pkcs8-migration

   # Generate RSA 4096 key in PKCS#8 format
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
     -outform PEM -out eye-of-thundera-v2-key.pem

   # Verify PKCS#8 format
   head -1 eye-of-thundera-v2-key.pem
   # Should show: -----BEGIN PRIVATE KEY-----
   ```

2. **Create self-signed root CA certificate:**
   ```bash
   # Create configuration for root CA extensions
   cat > root-ca-extensions.cnf << 'EOF'
   [root_ca]
   basicConstraints = critical,CA:TRUE
   keyUsage = critical,keyCertSign,cRLSign
   subjectKeyIdentifier = hash
   EOF

   # Generate self-signed root certificate (100-year validity)
   openssl req -new -x509 \
     -key eye-of-thundera-v2-key.pem \
     -out eye-of-thundera-v2-cert.pem \
     -days 36500 \
     -sha256 \
     -subj "/CN=Eye of Thundera v2/O=Funlab.Casa/OU=Tower of Omens/C=US" \
     -extensions root_ca \
     -config root-ca-extensions.cnf
   ```

3. **Verify root CA:**
   ```bash
   openssl x509 -in eye-of-thundera-v2-cert.pem -noout -text | grep -A3 "Subject:"
   openssl x509 -in eye-of-thundera-v2-cert.pem -noout -text | grep "CA:TRUE"

   # Verify self-signed
   openssl verify -CAfile eye-of-thundera-v2-cert.pem eye-of-thundera-v2-cert.pem
   # Should return: OK
   ```

4. **Encrypt and store in 1Password:**
   ```bash
   # Encrypt key for secure storage
   openssl pkcs8 -topk8 -in eye-of-thundera-v2-key.pem \
     -out eye-of-thundera-v2-key-encrypted.pem \
     -passout pass:TEMP_PASSWORD_CHANGE_IMMEDIATELY

   # Store in 1Password (Funlab.Casa.Ca vault)
   op document create eye-of-thundera-v2-key-encrypted.pem \
     --title "Eye of Thundera v2 - Root CA Private Key (PKCS8)" \
     --vault "Funlab.Casa.Ca"

   op document create eye-of-thundera-v2-cert.pem \
     --title "Eye of Thundera v2 - Root CA Certificate" \
     --vault "Funlab.Casa.Ca"

   echo "IMPORTANT: Update password in 1Password immediately!"
   ```

#### 2.2: Generate New Intermediate CA (Sword of Omens v2)

1. **Generate PKCS#8 intermediate CA private key:**
   ```bash
   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
     -outform PEM -out sword-of-omens-v2-key.pem

   # Verify PKCS#8 format
   head -1 sword-of-omens-v2-key.pem
   # Should show: -----BEGIN PRIVATE KEY-----
   ```

2. **Create CSR:**
   ```bash
   openssl req -new \
     -key sword-of-omens-v2-key.pem \
     -out sword-of-omens-v2.csr \
     -subj "/CN=Sword of Omens v2/O=Funlab.Casa/OU=Tower of Omens/C=US"
   ```

3. **Sign with new Root CA (Eye of Thundera v2):**
   ```bash
   # Create intermediate CA extensions
   cat > intermediate-ca-extensions.cnf << 'EOF'
   [intermediate_ca]
   basicConstraints = critical,CA:TRUE,pathlen:0
   keyUsage = critical,keyCertSign,cRLSign
   subjectKeyIdentifier = hash
   authorityKeyIdentifier = keyid:always,issuer
   EOF

   # Sign CSR with new root CA (10-year validity)
   openssl x509 -req \
     -in sword-of-omens-v2.csr \
     -CA eye-of-thundera-v2-cert.pem \
     -CAkey eye-of-thundera-v2-key.pem \
     -CAcreateserial \
     -out sword-of-omens-v2-cert.pem \
     -days 3650 \
     -sha256 \
     -extfile intermediate-ca-extensions.cnf \
     -extensions intermediate_ca
   ```

4. **Verify intermediate certificate:**
   ```bash
   # Verify chain
   openssl verify -CAfile eye-of-thundera-v2-cert.pem sword-of-omens-v2-cert.pem
   # Should return: OK

   # Verify pathlen:0
   openssl x509 -in sword-of-omens-v2-cert.pem -noout -text | grep -A1 "CA:TRUE"
   ```

5. **Import to YubiKey (Slot 9d):**

   **CRITICAL: Must delete old key first (one-time operation)**

   ```bash
   # YubiKey credentials from 1Password
   MGMT_KEY="de0836a40794ff047e9dc1658a98a3471af2b63a309ce111"
   PIN="S1iNIv2g"

   # Delete old key and cert from Slot 9d
   yubico-piv-tool -s 9d -a delete-certificate
   yubico-piv-tool -s 9d -a delete-key

   # Import new PKCS#8 key to Slot 9d
   yubico-piv-tool -s 9d \
     -a import-key \
     -k $MGMT_KEY \
     -i sword-of-omens-v2-key.pem

   # Import certificate
   yubico-piv-tool -s 9d \
     -a import-certificate \
     -k $MGMT_KEY \
     -i sword-of-omens-v2-cert.pem

   # Verify import
   yubico-piv-tool -a status
   pkcs11-tool --module /usr/lib/x86_64-linux-gnu/libykcs11.so -O | grep "Key Management"

   # Test PKCS#11 access (requires PIN)
   pkcs11-tool --module /usr/lib/x86_64-linux-gnu/libykcs11.so \
     --login --pin $PIN \
     --test
   ```

6. **Backup to 1Password:**
   ```bash
   # Encrypt key with password for 1Password storage (backup only)
   openssl pkcs8 -topk8 -in sword-of-omens-v2-key.pem \
     -out sword-of-omens-v2-key-encrypted.pem \
     -passout pass:TEMP_PASSWORD_CHANGE_IMMEDIATELY

   # Store in 1Password
   op document create sword-of-omens-v2-key-encrypted.pem \
     --title "Sword of Omens v2 - Intermediate CA Private Key (PKCS8) - Backup" \
     --vault "Funlab.Casa.Ca"

   op document create sword-of-omens-v2-cert.pem \
     --title "Sword of Omens v2 - Intermediate CA Certificate" \
     --vault "Funlab.Casa.Ca"

   echo "IMPORTANT: Update password in 1Password immediately!"
   echo "NOTE: Primary key is on YubiKey (hardware-backed), this is DR backup"
   ```

7. **Update step-ca configuration:**
   ```bash
   # Copy certificates to ca.funlab.casa
   scp eye-of-thundera-v2-cert.pem root@ca.funlab.casa:/etc/step-ca/certs/root_ca.crt
   scp sword-of-omens-v2-cert.pem root@ca.funlab.casa:/etc/step-ca/certs/intermediate_ca.crt

   # Verify ca.json KMS configuration (should remain unchanged)
   ssh root@ca.funlab.casa "grep -A5 'kms' /etc/step-ca/config/ca.json"
   # Should still point to: pkcs11:id=%03;object=Private%20key%20for%20Key%20Management
   ```

8. **Restart step-ca and verify:**
   ```bash
   ssh root@ca.funlab.casa "
     # Ensure YubiKey PIN is available
     /usr/local/bin/setup-yubikey-pin-for-step-ca

     # Restart step-ca
     systemctl restart step-ca

     # Check service status
     systemctl status step-ca

     # Check health endpoint
     sleep 5
     curl -k https://ca.funlab.casa:443/health
   "

   # Verify no YubiKey errors in logs
   ssh root@ca.funlab.casa "journalctl -u step-ca -n 50 | grep -i yubikey"
   ssh root@ca.funlab.casa "journalctl -u step-ca -n 50 | grep -i 'CKR_USER_NOT_LOGGED_IN'"
   # Should be no CKR_USER_NOT_LOGGED_IN errors
   ```

**Success Criteria:**
- [ ] Eye of Thundera v2 root CA generated (PKCS#8 format)
- [ ] Sword of Omens v2 intermediate CA generated (PKCS#8 format)
- [ ] Intermediate signed by new root
- [ ] Chain validates correctly
- [ ] Both keys backed up to 1Password (encrypted)
- [ ] Intermediate key imported to YubiKey Slot 9d
- [ ] Certificates installed to step-ca
- [ ] step-ca service healthy
- [ ] YubiKey access working (no login errors)

---

### Phase 3: Distribute New Root CA Trust (1 hour)

**Objectives:**
- Install new Eye of Thundera v2 root CA to all hosts
- Update system trust stores
- Update service-specific trust configurations
- Verify trust chain validation

**This phase is CRITICAL for the DR exercise - all systems must trust the new root CA.**

**Steps:**

1. **Install root CA to system trust store (all 3 hosts):**
   ```bash
   for host in spire auth ca; do
     echo "=== Installing root CA on $host ==="

     # Copy new root CA
     scp eye-of-thundera-v2-cert.pem root@${host}.funlab.casa:/tmp/

     ssh root@${host}.funlab.casa "
       # Install to system trust store
       cp /tmp/eye-of-thundera-v2-cert.pem \
         /usr/local/share/ca-certificates/eye-of-thundera-v2.crt

       # Update system CA trust
       update-ca-certificates

       # Verify installation
       ls -l /usr/local/share/ca-certificates/eye-of-thundera-v2.crt

       echo \"Root CA installed on $host\"
     "
   done
   ```

2. **Update Keylime CA trust (all 3 hosts):**
   ```bash
   for host in spire auth ca; do
     echo "=== Updating Keylime trust on $host ==="

     ssh root@${host}.funlab.casa "
       # Backup old root CA
       cp /etc/keylime/certs/ca-root-only.crt \
          /etc/keylime/certs/ca-root-only.crt.backup-v1

       # Install new root CA
       cp /tmp/eye-of-thundera-v2-cert.pem \
          /etc/keylime/certs/ca-root-only.crt

       # Set ownership
       chown keylime:tss /etc/keylime/certs/ca-root-only.crt
       chmod 644 /etc/keylime/certs/ca-root-only.crt

       echo \"Keylime trust updated on $host\"
     "
   done
   ```

3. **Update SPIRE trust bundles (if applicable):**
   ```bash
   for host in spire auth ca; do
     echo "=== Checking SPIRE trust on $host ==="

     ssh root@${host}.funlab.casa "
       if [ -f /opt/spire/conf/agent/bundle.crt ]; then
         echo \"SPIRE bundle found on $host\"
         cp /tmp/eye-of-thundera-v2-cert.pem \
           /opt/spire/conf/agent/bundle.crt.new
         echo \"New bundle staged at bundle.crt.new - MANUAL REVIEW REQUIRED\"
       else
         echo \"No SPIRE bundle on $host\"
       fi
     "
   done
   ```

4. **Verify trust chain (all hosts):**
   ```bash
   for host in spire auth ca; do
     echo "=== Verifying trust on $host ==="

     ssh root@${host}.funlab.casa "
       # Test that new root CA is trusted by system
       openssl verify /tmp/eye-of-thundera-v2-cert.pem

       # Verify it's in system trust store
       grep -l 'Eye of Thundera v2' /etc/ssl/certs/*.pem 2>/dev/null | head -1

       # Verify Keylime trust
       openssl x509 -in /etc/keylime/certs/ca-root-only.crt -noout -subject
     "
   done
   ```

**Success Criteria:**
- [ ] Root CA installed to `/usr/local/share/ca-certificates/` on all 3 hosts
- [ ] `update-ca-certificates` ran without errors on all hosts
- [ ] `/etc/keylime/certs/ca-root-only.crt` updated on all 3 hosts
- [ ] `openssl verify` confirms root CA is trusted on all hosts
- [ ] System trust store contains new root (checked in `/etc/ssl/certs/`)

---

### Phase 4: Update OpenBao PKI (1 hour)

**Objectives:**
- Generate new Book of Omens v2 intermediate CSR in OpenBao
- Sign with new Sword of Omens v2 intermediate
- Import signed cert back to OpenBao
- Verify certificate issuance works with new chain

**Steps:**

1. **Generate new OpenBao intermediate CSR:**
   ```bash
   ssh root@spire.funlab.casa "
     export BAO_ADDR='https://bao.funlab.casa:8200'
     export BAO_CACERT='/etc/keylime/certs/ca-complete-chain.crt'

     # Generate new intermediate CSR
     bao write -format=json pki_int/intermediate/generate/internal \
       common_name='Book of Omens v2' \
       organization='Funlab.Casa' \
       ou='Tower of Omens' \
       country='US' \
       key_type='rsa' \
       key_bits=4096 \
       > /tmp/book-of-omens-v2-csr.json

     # Extract CSR
     cat /tmp/book-of-omens-v2-csr.json | jq -r '.data.csr' > /tmp/book-of-omens-v2.csr

     # Verify CSR
     openssl req -in /tmp/book-of-omens-v2.csr -noout -text | head -20
   "

   # Copy CSR to ca.funlab.casa for signing
   scp root@spire.funlab.casa:/tmp/book-of-omens-v2.csr /tmp/
   scp /tmp/book-of-omens-v2.csr root@ca.funlab.casa:/tmp/
   ```

2. **Sign CSR with new Sword of Omens v2:**
   ```bash
   ssh root@ca.funlab.casa "
     # Ensure YubiKey PIN is available
     /usr/local/bin/setup-yubikey-pin-for-step-ca

     # Sign the CSR using step-ca
     step certificate sign /tmp/book-of-omens-v2.csr \
       /etc/step-ca/certs/intermediate_ca.crt \
       --kms 'pkcs11:module-path=/usr/lib/x86_64-linux-gnu/libykcs11.so;token=YubiKey%20PIV;id=%03;object=Private%20key%20for%20Key%20Management?pin-source=/run/step-ca/yubikey-pin' \
       --template /etc/step-ca/templates/intermediate-ca.tpl \
       --not-after 87600h \
       > /tmp/book-of-omens-v2-signed.crt

     # Verify signed certificate
     openssl x509 -in /tmp/book-of-omens-v2-signed.crt -noout -text | grep -A5 'Subject:'
   "

   # Copy signed cert back to spire
   scp root@ca.funlab.casa:/tmp/book-of-omens-v2-signed.crt /tmp/
   scp /tmp/book-of-omens-v2-signed.crt root@spire.funlab.casa:/tmp/
   ```

3. **Import to OpenBao:**
   ```bash
   ssh root@spire.funlab.casa "
     export BAO_ADDR='https://bao.funlab.casa:8200'
     export BAO_CACERT='/etc/keylime/certs/ca-complete-chain.crt'

     # Import signed intermediate
     bao write pki_int/intermediate/set-signed \
       certificate=@/tmp/book-of-omens-v2-signed.crt

     # Verify import
     bao read -format=json pki_int/cert/ca | jq -r '.data.certificate' > /tmp/book-of-omens-v2-verify.crt
     openssl x509 -in /tmp/book-of-omens-v2-verify.crt -noout -subject -issuer
   "
   ```

4. **Test certificate issuance:**
   ```bash
   ssh root@spire.funlab.casa "
     export BAO_ADDR='https://bao.funlab.casa:8200'
     export BAO_CACERT='/etc/keylime/certs/ca-complete-chain.crt'

     # Issue test certificate via keylime-services role
     bao write -format=json pki_int/issue/keylime-services \
       common_name='test-cert.funlab.casa' \
       ttl=24h \
       > /tmp/test-cert.json

     # Extract and verify
     cat /tmp/test-cert.json | jq -r '.data.certificate' > /tmp/test-cert.crt
     cat /tmp/test-cert.json | jq -r '.data.ca_chain[]' > /tmp/test-cert-chain.crt

     # Verify issuer
     openssl x509 -in /tmp/test-cert.crt -noout -issuer
     # Should show: issuer=CN=Book of Omens v2,...

     # Verify chain
     openssl verify -CAfile /etc/keylime/certs/ca-root-only.crt \
       -untrusted /tmp/test-cert-chain.crt \
       /tmp/test-cert.crt
     # Should return: OK
   "
   ```

5. **Extract and distribute new CA bundles:**
   ```bash
   ssh root@spire.funlab.casa "
     export BAO_ADDR='https://bao.funlab.casa:8200'
     export BAO_CACERT='/etc/keylime/certs/ca-complete-chain.crt'

     # Extract complete chain from OpenBao
     bao read -field=certificate pki_int/cert/ca > /tmp/book-of-omens-v2.crt

     # Create complete chain: Book of Omens v2 -> Sword of Omens v2 -> Eye of Thundera v2
     cat /tmp/book-of-omens-v2.crt > /tmp/ca-complete-chain-v2.crt
     cat /tmp/sword-of-omens-v2-cert.pem >> /tmp/ca-complete-chain-v2.crt
     cat /tmp/eye-of-thundera-v2-cert.pem >> /tmp/ca-complete-chain-v2.crt
   "

   # Distribute to all hosts
   for host in spire auth ca; do
     echo "=== Distributing CA bundles to $host ==="

     scp /tmp/eye-of-thundera-v2-cert.pem root@${host}.funlab.casa:/tmp/ca-root-only-v2.crt
     scp /tmp/ca-complete-chain-v2.crt root@${host}.funlab.casa:/tmp/

     ssh root@${host}.funlab.casa "
       # Backup old bundles
       cp /etc/keylime/certs/ca-root-only.crt /etc/keylime/certs/ca-root-only.crt.backup-v1
       cp /etc/keylime/certs/ca-complete-chain.crt /etc/keylime/certs/ca-complete-chain.crt.backup-v1

       # Install new bundles
       cp /tmp/ca-root-only-v2.crt /etc/keylime/certs/ca-root-only.crt
       cp /tmp/ca-complete-chain-v2.crt /etc/keylime/certs/ca-complete-chain.crt

       # Set ownership
       chown keylime:tss /etc/keylime/certs/ca-*.crt
       chmod 644 /etc/keylime/certs/ca-*.crt

       # Verify
       ls -l /etc/keylime/certs/ca-*.crt
     "
   done

   # Update nginx CA chain on spire
   ssh root@spire.funlab.casa "
     cp /tmp/ca-complete-chain-v2.crt /etc/nginx/certs/keylime-ca-chain.crt
     chown nginx:nginx /etc/nginx/certs/keylime-ca-chain.crt
     chmod 644 /etc/nginx/certs/keylime-ca-chain.crt
   "
   ```

**Success Criteria:**
- [ ] Book of Omens v2 CSR generated in OpenBao
- [ ] CSR signed by Sword of Omens v2
- [ ] Signed cert imported to OpenBao
- [ ] Test certificate issued successfully
- [ ] Test cert chain validates: Test → Book of Omens v2 → Sword of Omens v2 → Eye of Thundera v2
- [ ] CA bundles distributed to all 3 hosts
- [ ] Nginx CA chain updated on spire

---

### Phase 5: Renew All Service Certificates (1 hour)

**Objectives:**
- Trigger immediate certificate renewal with new PKI chain
- Restart all affected services in correct order
- Verify services come up successfully

**Steps:**

1. **Renew Keylime certificates on all hosts:**
   ```bash
   for host in spire auth ca; do
     echo "=== Renewing Keylime certificates on $host ==="

     ssh root@${host}.funlab.casa "
       # Run renewal script (already handles PKCS#8 conversion)
       /usr/local/bin/renew-keylime-certs.sh

       # Verify new certificates
       openssl x509 -in /etc/keylime/certs/agent.crt -noout -subject -issuer

       # Verify chain
       openssl verify -CAfile /etc/keylime/certs/ca-root-only.crt \
         -untrusted /etc/keylime/certs/ca-complete-chain.crt \
         /etc/keylime/certs/agent.crt
     "
   done
   ```

2. **Renew nginx certificates:**
   ```bash
   ssh root@spire.funlab.casa "
     # Run nginx renewal script
     /usr/local/bin/renew-nginx-certs.sh

     # Verify new certificates
     openssl x509 -in /etc/nginx/certs/nginx.crt -noout -subject -issuer
   "
   ```

3. **Restart services in correct order:**
   ```bash
   echo "=== Step 1: Restart Keylime agents on all hosts ==="
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "systemctl restart keylime_agent"
   done

   sleep 5

   echo "=== Step 2: Restart Keylime registrar and verifier on spire ==="
   ssh root@spire.funlab.casa "
     systemctl restart keylime_registrar
     systemctl restart keylime_verifier
   "

   sleep 5

   echo "=== Step 3: Restart nginx on spire ==="
   ssh root@spire.funlab.casa "systemctl restart nginx"

   sleep 5

   echo "=== Step 4: Restart SPIRE agents (if running) ==="
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "
       if systemctl is-active --quiet spire-agent; then
         systemctl restart spire-agent
       fi
     "
   done
   ```

4. **Verify service status:**
   ```bash
   echo "=== Verifying service status ==="

   for host in spire auth ca; do
     echo "--- $host ---"
     ssh root@${host}.funlab.casa "
       systemctl is-active keylime_agent
       if systemctl list-unit-files | grep -q spire-agent; then
         systemctl is-active spire-agent || echo 'spire-agent not running'
       fi
     "
   done

   echo "--- spire (registrar/verifier/nginx) ---"
   ssh root@spire.funlab.casa "
     systemctl is-active keylime_registrar
     systemctl is-active keylime_verifier
     systemctl is-active nginx
   "
   ```

**Success Criteria:**
- [ ] Keylime certificates renewed on all 3 hosts
- [ ] Nginx certificates renewed on spire
- [ ] All Keylime agents active
- [ ] Keylime registrar and verifier active on spire
- [ ] Nginx active on spire
- [ ] SPIRE agents active (if applicable)
- [ ] No TLS validation errors in logs

---

### Phase 6: Verification & Testing (1 hour)

**Objectives:**
- Verify complete certificate chains on all hosts
- Test Keylime agent registration
- Test new certificate issuance from step-ca
- Confirm PKCS#8 format

**Steps:**

1. **Certificate chain validation:**
   ```bash
   for host in spire auth ca; do
     echo "=== Validating certificate chains on $host ==="

     ssh root@${host}.funlab.casa "
       # Verify agent certificate chain
       openssl verify -CAfile /etc/keylime/certs/ca-root-only.crt \
         -untrusted /etc/keylime/certs/ca-complete-chain.crt \
         /etc/keylime/certs/agent.crt

       # Check certificate details
       echo '--- Agent Certificate ---'
       openssl x509 -in /etc/keylime/certs/agent.crt -noout -subject -issuer -dates

       # Check for expiration
       openssl x509 -in /etc/keylime/certs/agent.crt -noout -checkend 86400
     "
   done

   # Verify nginx certificates
   ssh root@spire.funlab.casa "
     echo '=== Nginx Certificate Validation ==='
     openssl verify -CAfile /etc/keylime/certs/ca-root-only.crt \
       -untrusted /etc/nginx/certs/keylime-ca-chain.crt \
       /etc/nginx/certs/nginx.crt

     # Test HTTPS endpoint
     curl -v https://localhost:8443 2>&1 | grep 'SSL certificate verify'
   "
   ```

2. **Test Keylime agent re-registration:**
   ```bash
   # Test on one agent (auth host)
   ssh root@auth.funlab.casa "
     # Stop agent
     systemctl stop keylime_agent

     # Remove agent data (forces re-registration)
     rm -f /var/lib/keylime/agent_data.json

     # Restart agent
     systemctl start keylime_agent

     # Wait for registration
     sleep 10

     # Check logs
     journalctl -u keylime_agent -n 50 | grep -i 'registr'
   "

   # Verify on registrar
   ssh root@spire.funlab.casa "
     journalctl -u keylime_registrar -n 50 | grep -i 'auth.funlab.casa'
   "
   ```

3. **Test step-ca certificate issuance:**
   ```bash
   ssh root@ca.funlab.casa "
     # Test ACME certificate issuance (if ACME enabled)
     step ca health

     # Test manual certificate issuance
     step ca certificate test.funlab.casa test.crt test.key \
       --provisioner admin \
       --not-after 24h

     # Verify issuer
     openssl x509 -in test.crt -noout -issuer
     # Should show: issuer=CN=Sword of Omens v2,...

     # Cleanup
     rm -f test.crt test.key
   "
   ```

4. **Verify PKCS#8 key format:**
   ```bash
   # Check intermediate CA key on YubiKey (indirect verification)
   ssh root@ca.funlab.casa "
     # Verify step-ca can use YubiKey key
     journalctl -u step-ca -n 100 | grep -i 'pkcs11'
     journalctl -u step-ca -n 100 | grep -i 'yubikey'

     # Should show successful PKCS#11 operations, no format errors
   "

   # Check agent keys (PKCS#8 format)
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "
       if [ -f /etc/keylime/certs/agent-pkcs8.key ]; then
         echo '=== Agent key format on $host ==='
         head -1 /etc/keylime/certs/agent-pkcs8.key
         # Should show: -----BEGIN PRIVATE KEY-----
       fi
     "
   done
   ```

5. **Monitor automated renewals:**
   ```bash
   for host in spire auth ca; do
     echo "=== Renewal timer status on $host ==="
     ssh root@${host}.funlab.casa "
       # Check timer is active
       systemctl list-timers renew-keylime-certs.timer

       # Check next run time
       systemctl status renew-keylime-certs.timer | grep 'Trigger:'
     "
   done
   ```

**Success Criteria:**
- [ ] All certificate chains validate correctly
- [ ] Certificates signed by Book of Omens v2 → Sword of Omens v2 → Eye of Thundera v2
- [ ] Keylime agent re-registration succeeds
- [ ] step-ca issues certificates signed by Sword of Omens v2
- [ ] PKCS#8 format confirmed for all new keys
- [ ] No TLS errors in service logs
- [ ] Renewal timers active and scheduled

---

### Phase 7: Post-Migration Monitoring (24 hours)

**Objectives:**
- Monitor first automated renewal cycle
- Update documentation
- Verify stability

**Tasks:**

1. **Monitor automated renewals:**
   ```bash
   # Day 1: Check timer execution (daily at 2 AM)
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "
       journalctl -u renew-keylime-certs.service --since '2 hours ago' | tail -50
       journalctl -u renew-keylime-certs.timer --since '2 hours ago'
     "
   done

   # Check monitoring timer (every 6 hours)
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "
       journalctl -u monitor-keylime-certs.service --since '6 hours ago' | tail -50
     "
   done
   ```

2. **Update documentation:**
   ```bash
   # Create migration completion document
   cat > /home/bullwinkle/infrastructure/STEP-CA-PKCS8-MIGRATION-COMPLETE.md << 'EOF'
   # step-ca PKCS#8 Migration - COMPLETE

   **Date:** $(date -u +%Y-%m-%d)
   **Duration:** [FILL IN ACTUAL TIME]
   **Result:** SUCCESS / PARTIAL / FAILED

   ## What Changed

   - Root CA: Eye of Thundera v1 → Eye of Thundera v2 (NEW, PKCS#8)
   - Intermediate CA: Sword of Omens v1 → Sword of Omens v2 (NEW, PKCS#8)
   - OpenBao PKI: Book of Omens v1 → Book of Omens v2 (re-signed)
   - All infrastructure certificates: Reissued from new PKI chain
   - All keys: 100% PKCS#8 format

   ## Verification Results

   [FILL IN VERIFICATION CHECKLIST RESULTS]

   ## Issues Encountered

   [DOCUMENT ANY ISSUES AND RESOLUTIONS]

   ## Lessons Learned

   [DR EXERCISE INSIGHTS]

   ## Recovery Timeline

   - Phase 1 (Backup): [TIME]
   - Phase 2 (CA Regeneration): [TIME]
   - Phase 3 (Trust Distribution): [TIME]
   - Phase 4 (OpenBao PKI): [TIME]
   - Phase 5 (Certificate Renewal): [TIME]
   - Phase 6 (Verification): [TIME]
   - Total: [TOTAL TIME]

   ## 1Password Updates

   - [x] Eye of Thundera v2 root CA key and cert stored
   - [x] Sword of Omens v2 intermediate CA key and cert stored (backup)
   - [x] Item notes updated with migration date
   - [ ] Old v1 items marked as deprecated (keep for 30 days)
   EOF

   # Update 1Password notes
   # Manually update items in Funlab.Casa.Ca vault
   # Add note: "Migrated to v2 on [DATE]. v1 deprecated, keep for rollback until [DATE+30]."
   ```

3. **Validation checklist:**
   ```bash
   echo "=== Final Validation Checklist ==="

   # step-ca service healthy
   ssh root@ca.funlab.casa "systemctl is-active step-ca && curl -k https://ca.funlab.casa:443/health"

   # Intermediate CA is PKCS#8 format
   ssh root@ca.funlab.casa "
     yubico-piv-tool -a status | grep '9d'
     # Verify YubiKey has key in Slot 9d
   "

   # OpenBao PKI issues certificates successfully
   ssh root@spire.funlab.casa "
     export BAO_ADDR='https://bao.funlab.casa:8200'
     export BAO_CACERT='/etc/keylime/certs/ca-complete-chain.crt'
     bao write pki_int/issue/keylime-services common_name=test.funlab.casa ttl=1h -format=json | jq -r '.data.certificate' | openssl x509 -noout -issuer
   "

   # All Keylime agents attesting
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "systemctl is-active keylime_agent"
   done

   # Nginx serving correct certificates
   ssh root@spire.funlab.casa "
     echo | openssl s_client -connect localhost:8443 2>/dev/null | openssl x509 -noout -issuer
   "

   # Certificate renewal timers functional
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "
       systemctl is-active renew-keylime-certs.timer
       systemctl is-active monitor-keylime-certs.timer
     "
   done

   echo "=== Validation Complete ==="
   echo ""
   echo "Checklist:"
   echo "[ ] step-ca service healthy"
   echo "[ ] Intermediate CA is PKCS#8 format"
   echo "[ ] OpenBao PKI issues certificates successfully"
   echo "[ ] All Keylime agents attesting"
   echo "[ ] Nginx serving correct certificates"
   echo "[ ] Certificate renewal timers functional"
   echo "[ ] Documentation updated"
   echo "[ ] Old backups retained for 30 days"
   ```

**Success Criteria:**
- [ ] First automated renewal cycle completes successfully
- [ ] No certificate expiration alerts
- [ ] All services remain healthy
- [ ] Migration completion document created
- [ ] 1Password updated with v2 keys and deprecation notes
- [ ] Old backups retained at `/root/step-ca-backup-*/`

---

## Rollback Procedure

**If migration fails at any point:**

### Emergency Rollback Steps

1. **Restore step-ca on ca.funlab.casa:**
   ```bash
   ssh root@ca.funlab.casa "
     # Stop step-ca
     systemctl stop step-ca

     # Find latest backup
     BACKUP_DIR=\$(ls -td /root/step-ca-backup-* | head -1)
     echo \"Restoring from: \$BACKUP_DIR\"

     # Restore from backup
     tar -xzf \$BACKUP_DIR/step-ca-full.tar.gz -C /

     # Restore database
     rm -rf /etc/step-ca/db
     cp -r \$BACKUP_DIR/db-backup /etc/step-ca/db

     # Restart step-ca
     systemctl start step-ca
     systemctl status step-ca

     # Verify health
     curl -k https://ca.funlab.casa:443/health
   "
   ```

2. **Restore CA bundles on all hosts:**
   ```bash
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "
       # Restore old CA bundles
       cp /etc/keylime/certs/ca-root-only.crt.backup-v1 \
          /etc/keylime/certs/ca-root-only.crt
       cp /etc/keylime/certs/ca-complete-chain.crt.backup-v1 \
          /etc/keylime/certs/ca-complete-chain.crt

       # Set ownership
       chown keylime:tss /etc/keylime/certs/ca-*.crt
       chmod 644 /etc/keylime/certs/ca-*.crt
     "
   done
   ```

3. **Restore OpenBao PKI (if changed):**
   ```bash
   ssh root@spire.funlab.casa "
     export BAO_ADDR='https://bao.funlab.casa:8200'
     export BAO_CACERT='/etc/keylime/certs/ca-complete-chain.crt'

     # Restore old intermediate from backup
     cat /tmp/book-of-omens-pre.json | jq -r '.data.certificate' > /tmp/book-of-omens-restore.crt
     bao write pki_int/intermediate/set-signed certificate=@/tmp/book-of-omens-restore.crt
   "
   ```

4. **Renew certificates with old PKI:**
   ```bash
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "/usr/local/bin/renew-keylime-certs.sh"
   done

   ssh root@spire.funlab.casa "/usr/local/bin/renew-nginx-certs.sh"
   ```

5. **Restart all services:**
   ```bash
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "systemctl restart keylime_agent"
   done

   ssh root@spire.funlab.casa "
     systemctl restart keylime_registrar
     systemctl restart keylime_verifier
     systemctl restart nginx
   "
   ```

6. **Verify rollback:**
   ```bash
   for host in spire auth ca; do
     ssh root@${host}.funlab.casa "
       openssl x509 -in /etc/keylime/certs/agent.crt -noout -issuer
       # Should show old issuer (Book of Omens v1)
       systemctl is-active keylime_agent
     "
   done
   ```

**Rollback Time:** 15-30 minutes
**Risk:** Low - complete backups ensure full restoration

---

## Risk Assessment

### High-Risk Operations

| Operation | Risk | Mitigation | Rollback |
|-----------|------|------------|----------|
| OpenBao PKI Update | Breaking trust for all infrastructure certificates | Test issuance before distributing to agents | Previous intermediate available in backup |
| Certificate Renewal | Keylime agents fail to renew and expire | Manual renewal first, verify before relying on timers | Restore old certificates from backup |
| Service Restart | Services fail with new certificates | Restart in correct order (Keylime → Nginx → SPIRE) | Complete rollback procedure (15-30 min) |
| YubiKey Key Import | Overwriting working intermediate key | Delete old key explicitly, verify import before deleting old certs | Cannot rollback key once deleted - rely on 1Password backup |
| Root CA Trust Distribution | Breaking system-wide trust | Install to user trust store first (/usr/local/share), not system (/etc/ssl) | Remove from /usr/local/share/ca-certificates, run update-ca-certificates |

### Critical Success Factors

1. **Complete backup before starting** - Validated and tested
2. **New root CA trust distributed** - All systems must trust Eye of Thundera v2
3. **Coordinated renewal** - All certs renewed in same maintenance window
4. **Service orchestration** - Correct restart order prevents cascade failures
5. **YubiKey access** - PIN and management key must be available

### Disaster Recovery Benefits

- **Complete CA loss recovery** procedure validated
- **Trust redistribution** process tested and documented
- **Full playbook** ready for actual disaster scenario
- **All dependencies** and touch points identified
- **Recovery timeline** validated (7 hours active work)

---

## Timeline Summary

| Phase | Duration | Description |
|-------|----------|-------------|
| 1. Pre-Migration | 1 hour | Backup, document, freeze |
| 2. Regenerate CAs | 2 hours | NEW root + intermediate (PKCS#8) |
| 3. Distribute Trust | 1 hour | Install to all hosts |
| 4. Update OpenBao PKI | 1 hour | New Book of Omens |
| 5. Renew Certificates | 1 hour | All services |
| 6. Verification | 1 hour | Testing & validation |
| 7. Monitoring | 24 hours | Passive observation |
| **Total active work** | **7 hours** | Hands-on time |

**Recommended Schedule:**
- Start: Tuesday 9 AM
- Complete: Tuesday 4 PM (7 hours)
- Monitor through: Wednesday 4 PM

---

## End State

**After full DR exercise:**

```
Eye of Thundera v2 (NEW Root CA)
├─ Format: PKCS#8, RSA 4096
├─ Validity: 100 years
├─ Storage: 1Password (encrypted) + /etc/step-ca/certs/root_ca.crt
│
└─── Sword of Omens v2 (NEW Intermediate CA)
     ├─ Format: PKCS#8, RSA 2048
     ├─ Validity: 10 years
     ├─ Storage: YubiKey Slot 9d (primary) + 1Password (DR backup)
     │
     └─── Book of Omens v2 (OpenBao PKI Intermediate)
          ├─ Format: PKCS#8, RSA 4096
          ├─ Validity: 10 years
          ├─ Signs all infrastructure certificates
          │
          └─── Service Certificates (24h-30d TTL)
               ├─ Keylime Agent/Registrar/Verifier (24h, PKCS#8)
               ├─ Nginx TLS (30d, PKCS#8)
               └─ All infrastructure (PKCS#8)
```

**Benefits:**
- 100% PKCS#8 standardization from root to leaf
- Complete disaster recovery capability validated
- Trust distribution mechanism tested
- Full playbook for actual CA loss scenario
- All dependencies documented
- Recovery timeline established (7 hours)

---

## Files Modified

### step-ca Configuration (ca.funlab.casa)

- `/etc/step-ca/certs/root_ca.crt` - NEW Eye of Thundera v2
- `/etc/step-ca/certs/intermediate_ca.crt` - NEW Sword of Omens v2
- `/etc/step-ca/config/ca.json` - Verify KMS config (should remain unchanged)
- YubiKey Slot 9d - NEW PKCS#8 intermediate key

### Trust Bundles (All 3 Hosts)

- `/etc/keylime/certs/ca-root-only.crt` - NEW root CA
- `/etc/keylime/certs/ca-complete-chain.crt` - NEW complete chain
- `/usr/local/share/ca-certificates/eye-of-thundera-v2.crt` - System trust
- `/etc/ssl/certs/` - Auto-updated by update-ca-certificates

### Nginx (spire.funlab.casa)

- `/etc/nginx/certs/keylime-ca-chain.crt` - NEW CA chain

### Service Certificates (Automatic via renewal scripts)

- `/etc/keylime/certs/agent.crt` - Renewed (all hosts)
- `/etc/keylime/certs/agent-pkcs8.key` - PKCS#8 format (all hosts)
- `/etc/keylime/certs/registrar.crt` - Renewed (spire)
- `/etc/keylime/certs/verifier.crt` - Renewed (spire)
- `/etc/nginx/certs/nginx.crt` - Renewed (spire)
- `/etc/nginx/certs/nginx-pkcs8.key` - PKCS#8 format (spire)

### Backups Created

- `/root/step-ca-backup-*/` - Complete step-ca backup (ca.funlab.casa)
- `/etc/keylime/certs/*.backup-v1` - Old CA bundles (all hosts)
- `/tmp/pre-migration-state-*.txt` - Pre-migration state (all hosts)

---

## 1Password Updates Required

**New Items to Create:**

1. **Eye of Thundera v2 - Root CA Private Key (PKCS8)**
   - Type: Document
   - File: `eye-of-thundera-v2-key-encrypted.pem`
   - Password: [Set strong password, update in item]
   - Notes: Created during PKCS#8 DR exercise on [DATE]. Replaces v1.

2. **Eye of Thundera v2 - Root CA Certificate**
   - Type: Document
   - File: `eye-of-thundera-v2-cert.pem`
   - Notes: Created during PKCS#8 DR exercise on [DATE]. Replaces v1.

3. **Sword of Omens v2 - Intermediate CA Private Key (PKCS8) - Backup**
   - Type: Document
   - File: `sword-of-omens-v2-key-encrypted.pem`
   - Password: [Set strong password, update in item]
   - Notes: DR BACKUP ONLY. Primary key on YubiKey Slot 9d. Created [DATE]. Replaces v1.

4. **Sword of Omens v2 - Intermediate CA Certificate**
   - Type: Document
   - File: `sword-of-omens-v2-cert.pem`
   - Notes: Created during PKCS#8 DR exercise on [DATE]. Replaces v1. Primary key on YubiKey.

**Existing Items to Update:**

1. **Eye of Thundera - Root CA Private Key** (v1)
   - Add note: "DEPRECATED. Replaced by v2 on [DATE]. Keep for rollback until [DATE+30]."

2. **Sword of Omens - Intermediate CA Private Key** (v1)
   - Add note: "DEPRECATED. Replaced by v2 on [DATE]. Keep for rollback until [DATE+30]."

3. **YubiKey NEO - ca.funlab.casa**
   - Add note: "Slot 9d updated with Sword of Omens v2 key on [DATE]."

---

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] YubiKey NEO #5497305 physically connected to workstation
- [ ] 1Password CLI (`op`) configured and authenticated
- [ ] Access to 1Password Funlab.Casa.Ca vault
- [ ] YubiKey PIN: `S1iNIv2g` (from 1Password)
- [ ] YubiKey Management Key: `de0836a40794ff047e9dc1658a98a3471af2b63a309ce111` (from 1Password)
- [ ] SSH access to all 3 hosts (spire, auth, ca)
- [ ] Root privileges on all hosts
- [ ] Patched step-ca binary: `/tmp/step-ca-full-pkcs8-binary`
- [ ] 7 hours of uninterrupted time (Tuesday 9 AM - 4 PM recommended)
- [ ] Network connectivity stable
- [ ] All stakeholders notified of maintenance window
- [ ] Rollback procedure reviewed and understood

---

## Notes

- This is a **disaster recovery exercise** - we're simulating complete CA loss
- All keys will be PKCS#8 format (Eye of Thundera → Sword of Omens → Book of Omens → Services)
- YubiKey Slot 9d chosen over 9c (9c requires PIN per operation, causes issues)
- Intermediate key primary storage: YubiKey (hardware-backed), 1Password backup for DR
- Root CA trust MUST be redistributed to all systems (this is the DR exercise)
- Service downtime expected during certificate renewal phase (~15 minutes)
- Monitor first automated renewal cycle (next day at 2 AM)
- Keep all backups for 30 days minimum
- Update 1Password immediately after completion

---

## Status Log

**2026-02-13:** Plan documented, ready to execute
**[DATE]:** Phase 1 started - Pre-migration backup
**[DATE]:** Phase 2 complete - CAs regenerated
**[DATE]:** Phase 3 complete - Trust distributed
**[DATE]:** Phase 4 complete - OpenBao PKI updated
**[DATE]:** Phase 5 complete - Certificates renewed
**[DATE]:** Phase 6 complete - Verification passed
**[DATE]:** Phase 7 monitoring - First renewal cycle successful
**[DATE]:** Migration COMPLETE

---

**END OF PLAN**
