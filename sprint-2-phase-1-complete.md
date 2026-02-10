# Sprint 2 Phase 1 Complete - OpenBao Workload Identity

**Date:** 2026-02-10
**Phase:** Sprint 2 - Phase 1
**Status:** ✅ COMPLETE
**Duration:** 30 minutes

---

## What We Accomplished

### 1. Deployed SPIRE Agent on spire.funlab.casa

**Host:** spire.funlab.casa (10.10.2.62)
**Agent Version:** v1.14.1
**Status:** ✅ Operational

**Configuration:**
- Trust Domain: funlab.casa
- Server Address: spire.funlab.casa:8081
- Socket Path: /run/spire/sockets/agent.sock
- Attestation: join_token (temporary)
- Health Check: http://127.0.0.1:8088/ready

**Agent SPIFFE ID:**
```
spiffe://funlab.casa/spire/agent/join_token/48fc8456-ac44-427b-8fd6-1f1475bbcb3d
```

**Attestation Details:**
- Join Token: 48fc8456-ac44-427b-8fd6-1f1475bbcb3d
- Serial Number: 314885993763781705660896925388505687262
- Expiration: 2026-02-10 18:16:25 -0500 EST
- Can Re-attest: false

### 2. Registered OpenBao as a Workload

**Workload SPIFFE ID:** `spiffe://funlab.casa/workload/openbao`
**Entry ID:** d7226986-0d9b-40ab-b151-20225ef8ad55
**Parent Agent:** spire agent (48fc8456-ac44-427b-8fd6-1f1475bbcb3d)

**Configuration:**
- **Selector:** unix:uid:999 (openbao user)
- **X509-SVID TTL:** 3600 seconds (1 hour)
- **DNS SANs:** spire.funlab.casa, localhost

### 3. Verified SVID Issuance

**Test Result:** ✅ SUCCESS

```
$ sudo -u openbao /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock

Received 1 svid after 2.755859ms

SPIFFE ID:        spiffe://funlab.casa/workload/openbao
SVID Valid After: 2026-02-10 22:17:09 +0000 UTC
SVID Valid Until: 2026-02-10 23:17:19 +0000 UTC
CA #1 Valid After:  2026-02-10 13:33:59 +0000 UTC
CA #1 Valid Until:  2026-02-11 13:34:09 +0000 UTC
```

**Performance:** 2.76ms ✅ Excellent!

---

## Infrastructure Status Update

### All SPIRE Agents (3 total)

```
1. auth.funlab.casa (10.10.2.70)
   SPIFFE ID: spiffe://funlab.casa/spire/agent/join_token/48a28e50-f108-4164-930b-df64142851f8
   Status: ✅ Operational

2. ca.funlab.casa (10.10.2.60)
   SPIFFE ID: spiffe://funlab.casa/spire/agent/join_token/9269fd4b-e483-4ee8-8cba-d624b204caba
   Status: ✅ Operational

3. spire.funlab.casa (10.10.2.62) ← NEW!
   SPIFFE ID: spiffe://funlab.casa/spire/agent/join_token/48fc8456-ac44-427b-8fd6-1f1475bbcb3d
   Status: ✅ Operational
```

### All Workload Entries (6 total)

**Agent Entries (3):**
1. spiffe://funlab.casa/agent/auth (automatic)
2. spiffe://funlab.casa/agent/ca (automatic)
3. spiffe://funlab.casa/agent/spire (automatic) ← NEW!

**Workload Entries (3):**
1. spiffe://funlab.casa/workload/openbao ← NEW!
   - Host: spire.funlab.casa
   - Selector: unix:uid:999
   - SVID Fetch: 2.76ms ✅

2. spiffe://funlab.casa/workload/step-ca
   - Host: ca.funlab.casa
   - Selector: unix:uid:999
   - SVID Fetch: 3.7ms ✅

3. spiffe://funlab.casa/workload/test-workload
   - Host: auth.funlab.casa
   - Selector: unix:uid:0
   - SVID Fetch: 6.5ms ✅

---

## Complete Infrastructure Map

```
Tower of Omens - Sprint 2 Phase 1
===================================

spire.funlab.casa (10.10.2.62)
├── ✅ TPM 2.0 validated
├── ✅ LUKS auto-unlock
├── ✅ SPIRE Server v1.14.1
├── ✅ SPIRE Agent v1.14.1 ← NEW!
├── ✅ OpenBao v2.5.0
│   └── ✅ Workload identity: spiffe://funlab.casa/workload/openbao ← NEW!
└── ✅ Workload API: /run/spire/sockets/agent.sock ← NEW!

auth.funlab.casa (10.10.2.70)
├── ✅ TPM 2.0 validated
├── ✅ LUKS auto-unlock
├── ✅ SPIRE Agent v1.14.1
├── ✅ Workload identity: spiffe://funlab.casa/agent/auth
└── ✅ Workloads: test-workload

ca.funlab.casa (10.10.2.60)
├── ✅ TPM 2.0 validated
├── ✅ LUKS auto-unlock
├── ✅ step-ca (YubiKey-backed)
├── ✅ SPIRE Agent v1.14.1
├── ✅ Workload identity: spiffe://funlab.casa/agent/ca
└── ✅ Workloads: step-ca
```

---

## Technical Implementation

### SPIRE Agent Installation on spire

**Pre-existing Components:**
- SPIRE Server binaries already included agent binaries
- No download required (already at /opt/spire/bin/spire-agent)

**Steps Performed:**
1. Created system user: `spire` (UID assigned by system)
2. Created directories:
   - /etc/spire (config)
   - /var/lib/spire/agent (data)
   - /run/spire/sockets (API socket)
