# Secure Web Service with mTLS + Bunny CDN - Project Plan

**Date:** 2026-02-11
**Status:** 🔲 Planning Phase
**Goal:** Deploy secure web service accessible only via client certificates on mobile devices

---

## Project Overview

### Objective
Create a secure web service infrastructure where:
- Content is proxied through Bunny.net CDN
- Only authenticated clients with valid mTLS certificates can access
- Firewalla provides network-level security
- Client certificate installed on phone provides seamless authentication
- Nginx Proxy Manager handles reverse proxy and SSL/TLS termination

### Use Cases
- Secure personal web services (dashboards, tools, documents)
- Private APIs accessible only from trusted devices
- Family/team services with device-based authentication
- Zero-trust web access model

---

## Architecture Design

### Proposed Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Internet / Mobile                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │ HTTPS + Client Cert
                            ▼
                  ┌───────────────────┐
                  │   Bunny.net CDN   │
                  │   (Edge Servers)  │
                  └─────────┬─────────┘
                            │
                            │ HTTPS (Origin)
                            ▼
                  ┌───────────────────┐
                  │    Firewalla      │
                  │  (WAN/Firewall)   │
                  │  - Geo-blocking   │
                  │  - Rate limiting  │
                  │  - IDS/IPS        │
                  └─────────┬─────────┘
                            │
                            │ Allow from Bunny IPs
                            ▼
            ┌──────────────────────────────┐
            │      Pica8 Switch            │
            │    (Network Layer)           │
            └──────────────┬───────────────┘
                           │
                           │ Internal Network
                           ▼
            ┌──────────────────────────────┐
            │  Nginx Proxy Manager (NPM)   │
            │  - mTLS Validation           │
            │  - Certificate Verification  │
            │  - Reverse Proxy             │
            │  - SSL/TLS Termination       │
            └──────────────┬───────────────┘
                           │
                           │ HTTP (Internal)
                           ▼
            ┌──────────────────────────────┐
            │     Test Web Server          │
            │  - Simple web application    │
            │  - No authentication needed  │
            │  - Trusts proxy              │
            └──────────────────────────────┘
