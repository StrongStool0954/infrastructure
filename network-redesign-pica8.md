# Network Redesign: 10Gbps Infrastructure with Pica8 P3922

**Date:** 2026-02-07
**Status:** Phase 1 In Progress - pm01 migrated ✓, wily pending, Firewalla 10G uplink pending

---

## Problem Statement

### Original Network Bottleneck
- **Firewalla Gold Pro** connected to **Netgear MS510TXUP** via 1Gbps uplink
- Infrastructure hosts (pm01 Proxmox, wily TrueNAS) had 10Gbps NICs but limited to 1Gbps WAN speed
- Speedtest results: ~920 Mbps despite 5+ Gbps ISP service
- Root cause: 1Gbps uplink between switch and Firewalla

### Goal
- Achieve 5+ Gbps throughput to infrastructure hosts
- Leverage Firewalla Gold Pro's 10G SFP+ LAN port
- Implement redundant LACP bonds for critical infrastructure
- Prioritize WiFi backbone (3x Firewalla Access Points via Netgear PoE switch)

---

## Solution Architecture

### Hardware Used
- **Pica8 P3922 Switch**
  - 48x 10G SFP+ ports
  - 4x 40G QSFP+ ports
  - PicOS 2.11.7
  - Management IP: 192.168.33.252

- **Connectivity**
  - 10G SFP+ DAC cables for host-to-switch connections
  - 10GBASE-T SFP+ module for Firewalla uplink (copper RJ45)

### Network Topology

```
                    Internet (5+ Gbps)
                           |
                    Firewalla Gold Pro
                     (10.200.200.1)
                           |
                           | 10G SFP+ (te-1/1/7)
                           |
                  Pica8 P3922 Core Switch
                  (192.168.33.252 mgmt)
                           |
        +------------------+------------------+
        |                  |                  |
       ae1                ae2                ae3
    (20Gbps)           (20Gbps)           (20Gbps)
        |                  |                  |
    Netgear            pm01.funlab        wily.funlab
    MS510TXUP          (Proxmox)          (TrueNAS)
        |
   WiFi Backbone
   3x Access Points
```

---

## Port Assignments

| Priority | Device | Pica8 Ports | Bond | Cable Type | Speed | Purpose |
|----------|--------|-------------|------|------------|-------|---------|
| **1** | Netgear MS510TXUP | te-1/1/1, te-1/1/2 | ae1 | 10G SFP+ DAC | 20Gbps | WiFi backbone |
| **2** | pm01.funlab.casa | te-1/1/3, te-1/1/4 | ae2 | 10G SFP+ DAC | 20Gbps | Proxmox host |
| **3** | wily.funlab.casa | te-1/1/5, te-1/1/6 | ae3 | 10G SFP+ DAC | 20Gbps | TrueNAS storage |
| **4** | Firewalla Gold Pro | te-1/1/7 | - | 10GBASE-T SFP+ | 10Gbps | Internet uplink |

---

## Configuration

### Pica8 P3922 Switch Configuration

**Access:**
```bash
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password admin@192.168.33.252
# Password: !!Gizmo1207
cli
configure
```

**Complete Configuration:**

```
# ae1 - Netgear MS510TXUP (WiFi Backbone - PRIORITY 1)
set interface aggregate-ethernet ae1 aggregated-ether-options lacp enable true
set interface aggregate-ethernet ae1 family ethernet-switching native-vlan-id 1
set interface aggregate-ethernet ae1 family ethernet-switching port-mode access
set interface aggregate-ethernet ae1 mtu 9216
set interface aggregate-ethernet ae1 description "Netgear-WiFi-Backbone"
set interface gigabit-ethernet te-1/1/1 ether-options 802.3ad ae1
set interface gigabit-ethernet te-1/1/1 description "Netgear-port1"
set interface gigabit-ethernet te-1/1/2 ether-options 802.3ad ae1
set interface gigabit-ethernet te-1/1/2 description "Netgear-port2"

# ae2 - pm01 Proxmox Host
set interface aggregate-ethernet ae2 aggregated-ether-options lacp enable true
set interface aggregate-ethernet ae2 family ethernet-switching native-vlan-id 1
set interface aggregate-ethernet ae2 family ethernet-switching port-mode access
set interface aggregate-ethernet ae2 mtu 9216
set interface aggregate-ethernet ae2 description "pm01-Proxmox-LACP"
set interface gigabit-ethernet te-1/1/3 ether-options 802.3ad ae2
set interface gigabit-ethernet te-1/1/3 description "pm01-port1"
set interface gigabit-ethernet te-1/1/4 ether-options 802.3ad ae2
set interface gigabit-ethernet te-1/1/4 description "pm01-port2"

# ae3 - wily TrueNAS Storage
set interface aggregate-ethernet ae3 aggregated-ether-options lacp enable true
set interface aggregate-ethernet ae3 family ethernet-switching native-vlan-id 1
set interface aggregate-ethernet ae3 family ethernet-switching port-mode access
set interface aggregate-ethernet ae3 mtu 9216
set interface aggregate-ethernet ae3 description "wily-TrueNAS-LACP"
set interface gigabit-ethernet te-1/1/5 ether-options 802.3ad ae3
set interface gigabit-ethernet te-1/1/5 description "wily-port1"
set interface gigabit-ethernet te-1/1/6 ether-options 802.3ad ae3
set interface gigabit-ethernet te-1/1/6 description "wily-port2"

# te-1/1/7 - Firewalla Uplink
set interface gigabit-ethernet te-1/1/7 family ethernet-switching native-vlan-id 1
set interface gigabit-ethernet te-1/1/7 family ethernet-switching port-mode access
set interface gigabit-ethernet te-1/1/7 mtu 9216
set interface gigabit-ethernet te-1/1/7 description "Firewalla-Uplink-10G"

# Commit and save
commit
save
```

