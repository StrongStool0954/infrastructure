{
  "subject": {
    "commonName": {{ toJson .Subject.CommonName }},
    "organization": ["Funlab.Casa"],
    "organizationalUnit": ["OIDC Users"]
  },
  "sans": {{ toJson .SANs }},
  {{- if .Token.email }}
  "emailAddresses": [{{ toJson .Token.email }}],
  {{- end }}
  "keyUsage": ["digitalSignature", "keyEncipherment"],
  "extKeyUsage": ["clientAuth", "emailProtection"]
}