```

### Security Layers

1. **CDN Layer (Bunny.net)**
   - DDoS protection
   - Geographic distribution
   - SSL/TLS termination (optional)
   - Client certificate validation (if supported)

2. **Firewall Layer (Firewalla)**
   - IP allowlist (Bunny.net edge IPs only)
   - Rate limiting
   - Geo-blocking
   - IDS/IPS monitoring

3. **Proxy Layer (Nginx Proxy Manager)**
   - mTLS certificate validation
   - Client certificate verification
   - Header injection (cert info to backend)
   - Access logging

4. **Application Layer (Test Web Server)**
   - Trusts proxy headers
   - No additional authentication needed
   - Simple content serving

---

## Components Breakdown

### 1. Nginx Proxy Manager (NPM)

**Purpose:** Central reverse proxy with web UI management

**Requirements:**
- Docker or LXC container
- Access to Book of Omens PKI
- Client certificate validation configuration
- Reverse proxy rules

**Features to Configure:**
- mTLS enforcement
- Certificate CN/SAN validation
- Custom SSL settings
- Access lists
- Logging

**Deployment Options:**
- **Option A:** Docker container on existing host
- **Option B:** Dedicated LXC container
- **Option C:** Existing nginx with NPM installed

**Recommended:** LXC container for isolation

### 2. Test Web Server

**Purpose:** Simple web application for testing mTLS flow

**Options:**
- **Nginx static site** - Simple HTML/CSS/JS
- **Apache with PHP** - Dynamic content
- **Python Flask/FastAPI** - REST API
- **Node.js Express** - Modern web app
- **Go/Caddy** - Lightweight binary

**Recommended for Testing:** Nginx static site
- Fast deployment
- No dependencies
- Easy to debug
- Can show client cert info

**Features to Include:**
- Display authenticated user (from cert CN)
- Show certificate details
- Simple UI to verify mTLS working
- Health check endpoint

### 3. Bunny.net CDN

**Purpose:** Edge caching and DDoS protection

**Configuration Needed:**
- Account setup
- Pull zone configuration
- Origin server (Firewalla public IP)
- SSL certificate (Let's Encrypt or custom)
- Cache rules
- Edge rules (if mTLS supported)

**Key Questions:**
- ⚠️ **Does Bunny.net support mTLS client certificate validation?**
- If not, mTLS validation happens at NPM only
- CDN provides DDoS protection but not certificate validation

**Alternative Approach:**
- Bunny CDN → Firewalla → NPM (mTLS here)
- CDN provides caching/DDoS
- NPM provides authentication

### 4. Firewalla Configuration

**Purpose:** Network security and access control

**Firewall Rules:**
- Allow HTTPS (443) from Bunny.net IP ranges ONLY
- Block all other inbound traffic
- Allow outbound from NPM to internet (for cert validation)

**Additional Security:**
- Geo-blocking (allow specific countries only)
- Rate limiting (requests per IP)
- IDS/IPS monitoring
- Alert on unusual traffic patterns

### 5. Client Certificates

**Purpose:** Device authentication via mTLS

**Certificate Requirements:**
- Issued by Book of Omens CA (already deployed)
- Subject CN: user identifier (e.g., "phone.user.funlab.casa")
- Key usage: Digital Signature, Key Encipherment
- Extended key usage: TLS Web Client Authentication
- Validity: 365 days (renewable)

**Deployment to Phone:**
- Export cert + private key as PKCS#12 (.p12/.pfx)
- Install on phone (iOS: Settings → General → VPN & Device Management)
- Configure browser to use certificate
- Test access

---

## Implementation Phases

### Phase 1: Local Setup & Testing (Week 1)
**Goal:** Get NPM and test server running locally with mTLS

**Tasks:**
- [ ] Deploy Nginx Proxy Manager (LXC or Docker)
  - [ ] Create container
  - [ ] Configure networking
  - [ ] Access web UI
  - [ ] Configure basic reverse proxy

- [ ] Deploy test web server
  - [ ] Create simple nginx static site
  - [ ] Add page to display client cert info
  - [ ] Configure health check endpoint

- [ ] Configure mTLS in NPM
  - [ ] Generate client certificate from Book of Omens
  - [ ] Configure NPM to require client cert
  - [ ] Configure NPM to validate against CA
  - [ ] Test cert validation

- [ ] Local testing
  - [ ] Test from laptop with client cert
  - [ ] Test from phone with client cert
  - [ ] Test rejection without cert
  - [ ] Verify cert details displayed

**Success Criteria:**
- ✅ Can access web server through NPM with valid cert
- ✅ Access denied without cert
- ✅ Certificate details displayed on web page

### Phase 2: Firewalla Security (Week 2)
**Goal:** Configure network-level security

**Tasks:**
- [ ] Document current Firewalla rules
- [ ] Create new rule set for web service
  - [ ] Allow HTTPS (443) to NPM
  - [ ] Initially allow from anywhere (testing)
  - [ ] Later restrict to Bunny.net IPs

- [ ] Configure additional security
  - [ ] Rate limiting rules
  - [ ] Geo-blocking (if desired)
  - [ ] IDS/IPS monitoring
  - [ ] Alert configuration

- [ ] Test firewall rules
  - [ ] Test from external network
  - [ ] Verify blocked IPs rejected
  - [ ] Verify allowed IPs accepted

**Success Criteria:**
- ✅ External access works through firewall
- ✅ Unauthorized IPs blocked
- ✅ Monitoring and alerts working

### Phase 3: Bunny CDN Integration (Week 3)
**Goal:** Add CDN layer for DDoS protection

**Tasks:**
- [ ] Research Bunny.net capabilities
  - [ ] Does it support mTLS passthrough?
  - [ ] Does it support client cert validation?
  - [ ] Document findings

- [ ] Create Bunny.net account
- [ ] Configure pull zone
  - [ ] Set origin to Firewalla public IP
  - [ ] Configure SSL (Let's Encrypt or custom)
  - [ ] Configure cache rules
  - [ ] Configure origin shield

- [ ] Update Firewalla rules
  - [ ] Get Bunny.net IP ranges
  - [ ] Restrict HTTPS to Bunny IPs only
  - [ ] Test access through CDN

- [ ] Configure NPM for CDN
  - [ ] Trust Bunny.net proxy headers
  - [ ] Extract real client IP
  - [ ] Configure cert validation (if CDN supports)

- [ ] Testing
  - [ ] Test access through CDN URL
  - [ ] Verify client cert still validated
  - [ ] Test from multiple locations
  - [ ] Verify caching works

**Success Criteria:**
- ✅ Access works through Bunny CDN
- ✅ mTLS validation still enforced
- ✅ Origin protected (only Bunny IPs allowed)
- ✅ Caching working correctly

### Phase 4: Mobile Client Setup (Week 4)
**Goal:** Configure phone for seamless access

**Tasks:**
- [ ] Generate client certificate for phone
  - [ ] Use Book of Omens CA
  - [ ] CN: phone identifier
  - [ ] Export as PKCS#12 with password

- [ ] Install on phone
  - [ ] Transfer .p12 file securely
  - [ ] Install certificate
  - [ ] Configure browser to use cert

- [ ] Testing from phone
  - [ ] Test in Safari/Chrome
  - [ ] Test certificate selection
  - [ ] Verify automatic authentication
  - [ ] Test without cert (should fail)

- [ ] User experience optimization
  - [ ] Bookmark with friendly name
  - [ ] Add to home screen (iOS)
  - [ ] Test automatic cert selection

**Success Criteria:**
- ✅ Phone can access service with cert
- ✅ Certificate auto-selected by browser
- ✅ Seamless user experience
- ✅ Access denied without cert

### Phase 5: Production Hardening (Week 5)
**Goal:** Prepare for production use

**Tasks:**
- [ ] Security hardening
  - [ ] Review all firewall rules
  - [ ] Ensure least privilege access
  - [ ] Configure certificate revocation (CRL/OCSP)
  - [ ] Set up monitoring and alerting

- [ ] Documentation
  - [ ] Document architecture
  - [ ] Document certificate issuance process
  - [ ] Document troubleshooting steps
  - [ ] Create user guide for adding devices

- [ ] Backup and recovery
  - [ ] Backup NPM configuration
  - [ ] Backup certificates
  - [ ] Document recovery procedures

- [ ] Performance testing
  - [ ] Load testing through CDN
  - [ ] Monitor response times
  - [ ] Optimize cache settings

**Success Criteria:**
- ✅ Complete documentation
- ✅ Backup and recovery tested
- ✅ Monitoring and alerting configured
- ✅ Performance acceptable

---

## Technical Decisions

### Decision 1: Where to Validate mTLS?

**Options:**
1. **At CDN (Bunny.net)**
   - Pros: Authentication at edge, reduced origin load
   - Cons: May not be supported by Bunny.net

2. **At Nginx Proxy Manager**
   - Pros: Full control, proven technology
   - Cons: Origin sees all traffic (mitigated by IP allowlist)

**Recommendation:** Validate at NPM (Option 2)
- More control over certificate validation
- Can customize validation logic
- Can extract cert details for backend
- CDN still provides DDoS protection

### Decision 2: NPM Deployment Method?

**Options:**
1. **Docker container**
   - Pros: Easy deployment, official images
   - Cons: Docker overhead, less isolation

2. **LXC container**
   - Pros: Better isolation, lower overhead
   - Cons: Manual setup, no official images

3. **VM**
   - Pros: Maximum isolation
   - Cons: Higher overhead, more resources

**Recommendation:** LXC container (Option 2)
- Consistent with existing infrastructure
- Good isolation
- Lower overhead than VM
- Easy to manage with Proxmox

### Decision 3: Certificate Validity Period?

**Options:**
1. **90 days** (Let's Encrypt style)
2. **365 days** (1 year)
3. **730 days** (2 years)

**Recommendation:** 365 days (Option 2)
- Balance between security and convenience
- Annual renewal is manageable
- Can automate with Book of Omens PKI
- Not too frequent to be annoying

### Decision 4: Test Web Server Implementation?

**Options:**
1. **Static nginx** - Simple HTML
2. **Dynamic app** - Python/Node.js
3. **Existing service** - Dashboard, etc.

**Recommendation:** Static nginx (Option 1) for testing
- Quick to deploy
- Easy to debug
- Can show cert details via JavaScript
- Later migrate to real application

---

## Certificate Management

### CA Structure

Using existing **Book of Omens PKI:**
- Root CA: Eye of Thundera
- Intermediate CA: Book of Omens
- Client certs issued from Book of Omens

### Client Certificate Template

**Subject:**
```
CN=device-name.user.funlab.casa
O=Funlab.Casa
OU=Client Devices
```

**Key Usage:**
- Digital Signature
- Key Encipherment

**Extended Key Usage:**
- TLS Web Client Authentication (1.3.6.1.5.5.7.3.2)

**Validity:** 365 days

**Example Subjects:**
- CN=iphone-tygra.funlab.casa
- CN=android-user2.funlab.casa
- CN=laptop-admin.funlab.casa

### Certificate Issuance Process

**Using OpenBao PKI:**

```bash
# Generate client certificate
bao write pki_int/issue/client-cert \
  common_name="iphone-tygra.funlab.casa" \
  ttl="8760h" \
  key_usage="DigitalSignature,KeyEncipherment" \
  ext_key_usage="ClientAuth"