**Verification:**
```bash
show interface aggregate-ethernet
show lacp interfaces
show interface te-1/1/7
```

---

## Host Configuration

### 1. Netgear MS510TXUP (WiFi Backbone)

**Web UI Configuration:**
1. Navigate to: **System → Switching → LAG → Advanced → LAG Configuration**
2. Create new LAG:
   - **LAG ID:** 1
   - **Type:** LACP (802.3ad)
   - **Mode:** Active
   - **Member Ports:** Both 10G SFP+ ports
   - **Name:** "Pica8-Uplink"
3. Apply configuration
4. Verify link status shows both ports active

### 2. pm01.funlab.casa (Proxmox)

**SSH to host:**
```bash
ssh root@pm01.funlab.casa
```

**Edit network configuration:**
```bash
nano /etc/network/interfaces
```

**Bond configuration:**
```
# Remove or comment out individual interface configs

# LACP bond for dual 10G ports
auto bond0
iface bond0 inet static
    address 10.200.200.10
    netmask 255.255.255.0
    gateway 10.200.200.1
    bond-slaves enp2s0f0np0 enp2s0f1np1
    bond-mode 802.3ad
    bond-miimon 100
    bond-lacp-rate fast
    bond-xmit-hash-policy layer3+4
    mtu 9000
```

**Apply configuration:**
```bash
ifreload -a
# Or reboot if network restart fails
```

**Verify bond status:**
```bash
cat /proc/net/bonding/bond0
ip link show bond0
```

### 3. wily.funlab.casa (TrueNAS)

**TrueNAS Web UI:**

1. Navigate to: **Network → Link Aggregations**
2. Click **Add**
3. Configure LACP:
   - **Type:** LACP
   - **Interfaces:** Select both 10G interfaces
   - **LACP Timeout:** Fast
   - **Transmit Hash Policy:** LAYER3+4
   - **MTU:** 9000
   - **Description:** "Pica8-LACP-Bond"
4. **Save**

5. Navigate to: **Network → Interfaces**
6. Edit the new LAGG interface:
   - **IP Address:** 10.200.200.x (assign appropriate IP)
   - **Netmask:** 255.255.255.0
   - **Gateway:** 10.200.200.1
7. **Test Changes** → **Save Changes**

**Verify:**
- Check **Network → Link Aggregations** status
- Both member ports should show "ACTIVE"

---

## Firewalla 10G Uplink (Phase 2)

**Required Hardware:**
- 10GBASE-T SFP+ module (FS.com SFP-10G-T, 10Gtek ASF-10G-T, or Ubiquiti UF-RJ45-10G)
- Cat6a or Cat7 ethernet cable

**Installation Procedure:**

1. **Insert module:**
   - Install 10GBASE-T SFP+ module into Pica8 port te-1/1/7

2. **Connect cable:**
   - Connect Cat6a/Cat7 from Firewalla 10G copper port to SFP+ module

3. **Verify link:**
   ```bash
   ssh admin@192.168.33.252
   cli
   show interface te-1/1/7
   ```
   Look for: `Speed: 10000mbps`

4. **No additional configuration needed** - port already configured

---

## Testing & Verification

### LACP Bond Status

**On Pica8:**
```bash
ssh admin@192.168.33.252
cli
show lacp interfaces
show lacp statistics interfaces ae1
show lacp statistics interfaces ae2
show lacp statistics interfaces ae3
```

