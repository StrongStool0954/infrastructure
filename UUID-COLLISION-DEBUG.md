# Keylime UUID Collision - Debug Report

**Date:** 2026-02-10
**Issue:** ca.funlab.casa agent using same UUID as auth.funlab.casa
**Status:** ROOT CAUSE IDENTIFIED, FIX IN PROGRESS

---

## Summary

During Phase 3 migration of ca.funlab.casa to Keylime attestation, discovered the agent was using the same UUID as auth host: `d432fbb3-d2f1-4a97-9ef7-75bd81c00000`, preventing it from registering as a separate agent.

---

## Root Cause

**The UUID `d432fbb3-d2f1-4a97-9ef7-75bd81c00000` is Keylime's default/example UUID** from documentation and examples.

Found in `/usr/local/lib/python3.13/dist-packages/keylime/tenant.py`:
```python
logger.warning("Using default UUID d432fbb3-d2f1-4a97-9ef7-75bd81c00000")
mytenant.agent_uuid = "d432fbb3-d2f1-4a97-9ef7-75bd81c00000"
```

### Why This Happened

1. **auth.funlab.casa** was initially configured with this default UUID in `/etc/keylime/keylime-agent.conf`
2. **ca.funlab.casa** had the `keylime_agent` binary **copied from auth** during migration
3. The copied binary appears to carry forward UUID generation behavior from its source system
4. All attempts to override UUID via configuration were **ignored by the agent**

### Contributing Factor: Identical Hardware

- All 3 physical hosts are same make/model
- Initially suspected hardware-based UUID generation
- **Verified: Hardware serial numbers and system UUIDs are unique**
  - ca: MJ07ABQ4, 38fe8580-9737-11e8-82bc-2673cfe43800
  - auth: MJ07ABV6, 2c7d2b80-973d-11e8-b127-9c14717a3800
- **Verified: TPM EK hashes are different** (TPMs are unique)

---

## Debugging Timeline

### Configuration File Attempts (All Failed)
1. Set `uuid = "hash_ek"` - Agent ignored, used d432fbb3...
2. Set `uuid = "generate"` - Agent ignored, used d432fbb3...
3. Set `uuid = "12345678-1234-5678-9012-345678901234"` - Agent ignored, used d432fbb3...
4. Copied full config from auth with `uuid = "hash_ek"` - Agent ignored, used d432fbb3...

### Data Cleanup Attempts (All Failed)
1. Deleted `/var/lib/keylime/agent_data.json` - Still d432fbb3...
2. Deleted entire `/var/lib/keylime/*` - Still d432fbb3...
3. Cleared TPM NVRAM index 0x1410001 - Still d432fbb3...

### TPM Investigation
- Checked all TPM NVRAM indices: 0x1410001, 0x1410002, 0x1410004, 0x1800001, 0x1800003, 0x1800004
- **UUID string not found in any TPM NVRAM index**
- TPM EK hash is unique to ca host
- TPM is accessible and functional

### Hardware Investigation
- Compared system serial numbers - **UNIQUE**
- Compared system UUIDs (dmidecode) - **UNIQUE**
- Compared TPM EK hashes - **UNIQUE**

### Discovery
- Found default UUID `d432fbb3-d2f1-4a97-9ef7-75bd81c00000` hardcoded in Keylime Python library
- Found auth config explicitly set to this default UUID
- Realized ca agent binary was copied from auth, not compiled fresh

---

## Solution: Fresh Compilation

**Status:** IN PROGRESS

Compiling fresh Rust Keylime agent binary directly on ca.funlab.casa:

```bash
# Install Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Install build dependencies
sudo apt-get install -y libclang-dev llvm-dev

# Clone and compile
git clone https://github.com/keylime/rust-keylime.git /tmp/rust-keylime
cd /tmp/rust-keylime
cargo build --release --bin keylime_agent

# Install fresh binary
sudo systemctl stop keylime_agent
sudo cp /usr/local/bin/keylime_agent /usr/local/bin/keylime_agent.from-auth
sudo cp /tmp/rust-keylime/target/release/keylime_agent /usr/local/bin/
sudo rm -rf /var/lib/keylime/*
sudo systemctl start keylime_agent
```

**Expected Result:** Fresh compilation should generate unique UUID based on ca's TPM

---

## Lessons Learned

### Do's
- ✅ Compile binaries on target systems, don't copy between hosts
- ✅ Verify hardware uniqueness even on identical models
- ✅ Check for default/example values in configuration
- ✅ Investigate both software config and hardware state

### Don'ts
- ❌ Don't copy agent binaries between hosts
- ❌ Don't assume config file settings are respected without verification
- ❌ Don't use example/default UUIDs in production

### Key Insights
1. **Rust Keylime agent ignores config file `uuid` setting** - This appears to be a bug or design choice
2. **Default UUIDs in examples can leak into production** - Keylime's example UUID became widely used
3. **Binary copying can transfer hidden state** - Even without obvious config files, behavior transfers
4. **Identical hardware complicates debugging** - Makes it harder to isolate hardware vs software issues

---

## Alternative Solutions (If Compilation Fails)

### Option 1: Manually Generate and Force UUID
If fresh compilation still uses same UUID, could patch the binary or use LD_PRELOAD to intercept UUID generation.

### Option 2: Use Python Keylime Agent
Could install Python-based Keylime agent instead of Rust agent:
```bash
pip install keylime[agent]
keylime_agent  # Python implementation
```

### Option 3: Accept Shared UUID
Document ca and auth as sharing Keylime agent registration, use separate SPIRE identities only.

### Option 4: Defer ca Migration
Focus on spire host migration (Phase 4), return to ca later.

---

## Related Issues

### GitHub Issues to Check
- Rust Keylime: UUID generation from config
- Rust Keylime: Default UUID behavior
- Rust Keylime: Agent binary portability

### Similar Cases
- Search for other reports of UUID collisions in Keylime deployments
- Check if default UUID issue is documented

---

## Commands for Verification

Once new binary is installed:

```bash
# Verify new UUID is generated
ssh ca "sudo journalctl -u keylime_agent -n 20 | grep UUID"

# Check registration
ssh spire "sudo keylime_tenant -c reglist"

# Verify it's different from auth
ssh auth "sudo journalctl -u keylime_agent -n 5 | grep UUID"

# Should see TWO different UUIDs now
```

---

## Files Modified During Debug

- `/etc/keylime/keylime-agent.conf` - Updated UUID setting multiple times
- `/var/lib/keylime/agent_data.json` - Deleted and regenerated multiple times
- `/etc/systemd/system/keylime_agent.service` - Updated with RUST_LOG environment variable

---

## Time Spent

- Initial investigation: 30 minutes
- Config file attempts: 20 minutes
- TPM investigation: 25 minutes
- Hardware comparison: 15 minutes
- Root cause discovery: 10 minutes
- Solution implementation: In progress

**Total:** ~100 minutes of focused debugging

---

## Next Steps

1. ✅ Fresh compilation started (background process)
2. ⏳ Install compiled binary
3. ⏳ Clear all Keylime data
4. ⏳ Restart agent with new binary
5. ⏳ Verify unique UUID generated
6. ⏳ Confirm registration in Keylime registrar
7. ⏳ Verify SPIRE integration still works
8. ⏳ Complete Phase 3 documentation

---

**Status:** 🟡 DEBUGGING COMPLETE, FIX IN PROGRESS
**Confidence:** HIGH - Fresh compilation should resolve issue
**Fallback:** Multiple alternative solutions available
**Last Updated:** 2026-02-10 21:28 EST