# Export as PKCS#12 for phone
openssl pkcs12 -export \
  -out iphone-tygra.p12 \
  -inkey client.key \
  -in client.crt \
  -certfile ca-chain.crt \
  -passout pass:SecurePassword123
```

### Certificate Revocation

**Options:**
1. **CRL (Certificate Revocation List)**
   - NPM checks CRL before accepting cert
   - Requires CRL distribution point in cert

2. **OCSP (Online Certificate Status Protocol)**
   - Real-time revocation checking
   - Requires OCSP responder

**Recommendation:** CRL initially
- Simpler to implement
- No additional infrastructure needed
- OCSP can be added later

---

## Bunny.net Research Needed

### Critical Questions

**mTLS Support:**
- ⚠️ Does Bunny.net support client certificate authentication?
- Can it pass client certs to origin?
- Can it validate certs at edge?

**If YES (mTLS at CDN):**
```
Phone → [Bunny CDN validates cert] → Bunny → Firewalla → NPM → Web
```
- Best security (authentication at edge)
- Reduced origin traffic

**If NO (mTLS at origin only):**
```
Phone → [Bunny CDN no validation] → Bunny → Firewalla → NPM validates cert → Web
```
- CDN provides DDoS protection only
- NPM handles authentication
- Still secure (Firewalla blocks non-Bunny IPs)

### Bunny.net Configuration

**Regardless of mTLS support:**
- Pull zone: https://your-cdn.b-cdn.net
- Origin: https://your-public-ip:443
- SSL: Let's Encrypt or custom cert
- Cache: Static assets (CSS, JS, images)
- No cache: Dynamic content, API calls

**IP Restrictions:**
- Get Bunny.net IP ranges: https://bunny.net/api/system/edgeserverlist
- Update Firewalla to allow only these IPs

---

## Monitoring & Observability

### Metrics to Track

**Nginx Proxy Manager:**
- mTLS authentication attempts
- Certificate validation failures
- Certificate expiration dates
- Request rates per certificate
- Backend health

**Bunny.net CDN:**
- Cache hit ratio
- Bandwidth usage
- Request distribution
- Error rates
- Geographic distribution

**Firewalla:**
- Blocked connection attempts
- Allowed connections from Bunny IPs
- IDS/IPS alerts
- Bandwidth usage

### Logging

**NPM Access Logs:**
```
$remote_addr - $ssl_client_s_dn [$time_local] "$request"
$status $body_bytes_sent "$http_referer"
```

**Log Aggregation:**
- Option 1: Local syslog
- Option 2: Centralized logging (future)
- Option 3: Bunny.net logs

### Alerts

**Critical:**
- Certificate validation failures spike
- Backend unreachable
- Firewalla blocks unusual traffic

**Warning:**
- Certificate expiring soon (30 days)
- High error rate
- Unusual geographic access pattern

---

## Security Considerations

### Threat Model

**Protected Against:**
- ✅ Unauthorized access (no valid cert)
- ✅ DDoS attacks (CDN + Firewalla)
- ✅ Direct origin attacks (IP allowlist)
- ✅ Certificate theft (password-protected PKCS#12)
- ✅ Man-in-the-middle (TLS + client auth)

**Not Protected Against:**
- ⚠️ Compromised client device (cert stolen)
- ⚠️ Certificate revocation delay (CRL refresh)
- ⚠️ CDN compromise (depends on provider)
- ⚠️ Insider threat (valid cert misused)

### Mitigation Strategies

**Certificate Theft:**
- Strong password on PKCS#12
- Device-level encryption (phone security)
- Short validity period (365 days)
- Certificate revocation capability

**Compromised Device:**
- Monitor for unusual access patterns
- Revoke certificate immediately
- Issue new certificate to replacement device
- Investigate logs for unauthorized access

**Certificate Revocation:**
- Implement CRL checking in NPM
- Refresh CRL frequently (hourly)
- Consider OCSP for real-time checking
- Document revocation procedure

---

## Cost Estimation

### Bunny.net Costs

**Pricing (as of 2024):**
- Bandwidth: ~$0.01/GB (varies by region)
- Storage: ~$0.02/GB/month (for caching)
- Requests: Included

**Estimated Monthly Cost:**
- Light usage (10GB/month): ~$0.10
- Medium usage (100GB/month): ~$1.00
- Heavy usage (1TB/month): ~$10.00

**Very affordable for personal use!**

### Infrastructure Costs

**Hardware:**
- NPM container: Minimal (existing Proxmox)
- Test web server: Minimal (existing infrastructure)
- Firewalla: Already owned

**Operational:**
- Certificate management: Free (Book of Omens PKI)
- Monitoring: Free (existing tools)
- Maintenance: Time investment only

**Total Additional Cost:** ~$0.10-1.00/month for CDN

---

## Testing Plan

### Test Scenarios

**Positive Tests:**
1. ✅ Access with valid certificate
2. ✅ Certificate auto-selected by browser
3. ✅ Access from multiple devices (phone, laptop)
4. ✅ Access through CDN URL
5. ✅ Certificate details displayed correctly

**Negative Tests:**
1. ❌ Access without certificate (should fail)
2. ❌ Access with expired certificate (should fail)
3. ❌ Access with revoked certificate (should fail)
4. ❌ Access with certificate from wrong CA (should fail)
5. ❌ Direct access bypassing CDN (should be blocked)

**Performance Tests:**
1. Load test through CDN
2. Measure TLS handshake time with mTLS
3. Verify caching working correctly
4. Test from multiple geographic locations

**Security Tests:**
1. Port scan from external network
2. Attempt to bypass authentication
3. Test certificate validation logic
4. Verify Firewalla blocks non-Bunny IPs

---

## Troubleshooting Guide

### Common Issues

**"Certificate not recognized"**
- Check certificate installed on device
- Verify certificate issued by Book of Omens
- Check certificate not expired
- Verify device trusts Book of Omens CA

**"Access denied"**
- Check certificate selected by browser
- Verify NPM configured to accept Book of Omens CA
- Check certificate has ClientAuth extended key usage
- Review NPM logs for validation errors

**"Can't reach server"**
- Check Firewalla rules allow traffic
- Verify Bunny CDN origin configured correctly
- Check NPM container running
- Verify network connectivity

**"Page loads but cert info not shown"**
- Check NPM passing cert headers to backend
- Verify web server reading headers correctly
- Check NPM configuration for SSL client variables

---

## Next Steps

### Immediate Actions

1. **Research Bunny.net mTLS Support**
   - Read documentation
   - Contact support if needed
   - Determine if client cert validation possible at edge

2. **Design NPM Deployment**
   - LXC vs Docker decision
   - Network planning (IP addressing, VLANs)
   - Resource allocation

3. **Test Certificate Generation**
   - Generate test client cert from Book of Omens
   - Export as PKCS#12
   - Test installation on phone

4. **Create Project Timeline**
   - Week-by-week milestones
   - Dependencies identified
   - Resource allocation

### Questions to Answer

1. **Bunny.net Capabilities:**
   - Does it support mTLS client certificate validation?
   - Can it pass client cert info to origin?
   - What headers does it send?

2. **NPM Configuration:**
   - Best deployment method for our infrastructure?
   - How to configure mTLS with custom CA?
   - How to pass cert details to backend?

3. **Firewalla Rules:**
   - Current rule structure?
   - How to get Bunny.net IP list?
   - Best way to implement geo-blocking?

4. **Use Cases:**
   - What services to protect with this?
   - How many client devices initially?
   - Performance requirements?

---

## Success Criteria

### Phase 1 Success (Local Testing)
- ✅ NPM deployed and accessible
- ✅ Test web server deployed
- ✅ mTLS working locally
- ✅ Can access with valid cert
- ✅ Access denied without cert

### Phase 2 Success (Firewalla)
- ✅ External access working
- ✅ Firewall rules configured
- ✅ Monitoring and alerting active

### Phase 3 Success (CDN)
- ✅ Bunny CDN configured
- ✅ Access works through CDN
- ✅ Origin protected (IP allowlist)
- ✅ Caching working

### Phase 4 Success (Mobile)
- ✅ Certificate installed on phone
- ✅ Seamless access from phone
- ✅ Good user experience

### Final Success Criteria
- ✅ All phases complete
- ✅ Documentation complete
- ✅ Monitoring working
- ✅ Production-ready
- ✅ Secure and performant

---

## References

### Documentation
- Nginx Proxy Manager: https://nginxproxymanager.com/
- Bunny.net: https://bunny.net/
- OpenSSL PKCS#12: https://www.openssl.org/docs/man1.1.1/man1/pkcs12.html
- mTLS in Nginx: https://nginx.org/en/docs/http/ngx_http_ssl_module.html

### Related Infrastructure Docs
- Book of Omens PKI: `book-of-omens-pki-deployment.md`
- Keylime mTLS: `keylime-mtls-deployment.md`
- Firewalla configuration: (to be documented)

---

**Project Status:** 🔲 Planning Phase
**Next Action:** Research Bunny.net mTLS capabilities
**Estimated Timeline:** 4-5 weeks for full implementation
**Priority:** Medium (new capability, not blocking existing systems)

**Created:** 2026-02-11
**Author:** Infrastructure Team

---

## Advanced Integration: SPIRE + Keylime + OpenBao

### Overview

Integrate existing security infrastructure to create a **zero-trust, attested, secrets-managed web service stack**.

---

### Component Roles

#### OpenBao (Secrets & PKI)
**Primary Functions:**
- Issue client certificates dynamically
- Store NPM configuration secrets
- Manage CDN API keys
- Rotate credentials automatically
- Provide CA certificates

**Integration Points:**
1. **Client Certificate Issuance**
   - Dynamic cert generation via PKI
   - Automated enrollment workflow
   - Certificate lifecycle management

2. **Secrets Management**
   - NPM database credentials
   - Bunny CDN API keys
   - Backend service credentials
   - TLS private keys

3. **PKI Infrastructure**
   - Book of Omens as CA for client certs
   - Automated renewal before expiration
   - CRL distribution

#### SPIRE (Workload Identity)
**Primary Functions:**
- Provide identity to NPM container
- Provide identity to web server
- Enable service-to-service authentication
- Mutual TLS between internal services

**Integration Points:**
1. **NPM Workload Identity**
   - NPM gets SPIFFE SVID on startup
   - Uses SVID to authenticate to OpenBao
   - Uses SVID to authenticate to backend services

2. **Web Server Identity**
   - Backend gets its own SVID
   - NPM validates backend SVID
   - Service mesh architecture

3. **OpenBao Integration**
   - NPM uses SVID to auth to OpenBao
   - Fetch secrets with workload identity
   - No static credentials needed

#### Keylime (Attestation)
**Primary Functions:**
- Attest hosts before allowing traffic
- Continuous runtime integrity monitoring
- Gate access based on attestation status
- Detect compromises

**Integration Points:**
1. **Host Attestation**
   - Attest NPM container host
   - Attest web server host
   - Only allow traffic if attestation PASS

2. **Runtime Monitoring**
   - IMA checks on running services
   - Detect unauthorized changes
   - Alert on attestation failures

3. **Attestation-Gated Access**
   - Firewall rules based on attestation
   - NPM only accessible if host attested
   - Similar to auto-unseal gate

---

### Enhanced Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Internet / Mobile                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │ HTTPS + Client Cert
                            ▼
                  ┌───────────────────┐
                  │   Bunny.net CDN   │
                  └─────────┬─────────┘
                            │
                            ▼
                  ┌───────────────────┐
                  │    Firewalla      │
                  │  + Attestation    │
                  │    Check          │
                  └─────────┬─────────┘
                            │
                            ▼
            ┌───────────────────────────────────────┐
            │         Keylime Verifier              │
            │  "Is NPM host attested?"              │
            │  PASS → Allow traffic                 │
            │  FAIL → Block traffic                 │
            └───────────────┬───────────────────────┘
                            │
                            │ Attestation PASS
                            ▼
            ┌───────────────────────────────────────┐
            │     Nginx Proxy Manager (NPM)         │
            │  + SPIRE Agent                        │
            │  + Keylime Agent                      │
            ├───────────────────────────────────────┤
            │  1. Get SVID from SPIRE               │
            │  2. Authenticate to OpenBao with SVID │
            │  3. Fetch CA cert from OpenBao        │
            │  4. Validate client cert against CA   │
            │  5. Extract SVID for backend auth     │
            └───────────────┬───────────────────────┘
                            │
                            │ SVID + Validated Client Cert Info
                            ▼
            ┌───────────────────────────────────────┐
            │         OpenBao (Secrets)             │
            │  - Client cert PKI                    │
            │  - NPM secrets                        │
            │  - Backend credentials                │
            └───────────────┬───────────────────────┘
                            │
                            │ Secrets Retrieved
                            ▼
            ┌───────────────────────────────────────┐
            │     Test Web Server                   │
            │  + SPIRE Agent                        │
            │  + Keylime Agent                      │
            ├───────────────────────────────────────┤
            │  1. Verify NPM's SVID                 │
            │  2. Trust client cert from NPM        │
            │  3. Serve content                     │
            └───────────────────────────────────────┘
```