**Expected output:**
- Actor State: "Active", "Aggregation", "Synchronization", "Collecting", "Distributing"
- Partner State: Same as Actor
- Both member ports in each bond showing active

**On pm01:**
```bash
cat /proc/net/bonding/bond0
```

**Expected:**
- Bonding Mode: IEEE 802.3ad Dynamic link aggregation
- Aggregator ID: Same for both slaves
- MII Status: up
- Both interfaces: Active aggregator

**On TrueNAS:**
- Navigate to: **Network → Link Aggregations**
- Status should show "ACTIVE"
- Both member ports: ACTIVE

### Connectivity Test

```bash
# From pm01
ping 10.200.200.1      # Firewalla gateway
ping 10.200.200.x      # wily TrueNAS
ping 8.8.8.8           # Internet

# From wily (TrueNAS shell)
ping 10.200.200.1      # Firewalla gateway
ping 10.200.200.10     # pm01 Proxmox
ping 8.8.8.8           # Internet
```

### Performance Test

**After Firewalla 10G uplink is connected:**

```bash
# Trigger speedtest from pm01
curl -X POST http://10.200.200.10:8888/trigger

# Wait ~60 seconds for test to complete

# Retrieve results
curl http://10.200.200.10:8888/speedtest
```

**Expected Results:**
- **Before:** ~920 Mbps (1Gbps bottleneck)
- **After:** 5+ Gbps (full ISP speed)

---

## Troubleshooting

### LACP Bond Not Forming

**Symptoms:**
- `show lacp interfaces` shows "No Collecting" or "No Distributing"
- Host shows "MII Status: down"

**Fixes:**
1. Verify both cables connected to correct ports
2. Check host-side LACP configured (802.3ad mode)
3. Verify switch ports in same LACP bond: `show interface ae1`
4. Check for mismatched MTU settings
5. Restart host network or reboot

**Debug commands:**
```bash
# Pica8
show lacp interfaces detail
show interface te-1/1/X extensive

# Linux (pm01)
dmesg | grep bond
journalctl -u networking -n 50

# TrueNAS
Check System → View Logs
```

### One Link Down in Bond

**Symptoms:**
- Only one port showing active in LACP bond
- Reduced throughput (10Gbps instead of 20Gbps)

**Fixes:**
1. Check cable seating on both ends
2. Verify SFP+ module/DAC cable compatibility
3. Check for port errors: `show interface te-1/1/X extensive | match error`
4. Try swapping cables between ports
5. Check host-side NIC status: `ethtool enp2s0f0np0`

### No Internet After Reconfiguration

**Symptoms:**
- Local network works (can ping other hosts)
- Cannot reach internet (ping 8.8.8.8 fails)

**Fixes:**
1. Verify Firewalla uplink on te-1/1/7 is up
2. Check Firewalla routing rules
3. Verify gateway setting on hosts (should be 10.200.200.1)
4. Check VLAN configuration on Firewalla if using VLANs
5. Restart Firewalla services

### Poor Performance After Upgrade

**Symptoms:**
- Speedtest shows < 1Gbps despite 10G links
- High latency or packet loss

**Fixes:**
1. Verify 10G link speed: `show interface te-1/1/7` (should show 10000mbps)
2. Check for packet drops: `show interface te-1/1/7 extensive | match drop`
3. Verify MTU 9216 on all switch ports
4. Check host MTU settings (should be 9000)
5. Monitor switch CPU: `show system resources`
6. Check for duplex mismatches: `show interface te-1/1/X extensive | match duplex`

---

## Maintenance

### Monitoring LACP Health

**Daily/Weekly Checks:**
```bash
# SSH to Pica8
ssh admin@192.168.33.252
cli

# Check all LACP bonds
show lacp interfaces

# Look for:
# - All ports "Collecting" and "Distributing"
# - No error counters incrementing
# - Both links in each bond active
```

### Firmware Updates

**Current Version:** PicOS 2.11.7 (May 2018)
**Available:** PicOS 2.11.24 (latest stable for P3922)

**Note:** PicOS 4.x appears incompatible with P3922 hardware based on documentation review.

### Configuration Backup

**Backup current config:**
```bash
ssh admin@192.168.33.252
cli
show configuration | display set > pica8-config-backup-$(date +%Y%m%d).txt
```

**Save to local machine:**
```bash
scp admin@192.168.33.252:pica8-config-backup-*.txt ~/backups/
```

---

## Performance Benchmarks

### Before Network Redesign
- **Test Date:** 2026-02-06
- **Topology:** pm01 → Netgear (10G) → Firewalla (1G) → Internet
- **Speedtest Results:**
  - Download: 922.95 Mbps
  - Upload: 810.24 Mbps
