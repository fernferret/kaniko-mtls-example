#!/bin/bash

# About:
#   This is a simple script to help automate testing of mTLS server/client
#   software. It generates:
#   * A Certificate Authority (ca.key/ca.pem)
#   * A Server Certificate (server.key/server.pem) (optionally with an extra DNS
#     name(s) and/or IP(s) if passed into this script)
#   * A Client Certificate (client.key/client.pem)
#
# Usage:
#   # If you just want server to be accessible over localhost/127.0.0.1:
#   ./make_certs.sh 
#
#   # If you just want server to be accessible over another dns name like
#   # foo.example.com. This is needed for my kaniko testing, as kaniko
#   # short-circuits "local" domains/IP addrs to ignore TLS. I want to
#   # explicitly use TLS on local connections for testing. It short-circuits
#   # IP/domains such as: 127.0.0.1, 192.168.*.*, 10.*.*.*, *.local so I had
#   # to setup foo.example.com as a local DNS entry.
#   #
#   # With all of that said, this script will allow a comma split list of DNS
#   # names and IP. They waill all be added as SANs, here's what it looks like:
#   ./make_certs.sh foo.example.com,192.168.1.50

mkdir -p certs
cd certs

# Create the extensions file for the server.pem file. This is what adds the
# Subject Alternative Names (SANs) to the cert.
cat << EOF > ./domains.ext 
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
IP.1 = 127.0.0.1
DNS.1 = localhost
DNS.2 = localhost.local
EOF

# If there were any args specied, they should be in a comma split format, like:
# foo.example.com,192.168.1.50,foo
# Loop through these and see if each one is an IP address or DNS name, then add
# them as SANs to the `domains.ext` file that we created above.
if [ "$1" != "" ]; then
  dns_count=3
  ip_count=2

  items=$(echo $1 | tr "," "\n")

  for item in $items
  do
    if [[ $item =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo -e "IP.${ip_count} = $item" >> domains.ext
      ip_count=$((ip_count+1))
    else
      echo -e "DNS.${dns_count} = $item" >> domains.ext
      dns_count=$((dns_count+1))
    fi
  done
fi

# Generate the certificate authority with a key and a self-signed certificate
echo "==> Make ca.key / ca.pem"
openssl req -subj '/C=US/O=ACME Inc./CN=Example CA Root 1' -new -newkey rsa:2048 -sha256 -days 3650 -nodes -x509 -keyout ca.key -out ca.pem

# Create the server's private key and certificate signing request (CSR)
echo "==> Make server.key / server.csr"
openssl req -new -nodes -newkey rsa:2048 -keyout server.key -out server.csr -subj "/C=US/O=Soap Inc./CN=${1-localhost.local}"

# Sign the server's certificate using the certificate authority created above
# and the extension file to add in the SANs
echo "==> Make server.pem"
openssl x509 -req -sha256 -days 365 -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -extfile domains.ext -out server.pem

# Create the client's private key and certificate signing request (CSR)
echo "==> Make client.key / client.csr"
openssl req -new -nodes -newkey rsa:2048 -keyout client.key -out client.csr -subj "/C=US/O=Soap Inc./OU=Sales/CN=Tyler Durden/emailAddress=durden.tyler@soapinc.example.com"

# Sign the client's certificate using the certificate authority created above
echo "==> Make client.pem"
openssl x509 -req -sha256 -days 365 -in client.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out client.pem