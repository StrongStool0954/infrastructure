# tinyca.funlab.casa - CA Infrastructure Review

**Date:** 2026-02-10
**Purpose:** Review existing CA before deploying ca.funlab.casa (step-ca) with Yubikey

---

## 🔍 Current State - tinyca.funlab.casa

### Infrastructure Details
- **Hostname:** tinyca.funlab.casa
- **IP Address:** 10.10.2.25
- **Platform:** ARM64 (Raspberry Pi or similar)
- **Software:** Smallstep step-ca (running since 2026-02-06)
- **Port:** 9000 (HTTPS)
- **Status:** ✅ Active and running (3 days uptime)

### Certificate Hierarchy

```
Third Earth (Root CA)
├── Type: X.509v3 Root CA Certificate
├── Key: RSA 4096-bit
├── Serial: 9142...8556
├── Subject: Third Earth
├── Issuer: Third Earth (self-signed)
├── Valid From: 2025-11-29T14:28:17Z
├── Valid To: 2094-11-29T14:28:17Z
├── Validity: 69 years ✅
└── Location: /etc/step/certs/root_ca.crt

    └── Thundera (Intermediate CA)
        ├── Type: X.509v3 Intermediate CA Certificate
        ├── Key: RSA 2048-bit
        ├── Serial: 5152
        ├── Subject: Thundera
        ├── Issuer: Third Earth
        ├── Valid From: 2025-11-29T14:34:00Z
        ├── Valid To: 2035-11-27T14:34:00Z
        ├── Validity: ~9 years
        └── Location: /etc/step/certs/intermediate_ca.crt
```

### step-ca Configuration
```json
{
  "root": "/etc/step/certs/root_ca.crt",
  "crt": "/etc/step/certs/intermediate_ca.crt",
  "dnsNames": ["tinyca.funlab.casa"],
  "address": ":9000"
}
```

### Features Enabled
- ✅ ACME protocol support
- ✅ HTTPS endpoint on port 9000
- ✅ Automated certificate issuance
- ✅ Active provisioner configured

### Files Present
```
/etc/step/
├── certs/
│   ├── root_ca.crt (Third Earth - Root CA)
│   ├── intermediate_ca.crt (Thundera - Intermediate CA)
│   └── intermediate_ca.srl
├── secrets/
│   └── (private keys - encrypted)
├── config/
│   └── ca.json
├── db/
│   └── (certificate database)
├── templates/
│   └── (certificate templates)
├── password.txt
└── provisioner-pw-temp.txt
```

---

## 🤔 Decision Point: CA Architecture for Tower of Omens

### Option 1: Use tinyca as Root for Everything (Simplest)

```
Third Earth (Root CA - tinyca)
└── Thundera (Intermediate CA - tinyca)
    └── ca.funlab.casa issues certificates
        └── Tower of Omens services use these certs
```

**Pros:**
- ✅ Simple - reuse existing infrastructure
- ✅ Single root of trust
- ✅ tinyca already operational

**Cons:**
- ❌ Tower of Omens depends on tinyca (single point of failure)
- ❌ No hardware-backed security for CA key
- ❌ Thundera intermediate expires in 2035 (need renewal)

---

### Option 2: Create New Intermediate on Yubikey under Third Earth (Recommended)

```
Third Earth (Root CA - tinyca)
├── Thundera (Intermediate CA - tinyca)
│   └── tinyca issues general certificates
│
└── Tower of Omens Intermediate (NEW - on Yubikey)
    └── ca.funlab.casa (step-ca)
        └── Tower of Omens services
            └── DevID certificates for TPMs
```

**Pros:**
- ✅ Hardware-backed security (Yubikey for Tower CA key)
- ✅ Separate intermediate for Tower infrastructure
- ✅ Can operate independently from tinyca
- ✅ Better security isolation
- ✅ Root CA stays the same (Third Earth)

**Cons:**
- ⚠️ More complex setup
- ⚠️ Requires Yubikey configuration
- ⚠️ Need to generate CSR and get it signed by root CA

---

### Option 3: Completely Independent CA (Not Recommended)

```
Funlab CA (New Root - ca.funlab.casa)
└── Funlab Intermediate (ca.funlab.casa)
    └── Tower of Omens services
```

