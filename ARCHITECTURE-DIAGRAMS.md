# Tower of Omens - Architecture Diagrams

**Date:** 2026-02-10  
**Status:** Production  
**Purpose:** Visual documentation of infrastructure architecture

---

## Table of Contents
1. [Infrastructure Overview](#infrastructure-overview)
2. [Trust Chain](#trust-chain)
3. [PKI Hierarchy](#pki-hierarchy)
4. [Attestation Flow](#attestation-flow)
5. [Network Topology](#network-topology)
6. [Certificate Issuance Flow](#certificate-issuance-flow)
7. [SPIRE Agent Registration](#spire-agent-registration)

---

## Infrastructure Overview

```mermaid
graph TB
    subgraph "Tower of Omens Infrastructure"
        subgraph "auth.funlab.casa (10.10.2.70)"
            AUTH_KA[Keylime Agent<br/>HTTPS:9002]
            AUTH_SA[SPIRE Agent<br/>Keylime Attestation]
            AUTH_TPM[TPM 2.0<br/>Hardware Root of Trust]
            AUTH_TPM --> AUTH_KA
            AUTH_KA --> AUTH_SA
        end

        subgraph "ca.funlab.casa (10.10.2.60)"
            CA_KA[Keylime Agent<br/>HTTPS:9002]
            CA_SA[SPIRE Agent<br/>Keylime Attestation]
            CA_TPM[TPM 2.0<br/>Hardware Root of Trust]
            CA_STEP[step-ca<br/>Sword of Omens]
            CA_TPM --> CA_KA
            CA_KA --> CA_SA
        end

        subgraph "spire.funlab.casa (10.10.2.62)"
            SPIRE_KA[Keylime Agent<br/>HTTPS:9002]
            SPIRE_SA[SPIRE Agent<br/>Self-Attestation]
            SPIRE_TPM[TPM 2.0<br/>Hardware Root of Trust]
            SPIRE_SERVER[SPIRE Server<br/>Trust Domain Controller]
            SPIRE_VERIFIER[Keylime Verifier<br/>:8881 TLS]
            SPIRE_REGISTRAR[Keylime Registrar<br/>:8891 TLS]
            OPENBAO[OpenBao PKI<br/>Book of Omens CA]
            
            SPIRE_TPM --> SPIRE_KA
            SPIRE_KA --> SPIRE_SA
            SPIRE_SA --> SPIRE_SERVER
        end
    end

    AUTH_KA -->|HTTPS/mTLS<br/>Continuous Attestation| SPIRE_VERIFIER
    CA_KA -->|HTTPS/mTLS<br/>Continuous Attestation| SPIRE_VERIFIER
    SPIRE_KA -->|HTTPS/mTLS<br/>Continuous Attestation| SPIRE_VERIFIER
    
    AUTH_SA -->|Keylime<br/>Attestation| SPIRE_SERVER
    CA_SA -->|Keylime<br/>Attestation| SPIRE_SERVER
    
    AUTH_KA -->|Register| SPIRE_REGISTRAR
    CA_KA -->|Register| SPIRE_REGISTRAR
    SPIRE_KA -->|Register| SPIRE_REGISTRAR
    
    OPENBAO -->|Issue Certs| AUTH_KA
    OPENBAO -->|Issue Certs| CA_KA
    OPENBAO -->|Issue Certs| SPIRE_KA

    style AUTH_KA fill:#90EE90
    style CA_KA fill:#90EE90
    style SPIRE_KA fill:#90EE90
    style AUTH_SA fill:#87CEEB
    style CA_SA fill:#87CEEB
    style SPIRE_SA fill:#87CEEB
    style SPIRE_SERVER fill:#FFD700
    style SPIRE_VERIFIER fill:#FFB6C1
    style OPENBAO fill:#DDA0DD
    style AUTH_TPM fill:#FF6B6B
    style CA_TPM fill:#FF6B6B
    style SPIRE_TPM fill:#FF6B6B
```

---

## Trust Chain

```mermaid
graph LR
    subgraph "Hardware Layer"
        TPM[TPM 2.0 Chip<br/>Hardware Root of Trust]
    end
    
    subgraph "Attestation Layer"
        EK[Endorsement Key<br/>Manufacturer Cert]
        AIK[Attestation Identity Key<br/>TPM-Generated]
        QUOTE[TPM Quote<br/>Signed Integrity Proof]
    end
    
    subgraph "Keylime Layer"
        AGENT[Keylime Agent<br/>Collect & Report]
        VERIFIER[Keylime Verifier<br/>Validate Quotes]
        STATUS[Attestation Status<br/>PASS/FAIL]
    end
    
    subgraph "SPIRE Layer"
        PLUGIN[SPIRE Plugin<br/>Keylime Attestor]
        SPIRE[SPIRE Server<br/>Trust Decision]
        SVID[SPIFFE SVID<br/>Workload Identity]
    end
    
    subgraph "Workload Layer"
        WORKLOAD[Workload<br/>Trusted Service]
    end

    TPM -->|Generates| EK
    TPM -->|Generates| AIK
    TPM -->|Signs| QUOTE
    
    EK -->|Validates| AGENT
    AIK -->|Signs| QUOTE
    QUOTE -->|Delivered by| AGENT
    
    AGENT -->|HTTPS/mTLS| VERIFIER
    VERIFIER -->|Validates| STATUS
    
    STATUS -->|PASS| PLUGIN
    PLUGIN -->|Keylime OK| SPIRE
    SPIRE -->|Issues| SVID
    SVID -->|Identity for| WORKLOAD

    style TPM fill:#FF6B6B,stroke:#333,stroke-width:4px
    style STATUS fill:#90EE90,stroke:#333,stroke-width:2px
    style SVID fill:#FFD700,stroke:#333,stroke-width:2px
    style WORKLOAD fill:#87CEEB,stroke:#333,stroke-width:2px
```

---

## PKI Hierarchy

```mermaid
graph TD
    ROOT[Eye of Thundera<br/>Root CA<br/>━━━━━━━━━━━━━<br/>RSA 4096<br/>Valid: 100 years<br/>2026-2126]
    
    subgraph "Intermediate CAs"
        SWORD[Sword of Omens<br/>step-ca<br/>━━━━━━━━━━━━━<br/>YubiKey-backed<br/>Valid: 10 years<br/>ACME, DevID]
        
        BOOK[Book of Omens<br/>OpenBao PKI<br/>━━━━━━━━━━━━━<br/>RSA 4096<br/>Valid: 10 years<br/>pki_int/]
    end
    
    subgraph "Leaf Certificates"
        KA_CERTS[Keylime Agent Certs<br/>━━━━━━━━━━━━━<br/>EC P-256<br/>TTL: 7 days<br/>Role: keylime-services]
        
        INFRA_CERTS[Infrastructure Certs<br/>━━━━━━━━━━━━━<br/>RSA 2048<br/>TTL: 7 days<br/>Role: tower-infrastructure]
        
        SPIRE_CERTS[SPIRE Agent Certs<br/>━━━━━━━━━━━━━<br/>EC P-256<br/>TTL: 7 days<br/>Role: spire-agents]
        
        OB_CERT[OpenBao Server Cert<br/>━━━━━━━━━━━━━<br/>RSA 2048<br/>TTL: 30 days<br/>Role: openbao-server]
    end
    
    ROOT -->|Signs| SWORD
    ROOT -->|Signs| BOOK
    
    BOOK -->|Issues| KA_CERTS
    BOOK -->|Issues| INFRA_CERTS
    BOOK -->|Issues| SPIRE_CERTS
    BOOK -->|Issues| OB_CERT
    
    KA_CERTS -.->|Deployed to| AUTH_HOST[auth.funlab.casa<br/>ca.funlab.casa<br/>spire.funlab.casa]

    style ROOT fill:#FF6B6B,stroke:#333,stroke-width:4px
    style BOOK fill:#DDA0DD,stroke:#333,stroke-width:3px
    style SWORD fill:#87CEEB,stroke:#333,stroke-width:2px
    style KA_CERTS fill:#90EE90,stroke:#333,stroke-width:2px
    style AUTH_HOST fill:#FFD700,stroke:#333,stroke-width:2px
```

---

## Attestation Flow

```mermaid
sequenceDiagram
    participant TPM as TPM 2.0 Chip
    participant KA as Keylime Agent
    participant REG as Keylime Registrar
    participant VER as Keylime Verifier
    participant PLUGIN as SPIRE Plugin
    participant SERVER as SPIRE Server

    Note over TPM,SERVER: 1. Agent Registration
    KA->>TPM: Generate AIK
    TPM-->>KA: AIK Public Key
    KA->>REG: Register Agent<br/>(UUID, EK, AIK)
    REG-->>KA: Registration OK
    
    Note over TPM,SERVER: 2. Initial Attestation
    VER->>KA: Request Quote<br/>(nonce)
    KA->>TPM: Get Quote<br/>(nonce, PCRs)
    TPM-->>KA: Signed Quote
    KA-->>VER: Quote + PCRs
    VER->>VER: Verify Quote<br/>Validate PCRs
    VER-->>VER: Status: PASS
    
    Note over TPM,SERVER: 3. SPIRE Agent Attestation
    PLUGIN->>KA: Get Agent Info<br/>(HTTPS/mTLS)
    KA-->>PLUGIN: Agent UUID, Hash Alg
    PLUGIN->>SERVER: Attestation Request<br/>(UUID, Hash)
    SERVER->>VER: Check Status<br/>(UUID)
    VER-->>SERVER: Status: PASS
    SERVER->>PLUGIN: Challenge<br/>(nonce)
    PLUGIN->>KA: Get Quote<br/>(nonce, HTTPS/mTLS)
    KA->>TPM: Get Quote
    TPM-->>KA: Signed Quote
    KA-->>PLUGIN: Quote
    PLUGIN->>SERVER: Challenge Response<br/>(Quote)
    SERVER->>SERVER: Validate Quote
    SERVER-->>PLUGIN: Attestation OK
    PLUGIN-->>PLUGIN: SVID Issued
    
    Note over TPM,SERVER: 4. Continuous Attestation
    loop Every 2 seconds
        VER->>KA: Request Quote
        KA->>TPM: Get Quote
        TPM-->>KA: Signed Quote
        KA-->>VER: Quote
        VER->>VER: Validate
        VER-->>VER: Status: PASS
    end

    Note over TPM,SERVER: All communication over HTTPS/mTLS
```

---

## Network Topology

```mermaid
graph TB
    subgraph "10.10.2.0/24 Network"
        subgraph "auth.funlab.casa - 10.10.2.70"
            AUTH_9002[":9002 HTTPS<br/>Keylime Agent"]
            AUTH_SPIRE[":8088<br/>SPIRE Agent Health"]
        end
        
        subgraph "ca.funlab.casa - 10.10.2.60"
            CA_9002[":9002 HTTPS<br/>Keylime Agent"]
            CA_SPIRE[":8088<br/>SPIRE Agent Health"]
            CA_443[":443 HTTPS<br/>step-ca ACME"]
        end
        
        subgraph "spire.funlab.casa - 10.10.2.62"
            SPIRE_9002[":9002 HTTPS<br/>Keylime Agent"]
            SPIRE_8081[":8081<br/>SPIRE Server"]
            SPIRE_8881[":8881 TLS<br/>Keylime Verifier"]
            SPIRE_8891[":8891 TLS<br/>Keylime Registrar"]
            SPIRE_8200[":8200 HTTPS<br/>OpenBao API"]
            SPIRE_HEALTH[":8088<br/>SPIRE Agent Health"]
        end
    end
    
    AUTH_9002 -->|HTTPS/mTLS| SPIRE_8881
    AUTH_9002 -->|TLS| SPIRE_8891
    CA_9002 -->|HTTPS/mTLS| SPIRE_8881
    CA_9002 -->|TLS| SPIRE_8891
    SPIRE_9002 -->|HTTPS/mTLS| SPIRE_8881
    SPIRE_9002 -->|TLS| SPIRE_8891
    
    AUTH_SPIRE -->|gRPC| SPIRE_8081
    CA_SPIRE -->|gRPC| SPIRE_8081
    SPIRE_HEALTH -->|gRPC| SPIRE_8081
    
    style AUTH_9002 fill:#90EE90
    style CA_9002 fill:#90EE90
    style SPIRE_9002 fill:#90EE90
    style SPIRE_8881 fill:#FFB6C1
    style SPIRE_8891 fill:#FFB6C1
    style SPIRE_8081 fill:#FFD700
    style SPIRE_8200 fill:#DDA0DD
```

---

## Certificate Issuance Flow

```mermaid
sequenceDiagram
    participant ADMIN as Administrator
    participant BAO as OpenBao PKI
    participant AGENT as Keylime Agent
    participant KA_SVC as Keylime Service

    Note over ADMIN,KA_SVC: Certificate Issuance (7-day TTL)
    
    ADMIN->>BAO: Authenticate<br/>(token)
    BAO-->>ADMIN: Authenticated
    
    ADMIN->>BAO: Issue Certificate<br/>pki_int/issue/keylime-services<br/>CN=agent.keylime.funlab.casa<br/>IP=10.10.2.X
    
    BAO->>BAO: Generate Key Pair<br/>(EC P-256)
    BAO->>BAO: Sign Certificate<br/>(Book of Omens CA)
    BAO->>BAO: Create CA Chain<br/>(Book + Eye)
    
    BAO-->>ADMIN: Certificate Bundle<br/>- certificate (EC P-256)<br/>- private_key<br/>- ca_chain<br/>- serial, expiry
    
    ADMIN->>AGENT: Install Certificate<br/>/etc/keylime/certs/agent.crt
    ADMIN->>AGENT: Install Private Key<br/>/etc/keylime/certs/agent.key<br/>(chmod 640, keylime:spire)
    ADMIN->>AGENT: Install CA Chain<br/>/etc/keylime/certs/ca-complete-chain.crt
    
    ADMIN->>KA_SVC: Restart Service
    KA_SVC->>KA_SVC: Load Certificates
    KA_SVC-->>KA_SVC: mTLS Enabled<br/>Listening on HTTPS:9002
    
    Note over ADMIN,KA_SVC: Renewal Required in 7 Days
```

---

## SPIRE Agent Registration

```mermaid
stateDiagram-v2
    [*] --> Startup: SPIRE Agent Starts
    
    Startup --> LoadConfig: Load agent.conf
    LoadConfig --> LoadPlugin: Load Keylime Plugin
    
    LoadPlugin --> CheckSVID: Check for Existing SVID
    CheckSVID --> Attest: No SVID Found
    CheckSVID --> Running: Valid SVID Found
    
    state Attest {
        [*] --> GetAgentInfo: Query Keylime Agent<br/>(HTTPS/mTLS)
        GetAgentInfo --> SendRequest: Get UUID, Hash Alg
        SendRequest --> ReceiveChallenge: Send to SPIRE Server
        ReceiveChallenge --> GetQuote: Server Returns Nonce
        GetQuote --> SendResponse: Request TPM Quote<br/>(HTTPS/mTLS)
        SendResponse --> ValidateQuote: Submit Quote
        ValidateQuote --> IssueSVID: Server Validates
        IssueSVID --> [*]: SVID Received
    end
    
    Attest --> Running: Attestation Success
    Attest --> Failed: Attestation Failed
    
    Running --> CheckExpiry: Monitor SVID
    CheckExpiry --> ReAttest: SVID Near Expiry
    CheckExpiry --> Running: SVID Valid
    
    ReAttest --> Attest: Re-attestation
    
    Failed --> Retry: Wait & Retry
    Retry --> Attest: Retry Attestation
    
    note right of Attest
        All communication with
        Keylime Agent uses
        HTTPS/mTLS with
        client certificates
    end note
    
    note right of Running
        SVID renewed before
        expiration via
        re-attestation
    end note
```

---

## Component Communication Matrix

| Source | Destination | Protocol | Port | Purpose | Auth Method |
|--------|-------------|----------|------|---------|-------------|
| Keylime Agent | Keylime Verifier | HTTPS | 8881 | Continuous Attestation | mTLS (optional) |
| Keylime Agent | Keylime Registrar | TLS | 8891 | Agent Registration | mTLS (optional) |
| SPIRE Plugin | Keylime Agent | HTTPS | 9002 | Get TPM Quotes | mTLS (client cert) |
| SPIRE Agent | SPIRE Server | gRPC | 8081 | Workload API | SVID-based |
| Administrator | OpenBao | HTTPS | 8200 | PKI Operations | Token-based |
| Workloads | SPIRE Agent | Unix Socket | - | Get SVID | Unix permissions |

---

## Security Layers

```mermaid
graph TB
    subgraph "Layer 1: Hardware"
        TPM[TPM 2.0<br/>━━━━━━━━━━━━━<br/>• Endorsement Key<br/>• Attestation Key<br/>• PCR Measurements<br/>• Secure Storage]
    end
    
    subgraph "Layer 2: Attestation"
        KEYLIME[Keylime<br/>━━━━━━━━━━━━━<br/>• Agent Registration<br/>• Continuous Quotes<br/>• Status: PASS/FAIL<br/>• 2s Interval]
    end
    
    subgraph "Layer 3: Transport"
        TLS[HTTPS/mTLS<br/>━━━━━━━━━━━━━<br/>• Encrypted Channels<br/>• Client Certificates<br/>• Server Validation<br/>• No HTTP]
    end
    
    subgraph "Layer 4: Identity"
        SPIRE_ID[SPIRE<br/>━━━━━━━━━━━━━<br/>• Keylime Attestor<br/>• SPIFFE SVIDs<br/>• Workload Identity<br/>• Trust Domain]
    end
    
    subgraph "Layer 5: PKI"
        PKI[OpenBao PKI<br/>━━━━━━━━━━━━━<br/>• Book of Omens CA<br/>• Short-lived Certs<br/>• Automated Issuance<br/>• 7-day TTL]
    end
    
    TPM -->|Proves Integrity| KEYLIME
    KEYLIME -->|Validates| TLS
    TLS -->|Secures| SPIRE_ID
    PKI -->|Certificates for| TLS
    KEYLIME -->|Gates| SPIRE_ID
    
    style TPM fill:#FF6B6B,stroke:#333,stroke-width:3px
    style KEYLIME fill:#FFB6C1,stroke:#333,stroke-width:3px
    style TLS fill:#90EE90,stroke:#333,stroke-width:3px
    style SPIRE_ID fill:#FFD700,stroke:#333,stroke-width:3px
    style PKI fill:#DDA0DD,stroke:#333,stroke-width:3px
```

---

## Legend

### Color Coding
- 🔴 **Red**: Hardware components (TPM, Root CA)
- 🟢 **Green**: Keylime agents (attesting nodes)
- 🔵 **Blue**: SPIRE agents (identity consumers)
- 🟡 **Yellow**: SPIRE server (trust authority)
- 🟣 **Purple**: OpenBao/PKI (certificate authority)
- 🌸 **Pink**: Keylime infrastructure (verifier/registrar)

### Communication Patterns
- **Solid Lines**: Active data flow
- **Dashed Lines**: Deployment/configuration
- **Thick Lines**: Critical trust path

### Status Indicators
- ✅ Active/Operational
- ⚠️ Warning/Attention needed
- ❌ Failed/Inactive
- 🔄 Continuous/Recurring

---

**Document Version:** 1.0  
**Last Updated:** 2026-02-10  
**Maintained By:** Infrastructure Team