- **Bottleneck:** 1Gbps uplink between Netgear and Firewalla

### After Network Redesign (Expected)
- **Test Date:** 2026-02-08 (after Firewalla 10G uplink)
- **Topology:** pm01 → Pica8 (20G LACP) → Firewalla (10G) → Internet
- **Expected Results:**
  - Download: 5+ Gbps
  - Upload: 4+ Gbps
- **Bottleneck Removed:** Full 10Gbps path to Firewalla

---

## Future Enhancements

### Planned
1. ✅ Configure LACP bonds (Phase 1 - Complete)
2. ⏳ Add Firewalla 10G uplink (Phase 2 - Pending 10GBASE-T SFP+ module)
3. 🔜 Create dedicated management network (10.10.20.0/24)
4. 🔜 Implement VLANs for network segmentation
5. 🔜 Configure SNMP monitoring for Pica8

### Considered
- Upgrade pm01 network optimization (already applied BBR, ring buffers)
- Add additional Proxmox hosts to LACP bonds
- Implement 40G uplink if bandwidth requirements grow
- Firmware upgrade to PicOS 2.11.24 (if stable)

---

## References

### Documentation
- Pica8 P3922 Hardware Guide
- PicOS 2.11 Configuration Guide
- LACP (IEEE 802.3ad) Specification
- Proxmox Network Configuration Guide
- TrueNAS Network Configuration Guide

### Network Optimization
- TCP BBR Congestion Control
- NIC Ring Buffer Tuning
- Jumbo Frames (MTU 9000/9216)
- Linux Bonding Modes

### Related Scripts
- `/tmp/optimize-pm01-network.sh` - Network optimization script for pm01
- Speedtest server: http://10.200.200.10:8888

---

## Implementation Progress (2026-02-07)

### Completed Today

#### 1. Pica8 Management Configuration ✓
- **Management DHCP enabled** - Switch picks up IP automatically on any network
- **Current management IP:** 10.10.2.100/24 (DHCP)
- **Accessible from:** 10.10.2.x network (Firewalla LAN)

#### 2. VLAN Configuration ✓
Created and configured VLANs matching Firewalla networks:
- **VLAN 100** - Media (192.168.22.x)
- **VLAN 200** - Management (10.10.10.x)
- **VLAN 300** - Home (192.168.147.x)
- **VLAN 400** - Phreesia (192.168.136.x)
- **VLAN 500** - Funlab (10.200.200.x)
- **VLAN 1** - Untagged/Native (10.10.2.x)

#### 3. Firewalla Trunk Link ✓
- **Port:** te-1/1/7
- **Configuration:** Trunk mode with all VLANs (100, 200, 300, 400, 500) + native VLAN 1
- **Current connection:** Firewalla Port 2 (2.5G) → Pica8 te-1/1/7 (1G SFP+ DAC temporary)
- **Status:** Active, trunk working, all VLANs passing
- **Future:** Will upgrade to 10GBASE-T module when arrives

**Firewalla Configuration:**
- Port 1 (10G): Currently connected to Netgear (existing WiFi path)
- Port 2 (2.5G): Configured as VLAN trunk → Pica8 te-1/1/7

#### 4. pm01 Migration Complete ✓
**Switch Configuration:**
- **Bond:** ae2 (LACP 802.3ad)
- **Ports:** te-1/1/3 + te-1/1/4 (10G SFP+ DAC)
- **VLAN:** 500 (Funlab - 10.200.200.x) access mode
- **Status:** LACP fully formed, State 0x3F (collecting/distributing)

**pm01 Host Configuration:**
- **OS:** Proxmox VE
- **Bond:** bond0 (802.3ad LACP)
- **Interfaces:** enp2s0f0np0 + enp2s0f1np1
- **Bridge:** vmbr0 (Proxmox bridge using bond0)
- **IP:** 10.200.200.10/24
- **MTU:** 9000 (jumbo frames)
- **Status:** LACP active, Aggregator ID: 2, both links 10Gbps full duplex
- **Connectivity:** Verified - pings to gateway and internet working

**Migration Method:**
- Used gradual migration: kept one port on Netgear during config
- Configured bond while maintaining connectivity
- Moved both ports to Pica8 once bond configured
- Zero IRC downtime during migration

### In Progress

#### 5. wily Migration (Next)
**Switch Configuration:** ae3 ready
- **Bond:** ae3 (LACP 802.3ad)
- **Ports:** te-1/1/5 + te-1/1/6 (10G SFP+ DAC)
- **VLAN:** 500 (Funlab - 10.200.200.x) access mode
- **Status:** Configured, awaiting host-side LACP

