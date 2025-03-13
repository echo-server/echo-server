# Echo Server

这是一个基于OpenResty的HTTP回显服务器，用于显示HTTP请求的详细信息。

## 项目背景

在开发和调试网络应用时，了解HTTP请求的详细信息非常重要。Echo Server提供了一个简单的方式来查看请求头、请求体、环境变量等信息，帮助开发人员诊断问题和理解请求流程。

## 主要功能

- 显示请求的详细信息，包括：
  - 请求方法（GET、POST等）
  - 请求路径
  - 查询参数
  - 请求头
  - 请求体
  - 客户端IP地址
- 显示服务器环境信息，包括：
  - 主机名
  - Pod信息（如果在Kubernetes环境中运行）
  - Nginx和Lua版本
- 提供长连接测试端点（/hang）

## 安装与部署

### 使用Docker

#### 方法一：使用预编译镜像（推荐）

```bash
docker run -p 8080:80 ghcr.io/echo-server/echo-server:main
```

预编译镜像同时支持ARM和x86两种CPU架构，无需自行构建。

#### 方法二：本地构建

1. 克隆仓库

```bash
git clone https://github.com/echo-server/echo-server.git
cd echo-server
```

2. 构建Docker镜像

```bash
docker build -t echo-server .
```

3. 运行容器

```bash
docker run -p 8080:80 echo-server
```

现在，Echo Server将在 http://localhost:8080 上运行。

## 使用方式

### 基本用法

访问服务器的根路径来查看请求信息：

```bash
curl http://localhost:8080
```

或者使用浏览器访问 http://localhost:8080

### 发送不同类型的请求

#### POST请求示例

```bash
curl -X POST -d "Hello World" http://localhost:8080
```

#### 带自定义头的请求

```bash
curl -H "X-Custom-Header: CustomValue" http://localhost:8080
```

### 长连接测试

```bash
curl http://localhost:8080/hang
```

这个端点会保持连接打开，每5秒发送一个换行符。

## 在Kubernetes中使用

Echo Server可以在Kubernetes集群中部署，它会自动显示Pod相关信息（如果环境变量可用）。

使用预编译镜像：
```bash
ghcr.io/echo-server/echo-server:main
```

部署示例：
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

这些环境变量将被回显服务器显示，有助于调试和了解Pod的运行环境。

## 技术栈

- [OpenResty](https://openresty.org/): 基于Nginx和Lua的高性能Web平台
- [lua-resty-template](https://github.com/bungle/lua-resty-template): Lua模板引擎

## 贡献

欢迎提交问题和拉取请求！

## 许可证

请查看项目中的LICENSE文件。