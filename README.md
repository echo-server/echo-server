# Echo Server

This is an HTTP echo server based on OpenResty, designed to display detailed information about HTTP requests.

## Project Background

When developing and debugging network applications, understanding the details of HTTP requests is crucial. Echo Server provides a simple way to view request headers, request body, environment variables, and other information, helping developers diagnose problems and understand request flows.

## Main Features

- Display detailed request information, including:
  - Request method (GET, POST, etc.)
  - Request path
  - Query parameters
  - Request headers
  - Request body
  - Client IP address
- Display server environment information, including:
  - Hostname
  - Pod information (if running in a Kubernetes environment)
  - Nginx and Lua versions
- Provide a long connection test endpoint (/hang)

## Installation and Deployment

### Using Docker

#### Method 1: Using Pre-built Image (Recommended)

```bash
docker run -p 8080:80 ghcr.io/echo-server/echo-server:main
```

The pre-built image supports both ARM and x86 CPU architectures, no need to build it yourself.

#### Method 2: Local Build

1. Clone the repository

```bash
git clone https://github.com/echo-server/echo-server.git
cd echo-server
```

2. Build the Docker image

```bash
docker build -t echo-server .
```

3. Run the container

```bash
docker run -p 8080:80 echo-server
```

Now, Echo Server will be running at http://localhost:8080.

## Usage

### Basic Usage

Access the server's root path to view request information:

```bash
curl http://localhost:8080
```

Or use a browser to visit http://localhost:8080

### Sending Different Types of Requests

#### POST Request Example

```bash
curl -X POST -d "Hello World" http://localhost:8080
```

#### Request with Custom Headers

```bash
curl -H "X-Custom-Header: CustomValue" http://localhost:8080
```

### Long Connection Test

```bash
curl http://localhost:8080/hang
```

This endpoint keeps the connection open, sending a newline character every 5 seconds.

## Using in Kubernetes

Echo Server can be deployed in a Kubernetes cluster, and it will automatically display Pod-related information (if environment variables are available).

Using pre-built image:
```bash
ghcr.io/echo-server/echo-server:main
```

Deployment example:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      containers:
      - name: echo-server
        image: ghcr.io/echo-server/echo-server:main
        ports:
        - containerPort: 80
        env:
        - name: HOSTNAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
---
apiVersion: v1
kind: Service
metadata:
  name: echo-server
spec:
  selector:
    app: echo-server
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

These environment variables will be displayed by the echo server, helping to debug and understand the Pod's runtime environment.

## Technology Stack

- [OpenResty](https://openresty.org/): A high-performance web platform based on Nginx and Lua
- [lua-resty-template](https://github.com/bungle/lua-resty-template): Lua template engine

## Contribution

Issues and pull requests are welcome!

## License

Please see the LICENSE file in the project.