---

### Implementation Details

#### Phase 1a: OpenBao Integration

**Certificate Issuance Automation**

```bash
# Script: /usr/local/bin/issue-client-cert.sh
#!/bin/bash
# Issue client certificate via OpenBao PKI

DEVICE_NAME="$1"
USER_NAME="$2"

# Authenticate to OpenBao (using SPIRE SVID in later phase)
export BAO_ADDR="https://openbao.funlab.casa:8200"
export BAO_TOKEN="..." # Or use SPIRE auth

# Issue certificate
bao write pki_int/issue/client-cert \
  common_name="${DEVICE_NAME}.${USER_NAME}.funlab.casa" \
  ttl="8760h" \
  key_usage="DigitalSignature,KeyEncipherment" \
  ext_key_usage="ClientAuth" \
  format="pem" \
  > cert-data.json

# Extract components
jq -r '.data.certificate' cert-data.json > client.crt
jq -r '.data.private_key' cert-data.json > client.key
jq -r '.data.ca_chain[]' cert-data.json > ca-chain.crt

# Create PKCS#12 for mobile
openssl pkcs12 -export \
  -out "${DEVICE_NAME}-${USER_NAME}.p12" \
  -inkey client.key \
  -in client.crt \
  -certfile ca-chain.crt \
  -passout pass:SecurePassword123

# Cleanup
rm cert-data.json client.key

echo "Certificate issued: ${DEVICE_NAME}-${USER_NAME}.p12"
```