**Next Steps:**
1. Connect wily port 2 → Pica8 te-1/1/6 (keep port 1 on Netgear)
2. Configure TrueNAS LACP via web UI
3. Move wily port 1 → Pica8 te-1/1/5
4. Verify LACP forms
5. Test connectivity

### Pending (After wily Migration)

#### 6. Netgear Migration
Once pm01 and wily are migrated, Netgear SFP+ ports will be free:
1. Configure ae1 (Netgear bond) as trunk with all VLANs
2. Configure Netgear LACP on both SFP+ ports
3. Connect Netgear → Pica8 te-1/1/1 + te-1/1/2
4. WiFi APs traffic flows: APs → Netgear → Pica8 → Firewalla
5. Disconnect Firewalla Port 1 from Netgear

#### 7. Firewalla 10G Upgrade (Tomorrow - when 10GBASE-T module arrives)
1. Disconnect Firewalla Port 2 temporary link
2. Swap 1G SFP+ module → 10GBASE-T SFP+ module on te-1/1/7
3. Move Firewalla Port 1 (10G) → Pica8 te-1/1/7
4. Full 10G trunk active with all VLANs
5. Run speedtest - expect 5+ Gbps!

### Network State Diagram

**Current (During Migration):**
```
Internet
   |
Firewalla Gold Pro
   |                    |
Port 1 (10G)         Port 2 (2.5G Trunk)
   |                    |
Netgear              Pica8 te-1/1/7 (1G temp)
   |                    |
WiFi APs          +-----+------+
  (Active)        |            |
               ae2 (pm01)   ae3 (wily)
                  |            |
              pm01 ✓      wily (pending)
```

**Target (After Full Migration):**
```
Internet
   |
Firewalla Gold Pro
   |
Port 1 (10G Trunk - all VLANs)
   |
Pica8 te-1/1/7
   |
   +----------+----------+----------+
   |          |          |          |
  ae1        ae2        ae3      (other)
   |          |          |
Netgear     pm01       wily
   |
WiFi APs
```

### Key Learnings

1. **DHCP Management:** Rebooting the switch after removing static IP and gateway enabled DHCP automatically
2. **VLAN Trunking:** Firewalla supports multiple ports as VLAN trunks (Port 1 + Port 2 both trunking)
3. **Gradual Migration:** Keeping one interface on old network during bond configuration prevents downtime
4. **Proxmox Bonding:** Must bridge the bond (bond0 → vmbr0), not the individual interfaces
5. **LACP Verification:** Same Aggregator ID = LACP formed; State 0x3F = fully active
6. **Zero-Downtime Possible:** With dual trunk ports, migration can be done without WiFi/IRC interruption

### Hardware Inventory Used

- **10G SFP+ DAC cables:** 4 (pm01 x2, wily x2 pending, Netgear x2 pending)
- **1G SFP+ module:** 1 (temporary Firewalla uplink)
- **10GBASE-T SFP+ module:** 1 (on order, arrives tomorrow)
- **Cat6a/Cat7 cables:** 1 (for 10GBASE-T Firewalla connection)

---

## Change Log

| Date | Change | Status |
|------|--------|--------|
| 2026-02-06 | Identified 1Gbps bottleneck via speedtest | Complete |
| 2026-02-07 | Configured Pica8 management DHCP (10.10.2.100) | Complete |
| 2026-02-07 | Created VLANs 100, 200, 300, 400, 500 on Pica8 | Complete |
| 2026-02-07 | Configured te-1/1/7 as VLAN trunk to Firewalla | Complete |
| 2026-02-07 | Connected Firewalla Port 2 → Pica8 (1G temp trunk) | Complete |
| 2026-02-07 | Configured ae2 (pm01) LACP bond on VLAN 500 | Complete |
| 2026-02-07 | Migrated pm01 to Pica8 with LACP bonding | Complete |
| 2026-02-07 | Verified pm01 connectivity and LACP status | Complete |
| 2026-02-07 | Migrate wily to Pica8 with LACP bonding | In Progress |
| 2026-02-07 | Migrate Netgear to Pica8 LACP trunk | Pending |
| 2026-02-08 | Install 10GBASE-T SFP+ module (arriving tomorrow) | Pending |
| 2026-02-08 | Upgrade Firewalla Port 1 to Pica8 (10G trunk) | Pending |
| 2026-02-08 | Performance test - verify 5+ Gbps | Pending |

---

**Author:** Claude Code Assistant
**Last Updated:** 2026-02-07
**Configuration Status:** Phase 1 Complete, Phase 2 Pending Hardware
