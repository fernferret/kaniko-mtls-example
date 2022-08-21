# About

This repo contains an example of how to use
[`caddy`](https://github.com/caddyserver/caddy) to enforce mutual TLS (mTLS)
authentication on a docker registry.

It exists mainly to help me test kaniko's ability to push to mTLS repositories.

## Prerequisites

You'll need a copy of `caddy` from https://caddyserver.com/download and
`openssl`.

## Security

This repo generates some example certificates for you. These are **not
to be used in production environments and are only for testing**.

## Testing Kaniko with mTLS

This process is a bit involved so go ahead and read through all the steps.
Someday it might be nice to have these as integration tests.

### 1. DNS Setup

Kaniko has [several short-circuits to not use TLS when a registry on a local
network is
detected](https://github.com/google/go-containerregistry/blob/main/pkg/name/registry.go#L74-L95),
so we'll need to assign a **non-local** dns name to our local IP, I chose
`soapshop.example.com`.

With that setup you should be able to perform a quick lookup on your host:

```console
$ nslookup soapshop.example.com
Server:   192.168.1.10
Address:  192.168.1.10#53

Name: soapshop.example.com
Address: 192.168.1.50
```

### 2. Generate some test certificates

First, generate some test certs:

```console
./make_certs.sh soapshop.example.com
```

### 3. Start the docker registry

In another terminal, start a docker registry

NOTE: I'm on a Mac, so there's a port conflict with port 5000, so I bound it to 5001

```console
docker run --rm --name registry -it -p 5001:5000 registry:2
```

Verify the registry is up on `http://127.0.0.1:5001/v2/`, you should see the
output of `{}`

```console
$ curl http://localhost:5001/v2/
{}
```

### 4. Start TLS reverse proxy (`caddy`)

Start `caddy` using:

```console
REGISTRY=soapshop.example.com REG_INT_PORT=5001 REG_EXT_PORT=9444 caddy run
```

Now test to make sure we're protected with mTLS

```console
$ curl --cacert ./certs/ca.pem https://soapshop.example.com:9444/v2/
curl: (55) LibreSSL SSL_write: error:02FFF020:system library:func(4095):Broken pipe, errno 32
```

Excellent, now add client certs for mTLS, we should see the same thing that we
did above, just `{}`

```console
$ curl --cacert ./certs/ca.pem --cert ./certs/client.pem --key ./certs/client.key https://soapshop.example.com:9444/v2/
{}
```

### 5. Build/Push the example container

To tie it all together, we can now push the `example` dockerfile provided with
this repo using a copy of kaniko [built with
mTLS](https://github.com/GoogleContainerTools/kaniko/pull/2180) support and our
example certs:

```
docker run -it --rm -v $(pwd)/certs:/certs -v $(pwd)/example:/workspace kaniko-debug \
  --destination soapshop.example.com:9444/example/kaniko-example:latest \
  --registry-certificate soapshop.example.com:9444=/certs/ca.pem \
  --registry-client-cert soapshop.example.com:9444=/certs/client.pem,/certs/client.key
```