**NPM Secrets Management**

```yaml
# Store NPM secrets in OpenBao
path: secret/data/npm
data:
  db_password: "random-generated-password"
  admin_password: "hashed-password"
  bunny_api_key: "bunny-cdn-key"
```

**Retrieval Script:**

```bash
# NPM startup script retrieves secrets
export BAO_ADDR="https://openbao.funlab.casa:8200"

# Get secrets (later: use SPIRE SVID for auth)
DB_PASS=$(bao kv get -field=db_password secret/npm)
ADMIN_PASS=$(bao kv get -field=admin_password secret/npm)

# Configure NPM with secrets
# ...
```

#### Phase 1b: SPIRE Integration

**Workload Registration**

```bash
# Register NPM workload
spire-server entry create \
  -parentID spiffe://funlab.casa/agent/spire \
  -spiffeID spiffe://funlab.casa/npm \
  -selector systemd:id:nginx-proxy-manager \
  -x509SVID

# Register backend web server
spire-server entry create \
  -parentID spiffe://funlab.casa/agent/spire \
  -spiffeID spiffe://funlab.casa/web/test \
  -selector systemd:id:test-web-server \
  -x509SVID
```

**NPM SVID Usage**

```nginx
# NPM nginx config
location / {
    # Get SVID from SPIRE agent socket
    proxy_set_header X-SPIFFE-ID $ssl_client_s_dn;
    
    # Use SVID for backend authentication
    proxy_ssl_certificate /var/run/spire/svid.pem;
    proxy_ssl_certificate_key /var/run/spire/svid-key.pem;
    
    # Verify backend SVID
    proxy_ssl_trusted_certificate /var/run/spire/bundle.pem;
    proxy_ssl_verify on;
    
    proxy_pass https://backend;
}
```