**Pros:**
- ✅ Complete independence

**Cons:**
- ❌ Different root of trust than rest of infrastructure
- ❌ Clients need to trust two root CAs
- ❌ More complex certificate management
- ❌ Doesn't leverage existing tinyca infrastructure

---

## 🎯 Recommendation: Option 2 - New Yubikey-backed Intermediate

### Implementation Plan

#### Phase 1: Prepare Root CA Materials
1. **Mount USB drive with root CA private key**
   - Copy Third Earth root CA private key
   - Keep it secured/encrypted
   - Only needed for signing intermediate cert

2. **Copy Third Earth root certificate**
   ```bash
   scp tinyca:/etc/step/certs/root_ca.crt /etc/step-ca/certs/third-earth-root.crt
   ```

#### Phase 2: Configure Yubikey
1. **Initialize Yubikey for PIV**
   ```bash
   ykman piv reset  # Factory reset (if needed)
   ykman piv change-management-key  # Set management key
   ykman piv change-pin  # Set user PIN
   ykman piv change-puk  # Set PUK
   ```

2. **Generate RSA key pair ON Yubikey**
   ```bash
   # Generate 4096-bit RSA key in slot 9c (Digital Signature)
   ykman piv keys generate \
     --algorithm RSA4096 \
     --pin-policy ONCE \
     9c /tmp/yubikey-public.pem
   ```

   **Important:** Key is generated IN the Yubikey and never leaves it!

#### Phase 3: Create Certificate Signing Request (CSR)
1. **Generate CSR from Yubikey key**
   ```bash
   ykman piv certificates request \
     --subject "CN=Tower of Omens CA,O=Funlab,C=US" \
     --valid-days 3650 \
     9c /tmp/yubikey-public.pem /tmp/tower-ca.csr
   ```

#### Phase 4: Sign CSR with Third Earth Root CA
1. **Mount USB with root CA key**
   ```bash
   # Assuming USB is mounted at /media/usb
   ROOT_KEY=/media/usb/third-earth-root-key.pem
   ```

2. **Sign the CSR**
   ```bash
   # Create intermediate CA certificate signed by Third Earth root
   step certificate sign \
     /tmp/tower-ca.csr \
     /tmp/tinyca-root.crt \
     $ROOT_KEY \
     --profile intermediate-ca \
     --not-after 8760h \  # 1 year
     --bundle > /tmp/tower-ca.crt
   ```

#### Phase 5: Import Signed Certificate to Yubikey
```bash
ykman piv certificates import \
  9c /tmp/tower-ca.crt
```

#### Phase 6: Configure step-ca on ca.funlab.casa
1. **Update ca.json configuration**
   ```json
   {
     "root": "/etc/step-ca/certs/third-earth-root.crt",
     "crt": "/etc/step-ca/certs/tower-ca.crt",
     "key": "yubikey:slot-id=9c",
     "address": ":443",
     "dnsNames": ["ca.funlab.casa"]
   }
   ```

2. **Configure step-ca to use Yubikey**
   - step-ca supports Yubikey via PKCS#11
   - Requires yubico-piv-tool or similar
   - Key operations happen on Yubikey

#### Phase 7: Test Certificate Issuance
```bash
# Bootstrap trust
step ca bootstrap --ca-url https://ca.funlab.casa --fingerprint <fingerprint>

# Request test certificate
step ca certificate test.funlab.casa test.crt test.key

# Verify chain
step certificate verify test.crt --roots /etc/step-ca/certs/third-earth-root.crt
```

---

## 🔐 Security Considerations

### Yubikey Benefits
- ✅ **Private key never leaves hardware** - Generated on Yubikey, stays on Yubikey
- ✅ **PIN protection** - Requires PIN for signing operations
- ✅ **Physical security** - Key destroyed if Yubikey lost/destroyed
- ✅ **Audit trail** - Yubikey touch policy can require physical presence
- ✅ **FIPS compliance** - Some Yubikeys are FIPS 140-2 Level 2 certified

