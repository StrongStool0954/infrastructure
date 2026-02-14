# Full access to PKI
path "pki_int/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Full access to secrets
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Full access to cubbyhole
path "cubbyhole/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Read system mounts
path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/mounts/*" {
  capabilities = ["read", "list"]
}

# Read auth methods
path "sys/auth" {
  capabilities = ["read", "list"]
}

path "sys/auth/*" {
  capabilities = ["read", "list"]
}

# Read policies
path "sys/policies/*" {
  capabilities = ["read", "list"]
}

# Read system health
path "sys/health" {
  capabilities = ["read"]
}

# Full access to database credentials
path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