**OpenBao Authentication with SPIRE**

```bash
# NPM authenticates to OpenBao using SVID
# Instead of static token

# 1. Get SVID from SPIRE
SVID=$(cat /var/run/spire/svid.pem)

# 2. Authenticate to OpenBao with JWT
bao write auth/jwt/login \
  role=npm-role \
  jwt=$(spire-agent api fetch jwt -audience openbao.funlab.casa)

# 3. Use returned token to fetch secrets
export BAO_TOKEN="<returned-token>"
bao kv get secret/npm
```

#### Phase 1c: Keylime Integration

**Agent Deployment on NPM Host**

```bash
# Install Keylime agent on NPM container host
# (Already done on spire.funlab.casa if NPM deployed there)

# Register with verifier
keylime_tenant -c add \
  -t npm-host.funlab.casa \
  -u <npm-host-uuid>
```

**Attestation-Gated Access**

```bash
# Script: /usr/local/bin/check-attestation-before-traffic.sh
#!/bin/bash
# Check if NPM host is attested before allowing traffic

NPM_HOST_UUID="<uuid>"

# Check attestation status
STATUS=$(keylime_tenant -c status -u "$NPM_HOST_UUID" | \
  jq -r '.attestation_status')

if [ "$STATUS" = "PASS" ]; then
    echo "✅ Attestation PASS - Allow traffic to NPM"
    # Firewalla: Enable NPM forwarding rule
    exit 0
else
    echo "❌ Attestation FAIL - Block traffic to NPM"
    # Firewalla: Disable NPM forwarding rule
    exit 1
fi
```

**Continuous Monitoring**

```bash
# Systemd timer: check attestation every minute
[Unit]
Description=Check NPM Host Attestation

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
```

---

### Security Flow: End-to-End

#### Request Flow with All Components

1. **Mobile Client Initiates Request**
   ```
   Phone → HTTPS + Client Cert → Bunny CDN
   ```

2. **CDN to Origin**
   ```
   Bunny CDN → Firewalla → "Is NPM host attested?"
   ```

3. **Keylime Attestation Check**
   ```
   Keylime Verifier: Check NPM host attestation
   - PASS → Allow traffic
   - FAIL → Block traffic (firewall rule)
   ```

4. **NPM Receives Request**
   ```
   NPM:
   a) Get own SVID from SPIRE agent
   b) Authenticate to OpenBao using SVID
   c) Fetch Book of Omens CA cert from OpenBao
   d) Validate client certificate against CA
   e) Extract client identity (CN)
   ```

5. **NPM to Backend**
   ```
   NPM → Backend:
   a) Include own SVID for authentication
   b) Include client cert details in headers
   c) Mutual TLS using SVIDs
   ```

6. **Backend Validates**
   ```
   Backend:
   a) Verify NPM's SVID (is it really NPM?)
   b) Trust client cert info from NPM
   c) Serve content
   ```

7. **Response**
   ```
   Backend → NPM → Firewalla → CDN → Phone
   ```

---

### Enhanced Security Benefits

#### With OpenBao
- ✅ **No static secrets** - All credentials in vault
- ✅ **Dynamic certificates** - Issue certs on-demand
- ✅ **Automatic rotation** - Secrets rotated regularly
- ✅ **Audit trail** - All secret access logged
- ✅ **Centralized PKI** - One source of truth

#### With SPIRE
- ✅ **No credentials needed** - Workload identity via attestation
- ✅ **Service mesh ready** - Mutual TLS between services
- ✅ **Automatic rotation** - SVIDs rotate automatically (1 hour default)
- ✅ **Zero-trust networking** - Every connection authenticated
- ✅ **Platform agnostic** - Works across containers, VMs, bare metal