### Root CA Key Management
- 🔒 **Keep offline** - Only needed for signing intermediate certs
- 🔒 **Encrypted storage** - USB drive should be encrypted
- 🔒 **Physical security** - Store USB in safe/secure location
- 🔒 **Backup** - Have encrypted backup of root key
- 🔒 **Limited use** - Only bring online for intermediate cert signing

### Intermediate CA Lifespan
- **Recommended:** 1-2 years
- **Renewal process:** Generate new CSR from Yubikey, sign with root CA
- **Zero downtime:** Can have overlapping intermediates during renewal

---

## 📋 Next Steps

### Immediate Actions
1. ✅ Review tinyca infrastructure - COMPLETE
2. ⏳ Locate USB drive with Third Earth root CA key
3. ⏳ Confirm Yubikey model and firmware version
4. ⏳ Decide: Option 1 (simple) vs Option 2 (Yubikey + security)

### If Proceeding with Option 2 (Yubikey)
1. Mount USB drive with root CA key
2. Configure Yubikey (reset, set PIN/PUK/management key)
3. Generate key pair on Yubikey
4. Create CSR
5. Sign CSR with Third Earth root CA
6. Import certificate to Yubikey
7. Reconfigure ca.funlab.casa step-ca to use Yubikey
8. Test certificate issuance
9. Securely store root CA key (offline)

### If Proceeding with Option 1 (Simple)
1. Copy tinyca certificates to ca.funlab.casa
2. Reconfigure step-ca to use tinyca's Thundera intermediate
3. Test certificate issuance
4. Consider Yubikey migration later

---

## ❓ Questions for User

1. **Do you have the Third Earth root CA private key accessible?**
   - On USB drive - what's the path when mounted?
   - Encrypted? If so, what's needed to decrypt?

2. **What Yubikey model do you have?**
   - Yubikey 5 series? (5 NFC, 5C, 5Ci, etc.)
   - Firmware version?

3. **Preference for intermediate certificate lifespan?**
   - 1 year (more secure, annual renewal)
   - 2 years (balanced)
   - 5 years (less frequent renewal)

4. **Should Tower of Omens CA be completely independent of tinyca?**
   - Option 2: Same root (Third Earth), different intermediate
   - Option 3: Completely separate root

5. **PIN/PUK/Management Key strategy for Yubikey?**
   - Store in 1Password?
   - Different location?
   - How to manage securely?

---

## 🗺️ Updated Architecture (Option 2)

```
Third Earth Root CA (tinyca - Offline key on USB)
├── Validity: 2025 → 2094 (69 years)
├── Location: USB drive (encrypted, offline)
│
├── Thundera Intermediate (tinyca.funlab.casa)
│   ├── Validity: 2025 → 2035
│   ├── Port: 9000
│   ├── Purpose: General certificate issuance
│   └── Uses: Internal services, ACME clients
│
└── Tower of Omens Intermediate (ca.funlab.casa) ← NEW!
    ├── Validity: 2026 → 2027 (1 year, renewable)
    ├── Key Storage: Yubikey slot 9c
    ├── Port: 443
    ├── Purpose: Tower of Omens infrastructure
    └── Will Issue:
        ├── DevID certificates for TPM attestation
        ├── Service certificates for OpenBao, SPIRE
        ├── Internal mTLS certificates
        └── Admin certificates
```

---

## 📊 Comparison Matrix

| Aspect | Current (tinyca) | Option 1 (Use tinyca) | Option 2 (Yubikey) |
|--------|------------------|------------------------|---------------------|
| **Root CA** | Third Earth | Third Earth | Third Earth |
| **Intermediate** | Thundera | Thundera | Tower of Omens (NEW) |
| **Key Storage** | Disk (encrypted) | Disk | Yubikey (hardware) |
| **Security** | Good | Good | Excellent |
| **Independence** | N/A | Depends on tinyca | Independent operation |
| **Complexity** | Simple | Simple | Medium |
| **Setup Time** | Already done | 1 hour | 3-4 hours |
| **Best For** | General use | Simple setup | Production security |

---

**Current Status:** Ready to proceed - awaiting user decision on Option 1 vs Option 2

**Recommended:** Option 2 (Yubikey) for Tower of Omens production security

**Next Action:** User confirms Yubikey approach and provides access to root CA key
