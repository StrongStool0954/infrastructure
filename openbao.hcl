# OpenBao Configuration for spire.funlab.casa
# Integrated Storage (Raft) - HA-ready, no external dependencies

ui = true

# Integrated Storage backend (Raft consensus)
storage "raft" {
  path    = "/var/lib/openbao/data"
  node_id = "spire-node-1"
  
  # Performance tuning
  performance_multiplier = 1
}

# HTTPS listener on all interfaces
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/opt/openbao/tls/tls.crt"
  tls_key_file  = "/opt/openbao/tls/tls.key"
  
  # Security settings
  tls_min_version = "tls12"
}

# API address for cluster communication
api_addr = "https://spire.funlab.casa:8200"
cluster_addr = "https://spire.funlab.casa:8201"

# Disable mlock for development/testing
# TODO: Enable in production with proper capabilities
disable_mlock = true

# Telemetry (optional)
telemetry {
  disable_hostname = false
  prometheus_retention_time = "30s"
}

# Log level
log_level = "info"