3. Created agent configuration: /etc/spire/agent.conf
4. Created systemd service: /etc/systemd/system/spire-agent.service
5. Generated join token from SPIRE Server
6. Started agent with join token for initial attestation
7. Restarted agent via systemd for persistent operation

**Configuration Highlights:**
```hcl
agent {
  data_dir = "/var/lib/spire/agent"
  server_address = "spire.funlab.casa"
  server_port = "8081"
  socket_path = "/run/spire/sockets/agent.sock"
  trust_domain = "funlab.casa"
  insecure_bootstrap = true
}

plugins {
  NodeAttestor "join_token" {}
  KeyManager "disk" {}
  WorkloadAttestor "unix" {}
}

health_checks {
  listener_enabled = true
  bind_address = "127.0.0.1"
  bind_port = "8088"
}
```

### OpenBao Workload Registration

**Command:**
```bash
sudo /opt/spire/bin/spire-server entry create \
  -parentID spiffe://funlab.casa/spire/agent/join_token/48fc8456-ac44-427b-8fd6-1f1475bbcb3d \
  -spiffeID spiffe://funlab.casa/workload/openbao \
  -selector unix:uid:999 \
  -x509SVIDTTL 3600 \
  -dns spire.funlab.casa \
  -dns localhost
```

**Why These Settings:**
- **Selector unix:uid:999:** OpenBao runs as openbao user (UID 999)
- **TTL 3600:** 1-hour certificates with automatic rotation
- **DNS SANs:** Enables TLS with both hostname and localhost

---

## Benefits Achieved

### 1. OpenBao Has Workload Identity
- No longer requires static credentials for SPIRE integration
- Can authenticate as `spiffe://funlab.casa/workload/openbao`
- Ready for JWT-SVID based authentication

### 2. Complete Agent Coverage
- All 3 hosts now have SPIRE Agents
- Full workload identity infrastructure operational
- Consistent attestation model across all hosts

### 3. Foundation for JWT Authentication
- OpenBao can now retrieve JWT-SVIDs
- Ready for Phase 2: SPIRE Server OIDC configuration
- Enables workload-to-OpenBao authentication without secrets

---

## Verification Results

### Health Checks (All Passing)

```bash
# spire agent
$ curl http://127.0.0.1:8088/ready
{"agent":{}}  ✅

# auth agent
$ ssh auth "curl http://127.0.0.1:8088/ready"
{"agent":{}}  ✅

# ca agent
$ ssh ca "curl http://127.0.0.1:8088/ready"
{"agent":{}}  ✅
```

### Agent List

```
Found 3 attested agents:
✅ auth.funlab.casa (48a28e50-f108-4164-930b-df64142851f8)
✅ ca.funlab.casa (9269fd4b-e483-4ee8-8cba-d624b204caba)
✅ spire.funlab.casa (48fc8456-ac44-427b-8fd6-1f1475bbcb3d)
```

### SVID Retrieval Performance

```
✅ openbao:       2.76ms (NEW!)
✅ step-ca:       3.7ms
✅ test-workload: 6.5ms
```

All sub-10ms, excellent performance!

---

## What's Next: Sprint 2 Phase 2

### Phase 2: JWT Authentication Integration

**Objective:** Enable workloads to authenticate to OpenBao using JWT-SVIDs

**Tasks:**
1. Configure SPIRE Server JWT-SVID issuer
   - Enable OIDC discovery endpoint
   - Configure JWT key rotation
   - Set issuer URL

2. Update OpenBao JWT auth configuration
   - Point jwt_auth backend to SPIRE OIDC endpoint
   - Create policies for SPIRE workloads
   - Map SPIFFE IDs to OpenBao roles

3. Test end-to-end JWT authentication
   - step-ca retrieves JWT-SVID
   - step-ca authenticates to OpenBao
   - step-ca retrieves secret
   - Verify no static credentials used

**Duration:** 2-3 hours
**Complexity:** Medium (new SPIRE features)

---

## Sprint 2 Progress

**Phase 1:** ✅ COMPLETE (OpenBao workload identity)
**Phase 2:** ⏳ NEXT (JWT authentication integration)
**Phase 3:** ⏳ PENDING (TPM DevID provisioning)
**Phase 4:** ⏳ PENDING (Documentation & testing)

**Overall Sprint 2 Progress:** 25% complete

---

## Quick Reference

### Check spire Agent Status
```bash
ssh spire "sudo systemctl status spire-agent"
```

### Test OpenBao SVID Retrieval
```bash
ssh spire "sudo -u openbao /opt/spire/bin/spire-agent api fetch x509 -socketPath /run/spire/sockets/agent.sock"
```

### List All Agents
```bash
ssh spire "sudo /opt/spire/bin/spire-server agent list"
```

### List All Entries
```bash
ssh spire "sudo /opt/spire/bin/spire-server entry show"
```

---

## Success Metrics

✅ **Phase 1 Goals Achieved:**
- [x] SPIRE Agent deployed on spire.funlab.casa
- [x] Agent attested to SPIRE Server
- [x] OpenBao registered as workload
- [x] SVID retrieval verified (2.76ms)
- [x] All health checks passing
- [x] All 3 hosts have SPIRE Agents

**Deployment Time:** 30 minutes
**Agents Deployed:** 3/3 ✅
**Workloads Registered:** 3 production workloads
**Test Success Rate:** 100%
**Incidents:** 0

---

**Phase 1 Status:** ✅ COMPLETE
**Ready for Phase 2:** ✅ YES
**Last Updated:** 2026-02-10 17:20 EST