#### With Keylime
- ✅ **Host integrity** - Only attested hosts serve traffic
- ✅ **Runtime monitoring** - Detect compromises in real-time
- ✅ **Attestation gate** - Similar to OpenBao auto-unseal
- ✅ **Compliance** - Prove system integrity
- ✅ **Defense in depth** - Another security layer

---

### Implementation Phases (Revised)

#### Phase 1: Basic mTLS (Week 1)
- Deploy NPM + test web server
- Configure basic mTLS with static certs
- Test locally

#### Phase 2: OpenBao Integration (Week 2)
- Automate cert issuance via OpenBao PKI
- Store NPM secrets in OpenBao
- Fetch secrets on NPM startup
- Test dynamic cert generation

#### Phase 3: SPIRE Integration (Week 3)
- Register NPM + backend as workloads
- NPM authenticates to OpenBao with SVID
- Mutual TLS between NPM and backend
- Test workload identity flow

#### Phase 4: Keylime Integration (Week 4)
- Deploy Keylime agent on NPM host (if not already)
- Implement attestation check before traffic
- Configure firewall rules based on attestation
- Test attestation gate

#### Phase 5: CDN + Production (Week 5)
- Add Bunny CDN layer
- Configure Firewalla with all rules
- Mobile client setup
- End-to-end testing

---

### Configuration Examples

#### OpenBao PKI Role for Client Certs

```bash
# Create role for issuing client certificates
bao write pki_int/roles/client-cert \
  allowed_domains="funlab.casa" \
  allow_subdomains=true \
  max_ttl="8760h" \
  key_type="rsa" \
  key_bits=2048 \
  key_usage="DigitalSignature,KeyEncipherment" \
  ext_key_usage="ClientAuth" \
  require_cn=true
```

#### SPIRE JWT Auth in OpenBao

```bash
# Configure OpenBao to trust SPIRE JWTs
bao auth enable jwt

bao write auth/jwt/config \
  oidc_discovery_url="https://spire.funlab.casa:8443" \
  bound_issuer="spiffe://funlab.casa"

# Create policy for NPM workload
bao policy write npm-policy - <<EOF
path "secret/data/npm" {
  capabilities = ["read"]
}
path "pki_int/issue/client-cert" {
  capabilities = ["create", "update"]
}
EOF

# Create role for NPM workload
bao write auth/jwt/role/npm-role \
  role_type="jwt" \
  bound_audiences="openbao.funlab.casa" \
  user_claim="sub" \
  bound_subject="spiffe://funlab.casa/npm" \
  policies="npm-policy" \
  ttl="1h"
```

#### Keylime Attestation Policy

```bash
# Keylime policy for NPM host
# /var/lib/keylime/npm-host-policy.json
{
  "meta": {
    "version": 1
  },
  "digests": {
    "boot_aggregate": ["<expected-sha256>"],
    "ima": {
      "/usr/bin/nginx": ["<expected-sha256>"],
      "/etc/nginx/nginx.conf": ["<expected-sha256>"]
    }
  },
  "pcrs": {
    "0": "<uefi-firmware>",
    "7": "<secure-boot>",
    "10": "<ima-measurement>"
  }
}

# Apply policy
keylime_tenant -c update \
  -u <npm-host-uuid> \
  --runtime-policy /var/lib/keylime/npm-host-policy.json
```

---

### Integration Testing Checklist

#### OpenBao Tests
- [ ] Generate client cert from OpenBao PKI
- [ ] Verify cert has correct attributes (ClientAuth)
- [ ] Export as PKCS#12
- [ ] Fetch NPM secrets from vault
- [ ] Test secret rotation
- [ ] Verify audit logs captured

#### SPIRE Tests
- [ ] NPM receives SVID on startup
- [ ] Backend receives SVID on startup
- [ ] NPM authenticates to OpenBao with JWT
- [ ] NPM validates backend SVID
- [ ] SVID auto-rotation works (1 hour)
- [ ] Service mesh mTLS functional

#### Keylime Tests
- [ ] Agent registers successfully
- [ ] Attestation reaches PASS status
- [ ] Firewall rule enables on PASS
- [ ] Firewall rule disables on FAIL
- [ ] IMA detects file changes
- [ ] Alerts trigger on attestation failure

#### End-to-End Tests
- [ ] Phone → CDN → NPM → Backend (full flow)
- [ ] Client cert validated correctly
- [ ] SVID authentication works
- [ ] Secrets fetched from OpenBao
- [ ] Attestation gate enforced
- [ ] All logs captured correctly

---

### Migration Path: Basic → Zero-Trust

#### Stage 1: Basic mTLS (Current Plan)
**Components:**
- NPM + test web server
- Static client certificates
- Basic authentication

**Security Level:** Medium
- Client certificate authentication
- No workload identity
- No attestation
- Static secrets

#### Stage 2: + OpenBao
**Add:**
- Dynamic certificate issuance
- Secrets management
- Automated rotation

**Security Level:** High
- Dynamic credentials
- Centralized PKI
- Audit trail
- Still no workload identity

#### Stage 3: + SPIRE
**Add:**
- Workload identity for services
- Service mesh with mutual TLS
- OpenBao auth via SVID

**Security Level:** Very High
- Zero-trust service communication
- No static credentials
- Automatic rotation
- Still no host attestation

#### Stage 4: + Keylime (Final)
**Add:**
- Host integrity verification
- Runtime monitoring
- Attestation-gated access

**Security Level:** Maximum
- ✅ Zero-trust networking
- ✅ Attested infrastructure
- ✅ Dynamic secrets
- ✅ Complete audit trail
- ✅ Defense in depth

---

### Operational Considerations

#### Monitoring Integration

**OpenBao Metrics:**
```bash
# Certificate issuance rate
rate(openbao_pki_issue_count[5m])

# Secret fetch latency
histogram_quantile(0.95, openbao_secret_fetch_duration_seconds)
```

**SPIRE Metrics:**
```bash
# SVID rotation success rate
rate(spire_agent_svid_rotation_success[5m])

# Active workload count
spire_server_workload_count
```

**Keylime Metrics:**
```bash
# Attestation status by host
keylime_attestation_status{host="npm-host"}

# Failed attestation count
rate(keylime_attestation_failures[5m])
```

#### Troubleshooting Guide

**"NPM can't fetch secrets from OpenBao"**
1. Check NPM has valid SVID
2. Verify SVID in OpenBao JWT role
3. Check OpenBao policy allows secret read
4. Review OpenBao audit logs
5. Test JWT authentication manually

**"Backend rejects NPM connection"**
1. Check NPM SVID is valid
2. Verify backend trusts SPIRE bundle
3. Check SPIRE server connectivity
4. Review SPIRE agent logs
5. Test SVID validation manually

**"Traffic blocked despite attestation PASS"**
1. Check Keylime verifier status
2. Verify attestation check script running
3. Check Firewalla rule status
4. Review Keylime agent logs
5. Test attestation manually

**"Client cert rejected"**
1. Check cert issued by Book of Omens
2. Verify NPM has CA certificate
3. Check cert not expired
4. Verify ClientAuth extended key usage
5. Review NPM access logs

---

### Cost-Benefit Analysis

#### Without Integration (Basic mTLS)
**Pros:**
- Simpler setup
- Faster initial deployment
- Fewer moving parts

**Cons:**
- Static secrets
- No workload identity
- No attestation
- Manual certificate management
- Higher operational burden

**Time to Deploy:** 4 weeks

#### With Integration (Zero-Trust)
**Pros:**
- Dynamic secrets (reduced risk)
- Workload identity (zero-trust)
- Attestation (integrity verification)
- Automated certificate lifecycle
- Better audit trail
- Future-proof architecture

**Cons:**
- More complex setup
- More components to manage
- Requires understanding of each system

**Time to Deploy:** 5 weeks (+1 week)

**Recommendation:** **Implement full integration**
- Only +1 week additional time
- Significantly better security posture
- Leverages existing infrastructure (SPIRE, Keylime, OpenBao already deployed)
- Sets foundation for future services
- Aligned with zero-trust architecture goals

---

### Success Metrics

#### Security Metrics
- ✅ 100% of traffic attested before reaching NPM
- ✅ 0 static credentials in configuration
- ✅ 100% of service-to-service connections use SVIDs
- ✅ All secrets fetched from OpenBao (audit trail)
- ✅ Certificate rotation automated (no manual intervention)

#### Performance Metrics
- ✅ SVID rotation < 1s overhead
- ✅ Attestation check < 2s (similar to auto-unseal)
- ✅ OpenBao secret fetch < 500ms
- ✅ End-to-end request latency < 200ms
- ✅ No impact on user experience

#### Operational Metrics
- ✅ Zero manual certificate renewals
- ✅ Zero static secrets to manage
- ✅ 100% audit coverage
- ✅ Automated attestation monitoring
- ✅ Clear troubleshooting procedures

---

### Related Documentation

**Existing Infrastructure:**
- OpenBao auto-unseal: `OPENBAO-AUTOUNSEAL-EXECUTIVE-SUMMARY.md`
- Keylime mTLS: `keylime-mtls-deployment.md`
- Book of Omens PKI: `book-of-omens-pki-deployment.md`
- Infrastructure Roadmap: `ROADMAP-ALL-PROJECTS.md`

**New Documentation to Create:**
- NPM deployment guide
- SPIRE workload registration procedures
- Keylime attestation policies
- OpenBao PKI automation
- End-to-end testing guide

---

### Next Steps with Integration

1. **Review Integration Plan** ✅ (This document)
2. **Deploy Basic mTLS** (Phase 1 - Week 1)
3. **Add OpenBao** (Phase 2 - Week 2)
4. **Add SPIRE** (Phase 3 - Week 3)
5. **Add Keylime** (Phase 4 - Week 4)
6. **Production Deployment** (Phase 5 - Week 5)

**Recommended First Action:**
Start with Phase 1 (basic mTLS) to validate the NPM + web server architecture, then incrementally add OpenBao, SPIRE, and Keylime integration.

---

### Integration Summary

**What We're Building:**
A **zero-trust, attested, secrets-managed web service** where:
- Mobile client authenticates with dynamic certificate (OpenBao PKI)
- NPM uses workload identity to fetch secrets (SPIRE + OpenBao)
- Services communicate via mutual TLS (SPIRE SVIDs)
- Host integrity verified before traffic allowed (Keylime attestation)
- All secrets centralized, rotated, audited (OpenBao)
- Complete audit trail across all components

**Why It's Worth It:**
- Leverages existing infrastructure (SPIRE, Keylime, OpenBao)
- Only +1 week additional implementation time
- Significantly better security posture
- Future-proof for additional services
- Aligned with zero-trust goals
- Operational benefits (automation, audit, monitoring)

**Status:** Ready to begin Phase 1 upon approval

---

**Document Updated:** 2026-02-11
**Integration Plan Status:** ✅ Complete
**Estimated Timeline:** 5 weeks (1 week per phase)
**Next Action:** Begin Phase 1 (Basic mTLS Setup)
